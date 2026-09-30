-- Depends on 202609300001_network_multiround_auction.sql.
-- Public state contains only the action explicitly offered/executed. Hands,
-- locks, profiles, preferences and draw history remain client-private.

alter table public.network_rounds drop constraint network_rounds_phase_check;
alter table public.network_rounds add constraint network_rounds_phase_check check (phase in (
  'COMMIT', 'REVEAL', 'READY', 'COUNTER_DECISION',
  'FINAL_DEFENSE_DECISION', 'TIE_DECISION', 'FINAL_RESOLVED',
  'CORRUPTION_DECISION', 'CORRUPTION_RESPONSE', 'CORRUPTION_EXECUTION',
  'RECOVERY', 'RECOVERY_RESPONSE', 'RECOVERY_EXECUTION', 'WAITING_NEXT', 'CLOSED'
));

alter table public.network_rounds
  add column corruption jsonb,
  add column recovery_by_player jsonb not null default '{}'::jsonb
    check (jsonb_typeof(recovery_by_player) = 'object'),
  add column recovery_done jsonb not null default '{}'::jsonb
    check (jsonb_typeof(recovery_done) = 'object');

alter table public.network_round_commands drop constraint network_round_commands_kind_check;
alter table public.network_round_commands add constraint network_round_commands_kind_check check (kind in (
  'CREATE', 'OPEN', 'COMMIT', 'REVEAL', 'INITIAL_RESOLVE',
  'COUNTER_DECISION', 'FINAL_DEFENSE', 'TIE_DECISION', 'READY_NEXT',
  'CORRUPTION_OFFER', 'CORRUPTION_RESPONSE', 'CORRUPTION_RESOLVE',
  'CORRUPTION_SKIP', 'RECOVERY', 'RECOVERY_RESPONSE', 'RECOVERY_RESOLVE', 'RECOVERY_SKIP'
));

create or replace function public.network_round_json(p_round_id uuid, p_requester uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'schema_version', 1, 'round_id', r.id, 'session_id', r.session_id,
    'session_round', r.round_key, 'round_number', r.round_number,
    'phase', r.phase, 'player_id', p_requester, 'action_points', g.action_points,
    'commits', coalesce((select jsonb_object_agg(c.player_id::text, c.digest)
      from public.network_round_commits c where c.round_id = r.id), '{}'::jsonb),
    'own_reveal', (select jsonb_build_object(
      'schema_version', 1, 'session_round', r.round_key, 'player_id', v.player_id,
      'choice', v.choice_payload, 'nonce', v.nonce)
      from public.network_round_reveals v
      where v.round_id = r.id and v.player_id = p_requester),
    'opponent_reveal', case when r.phase = 'READY' then (select jsonb_build_object(
      'schema_version', 1, 'session_round', r.round_key, 'player_id', v.player_id,
      'choice', v.choice_payload, 'nonce', v.nonce)
      from public.network_round_reveals v
      where v.round_id = r.id and v.player_id <> p_requester) else null end,
    'initial_resolution', r.initial_resolution, 'counter_bid', r.counter_bid,
    'final_defense', r.final_defense, 'final_resolution', r.final_resolution,
    'ready_next', r.ready_next, 'tie_decisions', r.tie_decisions,
    'corruption', r.corruption, 'recovery_by_player', r.recovery_by_player,
    'recovery_done', r.recovery_done
  ) from public.network_rounds r
  join public.network_game_states g on g.session_id = r.session_id
  where r.id = p_round_id;
$$;

create function public.route_network_post_duel() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.phase = 'FINAL_RESOLVED'
    and old.phase in ('COUNTER_DECISION', 'FINAL_DEFENSE_DECISION', 'TIE_DECISION') then
    new.phase := case when new.final_resolution->>'retained_player_id' is null
      then 'RECOVERY' else 'CORRUPTION_DECISION' end;
  end if;
  return new;
end;
$$;

create trigger route_network_post_duel_before_update
before update on public.network_rounds for each row execute function public.route_network_post_duel();

