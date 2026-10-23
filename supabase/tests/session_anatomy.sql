-- Run after all migrations, on a disposable local test database only.
begin;
do $$ begin if current_database() not like 'concept_usage_test%' then raise exception 'Local test database required'; end if; end; $$;
create function pg_temp.check_anatomy(ok boolean, message text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'TEST FAILED: %',message; end if; end; $$;
do $$
declare
 a uuid:='11111111-1111-1111-1111-111111111111'; b uuid:='22222222-2222-2222-2222-222222222222';
 s uuid:=gen_random_uuid(); state jsonb; env jsonb; r uuid;
begin
 insert into auth.users(id) values(a),(b);
 insert into public.game_sessions(id,join_code,status,host_user_id) values(s,'ANAT23','ready',a);
 insert into public.session_players(session_id,user_id,role,join_command_id) values(s,a,'PLAYER_1','anatomy-a'),(s,b,'PLAYER_2','anatomy-b');
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
  perform public.register_v4_setup_profile(s,'[]',null);
  raise exception 'TEST FAILED: accepted missing anatomy';
 exception when raise_exception then if sqlerrm<>'ROUND_INVALID_ARGUMENT' then raise; end if; end;
 begin
  perform public.register_v4_setup_profile(s,'[]','VAGIN');
  raise exception 'TEST FAILED: accepted invalid anatomy';
 exception when raise_exception then if sqlerrm<>'ROUND_INVALID_ARGUMENT' then raise; end if; end;
 state:=public.register_v4_setup_profile(s,'[]','PENIS');
 perform pg_temp.check_anatomy((select session_anatomy='PENIS' from public.session_players where session_id=s and user_id=a),'own anatomy persisted');
 perform pg_temp.check_anatomy((select session_anatomy is null from public.session_players where session_id=s and user_id=b),'partner not modified');
 perform set_config('request.jwt.claim.sub',b::text,true);
 perform public.register_v4_setup_accessories(s,'[]');
 perform set_config('request.jwt.claim.sub',a::text,true);
 env:=jsonb_build_object(a::text,jsonb_build_object('clothing_count',2,'accessories','[]'::jsonb),b::text,jsonb_build_object('clothing_count',2,'accessories','[]'::jsonb,'anatomy','PENIS'));
 perform public.propose_v4_session_setup(s,'presentiel','SOFT',env,0,'anatomy-propose');
 perform pg_temp.check_anatomy((select session_anatomy is null from public.session_players where session_id=s and user_id=b),'host environment cannot choose partner anatomy');
 perform set_config('request.jwt.claim.sub',b::text,true);
 begin
  perform public.respond_v4_session_setup(s,1,true,null,'anatomy-accept');
  raise exception 'TEST FAILED: accepted incomplete anatomies';
 exception when raise_exception then if sqlerrm<>'ROUND_SETUP_NOT_READY' then raise; end if; end;
 begin
  perform public.open_network_game_round(s,b,'anatomy-premature');
  raise exception 'TEST FAILED: opened incomplete anatomies';
 exception when raise_exception then if sqlerrm<>'ROUND_SETUP_NOT_READY' then raise; end if; end;
 perform public.register_v4_setup_profile(s,'[]','VULVE');
 state:=public.respond_v4_session_setup(s,1,true,null,'anatomy-accept');
 perform pg_temp.check_anatomy(state#>>'{players,0,anatomy}'='PENIS' and state#>>'{players,1,anatomy}'='VULVE','both canonical anatomies in setup');
 perform pg_temp.check_anatomy(public.get_v4_session_setup(s)=state,'reconnect preserves setup');
 perform pg_temp.check_anatomy(public.respond_v4_session_setup(s,1,true,null,'anatomy-accept')=state,'accept retry preserves setup');
 perform pg_temp.check_anatomy(public.register_v4_setup_profile(s,'[]','VULVE')=state,'same-value registration retry allowed');
 begin
  perform public.register_v4_setup_profile(s,'[]','PENIS');
  raise exception 'TEST FAILED: changed anatomy after acceptance';
 exception when raise_exception then if sqlerrm<>'ROUND_SESSION_SETUP_IMMUTABLE' then raise; end if; end;
 state:=public.open_network_game_round(s,b,'anatomy-open');
 r:=(state->>'round_id')::uuid;
 perform pg_temp.check_anatomy(r is not null,'complete setup opens round');
 begin
  update public.session_players set session_anatomy='PENIS' where session_id=s and user_id=b;
  raise exception 'TEST FAILED: changed anatomy in gameplay';
 exception when raise_exception then if sqlerrm<>'ROUND_SESSION_SETUP_IMMUTABLE' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','33333333-3333-3333-3333-333333333333',true);
 begin
  perform public.register_v4_setup_profile(s,'[]','PENIS');
  raise exception 'TEST FAILED: nonmember registered anatomy';
 exception when raise_exception then if sqlerrm<>'ROUND_NOT_MEMBER' then raise; end if; end;
 raise notice 'PASS session anatomy: strict values, personal publication, host cannot override, readiness, retry, resume and immutability';
end; $$;
rollback;
