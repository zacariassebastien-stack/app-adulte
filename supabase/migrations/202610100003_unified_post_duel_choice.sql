-- Unify the final loser's post-duel choice without changing the persisted
-- corruption protocol introduced by 202610100002.

create or replace function public.network_round_json(
  p_round_id uuid,
  p_requester uuid
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'schema_version',1,'round_id',r.id,'session_id',r.session_id,
    'session_round',r.round_key,'round_number',r.round_number,'phase',r.phase,
    'player_id',p_requester,'action_points',g.action_points,
    'hybrid_orientation',g.hybrid_orientation,'deck_cycle',g.deck_cycle,
    'v4_unlocked_spice',g.v4_unlocked_spice,
    'infinite_mode',g.infinite_mode,'deck_style',g.deck_style,
    'deck_adjustment',g.deck_adjustment,'cycle_exhausted',g.cycle_exhausted,
    'action_projection',r.v4_action_projection,
    'clothing_counts',coalesce((select jsonb_object_agg(
      p.user_id::text,p.v4_clothing_count) from public.session_players p
      where p.session_id=r.session_id and p.v4_clothing_count is not null),'{}'::jsonb),
    'clothing_resynced',r.v4_clothing_resynced,
    'commits',coalesce((select jsonb_object_agg(c.player_id::text,c.digest)
      from public.network_round_commits c where c.round_id=r.id),'{}'::jsonb),
    'own_reveal',(select jsonb_build_object('schema_version',1,
      'session_round',r.round_key,'player_id',v.player_id,'choice',v.choice_payload,'nonce',v.nonce)
      from public.network_round_reveals v where v.round_id=r.id and v.player_id=p_requester),
    'opponent_reveal',null,
    'initial_resolution',case when r.initial_resolution is null then null
      else r.initial_resolution-'gap'-'gap_cost'-'high_value' end,
    'negotiation',public.v4_public_negotiation(
      r.negotiation,
      p_requester::text=coalesce(
        r.negotiation->>'offered_by',
        r.initial_resolution->>'loser_player_id'
      )
    ),
    'counter_bid',r.counter_bid,'final_defense',r.final_defense,
    'final_resolution',case when r.final_resolution is null then null else
      jsonb_set(r.final_resolution,'{compromise}',
        public.v4_public_compromise_cards(r.final_resolution->'compromise'),true)
      end,
    'ready_next',r.ready_next,
    'tie_decisions',r.tie_decisions,'corruption',r.corruption,
    'recovery_by_player',r.recovery_by_player,'recovery_done',r.recovery_done,
    'recovery_history',r.recovery_history
  ) from public.network_rounds r join public.network_game_states g on g.session_id=r.session_id
  where r.id=p_round_id;
$$;

