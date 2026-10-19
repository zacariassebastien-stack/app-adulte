-- Refusals preserve the original result and allow the other untried choice.
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
  v_canonical_offer jsonb;
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
  if v_round.negotiation#>'{response,accepted}' is not null then
    raise exception 'ROUND_NEGOTIATION_INVALID';
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
  v_canonical_offer:=p_offer;
  v_direct:=(p_offer->>'direct_pa')::integer;
  select (action_points->>p_player_id::text)::integer,v4_unlocked_spice
  into v_available,v_unlocked_spice
  from public.network_game_states
  where session_id=p_session_id for update;
  if v_direct>v_available then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
  if v_available<10 and v_direct>0 then raise exception 'ROUND_INVALID_BID'; end if;
  if (p_offer->>'inversion_requested')::boolean then
    select choice_payload into v_choice from public.network_round_reveals
    -- Invert the winning action, consistently with INITIAL_RESOLVE.
    where round_id=p_round_id and player_id=v_winner;
    if not found
      or coalesce(v_choice#>>'{resolved_action,direction}','GENERAL') not in ('FAIRE','RECEVOIR')
      or coalesce(v_choice#>>'{inverted_resolution,snapshot_value}','') !~ '^[0-9]+$'
      or (v_choice#>>'{inverted_resolution,snapshot_value}')::integer not between 1 and 20 then
      raise exception 'ROUND_INVERSION_FORBIDDEN';
    end if;
  end if;
  if (select count(*) from jsonb_array_elements(p_offer->'cards')) <>
     (select count(distinct x->>'usage_id')
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
      where (card#>>'{resolved_action,effective_chili}')::integer>v_unlocked_spice
    ) then
      raise exception 'ROUND_NEGOTIATION_INVALID';
    end if;
    select coalesce(jsonb_agg(
      card||jsonb_build_object('origin','AUCTION') order by ordinality
    ),'[]'::jsonb) into v_compromise
    from jsonb_array_elements(v_compromise)
      with ordinality as canonical(card,ordinality);
    v_canonical_offer:=jsonb_set(
      p_offer,'{cards}',v_compromise,true
    );
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(
    p_command_id,p_session_id,p_round_id,p_player_id,
    'NEGOTIATION_PROPOSAL',p_offer
  );
  update public.network_rounds set negotiation=jsonb_build_object(
    'offered_by',p_player_id,
    'proposal',v_canonical_offer,
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
  v_winner:=coalesce(
    (v_round.final_resolution->>'final_winner_player_id')::uuid,
    (v_round.final_resolution->>'retained_player_id')::uuid
  );
  if v_winner is null or v_winner=v_loser then
    raise exception 'ROUND_NEGOTIATION_INVALID';
  end if;
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
    ),phase='CORRUPTION_DECISION',updated_at=now() where id=p_round_id;
    return public.network_round_json(p_round_id,p_player_id);
  end if;

  select choice_payload into v_choice from public.network_round_reveals
  -- Only inversion targets the initial winning action; ordinary compromises
  -- retain the losing action as before.
  where round_id=p_round_id and player_id=case when v_inverted
    then (v_round.initial_resolution->>'winner_player_id')::uuid else v_loser end;
  if not found then raise exception 'ROUND_REVEAL_MISSING'; end if;
  if coalesce(v_choice#>>'{native_direction}',
      v_choice#>>'{resolved_action,direction}','GENERAL') <>
     coalesce(v_choice#>>'{effective_direction}',
      v_choice#>>'{resolved_action,direction}','GENERAL') then
    raise exception 'ROUND_DIRECTION_MISMATCH';
  end if;
  if v_inverted and (
    coalesce(v_choice#>>'{resolved_action,direction}','GENERAL') not in ('FAIRE','RECEVOIR')
    or coalesce(v_choice#>>'{inverted_resolution,snapshot_value}','') !~ '^[0-9]+$'
    or (v_choice#>>'{inverted_resolution,snapshot_value}')::integer not between 1 and 20
  ) then
    raise exception 'ROUND_INVERSION_UNAVAILABLE';
  end if;
  v_initial_card:=public.network_usage_resolution(v_choice,v_inverted)
    ||jsonb_build_object('origin','INITIAL_DUEL','logical_order',0);
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
      'final_winner_player_id',v_winner,
      'concept_id',v_initial_card->>'concept_id',
      'usage_id',v_initial_card->>'usage_id',
      'inverted',v_inverted,
      'mutual_abandon',false,
      'compromise',v_cards
    ),
    phase='FINAL_RESOLVED',updated_at=now()
  where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

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
      where jsonb_typeof(x)<>'object' or coalesce(x->>'concept_id','')=''
        or coalesce(x->>'usage_id','')='')
    or (select count(distinct x->>'usage_id') from jsonb_array_elements(p_card_ids) x)
      <>jsonb_array_length(p_card_ids) then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  for v_actions in select value from jsonb_array_elements(p_card_ids) loop
    perform public.network_usage_projection(v_actions,false);
  end loop;
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
  if v_round.corruption->>'accepted' is not null then
    raise exception 'ROUND_CORRUPTION_FORBIDDEN';
  end if;
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
          and previous.corruption->>'accepted'='true'
          and (action->>'usage_id'=proposed->>'source_usage_id'
            or action->>'source_usage_id'=proposed->>'source_usage_id')
      ) or exists(
        select 1 from public.network_rounds previous,
          jsonb_array_elements(coalesce(previous.recovery_history,'[]'::jsonb)) recovery
        where previous.session_id=p_session_id
          and previous.round_number<v_round.round_number
          and recovery->>'player_id'=p_player_id::text
          and recovery->>'usage_id'=proposed->>'usage_id'
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
    where (card#>>'{resolved_action,effective_chili}')::integer>v_unlocked_spice
  ) then
    raise exception 'ROUND_CORRUPTION_FORBIDDEN';
  end if;
  select jsonb_agg((card-array['origin','logical_order'])||jsonb_build_object(
    'source','DISCARD','status','PROPOSED','visibility','VISIBLE') order by ordinality)
    into v_actions from jsonb_array_elements(v_compromise) with ordinality as item(card,ordinality);
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
          '{concept_id}',to_jsonb(v_first->>'concept_id'),true
        ),
        '{usage_id}',to_jsonb(v_first->>'usage_id'),true
      ),
      v4_action_projection=null,
      phase='FINAL_RESOLVED',updated_at=now()
    where id=p_round_id;
  else
    update public.network_rounds set corruption=v_corruption,
      phase='CORRUPTION_DECISION',updated_at=now() where id=p_round_id;
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_RESPONSE',v_payload);
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;
