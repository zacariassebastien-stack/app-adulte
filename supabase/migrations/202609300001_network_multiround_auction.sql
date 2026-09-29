create table public.network_game_states (
  session_id uuid primary key references public.game_sessions(id) on delete cascade,
  current_round_number integer not null default 1 check (current_round_number > 0),
  action_points jsonb not null check (jsonb_typeof(action_points) = 'object'),
  updated_at timestamptz not null default now()
);

alter table public.network_game_states enable row level security;
revoke all on public.network_game_states from anon, authenticated;

alter table public.network_rounds
  drop constraint network_rounds_phase_check;
alter table public.network_rounds
  add constraint network_rounds_phase_check check (phase in (
    'COMMIT', 'REVEAL', 'READY', 'COUNTER_DECISION',
    'FINAL_DEFENSE_DECISION', 'TIE_DECISION', 'FINAL_RESOLVED',
    'WAITING_NEXT', 'CLOSED'
  ));
alter table public.network_rounds
  add column initial_resolution jsonb,
  add column counter_bid jsonb,
  add column final_defense jsonb,
  add column final_resolution jsonb,
  add column ready_next jsonb not null default '{}'::jsonb,
  add column tie_decisions jsonb not null default '{}'::jsonb,
  add column closed_at timestamptz;

alter table public.network_round_commands
  drop constraint network_round_commands_kind_check;
alter table public.network_round_commands
  add constraint network_round_commands_kind_check check (kind in (
    'CREATE', 'OPEN', 'COMMIT', 'REVEAL', 'INITIAL_RESOLVE',
    'COUNTER_DECISION', 'FINAL_DEFENSE', 'TIE_DECISION', 'READY_NEXT'
  ));
alter table public.network_round_commands
  add column command_payload jsonb not null default '{}'::jsonb
  check (jsonb_typeof(command_payload) = 'object');

create or replace function public.network_round_json(
  p_round_id uuid,
  p_requester uuid
) returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'schema_version', 1,
    'round_id', r.id,
    'session_id', r.session_id,
    'session_round', r.round_key,
    'round_number', r.round_number,
    'phase', r.phase,
    'player_id', p_requester,
    'action_points', g.action_points,
    'commits', coalesce((
      select jsonb_object_agg(c.player_id::text, c.digest)
      from public.network_round_commits c where c.round_id = r.id
    ), '{}'::jsonb),
    'own_reveal', (
      select jsonb_build_object(
        'schema_version', 1,
        'session_round', r.round_key,
        'player_id', v.player_id,
        'choice', v.choice_payload,
        'nonce', v.nonce
      )
      from public.network_round_reveals v
      where v.round_id = r.id and v.player_id = p_requester
    ),
    'opponent_reveal', case when r.phase = 'READY' then (
      select jsonb_build_object(
        'schema_version', 1,
        'session_round', r.round_key,
        'player_id', v.player_id,
        'choice', v.choice_payload,
        'nonce', v.nonce
      )
      from public.network_round_reveals v
      where v.round_id = r.id and v.player_id <> p_requester
    ) else null end,
    'initial_resolution', r.initial_resolution,
    'counter_bid', r.counter_bid,
    'final_defense', r.final_defense,
    'final_resolution', r.final_resolution,
    'ready_next', r.ready_next,
    'tie_decisions', r.tie_decisions
  )
  from public.network_rounds r
  join public.network_game_states g on g.session_id = r.session_id
  where r.id = p_round_id;
$$;

create function public.network_final_choice(
  p_round_id uuid,
  p_choice_player_id uuid,
  p_retained_player_id uuid,
  p_inverted boolean
) returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'retained_player_id', p_retained_player_id,
    'card_id', v.choice_payload->>'card_id',
    'variant_id', v.choice_payload->>'variant_id',
    'inverted', p_inverted,
    'mutual_abandon', false
  )
  from public.network_round_reveals v
  where v.round_id = p_round_id and v.player_id = p_choice_player_id;
$$;

