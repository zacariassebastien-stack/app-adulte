-- Prevent SECURITY DEFINER helpers from returning a round that does not belong
-- to the authenticated member's session. Keep this check before idempotent
-- command replay so a known command id cannot bypass the binding.

create or replace function public.set_network_hybrid_orientation(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_orientation text,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_orientation not in ('FACE_TO_FACE','DISTANCE') then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  v_payload:=jsonb_build_object('orientation',p_orientation);
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text,0));
  select * into v_round from public.network_rounds
    where id=p_round_id and session_id=p_session_id for update;
  if not found then raise exception 'ROUND_NOT_FOUND'; end if;
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'SET_ORIENTATION'
      or v_command.command_payload is distinct from v_payload
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'SET_ORIENTATION',v_payload);
  update public.network_game_states set hybrid_orientation=p_orientation,updated_at=now()
    where session_id=p_session_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.continue_network_deck_cycle(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_choice text,
  p_adjustment jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if not exists(select 1 from public.session_players
    where session_id=p_session_id and user_id=p_player_id and role='PLAYER_1')
    then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  if p_choice not in ('CONTINUE_SPICIER','CONTINUE_INTENABLE','INFINITE','NEW_GAME','FINISH')
    or jsonb_typeof(p_adjustment)<>'object' then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  v_payload:=jsonb_build_object('choice',p_choice,'adjustment',p_adjustment);
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text,0));
  select * into v_round from public.network_rounds
    where id=p_round_id and session_id=p_session_id for update;
  if not found then raise exception 'ROUND_NOT_FOUND'; end if;
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'CONTINUE_CYCLE'
      or v_command.command_payload is distinct from v_payload
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'CONTINUE_CYCLE',v_payload);
  update public.network_game_states set
    deck_cycle=case when p_choice in ('CONTINUE_SPICIER','CONTINUE_INTENABLE','INFINITE') then deck_cycle+1 else deck_cycle end,
    deck_style=case
      when p_choice='CONTINUE_INTENABLE' then 'INTENABLE'
      when p_choice='CONTINUE_SPICIER' and deck_style='SOFT' then 'EPICE'
      when p_choice='CONTINUE_SPICIER' then 'INTENABLE'
      else deck_style end,
    infinite_mode=case when p_choice='INFINITE' then true else infinite_mode end,
    deck_adjustment=p_adjustment,updated_at=now() where session_id=p_session_id;
  if p_choice in ('NEW_GAME','FINISH') then
    update public.game_sessions set status='closed' where id=p_session_id;
  end if;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

revoke all on function public.set_network_hybrid_orientation(uuid,uuid,uuid,text,text) from public;
revoke all on function public.continue_network_deck_cycle(uuid,uuid,uuid,text,jsonb,text) from public;
grant execute on function public.set_network_hybrid_orientation(uuid,uuid,uuid,text,text) to authenticated;
grant execute on function public.continue_network_deck_cycle(uuid,uuid,uuid,text,jsonb,text) to authenticated;
