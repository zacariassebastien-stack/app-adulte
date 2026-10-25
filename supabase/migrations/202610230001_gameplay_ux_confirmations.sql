-- UX confirmations use frozen action roles. No PA, gain, consent or duration rules change.
begin;

create or replace function public.v4_clothing_player_ids(p_action jsonb)
returns jsonb language sql immutable set search_path=public as $$
  select case p_action#>>'{parameters,clothing_behavior}'
    when 'resetThenUnderwear' then p_action->'actor_player_ids'
    when 'resetThenNude' then p_action->'actor_player_ids'
    when 'resetThenStrip' then p_action->'actor_player_ids'
    when 'resetThenStripComplete' then p_action->'actor_player_ids'
    when 'removeOne' then p_action->'target_player_ids'
    when 'removeTwo' then p_action->'target_player_ids'
    when 'chooseOutfit' then p_action->'target_player_ids'
    when 'changeOutfit' then p_action->'target_player_ids'
    else '[]'::jsonb end;
$$;

create or replace function public.normalize_v4_clothing_projection()
returns trigger language plpgsql set search_path=public as $$
declare v_required jsonb;
begin
  if new.v4_action_projection is not null then
    select coalesce(jsonb_agg(id order by id),'[]'::jsonb) into v_required
    from (select distinct id from jsonb_array_elements(new.v4_action_projection->'cards') card,
      jsonb_array_elements_text(public.v4_clothing_player_ids(card->'resolved_action')) id) people;
    new.v4_action_projection:=jsonb_set(new.v4_action_projection,'{required_clothing_player_ids}',v_required);
  end if;
  return new;
end;
$$;
create trigger ux_clothing_projection before insert or update of v4_action_projection
on public.network_rounds for each row execute function public.normalize_v4_clothing_projection();

-- Repair the gate of in-flight actions without changing anyone's clothing count.
update public.network_rounds set v4_action_projection=v4_action_projection
where phase='FINAL_RESOLVED' and v4_action_projection is not null;

