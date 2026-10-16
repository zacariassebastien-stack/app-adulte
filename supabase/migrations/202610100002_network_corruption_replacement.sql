-- Corruption is decided before action execution. The final loser can offer a
-- whole batch of previously played discard occurrences. Refusal resumes the
-- original final action; acceptance replaces it without changing PA.

alter table public.network_game_states
  add column if not exists v4_unlocked_spice integer not null default 1
    check (v4_unlocked_spice between 1 and 4);

alter table public.network_round_commands
  drop constraint network_round_commands_kind_check;
alter table public.network_round_commands
  add constraint network_round_commands_kind_check check (kind in (
    'CREATE','OPEN','COMMIT','CANCEL_COMMIT','REVEAL','INITIAL_RESOLVE',
    'NEGOTIATION_PROPOSAL','NEGOTIATION_RESPONSE','NEGOTIATION_ADAPTATION',
    'NEGOTIATION_VALIDATION','SET_ORIENTATION','CONTINUE_CYCLE',
    'COUNTER_DECISION','FINAL_DEFENSE','TIE_DECISION','READY_NEXT',
    'CORRUPTION_OFFER','CORRUPTION_RESPONSE','CORRUPTION_RESOLVE',
    'CORRUPTION_SKIP','RECOVERY','RECOVERY_RESPONSE','RECOVERY_RESOLVE',
    'RECOVERY_SKIP','CLOSE_SESSION','REPAIR_V4_ACTION_PARAMETERS',
    'PUBLISH_V4_ACTION','PUBLISH_V4_SPICE'
  ));

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
      p_requester::text=r.initial_resolution->>'loser_player_id'
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