create or replace function public.submit_network_negotiation_proposal(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,
  p_offer jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_available integer;
  v_direct integer;
  v_unlocked_spice integer;
  v_compromise jsonb;
  v_winner uuid;
  v_loser uuid;
  v_choice jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands
  where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id
      or v_command.kind<>'NEGOTIATION_PROPOSAL'
      or v_command.command_payload is distinct from p_offer then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds
  where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase not in ('CORRUPTION_DECISION','NEGOTIATION_PROPOSAL') then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  if v_round.phase='CORRUPTION_DECISION' then
    v_winner:=coalesce(
      (v_round.final_resolution->>'final_winner_player_id')::uuid,
      (v_round.final_resolution->>'retained_player_id')::uuid
    );
    select user_id into v_loser from public.session_players
    where session_id=p_session_id and user_id<>v_winner;
  else
    -- Compatibility for a negotiation persisted before this migration.
    v_winner:=(v_round.initial_resolution->>'winner_player_id')::uuid;
    v_loser:=(v_round.initial_resolution->>'loser_player_id')::uuid;
  end if;
  if p_player_id is distinct from v_loser then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  if jsonb_typeof(p_offer)<>'object'
    or jsonb_typeof(p_offer->'cards')<>'array'
    or coalesce((p_offer->>'direct_pa')::integer,-1)<0
    or jsonb_typeof(p_offer->'inversion_requested') is distinct from 'boolean'
    or (
      not (p_offer->>'inversion_requested')::boolean
      and (p_offer->>'direct_pa')::integer=0
      and jsonb_array_length(p_offer->'cards')=0
    ) then
    raise exception 'ROUND_NEGOTIATION_INVALID';
  end if;
  v_direct:=(p_offer->>'direct_pa')::integer;
  select (action_points->>p_player_id::text)::integer,v4_unlocked_spice
  into v_available,v_unlocked_spice
  from public.network_game_states
  where session_id=p_session_id for update;
  if v_direct>v_available then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
  if v_available<10 and v_direct>0 then raise exception 'ROUND_INVALID_BID'; end if;
  if (p_offer->>'inversion_requested')::boolean then
    select choice_payload into v_choice from public.network_round_reveals
    where round_id=p_round_id and player_id=v_loser;
    if not found
      or coalesce(v_choice#>>'{parameters,role}','GENERAL') not in ('FAIRE','RECEVOIR')
      or coalesce(v_choice#>>'{parameters,opposite_personal_value}','') !~ '^[0-9]+$'
      or (v_choice#>>'{parameters,opposite_personal_value}')::integer not between 1 and 20 then
      raise exception 'ROUND_INVERSION_FORBIDDEN';
    end if;
  end if;
  if (select count(*) from jsonb_array_elements(p_offer->'cards')) <>
     (select count(distinct x->>'occurrence_id')
      from jsonb_array_elements(p_offer->'cards') x) then
    raise exception 'ROUND_AUCTION_CARD_REUSED';
  end if;
  if exists(
    select 1 from jsonb_array_elements(p_offer->'cards') x where
      x->>'owner_player_id'<>p_player_id::text or x->>'origin'<>'AUCTION'
      or x->>'native_direction'<>x->>'effective_direction'
      or (x->>'snapshot_value')::integer not between 1 and 20
  ) then
    raise exception 'ROUND_NEGOTIATION_INVALID';
  end if;
  if jsonb_array_length(p_offer->'cards')>0 then
    v_compromise:=public.v4_corruption_compromise(
      p_session_id,v_round.round_number,p_player_id,p_offer->'cards'
    );
    if v_unlocked_spice is null or exists(
      select 1 from jsonb_array_elements(v_compromise) card
      where (card->>'effective_spice')::integer>v_unlocked_spice
    ) then
      raise exception 'ROUND_NEGOTIATION_INVALID';
    end if;
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(
    p_command_id,p_session_id,p_round_id,p_player_id,
    'NEGOTIATION_PROPOSAL',p_offer
  );
  update public.network_rounds set negotiation=jsonb_build_object(
    'offered_by',p_player_id,
    'proposal',p_offer,
    'response',null,
    'final_offer',null
  ),phase='NEGOTIATION_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

create or replace function public.respond_network_negotiation(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,
  p_response jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_offer jsonb;
  v_points jsonb;
  v_winner uuid;
  v_loser uuid;
  v_accepted boolean;
  v_spend integer;
  v_current integer;
  v_inverted boolean;
  v_choice jsonb;
  v_initial_card jsonb;
  v_cards jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if jsonb_typeof(p_response->'accepted') is distinct from 'boolean' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_accepted:=(p_response->>'accepted')::boolean;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands
  where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id
      or v_command.kind<>'NEGOTIATION_RESPONSE'
      or v_command.command_payload is distinct from p_response then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds
  where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase<>'NEGOTIATION_RESPONSE' then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  v_offer:=v_round.negotiation->'proposal';
  v_loser:=coalesce(
    (v_round.negotiation->>'offered_by')::uuid,
    (v_round.initial_resolution->>'loser_player_id')::uuid
  );
  select user_id into v_winner from public.session_players
  where session_id=p_session_id and user_id<>v_loser;
  if p_player_id is distinct from v_winner then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  if jsonb_typeof(v_offer)<>'object' then
    raise exception 'ROUND_NEGOTIATION_INVALID';
  end if;
  v_inverted:=v_accepted and (v_offer->>'inversion_requested')::boolean;

  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(
    p_command_id,p_session_id,p_round_id,p_player_id,
    'NEGOTIATION_RESPONSE',p_response
  );

  if not v_accepted then
    update public.network_rounds set negotiation=jsonb_set(
      jsonb_set(negotiation,'{response}',p_response,true),
      '{final_offer}','null'::jsonb,true
    ),phase='FINAL_RESOLVED',updated_at=now() where id=p_round_id;
    return public.network_round_json(p_round_id,p_player_id);
  end if;

  select choice_payload into v_choice from public.network_round_reveals
  where round_id=p_round_id and player_id=v_loser;
  if not found then raise exception 'ROUND_REVEAL_MISSING'; end if;
  if coalesce(v_choice#>>'{parameters,native_direction}',
      v_choice#>>'{parameters,role}','GENERAL') <>
     coalesce(v_choice#>>'{parameters,role}','GENERAL')
    or coalesce(v_choice#>>'{parameters,effective_direction}',
      v_choice#>>'{parameters,role}','GENERAL') <>
     coalesce(v_choice#>>'{parameters,role}','GENERAL') then
    raise exception 'ROUND_DIRECTION_MISMATCH';
  end if;
  if v_inverted and (
    coalesce(v_choice#>>'{parameters,role}','GENERAL') not in ('FAIRE','RECEVOIR')
    or coalesce(v_choice#>>'{parameters,opposite_personal_value}','') !~ '^[0-9]+$'
    or (v_choice#>>'{parameters,opposite_personal_value}')::integer not between 1 and 20
  ) then
    raise exception 'ROUND_INVERSION_UNAVAILABLE';
  end if;
  select jsonb_build_object(
    'occurrence_id',coalesce(
      v_choice#>>'{parameters,occurrence_id}',
      p_round_id::text||':initial:'||v_loser::text
    ),
    'card_id',v_choice->>'card_id',
    'variant_id',v_choice->>'variant_id',
    'owner_player_id',v_loser,
    'native_direction',coalesce(
      v_choice#>>'{parameters,native_direction}',
      v_choice#>>'{parameters,role}','GENERAL'
    ),
    'effective_direction',case coalesce(
      v_choice#>>'{parameters,effective_direction}',
      v_choice#>>'{parameters,role}','GENERAL'
    )
      when 'FAIRE' then case when v_inverted then 'RECEVOIR' else 'FAIRE' end
      when 'RECEVOIR' then case when v_inverted then 'FAIRE' else 'RECEVOIR' end
      else coalesce(v_choice#>>'{parameters,effective_direction}',
        v_choice#>>'{parameters,role}','GENERAL')
    end,
    'origin','INITIAL_DUEL',
    'snapshot_value',case when v_inverted
      then (v_choice#>>'{parameters,opposite_personal_value}')::integer
      else (v_choice#>>'{parameters,personal_value}')::integer end,
    'logical_order',0
  ) into v_initial_card;
  v_cards:=jsonb_build_array(v_initial_card)||coalesce(v_offer->'cards','[]'::jsonb);

  select action_points into v_points from public.network_game_states
  where session_id=p_session_id for update;
  v_spend:=(v_offer->>'direct_pa')::integer
    + case when v_inverted
      then (v_round.initial_resolution->>'high_value')::integer else 0 end;
  v_current:=(v_points->>v_loser::text)::integer;
  if v_spend>v_current then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
  v_points:=jsonb_set(
    v_points,array[v_loser::text],to_jsonb(v_current-v_spend)
  );
  update public.network_game_states set action_points=v_points,updated_at=now()
  where session_id=p_session_id;
  update public.network_rounds set
    negotiation=jsonb_set(
      jsonb_set(negotiation,'{response}',p_response,true),
      '{final_offer}',v_offer,true
    ),
    final_resolution=jsonb_build_object(
      'retained_player_id',v_loser,
      'initial_winner_player_id',coalesce(
        v_round.final_resolution->>'initial_winner_player_id',
        v_round.initial_resolution->>'winner_player_id'
      ),
      'final_winner_player_id',v_loser,
      'card_id',v_initial_card->>'card_id',
      'variant_id',v_initial_card->>'variant_id',
      'inverted',v_inverted,
      'mutual_abandon',false,
      'compromise',v_cards
    ),
    phase='FINAL_RESOLVED',updated_at=now()
  where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

create or replace function public.route_network_post_duel() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  -- New rounds go through the existing counter/final-defense duel first.
  if old.phase='READY' and new.phase='NEGOTIATION_PROPOSAL' then
    new.phase:='COUNTER_DECISION';
  elsif new.phase='FINAL_RESOLVED' and old.phase in (
    'COUNTER_DECISION','FINAL_DEFENSE_DECISION','TIE_DECISION'
  ) then
    new.phase:=case when new.final_resolution->>'retained_player_id' is null
      then 'RECOVERY' else 'CORRUPTION_DECISION' end;
  end if;
  -- A negotiation response deliberately remains FINAL_RESOLVED: choosing the
  -- compromise path consumes the unique post-duel choice.
  return new;
end;
$$;

revoke all on function public.submit_network_negotiation_proposal(
  uuid,uuid,uuid,jsonb,text
) from public;
revoke all on function public.respond_network_negotiation(
  uuid,uuid,uuid,jsonb,text
) from public;
grant execute on function public.submit_network_negotiation_proposal(
  uuid,uuid,uuid,jsonb,text
) to authenticated;
grant execute on function public.respond_network_negotiation(
  uuid,uuid,uuid,jsonb,text
) to authenticated;