create or replace function public.network_round_json(
  p_round_id uuid,
  p_requester uuid
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'schema_version',1,'usage_contract_version',1,'round_id',r.id,'session_id',r.session_id,
    'session_round',r.round_key,'round_number',r.round_number,'phase',r.phase,
    'player_id',p_requester,'action_points',g.action_points,
    'hybrid_orientation',g.hybrid_orientation,'deck_cycle',g.deck_cycle,
    'hybrid_availability_orientation',r.hybrid_availability_orientation,
    'hybrid_availability_generation',r.hybrid_availability_generation,
    'hybrid_availability',r.hybrid_availability,
    'v4_unlocked_spice',g.v4_unlocked_spice,
    'v4_consumed_usage_ids',coalesce(
      g.v4_consumed_occurrences->p_requester::text,'[]'::jsonb
    ),
    'v4_persistent_effects',g.v4_persistent_effects,
    'infinite_mode',g.infinite_mode,'deck_style',g.deck_style,
    'cycle_style_proposal',g.cycle_style_proposal,'cycle_style_proposer',g.cycle_style_proposer,
    'cycle_style_revision',g.cycle_style_revision,'cycle_style_votes',g.cycle_style_votes,
    'deck_adjustment',g.deck_adjustment,'cycle_exhausted',g.cycle_exhausted,
    'action_projection',r.v4_action_projection,
    'clothing_counts',coalesce((select jsonb_object_agg(
      p.user_id::text,p.v4_clothing_count) from public.session_players p
      where p.session_id=r.session_id and p.v4_clothing_count is not null),'{}'::jsonb),
    'clothing_resynced',r.v4_clothing_resynced,
    'recovery_clothing_confirmations',coalesce((select jsonb_object_agg(usage_id,players)
      from (select command_payload->>'usage_id' usage_id,jsonb_agg(player_id::text order by player_id) players
        from public.network_round_commands where round_id=r.id and kind='RECOVERY_CLOTHING_CONFIRM'
        group by command_payload->>'usage_id') confirmations),'{}'::jsonb),
    'commits',coalesce((select jsonb_object_agg(c.player_id::text,c.digest)
      from public.network_round_commits c where c.round_id=r.id),'{}'::jsonb),
    'own_reveal',(select jsonb_build_object('schema_version',1,
      'session_round',r.round_key,'player_id',v.player_id,'choice',v.choice_payload,'nonce',v.nonce)
      from public.network_round_reveals v where v.round_id=r.id and v.player_id=p_requester),
    'opponent_reveal',null,
    -- Only resolved duel actions are public; never expose values or nonces.
    'initial_duel_cards',case when r.initial_resolution is null then '[]'::jsonb
      else coalesce((select jsonb_agg(
        v.choice_payload-'snapshot_value'-'inverted_resolution' order by v.player_id)
        from public.network_round_reveals v where v.round_id=r.id
          and v.choice_payload->'usage_schema_version'='1'::jsonb
          and (r.phase<>'TIE_DECISION' or v.player_id=p_requester)),'[]'::jsonb) end,
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

create or replace function public.confirm_network_recovery_clothing(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,p_command_id text,
  p_usage_id text,p_clothing_count integer
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_round public.network_rounds%rowtype; v_command public.network_round_commands%rowtype;
  v_recovery jsonb; v_payload jsonb;
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_clothing_count is null or p_clothing_count<0 then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  v_payload:=jsonb_build_object('usage_id',p_usage_id,'clothing_count',p_clothing_count);
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text,0));
  select * into v_command from public.network_round_commands where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id or v_command.player_id<>p_player_id
      or v_command.kind<>'RECOVERY_CLOTHING_CONFIRM' or v_command.command_payload is distinct from v_payload
      then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'RECOVERY_EXECUTION' then raise exception 'ROUND_INVALID_PHASE'; end if;
  select value into v_recovery from jsonb_each(v_round.recovery_by_player)
    where value->>'usage_id'=p_usage_id and value->>'response'='ACCEPT';
  if v_recovery is null or not (public.v4_clothing_player_ids(v_recovery->'resolved_action') ? p_player_id::text)
    then raise exception 'ROUND_CLOTHING_ACTOR_REQUIRED'; end if;
  if exists(select 1 from public.network_round_commands where round_id=p_round_id and player_id=p_player_id
    and kind='RECOVERY_CLOTHING_CONFIRM' and command_payload->>'usage_id'=p_usage_id)
    then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
  insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
    values(p_command_id,p_session_id,p_round_id,p_player_id,'RECOVERY_CLOTHING_CONFIRM',v_payload);
  update public.session_players set v4_clothing_count=p_clothing_count
    where session_id=p_session_id and user_id=p_player_id;
  update public.network_rounds set updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;
revoke all on function public.confirm_network_recovery_clothing(uuid,uuid,uuid,text,text,integer) from public;
grant execute on function public.confirm_network_recovery_clothing(uuid,uuid,uuid,text,text,integer) to authenticated;

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
  perform public.network_usage_projection(p_recovery-array['player_id','source','completed','gain','response'],false);
  if p_recovery->>'owner_player_id' is distinct from p_player_id::text then raise exception 'ROUND_USAGE_INVALID'; end if;
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
    or v_existing->>'usage_id' is distinct from p_recovery->>'usage_id'
    or (v_existing-array['gain','completed','response']) is distinct from
       (p_recovery-array['gain','completed','response'])
    then raise exception 'ROUND_RECOVERY_NOT_ELIGIBLE'; end if;
  if coalesce((p_recovery->>'completed')::boolean,false) and exists(
    select 1 from jsonb_array_elements_text(public.v4_clothing_player_ids(v_existing->'resolved_action')) required(id)
    where not exists(select 1 from public.network_round_commands confirmation
      where confirmation.round_id=p_round_id and confirmation.player_id::text=required.id
        and confirmation.kind='RECOVERY_CLOTHING_CONFIRM'
        and confirmation.command_payload->>'usage_id'=p_recovery->>'usage_id'))
    then raise exception 'ROUND_CLOTHING_RESYNC_REQUIRED'; end if;
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


commit;
