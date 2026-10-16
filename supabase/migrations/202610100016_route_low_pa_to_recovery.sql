-- Route a completed normal action through Recovery when a canonical balance
-- is at or below the existing 10 PA threshold.

create or replace function public.ready_network_next_round(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_command_id text,
  p_no_playable_occurrences boolean default false,
  p_clothing_count integer default null,
  p_has_playable_alternate boolean default false
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
  v_orientation text;
  v_report jsonb;
  v_reports jsonb;
  v_is_hybrid boolean;
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
    'clothing_count', p_clothing_count,
    'has_playable_alternate', p_has_playable_alternate
  );
  select * into v_command
  from public.network_round_commands
  where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id
      or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id
      or v_command.kind <> 'READY_NEXT'
      or (
        v_command.command_payload is distinct from v_payload
        and v_command.command_payload is distinct from
          (v_payload-'has_playable_alternate')
      ) then
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
  select s.v4_session_mode='hybrid',g.hybrid_orientation
  into v_is_hybrid,v_orientation
  from public.game_sessions s
  join public.network_game_states g on g.session_id=s.id
  where s.id=p_session_id;
  if v_round.phase='WAITING_NEXT' then
    if exists(
      select 1 from public.network_game_states
      where session_id=p_session_id and cycle_exhausted
    ) then
      raise exception 'ROUND_CYCLE_EXHAUSTED';
    end if;
    if v_is_hybrid and v_round.hybrid_availability_orientation is not null then
      if v_round.hybrid_availability_orientation is distinct from v_orientation
        or exists(
          select 1 from public.session_players participant
          where participant.session_id=p_session_id
            and not (v_round.hybrid_availability ? participant.user_id::text)
        )
        or exists(
          select 1 from jsonb_each(v_round.hybrid_availability) report
          where report.value->>'orientation' is distinct from v_orientation
            or coalesce((report.value->>'generation')::integer,-1)
              <>v_round.hybrid_availability_generation
        ) then
        raise exception 'ROUND_HYBRID_AVAILABILITY_PENDING';
      end if;
      if exists(
        select 1 from jsonb_each(v_round.hybrid_availability) report
        where coalesce((report.value->>'has_playable_current')::boolean,false)=false
      ) then
        raise exception 'ROUND_HYBRID_SWITCH_REQUIRED';
      end if;
    end if;
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
    if v_is_hybrid then
      v_report:=jsonb_build_object(
        'orientation',v_orientation,
        'generation',v_round.hybrid_availability_generation,
        'has_playable_current',not p_no_playable_occurrences,
        'has_playable_alternate',p_has_playable_alternate
      );
      v_reports:=jsonb_set(
        v_round.hybrid_availability,array[p_player_id::text],v_report,true
      );
      update public.network_rounds
      set hybrid_availability_orientation=v_orientation,
          hybrid_availability=v_reports,
          updated_at=now()
      where id=p_round_id;
      if p_no_playable_occurrences and not p_has_playable_alternate then
        update public.network_game_states
        set cycle_exhausted=true,updated_at=now()
        where session_id=p_session_id;
      end if;
    elsif p_no_playable_occurrences then
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
          ) then case
            when exists(
              select 1
              from public.network_game_states state
              cross join lateral jsonb_each_text(state.action_points) balance
              where state.session_id = p_session_id
                and balance.value::integer <= 10
            ) then 'RECOVERY'
            else 'WAITING_NEXT'
          end
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
  uuid,uuid,uuid,text,boolean,integer,boolean
) from public;
grant execute on function public.ready_network_next_round(
  uuid,uuid,uuid,text,boolean,integer,boolean
) to authenticated;