create or replace function public.publish_network_v4_unlocked_spice(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_unlocked_spice integer,
  p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_current integer;
  v_cycle_actor uuid;
  v_payload jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if p_unlocked_spice not between 1 and 4 then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_payload:=jsonb_build_object('unlocked_spice',p_unlocked_spice);
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands
  where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'PUBLISH_V4_SPICE'
      or v_command.command_payload is distinct from v_payload then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds
  where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase<>'WAITING_NEXT' then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  select user_id into v_cycle_actor from public.session_players
  where session_id=p_session_id and role='PLAYER_1';
  if p_player_id is distinct from v_cycle_actor then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  if exists(
    select 1 from public.session_players participant
    where participant.session_id=p_session_id
      and not (v_round.ready_next ? participant.user_id::text)
  ) then
    raise exception 'ROUND_NOT_READY';
  end if;
  select v4_unlocked_spice into v_current
  from public.network_game_states
  where session_id=p_session_id for update;
  if not found then raise exception 'ROUND_NOT_FOUND'; end if;
  if p_unlocked_spice<>v_current+1 then
    raise exception 'ROUND_INVALID_SPICE_PROGRESSION';
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(
    p_command_id,p_session_id,p_round_id,p_player_id,
    'PUBLISH_V4_SPICE',v_payload
  );
  update public.network_game_states
  set v4_unlocked_spice=p_unlocked_spice,updated_at=now()
  where session_id=p_session_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

revoke all on function public.publish_network_v4_unlocked_spice(
  uuid,uuid,uuid,integer,text
) from public;
grant execute on function public.publish_network_v4_unlocked_spice(
  uuid,uuid,uuid,integer,text
) to authenticated;

create or replace function public.v4_corruption_compromise(
  p_session_id uuid,
  p_round_number integer,
  p_player_id uuid,
  p_actions jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_proposed record;
  v_choice jsonb;
  v_resolved_action jsonb;
  v_parameters jsonb;
  v_effective_spice jsonb;
  v_native_direction text;
  v_effective_direction text;
  v_result jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions)=0 then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  for v_proposed in
    select value, ordinality
    from jsonb_array_elements(p_actions) with ordinality
  loop
    v_choice:=null;
    v_resolved_action:=null;
    -- A compromise/corruption argument must be a server-verifiable discard:
    -- it was exposed in a completed earlier round and has not subsequently
    -- been exhausted by an executed corruption or Recovery action.
    if not exists(
      select 1
      from public.network_rounds previous
      where previous.session_id=p_session_id
        and previous.round_number<p_round_number
        and (
          exists(
            select 1 from public.network_round_reveals reveal
            where reveal.round_id=previous.id
              and reveal.player_id=p_player_id
              and coalesce(
                reveal.choice_payload#>>'{parameters,occurrence_id}',
                reveal.choice_payload->>'card_id'
              )=v_proposed.value->>'occurrence_id'
              and reveal.choice_payload->>'card_id'=
                v_proposed.value->>'card_id'
          ) or exists(
            select 1
            from jsonb_array_elements(coalesce(
              previous.final_resolution->'compromise','[]'::jsonb
            )) action
            where action->>'owner_player_id'=p_player_id::text
              and action->>'occurrence_id'=
                v_proposed.value->>'occurrence_id'
              and action->>'card_id'=v_proposed.value->>'card_id'
          )
        )
    ) or exists(
      select 1
      from public.network_rounds previous
      where previous.session_id=p_session_id
        and previous.round_number<p_round_number
        and (
          exists(
            select 1 from jsonb_array_elements(coalesce(
              previous.corruption->'actions','[]'::jsonb
            )) action
            where previous.corruption->>'offered_by'=p_player_id::text
              and action->>'occurrence_id'=
                v_proposed.value->>'occurrence_id'
              and action->>'status'='COMPLETED'
          ) or exists(
            select 1 from jsonb_array_elements(coalesce(
              previous.recovery_history,'[]'::jsonb
            )) recovery
            where recovery->>'player_id'=p_player_id::text
              and recovery->>'occurrence_id'=
                v_proposed.value->>'occurrence_id'
              and (recovery->>'completed')::boolean
          )
        )
    ) then
      raise exception 'ROUND_CORRUPTION_FORBIDDEN';
    end if;
    select reveal.choice_payload into v_choice
    from public.network_round_reveals reveal
    join public.network_rounds previous on previous.id=reveal.round_id
    where previous.session_id=p_session_id
      and previous.round_number<p_round_number
      and reveal.player_id=p_player_id
      and coalesce(
        reveal.choice_payload#>>'{parameters,occurrence_id}',
        reveal.choice_payload->>'card_id'
      )=v_proposed.value->>'occurrence_id'
    order by previous.round_number desc
    limit 1;
    if not found then
      select action into v_resolved_action
      from public.network_rounds previous,
        jsonb_array_elements(coalesce(
          previous.final_resolution->'compromise','[]'::jsonb
        )) action
      where previous.session_id=p_session_id
        and previous.round_number<p_round_number
        and action->>'owner_player_id'=p_player_id::text
        and action->>'occurrence_id'=v_proposed.value->>'occurrence_id'
      order by previous.round_number desc
      limit 1;
      if not found
        or v_resolved_action->>'card_id' is distinct from
          v_proposed.value->>'card_id' then
        raise exception 'ROUND_CORRUPTION_FORBIDDEN';
      end if;
      v_choice:=jsonb_build_object(
        'card_id',v_resolved_action->>'card_id',
        'variant_id',v_resolved_action->>'variant_id',
        'parameters',jsonb_build_object(
          'resolved_parameters',v_resolved_action->'resolved_parameters',
          'effective_spice',v_resolved_action->'effective_spice',
          'native_direction',v_resolved_action->>'native_direction',
          'effective_direction',v_resolved_action->>'effective_direction'
        )
      );
    elsif v_choice->>'card_id' is distinct from
      v_proposed.value->>'card_id' then
      raise exception 'ROUND_CORRUPTION_FORBIDDEN';
    end if;
    v_parameters:=v_choice#>'{parameters,resolved_parameters}';
    v_effective_spice:=v_choice#>'{parameters,effective_spice}';
    if jsonb_typeof(v_parameters)<>'object'
      or jsonb_typeof(v_effective_spice)<>'number' then
      raise exception 'ROUND_ACTION_PARAMETERS_MISSING';
    end if;
    v_native_direction:=coalesce(
      v_choice#>>'{parameters,native_direction}',
      v_choice#>>'{parameters,role}',
      'GENERAL'
    );
    v_effective_direction:=coalesce(
      v_choice#>>'{parameters,effective_direction}',
      v_choice#>>'{parameters,role}',
      'GENERAL'
    );
    v_result:=v_result||jsonb_build_array(jsonb_build_object(
      'occurrence_id',v_proposed.value->>'occurrence_id',
      'card_id',v_choice->>'card_id',
      'variant_id',v_choice->>'variant_id',
      'owner_player_id',p_player_id,
      'native_direction',v_native_direction,
      'effective_direction',v_effective_direction,
      'origin','CORRUPTION',
      'snapshot_value',0,
      'logical_order',v_proposed.ordinality-1,
      'resolved_parameters',v_parameters,
      'effective_spice',v_effective_spice
    ));
  end loop;
  return v_result;
end;
$$;

revoke all on function public.v4_corruption_compromise(
  uuid,integer,uuid,jsonb
) from public, authenticated;

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
  if v_round.phase<>'NEGOTIATION_PROPOSAL' then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  if p_player_id::text<>v_round.initial_resolution->>'loser_player_id' then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  if jsonb_typeof(p_offer)<>'object'
    or jsonb_typeof(p_offer->'cards')<>'array'
    or (p_offer->>'direct_pa')::integer<0 then
    raise exception 'ROUND_NEGOTIATION_INVALID';
  end if;
  v_direct:=(p_offer->>'direct_pa')::integer;
  select (action_points->>p_player_id::text)::integer,v4_unlocked_spice
  into v_available,v_unlocked_spice
  from public.network_game_states
  where session_id=p_session_id for update;
  if v_direct>v_available then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
  if v_available<10 and v_direct>0 then raise exception 'ROUND_INVALID_BID'; end if;
  if (p_offer->>'inversion_requested')::boolean
    and not (v_round.initial_resolution->>'inversion_allowed')::boolean then
    raise exception 'ROUND_INVERSION_FORBIDDEN';
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
    'proposal',p_offer,'response',null,'final_offer',null
  ),phase='NEGOTIATION_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

