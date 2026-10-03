-- Directional PA: an accepted ABA inversion uses the committed opposite
-- personal value. This migration is additive and must be applied after 202610020001.

create or replace function public.validate_network_negotiation(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_accepted boolean,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_offer jsonb; v_points jsonb; v_winner uuid; v_loser uuid; v_final uuid;
  v_spend integer:=0; v_current integer; v_inverted boolean:=false; v_choice_owner uuid;
  v_initial_card jsonb; v_cards jsonb; v_payload jsonb; v_choice jsonb;
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
  select choice_payload into v_choice from public.network_round_reveals
    where round_id=p_round_id and player_id=v_choice_owner;
  if not found then raise exception 'ROUND_REVEAL_MISSING'; end if;
  if coalesce(v_choice#>>'{parameters,native_direction}',v_choice#>>'{parameters,role}','GENERAL')
      <> coalesce(v_choice#>>'{parameters,role}','GENERAL')
    or coalesce(v_choice#>>'{parameters,effective_direction}',v_choice#>>'{parameters,role}','GENERAL')
      <> coalesce(v_choice#>>'{parameters,role}','GENERAL') then
    raise exception 'ROUND_DIRECTION_MISMATCH';
  end if;
  if v_inverted and (
      coalesce(v_choice#>>'{parameters,role}','GENERAL') not in ('FAIRE','RECEVOIR')
      or coalesce(v_choice#>>'{parameters,opposite_personal_value}','') !~ '^[0-9]+$'
      or (v_choice#>>'{parameters,opposite_personal_value}')::integer not between 1 and 20
    ) then raise exception 'ROUND_INVERSION_UNAVAILABLE'; end if;
  select jsonb_build_object(
    'occurrence_id',coalesce(v_choice#>>'{parameters,occurrence_id}',p_round_id::text||':initial:'||v_choice_owner::text),
    'card_id',v_choice->>'card_id','variant_id',v_choice->>'variant_id',
    'owner_player_id',v_choice_owner,'native_direction',coalesce(v_choice#>>'{parameters,native_direction}',v_choice#>>'{parameters,role}','GENERAL'),
    'effective_direction',case coalesce(v_choice#>>'{parameters,effective_direction}',v_choice#>>'{parameters,role}','GENERAL')
      when 'FAIRE' then case when v_inverted then 'RECEVOIR' else 'FAIRE' end
      when 'RECEVOIR' then case when v_inverted then 'FAIRE' else 'RECEVOIR' end
      else coalesce(v_choice#>>'{parameters,effective_direction}',v_choice#>>'{parameters,role}','GENERAL') end,
    'origin','INITIAL_DUEL','snapshot_value',case when v_inverted
      then (v_choice#>>'{parameters,opposite_personal_value}')::integer
      else (v_choice#>>'{parameters,personal_value}')::integer end,
    'logical_order',0) into v_initial_card;
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
