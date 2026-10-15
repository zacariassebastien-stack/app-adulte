-- Run after all migrations, only in the disposable local test database.
-- Fixtures and temporary test functions are rolled back. No remote deployment.
begin;
do $$ begin
  if current_database() not like 'concept_usage_test%' then raise exception 'Local test database required'; end if;
end; $$;

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
  s uuid:='00000000-0000-0000-0000-000000000100';
  prior uuid:='00000000-0000-0000-0000-000000000001';
  current_round uuid:='00000000-0000-0000-0000-000000000002';
  tied uuid:='00000000-0000-0000-0000-000000000003';
  ua jsonb; ub jsonb; inverse jsonb; bid1 jsonb; bid2 jsonb; offer jsonb;
  c1 jsonb; c2 jsonb; statuses jsonb; recovery jsonb; completed jsonb;
  state jsonb; saved jsonb; points jsonb; n integer;
begin
  insert into auth.users(id) values(a),(b);
  insert into public.game_sessions(id,join_code,status,host_user_id) values(s,'ABCDEF','ready',a);
  insert into public.session_players(session_id,user_id,role,join_command_id)
    values(s,a,'PLAYER_1','fixture-join-a'),(s,b,'PLAYER_2','fixture-join-b');
  insert into public.network_game_states(session_id,current_round_number,action_points)
    values(s,2,jsonb_build_object(a::text,100,b::text,100));
  insert into public.network_rounds(id,session_id,round_number,round_key,phase)
    values(prior,s,1,'fixture-round-1','CLOSED'),(current_round,s,2,'fixture-round-2','COMMIT'),
      (tied,s,3,'fixture-round-3','TIE_DECISION');

  ua:=pg_temp.make_usage('usage-a','044',1,a,9);
  ub:=pg_temp.make_usage('usage-b','045',1,b,7);
  inverse:=jsonb_set(ua->'resolved_action','{direction}','"RECEVOIR"'::jsonb);
  inverse:=jsonb_set(inverse,'{actor_player_ids}',jsonb_build_array(b));
  inverse:=jsonb_set(inverse,'{target_player_ids}',jsonb_build_array(a));
  ua:=ua||jsonb_build_object('inverted_resolution',jsonb_build_object('resolved_action',inverse,'snapshot_value',13));
  perform pg_temp.assert_true(public.network_usage_projection(ua,true)=ua,'projection must preserve exact frozen data');
  state:=public.network_usage_resolution(ua,true);
  perform pg_temp.assert_true(state->>'usage_id'='usage-a' and state->>'snapshot_value'='13'
    and state#>>'{resolved_action,direction}'='RECEVOIR','frozen inversion');
  perform pg_temp.assert_true(ua#>>'{resolved_action,direction}'='FAIRE','inversion cannot mutate original');
  begin
    perform public.network_usage_projection(ua,false);
    raise exception 'TEST FAILED: secondary proposal accepted private value';
  exception when raise_exception then
    if sqlerrm<>'ROUND_USAGE_PRIVATE_VALUE' then raise; end if;
  end;
  begin
    perform public.network_usage_projection(jsonb_set(ua,'{resolved_action,personal_values}','[]'::jsonb),true);
    raise exception 'TEST FAILED: raw private snapshot accepted';
  exception when raise_exception then
    if sqlerrm<>'ROUND_USAGE_INVALID' then raise; end if;
  end;

  -- Actual existing commit/reveal RPCs, including canonical digest and retries.
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform public.submit_network_round_commit(s,current_round,a,
    pg_temp.digest_choice('fixture-round-2',a,ua,'nonce-a'),'commit-a');
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform public.submit_network_round_commit(s,current_round,b,
    pg_temp.digest_choice('fixture-round-2',b,ub,'nonce-b'),'commit-b');
  perform set_config('request.jwt.claim.sub',a::text,true);
  state:=public.submit_network_round_reveal(s,current_round,a,ua,'nonce-a','reveal-a');
  perform pg_temp.assert_true(state->'opponent_reveal'='null'::jsonb,'no premature opponent reveal');
  perform set_config('request.jwt.claim.sub',b::text,true);
  state:=public.submit_network_round_reveal(s,current_round,b,ub,'nonce-b','reveal-b');
  perform pg_temp.assert_true(state->>'phase'='READY' and state->>'usage_contract_version'='1','native contract marker');
  perform set_config('request.jwt.claim.sub',a::text,true);
  state:=public.submit_network_round_reveal(s,current_round,a,ua,'nonce-a','reveal-a');
  select count(*) into n from public.network_round_reveals where round_id=current_round;
  perform pg_temp.assert_true(n=2 and state#>>'{own_reveal,choice,usage_id}'='usage-a','reveal retry/reconnect identity');

  perform public.submit_network_initial_resolution(s,current_round,a,jsonb_build_object(
    'tied',false,'winner_player_id',a,'loser_player_id',b,'gap',2,'gap_cost',2,
    'high_value',9,'action_points',jsonb_build_object(a::text,100,b::text,100),'inversion_allowed',true),'initial');
  bid1:=pg_temp.make_usage('bid-1','045',1,b,5)||jsonb_build_object('origin','AUCTION','logical_order',1);
  bid2:=pg_temp.make_usage('bid-2','045',2,b,6)||jsonb_build_object('origin','AUCTION','logical_order',2);
  offer:=jsonb_build_object('inversion_requested',false,'direct_pa',0,'cards',jsonb_build_array(bid1,bid2));
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform public.submit_network_negotiation_proposal(s,current_round,b,offer,'proposal');
  perform set_config('request.jwt.claim.sub',a::text,true);
  perform public.respond_network_negotiation(s,current_round,a,
    jsonb_build_object('accept_inversion',false,'accept_auction',true),'response');
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform public.adapt_network_negotiation(s,current_round,b,offer,'adapt');
  perform set_config('request.jwt.claim.sub',a::text,true);
  state:=public.validate_network_negotiation(s,current_round,a,true,'validate');
  saved:=state->'final_resolution';
  perform pg_temp.assert_true(saved->>'usage_id'='usage-b'
    and saved#>'{compromise,0,resolved_action}'=ub->'resolved_action','initial compromise preserves resolved action');
  perform pg_temp.assert_true(jsonb_array_length(saved->'compromise')=3
    and saved#>>'{compromise,1,usage_id}'='bid-1'
    and saved#>>'{compromise,2,usage_id}'='bid-2','same concept distinct auction usages');
  state:=public.validate_network_negotiation(s,current_round,a,true,'validate');
  perform pg_temp.assert_true(state->'final_resolution'=saved,'validation retry cannot rebuild snapshot');

  -- Earlier discarded source: provenance uses source_usage_id, not the new ID.
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind)
    values('prior-reveal',s,prior,a,'REVEAL');
  insert into public.network_round_reveals(round_id,player_id,choice_payload,nonce,command_id)
    values(prior,a,pg_temp.make_usage('prior-a','019',1,a,7),'prior-nonce','prior-reveal');
  c1:=(pg_temp.make_usage('corruption-1','019',1,a,7)-'snapshot_value')||jsonb_build_object('source_usage_id','prior-a');
  c2:=(pg_temp.make_usage('corruption-2','019',2,a,7)-'snapshot_value')||jsonb_build_object('source_usage_id','prior-a');
  state:=public.submit_network_corruption_offer(s,current_round,a,'OWN_INITIAL_ACTION',jsonb_build_array(c1,c2),'corruption-offer');
  perform pg_temp.assert_true(state#>'{corruption,actions,0,resolved_action}'=c1->'resolved_action','corruption offer keeps snapshot');
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform public.respond_network_corruption(s,current_round,b,true,'corruption-accept');
  perform set_config('request.jwt.claim.sub',a::text,true);
  statuses:=jsonb_build_array(
    jsonb_build_object('usage_id','corruption-2','source','DISCARD','status','SKIPPED','visibility','VISIBLE'),
    jsonb_build_object('usage_id','corruption-1','source','DISCARD','status','COMPLETED','visibility','VISIBLE'));
  state:=public.resolve_network_corruption(s,current_round,a,statuses,'corruption-resolve');
  saved:=state->'corruption';
  perform pg_temp.assert_true(saved#>>'{actions,0,usage_id}'='corruption-1'
    and saved#>>'{actions,0,status}'='COMPLETED'
    and saved#>'{actions,0,resolved_action}'=c1->'resolved_action'
    and saved#>'{actions,1,resolved_action}'=c2->'resolved_action','corruption status join preserves snapshots and order');
  state:=public.resolve_network_corruption(s,current_round,a,statuses,'corruption-resolve');
  perform pg_temp.assert_true(state->'corruption'=saved,'corruption retry');

  -- Recovery refusals and completed uses of the same concept have distinct IDs.
  update public.network_game_states set action_points=jsonb_build_object(a::text,8,b::text,100) where session_id=s;
  recovery:=(pg_temp.make_usage('recovery-1','019',1,a,7)-'snapshot_value')||jsonb_build_object(
    'player_id',a,'source','HAND','completed',false,'gain',0,'response',null);
  state:=public.submit_network_recovery(s,current_round,a,recovery,'recovery-offer-1');
  perform pg_temp.assert_true(not (state#>'{recovery_by_player}'->a::text ? 'snapshot_value')
    and state#>>array['recovery_by_player',a::text,'gain']='0','Recovery proposal privacy');
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform public.respond_network_recovery(s,current_round,b,'REFUSE','recovery-refuse');
  perform set_config('request.jwt.claim.sub',a::text,true);
  recovery:=jsonb_set(recovery,'{usage_id}','"recovery-2"'::jsonb);
  perform public.submit_network_recovery(s,current_round,a,recovery,'recovery-offer-2');
  perform set_config('request.jwt.claim.sub',b::text,true);
  perform public.respond_network_recovery(s,current_round,b,'ACCEPT','recovery-accept');
  perform set_config('request.jwt.claim.sub',a::text,true);
  completed:=recovery||jsonb_build_object('completed',true,'gain',12,'response','ACCEPT');
  begin
    perform public.resolve_network_recovery(s,current_round,a,
      jsonb_set(completed,'{resolved_action,action_text}','"changed"'::jsonb),'recovery-mismatch');
    raise exception 'TEST FAILED: Recovery reinterpreted reserved action';
  exception when raise_exception then
    if sqlerrm<>'ROUND_RECOVERY_NOT_ELIGIBLE' then raise; end if;
  end;
  state:=public.resolve_network_recovery(s,current_round,a,completed,'recovery-resolve');
  perform pg_temp.assert_true(state#>>array['action_points',a::text]='20'
    and jsonb_array_length(state->'recovery_history')=2,'distinct Recovery history and gain');
  state:=public.resolve_network_recovery(s,current_round,a,completed,'recovery-resolve');
  perform pg_temp.assert_true(state#>>array['action_points',a::text]='20'
    and jsonb_array_length(state->'recovery_history')=2,'Recovery retry must not duplicate gain/history');

  -- Tie concession uses the same canonical usage path, not legacy card IDs.
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind)
    values('tie-reveal-b',s,tied,b,'REVEAL');
  insert into public.network_round_reveals(round_id,player_id,choice_payload,nonce,command_id)
    values(tied,b,pg_temp.make_usage('tie-b','045',2,b,7),'tie-nonce','tie-reveal-b');
  state:=public.submit_network_tie_decision(s,tied,a,'CONCEDE','tie-concede');
  perform pg_temp.assert_true(state#>>'{final_resolution,usage_id}'='tie-b'
    and state#>>'{final_resolution,compromise,0,resolved_action,action_text}'='Frozen action text','tie resolved snapshot');
  raise notice 'PASS concept usage RPC integration scenarios';
end; $$;
rollback;
