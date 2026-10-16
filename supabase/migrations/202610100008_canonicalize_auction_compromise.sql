-- Persist only the server-reconstructed canonical AUCTION cards. The raw
-- command payload remains private and is retained solely for idempotency checks.

create or replace function public.submit_network_negotiation_proposal(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,
  p_offer jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_available integer;
  v_direct integer;
  v_unlocked_spice integer;
  v_compromise jsonb;
  v_canonical_offer jsonb;
  v_winner uuid;
  v_loser uuid;
  v_choice jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands
  where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id
      or v_command.kind<>'NEGOTIATION_PROPOSAL'
      or v_command.command_payload is distinct from p_offer then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds
  where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase not in ('CORRUPTION_DECISION','NEGOTIATION_PROPOSAL') then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  if v_round.phase='CORRUPTION_DECISION' then
    v_winner:=coalesce(
      (v_round.final_resolution->>'final_winner_player_id')::uuid,
      (v_round.final_resolution->>'retained_player_id')::uuid
    );
    select user_id into v_loser from public.session_players
    where session_id=p_session_id and user_id<>v_winner;
  else
    -- Compatibility for a negotiation persisted before this migration.
    v_winner:=(v_round.initial_resolution->>'winner_player_id')::uuid;
    v_loser:=(v_round.initial_resolution->>'loser_player_id')::uuid;
  end if;
  if p_player_id is distinct from v_loser then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  if jsonb_typeof(p_offer)<>'object'
    or jsonb_typeof(p_offer->'cards')<>'array'
    or coalesce((p_offer->>'direct_pa')::integer,-1)<0
    or jsonb_typeof(p_offer->'inversion_requested') is distinct from 'boolean'
    or (
      not (p_offer->>'inversion_requested')::boolean
      and (p_offer->>'direct_pa')::integer=0
      and jsonb_array_length(p_offer->'cards')=0
    ) then
    raise exception 'ROUND_NEGOTIATION_INVALID';
  end if;
  v_canonical_offer:=p_offer;
  v_direct:=(p_offer->>'direct_pa')::integer;
  select (action_points->>p_player_id::text)::integer,v4_unlocked_spice
  into v_available,v_unlocked_spice
  from public.network_game_states
  where session_id=p_session_id for update;
  if v_direct>v_available then raise exception 'ROUND_INSUFFICIENT_PA'; end if;
  if v_available<10 and v_direct>0 then raise exception 'ROUND_INVALID_BID'; end if;
  if (p_offer->>'inversion_requested')::boolean then
    select choice_payload into v_choice from public.network_round_reveals
    where round_id=p_round_id and player_id=v_loser;
    if not found
      or coalesce(v_choice#>>'{parameters,role}','GENERAL') not in ('FAIRE','RECEVOIR')
      or coalesce(v_choice#>>'{parameters,opposite_personal_value}','') !~ '^[0-9]+$'
      or (v_choice#>>'{parameters,opposite_personal_value}')::integer not between 1 and 20 then
      raise exception 'ROUND_INVERSION_FORBIDDEN';
    end if;
  end if;
  if (select count(*) from jsonb_array_elements(p_offer->'cards')) <>
     (select count(distinct x->>'occurrence_id')
      from jsonb_array_elements(p_offer->'cards') x) then
    raise exception 'ROUND_AUCTION_CARD_REUSED';
  end if;
  if exists(
    select 1 from jsonb_array_elements(p_offer->'cards') x where
      x->>'owner_player_id'<>p_player_id::text or x->>'origin'<>'AUCTION'
      or x->>'native_direction'<>x->>'effective_direction'
      or (x->>'snapshot_value')::integer not between 1 and 20
  ) then
    raise exception 'ROUND_NEGOTIATION_INVALID';
  end if;
  if jsonb_array_length(p_offer->'cards')>0 then
    v_compromise:=public.v4_corruption_compromise(
      p_session_id,v_round.round_number,p_player_id,p_offer->'cards'
    );
    if v_unlocked_spice is null or exists(
      select 1 from jsonb_array_elements(v_compromise) card
      where (card->>'effective_spice')::integer>v_unlocked_spice
    ) then
      raise exception 'ROUND_NEGOTIATION_INVALID';
    end if;
    select coalesce(jsonb_agg(
      card||jsonb_build_object('origin','AUCTION') order by ordinality
    ),'[]'::jsonb) into v_compromise
    from jsonb_array_elements(v_compromise)
      with ordinality as canonical(card,ordinality);
    v_canonical_offer:=jsonb_set(
      p_offer,'{cards}',v_compromise,true
    );
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(
    p_command_id,p_session_id,p_round_id,p_player_id,
    'NEGOTIATION_PROPOSAL',p_offer
  );
  update public.network_rounds set negotiation=jsonb_build_object(
    'offered_by',p_player_id,
    'proposal',v_canonical_offer,
    'response',null,
    'final_offer',null
  ),phase='NEGOTIATION_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