create function public.open_network_game_round(
  p_session_id uuid,
  p_player_id uuid,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_game public.network_game_states%rowtype;
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if (select count(*) from public.session_players where session_id = p_session_id) <> 2 then
    raise exception 'ROUND_SESSION_NOT_READY';
  end if;
  if p_command_id is null or length(trim(p_command_id)) = 0 then raise exception 'ROUND_INVALID_ARGUMENT'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text, 0));
  insert into public.network_game_states(session_id, action_points)
  select p_session_id, jsonb_object_agg(user_id::text, 100)
  from public.session_players where session_id = p_session_id
  on conflict (session_id) do nothing;

  select * into v_game from public.network_game_states where session_id = p_session_id for update;
  insert into public.network_rounds(session_id, round_number, round_key)
  values (
    p_session_id,
    v_game.current_round_number,
    p_session_id::text || '.round-' || v_game.current_round_number
  ) on conflict (session_id, round_number) do nothing;
  select * into v_round from public.network_rounds
  where session_id = p_session_id and round_number = v_game.current_round_number;

  select * into v_command from public.network_round_commands where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id or v_command.player_id <> p_player_id
      or v_command.kind <> 'OPEN' then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(v_round.id, p_player_id);
  end if;
  insert into public.network_round_commands(command_id, session_id, round_id, player_id, kind)
  values (p_command_id, p_session_id, v_round.id, p_player_id, 'OPEN');
  return public.network_round_json(v_round.id, p_player_id);
end;
$$;

create function public.get_current_network_game_round(
  p_session_id uuid,
  p_player_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_round_id uuid;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  select r.id into v_round_id
  from public.network_game_states g
  join public.network_rounds r
    on r.session_id = g.session_id and r.round_number = g.current_round_number
  where g.session_id = p_session_id;
  if v_round_id is null then raise exception 'ROUND_NOT_FOUND'; end if;
  return public.network_round_json(v_round_id, p_player_id);
end;
$$;

create function public.submit_network_initial_resolution(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_resolution jsonb,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_points jsonb;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_resolution is null or jsonb_typeof(p_resolution) <> 'object' then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text, 0));
  select * into v_command from public.network_round_commands where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id or v_command.kind <> 'INITIAL_RESOLVE'
      or v_command.command_payload is distinct from p_resolution then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id, p_player_id);
  end if;
  select * into v_round from public.network_rounds where id = p_round_id for update;
  if not found or v_round.session_id <> p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase <> 'READY' then
    if v_round.initial_resolution = p_resolution then
      insert into public.network_round_commands(
        command_id, session_id, round_id, player_id, kind, command_payload
      ) values (
        p_command_id, p_session_id, p_round_id, p_player_id, 'INITIAL_RESOLVE', p_resolution
      );
      return public.network_round_json(p_round_id, p_player_id);
    end if;
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  v_points := p_resolution->'action_points';
  if jsonb_typeof(v_points) <> 'object'
    or (select count(*) from jsonb_object_keys(v_points)) <> 2
    or exists (
      select 1 from public.session_players member
      where member.session_id = p_session_id
        and not (v_points ? member.user_id::text)
    )
    or exists (
      select 1 from jsonb_object_keys(v_points) proposed(player_id)
      where not exists (
        select 1 from public.session_players member
        where member.session_id = p_session_id
          and member.user_id::text = proposed.player_id
      )
    )
    or (p_resolution->>'gap_cost')::integer < 0
    or exists (
      select 1 from jsonb_each_text(v_points) proposed
      left join jsonb_each_text((select action_points from public.network_game_states where session_id = p_session_id)) current
        on current.key = proposed.key
      where current.key is null or proposed.value::integer < 0 or proposed.value::integer > current.value::integer
    ) then raise exception 'ROUND_RESOLUTION_MISMATCH';
  end if;
  insert into public.network_round_commands(
    command_id, session_id, round_id, player_id, kind, command_payload
  ) values (
    p_command_id, p_session_id, p_round_id, p_player_id, 'INITIAL_RESOLVE', p_resolution
  );
  update public.network_game_states set action_points = v_points, updated_at = now()
  where session_id = p_session_id;
  update public.network_rounds
  set initial_resolution = p_resolution,
      phase = case when (p_resolution->>'tied')::boolean then 'TIE_DECISION' else 'COUNTER_DECISION' end,
      updated_at = now()
  where id = p_round_id;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

