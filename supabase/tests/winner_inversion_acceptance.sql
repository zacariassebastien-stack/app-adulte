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
 s uuid; r uuid; winner uuid; loser uuid; who uuid;
 uw jsonb; ul jsonb; choice jsonb; state jsonb; points jsonb; saved jsonb; before_final jsonb;
 offer jsonb:='{"cards":[],"direct_pa":0,"inversion_requested":true}';
 i integer; mask integer; winner_invertible boolean; loser_invertible boolean;
begin
 insert into auth.users(id) values(a),(b);
 for i in 1..8 loop
  s:=gen_random_uuid(); r:=gen_random_uuid();
  winner:=case when i<=4 then a else b end;
  loser:=case when winner=a then b else a end;
  mask:=(i-1)%4;
  winner_invertible:=mask<>3; loser_invertible:=false;
  insert into public.game_sessions(id,join_code,status,host_user_id) values(s,'ABCDE'||substr('ABCDEFGH',i,1),'ready',a);
  insert into public.session_players(session_id,user_id,role,join_command_id)
   values(s,a,'PLAYER_1','join-a-'||i),(s,b,'PLAYER_2','join-b-'||i);
  insert into public.network_game_states(session_id,action_points,v4_unlocked_spice)
   values(s,jsonb_build_object(a::text,100,b::text,100),4);
  insert into public.network_rounds(id,session_id,round_number,round_key) values(r,s,1,'inversion-'||i);
  uw:=pg_temp.make_usage('winner-'||i,'010',2,winner,20);
  ul:=pg_temp.make_usage('loser-'||i,'031',1,loser,7);
  ul:=ul||jsonb_build_object('native_direction','MUTUEL','effective_direction','MUTUEL');
  ul:=jsonb_set(ul,'{resolved_action}',(ul->'resolved_action')||jsonb_build_object(
    'direction','MUTUEL','actor_player_ids',jsonb_build_array(a,b),'target_player_ids',jsonb_build_array(a,b)));
  if winner_invertible then
   uw:=uw||jsonb_build_object('inverted_resolution',jsonb_build_object('snapshot_value',12,'resolved_action',
    jsonb_set(jsonb_set(jsonb_set(uw->'resolved_action','{direction}','"RECEVOIR"'),'{actor_player_ids}',jsonb_build_array(loser)),'{target_player_ids}',jsonb_build_array(winner))));
  end if;
  if loser_invertible then
   ul:=ul||jsonb_build_object('inverted_resolution',jsonb_build_object('snapshot_value',10,'resolved_action',
    jsonb_set(jsonb_set(jsonb_set(ul->'resolved_action','{direction}','"RECEVOIR"'),'{actor_player_ids}',jsonb_build_array(winner)),'{target_player_ids}',jsonb_build_array(loser))));
  end if;
  foreach who in array array[a,b] loop
   choice:=case when who=winner then uw else ul end;
   perform set_config('request.jwt.claim.sub',who::text,true);
   perform public.submit_network_round_commit(s,r,who,pg_temp.digest_choice('inversion-'||i,who,choice,'nonce'),'commit-'||i||who);
  end loop;
  foreach who in array array[a,b] loop
   choice:=case when who=winner then uw else ul end;
   perform set_config('request.jwt.claim.sub',who::text,true);
   perform public.submit_network_round_reveal(s,r,who,choice,'nonce','reveal-'||i||who);
  end loop;
  state:=public.resolve_network_initial_private(s,r,b,'resolve-'||i);
  perform pg_temp.assert_true((state#>>'{initial_resolution,inversion_allowed}')::boolean=winner_invertible,'initial permission follows winning card');
  select action_points into points from public.network_game_states where session_id=s;
  perform set_config('request.jwt.claim.sub',loser::text,true);
  select final_resolution into before_final from public.network_rounds where id=r;
  if mask=3 then
   begin
    perform public.submit_network_negotiation_proposal(s,r,loser,offer,'proposal-'||i);
    raise exception 'TEST FAILED: noninvertible winner accepted';
   exception when raise_exception then
    if sqlerrm<>'ROUND_INVERSION_FORBIDDEN' then raise; end if;
   end;
   -- A persisted invalid proposal must still fail at acceptance, atomically.
   update public.network_rounds set phase='NEGOTIATION_RESPONSE',
    negotiation=jsonb_build_object('offered_by',loser,'proposal',offer) where id=r;
   perform set_config('request.jwt.claim.sub',winner::text,true);
   begin
    perform public.respond_network_negotiation(s,r,winner,'{"accepted":true}','response-'||i);
    raise exception 'TEST FAILED: invalid winner inverse resolved';
   exception when raise_exception then
    if sqlerrm<>'ROUND_INVERSION_UNAVAILABLE' then raise; end if;
   end;
   perform pg_temp.assert_true(not exists(select 1 from public.network_round_commands where command_id='response-'||i),'failed acceptance records no command');
   perform pg_temp.assert_true((select action_points=points from public.network_game_states where session_id=s),'failed acceptance leaves PA unchanged');
   continue;
  end if;
  offer:=jsonb_build_object('cards','[]'::jsonb,'direct_pa',10,'inversion_requested',mask<>1);
  state:=public.submit_network_negotiation_proposal(s,r,loser,offer,'proposal-'||i);
  perform pg_temp.assert_true(state->>'phase'='NEGOTIATION_RESPONSE','proposal accepted');
  perform set_config('request.jwt.claim.sub',winner::text,true);
  state:=public.respond_network_negotiation(s,r,winner,jsonb_build_object('accepted',mask<>2),'response-'||i);
  perform pg_temp.assert_true(state->>'phase'=case when mask=2 then 'CORRUPTION_DECISION' else 'FINAL_RESOLVED' end,'response returns to choice only on refusal');
  select final_resolution into saved from public.network_rounds where id=r;
  if mask=2 then
   perform pg_temp.assert_true(saved=before_final,'refusal preserves original resolution');
   perform pg_temp.assert_true((select action_points=points from public.network_game_states where session_id=s),'refusal spends no PA');
  else
   perform pg_temp.assert_true(saved->>'initial_winner_player_id'=winner::text and saved->>'final_winner_player_id'=winner::text,'duel winner preserved');
   perform pg_temp.assert_true(saved#>'{compromise,0}'=(public.network_usage_resolution(case when mask=0 then uw else ul end,mask=0)||jsonb_build_object('origin','INITIAL_DUEL','logical_order',0)),'exact selected frozen usage and inverse');
   if mask=0 then
    perform pg_temp.assert_true(saved->>'concept_id'='010' and saved#>>'{compromise,0,resolved_action,direction}'='RECEVOIR' and saved#>>'{compromise,0,snapshot_value}'='12','real failure resolves winning Strip-tease stage 2 inverted');
   else
    perform pg_temp.assert_true(saved->>'concept_id'='031' and saved#>>'{compromise,0,resolved_action,direction}'='MUTUEL','ordinary compromise retains losing mutual action');
   end if;
   perform pg_temp.assert_true((select (action_points->>loser::text)::integer=(points->>loser::text)::integer-10-case when mask=0 then 20 else 0 end and action_points->winner::text=points->winner::text from public.network_game_states where session_id=s),'existing exact PA debit preserved');
  end if;
  select action_points into points from public.network_game_states where session_id=s;
  state:=public.respond_network_negotiation(s,r,winner,jsonb_build_object('accepted',mask<>2),'response-'||i);
  perform pg_temp.assert_true((select final_resolution=saved from public.network_rounds where id=r),'retry preserves frozen resolution');
  perform pg_temp.assert_true((select action_points=points from public.network_game_states where session_id=s),'retry does not debit twice');
  perform pg_temp.assert_true((select count(*)=1 from public.network_round_commands where command_id='response-'||i),'one response command');
  offer:='{"cards":[],"direct_pa":0,"inversion_requested":true}';
 end loop;
 raise notice 'Winner inversion acceptance: real fixture, ordinary acceptance, refusals, invalid winner and retries passed for both players';
end; $$;
rollback;
