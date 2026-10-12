-- Persist the second and final use of discard occurrences accepted in a
-- compromise. The state is private per requester in network_round_json and is
-- reset whenever a new deck cycle starts.

alter table public.network_game_states
  add column if not exists v4_consumed_occurrences jsonb not null default '{}'::jsonb;

alter table public.network_game_states
  drop constraint if exists network_game_states_v4_consumed_occurrences_check;
alter table public.network_game_states
  add constraint network_game_states_v4_consumed_occurrences_check
  check (jsonb_typeof(v4_consumed_occurrences)='object');

-- Backfill accepted compromises whose normal two-player completion barrier was
-- already crossed before this migration.
do $$
declare
  v_round record;
  v_action jsonb;
  v_owner text;
  v_occurrence text;
begin
  for v_round in
    select session_id,final_resolution
    from public.network_rounds
    where phase in ('WAITING_NEXT','CLOSED')
      and (negotiation#>>'{response,accepted}')::boolean
  loop
    for v_action in
      select value from jsonb_array_elements(coalesce(
        v_round.final_resolution->'compromise','[]'::jsonb
      )) where value->>'origin'='AUCTION'
    loop
      v_owner:=v_action->>'owner_player_id';
      v_occurrence:=v_action->>'occurrence_id';
      if coalesce(v_owner,'')<>'' and coalesce(v_occurrence,'')<>'' then
        update public.network_game_states set
          v4_consumed_occurrences=jsonb_set(
            v4_consumed_occurrences,array[v_owner],
            case when coalesce(
              v4_consumed_occurrences->v_owner,'[]'::jsonb
            ) ? v_occurrence then coalesce(
              v4_consumed_occurrences->v_owner,'[]'::jsonb
            ) else coalesce(
              v4_consumed_occurrences->v_owner,'[]'::jsonb
            )||jsonb_build_array(v_occurrence) end,
            true
          )
        where session_id=v_round.session_id;
      end if;
    end loop;
  end loop;
end;
$$;

create or replace function public.network_round_json(
  p_round_id uuid,
  p_requester uuid
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'schema_version',1,'round_id',r.id,'session_id',r.session_id,
    'session_round',r.round_key,'round_number',r.round_number,'phase',r.phase,
    'player_id',p_requester,'action_points',g.action_points,
    'hybrid_orientation',g.hybrid_orientation,'deck_cycle',g.deck_cycle,
    'v4_unlocked_spice',g.v4_unlocked_spice,
    'v4_consumed_occurrence_ids',coalesce(
      g.v4_consumed_occurrences->p_requester::text,'[]'::jsonb
    ),
    'infinite_mode',g.infinite_mode,'deck_style',g.deck_style,
    'deck_adjustment',g.deck_adjustment,'cycle_exhausted',g.cycle_exhausted,
    'action_projection',r.v4_action_projection,
    'clothing_counts',coalesce((select jsonb_object_agg(
      p.user_id::text,p.v4_clothing_count) from public.session_players p
      where p.session_id=r.session_id and p.v4_clothing_count is not null),'{}'::jsonb),
    'clothing_resynced',r.v4_clothing_resynced,
    'commits',coalesce((select jsonb_object_agg(c.player_id::text,c.digest)
      from public.network_round_commits c where c.round_id=r.id),'{}'::jsonb),
    'own_reveal',(select jsonb_build_object('schema_version',1,
      'session_round',r.round_key,'player_id',v.player_id,'choice',v.choice_payload,'nonce',v.nonce)
      from public.network_round_reveals v where v.round_id=r.id and v.player_id=p_requester),
    'opponent_reveal',null,
    'initial_resolution',case when r.initial_resolution is null then null
      else r.initial_resolution-'gap'-'gap_cost'-'high_value' end,
    'negotiation',public.v4_public_negotiation(
      r.negotiation,
      p_requester::text=coalesce(
        r.negotiation->>'offered_by',
        r.initial_resolution->>'loser_player_id'
      )
    ),
    'counter_bid',r.counter_bid,'final_defense',r.final_defense,
    'final_resolution',case when r.final_resolution is null then null else
      jsonb_set(r.final_resolution,'{compromise}',
        public.v4_public_compromise_cards(r.final_resolution->'compromise'),true)
      end,
    'ready_next',r.ready_next,
    'tie_decisions',r.tie_decisions,'corruption',r.corruption,
    'recovery_by_player',r.recovery_by_player,'recovery_done',r.recovery_done,
    'recovery_history',r.recovery_history
  ) from public.network_rounds r join public.network_game_states g on g.session_id=r.session_id
  where r.id=p_round_id;
$$;

create or replace function public.v4_corruption_compromise(
  p_session_id uuid,
  p_round_number integer,
  p_player_id uuid,
  p_actions jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_proposed record;
  v_choice jsonb;
  v_resolved_action jsonb;
  v_parameters jsonb;
  v_effective_spice jsonb;
  v_native_direction text;
  v_effective_direction text;
  v_result jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions)=0 then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  for v_proposed in
    select value, ordinality
    from jsonb_array_elements(p_actions) with ordinality
  loop
    if exists(
      select 1 from public.network_game_states game
      where game.session_id=p_session_id
        and coalesce(
          game.v4_consumed_occurrences->p_player_id::text,'[]'::jsonb
        ) ? (v_proposed.value->>'occurrence_id')
    ) then
      raise exception 'ROUND_CORRUPTION_FORBIDDEN';
    end if;
    v_choice:=null;
    v_resolved_action:=null;
    -- A compromise/corruption argument must be a server-verifiable discard:
    -- it was exposed in a completed earlier round and has not subsequently
    -- been exhausted by an executed corruption or Recovery action.
    if not exists(
      select 1
      from public.network_rounds previous
      where previous.session_id=p_session_id
        and previous.round_number<p_round_number
        and (
          exists(
            select 1 from public.network_round_reveals reveal
            where reveal.round_id=previous.id
              and reveal.player_id=p_player_id
              and coalesce(
                reveal.choice_payload#>>'{parameters,occurrence_id}',
                reveal.choice_payload->>'card_id'
              )=v_proposed.value->>'occurrence_id'
              and reveal.choice_payload->>'card_id'=
                v_proposed.value->>'card_id'
          ) or exists(
            select 1
            from jsonb_array_elements(coalesce(
              previous.final_resolution->'compromise','[]'::jsonb
            )) action
            where action->>'owner_player_id'=p_player_id::text
              and action->>'occurrence_id'=
                v_proposed.value->>'occurrence_id'
              and action->>'card_id'=v_proposed.value->>'card_id'
          )
        )
    ) or exists(
      select 1
      from public.network_rounds previous
      where previous.session_id=p_session_id
        and previous.round_number<p_round_number
        and (
          exists(
            select 1 from jsonb_array_elements(coalesce(
              previous.corruption->'actions','[]'::jsonb
            )) action
            where previous.corruption->>'offered_by'=p_player_id::text
              and action->>'occurrence_id'=
                v_proposed.value->>'occurrence_id'
              and action->>'status'='COMPLETED'
          ) or exists(
            select 1 from jsonb_array_elements(coalesce(
              previous.recovery_history,'[]'::jsonb
            )) recovery
            where recovery->>'player_id'=p_player_id::text
              and recovery->>'occurrence_id'=
                v_proposed.value->>'occurrence_id'
              and (recovery->>'completed')::boolean
          )
        )
    ) then
      raise exception 'ROUND_CORRUPTION_FORBIDDEN';
    end if;
    select reveal.choice_payload into v_choice
    from public.network_round_reveals reveal
    join public.network_rounds previous on previous.id=reveal.round_id
    where previous.session_id=p_session_id
      and previous.round_number<p_round_number
      and reveal.player_id=p_player_id
      and coalesce(
        reveal.choice_payload#>>'{parameters,occurrence_id}',
        reveal.choice_payload->>'card_id'
      )=v_proposed.value->>'occurrence_id'
    order by previous.round_number desc
    limit 1;
    if not found then
      select action into v_resolved_action
      from public.network_rounds previous,
        jsonb_array_elements(coalesce(
          previous.final_resolution->'compromise','[]'::jsonb
        )) action
      where previous.session_id=p_session_id
        and previous.round_number<p_round_number
        and action->>'owner_player_id'=p_player_id::text
        and action->>'occurrence_id'=v_proposed.value->>'occurrence_id'
      order by previous.round_number desc
      limit 1;
      if not found
        or v_resolved_action->>'card_id' is distinct from
          v_proposed.value->>'card_id' then
        raise exception 'ROUND_CORRUPTION_FORBIDDEN';
      end if;
      v_choice:=jsonb_build_object(
        'card_id',v_resolved_action->>'card_id',
        'variant_id',v_resolved_action->>'variant_id',
        'parameters',jsonb_build_object(
          'resolved_parameters',v_resolved_action->'resolved_parameters',
          'effective_spice',v_resolved_action->'effective_spice',
          'native_direction',v_resolved_action->>'native_direction',
          'effective_direction',v_resolved_action->>'effective_direction'
        )
      );
    elsif v_choice->>'card_id' is distinct from
      v_proposed.value->>'card_id' then
      raise exception 'ROUND_CORRUPTION_FORBIDDEN';
    end if;
    v_parameters:=v_choice#>'{parameters,resolved_parameters}';
    v_effective_spice:=v_choice#>'{parameters,effective_spice}';
    if jsonb_typeof(v_parameters)<>'object'
      or jsonb_typeof(v_effective_spice)<>'number' then
      raise exception 'ROUND_ACTION_PARAMETERS_MISSING';
    end if;
    v_native_direction:=coalesce(
      v_choice#>>'{parameters,native_direction}',
      v_choice#>>'{parameters,role}',
      'GENERAL'
    );
    v_effective_direction:=coalesce(
      v_choice#>>'{parameters,effective_direction}',
      v_choice#>>'{parameters,role}',
      'GENERAL'
    );
    v_result:=v_result||jsonb_build_array(jsonb_build_object(
      'occurrence_id',v_proposed.value->>'occurrence_id',
      'card_id',v_choice->>'card_id',
      'variant_id',v_choice->>'variant_id',
      'owner_player_id',p_player_id,
      'native_direction',v_native_direction,
      'effective_direction',v_effective_direction,
      'origin','CORRUPTION',
      'snapshot_value',0,
      'logical_order',v_proposed.ordinality-1,
      'resolved_parameters',v_parameters,
      'effective_spice',v_effective_spice
    ));
  end loop;
  return v_result;
end;
$$;

revoke all on function public.v4_corruption_compromise(
  uuid,integer,uuid,jsonb
) from public, authenticated;

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
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(
    p_command_id,p_session_id,p_round_id,p_player_id,
    'NEGOTIATION_PROPOSAL',p_offer
  );
  update public.network_rounds set negotiation=jsonb_build_object(
    'offered_by',p_player_id,
    'proposal',p_offer,
    'response',null,
    'final_offer',null
  ),phase='NEGOTIATION_RESPONSE',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

create or replace function public.route_network_post_duel() returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_payer uuid;
  v_cost integer;
  v_current integer;
  v_actions jsonb;
  v_action jsonb;
  v_owner text;
  v_occurrence text;
begin
  -- Preserve the PA settlement installed by 202610100004. It only runs for
  -- the original direct acceptance, never for a later corruption response.
  if old.phase='COUNTER_DECISION' and new.phase='FINAL_RESOLVED'
    and old.counter_bid is null then
    v_payer:=coalesce(
      (new.final_resolution->>'final_winner_player_id')::uuid,
      (new.final_resolution->>'retained_player_id')::uuid
    );
    v_cost:=coalesce((old.initial_resolution->>'gap_cost')::integer,0);
    select (action_points->>v_payer::text)::integer into v_current
    from public.network_game_states
    where session_id=new.session_id for update;
    v_cost:=least(v_cost,v_current);
    update public.network_game_states set
      action_points=jsonb_set(
        action_points,array[v_payer::text],to_jsonb(v_current-v_cost)
      ),
      updated_at=now()
    where session_id=new.session_id;
  end if;

  if old.phase='READY' and new.phase='NEGOTIATION_PROPOSAL' then
    new.phase:='COUNTER_DECISION';
  elsif new.phase='FINAL_RESOLVED' and old.phase in (
    'COUNTER_DECISION','FINAL_DEFENSE_DECISION','TIE_DECISION'
  ) then
    new.phase:=case when new.final_resolution->>'retained_player_id' is null
      then 'RECOVERY' else 'CORRUPTION_DECISION' end;
elsif old.phase='FINAL_RESOLVED' and new.phase='WAITING_NEXT' then
    if (old.corruption->>'accepted')::boolean then
      select jsonb_agg(
        action||jsonb_build_object('status','COMPLETED') order by ordinality
      ) into v_actions
      from jsonb_array_elements(old.corruption->'actions')
        with ordinality as item(action,ordinality);
      new.corruption:=jsonb_set(old.corruption,'{actions}',v_actions,true);
    end if;
    if (old.negotiation#>>'{response,accepted}')::boolean then
      for v_action in
        select value from jsonb_array_elements(coalesce(
          old.final_resolution->'compromise','[]'::jsonb
        )) where value->>'origin'='AUCTION'
      loop
        v_owner:=v_action->>'owner_player_id';
        v_occurrence:=v_action->>'occurrence_id';
        if coalesce(v_owner,'')='' or coalesce(v_occurrence,'')='' then
          raise exception 'ROUND_NEGOTIATION_INVALID';
        end if;
        update public.network_game_states set
          v4_consumed_occurrences=jsonb_set(
            v4_consumed_occurrences,array[v_owner],
            case when coalesce(
              v4_consumed_occurrences->v_owner,'[]'::jsonb
            ) ? v_occurrence then coalesce(
              v4_consumed_occurrences->v_owner,'[]'::jsonb
            ) else coalesce(
              v4_consumed_occurrences->v_owner,'[]'::jsonb
            )||jsonb_build_array(v_occurrence) end,
            true
          ),updated_at=now()
        where session_id=new.session_id;
      end loop;
    end if;
  end if;
  return new;
end;
$$;
create or replace function public.continue_network_deck_cycle(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_choice text,
  p_adjustment jsonb,
  p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_payload jsonb;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if not exists(
    select 1 from public.session_players
    where session_id = p_session_id and user_id = p_player_id
      and role = 'PLAYER_1'
  ) then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  if p_choice not in (
    'CONTINUE_SPICIER','CONTINUE_INTENABLE','INFINITE','NEW_GAME','FINISH'
  ) or jsonb_typeof(p_adjustment) <> 'object' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_payload := jsonb_build_object(
    'choice', p_choice, 'adjustment', p_adjustment
  );
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text, 0));
  select * into v_round from public.network_rounds
  where id = p_round_id and session_id = p_session_id for update;
  if not found then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase <> 'WAITING_NEXT' then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  select * into v_command from public.network_round_commands
  where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id
      or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id
      or v_command.kind <> 'CONTINUE_CYCLE'
      or v_command.command_payload is distinct from v_payload then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id, p_player_id);
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values (
    p_command_id,p_session_id,p_round_id,p_player_id,
    'CONTINUE_CYCLE',v_payload
  );
  update public.network_game_states set
    deck_cycle = case
      when p_choice in ('CONTINUE_SPICIER','CONTINUE_INTENABLE','INFINITE')
        then deck_cycle + 1 else deck_cycle end,
    deck_style = case
      when p_choice = 'CONTINUE_INTENABLE' then 'INTENABLE'
      when p_choice = 'CONTINUE_SPICIER' and deck_style = 'SOFT' then 'EPICE'
      when p_choice = 'CONTINUE_SPICIER' then 'INTENABLE'
      else deck_style end,
    infinite_mode = case
      when p_choice = 'INFINITE' then true else infinite_mode end,
    deck_adjustment = p_adjustment,
    cycle_exhausted = false,
    v4_consumed_occurrences = case
      when p_choice in ('CONTINUE_SPICIER','CONTINUE_INTENABLE','INFINITE')
        then '{}'::jsonb
      else v4_consumed_occurrences end,
    updated_at = now()
  where session_id = p_session_id;
  if p_choice in ('NEW_GAME','FINISH') then
    update public.game_sessions set status = 'closed' where id = p_session_id;
  end if;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;
