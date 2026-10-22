-- Veto-only capability contributions. Profiles, scores, tags and reasons stay
-- on their device. Neither participant can read the other's contribution.
create table public.network_session_consent (
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  allowed jsonb not null check (jsonb_typeof(allowed) = 'array'),
  primary key (session_id, player_id)
);
create table public.network_session_consent_revisions (
  session_id uuid primary key references public.game_sessions(id) on delete cascade,
  revision bigint not null default 0
);
create table public.network_session_consent_commands (
  command_id text primary key,
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  allowed jsonb not null
);
alter table public.network_session_consent enable row level security;
alter table public.network_session_consent_revisions enable row level security;
alter table public.network_session_consent_commands enable row level security;
revoke all on public.network_session_consent, public.network_session_consent_revisions,
  public.network_session_consent_commands from anon, authenticated;
-- The only public invalidation is an opaque session revision. No contributor,
-- occurrence, veto or reason is included in Realtime.
grant select on public.network_session_consent_revisions to authenticated;
create policy session_consent_revision_member on public.network_session_consent_revisions
  for select to authenticated using (public.is_session_member(session_id));
alter publication supabase_realtime add table public.network_session_consent_revisions;

create function public.get_session_consent(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_ready boolean; v_allowed jsonb; v_revision bigint;
begin
  if auth.uid() is null or not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  -- Serialize the projection with writes; callers never receive one half of
  -- a concurrent update. No Realtime subscription to private tables is needed.
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text, 220001));
  select count(*)=2 into v_ready from public.network_session_consent
    where session_id=p_session_id;
  select revision into v_revision from public.network_session_consent_revisions
    where session_id=p_session_id;
  select coalesce(jsonb_agg(key order by key), '[]'::jsonb) into v_allowed
    from (
      select distinct key from public.network_session_consent mine,
        lateral jsonb_array_elements_text(mine.allowed) keys(key)
      where mine.session_id=p_session_id and mine.player_id=auth.uid()
        and split_part(key,'/',1)=auth.uid()::text
        and v_ready
        and not exists(select 1 from public.network_session_consent other
          where other.session_id=p_session_id and not (other.allowed ? key))
    ) permitted;
  return jsonb_build_object('revision',coalesce(v_revision,0),
    'ready',v_ready,'allowed',v_allowed);
end; $$;

create function public.publish_session_consent(
  p_session_id uuid, p_allowed jsonb, p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_previous public.network_session_consent_commands%rowtype;
  v_current jsonb;
begin
  if auth.uid() is null or not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if p_command_id is null or length(p_command_id)>256 or
    jsonb_typeof(p_allowed) is distinct from 'array' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  if jsonb_array_length(p_allowed)>10000 or exists(
    select 1 from jsonb_array_elements(p_allowed) item
    where jsonb_typeof(item)<>'string' or length(item#>>'{}')>256
      or not exists(select 1 from public.session_players p
        where p.session_id=p_session_id and p.user_id::text=split_part(item#>>'{}','/',1))
  ) then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text, 220001));
  select * into v_previous from public.network_session_consent_commands
    where command_id=p_command_id;
  if found then
    if v_previous.session_id<>p_session_id or v_previous.player_id<>auth.uid()
      or v_previous.allowed<>p_allowed then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.get_session_consent(p_session_id);
  end if;
  select allowed into v_current from public.network_session_consent
    where session_id=p_session_id and player_id=auth.uid();
  insert into public.network_session_consent_commands values
    (p_command_id,p_session_id,auth.uid(),p_allowed);
  if v_current is distinct from p_allowed then
    insert into public.network_session_consent values (p_session_id,auth.uid(),p_allowed)
      on conflict (session_id,player_id) do update set allowed=excluded.allowed;
    insert into public.network_session_consent_revisions values(p_session_id,1)
      on conflict(session_id) do update set revision=network_session_consent_revisions.revision+1;
  end if;
  return public.get_session_consent(p_session_id);
end; $$;

revoke all on function public.get_session_consent(uuid) from public, anon;
revoke all on function public.publish_session_consent(uuid,jsonb,text) from public, anon;
grant execute on function public.get_session_consent(uuid) to authenticated;
grant execute on function public.publish_session_consent(uuid,jsonb,text) to authenticated;
