-- Run after all migrations, only in a disposable local PostgreSQL database.
begin;
do $$ begin if current_database() not like 'concept_usage_test%' then raise exception 'Local test database required'; end if; end; $$;
create function pg_temp.check_setup(p_ok boolean,p_message text) returns void language plpgsql as $$ begin if p_ok is not true then raise exception 'TEST FAILED: %',p_message; end if; end; $$;
do $$
declare
 a uuid:='11111111-1111-1111-1111-111111111111'; b uuid:='22222222-2222-2222-2222-222222222222';
 s uuid; r uuid; m text; st text; n integer:=0; state jsonb; before_state jsonb; env jsonb; own jsonb; g public.network_game_states%rowtype;
begin
 insert into auth.users(id) values(a),(b);
 foreach m in array array['presentiel','hybrid','distance'] loop
 foreach st in array array['SOFT','EPICE','INTENABLE'] loop
  n:=n+1;s:=gen_random_uuid();
  insert into public.game_sessions(id,join_code,status,host_user_id) values(s,'ABCDE'||substr('ABCDEFGHJKLMNP',n,1),'ready',a);
  insert into public.session_players(session_id,user_id,role,join_command_id) values(s,a,'PLAYER_1','setup-a-'||n),(s,b,'PLAYER_2','setup-b-'||n);
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform public.register_v4_setup_profile(s,'[]','PENIS');
  begin
   perform public.open_network_game_round(s,a,'premature-'||n);
   raise exception 'TEST FAILED: round opened without preparation';
  exception when raise_exception then if sqlerrm<>'ROUND_SETUP_NOT_READY' then raise; end if; end;
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform public.register_v4_setup_profile(s,'[{"id":"partner-gear","name":"Accessoire partenaire","tags":["externe"]}]','VULVE');
  own:=jsonb_build_object('clothing_count',4,'accessories',jsonb_build_array(jsonb_build_object('id','temporary-b','name','Temporaire partenaire','tags',jsonb_build_array('vibrant'),'temporary',true)));
  env:=jsonb_build_object(a::text,jsonb_build_object('clothing_count',2,'accessories','[]'::jsonb));
  if m<>'distance' then env:=env||jsonb_build_object(b::text,own); end if;
  begin
   perform public.propose_v4_session_setup(s,m,st,env,0,'partner-forbidden-'||n);
   raise exception 'TEST FAILED: partner changed shared parameters';
  exception when raise_exception then if sqlerrm<>'ROUND_NOT_ACTIVE_PLAYER' then raise; end if; end;
  perform set_config('request.jwt.claim.sub',a::text,true);
  state:=public.propose_v4_session_setup(s,m,st,env,0,'proposal-'||n);
  perform pg_temp.check_setup(state->>'status'='PROPOSED' and state->>'style'=st,'explicit host style persisted');
  state:=public.propose_v4_session_setup(s,m,st,env,0,'proposal-'||n);
  perform pg_temp.check_setup((state->>'revision')::integer=1,'proposal retry does not create a new revision');
  perform set_config('request.jwt.claim.sub',b::text,true);
  if m<>'distance' then
   begin
    perform public.respond_v4_session_setup(s,1,true,own,'partner-environment-forbidden-'||n);
    raise exception 'TEST FAILED: partner edited shared environment';
   exception when raise_exception then if sqlerrm<>'ROUND_NOT_ACTIVE_PLAYER' then raise; end if; end;
  end if;
  state:=public.respond_v4_session_setup(s,1,false,case when m='distance' then own else null end,'refuse-'||n);
  perform pg_temp.check_setup(state->>'status'='REFUSED','refusal visible to host and persisted');
  before_state:=state;
  state:=public.get_v4_session_setup(s);
  perform pg_temp.check_setup(state=before_state,'reconnect restores refused configuration and environments');
  begin
   perform public.open_network_game_round(s,b,'refused-open-'||n);
   raise exception 'TEST FAILED: refused setup opened a round';
  exception when raise_exception then if sqlerrm<>'ROUND_SETUP_NOT_READY' then raise; end if; end;
  perform set_config('request.jwt.claim.sub',a::text,true);
  state:=public.propose_v4_session_setup(s,m,st,env,1,'reproposal-'||n);
  perform set_config('request.jwt.claim.sub',b::text,true);
  begin
   perform public.respond_v4_session_setup(s,1,true,null,'stale-accept-'||n);
   raise exception 'TEST FAILED: stale validation accepted a new proposal';
  exception when raise_exception then if sqlerrm<>'ROUND_SETUP_STALE' then raise; end if; end;
  state:=public.respond_v4_session_setup(s,2,true,case when m='distance' then own else null end,'accept-'||n);
  perform pg_temp.check_setup(state->>'status'='ACCEPTED','accepted by partner');
  state:=public.respond_v4_session_setup(s,2,true,case when m='distance' then own else null end,'accept-'||n);
  perform pg_temp.check_setup(state->>'status'='ACCEPTED' and (state->>'revision')::integer=2,'accept retry');
  state:=public.open_network_game_round(s,b,'open-b-'||n);
  perform pg_temp.check_setup(state->>'deck_style'=st and state->>'v4_unlocked_spice'='1','style before first draw; spice still starts at 1');
  state:=public.open_network_game_round(s,b,'open-b-'||n);
  perform pg_temp.check_setup((select count(*)=1 from public.network_rounds where session_id=s),'opening retry creates one round');
  perform pg_temp.check_setup((select v4_clothing_count=4 and v4_accessories#>>'{0,owner_player_id}'=b::text from public.session_players where session_id=s and user_id=b),'partner clothing/accessory owner preserved');
 end loop;end loop;
 -- Consensus, refusal, retry and immediate PA thresholds with the existing 80 PA.
 select session_id into s from public.session_players where user_id=a order by session_id limit 1;
 select id into r from public.network_rounds where session_id=s;
 update public.network_game_states set deck_style='SOFT',action_points=jsonb_build_object(a::text,60,b::text,60),cycle_exhausted=true where session_id=s;
 -- Previous test may have used another initial style but 0 spent, so level is 2.
 update public.network_rounds set phase='WAITING_NEXT' where id=r;
 perform set_config('request.jwt.claim.sub',a::text,true);
 state:=public.continue_network_deck_cycle(s,r,a,'CONTINUE_SPICIER','{"expected_cycle":1,"style_revision":0}','cycle-propose');
 perform pg_temp.check_setup(state->>'deck_style'='SOFT' and state->>'deck_cycle'='1','no unilateral increase or renewal');
 state:=public.continue_network_deck_cycle(s,r,a,'CONTINUE_SPICIER','{"expected_cycle":1,"style_revision":0}','cycle-propose');
 perform pg_temp.check_setup(state->>'cycle_style_revision'='1','proposal retry does not add a second vote');
 perform set_config('request.jwt.claim.sub',b::text,true);
 state:=public.continue_network_deck_cycle(s,r,b,'REFUSE_STYLE','{"expected_cycle":1,"style_revision":1}','cycle-refuse');
 perform pg_temp.check_setup(state->>'deck_style'='SOFT' and state->>'deck_cycle'='1','refusal preserves style and cycle');
 perform set_config('request.jwt.claim.sub',a::text,true);
 state:=public.continue_network_deck_cycle(s,r,a,'CONTINUE_SPICIER','{"expected_cycle":1,"style_revision":2}','cycle-repropose');
 perform set_config('request.jwt.claim.sub',b::text,true);
 state:=public.continue_network_deck_cycle(s,r,b,'CONTINUE_SPICIER','{"expected_cycle":1,"style_revision":3}','cycle-agree');
 perform pg_temp.check_setup(state->>'deck_style'='EPICE' and state->>'deck_cycle'='2' and state->>'v4_unlocked_spice'='3','80 PA Soft -> consensual Epice immediately spice 3');
 state:=public.continue_network_deck_cycle(s,r,b,'CONTINUE_SPICIER','{"expected_cycle":1,"style_revision":3}','cycle-agree');
 perform pg_temp.check_setup(state->>'deck_cycle'='2','agreement retry does not renew twice');
 update public.network_game_states set cycle_exhausted=true where session_id=s;
 state:=public.continue_network_deck_cycle(s,r,b,'CONTINUE_SAME','{"expected_cycle":2,"style_revision":4}','cycle-same');
 perform pg_temp.check_setup(state->>'deck_style'='EPICE' and state->>'deck_cycle'='3','keep existing style');
 update public.network_game_states set cycle_exhausted=true where session_id=s;
 state:=public.continue_network_deck_cycle(s,r,b,'CONTINUE_SPICIER','{"expected_cycle":3,"style_revision":5}','cycle-to-intense');
 perform set_config('request.jwt.claim.sub',a::text,true);
 state:=public.continue_network_deck_cycle(s,r,a,'CONTINUE_SPICIER','{"expected_cycle":3,"style_revision":6}','cycle-intense-agree');
 perform pg_temp.check_setup(state->>'deck_style'='INTENABLE' and state->>'deck_cycle'='4','consensual Epice -> Intenable');
 perform pg_temp.check_setup(public.network_total_pa_spent(s,state->'action_points')=80,'PA preserved across cycles');
 raise notice 'PASS setup modes/styles, roles, validation/refusal/reconnect/retry and cycle consensus';
end; $$;
rollback;
