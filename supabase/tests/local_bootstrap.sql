-- ONLY for a fresh disposable LOCAL PostgreSQL database used by the test runner.
do $$ begin
  if current_database() not like 'concept_usage_test%' then
    raise exception 'Use a disposable concept_usage_test* database';
  end if;
  if to_regclass('public.game_sessions') is not null then
    raise exception 'Use a fresh database; this bootstrap does not reset existing data';
  end if;
  if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
end; $$;
create schema if not exists auth;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
