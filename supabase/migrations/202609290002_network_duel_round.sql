create table public.network_rounds (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  round_number integer not null check (round_number > 0),
  round_key text not null unique,
  phase text not null default 'COMMIT'
    check (phase in ('COMMIT', 'REVEAL', 'READY')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (session_id, round_number)
);

create table public.network_round_commands (
  command_id text primary key check (length(trim(command_id)) > 0),
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  round_id uuid not null references public.network_rounds(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('CREATE', 'COMMIT', 'REVEAL')),
  created_at timestamptz not null default now()
);

create table public.network_round_commits (
  round_id uuid not null references public.network_rounds(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  digest text not null check (digest ~ '^[0-9a-f]{64}$'),
  command_id text not null unique
    references public.network_round_commands(command_id),
  committed_at timestamptz not null default now(),
  primary key (round_id, player_id)
);

create table public.network_round_reveals (
  round_id uuid not null references public.network_rounds(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  choice_payload jsonb not null check (jsonb_typeof(choice_payload) = 'object'),
  nonce text not null check (length(nonce) > 0),
  command_id text not null unique
    references public.network_round_commands(command_id),
  revealed_at timestamptz not null default now(),
  primary key (round_id, player_id)
);

alter table public.network_rounds enable row level security;
alter table public.network_round_commands enable row level security;
alter table public.network_round_commits enable row level security;
alter table public.network_round_reveals enable row level security;

create policy "members observe round changes"
on public.network_rounds for select to authenticated
using (public.is_session_member(session_id));

revoke all on public.network_rounds from anon, authenticated;
revoke all on public.network_round_commands from anon, authenticated;
revoke all on public.network_round_commits from anon, authenticated;
revoke all on public.network_round_reveals from anon, authenticated;
grant select on public.network_rounds to authenticated;

create function public.canonical_jsonb(p_value jsonb)
returns text
language sql
immutable
strict
set search_path = public
as $$
  select case jsonb_typeof(p_value)
    when 'object' then (
      select '{' || coalesce(
        string_agg(to_jsonb(key)::text || ':' || public.canonical_jsonb(value), ',' order by key),
        ''
      ) || '}'
      from jsonb_each(p_value)
    )
    when 'array' then (
      select '[' || coalesce(
        string_agg(public.canonical_jsonb(value), ',' order by ordinal),
        ''
      ) || ']'
      from jsonb_array_elements(p_value) with ordinality as items(value, ordinal)
    )
    else p_value::text
  end;
$$;

create function public.network_round_json(p_round_id uuid, p_requester uuid)
returns jsonb
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
    ) else null end
  )
  from public.network_rounds r
  where r.id = p_round_id;
$$;

create function public.create_network_round(
  p_session_id uuid,
  p_round_number integer,
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
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if (select count(*) from public.session_players where session_id = p_session_id) <> 2 then
    raise exception 'ROUND_SESSION_NOT_READY';
  end if;
  if p_round_number is null or p_round_number <= 0
    or p_command_id is null or length(trim(p_command_id)) = 0 then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_command_id, 0));
  select * into v_command from public.network_round_commands where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id or v_command.player_id <> p_player_id or v_command.kind <> 'CREATE' then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(v_command.round_id, p_player_id);
  end if;

  insert into public.network_rounds(session_id, round_number, round_key)
  values (p_session_id, p_round_number, p_session_id::text || '.round-' || p_round_number)
  on conflict (session_id, round_number) do nothing;

  select * into v_round from public.network_rounds
  where session_id = p_session_id and round_number = p_round_number;

  insert into public.network_round_commands(command_id, session_id, round_id, player_id, kind)
  values (p_command_id, p_session_id, v_round.id, p_player_id, 'CREATE');
  return public.network_round_json(v_round.id, p_player_id);
end;
$$;

create function public.submit_network_round_commit(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_digest text,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_digest is null or p_digest !~ '^[0-9a-f]{64}$'
    or p_command_id is null or length(trim(p_command_id)) = 0 then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_command_id, 0));
  select * into v_command from public.network_round_commands where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id or v_command.kind <> 'COMMIT'
      or not exists (select 1 from public.network_round_commits where command_id = p_command_id and digest = p_digest) then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id, p_player_id);
  end if;

  select * into v_round from public.network_rounds where id = p_round_id for update;
  if not found or v_round.session_id <> p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase <> 'COMMIT' then raise exception 'ROUND_COMMIT_CLOSED'; end if;
  if not exists (select 1 from public.session_players where session_id = p_session_id and user_id = p_player_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;

  insert into public.network_round_commands(command_id, session_id, round_id, player_id, kind)
  values (p_command_id, p_session_id, p_round_id, p_player_id, 'COMMIT');
  insert into public.network_round_commits(round_id, player_id, digest, command_id)
  values (p_round_id, p_player_id, p_digest, p_command_id);

  update public.network_rounds
  set phase = case
      when (select count(*) from public.network_round_commits where round_id = p_round_id) = 2
        then 'REVEAL'
      else phase
    end,
    updated_at = now()
  where id = p_round_id;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

create function public.submit_network_round_reveal(
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
  if encode(digest(convert_to(v_envelope, 'UTF8'), 'sha256'), 'hex') <> v_expected then
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

create function public.get_network_round_state(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if not exists (select 1 from public.network_rounds where id = p_round_id and session_id = p_session_id) then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

revoke all on function public.canonical_jsonb(jsonb) from public;
revoke all on function public.network_round_json(uuid, uuid) from public;
revoke all on function public.create_network_round(uuid, integer, uuid, text) from public;
revoke all on function public.submit_network_round_commit(uuid, uuid, uuid, text, text) from public;
revoke all on function public.submit_network_round_reveal(uuid, uuid, uuid, jsonb, text, text) from public;
revoke all on function public.get_network_round_state(uuid, uuid, uuid) from public;
grant execute on function public.create_network_round(uuid, integer, uuid, text) to authenticated;
grant execute on function public.submit_network_round_commit(uuid, uuid, uuid, text, text) to authenticated;
grant execute on function public.submit_network_round_reveal(uuid, uuid, uuid, jsonb, text, text) to authenticated;
grant execute on function public.get_network_round_state(uuid, uuid, uuid) to authenticated;

alter publication supabase_realtime add table public.network_rounds;
