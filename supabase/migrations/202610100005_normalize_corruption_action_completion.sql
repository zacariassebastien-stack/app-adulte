-- Route an accepted corruption through the shared V4 action-completion flow.
-- The duel cost was already settled before this point and is not touched here.

create or replace function public.respond_network_corruption(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_accepted boolean,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_payload jsonb;
  v_winner uuid;
  v_compromise jsonb;
  v_first jsonb;
  v_corruption jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  v_payload:=jsonb_build_object('accepted',p_accepted);
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'CORRUPTION_RESPONSE'
      or v_command.command_payload is distinct from v_payload then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'CORRUPTION_RESPONSE' then raise exception 'ROUND_INVALID_PHASE'; end if;
  v_winner:=coalesce(
    (v_round.final_resolution->>'final_winner_player_id')::uuid,
    (v_round.final_resolution->>'retained_player_id')::uuid
  );
  if p_player_id<>v_winner
    or v_round.corruption->>'offered_by'=p_player_id::text then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  v_corruption:=jsonb_set(v_round.corruption,'{accepted}',to_jsonb(p_accepted),true);
  if p_accepted then
    v_compromise:=public.v4_corruption_compromise(
      p_session_id,v_round.round_number,
      (v_round.corruption->>'offered_by')::uuid,
      v_round.corruption->'actions'
    );
    v_first:=v_compromise->0;
    v_corruption:=jsonb_set(
      v_corruption,'{accepted_compromise}',v_compromise,true
    );
    update public.network_rounds set
      corruption=v_corruption,
      final_resolution=jsonb_set(
        jsonb_set(
          jsonb_set(v_round.final_resolution,'{compromise}',v_compromise,true),
          '{card_id}',to_jsonb(v_first->>'card_id'),true
        ),
        '{variant_id}',to_jsonb(v_first->>'variant_id'),true
      ),
      v4_action_projection=null,
      phase='FINAL_RESOLVED',updated_at=now()
    where id=p_round_id;
  else
    update public.network_rounds set corruption=v_corruption,
      phase='FINAL_RESOLVED',updated_at=now() where id=p_round_id;
  end if;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'CORRUPTION_RESPONSE',v_payload);
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
  elsif old.phase='FINAL_RESOLVED' and new.phase='WAITING_NEXT'
    and (old.corruption->>'accepted')::boolean then
    select jsonb_agg(
      action||jsonb_build_object('status','COMPLETED') order by ordinality
    ) into v_actions
    from jsonb_array_elements(old.corruption->'actions')
      with ordinality as item(action,ordinality);
    new.corruption:=jsonb_set(old.corruption,'{actions}',v_actions,true);
  end if;
  return new;
end;
$$;

-- Repair an accepted corruption already waiting in the obsolete intermediate
-- phase. Its proposed actions remain unconsumed until both normal completion
-- confirmations move the round to WAITING_NEXT.
update public.network_rounds
set phase='FINAL_RESOLVED',v4_action_projection=null,updated_at=now()
where phase='CORRUPTION_EXECUTION'
  and (corruption->>'accepted')::boolean;

revoke all on function public.respond_network_corruption(
  uuid,uuid,uuid,boolean,text
) from public;
grant execute on function public.respond_network_corruption(
  uuid,uuid,uuid,boolean,text
) to authenticated;
