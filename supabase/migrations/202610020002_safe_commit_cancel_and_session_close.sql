-- Safe pre-reveal cancellation and definitive voluntary session closure.

alter table public.network_rounds drop constraint network_rounds_phase_check;
alter table public.network_rounds add constraint network_rounds_phase_check check (phase in (
  'COMMIT','REVEAL','READY','NEGOTIATION_PROPOSAL','NEGOTIATION_RESPONSE',
  'NEGOTIATION_ADAPTATION','NEGOTIATION_VALIDATION','COUNTER_DECISION',
  'FINAL_DEFENSE_DECISION','TIE_DECISION','FINAL_RESOLVED',
  'CORRUPTION_DECISION','CORRUPTION_RESPONSE','CORRUPTION_EXECUTION',
  'RECOVERY','RECOVERY_RESPONSE','RECOVERY_EXECUTION','WAITING_NEXT','CLOSED',
  'SESSION_CLOSED'
));

alter table public.network_round_commands drop constraint network_round_commands_kind_check;
alter table public.network_round_commands add constraint network_round_commands_kind_check check (kind in (
  'CREATE','OPEN','COMMIT','CANCEL_COMMIT','REVEAL','INITIAL_RESOLVE',
  'NEGOTIATION_PROPOSAL','NEGOTIATION_RESPONSE','NEGOTIATION_ADAPTATION','NEGOTIATION_VALIDATION',
  'SET_ORIENTATION','CONTINUE_CYCLE','COUNTER_DECISION','FINAL_DEFENSE','TIE_DECISION','READY_NEXT',
  'CORRUPTION_OFFER','CORRUPTION_RESPONSE','CORRUPTION_RESOLVE','CORRUPTION_SKIP',
  'RECOVERY','RECOVERY_RESPONSE','RECOVERY_RESOLVE','RECOVERY_SKIP','CLOSE_SESSION'
));

create function public.cancel_network_round_commit(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'CANCEL_COMMIT'
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'COMMIT' then raise exception 'ROUND_CANCEL_CLOSED'; end if;
  if not exists(select 1 from public.network_round_commits where round_id=p_round_id and player_id=p_player_id)
    then raise exception 'ROUND_COMMIT_MISSING'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'CANCEL_COMMIT');
  delete from public.network_round_commits where round_id=p_round_id and player_id=p_player_id;
  update public.network_rounds set updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;
revoke all on function public.cancel_network_round_commit(uuid,uuid,uuid,text) from public;
grant execute on function public.cancel_network_round_commit(uuid,uuid,uuid,text) to authenticated;

create function public.close_network_game_session(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.player_id<>p_player_id
      or v_command.kind<>'CLOSE_SESSION' then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'CLOSE_SESSION');
  update public.game_sessions set status='closed',updated_at=now() where id=p_session_id;
  update public.network_rounds set phase='SESSION_CLOSED',updated_at=now()
    where session_id=p_session_id and phase<>'SESSION_CLOSED';
  return public.network_round_json(p_round_id,p_player_id);
end; $$;
revoke all on function public.close_network_game_session(uuid,uuid,uuid,text) from public;
grant execute on function public.close_network_game_session(uuid,uuid,uuid,text) to authenticated;
