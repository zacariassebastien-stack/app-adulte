alter table public.network_game_states
  add column if not exists cycle_exhausted boolean not null default false;

alter table public.network_rounds
  add column if not exists v4_action_projection jsonb,
  add column if not exists v4_clothing_resynced jsonb not null default '{}'::jsonb;

alter table public.game_sessions
  add column if not exists v4_session_mode text
    check (v4_session_mode in ('presentiel','distance','hybrid'));
alter table public.session_players
  add column if not exists v4_clothing_count integer check (v4_clothing_count >= 0),
  add column if not exists v4_accessories jsonb;

create or replace function public.v4_session_setup_json(p_session_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'mode', s.v4_session_mode,
    'players', coalesce(jsonb_agg(jsonb_build_object(
      'player_id', p.user_id,
      'clothing_count', p.v4_clothing_count,
      'accessories', coalesce(p.v4_accessories, '[]'::jsonb)
    ) order by p.role) filter (where p.v4_clothing_count is not null), '[]'::jsonb)
  ) from public.game_sessions s
  left join public.session_players p on p.session_id = s.id
  where s.id = p_session_id group by s.id;
$$;

create or replace function public.get_v4_session_setup(p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  return public.v4_session_setup_json(p_session_id);
end;
$$;

create or replace function public.submit_v4_session_setup(
  p_session_id uuid,
  p_clothing_count integer,
  p_accessories jsonb,
  p_mode text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text; v_accessories jsonb;
begin
  if auth.uid() is null or not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if p_clothing_count < 0 or jsonb_typeof(p_accessories) <> 'array' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', item->>'id', 'name', item->>'name',
    'owner_player_id', auth.uid(), 'tags', coalesce(item->'tags','[]'::jsonb),
    'normally_active', coalesce((item->>'normally_active')::boolean, true),
    'temporary', coalesce((item->>'temporary')::boolean, false),
    'remote_controllable', coalesce((item->>'remote_controllable')::boolean, false)
  )), '[]'::jsonb) into v_accessories
  from jsonb_array_elements(p_accessories) item;
  select role into v_role from public.session_players
  where session_id = p_session_id and user_id = auth.uid();
  if v_role = 'PLAYER_1' then
    if p_mode not in ('presentiel','distance','hybrid') then
      raise exception 'ROUND_INVALID_ARGUMENT';
    end if;
    if exists(select 1 from public.game_sessions where id=p_session_id
      and v4_session_mode is not null and v4_session_mode<>p_mode) then
      raise exception 'ROUND_SESSION_MODE_IMMUTABLE';
    end if;
    update public.game_sessions set v4_session_mode = p_mode, updated_at = now()
    where id = p_session_id;
  elsif p_mode is not null then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  update public.session_players set
    v4_clothing_count = p_clothing_count,
    v4_accessories = v_accessories
  where session_id = p_session_id and user_id = auth.uid();
  return public.v4_session_setup_json(p_session_id);
end;
$$;

revoke all on function public.v4_session_setup_json(uuid) from public;
revoke all on function public.get_v4_session_setup(uuid) from public;
revoke all on function public.submit_v4_session_setup(uuid,integer,jsonb,text) from public;
grant execute on function public.get_v4_session_setup(uuid) to authenticated;
grant execute on function public.submit_v4_session_setup(uuid,integer,jsonb,text) to authenticated;

create or replace function public.network_round_json(
  p_round_id uuid,
  p_requester uuid
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'schema_version',1,'round_id',r.id,'session_id',r.session_id,
    'session_round',r.round_key,'round_number',r.round_number,'phase',r.phase,
    'player_id',p_requester,'action_points',g.action_points,
    'hybrid_orientation',g.hybrid_orientation,'deck_cycle',g.deck_cycle,
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
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'PUBLISH_V4_ACTION',p_projection);
  update public.network_rounds set
    v4_action_projection=coalesce(v4_action_projection,p_projection),updated_at=now()
  where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

revoke all on function public.publish_v4_action_projection(
  uuid,uuid,uuid,text,jsonb
) from public;
grant execute on function public.publish_v4_action_projection(
  uuid,uuid,uuid,text,jsonb
) to authenticated;

