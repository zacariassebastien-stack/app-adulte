-- Run on a disposable database migrated through 202610180001, using psql
-- (or a runner supporting \ir). Exercises the real migration with old data.
begin;
do $$ begin if current_database() not like 'concept_usage_test%' then raise exception 'Local test database required'; end if; end; $$;
create function pg_temp.check_upgrade(ok boolean, message text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'TEST FAILED: %',message; end if; end; $$;
create temporary table upgrade_before(session_id uuid, points jsonb, resolutions jsonb);
do $$
declare
 a uuid:='11111111-1111-1111-1111-111111111111';
 b uuid:='22222222-2222-2222-2222-222222222222';
 s uuid; r uuid; i integer;
begin
 insert into auth.users(id) values(a),(b);
 -- Both retired phases, a session already closed, an obsolete non-current
 -- round in a healthy session, and a fresh unaffected session.
 for i in 1..5 loop
  s:=gen_random_uuid(); r:=gen_random_uuid();
  insert into public.game_sessions(id,join_code,status,host_user_id)
   values(s,'UPGRA'||substr('ABCDE',i,1),case when i=3 then 'closed' else 'ready' end,a);
  insert into public.network_game_states(session_id,action_points,current_round_number)
   values(s,jsonb_build_object(a::text,83,b::text,91),case when i=4 then 2 else 1 end);
  insert into public.network_rounds(id,session_id,round_number,round_key,phase,initial_resolution,counter_bid)
   values(r,s,1,'upgrade-'||i,case when i=2 then 'FINAL_DEFENSE_DECISION' when i=5 then 'COMMIT' else 'COUNTER_DECISION' end,
    jsonb_build_object('winner_player_id',a,'loser_player_id',b,'gap_cost',7),
    case when i=2 then '{"amount":9}'::jsonb else null end);
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind)
   values('upgrade-reveal-'||i,s,r,a,'REVEAL');
  -- Persisted legacy card choices were legal before the native usage contract.
  insert into public.network_round_reveals(round_id,player_id,choice_payload,nonce,command_id)
   values(r,a,'{"card_id":"legacy-card","variant_id":"legacy-variant","parameters":{},"value":12}',
    'historical-nonce','upgrade-reveal-'||i);
  if i=4 then
   insert into public.network_rounds(session_id,round_number,round_key,phase) values(s,2,'upgrade-current','COMMIT');
  end if;
  if i=1 then
   -- Reproduce the precise call made by the original migration. The caught
   -- subtransaction also verifies the preceding gap debit cannot leak out.
   begin
    update public.network_game_states set action_points=jsonb_set(action_points,array[a::text],'76') where session_id=s;
    perform public.network_final_choice(r,a,a,false);
    raise exception 'TEST FAILED: legacy reveal unexpectedly accepted';
   exception when raise_exception then
    if sqlerrm<>'ROUND_USAGE_INVALID' then raise; end if;
   end;
   perform pg_temp.check_upgrade((select (action_points->>a::text)::integer=83 from public.network_game_states where session_id=s),'failed conversion rolls back debit');
  end if;
 end loop;
 insert into upgrade_before
 select g.session_id,g.action_points,jsonb_agg(jsonb_build_object('id',r.id,'initial',r.initial_resolution,'final',r.final_resolution,'counter',r.counter_bid) order by r.round_number)
 from public.network_game_states g join public.network_rounds r using(session_id) group by g.session_id;
end; $$;

\ir ../migrations/202610180002_session_preparation_and_flow.sql

do $$
begin
 perform pg_temp.check_upgrade((select count(*)=3 from public.game_sessions where join_code in ('UPGRAA','UPGRAB','UPGRAC') and status='closed'),'retired sessions closed');
 perform pg_temp.check_upgrade((select count(*)=3 from public.network_rounds r join public.game_sessions s on s.id=r.session_id where s.join_code in ('UPGRAA','UPGRAB','UPGRAC') and r.phase='SESSION_CLOSED'),'retired rounds closed');
 perform pg_temp.check_upgrade((select count(*)=2 from public.game_sessions where join_code in ('UPGRAD','UPGRAE') and status='ready'),'healthy sessions preserved');
 perform pg_temp.check_upgrade((select count(*)=2 from public.network_rounds r join public.game_sessions s on s.id=r.session_id where s.join_code in ('UPGRAD','UPGRAE') and r.phase='COMMIT'),'healthy current rounds preserved');
 perform pg_temp.check_upgrade(not exists(select 1 from upgrade_before b join public.network_game_states g using(session_id) where b.points is distinct from g.action_points),'no debit, credit or duplicate historical spending');
 perform pg_temp.check_upgrade(not exists(select 1 from upgrade_before b where b.resolutions is distinct from (select jsonb_agg(jsonb_build_object('id',r.id,'initial',r.initial_resolution,'final',r.final_resolution,'counter',r.counter_bid) order by r.round_number) from public.network_rounds r where r.session_id=b.session_id)),'historical resolutions and counter spending preserved');
 perform pg_temp.check_upgrade((select count(*)=5 from public.network_round_reveals where command_id like 'upgrade-reveal-%'),'historical reveals preserved');
 raise notice 'Historical upgrade regression passed';
end; $$;
rollback;