create function public.submit_network_counter_decision(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_decision text,
  p_amount integer,
  p_target text,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_loser uuid;
  v_winner uuid;
  v_points jsonb;
  v_available integer;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text, 0));
  select * into v_command from public.network_round_commands where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id or v_command.kind <> 'COUNTER_DECISION'
      or v_command.command_payload is distinct from jsonb_strip_nulls(jsonb_build_object(
        'decision', p_decision, 'amount', p_amount, 'target', p_target
      )) then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id, p_player_id);
  end if;
  select * into v_round from public.network_rounds where id = p_round_id for update;
  if not found or v_round.session_id <> p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase <> 'COUNTER_DECISION' then raise exception 'ROUND_INVALID_PHASE'; end if;
  v_loser := (v_round.initial_resolution->>'loser_player_id')::uuid;
  v_winner := (v_round.initial_resolution->>'winner_player_id')::uuid;
  if p_player_id <> v_loser then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  insert into public.network_round_commands(
    command_id, session_id, round_id, player_id, kind, command_payload
  ) values (
    p_command_id, p_session_id, p_round_id, p_player_id, 'COUNTER_DECISION',
    jsonb_strip_nulls(jsonb_build_object(
      'decision', p_decision, 'amount', p_amount, 'target', p_target
    ))
  );
  if p_decision = 'ACCEPT' then
    update public.network_rounds
    set final_resolution = public.network_final_choice(p_round_id, v_winner, v_winner, false),
        phase = 'FINAL_RESOLVED', updated_at = now()
    where id = p_round_id;
  elsif p_decision = 'BID' then
    if p_amount is null or p_amount <= 0 then raise exception 'ROUND_INVALID_BID'; end if;
    if p_target not in ('OWN_INITIAL_ACTION', 'INVERT_WINNING_ACTION') then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
    if p_target = 'INVERT_WINNING_ACTION'
      and not (v_round.initial_resolution->>'inversion_allowed')::boolean then
      raise exception 'ROUND_INVERSION_FORBIDDEN';
    end if;
    select action_points into v_points from public.network_game_states where session_id = p_session_id for update;
    v_available := (v_points->>p_player_id::text)::integer;
    if p_amount > v_available then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
    v_points := jsonb_set(v_points, array[p_player_id::text], to_jsonb(v_available - p_amount));
    update public.network_game_states set action_points = v_points, updated_at = now() where session_id = p_session_id;
    update public.network_rounds
    set counter_bid = jsonb_build_object('player_id', p_player_id, 'amount', p_amount, 'target', p_target),
        phase = 'FINAL_DEFENSE_DECISION', updated_at = now()
    where id = p_round_id;
  else raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

create function public.submit_network_final_defense(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_decision text,
  p_amount integer,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_winner uuid;
  v_loser uuid;
  v_counter integer;
  v_points jsonb;
  v_available integer;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text, 0));
  select * into v_command from public.network_round_commands where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id or v_command.kind <> 'FINAL_DEFENSE'
      or v_command.command_payload is distinct from jsonb_strip_nulls(jsonb_build_object(
        'decision', p_decision, 'amount', p_amount
      )) then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id, p_player_id);
  end if;
  select * into v_round from public.network_rounds where id = p_round_id for update;
  if not found or v_round.session_id <> p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase <> 'FINAL_DEFENSE_DECISION' then raise exception 'ROUND_INVALID_PHASE'; end if;
  v_winner := (v_round.initial_resolution->>'winner_player_id')::uuid;
  v_loser := (v_round.initial_resolution->>'loser_player_id')::uuid;
  if p_player_id <> v_winner then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  v_counter := (v_round.counter_bid->>'amount')::integer;
  insert into public.network_round_commands(
    command_id, session_id, round_id, player_id, kind, command_payload
  ) values (
    p_command_id, p_session_id, p_round_id, p_player_id, 'FINAL_DEFENSE',
    jsonb_strip_nulls(jsonb_build_object('decision', p_decision, 'amount', p_amount))
  );
  if p_decision = 'YIELD' then
    update public.network_rounds
    set final_resolution = case
          when counter_bid->>'target' = 'OWN_INITIAL_ACTION'
            then public.network_final_choice(p_round_id, v_loser, v_loser, false)
          else public.network_final_choice(p_round_id, v_winner, v_loser, true)
        end,
        phase = 'FINAL_RESOLVED', updated_at = now()
    where id = p_round_id;
  elsif p_decision = 'DEFEND' then
    if p_amount is null or p_amount <= v_counter then raise exception 'ROUND_INVALID_BID'; end if;
    select action_points into v_points from public.network_game_states where session_id = p_session_id for update;
    v_available := (v_points->>p_player_id::text)::integer;
    if p_amount > v_available then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
    v_points := jsonb_set(v_points, array[p_player_id::text], to_jsonb(v_available - p_amount));
    update public.network_game_states set action_points = v_points, updated_at = now() where session_id = p_session_id;
    update public.network_rounds
    set final_defense = jsonb_build_object(
          'player_id', p_player_id,
          'amount', p_amount,
          'target', counter_bid->>'target'
        ),
        final_resolution = public.network_final_choice(p_round_id, v_winner, v_winner, false),
        phase = 'FINAL_RESOLVED', updated_at = now()
    where id = p_round_id;
  else raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