-- V4: the resolved action is a shared ACTION_IN_PROGRESS state. The first
-- player who confirms "Terminé" closes it for both players. READY_NEXT stays
-- as the wire command name so deployed clients and idempotency keys remain
-- compatible.
drop function if exists public.ready_network_next_round(uuid, uuid, uuid, text);
drop function if exists public.ready_network_next_round(uuid, uuid, uuid, text, boolean);
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
  if v_round.phase not in ('FINAL_RESOLVED', 'WAITING_NEXT') then
    raise exception 'ROUND_INVALID_PHASE';
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
        phase = case when not exists(
          select 1 from jsonb_array_elements_text(coalesce(
            v4_action_projection->'required_clothing_player_ids','[]'::jsonb
          )) required(id)
          where not (v4_clothing_resynced ? required.id)
        ) then 'WAITING_NEXT' else 'FINAL_RESOLVED' end,
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

-- A hybrid context is a cycle-boundary decision. Enforce the same boundary on
-- the server so an older or modified client cannot change eligibility while an
-- action is being selected or resolved.
create or replace function public.set_network_hybrid_orientation(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_orientation text,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_payload jsonb;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if not exists(
    select 1 from public.session_players
    where session_id = p_session_id
      and user_id = p_player_id
      and role = 'PLAYER_1'
  ) then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  if p_orientation not in ('FACE_TO_FACE', 'DISTANCE') then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_payload := jsonb_build_object('orientation', p_orientation);
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text, 0));
  select * into v_round
  from public.network_rounds
  where id = p_round_id and session_id = p_session_id
  for update;
  if not found then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase <> 'WAITING_NEXT' then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  select * into v_command
  from public.network_round_commands
  where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id
      or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id
      or v_command.kind <> 'SET_ORIENTATION'
      or v_command.command_payload is distinct from v_payload then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id, p_player_id);
  end if;
  insert into public.network_round_commands(
    command_id, session_id, round_id, player_id, kind, command_payload
  ) values (
    p_command_id, p_session_id, p_round_id, p_player_id,
    'SET_ORIENTATION', v_payload
  );
  update public.network_game_states
  set hybrid_orientation = p_orientation, updated_at = now()
  where session_id = p_session_id;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

revoke all on function public.set_network_hybrid_orientation(
  uuid, uuid, uuid, text, text
) from public;
grant execute on function public.set_network_hybrid_orientation(
  uuid, uuid, uuid, text, text
) to authenticated;

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
begin
  if auth.uid() is null or auth.uid() <> p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if not exists(
    select 1 from public.session_players
    where session_id = p_session_id and user_id = p_player_id
      and role = 'PLAYER_1'
  ) then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  if p_choice not in (
    'CONTINUE_SPICIER','CONTINUE_INTENABLE','INFINITE','NEW_GAME','FINISH'
  ) or jsonb_typeof(p_adjustment) <> 'object' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_payload := jsonb_build_object(
    'choice', p_choice, 'adjustment', p_adjustment
  );
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text, 0));
  select * into v_round from public.network_rounds
  where id = p_round_id and session_id = p_session_id for update;
  if not found then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase <> 'WAITING_NEXT' then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
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
    return public.network_round_json(p_round_id, p_player_id);
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values (
    p_command_id,p_session_id,p_round_id,p_player_id,
    'CONTINUE_CYCLE',v_payload
  );
  update public.network_game_states set
    deck_cycle = case
      when p_choice in ('CONTINUE_SPICIER','CONTINUE_INTENABLE','INFINITE')
        then deck_cycle + 1 else deck_cycle end,
    deck_style = case
      when p_choice = 'CONTINUE_INTENABLE' then 'INTENABLE'
      when p_choice = 'CONTINUE_SPICIER' and deck_style = 'SOFT' then 'EPICE'
      when p_choice = 'CONTINUE_SPICIER' then 'INTENABLE'
      else deck_style end,
    infinite_mode = case
      when p_choice = 'INFINITE' then true else infinite_mode end,
    deck_adjustment = p_adjustment,
    cycle_exhausted = false,
    updated_at = now()
  where session_id = p_session_id;
  if p_choice in ('NEW_GAME','FINISH') then
    update public.game_sessions set status = 'closed' where id = p_session_id;
  end if;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

revoke all on function public.continue_network_deck_cycle(
  uuid,uuid,uuid,text,jsonb,text
) from public;
grant execute on function public.continue_network_deck_cycle(
  uuid,uuid,uuid,text,jsonb,text
) to authenticated;
