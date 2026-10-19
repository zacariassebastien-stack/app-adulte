-- Run after all migrations in a disposable local database. No remote writes.
begin;
do $$ begin if current_database() not like 'concept_usage_test%' then raise exception 'Local test database required'; end if; end; $$;
create function pg_temp.assert_true(p_condition boolean,p_message text)
returns void language plpgsql as $$ begin
  if p_condition is not true then raise exception 'TEST FAILED: %',p_message; end if;
end; $$;

create function pg_temp.make_usage(p_id text,p_concept text,p_stage integer,p_owner uuid,p_value integer)
returns jsonb language sql as $$
  select jsonb_build_object('usage_schema_version',1,'usage_id',p_id,'concept_id',p_concept,
    'owner_player_id',p_owner,'native_direction','FAIRE','effective_direction','FAIRE',
    'snapshot_value',p_value,'resolved_action',jsonb_build_object(
      'concept_id',p_concept,'catalog_version',1,'locale','fr-FR',
      'stage_id',p_concept||'.stage.'||p_stage,'zone_id','arms_hands','effective_chili',
        case when p_concept='019' then 3 when p_stage=2 then 2 else 1 end,
      'direction','FAIRE','actor_player_ids',jsonb_build_array(p_owner),
      'target_player_ids',jsonb_build_array(case when p_owner::text='11111111-1111-1111-1111-111111111111'
        then '22222222-2222-2222-2222-222222222222' else '11111111-1111-1111-1111-111111111111' end),
      'parameters',jsonb_build_object('chosen','frozen option'),
      'accessories',jsonb_build_array(jsonb_build_object('accessory_id','chosen-device','label','Selected')),
      'tags',jsonb_build_array('v3.preference.fixture','v3.zone.bras'),
      'primary_preference_ids',jsonb_build_array('v3.preference.fixture'),
      'effects',jsonb_build_array(jsonb_build_object('effect_id','fixture','parameters',jsonb_build_object('duration_actions',3))),
      'action_text','Frozen action text'));
$$;

create function pg_temp.digest_choice(p_round text,p_owner uuid,p_usage jsonb,p_nonce text)
returns text language sql as $$
  select encode(extensions.digest(convert_to('['||to_jsonb(p_round)::text||','||to_jsonb(p_owner::text)::text||','
    ||to_jsonb(public.canonical_jsonb(p_usage))::text||','||to_jsonb(p_nonce)::text||']','UTF8'),'sha256'),'hex');
$$;

do $$
declare
 a uuid:='11111111-1111-1111-1111-111111111111';
 b uuid:='22222222-2222-2222-2222-222222222222';
 s uuid; prior uuid; r uuid; followup uuid;
 original jsonb; points jsonb; winner_usage jsonb; loser_usage jsonb; source jsonb; replay jsonb; offer jsonb;
 i integer; step integer; compromise boolean; accept_other boolean; state jsonb;