revoke all on function public.submit_network_negotiation_proposal(
  uuid,uuid,uuid,jsonb,text
) from public;
grant execute on function public.submit_network_negotiation_proposal(
  uuid,uuid,uuid,jsonb,text
) to authenticated;

create or replace function public.submit_network_corruption_offer(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_objective text,
  p_card_ids jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_actor uuid;
  v_winner uuid;
  v_payload jsonb;
  v_compromise jsonb;
  v_actions jsonb;
  v_unlocked_spice integer;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_objective<>'OWN_INITIAL_ACTION'
    or jsonb_typeof(p_card_ids)<>'array' or jsonb_array_length(p_card_ids)=0
    or exists(select 1 from jsonb_array_elements(p_card_ids) x
      where jsonb_typeof(x)<>'object' or coalesce(x->>'card_id','')=''
        or coalesce(x->>'occurrence_id','')='')
    or (select count(distinct x->>'occurrence_id') from jsonb_array_elements(p_card_ids) x)
      <>jsonb_array_length(p_card_ids) then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_payload:=jsonb_build_object('objective',p_objective,'cards',p_card_ids);
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'CORRUPTION_OFFER'
      or v_command.command_payload is distinct from v_payload then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'CORRUPTION_DECISION' then raise exception 'ROUND_INVALID_PHASE'; end if;
  v_winner:=coalesce(
    (v_round.final_resolution->>'final_winner_player_id')::uuid,
    (v_round.final_resolution->>'retained_player_id')::uuid
  );
  select user_id into v_actor from public.session_players
  where session_id=p_session_id and user_id<>v_winner;
  if p_player_id<>v_actor then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  if exists(
    select 1 from jsonb_array_elements(p_card_ids) proposed
    where exists(
        select 1 from public.network_rounds previous,
          jsonb_array_elements(coalesce(previous.corruption->'actions','[]'::jsonb)) action
        where previous.session_id=p_session_id
          and previous.round_number<v_round.round_number
          and previous.corruption->>'offered_by'=p_player_id::text
          and action->>'occurrence_id'=proposed->>'occurrence_id'
          and action->>'status'='COMPLETED'
      ) or exists(
        select 1 from public.network_rounds previous,
          jsonb_array_elements(coalesce(previous.recovery_history,'[]'::jsonb)) recovery
        where previous.session_id=p_session_id
          and previous.round_number<v_round.round_number
          and recovery->>'player_id'=p_player_id::text
          and recovery->>'occurrence_id'=proposed->>'occurrence_id'
          and (recovery->>'completed')::boolean
      )
  ) then raise exception 'ROUND_CORRUPTION_FORBIDDEN'; end if;
  v_compromise:=public.v4_corruption_compromise(
    p_session_id,v_round.round_number,p_player_id,p_card_ids
  );
  select v4_unlocked_spice into v_unlocked_spice
  from public.network_game_states where session_id=p_session_id;
  if v_unlocked_spice is null or exists(
    select 1 from jsonb_array_elements(v_compromise) card
    where (card->>'effective_spice')::integer>v_unlocked_spice
  ) then
    raise exception 'ROUND_CORRUPTION_FORBIDDEN';
  end if;
  select jsonb_agg(jsonb_build_object(
    'card_id',card->>'card_id',
    'occurrence_id',card->>'occurrence_id',
    'variant_id',card->>'variant_id',
    'effective_spice',card->'effective_spice',
    'source','DISCARD','status','PROPOSED','visibility','VISIBLE'
  ) order by ordinality) into v_actions
  from jsonb_array_elements(v_compromise) with ordinality as item(card,ordinality);
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_OFFER',v_payload);
  update public.network_rounds set corruption=jsonb_build_object(
    'offered_by',p_player_id,'objective',p_objective,'accepted',null,
    'actions',v_actions
  ),phase='CORRUPTION_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

create or replace function public.respond_network_corruption(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_accepted boolean,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_payload jsonb;
  v_winner uuid;
  v_compromise jsonb;
  v_first jsonb;
  v_corruption jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  v_payload:=jsonb_build_object('accepted',p_accepted);
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'CORRUPTION_RESPONSE'
      or v_command.command_payload is distinct from v_payload then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'CORRUPTION_RESPONSE' then raise exception 'ROUND_INVALID_PHASE'; end if;
  v_winner:=coalesce(
    (v_round.final_resolution->>'final_winner_player_id')::uuid,
    (v_round.final_resolution->>'retained_player_id')::uuid
  );
  if p_player_id<>v_winner
    or v_round.corruption->>'offered_by'=p_player_id::text then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  v_corruption:=jsonb_set(v_round.corruption,'{accepted}',to_jsonb(p_accepted),true);
  if p_accepted then
    v_compromise:=public.v4_corruption_compromise(
      p_session_id,v_round.round_number,
      (v_round.corruption->>'offered_by')::uuid,
      v_round.corruption->'actions'
    );
    v_first:=v_compromise->0;
    v_corruption:=jsonb_set(
      v_corruption,'{accepted_compromise}',v_compromise,true
    );
    update public.network_rounds set
      corruption=v_corruption,
      final_resolution=jsonb_set(
        jsonb_set(
          jsonb_set(v_round.final_resolution,'{compromise}',v_compromise,true),
          '{card_id}',to_jsonb(v_first->>'card_id'),true
        ),
        '{variant_id}',to_jsonb(v_first->>'variant_id'),true
      ),
      phase='CORRUPTION_EXECUTION',updated_at=now()
    where id=p_round_id;
  else
    update public.network_rounds set corruption=v_corruption,
      phase='FINAL_RESOLVED',updated_at=now() where id=p_round_id;
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_RESPONSE',v_payload);
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

create or replace function public.resolve_network_corruption(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_actions jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_payload jsonb;
  v_actions jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions)=0
    or exists(select 1 from jsonb_array_elements(p_actions) x
      where x->>'source'<>'DISCARD'
        or x->>'status' not in ('COMPLETED','SKIPPED','STOPPED')
        or coalesce(x->>'occurrence_id','')='')
    or (select count(distinct x->>'occurrence_id') from jsonb_array_elements(p_actions) x)
      <>jsonb_array_length(p_actions) then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_payload:=jsonb_build_object('actions',p_actions);
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'CORRUPTION_RESOLVE'
      or v_command.command_payload is distinct from v_payload then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'CORRUPTION_EXECUTION'
    or v_round.corruption->>'offered_by'<>p_player_id::text
    or jsonb_array_length(p_actions)<>jsonb_array_length(v_round.corruption->'actions')
    or exists(
      select 1 from jsonb_array_elements(v_round.corruption->'actions') offered
      where not exists(
        select 1 from jsonb_array_elements(p_actions) submitted
        where submitted->>'occurrence_id'=offered->>'occurrence_id'
          and submitted->>'card_id'=offered->>'card_id'
      )
    ) then raise exception 'ROUND_CORRUPTION_FORBIDDEN'; end if;
  select jsonb_agg(
    offered||jsonb_build_object('status',submitted->>'status')
    order by ordinality
  ) into v_actions
  from jsonb_array_elements(v_round.corruption->'actions')
    with ordinality as original(offered,ordinality)
  join jsonb_array_elements(p_actions) submitted
    on submitted->>'occurrence_id'=offered->>'occurrence_id'
   and submitted->>'card_id'=offered->>'card_id';
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_RESOLVE',v_payload);
  update public.network_rounds set corruption=jsonb_set(
    corruption,'{actions}',v_actions,true
  ),phase='RECOVERY',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

create or replace function public.skip_network_corruption(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_actor uuid;
  v_winner uuid;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'CORRUPTION_SKIP' then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  v_winner:=coalesce(
    (v_round.final_resolution->>'final_winner_player_id')::uuid,
    (v_round.final_resolution->>'retained_player_id')::uuid
  );
  select user_id into v_actor from public.session_players
  where session_id=p_session_id and user_id<>v_winner;
  if v_round.phase<>'CORRUPTION_DECISION' or p_player_id<>v_actor then
    raise exception 'ROUND_CORRUPTION_FORBIDDEN';
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_SKIP');
  update public.network_rounds set phase='FINAL_RESOLVED',updated_at=now()
  where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

revoke all on function public.submit_network_corruption_offer(
  uuid,uuid,uuid,text,jsonb,text
) from public;
revoke all on function public.respond_network_corruption(
  uuid,uuid,uuid,boolean,text
) from public;
revoke all on function public.resolve_network_corruption(
  uuid,uuid,uuid,jsonb,text
) from public;
revoke all on function public.skip_network_corruption(
  uuid,uuid,uuid,text
) from public;
grant execute on function public.submit_network_corruption_offer(
  uuid,uuid,uuid,text,jsonb,text
) to authenticated;
grant execute on function public.respond_network_corruption(
  uuid,uuid,uuid,boolean,text
) to authenticated;
grant execute on function public.resolve_network_corruption(
  uuid,uuid,uuid,jsonb,text
) to authenticated;
grant execute on function public.skip_network_corruption(
  uuid,uuid,uuid,text
) to authenticated;
