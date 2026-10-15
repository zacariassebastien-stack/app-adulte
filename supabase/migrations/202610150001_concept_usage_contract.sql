-- Lot 4: native concept/usage JSON contract. No tables, columns or quotas.
-- BREAKING for old runtime payloads: do not deploy before Lot 5/6 cutover.
-- Resolved semantic tags are shared action metadata; private profile state and
-- personal_values never belong to this public projection.

create function public.network_usage_action(p_action jsonb)
returns jsonb language plpgsql immutable set search_path=public as $$
declare v_item jsonb; v_field text; v_definition text;
begin
  if coalesce(jsonb_typeof(p_action),'null')<>'object' then raise exception 'ROUND_USAGE_INVALID'; end if;
  if exists(select 1 from jsonb_object_keys(p_action) k where k <> all(array[
    'concept_id','catalog_version','locale','stage_id','variant_id','zone_id',
    'effective_chili','direction','actor_player_ids','target_player_ids',
    'parameters','accessories','tags','primary_preference_ids','effects','action_text'
  ])) then raise exception 'ROUND_USAGE_INVALID'; end if;
  if coalesce(trim(p_action->>'concept_id'),'')='' or coalesce(trim(p_action->>'locale'),'')=''
    or coalesce(p_action->>'catalog_version','') !~ '^[1-9][0-9]*$'
    or coalesce(p_action->>'effective_chili','') !~ '^[1-4]$'
    or coalesce(p_action->>'direction','') not in ('GENERAL','FAIRE','RECEVOIR','MUTUEL','SOLO','SIMULTANE')
    or coalesce(trim(p_action->>'action_text'),'')=''
    or (p_action ? 'stage_id')=(p_action ? 'variant_id')
    or coalesce(jsonb_typeof(p_action->'parameters'),'null')<>'object'
    then raise exception 'ROUND_USAGE_INVALID'; end if;
  v_definition:=coalesce(p_action->>'stage_id',p_action->>'variant_id');
  if left(coalesce(v_definition,''),length(p_action->>'concept_id')+1)<>(p_action->>'concept_id')||'.'
    or ((p_action ? 'zone_id') and coalesce(trim(p_action->>'zone_id'),'')='')
    then raise exception 'ROUND_USAGE_INVALID'; end if;
  foreach v_field in array array['actor_player_ids','target_player_ids','tags','primary_preference_ids'] loop
    if coalesce(jsonb_typeof(p_action->v_field),'null')<>'array' then raise exception 'ROUND_USAGE_INVALID'; end if;
    if exists(select 1 from jsonb_array_elements(p_action->v_field) x
      where jsonb_typeof(x)<>'string' or trim(x#>>'{}')='') then raise exception 'ROUND_USAGE_INVALID'; end if;
  end loop;
  if jsonb_array_length(p_action->'actor_player_ids')=0
    or coalesce(jsonb_typeof(p_action->'accessories'),'null')<>'array'
    or coalesce(jsonb_typeof(p_action->'effects'),'null')<>'array' then raise exception 'ROUND_USAGE_INVALID'; end if;
  for v_item in select value from jsonb_array_elements(p_action->'accessories') loop
    if jsonb_typeof(v_item)<>'object' or coalesce(trim(v_item->>'accessory_id'),'')=''
      or coalesce(trim(v_item->>'label'),'')='' then raise exception 'ROUND_USAGE_INVALID'; end if;
    if exists(select 1 from jsonb_object_keys(v_item) k where k <> all(array['accessory_id','label']))
      then raise exception 'ROUND_USAGE_INVALID'; end if;
  end loop;
  for v_item in select value from jsonb_array_elements(p_action->'effects') loop
    if jsonb_typeof(v_item)<>'object' or coalesce(trim(v_item->>'effect_id'),'')=''
      or coalesce(jsonb_typeof(v_item->'parameters'),'null')<>'object' then raise exception 'ROUND_USAGE_INVALID'; end if;
    if exists(select 1 from jsonb_object_keys(v_item) k where k <> all(array['effect_id','parameters']))
      then raise exception 'ROUND_USAGE_INVALID'; end if;
  end loop;
  return p_action;
end; $$;

create function public.network_usage_projection(p_usage jsonb,p_values boolean)
returns jsonb language plpgsql immutable set search_path=public as $$
declare v_action jsonb; v_inverse jsonb;
begin
  if coalesce(jsonb_typeof(p_usage),'null')<>'object' then raise exception 'ROUND_USAGE_INVALID'; end if;
  if exists(select 1 from jsonb_object_keys(p_usage) k where k <> all(array[
    'usage_schema_version','usage_id','concept_id','owner_player_id','native_direction',
    'effective_direction','resolved_action','snapshot_value','inverted_resolution','source_usage_id'
  ])) then raise exception 'ROUND_USAGE_INVALID'; end if;
  if p_usage->'usage_schema_version' is distinct from '1'::jsonb
    or coalesce(trim(p_usage->>'usage_id'),'')='' or coalesce(trim(p_usage->>'concept_id'),'')=''
    or coalesce(trim(p_usage->>'owner_player_id'),'')=''
    or coalesce(p_usage->>'native_direction','') not in ('GENERAL','FAIRE','RECEVOIR','MUTUEL','SOLO','SIMULTANE')
    or ((p_usage ? 'source_usage_id') and coalesce(trim(p_usage->>'source_usage_id'),'')='')
    then raise exception 'ROUND_USAGE_INVALID'; end if;
  v_action:=public.network_usage_action(p_usage->'resolved_action');
  if v_action->>'concept_id' is distinct from p_usage->>'concept_id'
    or v_action->>'direction' is distinct from p_usage->>'effective_direction' then raise exception 'ROUND_USAGE_INVALID'; end if;
  if p_usage ? 'snapshot_value' then
    if not p_values then raise exception 'ROUND_USAGE_PRIVATE_VALUE'; end if;
    if coalesce(p_usage->>'snapshot_value','') !~ '^[0-9]+$'
      or (p_usage->>'snapshot_value')::integer not between 1 and 20 then raise exception 'ROUND_USAGE_INVALID'; end if;
  end if;
  if p_usage ? 'inverted_resolution' then
    v_inverse:=p_usage->'inverted_resolution';
    if coalesce(jsonb_typeof(v_inverse),'null')<>'object' then raise exception 'ROUND_USAGE_INVALID'; end if;
    if exists(select 1 from jsonb_object_keys(v_inverse) k where k <> all(array['resolved_action','snapshot_value']))
      then raise exception 'ROUND_USAGE_INVALID'; end if;
    perform public.network_usage_action(v_inverse->'resolved_action');
    if v_inverse#>>'{resolved_action,concept_id}' is distinct from p_usage->>'concept_id'
      or v_inverse#>>'{resolved_action,stage_id}' is distinct from v_action->>'stage_id'
      or v_inverse#>>'{resolved_action,variant_id}' is distinct from v_action->>'variant_id'
      then raise exception 'ROUND_USAGE_INVALID'; end if;
    if v_inverse ? 'snapshot_value' then
      if not p_values then raise exception 'ROUND_USAGE_PRIVATE_VALUE'; end if;
      if coalesce(v_inverse->>'snapshot_value','') !~ '^[0-9]+$'
        or (v_inverse->>'snapshot_value')::integer not between 1 and 20 then raise exception 'ROUND_USAGE_INVALID'; end if;
    end if;
  end if;
  return p_usage;
end; $$;

create function public.network_usage_resolution(p_usage jsonb,p_inverted boolean)
returns jsonb language plpgsql immutable set search_path=public as $$
declare v_usage jsonb; v_inverse jsonb;
begin
  v_usage:=public.network_usage_projection(p_usage,true);
  if p_inverted then
    v_inverse:=v_usage->'inverted_resolution';
    if v_usage->>'native_direction' not in ('FAIRE','RECEVOIR')
      or v_inverse is null or not (v_inverse ? 'snapshot_value')
      then raise exception 'ROUND_INVERSION_UNAVAILABLE'; end if;
    if v_inverse#>>'{resolved_action,direction}' is distinct from
      case v_usage->>'native_direction' when 'FAIRE' then 'RECEVOIR' else 'FAIRE' end
      then raise exception 'ROUND_DIRECTION_MISMATCH'; end if;
    return (v_usage-'inverted_resolution')||jsonb_build_object(
      'resolved_action',v_inverse->'resolved_action',
      'effective_direction',v_inverse#>>'{resolved_action,direction}',
      'snapshot_value',v_inverse->'snapshot_value');
  end if;
  return v_usage-'inverted_resolution';
end; $$;

revoke all on function public.network_usage_action(jsonb) from public,anon,authenticated;
revoke all on function public.network_usage_projection(jsonb,boolean) from public,anon,authenticated;
revoke all on function public.network_usage_resolution(jsonb,boolean) from public,anon,authenticated;

create or replace function public.network_round_json(p_round_id uuid, p_requester uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'schema_version',1,'usage_contract_version',1,'round_id',r.id,'session_id',r.session_id,
    'session_round',r.round_key,'round_number',r.round_number,'phase',r.phase,
    'player_id',p_requester,'action_points',g.action_points,
    'hybrid_orientation',g.hybrid_orientation,'deck_cycle',g.deck_cycle,
    'infinite_mode',g.infinite_mode,'deck_style',g.deck_style,
    'deck_adjustment',g.deck_adjustment,
    'commits',coalesce((select jsonb_object_agg(c.player_id::text,c.digest)
      from public.network_round_commits c where c.round_id=r.id),'{}'::jsonb),
    'own_reveal',(select jsonb_build_object('schema_version',1,
      'session_round',r.round_key,'player_id',v.player_id,'choice',v.choice_payload,'nonce',v.nonce)
      from public.network_round_reveals v where v.round_id=r.id and v.player_id=p_requester),
    'opponent_reveal',case when r.phase='READY' then (select jsonb_build_object(
      'schema_version',1,'session_round',r.round_key,'player_id',v.player_id,
      'choice',v.choice_payload,'nonce',v.nonce) from public.network_round_reveals v
      where v.round_id=r.id and v.player_id<>p_requester) else null end,
    'initial_resolution',r.initial_resolution,'negotiation',r.negotiation,
    'counter_bid',r.counter_bid,'final_defense',r.final_defense,
    'final_resolution',r.final_resolution,'ready_next',r.ready_next,
    'tie_decisions',r.tie_decisions,'corruption',r.corruption,
    'recovery_by_player',r.recovery_by_player,'recovery_done',r.recovery_done,
    'recovery_history',r.recovery_history
  ) from public.network_rounds r join public.network_game_states g on g.session_id=r.session_id
  where r.id=p_round_id;
$$;

create or replace function public.submit_network_round_reveal(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_choice_payload jsonb,
  p_nonce text,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_expected text;
  v_envelope text;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_choice_payload is null or jsonb_typeof(p_choice_payload) <> 'object'
    or p_nonce is null or length(p_nonce) = 0
    or p_command_id is null or length(trim(p_command_id)) = 0 then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;

  perform public.network_usage_projection(p_choice_payload,true);
  if p_choice_payload->>'owner_player_id' is distinct from p_player_id::text
    or p_choice_payload->>'native_direction' is distinct from p_choice_payload->>'effective_direction'
    or not (p_choice_payload ? 'snapshot_value') then raise exception 'ROUND_USAGE_INVALID'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_command_id, 0));
  select * into v_command from public.network_round_commands where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id or v_command.kind <> 'REVEAL'
      or not exists (
        select 1 from public.network_round_reveals
        where command_id = p_command_id and choice_payload = p_choice_payload and nonce = p_nonce
      ) then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id, p_player_id);
  end if;

  select * into v_round from public.network_rounds where id = p_round_id for update;
  if not found or v_round.session_id <> p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase <> 'REVEAL' then raise exception 'ROUND_REVEAL_CLOSED'; end if;

  select digest into v_expected from public.network_round_commits
  where round_id = p_round_id and player_id = p_player_id;
  if v_expected is null then raise exception 'ROUND_COMMIT_MISSING'; end if;

  v_envelope := '[' || to_jsonb(v_round.round_key)::text || ',' || to_jsonb(p_player_id::text)::text || ','
    || to_jsonb(public.canonical_jsonb(p_choice_payload))::text || ',' || to_jsonb(p_nonce)::text || ']';
  if encode(extensions.digest(convert_to(v_envelope, 'UTF8'), 'sha256'::text), 'hex') <> v_expected then
    raise exception 'ROUND_REVEAL_MISMATCH';
  end if;

  insert into public.network_round_commands(command_id, session_id, round_id, player_id, kind)
  values (p_command_id, p_session_id, p_round_id, p_player_id, 'REVEAL');
  insert into public.network_round_reveals(round_id, player_id, choice_payload, nonce, command_id)
  values (p_round_id, p_player_id, p_choice_payload, p_nonce, p_command_id);

  update public.network_rounds
  set phase = case
      when (select count(*) from public.network_round_reveals where round_id = p_round_id) = 2
        then 'READY'
      else phase
    end,
    updated_at = now()
  where id = p_round_id;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

