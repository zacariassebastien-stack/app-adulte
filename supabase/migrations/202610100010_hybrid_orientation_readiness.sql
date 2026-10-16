-- A HYBRID orientation change is not ready for the next round until both
-- players have rebuilt their private hands and reported availability for the
-- same canonical orientation generation.

alter table public.network_rounds
  add column if not exists hybrid_availability_orientation text
    check (hybrid_availability_orientation in ('FACE_TO_FACE','DISTANCE')),
  add column if not exists hybrid_availability_generation integer not null
    default 0 check (hybrid_availability_generation >= 0),
  add column if not exists hybrid_availability jsonb not null default '{}'::jsonb
    check (jsonb_typeof(hybrid_availability) = 'object');

alter table public.network_round_commands
  drop constraint network_round_commands_kind_check;
alter table public.network_round_commands
  add constraint network_round_commands_kind_check check (kind in (
    'CREATE','OPEN','COMMIT','CANCEL_COMMIT','REVEAL','INITIAL_RESOLVE',
    'NEGOTIATION_PROPOSAL','NEGOTIATION_RESPONSE','NEGOTIATION_ADAPTATION',
    'NEGOTIATION_VALIDATION','SET_ORIENTATION','CONTINUE_CYCLE',
    'COUNTER_DECISION','FINAL_DEFENSE','TIE_DECISION','READY_NEXT',
    'CORRUPTION_OFFER','CORRUPTION_RESPONSE','CORRUPTION_RESOLVE',
    'CORRUPTION_SKIP','RECOVERY','RECOVERY_RESPONSE','RECOVERY_RESOLVE',
    'RECOVERY_SKIP','CLOSE_SESSION','REPAIR_V4_ACTION_PARAMETERS',
    'PUBLISH_V4_ACTION','PUBLISH_V4_SPICE','REPORT_HYBRID_AVAILABILITY'
  ));

create or replace function public.network_round_json(
  p_round_id uuid,
  p_requester uuid
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'schema_version',1,'round_id',r.id,'session_id',r.session_id,
    'session_round',r.round_key,'round_number',r.round_number,'phase',r.phase,
    'player_id',p_requester,'action_points',g.action_points,
    'hybrid_orientation',g.hybrid_orientation,'deck_cycle',g.deck_cycle,
    'hybrid_availability_orientation',r.hybrid_availability_orientation,
    'hybrid_availability_generation',r.hybrid_availability_generation,
    'hybrid_availability',r.hybrid_availability,
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

create or replace function public.set_network_hybrid_orientation(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_orientation text,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
    where session_id = p_session_id
      and user_id = p_player_id
      and role = 'PLAYER_1'
  ) then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  if p_orientation not in ('FACE_TO_FACE', 'DISTANCE') then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_payload := jsonb_build_object('orientation', p_orientation);
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text, 0));
  select * into v_round
  from public.network_rounds
  where id = p_round_id and session_id = p_session_id
  for update;
  if not found then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase <> 'WAITING_NEXT' then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  select * into v_command
  from public.network_round_commands
  where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id
      or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id
      or v_command.kind <> 'SET_ORIENTATION'
      or v_command.command_payload is distinct from v_payload then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id, p_player_id);
  end if;
  insert into public.network_round_commands(
    command_id, session_id, round_id, player_id, kind, command_payload
  ) values (
    p_command_id, p_session_id, p_round_id, p_player_id,
    'SET_ORIENTATION', v_payload
  );
  update public.network_game_states
  set hybrid_orientation = p_orientation,
      cycle_exhausted = false,
      updated_at = now()
  where session_id = p_session_id;
  update public.network_rounds
  set hybrid_availability_orientation = p_orientation,
      hybrid_availability_generation = hybrid_availability_generation + 1,
      hybrid_availability = '{}'::jsonb,
      updated_at = now()
  where id = p_round_id;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

revoke all on function public.set_network_hybrid_orientation(
  uuid, uuid, uuid, text, text
) from public;
grant execute on function public.set_network_hybrid_orientation(
  uuid, uuid, uuid, text, text
) to authenticated;

