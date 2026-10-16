-- Either session member may advance a normal WAITING_NEXT boundary. The
-- advisory lock and unique round number keep creation singular; a concurrent
-- caller observing the old round already closed receives the canonical round.
drop function if exists public.ready_network_next_round(uuid, uuid, uuid, text);
drop function if exists public.ready_network_next_round(uuid, uuid, uuid, text, boolean);
drop function if exists public.ready_network_next_round(uuid, uuid, uuid, text, boolean, integer);
create function public.ready_network_next_round(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_command_id text,
  p_no_playable_occurrences boolean default false,
  p_clothing_count integer default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_ready jsonb;
  v_next_id uuid;
  v_next_number integer;
  v_payload jsonb;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text, 0));
  v_payload := jsonb_build_object(
    'no_playable_occurrences', p_no_playable_occurrences,
    'clothing_count', p_clothing_count
  );
  select * into v_command
  from public.network_round_commands
  where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id
      or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id
      or v_command.kind <> 'READY_NEXT'
      or v_command.command_payload is distinct from v_payload then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.get_current_network_game_round(p_session_id, p_player_id);
  end if;

  select * into v_round
  from public.network_rounds
  where id = p_round_id
  for update;
  if not found or v_round.session_id <> p_session_id then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase = 'CLOSED' and exists(
    select 1
    from public.network_game_states state
    where state.session_id = p_session_id
      and state.current_round_number > v_round.round_number
  ) then
    insert into public.network_round_commands(
      command_id, session_id, round_id, player_id, kind, command_payload
    ) values (
      p_command_id, p_session_id, p_round_id, p_player_id, 'READY_NEXT', v_payload
    );
    return public.get_current_network_game_round(p_session_id, p_player_id);
  end if;
  if v_round.phase not in ('FINAL_RESOLVED', 'WAITING_NEXT') then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  if p_clothing_count is not null and p_clothing_count < 0 then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  if v_round.phase = 'WAITING_NEXT' and exists(
    select 1 from public.network_game_states
    where session_id = p_session_id and cycle_exhausted
  ) then
    raise exception 'ROUND_CYCLE_EXHAUSTED';
  end if;

  insert into public.network_round_commands(
    command_id, session_id, round_id, player_id, kind, command_payload
  ) values (
    p_command_id, p_session_id, p_round_id, p_player_id, 'READY_NEXT', v_payload
  );
  v_ready := jsonb_set(
    v_round.ready_next,
    array[p_player_id::text],
    'true'::jsonb
  );
  if v_round.phase = 'FINAL_RESOLVED' then
    if coalesce(v_round.v4_action_projection->'required_clothing_player_ids','[]'::jsonb)
        ? p_player_id::text then
      if p_clothing_count is null or p_clothing_count < 0 then
        raise exception 'ROUND_CLOTHING_RESYNC_REQUIRED';
      end if;
      update public.session_players set v4_clothing_count=p_clothing_count
      where session_id=p_session_id and user_id=p_player_id;
      update public.network_rounds set v4_clothing_resynced=jsonb_set(
        v4_clothing_resynced,array[p_player_id::text],'true'::jsonb
      ) where id=p_round_id returning v4_clothing_resynced into v_ready;
    end if;
    if p_no_playable_occurrences then
      update public.network_game_states
      set cycle_exhausted = true, updated_at = now()
      where session_id = p_session_id;
    end if;
    select ready_next into v_ready from public.network_rounds where id=p_round_id;
    v_ready := jsonb_set(v_ready,array[p_player_id::text],'true'::jsonb);
    update public.network_rounds
    set ready_next = v_ready,
        phase = case
          when not exists(
            select 1 from jsonb_array_elements_text(coalesce(
              v4_action_projection->'required_clothing_player_ids','[]'::jsonb
            )) required(id)
            where not (v4_clothing_resynced ? required.id)
          ) and not exists(
            select 1 from public.session_players participant
            where participant.session_id = p_session_id
              and not (v_ready ? participant.user_id::text)
          ) then 'WAITING_NEXT'
          else 'FINAL_RESOLVED'
        end,
        updated_at = now()
    where id = p_round_id;
    return public.network_round_json(p_round_id, p_player_id);
  end if;

  update public.network_rounds
  set phase = 'CLOSED', closed_at = now(), updated_at = now()
  where id = p_round_id;

  v_next_number := v_round.round_number + 1;
  update public.network_game_states
  set current_round_number = v_next_number, updated_at = now()
  where session_id = p_session_id
    and current_round_number = v_round.round_number;
  insert into public.network_rounds(session_id, round_number, round_key)
  values (
    p_session_id,
    v_next_number,
    p_session_id::text || '.round-' || v_next_number
  )
  on conflict (session_id, round_number) do nothing;
  select id into v_next_id
  from public.network_rounds
  where session_id = p_session_id and round_number = v_next_number;
  return public.network_round_json(v_next_id, p_player_id);
end;
$$;

revoke all on function public.ready_network_next_round(
  uuid, uuid, uuid, text, boolean, integer
) from public;
grant execute on function public.ready_network_next_round(
  uuid, uuid, uuid, text, boolean, integer
) to authenticated;

-- PLAYER_1 remains the spice publisher. A PLAYER_2 round advance may race
-- with that publication, so the immediately superseded boundary remains a
-- valid publication target and returns the new canonical round.
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
    return public.get_current_network_game_round(p_session_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds
  where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase<>'WAITING_NEXT' and not (
    v_round.phase='CLOSED' and exists(
      select 1 from public.network_game_states state
      where state.session_id=p_session_id
        and state.current_round_number=v_round.round_number+1
    )
  ) then
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
  return public.get_current_network_game_round(p_session_id,p_player_id);
end;
$$;

revoke all on function public.publish_network_v4_unlocked_spice(
  uuid,uuid,uuid,integer,text
) from public;
grant execute on function public.publish_network_v4_unlocked_spice(
  uuid,uuid,uuid,integer,text
) to authenticated;