create or replace function public.network_final_choice(
  p_round_id uuid,p_choice_player_id uuid,p_retained_player_id uuid,p_inverted boolean
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'retained_player_id',p_retained_player_id,'usage_id',v.choice_payload->>'usage_id',
    'concept_id',v.choice_payload->>'concept_id','inverted',p_inverted,'mutual_abandon',false,
    'compromise',jsonb_build_array(public.network_usage_resolution(v.choice_payload,p_inverted)
      ||jsonb_build_object('origin','INITIAL_DUEL','logical_order',0)))
  from public.network_round_reveals v where v.round_id=p_round_id and v.player_id=p_choice_player_id;
$$;

create or replace function public.submit_network_negotiation_proposal(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_offer jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_available integer; v_direct integer; v_card jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'NEGOTIATION_PROPOSAL' or v_command.command_payload is distinct from p_offer
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'NEGOTIATION_PROPOSAL' then raise exception 'ROUND_INVALID_PHASE'; end if;
  if p_player_id::text<>v_round.initial_resolution->>'loser_player_id' then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  if jsonb_typeof(p_offer)<>'object' or jsonb_typeof(p_offer->'cards')<>'array'
    or (p_offer->>'direct_pa')::integer<0 then raise exception 'ROUND_NEGOTIATION_INVALID'; end if;
  for v_card in select value from jsonb_array_elements(p_offer->'cards') loop
    perform public.network_usage_projection(v_card-array['origin','logical_order'],true);
    if not (v_card ? 'snapshot_value') then raise exception 'ROUND_USAGE_INVALID'; end if;
  end loop;
  v_direct:=(p_offer->>'direct_pa')::integer;
  select (action_points->>p_player_id::text)::integer into v_available
    from public.network_game_states where session_id=p_session_id for update;
  if v_direct>v_available then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
  if v_available<10 and v_direct>0 then raise exception 'ROUND_INVALID_BID'; end if;
  if (p_offer->>'inversion_requested')::boolean and not (v_round.initial_resolution->>'inversion_allowed')::boolean
    then raise exception 'ROUND_INVERSION_FORBIDDEN'; end if;
  if (select count(*) from jsonb_array_elements(p_offer->'cards')) <>
     (select count(distinct x->>'usage_id') from jsonb_array_elements(p_offer->'cards') x)
    then raise exception 'ROUND_AUCTION_CARD_REUSED'; end if;
  if exists(select 1 from jsonb_array_elements(p_offer->'cards') x where
      x->>'owner_player_id'<>p_player_id::text or x->>'origin'<>'AUCTION'
      or x->>'native_direction'<>x->>'effective_direction'
      or (x->>'snapshot_value')::integer not between 1 and 20)
    then raise exception 'ROUND_NEGOTIATION_INVALID'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'NEGOTIATION_PROPOSAL',p_offer);
  update public.network_rounds set negotiation=jsonb_build_object('proposal',p_offer,'response',null,'final_offer',null),
    phase='NEGOTIATION_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.adapt_network_negotiation(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_offer jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_response jsonb; v_available integer; v_direct integer;
  v_command public.network_round_commands%rowtype; v_card jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'NEGOTIATION_ADAPTATION' or v_command.command_payload is distinct from p_offer
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'NEGOTIATION_ADAPTATION' or p_player_id::text<>v_round.initial_resolution->>'loser_player_id'
    then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  for v_card in select value from jsonb_array_elements(p_offer->'cards') loop
    perform public.network_usage_projection(v_card-array['origin','logical_order'],true);
    if not (v_card ? 'snapshot_value') then raise exception 'ROUND_USAGE_INVALID'; end if;
  end loop;
  v_response:=v_round.negotiation->'response'; v_direct:=(p_offer->>'direct_pa')::integer;
  select (action_points->>p_player_id::text)::integer into v_available from public.network_game_states
    where session_id=p_session_id for update;
  if v_direct<0 or v_direct>v_available or (v_available<10 and v_direct>0)
    then raise exception 'ROUND_INVALID_BID'; end if;
  if (p_offer->>'inversion_requested')::boolean and not (v_response->>'accept_inversion')::boolean
    then raise exception 'ROUND_NEGOTIATION_INVALID'; end if;
  if (v_direct>0 or jsonb_array_length(p_offer->'cards')>0) and not (v_response->>'accept_auction')::boolean
    then raise exception 'ROUND_NEGOTIATION_INVALID'; end if;
  if (select count(*) from jsonb_array_elements(p_offer->'cards')) <>
     (select count(distinct x->>'usage_id') from jsonb_array_elements(p_offer->'cards') x)
    then raise exception 'ROUND_AUCTION_CARD_REUSED'; end if;
  if exists(select 1 from jsonb_array_elements(p_offer->'cards') x where x->>'owner_player_id'<>p_player_id::text
    or x->>'origin'<>'AUCTION' or x->>'native_direction'<>x->>'effective_direction')
    then raise exception 'ROUND_NEGOTIATION_INVALID'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'NEGOTIATION_ADAPTATION',p_offer);
  update public.network_rounds set negotiation=jsonb_set(negotiation,'{final_offer}',p_offer),
    phase='NEGOTIATION_VALIDATION',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.validate_network_negotiation(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_accepted boolean,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_offer jsonb; v_points jsonb; v_winner uuid; v_loser uuid; v_final uuid;
  v_spend integer:=0; v_current integer; v_inverted boolean:=false; v_choice_owner uuid;
  v_initial_card jsonb; v_cards jsonb; v_payload jsonb; v_choice jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  v_payload:=jsonb_build_object('accepted',p_accepted);
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'NEGOTIATION_VALIDATION' or v_command.command_payload is distinct from v_payload
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  v_winner:=(v_round.initial_resolution->>'winner_player_id')::uuid;
  v_loser:=(v_round.initial_resolution->>'loser_player_id')::uuid;
  if v_round.phase<>'NEGOTIATION_VALIDATION' or p_player_id<>v_winner then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  v_offer:=v_round.negotiation->'final_offer';
  v_inverted:=p_accepted and (v_offer->>'inversion_requested')::boolean;
  v_final:=case when p_accepted and (v_inverted or (v_offer->>'direct_pa')::integer>0
    or jsonb_array_length(v_offer->'cards')>0) then v_loser else v_winner end;
  v_choice_owner:=case when v_inverted then v_winner else v_final end;
  select choice_payload into v_choice from public.network_round_reveals
    where round_id=p_round_id and player_id=v_choice_owner;
  if not found then raise exception 'ROUND_REVEAL_MISSING'; end if;
  v_initial_card:=public.network_usage_resolution(v_choice,v_inverted)
    ||jsonb_build_object('origin','INITIAL_DUEL','logical_order',0);
  v_cards:=jsonb_build_array(v_initial_card);
  if p_accepted then v_cards:=v_cards||coalesce(v_offer->'cards','[]'::jsonb); end if;
  select action_points into v_points from public.network_game_states where session_id=p_session_id for update;
  if v_final=v_winner then
    v_current:=(v_points->>v_winner::text)::integer;
    v_points:=jsonb_set(v_points,array[v_winner::text],to_jsonb(greatest(0,v_current-(v_round.initial_resolution->>'gap_cost')::integer)));
  else
    v_spend:=(v_offer->>'direct_pa')::integer + case when v_inverted then (v_round.initial_resolution->>'high_value')::integer else 0 end;
    v_current:=(v_points->>v_loser::text)::integer;
    if v_spend>v_current then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
    v_points:=jsonb_set(v_points,array[v_loser::text],to_jsonb(v_current-v_spend));
  end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'NEGOTIATION_VALIDATION',v_payload);
  update public.network_game_states set action_points=v_points,updated_at=now() where session_id=p_session_id;
  update public.network_rounds set final_resolution=jsonb_build_object(
      'retained_player_id',v_final,'initial_winner_player_id',v_winner,'final_winner_player_id',v_final,
      'usage_id',v_initial_card->>'usage_id','concept_id',v_initial_card->>'concept_id',
      'inverted',v_inverted,'mutual_abandon',false,'compromise',v_cards),
    phase='FINAL_RESOLVED',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.submit_network_corruption_offer(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_objective text,
  p_card_ids jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_actor uuid; v_payload jsonb; v_card jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_objective not in ('OWN_INITIAL_ACTION','INVERT_WINNING_ACTION')
    or jsonb_typeof(p_card_ids)<>'array' or jsonb_array_length(p_card_ids)=0
    or exists(select 1 from jsonb_array_elements(p_card_ids) x
      where jsonb_typeof(x)<>'object' or coalesce(x->>'concept_id','')='' or coalesce(x->>'usage_id','')='')
    or (select count(distinct x->>'usage_id') from jsonb_array_elements(p_card_ids) x)<>jsonb_array_length(p_card_ids)
    then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  for v_card in select value from jsonb_array_elements(p_card_ids) loop
    perform public.network_usage_projection(v_card,false);
    if v_card->>'owner_player_id' is distinct from p_player_id::text
      or coalesce(v_card->>'source_usage_id','')='' then raise exception 'ROUND_USAGE_INVALID'; end if;
  end loop;
  v_payload:=jsonb_build_object('objective',p_objective,'cards',p_card_ids);
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'CORRUPTION_OFFER'
      or v_command.command_payload is distinct from v_payload then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'CORRUPTION_DECISION' then raise exception 'ROUND_INVALID_PHASE'; end if;
  select user_id into v_actor from public.session_players where session_id=p_session_id
    and user_id::text<>v_round.final_resolution->>'retained_player_id';
  if p_player_id<>v_actor then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  if exists (
    select 1 from jsonb_array_elements(p_card_ids) proposed
    where not exists (
      select 1 from public.network_round_reveals reveal
      join public.network_rounds previous on previous.id=reveal.round_id
      where previous.session_id=p_session_id and previous.round_number<v_round.round_number
        and reveal.player_id=p_player_id
        and reveal.choice_payload->>'usage_id'=proposed->>'source_usage_id'
        and reveal.choice_payload->>'concept_id'=proposed->>'concept_id'
    ) or exists (
      select 1 from public.network_rounds previous,
        jsonb_array_elements(coalesce(previous.corruption->'actions','[]'::jsonb)) action
      where previous.session_id=p_session_id and previous.round_number<v_round.round_number
        and previous.corruption->>'offered_by'=p_player_id::text
        and action->>'usage_id'=proposed->>'usage_id' and action->>'status'='COMPLETED'
    )
  ) then raise exception 'ROUND_CORRUPTION_FORBIDDEN'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_OFFER',v_payload);
  update public.network_rounds set corruption=jsonb_build_object(
    'offered_by',p_player_id,'objective',p_objective,'accepted',null,
    'actions',(select jsonb_agg(x||jsonb_build_object('source','DISCARD',
      'status','PROPOSED','visibility','VISIBLE')) from jsonb_array_elements(p_card_ids) x)),
    phase='CORRUPTION_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.resolve_network_corruption(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_actions jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions)=0
    or exists(select 1 from jsonb_array_elements(p_actions) x where x->>'source'<>'DISCARD'
      or x->>'status' not in ('COMPLETED','SKIPPED','STOPPED')) then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  v_payload:=jsonb_build_object('actions',p_actions); perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'CORRUPTION_RESOLVE' or v_command.command_payload is distinct from v_payload
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if (select count(distinct x->>'usage_id') from jsonb_array_elements(p_actions) x)<>jsonb_array_length(p_actions)
    then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  if v_round.phase<>'CORRUPTION_EXECUTION' or v_round.corruption->>'offered_by'<>p_player_id::text
    or (select array_agg(x->>'usage_id' order by x->>'usage_id') from jsonb_array_elements(p_actions)x)
       is distinct from (select array_agg(x->>'usage_id' order by x->>'usage_id') from jsonb_array_elements(v_round.corruption->'actions')x)
    then raise exception 'ROUND_CORRUPTION_FORBIDDEN'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_RESOLVE',v_payload);
  update public.network_rounds set corruption=jsonb_set(corruption,'{actions}',(
    select jsonb_agg(saved||jsonb_build_object('status',result->'status',
      'visibility',coalesce(result->'visibility',saved->'visibility')) order by ordinal)
    from jsonb_array_elements(v_round.corruption->'actions') with ordinality a(saved,ordinal)
    join jsonb_array_elements(p_actions) result on result->>'usage_id'=saved->>'usage_id')),phase='RECOVERY',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.submit_network_recovery(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_recovery jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_current integer;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_recovery->>'player_id'<>p_player_id::text or p_recovery->>'source' not in ('HAND','DISCARD','CATALOG')
    or (p_recovery->>'gain')::integer<>0 or (p_recovery->>'completed')::boolean or p_recovery->>'response' is not null
    then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  perform public.network_usage_projection(p_recovery-array['player_id','source','completed','gain','response'],false);
  if p_recovery->>'owner_player_id' is distinct from p_player_id::text then raise exception 'ROUND_USAGE_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'RECOVERY' or v_command.command_payload is distinct from p_recovery
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  select (action_points->>p_player_id::text)::integer into v_current from public.network_game_states
    where session_id=p_session_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'RECOVERY' or v_round.recovery_done ? p_player_id::text or v_current>10
    then raise exception 'ROUND_RECOVERY_NOT_ELIGIBLE'; end if;
  if exists(select 1 from jsonb_array_elements(v_round.recovery_history) x
    where x->>'usage_id'=p_recovery->>'usage_id') then raise exception 'ROUND_AUCTION_CARD_REUSED'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY',p_recovery);
  update public.network_rounds set recovery_by_player=jsonb_set(recovery_by_player,array[p_player_id::text],p_recovery),
    phase='RECOVERY_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.resolve_network_recovery(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_recovery jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_points jsonb; v_current integer; v_gain integer; v_existing jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_recovery->>'player_id'<>p_player_id::text or p_recovery->>'response'<>'ACCEPT'
    or (p_recovery->>'gain')::integer not between 0 and 30 then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  perform public.network_usage_projection(p_recovery-array['player_id','source','completed','gain','response'],false);
  if p_recovery->>'owner_player_id' is distinct from p_player_id::text then raise exception 'ROUND_USAGE_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'RECOVERY_RESOLVE' or v_command.command_payload is distinct from p_recovery
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  v_existing:=v_round.recovery_by_player->p_player_id::text;
  if v_round.phase<>'RECOVERY_EXECUTION' or v_existing is null
    or v_existing->>'usage_id' is distinct from p_recovery->>'usage_id'
    or (v_existing-array['gain','completed','response']) is distinct from
       (p_recovery-array['gain','completed','response'])
    then raise exception 'ROUND_RECOVERY_NOT_ELIGIBLE'; end if;
  select action_points into v_points from public.network_game_states where session_id=p_session_id for update;
  v_current:=(v_points->>p_player_id::text)::integer; v_gain:=(p_recovery->>'gain')::integer;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY_RESOLVE',p_recovery);
  update public.network_game_states set action_points=jsonb_set(v_points,array[p_player_id::text],to_jsonb(v_current+v_gain)),updated_at=now()
    where session_id=p_session_id;
  update public.network_rounds set recovery_history=recovery_history||jsonb_build_array(p_recovery),
    recovery_by_player=recovery_by_player-p_player_id::text,phase='RECOVERY',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;
