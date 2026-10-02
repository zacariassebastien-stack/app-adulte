-- Final Network Gameplay V3 state: public cycle style/neutral shortages and
-- occurrence-aware initial, auction, corruption and recovery references.

alter table public.network_game_states
  add column if not exists deck_style text not null default 'SOFT'
    check (deck_style in ('SOFT','EPICE','INTENABLE'));

create or replace function public.network_round_json(p_round_id uuid, p_requester uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'schema_version',1,'round_id',r.id,'session_id',r.session_id,
    'session_round',r.round_key,'round_number',r.round_number,'phase',r.phase,
    'player_id',p_requester,'action_points',g.action_points,
    'hybrid_orientation',g.hybrid_orientation,'deck_cycle',g.deck_cycle,
    'infinite_mode',g.infinite_mode,'deck_style',g.deck_style,
    'deck_adjustment',g.deck_adjustment,
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
    'recovery_by_player',r.recovery_by_player,'recovery_done',r.recovery_done,
    'recovery_history',r.recovery_history
  ) from public.network_rounds r join public.network_game_states g on g.session_id=r.session_id
  where r.id=p_round_id;
$$;

drop function if exists public.continue_network_deck_cycle(uuid,uuid,uuid,text,text);
create function public.continue_network_deck_cycle(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_choice text,
  p_adjustment jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_command public.network_round_commands%rowtype; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if not exists(select 1 from public.session_players
    where session_id=p_session_id and user_id=p_player_id and role='PLAYER_1')
    then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  if p_choice not in ('CONTINUE_SPICIER','CONTINUE_INTENABLE','INFINITE','NEW_GAME','FINISH')
    or jsonb_typeof(p_adjustment)<>'object' then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  v_payload:=jsonb_build_object('choice',p_choice,'adjustment',p_adjustment);
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
    deck_style=case
      when p_choice='CONTINUE_INTENABLE' then 'INTENABLE'
      when p_choice='CONTINUE_SPICIER' and deck_style='SOFT' then 'EPICE'
      when p_choice='CONTINUE_SPICIER' then 'INTENABLE'
      else deck_style end,
    infinite_mode=case when p_choice='INFINITE' then true else infinite_mode end,
    deck_adjustment=p_adjustment,updated_at=now() where session_id=p_session_id;
  if p_choice in ('NEW_GAME','FINISH') then
    update public.game_sessions set status='closed' where id=p_session_id;
  end if;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;
revoke all on function public.continue_network_deck_cycle(uuid,uuid,uuid,text,jsonb,text) from public;
grant execute on function public.continue_network_deck_cycle(uuid,uuid,uuid,text,jsonb,text) to authenticated;

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
    'occurrence_id',coalesce(choice_payload#>>'{parameters,occurrence_id}',p_round_id::text||':initial:'||v_choice_owner::text),
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

create or replace function public.submit_network_corruption_offer(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_objective text,
  p_card_ids jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_actor uuid; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_objective not in ('OWN_INITIAL_ACTION','INVERT_WINNING_ACTION')
    or jsonb_typeof(p_card_ids)<>'array' or jsonb_array_length(p_card_ids)=0
    or exists(select 1 from jsonb_array_elements(p_card_ids) x
      where jsonb_typeof(x)<>'object' or coalesce(x->>'card_id','')='' or coalesce(x->>'occurrence_id','')='')
    or (select count(distinct x->>'occurrence_id') from jsonb_array_elements(p_card_ids) x)<>jsonb_array_length(p_card_ids)
    then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  v_payload:=jsonb_build_object('objective',p_objective,'cards',p_card_ids);
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'CORRUPTION_OFFER'
      or v_command.command_payload is distinct from v_payload then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'CORRUPTION_DECISION' then raise exception 'ROUND_INVALID_PHASE'; end if;
  select user_id into v_actor from public.session_players where session_id=p_session_id
    and user_id::text<>v_round.final_resolution->>'retained_player_id';
  if p_player_id<>v_actor then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  if exists (
    select 1 from jsonb_array_elements(p_card_ids) proposed
    where not exists (
      select 1 from public.network_round_reveals reveal
      join public.network_rounds previous on previous.id=reveal.round_id
      where previous.session_id=p_session_id and previous.round_number<v_round.round_number
        and reveal.player_id=p_player_id
        and coalesce(reveal.choice_payload#>>'{parameters,occurrence_id}',reveal.choice_payload->>'card_id')=proposed->>'occurrence_id'
    ) or exists (
      select 1 from public.network_rounds previous,
        jsonb_array_elements(coalesce(previous.corruption->'actions','[]'::jsonb)) action
      where previous.session_id=p_session_id and previous.round_number<v_round.round_number
        and previous.corruption->>'offered_by'=p_player_id::text
        and action->>'occurrence_id'=proposed->>'occurrence_id' and action->>'status'='COMPLETED'
    )
  ) then raise exception 'ROUND_CORRUPTION_FORBIDDEN'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_OFFER',v_payload);
  update public.network_rounds set corruption=jsonb_build_object(
    'offered_by',p_player_id,'objective',p_objective,'accepted',null,
    'actions',(select jsonb_agg(jsonb_build_object(
      'card_id',x->>'card_id','occurrence_id',x->>'occurrence_id','source','DISCARD',
      'status','PROPOSED','visibility','VISIBLE')) from jsonb_array_elements(p_card_ids) x)),
    phase='CORRUPTION_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;
