-- Explicit preparation, participant approval and consensual cycle styles.
-- Existing sessions retain their accepted preparation; new preparation states
-- are created explicitly by the host before the first round is opened.
alter table public.network_game_states
  add column setup_status text not null default 'ACCEPTED'
    check (setup_status in ('DRAFT','PROPOSED','REFUSED','ACCEPTED')),
  add column setup_revision integer not null default 0,
  add column cycle_style_proposal text,
  add column cycle_style_proposer uuid,
  add column cycle_style_revision integer not null default 0,
  add column cycle_style_votes jsonb not null default '{}'::jsonb;
alter table public.session_players add column v4_available_accessories jsonb;
create table public.network_setup_commands (
  command_id text primary key,
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null
);
alter table public.network_setup_commands enable row level security;
revoke all on public.network_setup_commands from anon,authenticated;

create or replace function public.v4_session_setup_json(p_session_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('mode',s.v4_session_mode,'style',g.deck_style,
    'status',coalesce(g.setup_status,'DRAFT'),'revision',coalesce(g.setup_revision,0),
    'players',coalesce((select jsonb_agg(jsonb_build_object(
      'player_id',p.user_id,'clothing_count',coalesce(p.v4_clothing_count,0),
      'environment_ready',p.v4_clothing_count is not null,
      'inventory_ready',p.v4_available_accessories is not null,
      'available_accessories',coalesce(p.v4_available_accessories,'[]'::jsonb),
      'accessories',coalesce(p.v4_accessories,'[]'::jsonb)) order by p.role)
      from public.session_players p where p.session_id=s.id),'[]'::jsonb))
  from public.game_sessions s left join public.network_game_states g on g.session_id=s.id
  where s.id=p_session_id;
$$;

-- Only the accessory inventory is shared here, never private preferences/PA.
create function public.register_v4_setup_accessories(p_session_id uuid,p_accessories jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if jsonb_typeof(p_accessories) is distinct from 'array' then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  -- A submitted proposal freezes its accessory inventory until the setup ends.
  update public.session_players set v4_available_accessories=p_accessories
    where session_id=p_session_id and user_id=auth.uid() and v4_available_accessories is null;
  return public.v4_session_setup_json(p_session_id);
end; $$;

create function public.v4_store_setup_environment(p_session_id uuid,p_player uuid,p_environment jsonb)
returns void language plpgsql set search_path=public as $$
declare v_accessories jsonb;
begin
  if not exists(select 1 from public.session_players where session_id=p_session_id and user_id=p_player)
    or jsonb_typeof(p_environment->'accessories') is distinct from 'array'
    or coalesce(p_environment->>'clothing_count','') !~ '^[0-9]+$' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  select coalesce(jsonb_agg(item||jsonb_build_object('owner_player_id',p_player)),'[]'::jsonb)
    into v_accessories from jsonb_array_elements(p_environment->'accessories') item;
  update public.session_players set v4_clothing_count=(p_environment->>'clothing_count')::integer,
    v4_accessories=v_accessories where session_id=p_session_id and user_id=p_player;
end; $$;

-- Old clients must not bypass explicit style selection or participant approval.
create or replace function public.submit_v4_session_setup(
  p_session_id uuid,p_clothing_count integer,p_accessories jsonb,p_mode text default null
) returns jsonb language plpgsql as $$ begin raise exception 'SESSION_SETUP_UPGRADE_REQUIRED'; end; $$;

create function public.propose_v4_session_setup(
  p_session_id uuid,p_mode text,p_style text,p_players jsonb,
  p_expected_revision integer,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare g public.network_game_states%rowtype; v_player record; v_payload jsonb; v_prior public.network_setup_commands%rowtype;
begin
  if auth.uid() is null or not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if not exists(select 1 from public.session_players where session_id=p_session_id and user_id=auth.uid() and role='PLAYER_1')
    then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text,0));
  v_payload:=jsonb_build_object('mode',p_mode,'style',p_style,'players',p_players,'revision',p_expected_revision);
  select * into v_prior from public.network_setup_commands where command_id=p_command_id;
  if found then
    if v_prior.session_id<>p_session_id or v_prior.player_id<>auth.uid() or v_prior.payload<>v_payload then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.v4_session_setup_json(p_session_id);
  end if;
  if p_mode not in ('presentiel','distance','hybrid') or p_style not in ('SOFT','EPICE','INTENABLE')
    or p_mode is null or p_style is null or jsonb_typeof(p_players) is distinct from 'object'
    or (select count(*) from public.session_players where session_id=p_session_id)<>2 then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  insert into public.network_game_states(session_id,action_points,setup_status)
    select p_session_id,jsonb_object_agg(user_id::text,100),'DRAFT'
      from public.session_players where session_id=p_session_id on conflict do nothing;
  select * into g from public.network_game_states where session_id=p_session_id for update;
  if g.setup_status='ACCEPTED' or exists(select 1 from public.network_rounds where session_id=p_session_id)
    then raise exception 'ROUND_SESSION_SETUP_IMMUTABLE'; end if;
  if g.setup_revision<>p_expected_revision then raise exception 'ROUND_SETUP_STALE'; end if;
  for v_player in select * from public.session_players where session_id=p_session_id loop
    if v_player.v4_available_accessories is null then raise exception 'ROUND_SETUP_NOT_READY'; end if;
    if p_mode<>'distance' or v_player.user_id=auth.uid() then
      perform public.v4_store_setup_environment(p_session_id,v_player.user_id,p_players->v_player.user_id::text);
    elsif p_players ? v_player.user_id::text then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  end loop;
  update public.game_sessions set v4_session_mode=p_mode,updated_at=now() where id=p_session_id;
  update public.network_game_states set deck_style=p_style,setup_status='PROPOSED',setup_revision=setup_revision+1 where session_id=p_session_id;
  insert into public.network_setup_commands values(p_command_id,p_session_id,auth.uid(),v_payload);
  -- The existing setup stream listens to session_players.
  update public.session_players set v4_accessories=v4_accessories where session_id=p_session_id;
  return public.v4_session_setup_json(p_session_id);
end; $$;

create function public.respond_v4_session_setup(
  p_session_id uuid,p_revision integer,p_accepted boolean,p_environment jsonb,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare g public.network_game_states%rowtype; v_mode text; v_payload jsonb; v_prior public.network_setup_commands%rowtype;
begin
  if auth.uid() is null or not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if not exists(select 1 from public.session_players where session_id=p_session_id and user_id=auth.uid() and role='PLAYER_2') then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text,0));
  v_payload:=jsonb_build_object('revision',p_revision,'accepted',p_accepted,'environment',p_environment);
  select * into v_prior from public.network_setup_commands where command_id=p_command_id;
  if found then
    if v_prior.session_id<>p_session_id or v_prior.player_id<>auth.uid() or v_prior.payload<>v_payload then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.v4_session_setup_json(p_session_id);
  end if;
  select * into g from public.network_game_states where session_id=p_session_id for update;
  if not found or g.setup_status<>'PROPOSED' or g.setup_revision<>p_revision or p_accepted is null then raise exception 'ROUND_SETUP_STALE'; end if;
  select v4_session_mode into v_mode from public.game_sessions where id=p_session_id;
  if v_mode='distance' then
    if p_environment is not null then perform public.v4_store_setup_environment(p_session_id,auth.uid(),p_environment); end if;
    if p_accepted and (select v4_clothing_count is null from public.session_players where session_id=p_session_id and user_id=auth.uid()) then raise exception 'ROUND_SETUP_NOT_READY'; end if;
  elsif p_environment is not null then raise exception 'ROUND_NOT_ACTIVE_PLAYER'; end if;
  update public.network_game_states set setup_status=case when p_accepted then 'ACCEPTED' else 'REFUSED' end where session_id=p_session_id;
  insert into public.network_setup_commands values(p_command_id,p_session_id,auth.uid(),v_payload);
  update public.session_players set v4_accessories=v4_accessories where session_id=p_session_id;
  return public.v4_session_setup_json(p_session_id);
