-- Run after all migrations against a fresh, disposable local test database.
begin;
do $$ begin
  if current_database() not like 'concept_usage_test%' then
    raise exception 'Local test database required';
  end if;
end; $$;

create function pg_temp.assert_pa(p_condition boolean,p_message text)
returns void language plpgsql as $$ begin
  if p_condition is not true then raise exception 'TEST FAILED: %',p_message; end if;
end; $$;

do $$
declare
  a uuid:='11111111-1111-1111-1111-111111111111';
  b uuid:='22222222-2222-2222-2222-222222222222';
  s uuid:='00000000-0000-0000-0000-000000000180';
  r uuid:='00000000-0000-0000-0000-000000000181';
  fixture record; g public.network_game_states%rowtype; state jsonb;
begin
  insert into auth.users(id) values(a),(b);
  insert into public.game_sessions(id,join_code,status,host_user_id)
    values(s,'PATEST','ready',a);
  insert into public.session_players(session_id,user_id,role,join_command_id)
    values(s,a,'PLAYER_1','pa-join-a'),(s,b,'PLAYER_2','pa-join-b');
  insert into public.network_rounds(id,session_id,round_number,round_key,phase)
    values(r,s,1,'pa-round-1','COMMIT');

  -- Every boundary: just before, exactly at, just after. Each update starts at
  -- level 1, so levels 3/4 also exercise multiple thresholds in one operation.
  for fixture in select * from (values
    ('SOFT',0,1),('SOFT',39,1),('SOFT',40,2),('SOFT',41,2),
    ('SOFT',99,2),('SOFT',100,3),('SOFT',101,3),
    ('SOFT',149,3),('SOFT',150,4),('SOFT',151,4),
    ('EPICE',0,1),('EPICE',29,1),('EPICE',30,2),('EPICE',31,2),
    ('EPICE',74,2),('EPICE',75,3),('EPICE',76,3),
    ('EPICE',119,3),('EPICE',120,4),('EPICE',121,4),
    ('INTENABLE',0,1),('INTENABLE',19,1),('INTENABLE',20,2),('INTENABLE',21,2),
    ('INTENABLE',54,2),('INTENABLE',55,3),('INTENABLE',56,3),
    ('INTENABLE',89,3),('INTENABLE',90,4),('INTENABLE',91,4)
  ) as cases(style,spent,level) loop
    delete from public.network_game_states where session_id=s;
    insert into public.network_game_states(session_id,action_points,deck_style)
      values(s,jsonb_build_object(a::text,100,b::text,100),fixture.style);
    perform pg_temp.assert_pa((select v4_unlocked_spice=1
      from public.network_game_states where session_id=s),'starts at 1');
    update public.network_game_states set action_points=jsonb_build_object(
      a::text,100-least(100,fixture.spent),b::text,100-greatest(0,fixture.spent-100))
      where session_id=s returning * into g;
    perform pg_temp.assert_pa(g.v4_unlocked_spice=fixture.level,
      fixture.style||' at '||fixture.spent);
    perform pg_temp.assert_pa(public.network_total_pa_spent(s,g.action_points)=fixture.spent,
      'gross total includes both players');
    -- Retries/no-op state updates and reads do not invent a second expense.
    update public.network_game_states set action_points=action_points where session_id=s;
    perform set_config('request.jwt.claim.sub',a::text,true);
    state:=public.get_current_network_game_round(s,a);
    perform pg_temp.assert_pa((state->>'v4_unlocked_spice')::integer=fixture.level,
      'canonical read/reconnect preserves level');
    state:=public.publish_network_v4_unlocked_spice(s,r,a,4,'legacy-pa-spice');
    perform pg_temp.assert_pa((state->>'v4_unlocked_spice')::integer=fixture.level,
      'legacy pool publication cannot unlock spice');
  end loop;

  -- No debit: displayed/proposed PA, reservation/commit and refused offers
  -- only write round/command state. They must leave the PA ceiling untouched.
  delete from public.network_game_states where session_id=s;
  insert into public.network_game_states(session_id,action_points)
    values(s,jsonb_build_object(a::text,100,b::text,100));
  -- Neither player's individual spending reaches 40; their combined 40 does.
  update public.network_game_states set action_points=jsonb_build_object(a::text,80,b::text,80)
    where session_id=s returning * into g;
  perform pg_temp.assert_pa(g.v4_unlocked_spice=2
    and public.network_total_pa_spent(s,g.action_points)=40,'shared spending, not a per-player threshold');
  delete from public.network_game_states where session_id=s;
  insert into public.network_game_states(session_id,action_points)
    values(s,jsonb_build_object(a::text,100,b::text,100));
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values('pa-proposal',s,r,a,'NEGOTIATION_PROPOSAL','{"direct_pa":150}'),
          ('pa-refusal',s,r,b,'NEGOTIATION_RESPONSE','{"accepted":false}');
  update public.network_rounds set negotiation='{"proposal":{"direct_pa":150},"response":{"accepted":false}}'
    where id=r;
  select * into g from public.network_game_states where session_id=s;
  perform pg_temp.assert_pa(g.v4_unlocked_spice=1
    and public.network_total_pa_spent(s,g.action_points)=0,'no debit, no progression');
  begin
    update public.network_game_states set action_points=jsonb_build_object(a::text,0,b::text,50)
      where session_id=s;
    raise exception 'pa-test-rollback';
  exception when raise_exception then
    if sqlerrm<>'pa-test-rollback' then raise; end if;
  end;
  select * into g from public.network_game_states where session_id=s;
  perform pg_temp.assert_pa(g.v4_unlocked_spice=1
    and public.network_total_pa_spent(s,g.action_points)=0,'rolled-back debit cannot unlock spice');

  update public.network_game_states set action_points=jsonb_build_object(a::text,10,b::text,100)
    where session_id=s;
  -- A canonical Recovery credit is not a negative expense. Only the journaled
  -- credit counts, not proposed gains or duplicated public Recovery snapshots.
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values('pa-recovery-resolve',s,r,a,'RECOVERY_RESOLVE','{"gain":30}');
  update public.network_game_states set action_points=jsonb_build_object(a::text,40,b::text,100)
    where session_id=s returning * into g;
  perform pg_temp.assert_pa(public.network_total_pa_spent(s,g.action_points)=90
    and g.v4_unlocked_spice=2,'Recovery preserves cumulative spending');
  update public.network_game_states set action_points=jsonb_build_object(a::text,30,b::text,100)
    where session_id=s returning * into g;
  perform pg_temp.assert_pa(public.network_total_pa_spent(s,g.action_points)=100
    and g.v4_unlocked_spice=3,'spending recovered PA advances cumulative total');
  update public.network_game_states set deck_cycle=deck_cycle+1,deck_style='INTENABLE'
    where session_id=s returning * into g;
  perform pg_temp.assert_pa(public.network_total_pa_spent(s,g.action_points)=100
    and g.v4_unlocked_spice=4,'cycle/style change retains session spending');
  update public.network_game_states set deck_style='SOFT',v4_unlocked_spice=1
    where session_id=s returning * into g;
  perform pg_temp.assert_pa(g.v4_unlocked_spice=4,'spice never decreases');
  raise notice 'PASS PA thresholds, gross total, Recovery, cycles and legacy publication';
end; $$;
rollback;
