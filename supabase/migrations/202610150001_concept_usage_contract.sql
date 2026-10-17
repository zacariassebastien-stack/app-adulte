-- Native concept/usage contract on the stabilized V4 runtime.
-- Prepared locally, NOT deployed. Historical migrations remain immutable.
-- Existing shared state/RPC signatures are retained; JSON action identities become native.
-- The existing v4_consumed_occurrences column records usage IDs, never conceptual quotas.

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

create or replace function public.v4_public_compromise_cards(p_cards jsonb)
returns jsonb language sql immutable set search_path=public as $$
  select coalesce(jsonb_agg(
    (item.value - 'snapshot_value') #- '{inverted_resolution,snapshot_value}'
    order by item.ordinality),'[]'::jsonb)
  from jsonb_array_elements(coalesce(p_cards,'[]'::jsonb))
    with ordinality item(value,ordinality);
$$;

create or replace function public.network_round_json(
  p_round_id uuid,
  p_requester uuid
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'schema_version',1,'usage_contract_version',1,'round_id',r.id,'session_id',r.session_id,
    'session_round',r.round_key,'round_number',r.round_number,'phase',r.phase,
    'player_id',p_requester,'action_points',g.action_points,
    'hybrid_orientation',g.hybrid_orientation,'deck_cycle',g.deck_cycle,
    'hybrid_availability_orientation',r.hybrid_availability_orientation,
    'hybrid_availability_generation',r.hybrid_availability_generation,
    'hybrid_availability',r.hybrid_availability,
    'v4_unlocked_spice',g.v4_unlocked_spice,
    'v4_consumed_usage_ids',coalesce(
      g.v4_consumed_occurrences->p_requester::text,'[]'::jsonb
    ),
    'v4_persistent_effects',g.v4_persistent_effects,
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

create or replace function public.resolve_network_initial_private(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_reveal record;
  v_first_player uuid;
  v_second_player uuid;
  v_first_choice jsonb;
  v_second_choice jsonb;
  v_first_value integer;
  v_second_value integer;
  v_winner uuid;
  v_loser uuid;
  v_winner_choice jsonb;
  v_opposite_value text;
  v_gap integer;
  v_gap_cost integer;
  v_high_value integer;
  v_points jsonb;
  v_inversion_allowed boolean;
  v_resolution jsonb;
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
      or v_command.player_id<>p_player_id or v_command.kind<>'INITIAL_RESOLVE'
      or v_command.command_payload is distinct from '{}'::jsonb then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase<>'READY' then
    if v_round.initial_resolution is null then raise exception 'ROUND_INVALID_PHASE'; end if;
    insert into public.network_round_commands(
      command_id,session_id,round_id,player_id,kind,command_payload
    ) values(p_command_id,p_session_id,p_round_id,p_player_id,'INITIAL_RESOLVE','{}'::jsonb);
    return public.network_round_json(p_round_id,p_player_id);
  end if;

  for v_reveal in
    select player_id,choice_payload from public.network_round_reveals
    where round_id=p_round_id order by player_id
  loop
    if v_first_player is null then
      v_first_player:=v_reveal.player_id;
      v_first_choice:=v_reveal.choice_payload;
    elsif v_second_player is null then
      v_second_player:=v_reveal.player_id;
      v_second_choice:=v_reveal.choice_payload;
    else
      raise exception 'ROUND_READY_INCOMPLETE';
    end if;
  end loop;
  if v_first_player is null or v_second_player is null then
    raise exception 'ROUND_READY_INCOMPLETE';
  end if;
  if coalesce(v_first_choice#>>'{snapshot_value}','') !~ '^[0-9]+$'
    or coalesce(v_second_choice#>>'{snapshot_value}','') !~ '^[0-9]+$' then
    raise exception 'ROUND_RESOLUTION_MISMATCH';
  end if;
  v_first_value:=(v_first_choice#>>'{snapshot_value}')::integer;
  v_second_value:=(v_second_choice#>>'{snapshot_value}')::integer;
  if v_first_value not between 1 and 20 or v_second_value not between 1 and 20 then
    raise exception 'ROUND_RESOLUTION_MISMATCH';
  end if;
  if coalesce(v_first_choice#>>'{effective_direction}',
      v_first_choice#>>'{resolved_action,direction}','GENERAL') <>
      coalesce(v_first_choice#>>'{native_direction}',
      v_first_choice#>>'{resolved_action,direction}','GENERAL')
    or coalesce(v_second_choice#>>'{effective_direction}',
      v_second_choice#>>'{resolved_action,direction}','GENERAL') <>
      coalesce(v_second_choice#>>'{native_direction}',
      v_second_choice#>>'{resolved_action,direction}','GENERAL') then
    raise exception 'ROUND_DIRECTION_MISMATCH';
  end if;

  select action_points into v_points from public.network_game_states
  where session_id=p_session_id for update;
  v_gap:=abs(v_first_value-v_second_value);
  v_high_value:=greatest(v_first_value,v_second_value);
  if v_gap=0 then
    v_winner:=null;
    v_loser:=null;
    v_gap_cost:=0;
    v_inversion_allowed:=false;
  else
    if v_first_value>v_second_value then
      v_winner:=v_first_player; v_loser:=v_second_player;
      v_winner_choice:=v_first_choice;
    else
      v_winner:=v_second_player; v_loser:=v_first_player;
      v_winner_choice:=v_second_choice;
    end if;
    v_gap_cost:=least(v_gap,(v_points->>v_winner::text)::integer);
    v_opposite_value:=coalesce(
      v_winner_choice#>>'{inverted_resolution,snapshot_value}',
      ''
    );
    v_inversion_allowed:=case when v_opposite_value ~ '^[0-9]+$'
      then v_opposite_value::integer between 1 and 20
      else false end;
  end if;
  v_resolution:=jsonb_build_object(
    'tied',v_gap=0,'winner_player_id',v_winner,'loser_player_id',v_loser,
    'gap',v_gap,'gap_cost',v_gap_cost,'high_value',v_high_value,
    'action_points',v_points,'inversion_allowed',v_inversion_allowed
  );
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'INITIAL_RESOLVE','{}'::jsonb);
  update public.network_rounds set initial_resolution=v_resolution,
    phase=case when v_gap=0 then 'TIE_DECISION' else 'NEGOTIATION_PROPOSAL' end,
    updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

create or replace function public.v4_corruption_compromise(
  p_session_id uuid,p_round_number integer,p_player_id uuid,p_actions jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_proposed record; v_usage jsonb; v_source jsonb; v_result jsonb:='[]'::jsonb;
begin
  if jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions)=0 then
    raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  for v_proposed in select value,ordinality from jsonb_array_elements(p_actions) with ordinality loop
    v_usage:=public.network_usage_projection(v_proposed.value-array['origin','logical_order','source','status','visibility'],true);
    if v_usage->>'owner_player_id' is distinct from p_player_id::text
      or coalesce(v_usage->>'source_usage_id','')=''
      or v_usage->>'usage_id'=v_usage->>'source_usage_id' then
      raise exception 'ROUND_CORRUPTION_FORBIDDEN'; end if;
    select historical.usage into v_source
    from public.network_rounds previous
    cross join lateral (
      select item as usage,0 as priority from jsonb_array_elements(coalesce(previous.final_resolution->'compromise','[]'::jsonb)) item
      union all
      select item,1 from jsonb_array_elements(coalesce(previous.corruption->'actions','[]'::jsonb)) item
        where previous.corruption->>'accepted'='true'
      union all
      select item,1 from jsonb_array_elements(coalesce(previous.recovery_history,'[]'::jsonb)) item
        where item->>'response'='ACCEPT'
      union all
      select reveal.choice_payload,2 from public.network_round_reveals reveal
        where reveal.round_id=previous.id and reveal.player_id=p_player_id
    ) historical
    where previous.session_id=p_session_id and previous.round_number<p_round_number
      and historical.usage->>'owner_player_id'=p_player_id::text
      and historical.usage->>'usage_id'=v_usage->>'source_usage_id'
      and historical.usage->>'concept_id'=v_usage->>'concept_id'
    order by previous.round_number desc,historical.priority limit 1;
    if not found or v_source->'resolved_action' is distinct from v_usage->'resolved_action' then
      raise exception 'ROUND_ACTION_PARAMETERS_MISMATCH'; end if;
    v_result:=v_result||jsonb_build_array(v_usage||jsonb_build_object(
      'origin','CORRUPTION','logical_order',v_proposed.ordinality-1));
  end loop;
  return v_result;
end;
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
    where round_id=p_round_id and player_id=v_loser;
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
    ),phase='FINAL_RESOLVED',updated_at=now() where id=p_round_id;
    return public.network_round_json(p_round_id,p_player_id);
  end if;

  select choice_payload into v_choice from public.network_round_reveals
  where round_id=p_round_id and player_id=v_loser;
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

create or replace function public.adapt_network_negotiation(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_offer jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_response jsonb; v_available integer; v_direct integer;
  v_command public.network_round_commands%rowtype;
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
  if coalesce(v_choice#>>'{native_direction}',v_choice#>>'{resolved_action,direction}','GENERAL')
      <> coalesce(v_choice#>>'{resolved_action,direction}','GENERAL')
    or coalesce(v_choice#>>'{effective_direction}',v_choice#>>'{resolved_action,direction}','GENERAL')
      <> coalesce(v_choice#>>'{resolved_action,direction}','GENERAL') then
    raise exception 'ROUND_DIRECTION_MISMATCH';
  end if;
  if v_inverted and (
      coalesce(v_choice#>>'{resolved_action,direction}','GENERAL') not in ('FAIRE','RECEVOIR')
      or coalesce(v_choice#>>'{inverted_resolution,snapshot_value}','') !~ '^[0-9]+$'
      or (v_choice#>>'{inverted_resolution,snapshot_value}')::integer not between 1 and 20
    ) then raise exception 'ROUND_INVERSION_UNAVAILABLE'; end if;
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
      'concept_id',v_initial_card->>'concept_id','usage_id',v_initial_card->>'usage_id',
      'inverted',v_inverted,'mutual_abandon',false,'compromise',v_cards),
    phase='FINAL_RESOLVED',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

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
          and action->>'usage_id'=proposed->>'usage_id'
          and action->>'status'='COMPLETED'
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
        or coalesce(x->>'usage_id','')='')
    or (select count(distinct x->>'usage_id') from jsonb_array_elements(p_actions) x)
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
        where submitted->>'usage_id'=offered->>'usage_id'
          and submitted->>'concept_id'=offered->>'concept_id'
      )
    ) then raise exception 'ROUND_CORRUPTION_FORBIDDEN'; end if;
  select jsonb_agg(
    offered||jsonb_build_object('status',submitted->>'status')
    order by ordinality
  ) into v_actions
  from jsonb_array_elements(v_round.corruption->'actions')
    with ordinality as original(offered,ordinality)
  join jsonb_array_elements(p_actions) submitted
    on submitted->>'usage_id'=offered->>'usage_id'
   and submitted->>'concept_id'=offered->>'concept_id';
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_RESOLVE',v_payload);
  update public.network_rounds set corruption=jsonb_set(
    corruption,'{actions}',v_actions,true
  ),phase='RECOVERY',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

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

create or replace function public.v4_verified_final_resolution(p_round_id uuid,p_final_resolution jsonb)
returns jsonb language plpgsql set search_path=public as $$
declare v_card jsonb; v_usage jsonb; v_choice jsonb; v_expected jsonb;
begin
  if coalesce((p_final_resolution->>'mutual_abandon')::boolean,false) then
    return jsonb_set(p_final_resolution-array['card_id','variant_id'],'{compromise}','[]'::jsonb,true);
  end if;
  if p_final_resolution is null or jsonb_typeof(p_final_resolution->'compromise')<>'array' then
    raise exception 'ROUND_ACTION_PARAMETERS_MISSING'; end if;
  for v_card in select value from jsonb_array_elements(p_final_resolution->'compromise') loop
    v_usage:=public.network_usage_projection(v_card-array['origin','logical_order'],true);
    if v_card->>'origin'='INITIAL_DUEL' then
      select reveal.choice_payload into v_choice from public.network_round_reveals reveal
      where reveal.round_id=p_round_id and reveal.player_id::text=v_usage->>'owner_player_id'
        and reveal.choice_payload->>'usage_id'=v_usage->>'usage_id';
      if not found then raise exception 'ROUND_ACTION_IDENTITY_MISMATCH'; end if;
      v_expected:=public.network_usage_resolution(v_choice,coalesce((p_final_resolution->>'inverted')::boolean,false));
      if v_usage->>'concept_id' is distinct from v_expected->>'concept_id'
        or v_usage->>'native_direction' is distinct from v_expected->>'native_direction'
        or v_usage->>'effective_direction' is distinct from v_expected->>'effective_direction'
        or v_usage->'resolved_action' is distinct from v_expected->'resolved_action' then
        raise exception 'ROUND_ACTION_IDENTITY_MISMATCH'; end if;
    elsif v_card->>'origin' not in ('AUCTION','CORRUPTION','RECOVERY') then
      raise exception 'ROUND_ACTION_PARAMETERS_MISSING';
    end if;
  end loop;
  return p_final_resolution;
end;
$$;

create or replace function public.publish_v4_action_projection(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_command_id text,
  p_projection jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_required text;
  v_verified jsonb;
  v_card jsonb;
  v_projection_card jsonb;
  v_expected_targets jsonb;
  v_card_index integer := 0;
begin
  if auth.uid() is null or auth.uid() <> p_player_id
    or not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if jsonb_typeof(p_projection->'cards') <> 'array'
    or jsonb_typeof(p_projection->'required_clothing_player_ids') <> 'array'
    or p_projection::text ~* '"(pa|preferences|personal_value|opposite_personal_value)"[[:space:]]*:' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  for v_required in
    select jsonb_array_elements_text(p_projection->'required_clothing_player_ids')
  loop
    if not exists(select 1 from public.session_players
      where session_id=p_session_id and user_id=v_required::uuid) then
      raise exception 'ROUND_INVALID_ARGUMENT';
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text, 0));
  select * into v_command from public.network_round_commands
  where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'PUBLISH_V4_ACTION'
      or v_command.command_payload is distinct from p_projection then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'FINAL_RESOLVED' then raise exception 'ROUND_INVALID_PHASE'; end if;
  v_verified := public.v4_verified_final_resolution(
    p_round_id,
    v_round.final_resolution
  );
  if v_verified is distinct from v_round.final_resolution then
    update public.network_rounds set final_resolution=v_verified,updated_at=now()
    where id=p_round_id;
  end if;
  if jsonb_array_length(p_projection->'cards') <>
    jsonb_array_length(v_verified->'compromise') then
    raise exception 'ROUND_ACTION_PROJECTION_MISMATCH';
  end if;
  for v_card in
    select value from jsonb_array_elements(v_verified->'compromise')
  loop
    v_projection_card := p_projection->'cards'->v_card_index;
    perform public.network_usage_projection(v_projection_card,false);
    if v_projection_card->>'usage_id' is distinct from v_card->>'usage_id'
      or v_projection_card->>'concept_id' is distinct from v_card->>'concept_id'
      or v_projection_card->'resolved_action' is distinct from v_card->'resolved_action'
 then
      raise exception 'ROUND_ACTION_PROJECTION_MISMATCH';
    end if;
    v_card_index := v_card_index + 1;
  end loop;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'PUBLISH_V4_ACTION',p_projection);
  update public.network_rounds set
    v4_action_projection=coalesce(v4_action_projection,p_projection),updated_at=now()
  where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

create or replace function public.route_network_post_duel() returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_payer uuid;
  v_cost integer;
  v_current integer;
  v_actions jsonb;
  v_action jsonb;
  v_owner text;
  v_occurrence text;
begin
  if old.phase='COUNTER_DECISION' and new.phase='FINAL_RESOLVED'
    and old.counter_bid is null then
    v_payer:=coalesce(
      (new.final_resolution->>'final_winner_player_id')::uuid,
      (new.final_resolution->>'retained_player_id')::uuid
    );
    v_cost:=coalesce((old.initial_resolution->>'gap_cost')::integer,0);
    select (action_points->>v_payer::text)::integer into v_current
    from public.network_game_states
    where session_id=new.session_id for update;
    v_cost:=least(v_cost,v_current);
    update public.network_game_states set
      action_points=jsonb_set(
        action_points,array[v_payer::text],to_jsonb(v_current-v_cost)
      ),
      updated_at=now()
    where session_id=new.session_id;
  end if;

  if old.phase='READY' and new.phase='NEGOTIATION_PROPOSAL' then
    new.phase:='COUNTER_DECISION';
  elsif new.phase='FINAL_RESOLVED' and old.phase in (
    'COUNTER_DECISION','FINAL_DEFENSE_DECISION','TIE_DECISION'
  ) then
    new.phase:=case when new.final_resolution->>'retained_player_id' is null
      then 'RECOVERY' else 'CORRUPTION_DECISION' end;
  elsif old.phase in ('FINAL_RESOLVED','RECOVERY')
    and new.phase='WAITING_NEXT' then
    if (old.corruption->>'accepted')::boolean then
      select jsonb_agg(
        action||jsonb_build_object('status','COMPLETED') order by ordinality
      ) into v_actions
      from jsonb_array_elements(old.corruption->'actions')
        with ordinality as item(action,ordinality);
      new.corruption:=jsonb_set(old.corruption,'{actions}',v_actions,true);
    end if;
    if (old.negotiation#>>'{response,accepted}')::boolean then
      for v_action in
        select value from jsonb_array_elements(coalesce(
          old.final_resolution->'compromise','[]'::jsonb
        )) where value->>'origin'='AUCTION'
      loop
        v_owner:=v_action->>'owner_player_id';
        v_occurrence:=v_action->>'usage_id';
        if coalesce(v_owner,'')='' or coalesce(v_occurrence,'')='' then
          raise exception 'ROUND_NEGOTIATION_INVALID';
        end if;
        update public.network_game_states set
          v4_consumed_occurrences=jsonb_set(
            v4_consumed_occurrences,array[v_owner],
            case when coalesce(
              v4_consumed_occurrences->v_owner,'[]'::jsonb
            ) ? v_occurrence then coalesce(
              v4_consumed_occurrences->v_owner,'[]'::jsonb
            ) else coalesce(
              v4_consumed_occurrences->v_owner,'[]'::jsonb
            )||jsonb_build_array(v_occurrence) end,
            true
          ),updated_at=now()
        where session_id=new.session_id;
      end loop;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.v4_advance_persistent_effects(
  p_active jsonb,
  p_cards jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_active jsonb:=coalesce(p_active,'[]'::jsonb);
  v_card jsonb;
  v_target text;
  v_duration integer;
begin
  if jsonb_typeof(v_active)<>'array' or jsonb_typeof(p_cards)<>'array' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  for v_card in
    select value
    from jsonb_array_elements(p_cards) with ordinality
    order by ordinality
  loop
    -- Every projected card is one executed action. Existing effects tick
    -- before a possible new effect is installed, so activation does not
    -- consume its own duration.
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'card_id',effect->>'card_id',
        'target_player_id',effect->>'target_player_id',
        'remaining_actions',(effect->>'remaining_actions')::integer-1
      ) order by effect->>'card_id',effect->>'target_player_id'
    ),'[]'::jsonb)
    into v_active
    from jsonb_array_elements(v_active) effect
    where (effect->>'remaining_actions')::integer>1;

    v_duration:=(v_card#>>'{resolved_action,parameters,duration_actions}')::integer;
    if v_duration is not null then
      for v_target in
        select jsonb_array_elements_text(coalesce(
          v_card#>'{resolved_action,target_player_ids}','[]'::jsonb
        ))
      loop
        select coalesce(jsonb_agg(effect order by
          effect->>'card_id',effect->>'target_player_id'
        ),'[]'::jsonb)
        into v_active
        from jsonb_array_elements(v_active) effect
        where effect->>'card_id' is distinct from v_card->>'concept_id'
          or effect->>'target_player_id' is distinct from v_target;
        v_active:=v_active||jsonb_build_array(jsonb_build_object(
          'card_id',v_card->>'concept_id',
          'target_player_id',v_target,
          'remaining_actions',v_duration
        ));
      end loop;
    end if;
  end loop;
  return v_active;
end;
$$;

create or replace function public.continue_network_deck_cycle(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_choice text,
  p_adjustment jsonb,
  p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_payload jsonb;
  v_cycle integer;
  v_expected integer;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if p_choice in ('NEW_GAME','FINISH') then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  if p_choice not in (
    'CONTINUE_SPICIER','CONTINUE_INTENABLE','INFINITE'
  ) or jsonb_typeof(p_adjustment) is distinct from 'object'
    or coalesce(p_adjustment->>'expected_cycle','') !~ '^[1-9][0-9]{0,8}$' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_expected:=(p_adjustment->>'expected_cycle')::integer;
  v_payload := jsonb_build_object(
    'choice', p_choice, 'adjustment', p_adjustment
  );
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text, 0));

  select * into v_command from public.network_round_commands
  where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id
      or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id
      or v_command.kind <> 'CONTINUE_CYCLE'
      or v_command.command_payload is distinct from v_payload then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.get_current_network_game_round(p_session_id, p_player_id);
  end if;

  select deck_cycle into v_cycle from public.network_game_states where session_id=p_session_id for update;
  if not found or v_expected>v_cycle then raise exception 'ROUND_CYCLE_MISMATCH'; end if;
  if v_expected<v_cycle then
    insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
      values(p_command_id,p_session_id,p_round_id,p_player_id,'CONTINUE_CYCLE',v_payload);
    return public.get_current_network_game_round(p_session_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds
  where id = p_round_id and session_id = p_session_id for update;
  if not found then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase <> 'WAITING_NEXT' then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  if not exists(
    select 1 from public.network_game_states
    where session_id = p_session_id and cycle_exhausted is true
  ) then
    raise exception 'ROUND_CYCLE_NOT_EXHAUSTED';
  end if;

  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values (
    p_command_id,p_session_id,p_round_id,p_player_id,
    'CONTINUE_CYCLE',v_payload
  );
  update public.network_game_states set
    deck_cycle = deck_cycle + 1,
    deck_style = case
      when p_choice = 'CONTINUE_INTENABLE' then 'INTENABLE'
      when p_choice = 'CONTINUE_SPICIER' and deck_style = 'SOFT' then 'EPICE'
      when p_choice = 'CONTINUE_SPICIER' then 'INTENABLE'
      else deck_style end,
    infinite_mode = case
      when p_choice = 'INFINITE' then true else infinite_mode end,
    deck_adjustment = '{}'::jsonb,
    cycle_exhausted = false,
    v4_consumed_occurrences = '{}'::jsonb,
    updated_at = now()
  where session_id = p_session_id;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

revoke all on function public.network_usage_action(jsonb) from public,anon,authenticated;
revoke all on function public.network_usage_projection(jsonb,boolean) from public,anon,authenticated;
revoke all on function public.network_usage_resolution(jsonb,boolean) from public,anon,authenticated;


create or replace function public.submit_network_tie_decision(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_decision text,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_other uuid;
  v_decisions jsonb;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text, 0));
  select * into v_command from public.network_round_commands where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id or v_command.kind <> 'TIE_DECISION'
      or v_command.command_payload is distinct from jsonb_build_object('decision', p_decision) then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(v_command.round_id, p_player_id);
  end if;
  select * into v_round from public.network_rounds where id = p_round_id for update;
  if not found or v_round.session_id <> p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase <> 'TIE_DECISION' then raise exception 'ROUND_INVALID_PHASE'; end if;
  select user_id into v_other from public.session_players
  where session_id = p_session_id and user_id <> p_player_id;
  insert into public.network_round_commands(
    command_id, session_id, round_id, player_id, kind, command_payload
  ) values (
    p_command_id, p_session_id, p_round_id, p_player_id, 'TIE_DECISION',
    jsonb_build_object('decision', p_decision)
  );
  if p_decision = 'CONCEDE' then
    update public.network_rounds
    set tie_decisions = jsonb_set(tie_decisions, array[p_player_id::text], '"concede"'::jsonb),
        final_resolution = public.network_final_choice(p_round_id, v_other, v_other, false),
        phase = 'FINAL_RESOLVED', updated_at = now()
    where id = p_round_id;
  elsif p_decision = 'ABANDON' then
    v_decisions := jsonb_set(v_round.tie_decisions, array[p_player_id::text], '"abandon"'::jsonb);
    update public.network_rounds
    set tie_decisions = v_decisions,
        final_resolution = case when (select count(*) from jsonb_object_keys(v_decisions)) = 2 then
          jsonb_build_object(
            'retained_player_id', null,
            'concept_id', null,
            'usage_id', null,
            'inverted', false,
            'mutual_abandon', true,
            'compromise', '[]'::jsonb
          ) else final_resolution end,
        phase = case when (select count(*) from jsonb_object_keys(v_decisions)) = 2 then 'FINAL_RESOLVED' else phase end,
        updated_at = now()
    where id = p_round_id;
  else raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;
