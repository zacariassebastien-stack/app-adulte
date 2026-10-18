-- Resolve accepted compromise inversions from the initial winning reveal.
create or replace function public.respond_network_negotiation(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,
  p_response jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_offer jsonb;
  v_points jsonb;
  v_winner uuid;
  v_loser uuid;
  v_accepted boolean;
  v_spend integer;
  v_current integer;
  v_inverted boolean;
  v_choice jsonb;
  v_initial_card jsonb;
  v_cards jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if jsonb_typeof(p_response->'accepted') is distinct from 'boolean' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_accepted:=(p_response->>'accepted')::boolean;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands
  where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id
      or v_command.kind<>'NEGOTIATION_RESPONSE'
      or v_command.command_payload is distinct from p_response then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds
  where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase<>'NEGOTIATION_RESPONSE' then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  v_offer:=v_round.negotiation->'proposal';
  v_loser:=coalesce(
    (v_round.negotiation->>'offered_by')::uuid,
    (v_round.initial_resolution->>'loser_player_id')::uuid
  );
  v_winner:=coalesce(
    (v_round.final_resolution->>'final_winner_player_id')::uuid,
    (v_round.final_resolution->>'retained_player_id')::uuid
  );
  if v_winner is null or v_winner=v_loser then
    raise exception 'ROUND_NEGOTIATION_INVALID';
  end if;
  if p_player_id is distinct from v_winner then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  if jsonb_typeof(v_offer)<>'object' then
    raise exception 'ROUND_NEGOTIATION_INVALID';
  end if;
  v_inverted:=v_accepted and (v_offer->>'inversion_requested')::boolean;

  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(
    p_command_id,p_session_id,p_round_id,p_player_id,
    'NEGOTIATION_RESPONSE',p_response
  );

  if not v_accepted then
    update public.network_rounds set negotiation=jsonb_set(
      jsonb_set(negotiation,'{response}',p_response,true),
      '{final_offer}','null'::jsonb,true
    ),phase='FINAL_RESOLVED',updated_at=now() where id=p_round_id;
    return public.network_round_json(p_round_id,p_player_id);
  end if;

  select choice_payload into v_choice from public.network_round_reveals
  -- Only inversion targets the initial winning action; ordinary compromises
  -- retain the losing action as before.
  where round_id=p_round_id and player_id=case when v_inverted
    then (v_round.initial_resolution->>'winner_player_id')::uuid else v_loser end;
  if not found then raise exception 'ROUND_REVEAL_MISSING'; end if;
  if coalesce(v_choice#>>'{native_direction}',
      v_choice#>>'{resolved_action,direction}','GENERAL') <>
     coalesce(v_choice#>>'{effective_direction}',
      v_choice#>>'{resolved_action,direction}','GENERAL') then
    raise exception 'ROUND_DIRECTION_MISMATCH';
  end if;
  if v_inverted and (
    coalesce(v_choice#>>'{resolved_action,direction}','GENERAL') not in ('FAIRE','RECEVOIR')
    or coalesce(v_choice#>>'{inverted_resolution,snapshot_value}','') !~ '^[0-9]+$'
    or (v_choice#>>'{inverted_resolution,snapshot_value}')::integer not between 1 and 20
  ) then
    raise exception 'ROUND_INVERSION_UNAVAILABLE';
  end if;
  v_initial_card:=public.network_usage_resolution(v_choice,v_inverted)
    ||jsonb_build_object('origin','INITIAL_DUEL','logical_order',0);
  v_cards:=jsonb_build_array(v_initial_card)||coalesce(v_offer->'cards','[]'::jsonb);

  select action_points into v_points from public.network_game_states
  where session_id=p_session_id for update;
  v_spend:=(v_offer->>'direct_pa')::integer
    + case when v_inverted
      then (v_round.initial_resolution->>'high_value')::integer else 0 end;
  v_current:=(v_points->>v_loser::text)::integer;
  if v_spend>v_current then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
  v_points:=jsonb_set(
    v_points,array[v_loser::text],to_jsonb(v_current-v_spend)
  );
  update public.network_game_states set action_points=v_points,updated_at=now()
  where session_id=p_session_id;
  update public.network_rounds set
    negotiation=jsonb_set(
      jsonb_set(negotiation,'{response}',p_response,true),
      '{final_offer}',v_offer,true
    ),
    final_resolution=jsonb_build_object(
      'retained_player_id',v_loser,
      'initial_winner_player_id',coalesce(
        v_round.final_resolution->>'initial_winner_player_id',
        v_round.initial_resolution->>'winner_player_id'
      ),
      'final_winner_player_id',v_winner,
      'concept_id',v_initial_card->>'concept_id',
      'usage_id',v_initial_card->>'usage_id',
      'inverted',v_inverted,
      'mutual_abandon',false,
      'compromise',v_cards
    ),
    phase='FINAL_RESOLVED',updated_at=now()
  where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;
