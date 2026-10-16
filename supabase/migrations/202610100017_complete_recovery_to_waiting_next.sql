-- A Recovery starts after the normal action has already crossed the two-player
-- completion barrier. Once both players leave Recovery, close that action
-- directly instead of exposing its FINAL_RESOLVED projection a second time.

create or replace function public.skip_network_recovery(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_done jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command
  from public.network_round_commands
  where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id
      or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id
      or v_command.kind<>'RECOVERY_SKIP' then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round
  from public.network_rounds
  where id=p_round_id
  for update;
  if not found or v_round.session_id<>p_session_id then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase<>'RECOVERY'
    or v_round.recovery_done ? p_player_id::text then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind
  ) values(
    p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY_SKIP'
  );
  v_done:=jsonb_set(
    v_round.recovery_done,array[p_player_id::text],'true'::jsonb
  );
  update public.network_rounds
  set recovery_done=v_done,
      phase=case
        when (select count(*) from jsonb_object_keys(v_done))=2
          then 'WAITING_NEXT'
        else 'RECOVERY'
      end,
      updated_at=now()
  where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

revoke all on function public.skip_network_recovery(
  uuid,uuid,uuid,text
) from public;
grant execute on function public.skip_network_recovery(
  uuid,uuid,uuid,text
) to authenticated;

-- Keep the existing canonical close behavior, and run it at the actual close
-- boundary when a low-PA Recovery delayed WAITING_NEXT.
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
  elsif old.phase in ('FINAL_RESOLVED','RECOVERY')
    and new.phase='WAITING_NEXT' then
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

revoke all on function public.route_network_post_duel() from public;

create or replace function public.apply_network_v4_persistent_effects()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if old.phase in ('FINAL_RESOLVED','RECOVERY')
    and new.phase='WAITING_NEXT' then
    update public.network_game_states
    set v4_persistent_effects=public.v4_advance_persistent_effects(
          v4_persistent_effects,
          coalesce(new.v4_action_projection->'cards','[]'::jsonb)
        ),
        updated_at=now()
    where session_id=new.session_id;
  end if;
  return new;
end;
$$;

revoke all on function public.apply_network_v4_persistent_effects()
  from public;
