-- Network Gameplay V3: bounded ABA negotiation and public compromise.
-- Private hands, deck order, profile values and learning remain client-local.

alter table public.network_rounds drop constraint network_rounds_phase_check;
alter table public.network_rounds add constraint network_rounds_phase_check check (phase in (
  'COMMIT','REVEAL','READY','NEGOTIATION_PROPOSAL','NEGOTIATION_RESPONSE',
  'NEGOTIATION_ADAPTATION','NEGOTIATION_VALIDATION','COUNTER_DECISION',
  'FINAL_DEFENSE_DECISION','TIE_DECISION','FINAL_RESOLVED',
  'CORRUPTION_DECISION','CORRUPTION_RESPONSE','CORRUPTION_EXECUTION',
  'RECOVERY','RECOVERY_RESPONSE','RECOVERY_EXECUTION','WAITING_NEXT','CLOSED'
));

alter table public.network_rounds
  add column negotiation jsonb not null default '{}'::jsonb
  check (jsonb_typeof(negotiation) = 'object');
alter table public.network_rounds
  add column recovery_history jsonb not null default '[]'::jsonb
  check (jsonb_typeof(recovery_history) = 'array');

alter table public.network_game_states
  add column hybrid_orientation text not null default 'FACE_TO_FACE'
    check (hybrid_orientation in ('FACE_TO_FACE','DISTANCE')),
  add column deck_cycle integer not null default 1 check (deck_cycle > 0),
  add column infinite_mode boolean not null default false,
  add column deck_adjustment jsonb not null default '{}'::jsonb
    check (jsonb_typeof(deck_adjustment) = 'object');

alter table public.network_round_commands drop constraint network_round_commands_kind_check;
alter table public.network_round_commands add constraint network_round_commands_kind_check check (kind in (
  'CREATE','OPEN','COMMIT','REVEAL','INITIAL_RESOLVE','NEGOTIATION_PROPOSAL',
  'NEGOTIATION_RESPONSE','NEGOTIATION_ADAPTATION','NEGOTIATION_VALIDATION',
  'SET_ORIENTATION','CONTINUE_CYCLE',
  'COUNTER_DECISION','FINAL_DEFENSE','TIE_DECISION','READY_NEXT',
  'CORRUPTION_OFFER','CORRUPTION_RESPONSE','CORRUPTION_RESOLVE',
  'CORRUPTION_SKIP','RECOVERY','RECOVERY_RESPONSE','RECOVERY_RESOLVE','RECOVERY_SKIP'
));

create or replace function public.network_round_json(p_round_id uuid, p_requester uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'schema_version',1,'round_id',r.id,'session_id',r.session_id,
    'session_round',r.round_key,'round_number',r.round_number,'phase',r.phase,
    'player_id',p_requester,'action_points',g.action_points,
    'hybrid_orientation',g.hybrid_orientation,'deck_cycle',g.deck_cycle,
    'infinite_mode',g.infinite_mode,'deck_adjustment',g.deck_adjustment,
    'commits',coalesce((select jsonb_object_agg(c.player_id::text,c.digest)
      from public.network_round_commits c where c.round_id=r.id),'{}'::jsonb),
    'own_reveal',(select jsonb_build_object('schema_version',1,
      'session_round',r.round_key,'player_id',v.player_id,'choice',v.choice_payload,'nonce',v.nonce)
      from public.network_round_reveals v where v.round_id=r.id and v.player_id=p_requester),
    'opponent_reveal',case when r.phase='READY' then (select jsonb_build_object(
      'schema_version',1,'session_round',r.round_key,'player_id',v.player_id,
      'choice',v.choice_payload,'nonce',v.nonce) from public.network_round_reveals v
      where v.round_id=r.id and v.player_id<>p_requester) else null end,
    'initial_resolution',r.initial_resolution,'negotiation',r.negotiation,
    'counter_bid',r.counter_bid,'final_defense',r.final_defense,
    'final_resolution',r.final_resolution,'ready_next',r.ready_next,
    'tie_decisions',r.tie_decisions,'corruption',r.corruption,
    'recovery_by_player',r.recovery_by_player,'recovery_done',r.recovery_done
    ,'recovery_history',r.recovery_history
  ) from public.network_rounds r join public.network_game_states g on g.session_id=r.session_id
  where r.id=p_round_id;
