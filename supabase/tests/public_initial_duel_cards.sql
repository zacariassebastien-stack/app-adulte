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
 s uuid:=gen_random_uuid(); r uuid:=gen_random_uuid();
 ua jsonb; ub jsonb; state jsonb; public_cards jsonb; who uuid; saved jsonb;
begin
 insert into auth.users(id) values(a),(b);
 insert into public.game_sessions(id,join_code,status,host_user_id) values(s,'PUBABC','ready',a);
 insert into public.session_players(session_id,user_id,role,join_command_id) values(s,a,'PLAYER_1','public-a'),(s,b,'PLAYER_2','public-b');
 insert into public.network_game_states(session_id,action_points) values(s,jsonb_build_object(a::text,100,b::text,100));
 insert into public.network_rounds(id,session_id,round_number,round_key) values(r,s,1,'public-round-1');
 ua:=pg_temp.make_usage('free-a','002',1,a,7);
 ua:=jsonb_set(ua,'{resolved_action}',((ua->'resolved_action')-'stage_id'-'zone_id')||jsonb_build_object('variant_id','002.zone.free','tags',jsonb_build_array('v3.preference.embrasser'),'action_text','Choisis librement une zone à embrasser.'));
 ua:=ua||jsonb_build_object('inverted_resolution',jsonb_build_object('snapshot_value',13,'resolved_action',
   jsonb_set(jsonb_set(jsonb_set(ua->'resolved_action','{direction}','"RECEVOIR"'),'{actor_player_ids}',jsonb_build_array(b)),'{target_player_ids}',jsonb_build_array(a))));
 ub:=pg_temp.make_usage('fixed-b','005',1,b,12);
 perform pg_temp.assert_true(public.network_usage_projection(ua,true)=ua,'free zone allowed by existing usage contract');
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform public.submit_network_round_commit(s,r,a,pg_temp.digest_choice('public-round-1',a,ua,'nonce-a'),'public-commit-a');
 perform set_config('request.jwt.claim.sub',b::text,true);
 perform public.submit_network_round_commit(s,r,b,pg_temp.digest_choice('public-round-1',b,ub,'nonce-b'),'public-commit-b');
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform public.submit_network_round_reveal(s,r,a,ua,'nonce-a','public-reveal-a');
 perform set_config('request.jwt.claim.sub',b::text,true);
 perform public.submit_network_round_reveal(s,r,b,ub,'nonce-b','public-reveal-b');
 perform pg_temp.assert_true(public.network_round_json(r,a)->'initial_duel_cards'='[]','no public duel cards before resolution');
 perform public.resolve_network_initial_private(s,r,b,'public-resolve');
 foreach who in array array[a,b] loop
   state:=public.network_round_json(r,who);
   public_cards:=state->'initial_duel_cards';
   perform pg_temp.assert_true(jsonb_array_length(public_cards)=2,'both duel cards available to both players');
   perform pg_temp.assert_true(state->'opponent_reveal'='null','opponent private reveal stays hidden');
   perform pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public_cards) c where c ? 'snapshot_value' or c ? 'inverted_resolution' or c ? 'nonce'),'no private values or nonces in public cards');
   perform pg_temp.assert_true(public_cards->0=ua-'snapshot_value'-'inverted_resolution','free snapshot preserved without anatomy or modifier');
   perform pg_temp.assert_true(public_cards->1=ub-'snapshot_value'-'inverted_resolution','fixed zone snapshot preserved');
   perform public.network_usage_projection(public_cards->0,false);
   perform public.network_usage_projection(public_cards->1,false);
 end loop;
 saved:=public_cards;
 -- Retry of the same reveal is still idempotent after the duel resolves.
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform public.submit_network_round_reveal(s,r,a,ua,'nonce-a','public-reveal-a');
 perform pg_temp.assert_true(public.network_round_json(r,a)->'initial_duel_cards'=saved,'retry leaves public snapshots unchanged');
 perform pg_temp.assert_true((select count(*)=2 from public.network_round_reveals where round_id=r),'one reveal per player');
 raise notice 'Public initial duel cards and free zone contract passed';
end; $$;
rollback;