create function public.submit_network_corruption_offer(
  p_session_id uuid, p_round_id uuid, p_player_id uuid, p_objective text,
  p_card_ids jsonb, p_command_id text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_actor uuid; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_objective not in ('OWN_INITIAL_ACTION', 'INVERT_WINNING_ACTION')
    or jsonb_typeof(p_card_ids) <> 'array' or jsonb_array_length(p_card_ids) = 0
    or exists (select 1 from jsonb_array_elements(p_card_ids) x where jsonb_typeof(x) <> 'string')
    then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  v_payload := jsonb_build_object('objective', p_objective, 'card_ids', p_card_ids);
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text, 0));
  select * into v_command from public.network_round_commands where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id or v_command.kind <> 'CORRUPTION_OFFER'
      or v_command.command_payload is distinct from v_payload then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id, p_player_id);
  end if;
  select * into v_round from public.network_rounds where id = p_round_id for update;
  if not found or v_round.session_id <> p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase <> 'CORRUPTION_DECISION' then raise exception 'ROUND_INVALID_PHASE'; end if;
  select user_id into v_actor from public.session_players where session_id = p_session_id
    and user_id::text <> v_round.final_resolution->>'retained_player_id';
  if p_player_id <> v_actor then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  if exists (
    select 1 from jsonb_array_elements_text(p_card_ids) proposed(card_id)
    where not exists (
      select 1 from public.network_round_reveals reveal
      join public.network_rounds previous on previous.id=reveal.round_id
      where previous.session_id=p_session_id and previous.round_number<v_round.round_number
        and reveal.player_id=p_player_id and reveal.choice_payload->>'card_id'=proposed.card_id
    ) or exists (
      select 1 from public.network_rounds previous,
        jsonb_array_elements(coalesce(previous.corruption->'actions','[]'::jsonb)) action
      where previous.session_id=p_session_id and previous.round_number<v_round.round_number
        and previous.corruption->>'offered_by'=p_player_id::text
        and action->>'card_id'=proposed.card_id and action->>'status'='COMPLETED'
    )
  ) then raise exception 'ROUND_CORRUPTION_FORBIDDEN'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_OFFER',v_payload);
  update public.network_rounds set corruption = jsonb_build_object(
    'offered_by',p_player_id,'objective',p_objective,'accepted',null,
    'actions',(select jsonb_agg(jsonb_build_object('card_id',x#>>'{}','source','DISCARD',
      'status','PROPOSED','visibility','VISIBLE')) from jsonb_array_elements(p_card_ids) x)),
    phase='CORRUPTION_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create function public.respond_network_corruption(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_accepted boolean,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  v_payload:=jsonb_build_object('accepted',p_accepted); perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'CORRUPTION_RESPONSE' or v_command.command_payload is distinct from v_payload
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'CORRUPTION_RESPONSE' then raise exception 'ROUND_INVALID_PHASE'; end if;
  if v_round.corruption->>'offered_by'=p_player_id::text then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_RESPONSE',v_payload);
  update public.network_rounds set corruption=jsonb_set(corruption,'{accepted}',to_jsonb(p_accepted)),
    phase=case when p_accepted then 'CORRUPTION_EXECUTION' else 'RECOVERY' end,updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create function public.resolve_network_corruption(
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
  if v_round.phase<>'CORRUPTION_EXECUTION' or v_round.corruption->>'offered_by'<>p_player_id::text
    or (select array_agg(x->>'card_id' order by x->>'card_id') from jsonb_array_elements(p_actions)x)
       is distinct from (select array_agg(x->>'card_id' order by x->>'card_id') from jsonb_array_elements(v_round.corruption->'actions')x)
    then raise exception 'ROUND_CORRUPTION_FORBIDDEN'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_RESOLVE',v_payload);
  update public.network_rounds set corruption=jsonb_set(corruption,'{actions}',p_actions),phase='RECOVERY',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create function public.skip_network_corruption(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_actor uuid;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0)); select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id or v_command.kind<>'CORRUPTION_SKIP'
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if; return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  select user_id into v_actor from public.session_players where session_id=p_session_id and user_id::text<>v_round.final_resolution->>'retained_player_id';
  if v_round.phase<>'CORRUPTION_DECISION' or p_player_id<>v_actor then raise exception 'ROUND_CORRUPTION_FORBIDDEN'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind) values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_SKIP');
  update public.network_rounds set phase='RECOVERY',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create function public.submit_network_recovery(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_recovery jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_points jsonb; v_current integer; v_gain integer; v_done jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_recovery->>'player_id'<>p_player_id::text or p_recovery->>'source' not in ('HAND','DISCARD','CATALOG')
    or (p_recovery->>'gain')::integer not between 0 and 20
    or (p_recovery->>'completed')::boolean or p_recovery->>'response' is not null
    then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0)); select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'RECOVERY' or v_command.command_payload is distinct from p_recovery then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  select action_points into v_points from public.network_game_states where session_id=p_session_id for update;
  v_current:=(v_points->>p_player_id::text)::integer; v_gain:=(p_recovery->>'gain')::integer;
  if v_round.phase<>'RECOVERY' or v_round.recovery_done ? p_player_id::text or v_current>20 then raise exception 'ROUND_RECOVERY_NOT_ELIGIBLE'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY',p_recovery);
  update public.network_rounds set recovery_by_player=jsonb_set(recovery_by_player,array[p_player_id::text],p_recovery),
    phase='RECOVERY_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create function public.respond_network_recovery(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_response text,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_proposer text; v_payload jsonb; v_done jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_response not in ('ACCEPT','REFUSE') then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  v_payload:=jsonb_build_object('response',p_response); perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'RECOVERY_RESPONSE' or v_command.command_payload is distinct from v_payload then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  select key into v_proposer from jsonb_each(v_round.recovery_by_player) item
    where not (v_round.recovery_done ? item.key) limit 1;
  if v_round.phase<>'RECOVERY_RESPONSE' or v_proposer is null or v_proposer=p_player_id::text then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY_RESPONSE',v_payload);
  update public.network_rounds set recovery_by_player=jsonb_set(recovery_by_player,array[v_proposer,'response'],to_jsonb(p_response)) where id=p_round_id;
  if p_response='REFUSE' then
    v_done:=jsonb_set(v_round.recovery_done,array[v_proposer],'true'::jsonb);
    update public.network_rounds set recovery_done=v_done,
      phase=case when (select count(*) from jsonb_object_keys(v_done))=2 then 'FINAL_RESOLVED' else 'RECOVERY' end,updated_at=now() where id=p_round_id;
  else update public.network_rounds set phase='RECOVERY_EXECUTION',updated_at=now() where id=p_round_id; end if;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create function public.resolve_network_recovery(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_recovery jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_points jsonb; v_current integer; v_gain integer; v_done jsonb; v_existing jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_recovery->>'player_id'<>p_player_id::text or p_recovery->>'response'<>'ACCEPT'
    or p_recovery->>'source' not in ('HAND','DISCARD','CATALOG') or (p_recovery->>'gain')::integer not between 0 and 20
    or (not (p_recovery->>'completed')::boolean and (p_recovery->>'gain')::integer<>0) then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0)); select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'RECOVERY_RESOLVE' or v_command.command_payload is distinct from p_recovery then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update; v_existing:=v_round.recovery_by_player->p_player_id::text;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'RECOVERY_EXECUTION' or v_round.recovery_done ? p_player_id::text
    or v_existing->>'card_id'<>p_recovery->>'card_id' or v_existing->>'variant_id'<>p_recovery->>'variant_id'
    or v_existing->>'source'<>p_recovery->>'source' then raise exception 'ROUND_RECOVERY_NOT_ELIGIBLE'; end if;
  select action_points into v_points from public.network_game_states where session_id=p_session_id for update;
  v_current:=(v_points->>p_player_id::text)::integer; v_gain:=(p_recovery->>'gain')::integer;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY_RESOLVE',p_recovery);
  update public.network_game_states set action_points=jsonb_set(v_points,array[p_player_id::text],to_jsonb(v_current+v_gain)),updated_at=now() where session_id=p_session_id;
  v_done:=jsonb_set(v_round.recovery_done,array[p_player_id::text],'true'::jsonb);
  update public.network_rounds set recovery_by_player=jsonb_set(recovery_by_player,array[p_player_id::text],p_recovery),recovery_done=v_done,
    phase=case when (select count(*) from jsonb_object_keys(v_done))=2 then 'FINAL_RESOLVED' else 'RECOVERY' end,updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create function public.skip_network_recovery(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_done jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0)); select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id or v_command.kind<>'RECOVERY_SKIP'
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if; return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'RECOVERY' or v_round.recovery_done ? p_player_id::text then raise exception 'ROUND_INVALID_PHASE'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind) values(p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY_SKIP');
  v_done:=jsonb_set(v_round.recovery_done,array[p_player_id::text],'true'::jsonb);
  update public.network_rounds set recovery_done=v_done,phase=case when (select count(*) from jsonb_object_keys(v_done))=2 then 'FINAL_RESOLVED' else 'RECOVERY' end,updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

revoke all on function public.route_network_post_duel() from public;
revoke all on function public.submit_network_corruption_offer(uuid,uuid,uuid,text,jsonb,text) from public;
revoke all on function public.respond_network_corruption(uuid,uuid,uuid,boolean,text) from public;
revoke all on function public.resolve_network_corruption(uuid,uuid,uuid,jsonb,text) from public;
revoke all on function public.skip_network_corruption(uuid,uuid,uuid,text) from public;
revoke all on function public.submit_network_recovery(uuid,uuid,uuid,jsonb,text) from public;
revoke all on function public.respond_network_recovery(uuid,uuid,uuid,text,text) from public;
revoke all on function public.resolve_network_recovery(uuid,uuid,uuid,jsonb,text) from public;
revoke all on function public.skip_network_recovery(uuid,uuid,uuid,text) from public;
grant execute on function public.submit_network_corruption_offer(uuid,uuid,uuid,text,jsonb,text) to authenticated;
grant execute on function public.respond_network_corruption(uuid,uuid,uuid,boolean,text) to authenticated;
grant execute on function public.resolve_network_corruption(uuid,uuid,uuid,jsonb,text) to authenticated;
grant execute on function public.skip_network_corruption(uuid,uuid,uuid,text) to authenticated;
grant execute on function public.submit_network_recovery(uuid,uuid,uuid,jsonb,text) to authenticated;
grant execute on function public.respond_network_recovery(uuid,uuid,uuid,text,text) to authenticated;
grant execute on function public.resolve_network_recovery(uuid,uuid,uuid,jsonb,text) to authenticated;
grant execute on function public.skip_network_recovery(uuid,uuid,uuid,text) to authenticated;