create function public.report_network_hybrid_availability(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_orientation text,
  p_generation integer,
  p_has_playable_current boolean,
  p_has_playable_alternate boolean,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_canonical_orientation text;
  v_payload jsonb;
  v_report jsonb;
  v_reports jsonb;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if p_orientation not in ('FACE_TO_FACE','DISTANCE')
    or p_generation < 1
    or p_has_playable_current is null
    or p_has_playable_alternate is null then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_payload := jsonb_build_object(
    'orientation',p_orientation,
    'generation',p_generation,
    'has_playable_current',p_has_playable_current,
    'has_playable_alternate',p_has_playable_alternate
  );
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands
  where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id
      or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id
      or v_command.kind<>'REPORT_HYBRID_AVAILABILITY'
      or v_command.command_payload is distinct from v_payload then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds
  where id=p_round_id and session_id=p_session_id for update;
  if not found then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'WAITING_NEXT' then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  select hybrid_orientation into v_canonical_orientation
  from public.network_game_states where session_id=p_session_id;
  if v_round.hybrid_availability_orientation is distinct from p_orientation
    or v_canonical_orientation is distinct from p_orientation
    or v_round.hybrid_availability_generation<>p_generation then
    raise exception 'ROUND_HYBRID_ORIENTATION_STALE';
  end if;
  v_report:=jsonb_build_object(
    'orientation',p_orientation,
    'generation',p_generation,
    'has_playable_current',p_has_playable_current,
    'has_playable_alternate',p_has_playable_alternate
  );
  if v_round.hybrid_availability ? p_player_id::text
    and v_round.hybrid_availability->p_player_id::text is distinct from v_report then
    raise exception 'ROUND_HYBRID_AVAILABILITY_CONFLICT';
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(
    p_command_id,p_session_id,p_round_id,p_player_id,
    'REPORT_HYBRID_AVAILABILITY',v_payload
  );
  v_reports:=jsonb_set(
    v_round.hybrid_availability,array[p_player_id::text],v_report,true
  );
  update public.network_rounds
  set hybrid_availability=v_reports,updated_at=now()
  where id=p_round_id;
  update public.network_game_states
  set cycle_exhausted=exists(
        select 1 from jsonb_each(v_reports) report
        where coalesce((report.value->>'has_playable_current')::boolean,false)=false
          and coalesce((report.value->>'has_playable_alternate')::boolean,false)=false
      ),
      updated_at=now()
  where session_id=p_session_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

revoke all on function public.report_network_hybrid_availability(
  uuid,uuid,uuid,text,integer,boolean,boolean,text
) from public;
grant execute on function public.report_network_hybrid_availability(
  uuid,uuid,uuid,text,integer,boolean,boolean,text
) to authenticated;

drop function if exists public.ready_network_next_round(
  uuid,uuid,uuid,text,boolean,integer
);
create function public.ready_network_next_round(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_command_id text,
  p_no_playable_occurrences boolean default false,
  p_clothing_count integer default null,
  p_has_playable_alternate boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_ready jsonb;
  v_next_id uuid;
  v_next_number integer;
  v_payload jsonb;
  v_orientation text;
  v_report jsonb;
  v_reports jsonb;
  v_is_hybrid boolean;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text, 0));
  v_payload := jsonb_build_object(
    'no_playable_occurrences', p_no_playable_occurrences,
    'clothing_count', p_clothing_count,
    'has_playable_alternate', p_has_playable_alternate
  );
  select * into v_command
  from public.network_round_commands
  where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id
      or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id
      or v_command.kind <> 'READY_NEXT'
      or (
        v_command.command_payload is distinct from v_payload
        and v_command.command_payload is distinct from
          (v_payload-'has_playable_alternate')
      ) then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.get_current_network_game_round(p_session_id, p_player_id);
  end if;

  select * into v_round
  from public.network_rounds
  where id = p_round_id
  for update;
  if not found or v_round.session_id <> p_session_id then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase = 'CLOSED' and exists(
    select 1
    from public.network_game_states state
    where state.session_id = p_session_id
      and state.current_round_number > v_round.round_number
  ) then
    insert into public.network_round_commands(
      command_id, session_id, round_id, player_id, kind, command_payload
    ) values (
      p_command_id, p_session_id, p_round_id, p_player_id, 'READY_NEXT', v_payload
    );
    return public.get_current_network_game_round(p_session_id, p_player_id);
  end if;
  if v_round.phase not in ('FINAL_RESOLVED', 'WAITING_NEXT') then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  if p_clothing_count is not null and p_clothing_count < 0 then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  select s.v4_session_mode='hybrid',g.hybrid_orientation
  into v_is_hybrid,v_orientation
  from public.game_sessions s
  join public.network_game_states g on g.session_id=s.id
  where s.id=p_session_id;
  if v_round.phase='WAITING_NEXT' then
    if exists(
      select 1 from public.network_game_states
      where session_id=p_session_id and cycle_exhausted
    ) then
      raise exception 'ROUND_CYCLE_EXHAUSTED';
    end if;
    if v_is_hybrid and v_round.hybrid_availability_orientation is not null then
      if v_round.hybrid_availability_orientation is distinct from v_orientation
        or exists(
          select 1 from public.session_players participant
          where participant.session_id=p_session_id
            and not (v_round.hybrid_availability ? participant.user_id::text)
        )
        or exists(
          select 1 from jsonb_each(v_round.hybrid_availability) report
          where report.value->>'orientation' is distinct from v_orientation
            or coalesce((report.value->>'generation')::integer,-1)
              <>v_round.hybrid_availability_generation
        ) then
        raise exception 'ROUND_HYBRID_AVAILABILITY_PENDING';
      end if;
      if exists(
        select 1 from jsonb_each(v_round.hybrid_availability) report
        where coalesce((report.value->>'has_playable_current')::boolean,false)=false
      ) then
        raise exception 'ROUND_HYBRID_SWITCH_REQUIRED';
      end if;
    end if;
  end if;

  insert into public.network_round_commands(
    command_id, session_id, round_id, player_id, kind, command_payload
  ) values (
    p_command_id, p_session_id, p_round_id, p_player_id, 'READY_NEXT', v_payload
  );
  v_ready := jsonb_set(
    v_round.ready_next,
    array[p_player_id::text],
    'true'::jsonb
  );
  if v_round.phase = 'FINAL_RESOLVED' then
    if coalesce(v_round.v4_action_projection->'required_clothing_player_ids','[]'::jsonb)
        ? p_player_id::text then
      if p_clothing_count is null or p_clothing_count < 0 then
        raise exception 'ROUND_CLOTHING_RESYNC_REQUIRED';
      end if;
      update public.session_players set v4_clothing_count=p_clothing_count
      where session_id=p_session_id and user_id=p_player_id;
      update public.network_rounds set v4_clothing_resynced=jsonb_set(
        v4_clothing_resynced,array[p_player_id::text],'true'::jsonb
      ) where id=p_round_id returning v4_clothing_resynced into v_ready;
    end if;
    if v_is_hybrid then
      v_report:=jsonb_build_object(
        'orientation',v_orientation,
        'generation',v_round.hybrid_availability_generation,
        'has_playable_current',not p_no_playable_occurrences,
        'has_playable_alternate',p_has_playable_alternate
      );
      v_reports:=jsonb_set(
        v_round.hybrid_availability,array[p_player_id::text],v_report,true
      );
      update public.network_rounds
      set hybrid_availability_orientation=v_orientation,
          hybrid_availability=v_reports,
          updated_at=now()
      where id=p_round_id;
      if p_no_playable_occurrences and not p_has_playable_alternate then
        update public.network_game_states
        set cycle_exhausted=true,updated_at=now()
        where session_id=p_session_id;
      end if;
    elsif p_no_playable_occurrences then
      update public.network_game_states
      set cycle_exhausted = true, updated_at = now()
      where session_id = p_session_id;
    end if;
    select ready_next into v_ready from public.network_rounds where id=p_round_id;
    v_ready := jsonb_set(v_ready,array[p_player_id::text],'true'::jsonb);
    update public.network_rounds
    set ready_next = v_ready,
        phase = case
          when not exists(
            select 1 from jsonb_array_elements_text(coalesce(
              v4_action_projection->'required_clothing_player_ids','[]'::jsonb
            )) required(id)
            where not (v4_clothing_resynced ? required.id)
          ) and not exists(
            select 1 from public.session_players participant
            where participant.session_id = p_session_id
              and not (v_ready ? participant.user_id::text)
          ) then 'WAITING_NEXT'
          else 'FINAL_RESOLVED'
        end,
        updated_at = now()
    where id = p_round_id;
    return public.network_round_json(p_round_id, p_player_id);
  end if;

  update public.network_rounds
  set phase = 'CLOSED', closed_at = now(), updated_at = now()
  where id = p_round_id;
  v_next_number := v_round.round_number + 1;
  update public.network_game_states
  set current_round_number = v_next_number, updated_at = now()
  where session_id = p_session_id
    and current_round_number = v_round.round_number;
  insert into public.network_rounds(session_id, round_number, round_key)
  values (
    p_session_id,
    v_next_number,
    p_session_id::text || '.round-' || v_next_number
  )
  on conflict (session_id, round_number) do nothing;
  select id into v_next_id
  from public.network_rounds
  where session_id = p_session_id and round_number = v_next_number;
  return public.network_round_json(v_next_id, p_player_id);
end;
$$;

revoke all on function public.ready_network_next_round(
  uuid,uuid,uuid,text,boolean,integer,boolean
) from public;
grant execute on function public.ready_network_next_round(
  uuid,uuid,uuid,text,boolean,integer,boolean
) to authenticated;

-- Existing HYBRID rounds already waiting when this migration lands must also
-- pass through the new barrier before they can advance.
update public.network_rounds round
set hybrid_availability_orientation=game.hybrid_orientation,
    hybrid_availability_generation=greatest(
      round.hybrid_availability_generation,1
    ),
    hybrid_availability='{}'::jsonb,
    updated_at=now()
from public.network_game_states game
join public.game_sessions session on session.id=game.session_id
where round.session_id=game.session_id
  and round.phase='WAITING_NEXT'
  and session.v4_session_mode='hybrid';
