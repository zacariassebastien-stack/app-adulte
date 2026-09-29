create extension if not exists pgcrypto;

create table public.game_sessions (
  id uuid primary key default gen_random_uuid(),
  join_code text not null unique check (join_code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  status text not null default 'waiting'
    check (status in ('waiting', 'ready', 'closed')),
  host_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '2 hours')
);

create table public.session_players (
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('PLAYER_1', 'PLAYER_2')),
  join_command_id text not null unique,
  joined_at timestamptz not null default now(),
  primary key (session_id, user_id),
  unique (session_id, role)
);

create index session_players_user_id_idx
  on public.session_players(user_id);

alter table public.game_sessions enable row level security;
alter table public.session_players enable row level security;

create function public.is_session_member(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.session_players
    where session_id = p_session_id and user_id = auth.uid()
  );
$$;

revoke all on function public.is_session_member(uuid) from public;
grant execute on function public.is_session_member(uuid) to authenticated;

create policy "members read their sessions"
on public.game_sessions for select to authenticated
using (public.is_session_member(id));

create policy "members read participants in their sessions"
on public.session_players for select to authenticated
using (public.is_session_member(session_id));

create function public.lobby_json(p_session_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', s.id,
    'join_code', s.join_code,
    'status', s.status,
    'expires_at', s.expires_at,
    'players', coalesce(
      jsonb_agg(
        jsonb_build_object('user_id', p.user_id, 'role', p.role)
        order by p.role
      ) filter (where p.user_id is not null),
      '[]'::jsonb
    )
  )
  from public.game_sessions s
  left join public.session_players p on p.session_id = s.id
  where s.id = p_session_id
  group by s.id;
$$;

revoke all on function public.lobby_json(uuid) from public;

create function public.create_game_session(
  p_join_code text,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  select session_id into v_session_id
  from public.session_players
  where user_id = auth.uid() and join_command_id = p_command_id;
  if v_session_id is not null then
    return public.lobby_json(v_session_id);
  end if;

  insert into public.game_sessions(join_code, host_user_id)
  values (upper(p_join_code), auth.uid())
  returning id into v_session_id;

  insert into public.session_players(
    session_id, user_id, role, join_command_id
  ) values (v_session_id, auth.uid(), 'PLAYER_1', p_command_id);

  return public.lobby_json(v_session_id);
end;
$$;

create function public.join_game_session(
  p_join_code text,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.game_sessions%rowtype;
  v_existing uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  select session_id into v_existing
  from public.session_players
  where user_id = auth.uid() and join_command_id = p_command_id;
  if v_existing is not null then return public.lobby_json(v_existing); end if;

  select * into v_session
  from public.game_sessions
  where join_code = upper(p_join_code)
  for update;

  if v_session.id is null then raise exception 'LOBBY_NOT_FOUND'; end if;
  if v_session.expires_at <= now() then raise exception 'LOBBY_EXPIRED'; end if;

  select session_id into v_existing
  from public.session_players
  where session_id = v_session.id and user_id = auth.uid();
  if v_existing is not null then return public.lobby_json(v_existing); end if;

  if v_session.status <> 'waiting' or (
    select count(*) from public.session_players
    where session_id = v_session.id
  ) >= 2 then
    raise exception 'LOBBY_FULL';
  end if;

  insert into public.session_players(
    session_id, user_id, role, join_command_id
  ) values (v_session.id, auth.uid(), 'PLAYER_2', p_command_id);

  update public.game_sessions
  set status = 'ready', updated_at = now()
  where id = v_session.id;

  return public.lobby_json(v_session.id);
end;
$$;

create function public.get_game_session(p_session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_session_member(p_session_id) then
    raise exception 'LOBBY_NOT_FOUND';
  end if;
  return public.lobby_json(p_session_id);
end;
$$;

revoke all on function public.create_game_session(text, text) from public;
revoke all on function public.join_game_session(text, text) from public;
revoke all on function public.get_game_session(uuid) from public;
grant execute on function public.create_game_session(text, text) to authenticated;
grant execute on function public.join_game_session(text, text) to authenticated;
grant execute on function public.get_game_session(uuid) to authenticated;

alter publication supabase_realtime add table public.session_players;