end; $$;

alter function public.open_network_game_round(uuid,uuid,text) rename to open_prepared_network_game_round;
revoke all on function public.open_prepared_network_game_round(uuid,uuid,text) from public,anon,authenticated;
create function public.open_network_game_round(p_session_id uuid,p_player_id uuid,p_command_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or auth.uid()<>p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text,0));
  if not exists(select 1 from public.network_game_states where session_id=p_session_id and setup_status='ACCEPTED') then raise exception 'ROUND_SETUP_NOT_READY'; end if;
  return public.open_prepared_network_game_round(p_session_id,p_player_id,p_command_id);
end; $$;

revoke all on function public.register_v4_setup_accessories(uuid,jsonb) from public;
revoke all on function public.v4_store_setup_environment(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.propose_v4_session_setup(uuid,text,text,jsonb,integer,text) from public;
revoke all on function public.respond_v4_session_setup(uuid,integer,boolean,jsonb,text) from public;
revoke all on function public.open_network_game_round(uuid,uuid,text) from public;
grant execute on function public.register_v4_setup_accessories(uuid,jsonb),
  public.propose_v4_session_setup(uuid,text,text,jsonb,integer,text),
  public.respond_v4_session_setup(uuid,integer,boolean,jsonb,text),
  public.open_network_game_round(uuid,uuid,text) to authenticated;

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
  v_cycle integer;
  v_expected integer;
  g public.network_game_states%rowtype;
  v_target text;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if p_choice in ('NEW_GAME','FINISH') then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  if p_choice not in (
    'CONTINUE_SPICIER','CONTINUE_INTENABLE','CONTINUE_SAME','REFUSE_STYLE','INFINITE'
  ) or jsonb_typeof(p_adjustment) is distinct from 'object'
    or coalesce(p_adjustment->>'expected_cycle','') !~ '^[1-9][0-9]{0,8}$' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  v_expected:=(p_adjustment->>'expected_cycle')::integer;
  v_payload := jsonb_build_object(
    'choice', p_choice, 'adjustment', p_adjustment
  );
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text, 0));

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
    return public.get_current_network_game_round(p_session_id, p_player_id);
  end if;

  select deck_cycle into v_cycle from public.network_game_states where session_id=p_session_id for update;
  if not found or v_expected>v_cycle then raise exception 'ROUND_CYCLE_MISMATCH'; end if;
  if v_expected<v_cycle then
    insert into public.network_round_commands(command_id,session_id,round_id,player_id,kind,command_payload)
      values(p_command_id,p_session_id,p_round_id,p_player_id,'CONTINUE_CYCLE',v_payload);
    return public.get_current_network_game_round(p_session_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds
  where id = p_round_id and session_id = p_session_id for update;
  if not found then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase <> 'WAITING_NEXT' then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  if not exists(
    select 1 from public.network_game_states
    where session_id = p_session_id and cycle_exhausted is true
  ) then
    raise exception 'ROUND_CYCLE_NOT_EXHAUSTED';
  end if;

  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values (
    p_command_id,p_session_id,p_round_id,p_player_id,
    'CONTINUE_CYCLE',v_payload
  );
  select * into g from public.network_game_states where session_id=p_session_id for update;
  if coalesce((p_adjustment->>'style_revision')::integer,0)<>g.cycle_style_revision then
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  if p_choice='REFUSE_STYLE' then
    if g.cycle_style_proposal is null or g.cycle_style_proposer=p_player_id then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
    update public.network_game_states set cycle_style_proposal=null,
      cycle_style_votes=jsonb_build_object(p_player_id::text,false),cycle_style_revision=cycle_style_revision+1
      where session_id=p_session_id;
  else
    v_target:=case when p_choice='CONTINUE_SPICIER' and g.deck_style='SOFT' then 'EPICE'
      when p_choice in ('CONTINUE_SPICIER','CONTINUE_INTENABLE') and g.deck_style='EPICE' then 'INTENABLE'
      else g.deck_style end;
    if p_choice='CONTINUE_INTENABLE' and g.deck_style='SOFT' then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
    if v_target<>g.deck_style and g.cycle_style_proposal is null then
      update public.network_game_states set cycle_style_proposal=v_target,cycle_style_proposer=p_player_id,
        cycle_style_votes=jsonb_build_object(p_player_id::text,true),cycle_style_revision=cycle_style_revision+1
        where session_id=p_session_id;
    else
      if v_target<>g.deck_style and (g.cycle_style_proposal<>v_target or g.cycle_style_proposer=p_player_id) then raise exception 'ROUND_STYLE_NOT_AGREED'; end if;
      update public.network_game_states set deck_cycle=deck_cycle+1,deck_style=v_target,
        infinite_mode=case when p_choice='INFINITE' then true else infinite_mode end,
        deck_adjustment='{}'::jsonb,cycle_exhausted=false,v4_consumed_occurrences='{}'::jsonb,
        cycle_style_proposal=null,cycle_style_proposer=null,cycle_style_votes='{}'::jsonb,
        cycle_style_revision=cycle_style_revision+1,updated_at=now() where session_id=p_session_id;
    end if;
  end if;
  -- Publish even a proposal/refusal (no new round/cycle yet).
  update public.network_rounds set updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

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
  if old.phase='READY' and new.phase in ('NEGOTIATION_PROPOSAL','COUNTER_DECISION') then
    v_payer:=(new.initial_resolution->>'winner_player_id')::uuid;
    new.final_resolution:=public.network_final_choice(new.id,v_payer,v_payer,false)
      ||jsonb_build_object('initial_winner_player_id',v_payer,'final_winner_player_id',v_payer,
        'final_loser_player_id',new.initial_resolution->>'loser_player_id');
    v_cost:=coalesce((new.initial_resolution->>'gap_cost')::integer,0);
    select (action_points->>v_payer::text)::integer into v_current
      from public.network_game_states where session_id=new.session_id for update;
    update public.network_game_states set action_points=jsonb_set(action_points,array[v_payer::text],
      to_jsonb(v_current-least(v_cost,v_current))),updated_at=now() where session_id=new.session_id;
    new.phase:='CORRUPTION_DECISION';
  elsif new.phase='FINAL_RESOLVED' and old.phase='TIE_DECISION' then
    new.phase:=case when new.final_resolution->>'retained_player_id' is null then 'RECOVERY' else 'CORRUPTION_DECISION' end;
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
        v_occurrence:=v_action->>'usage_id';
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
  if coalesce(v_choice#>>'{native_direction}',v_choice#>>'{resolved_action,direction}','GENERAL')
      <> coalesce(v_choice#>>'{resolved_action,direction}','GENERAL')
    or coalesce(v_choice#>>'{effective_direction}',v_choice#>>'{resolved_action,direction}','GENERAL')
      <> coalesce(v_choice#>>'{resolved_action,direction}','GENERAL') then
    raise exception 'ROUND_DIRECTION_MISMATCH';
  end if;
  if v_inverted and (
      coalesce(v_choice#>>'{resolved_action,direction}','GENERAL') not in ('FAIRE','RECEVOIR')
      or coalesce(v_choice#>>'{inverted_resolution,snapshot_value}','') !~ '^[0-9]+$'
      or (v_choice#>>'{inverted_resolution,snapshot_value}')::integer not between 1 and 20
    ) then raise exception 'ROUND_INVERSION_UNAVAILABLE'; end if;
  v_initial_card:=public.network_usage_resolution(v_choice,v_inverted)
    ||jsonb_build_object('origin','INITIAL_DUEL','logical_order',0);
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
      'retained_player_id',v_final,'initial_winner_player_id',v_winner,'final_winner_player_id',v_winner,'final_loser_player_id',v_loser,
      'concept_id',v_initial_card->>'concept_id','usage_id',v_initial_card->>'usage_id',
      'inverted',v_inverted,'mutual_abandon',false,'compromise',v_cards),
    phase='FINAL_RESOLVED',updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end; $$;

create or replace function public.submit_network_counter_decision(p_session_id uuid,p_round_id uuid,p_player_id uuid,p_decision text,p_amount integer,p_target text,p_command_id text) returns jsonb language plpgsql as $$ begin raise exception 'ROUND_MECHANIC_REMOVED'; end; $$;

create or replace function public.submit_network_final_defense(p_session_id uuid,p_round_id uuid,p_player_id uuid,p_decision text,p_amount integer,p_command_id text) returns jsonb language plpgsql as $$ begin raise exception 'ROUND_MECHANIC_REMOVED'; end; $$;

-- Resume conceptual rounds paused at the retired counter/defense steps.
-- Previously debited counter PA remain part of canonical historical spending.
do $$
declare r public.network_rounds%rowtype; v_winner uuid; v_current integer;
begin
  for r in select * from public.network_rounds where phase in ('COUNTER_DECISION','FINAL_DEFENSE_DECISION') for update loop
    v_winner:=(r.initial_resolution->>'winner_player_id')::uuid;
    if r.phase='COUNTER_DECISION' and r.counter_bid is null then
      select (action_points->>v_winner::text)::integer into v_current
        from public.network_game_states where session_id=r.session_id for update;
      update public.network_game_states set action_points=jsonb_set(action_points,array[v_winner::text],
        to_jsonb(v_current-least(coalesce((r.initial_resolution->>'gap_cost')::integer,0),v_current))) where session_id=r.session_id;
    end if;
    update public.network_rounds set phase='CORRUPTION_DECISION',updated_at=now(),
      final_resolution=public.network_final_choice(r.id,v_winner,v_winner,false)
        ||jsonb_build_object('initial_winner_player_id',v_winner,'final_winner_player_id',v_winner,
          'final_loser_player_id',r.initial_resolution->>'loser_player_id') where id=r.id;
  end loop;
end; $$;