$$;

create or replace function public.submit_network_initial_resolution(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_resolution jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_current jsonb; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_resolution is null or jsonb_typeof(p_resolution)<>'object' then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'INITIAL_RESOLVE' or v_command.command_payload is distinct from p_resolution
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'READY' then
    if v_round.initial_resolution=p_resolution then
      insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
        values(p_command_id,p_session_id,p_round_id,p_player_id,'INITIAL_RESOLVE',p_resolution);
      return public.network_round_json(p_round_id,p_player_id);
    end if;
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  select action_points into v_current from public.network_game_states where session_id=p_session_id for update;
  if p_resolution->'action_points' is distinct from v_current
    or (p_resolution->>'gap')::integer<0 or (p_resolution->>'gap_cost')::integer<0
    or (p_resolution->>'high_value')::integer not between 1 and 20
    then raise exception 'ROUND_RESOLUTION_MISMATCH'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'INITIAL_RESOLVE',p_resolution);
  update public.network_rounds set initial_resolution=p_resolution,
    phase=case when (p_resolution->>'tied')::boolean then 'TIE_DECISION' else 'NEGOTIATION_PROPOSAL' end,
    updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.submit_network_negotiation_proposal(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_offer jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_available integer; v_direct integer;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'NEGOTIATION_PROPOSAL' or v_command.command_payload is distinct from p_offer
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'NEGOTIATION_PROPOSAL' then raise exception 'ROUND_INVALID_PHASE'; end if;
  if p_player_id::text<>v_round.initial_resolution->>'loser_player_id' then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  if jsonb_typeof(p_offer)<>'object' or jsonb_typeof(p_offer->'cards')<>'array'
    or (p_offer->>'direct_pa')::integer<0 then raise exception 'ROUND_NEGOTIATION_INVALID'; end if;
  v_direct:=(p_offer->>'direct_pa')::integer;
  select (action_points->>p_player_id::text)::integer into v_available
    from public.network_game_states where session_id=p_session_id for update;
  if v_direct>v_available then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
  if v_available<10 and v_direct>0 then raise exception 'ROUND_INVALID_BID'; end if;
  if (p_offer->>'inversion_requested')::boolean and not (v_round.initial_resolution->>'inversion_allowed')::boolean
    then raise exception 'ROUND_INVERSION_FORBIDDEN'; end if;
  if (select count(*) from jsonb_array_elements(p_offer->'cards')) <>
     (select count(distinct x->>'occurrence_id') from jsonb_array_elements(p_offer->'cards') x)
    then raise exception 'ROUND_AUCTION_CARD_REUSED'; end if;
  if exists(select 1 from jsonb_array_elements(p_offer->'cards') x where
      x->>'owner_player_id'<>p_player_id::text or x->>'origin'<>'AUCTION'
      or x->>'native_direction'<>x->>'effective_direction'
      or (x->>'snapshot_value')::integer not between 1 and 20)
    then raise exception 'ROUND_NEGOTIATION_INVALID'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'NEGOTIATION_PROPOSAL',p_offer);
  update public.network_rounds set negotiation=jsonb_build_object('proposal',p_offer,'response',null,'final_offer',null),
    phase='NEGOTIATION_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.respond_network_negotiation(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_response jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_offer jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'NEGOTIATION_RESPONSE' or v_command.command_payload is distinct from p_response
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'NEGOTIATION_RESPONSE' or p_player_id::text<>v_round.initial_resolution->>'winner_player_id'
    then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  v_offer:=v_round.negotiation->'proposal';
  if ((p_response->>'accept_inversion')::boolean and not (v_offer->>'inversion_requested')::boolean)
    or ((p_response->>'accept_auction')::boolean and
      (coalesce((v_offer->>'direct_pa')::integer,0)+coalesce((select sum((x->>'snapshot_value')::integer)
        from jsonb_array_elements(v_offer->'cards') x),0)=0))
    then raise exception 'ROUND_NEGOTIATION_INVALID'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'NEGOTIATION_RESPONSE',p_response);
  update public.network_rounds set negotiation=jsonb_set(negotiation,'{response}',p_response),
    phase='NEGOTIATION_ADAPTATION',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.adapt_network_negotiation(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_offer jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_response jsonb; v_available integer; v_direct integer;
  v_command public.network_round_commands%rowtype;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'NEGOTIATION_ADAPTATION' or v_command.command_payload is distinct from p_offer
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'NEGOTIATION_ADAPTATION' or p_player_id::text<>v_round.initial_resolution->>'loser_player_id'
    then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  v_response:=v_round.negotiation->'response'; v_direct:=(p_offer->>'direct_pa')::integer;
  select (action_points->>p_player_id::text)::integer into v_available from public.network_game_states
    where session_id=p_session_id for update;
  if v_direct<0 or v_direct>v_available or (v_available<10 and v_direct>0)
    then raise exception 'ROUND_INVALID_BID'; end if;
  if (p_offer->>'inversion_requested')::boolean and not (v_response->>'accept_inversion')::boolean
    then raise exception 'ROUND_NEGOTIATION_INVALID'; end if;
  if (v_direct>0 or jsonb_array_length(p_offer->'cards')>0) and not (v_response->>'accept_auction')::boolean
    then raise exception 'ROUND_NEGOTIATION_INVALID'; end if;
  if (select count(*) from jsonb_array_elements(p_offer->'cards')) <>
     (select count(distinct x->>'occurrence_id') from jsonb_array_elements(p_offer->'cards') x)
    then raise exception 'ROUND_AUCTION_CARD_REUSED'; end if;
  if exists(select 1 from jsonb_array_elements(p_offer->'cards') x where x->>'owner_player_id'<>p_player_id::text
    or x->>'origin'<>'AUCTION' or x->>'native_direction'<>x->>'effective_direction')
    then raise exception 'ROUND_NEGOTIATION_INVALID'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'NEGOTIATION_ADAPTATION',p_offer);
  update public.network_rounds set negotiation=jsonb_set(negotiation,'{final_offer}',p_offer),
    phase='NEGOTIATION_VALIDATION',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.validate_network_negotiation(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_accepted boolean,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_offer jsonb; v_points jsonb; v_winner uuid; v_loser uuid; v_final uuid;
  v_spend integer:=0; v_current integer; v_inverted boolean:=false; v_choice_owner uuid;
  v_initial_card jsonb; v_cards jsonb; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  v_payload:=jsonb_build_object('accepted',p_accepted);
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'NEGOTIATION_VALIDATION' or v_command.command_payload is distinct from v_payload
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  v_winner:=(v_round.initial_resolution->>'winner_player_id')::uuid;
  v_loser:=(v_round.initial_resolution->>'loser_player_id')::uuid;
  if v_round.phase<>'NEGOTIATION_VALIDATION' or p_player_id<>v_winner then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  v_offer:=v_round.negotiation->'final_offer';
  v_inverted:=p_accepted and (v_offer->>'inversion_requested')::boolean;
  v_final:=case when p_accepted and (v_inverted or (v_offer->>'direct_pa')::integer>0
    or jsonb_array_length(v_offer->'cards')>0) then v_loser else v_winner end;
  v_choice_owner:=case when v_inverted then v_winner else v_final end;
  select jsonb_build_object(
    'occurrence_id',p_round_id::text||':initial:'||v_choice_owner::text,
    'card_id',choice_payload->>'card_id','variant_id',choice_payload->>'variant_id',
    'owner_player_id',v_choice_owner,'native_direction',coalesce(choice_payload#>>'{parameters,role}','GENERAL'),
    'effective_direction',case coalesce(choice_payload#>>'{parameters,role}','GENERAL')
      when 'FAIRE' then case when v_inverted then 'RECEVOIR' else 'FAIRE' end
      when 'RECEVOIR' then case when v_inverted then 'FAIRE' else 'RECEVOIR' end
      else coalesce(choice_payload#>>'{parameters,role}','GENERAL') end,
    'origin','INITIAL_DUEL','snapshot_value',(choice_payload#>>'{parameters,personal_value}')::integer,
    'logical_order',0) into v_initial_card from public.network_round_reveals
    where round_id=p_round_id and player_id=v_choice_owner;
  v_cards:=jsonb_build_array(v_initial_card);
  if p_accepted then v_cards:=v_cards||coalesce(v_offer->'cards','[]'::jsonb); end if;
  select action_points into v_points from public.network_game_states where session_id=p_session_id for update;
  if v_final=v_winner then
    v_current:=(v_points->>v_winner::text)::integer;
    v_points:=jsonb_set(v_points,array[v_winner::text],to_jsonb(greatest(0,v_current-(v_round.initial_resolution->>'gap_cost')::integer)));
  else
    v_spend:=(v_offer->>'direct_pa')::integer + case when v_inverted then (v_round.initial_resolution->>'high_value')::integer else 0 end;
    v_current:=(v_points->>v_loser::text)::integer;
    if v_spend>v_current then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
    v_points:=jsonb_set(v_points,array[v_loser::text],to_jsonb(v_current-v_spend));
  end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'NEGOTIATION_VALIDATION',v_payload);
  update public.network_game_states set action_points=v_points,updated_at=now() where session_id=p_session_id;
  update public.network_rounds set final_resolution=jsonb_build_object(
      'retained_player_id',v_final,'initial_winner_player_id',v_winner,'final_winner_player_id',v_final,
      'card_id',v_initial_card->>'card_id','variant_id',v_initial_card->>'variant_id',
      'inverted',v_inverted,'mutual_abandon',false,'compromise',v_cards),
    phase='FINAL_RESOLVED',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.route_network_post_duel() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.phase='FINAL_RESOLVED' and old.phase in (
    'NEGOTIATION_VALIDATION','COUNTER_DECISION','FINAL_DEFENSE_DECISION','TIE_DECISION'
  ) then
    new.phase:=case when new.final_resolution->>'retained_player_id' is null
      then 'RECOVERY' else 'CORRUPTION_DECISION' end;
  end if;
  return new;
end; $$;

revoke all on function public.submit_network_negotiation_proposal(uuid,uuid,uuid,jsonb,text) from public;
revoke all on function public.respond_network_negotiation(uuid,uuid,uuid,jsonb,text) from public;
revoke all on function public.adapt_network_negotiation(uuid,uuid,uuid,jsonb,text) from public;
revoke all on function public.validate_network_negotiation(uuid,uuid,uuid,boolean,text) from public;
grant execute on function public.submit_network_negotiation_proposal(uuid,uuid,uuid,jsonb,text) to authenticated;
grant execute on function public.respond_network_negotiation(uuid,uuid,uuid,jsonb,text) to authenticated;
grant execute on function public.adapt_network_negotiation(uuid,uuid,uuid,jsonb,text) to authenticated;
grant execute on function public.validate_network_negotiation(uuid,uuid,uuid,boolean,text) to authenticated;

create function public.set_network_hybrid_orientation(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_orientation text,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_command public.network_round_commands%rowtype; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_orientation not in ('FACE_TO_FACE','DISTANCE') then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  v_payload:=jsonb_build_object('orientation',p_orientation);
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.player_id<>p_player_id
      or v_command.kind<>'SET_ORIENTATION' or v_command.command_payload is distinct from v_payload
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'SET_ORIENTATION',v_payload);
  update public.network_game_states set hybrid_orientation=p_orientation,updated_at=now() where session_id=p_session_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create function public.continue_network_deck_cycle(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_choice text,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_command public.network_round_commands%rowtype; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_choice not in ('CONTINUE_SPICIER','CONTINUE_INTENABLE','INFINITE','NEW_GAME','FINISH')
    then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  v_payload:=jsonb_build_object('choice',p_choice);
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.player_id<>p_player_id
      or v_command.kind<>'CONTINUE_CYCLE' or v_command.command_payload is distinct from v_payload
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'CONTINUE_CYCLE',v_payload);
  update public.network_game_states set
    deck_cycle=case when p_choice in ('CONTINUE_SPICIER','CONTINUE_INTENABLE','INFINITE') then deck_cycle+1 else deck_cycle end,
    infinite_mode=case when p_choice='INFINITE' then true else infinite_mode end,
    updated_at=now() where session_id=p_session_id;
  if p_choice in ('NEW_GAME','FINISH') then update public.game_sessions set status='closed' where id=p_session_id; end if;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

revoke all on function public.set_network_hybrid_orientation(uuid,uuid,uuid,text,text) from public;
revoke all on function public.continue_network_deck_cycle(uuid,uuid,uuid,text,text) from public;
grant execute on function public.set_network_hybrid_orientation(uuid,uuid,uuid,text,text) to authenticated;
grant execute on function public.continue_network_deck_cycle(uuid,uuid,uuid,text,text) to authenticated;

-- A completed Recovery no longer marks the player as done. The player may
-- propose again while still at <=10 PA; only RECOVERY_SKIP exits the loop.
create or replace function public.submit_network_recovery(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_recovery jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype; v_current integer;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_recovery->>'player_id'<>p_player_id::text or p_recovery->>'source' not in ('HAND','DISCARD','CATALOG')
    or (p_recovery->>'gain')::integer<>0 or (p_recovery->>'completed')::boolean or p_recovery->>'response' is not null
    then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'RECOVERY' or v_command.command_payload is distinct from p_recovery
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  select (action_points->>p_player_id::text)::integer into v_current from public.network_game_states
    where session_id=p_session_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'RECOVERY' or v_round.recovery_done ? p_player_id::text or v_current>10
    then raise exception 'ROUND_RECOVERY_NOT_ELIGIBLE'; end if;
  if exists(select 1 from jsonb_array_elements(v_round.recovery_history) x
    where x->>'occurrence_id'=p_recovery->>'occurrence_id') then raise exception 'ROUND_AUCTION_CARD_REUSED'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY',p_recovery);
  update public.network_rounds set recovery_by_player=jsonb_set(recovery_by_player,array[p_player_id::text],p_recovery),
    phase='RECOVERY_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.respond_network_recovery(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_response text,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_proposer text; v_payload jsonb; v_item jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_response not in ('ACCEPT','REFUSE') then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  v_payload:=jsonb_build_object('response',p_response); perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'RECOVERY_RESPONSE' or v_command.command_payload is distinct from v_payload
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  select key,value into v_proposer,v_item from jsonb_each(v_round.recovery_by_player) item limit 1;
  if v_round.phase<>'RECOVERY_RESPONSE' or v_proposer is null or v_proposer=p_player_id::text
    then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY_RESPONSE',v_payload);
  if p_response='REFUSE' then
    v_item:=jsonb_set(v_item,'{response}','"REFUSE"'::jsonb);
    update public.network_rounds set recovery_history=recovery_history||jsonb_build_array(v_item),
      recovery_by_player=recovery_by_player-v_proposer,phase='RECOVERY',updated_at=now() where id=p_round_id;
  else
    update public.network_rounds set recovery_by_player=jsonb_set(recovery_by_player,array[v_proposer,'response'],'"ACCEPT"'::jsonb),
      phase='RECOVERY_EXECUTION',updated_at=now() where id=p_round_id;
  end if;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.resolve_network_recovery(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_recovery jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_points jsonb; v_current integer; v_gain integer; v_existing jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_recovery->>'player_id'<>p_player_id::text or p_recovery->>'response'<>'ACCEPT'
    or (p_recovery->>'gain')::integer not between 0 and 30 then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'RECOVERY_RESOLVE' or v_command.command_payload is distinct from p_recovery
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  v_existing:=v_round.recovery_by_player->p_player_id::text;
  if v_round.phase<>'RECOVERY_EXECUTION' or v_existing is null
    or v_existing->>'occurrence_id'<>p_recovery->>'occurrence_id'
    then raise exception 'ROUND_RECOVERY_NOT_ELIGIBLE'; end if;
  select action_points into v_points from public.network_game_states where session_id=p_session_id for update;
  v_current:=(v_points->>p_player_id::text)::integer; v_gain:=(p_recovery->>'gain')::integer;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY_RESOLVE',p_recovery);
  update public.network_game_states set action_points=jsonb_set(v_points,array[p_player_id::text],to_jsonb(v_current+v_gain)),updated_at=now()
    where session_id=p_session_id;
  update public.network_rounds set recovery_history=recovery_history||jsonb_build_array(p_recovery),
    recovery_by_player=recovery_by_player-p_player_id::text,phase='RECOVERY',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;