begin
 insert into auth.users(id) values(a),(b);
 for i in 1..4 loop
  s:=gen_random_uuid(); prior:=gen_random_uuid(); r:=gen_random_uuid();
  accept_other:=i>2;
  insert into public.game_sessions(id,join_code,status,host_user_id) values(s,'RETRY'||substr('ABCD',i,1),'ready',a);
  insert into public.session_players(session_id,user_id,role,join_command_id) values(s,a,'PLAYER_1','a-'||i),(s,b,'PLAYER_2','b-'||i);
  points:=jsonb_build_object(a::text,85,b::text,100);
  insert into public.network_game_states(session_id,current_round_number,action_points,v4_unlocked_spice) values(s,2,points,4);
  winner_usage:=pg_temp.make_usage('winner-'||i,'044',1,a,12);
  loser_usage:=pg_temp.make_usage('loser-'||i,'045',1,b,7);
  source:=pg_temp.make_usage('source-'||i,'003',1,b,7);
  replay:=(source-'snapshot_value')||jsonb_build_object('usage_id','replay-'||i,'source_usage_id',source->>'usage_id');
  original:=jsonb_build_object('retained_player_id',a,'initial_winner_player_id',a,'final_winner_player_id',a,'final_loser_player_id',b,
    'concept_id','044','usage_id',winner_usage->>'usage_id','inverted',false,'compromise',jsonb_build_array(public.network_usage_resolution(winner_usage,false)||jsonb_build_object('origin','INITIAL_DUEL','logical_order',0)));
  insert into public.network_rounds(id,session_id,round_number,round_key,phase,initial_resolution,final_resolution)
   values(prior,s,1,'prior-'||i,'CLOSED',null,null),
   (r,s,2,'current-'||i,'CORRUPTION_DECISION',jsonb_build_object('winner_player_id',a,'loser_player_id',b,'high_value',12,'gap_cost',5),null);
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind)
   values('source-'||i,s,prior,b,'REVEAL'),('winner-'||i,s,r,a,'REVEAL'),('loser-'||i,s,r,b,'REVEAL');
  insert into public.network_round_reveals(round_id,player_id,choice_payload,nonce,command_id)
   values(prior,b,source,'nonce','source-'||i),(r,a,winner_usage,'nonce','winner-'||i),(r,b,loser_usage,'nonce','loser-'||i);
  update public.network_rounds set final_resolution=original where id=r;
  for step in 1..2 loop
   compromise:=case when step=1 then i%2=1 else i%2=0 end;
   perform set_config('request.jwt.claim.sub',b::text,true);
   if compromise then
    offer:='{"cards":[],"direct_pa":10,"inversion_requested":false}';
    perform public.submit_network_negotiation_proposal(s,r,b,offer,'offer-n-'||i);
   else
    perform public.submit_network_corruption_offer(s,r,b,'OWN_INITIAL_ACTION',jsonb_build_array(replay),'offer-c-'||i);
   end if;
   perform set_config('request.jwt.claim.sub',a::text,true);
   if compromise then
    state:=public.respond_network_negotiation(s,r,a,jsonb_build_object('accepted',accept_other and step=2),'response-n-'||i);
    perform public.respond_network_negotiation(s,r,a,jsonb_build_object('accepted',accept_other and step=2),'response-n-'||i);
   else
    state:=public.respond_network_corruption(s,r,a,accept_other and step=2,'response-c-'||i);
    perform public.respond_network_corruption(s,r,a,accept_other and step=2,'response-c-'||i);
   end if;
   if accept_other and step=2 then
    perform pg_temp.assert_true(state->>'phase'='FINAL_RESOLVED','accepted alternative resolves');
    perform pg_temp.assert_true(state#>>'{final_resolution,final_winner_player_id}'=a::text,'acceptance retains initial duel winner');
   else
    perform pg_temp.assert_true(state->>'phase'='CORRUPTION_DECISION','refusal returns to choice');
    perform pg_temp.assert_true((select final_resolution=original from public.network_rounds where id=r),'refusal preserves initial action');
    perform pg_temp.assert_true((select action_points=points from public.network_game_states where session_id=s),'refusal never recalculates PA');
    perform set_config('request.jwt.claim.sub',b::text,true);
    begin
     if compromise then
      perform public.submit_network_negotiation_proposal(s,r,b,offer,'repeat-n-'||i);
     else
      perform public.submit_network_corruption_offer(s,r,b,'OWN_INITIAL_ACTION',jsonb_build_array(replay),'repeat-c-'||i);
     end if;
     raise exception 'TEST FAILED: repeated mechanism accepted';
    exception when raise_exception then
     if sqlerrm<>(case when compromise then 'ROUND_NEGOTIATION_INVALID' else 'ROUND_CORRUPTION_FORBIDDEN' end) then raise; end if;
    end;
    state:=public.network_round_json(r,b);
    perform pg_temp.assert_true(case when compromise then state#>>'{negotiation,response,accepted}'='false' else state#>>'{corruption,accepted}'='false' end,'reconnect retains refusal marker');
   end if;
  end loop;
  if not accept_other then
   perform set_config('request.jwt.claim.sub',b::text,true);
   perform public.skip_network_corruption(s,r,b,'skip-'||i);
   perform pg_temp.assert_true((select phase='FINAL_RESOLVED' and final_resolution=original from public.network_rounds where id=r),'two refusals leave acceptance of original result');
  elsif i=3 then
   -- An accepted historical replay may not be offered from its source again,
   -- nor may its new usage become a third life in a later duel.
   followup:=gen_random_uuid();
   insert into public.network_rounds(id,session_id,round_number,round_key,phase,initial_resolution,final_resolution)
    select followup,s,3,'followup','CORRUPTION_DECISION',initial_resolution,jsonb_set(original,'{compromise}','[]'::jsonb) from public.network_rounds where id=r;
   perform set_config('request.jwt.claim.sub',b::text,true);
   begin
    perform public.submit_network_corruption_offer(s,followup,b,'OWN_INITIAL_ACTION',jsonb_build_array(replay||jsonb_build_object('usage_id','second-replay')),'third-life-source');
    raise exception 'TEST FAILED: source replayed twice';
   exception when raise_exception then if sqlerrm<>'ROUND_CORRUPTION_FORBIDDEN' then raise; end if; end;
   begin
    perform public.submit_network_corruption_offer(s,followup,b,'OWN_INITIAL_ACTION',jsonb_build_array(replay||jsonb_build_object('usage_id','third-life','source_usage_id','replay-'||i)),'third-life-usage');
    raise exception 'TEST FAILED: replay gained third life';
   exception when raise_exception then if sqlerrm<>'ROUND_CORRUPTION_FORBIDDEN' then raise; end if; end;
  end if;
 end loop;
 raise notice 'Post-duel alternatives, retries, persistent refusals and corruption second-life lifecycle passed';
end; $$;
rollback;