create function public.submit_network_tie_decision(
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
            'card_id', null,
            'variant_id', null,
            'inverted', false,
            'mutual_abandon', true
          ) else final_resolution end,
        phase = case when (select count(*) from jsonb_object_keys(v_decisions)) = 2 then 'FINAL_RESOLVED' else phase end,
        updated_at = now()
    where id = p_round_id;
  else raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

create function public.ready_network_next_round(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_command_id text
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
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text, 0));
  select * into v_command from public.network_round_commands where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id or v_command.kind <> 'READY_NEXT'
      or v_command.command_payload <> '{}'::jsonb then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.get_current_network_game_round(p_session_id, p_player_id);
  end if;
  select * into v_round from public.network_rounds where id = p_round_id for update;
  if not found or v_round.session_id <> p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase not in ('FINAL_RESOLVED', 'WAITING_NEXT') then raise exception 'ROUND_INVALID_PHASE'; end if;
  insert into public.network_round_commands(command_id, session_id, round_id, player_id, kind)
  values (p_command_id, p_session_id, p_round_id, p_player_id, 'READY_NEXT');
  v_ready := jsonb_set(v_round.ready_next, array[p_player_id::text], 'true'::jsonb);
  if (select count(*) from jsonb_object_keys(v_ready)) < 2 then
    update public.network_rounds set ready_next = v_ready, phase = 'WAITING_NEXT', updated_at = now()
    where id = p_round_id;
    return public.network_round_json(p_round_id, p_player_id);
  end if;
  update public.network_rounds
  set ready_next = v_ready, phase = 'CLOSED', closed_at = now(), updated_at = now()
  where id = p_round_id;
  v_next_number := v_round.round_number + 1;
  update public.network_game_states
  set current_round_number = v_next_number, updated_at = now()
  where session_id = p_session_id and current_round_number = v_round.round_number;
  insert into public.network_rounds(session_id, round_number, round_key)
  values (p_session_id, v_next_number, p_session_id::text || '.round-' || v_next_number)
  on conflict (session_id, round_number) do nothing;
  select id into v_next_id from public.network_rounds
  where session_id = p_session_id and round_number = v_next_number;
  return public.network_round_json(v_next_id, p_player_id);
end;
$$;

revoke all on function public.network_final_choice(uuid, uuid, uuid, boolean) from public;
revoke execute on function public.create_network_round(uuid, integer, uuid, text) from authenticated;
revoke all on function public.open_network_game_round(uuid, uuid, text) from public;
revoke all on function public.get_current_network_game_round(uuid, uuid) from public;
revoke all on function public.submit_network_initial_resolution(uuid, uuid, uuid, jsonb, text) from public;
revoke all on function public.submit_network_counter_decision(uuid, uuid, uuid, text, integer, text, text) from public;
revoke all on function public.submit_network_final_defense(uuid, uuid, uuid, text, integer, text) from public;
revoke all on function public.submit_network_tie_decision(uuid, uuid, uuid, text, text) from public;
revoke all on function public.ready_network_next_round(uuid, uuid, uuid, text) from public;

grant execute on function public.open_network_game_round(uuid, uuid, text) to authenticated;
grant execute on function public.get_current_network_game_round(uuid, uuid) to authenticated;
grant execute on function public.submit_network_initial_resolution(uuid, uuid, uuid, jsonb, text) to authenticated;
grant execute on function public.submit_network_counter_decision(uuid, uuid, uuid, text, integer, text, text) to authenticated;
grant execute on function public.submit_network_final_defense(uuid, uuid, uuid, text, integer, text) to authenticated;
grant execute on function public.submit_network_tie_decision(uuid, uuid, uuid, text, text) to authenticated;
grant execute on function public.ready_network_next_round(uuid, uuid, uuid, text) to authenticated;
