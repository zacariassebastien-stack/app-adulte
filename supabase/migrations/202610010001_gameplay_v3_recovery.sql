-- Gameplay V3 recovery: fixed threshold is 10% of the initial 100 PA.
-- The client computes ceil(personal value * 1.5); the public proposal keeps gain=0.

create or replace function public.submit_network_recovery(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_recovery jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_points jsonb; v_current integer; v_gain integer; v_done jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_recovery->>'player_id'<>p_player_id::text or p_recovery->>'source' not in ('HAND','DISCARD','CATALOG')
    or (p_recovery->>'gain')::integer not between 0 and 30
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
  if v_round.phase<>'RECOVERY' or v_round.recovery_done ? p_player_id::text or v_current>10 then raise exception 'ROUND_RECOVERY_NOT_ELIGIBLE'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY',p_recovery);
  update public.network_rounds set recovery_by_player=jsonb_set(recovery_by_player,array[p_player_id::text],p_recovery),
    phase='RECOVERY_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;


create or replace function public.resolve_network_recovery(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_recovery jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_points jsonb; v_current integer; v_gain integer; v_done jsonb; v_existing jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_recovery->>'player_id'<>p_player_id::text or p_recovery->>'response'<>'ACCEPT'
    or p_recovery->>'source' not in ('HAND','DISCARD','CATALOG') or (p_recovery->>'gain')::integer not between 0 and 30
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


