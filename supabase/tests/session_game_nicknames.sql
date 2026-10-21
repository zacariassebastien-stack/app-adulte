-- Disposable local database only; all fixtures roll back.
begin;
do $$ begin if current_database() not like 'concept_usage_test%' then
  raise exception 'Local test database required'; end if; end; $$;
do $$
declare
  a uuid := '11111111-1111-1111-1111-111111111111';
  b uuid := '22222222-2222-2222-2222-222222222222';
  s uuid; state jsonb; before_rounds jsonb; before_commands bigint;
begin
  insert into auth.users(id) values(a),(b);
  perform set_config('request.jwt.claim.sub', a::text, true);
  state := public.create_game_session('NAMABC', 'nickname-create');
  s := (state->>'id')::uuid;
  if state#>>'{players,0,game_nickname}' is not null then raise exception 'Legacy fallback broken'; end if;
  perform public.set_session_game_nickname(s, '  Seb  ');
  perform set_config('request.jwt.claim.sub', b::text, true);
  perform public.join_game_session('NAMABC', 'nickname-join');
  perform public.set_session_game_nickname(s, 'Julie');
  select jsonb_agg(to_jsonb(r)) into before_rounds from public.network_rounds r where session_id=s;
  select count(*) into before_commands from public.network_round_commands;
  for state in select public.get_game_session(s) union all select public.get_game_session(s) loop
    if not exists(select 1 from jsonb_array_elements(state->'players') p
      where p->>'user_id'=a::text and p->>'game_nickname'='Seb') or
      not exists(select 1 from jsonb_array_elements(state->'players') p
      where p->>'user_id'=b::text and p->>'game_nickname'='Julie') then
      raise exception 'ID/name association or restoration broken';
    end if;
  end loop;
  perform public.set_session_game_nickname(s, 'Julie');
  begin
    perform public.set_session_game_nickname(s, ' ');
    raise exception 'Empty nickname accepted';
  exception when raise_exception then if sqlerrm <> 'NICKNAME_INVALID' then raise; end if; end;
  begin
    perform public.set_session_game_nickname(s, repeat('x',21));
    raise exception 'Long nickname accepted';
  exception when raise_exception then if sqlerrm <> 'NICKNAME_INVALID' then raise; end if; end;
  perform public.set_session_game_nickname(s, 'Ju');
  perform public.set_session_game_nickname(s, repeat('J',20));
  if (select count(*) from public.network_round_commands) <> before_commands or
     (select jsonb_agg(to_jsonb(r)) from public.network_rounds r where session_id=s) is distinct from before_rounds then
    raise exception 'Identity update changed game state or commands';
  end if;
  perform set_config('request.jwt.claim.sub', a::text, true);
  state := public.get_game_session(s);
  if not exists(select 1 from jsonb_array_elements(state->'players') p
    where p->>'user_id'=a::text and p->>'game_nickname'='Seb') then raise exception 'Partner overwritten'; end if;
end;
$$;
rollback;
