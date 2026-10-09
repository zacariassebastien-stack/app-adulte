alter table public.network_game_states
  add column if not exists cycle_exhausted boolean not null default false;

alter table public.network_rounds
  add column if not exists v4_action_projection jsonb,
  add column if not exists v4_clothing_resynced jsonb not null default '{}'::jsonb;

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
    'PUBLISH_V4_ACTION'
  ));

alter table public.game_sessions
  add column if not exists v4_session_mode text
    check (v4_session_mode in ('presentiel','distance','hybrid'));
alter table public.session_players
  add column if not exists v4_clothing_count integer check (v4_clothing_count >= 0),
  add column if not exists v4_accessories jsonb;

-- Realtime must never expose the storage row: it contains server-private
-- reveals, value snapshots and resolution metrics. Clients subscribe to this
-- revision-only table, then fetch the requester-specific public projection via
-- a SECURITY DEFINER RPC.
create table if not exists public.network_round_public_events (
  round_id uuid primary key references public.network_rounds(id) on delete cascade,
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  revision bigint not null default 1,
  changed_at timestamptz not null default now()
);

create index if not exists network_round_public_events_session_idx
  on public.network_round_public_events(session_id);

alter table public.network_round_public_events enable row level security;
drop policy if exists "members observe public round changes"
  on public.network_round_public_events;
create policy "members observe public round changes"
on public.network_round_public_events for select to authenticated
using (public.is_session_member(session_id));

revoke all on public.network_round_public_events from anon, authenticated;
grant select on public.network_round_public_events to authenticated;

insert into public.network_round_public_events(round_id, session_id)
select id, session_id from public.network_rounds
on conflict (round_id) do nothing;

create or replace function public.signal_network_round_public_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.network_round_public_events(
    round_id, session_id, revision, changed_at
  ) values (new.id, new.session_id, 1, now())
  on conflict (round_id) do update set
    revision = public.network_round_public_events.revision + 1,
    changed_at = now();
  return new;
end;
$$;

revoke all on function public.signal_network_round_public_change() from public;

drop trigger if exists network_round_public_change on public.network_rounds;
create trigger network_round_public_change
after insert or update on public.network_rounds
for each row execute function public.signal_network_round_public_change();

create or replace function public.signal_network_game_state_public_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_round_id uuid;
begin
  select id into v_round_id
  from public.network_rounds
  where session_id = new.session_id
  order by round_number desc
  limit 1;
  if v_round_id is not null then
    insert into public.network_round_public_events(
      round_id, session_id, revision, changed_at
    ) values (v_round_id, new.session_id, 1, now())
    on conflict (round_id) do update set
      revision = public.network_round_public_events.revision + 1,
      changed_at = now();
  end if;
  return new;
end;
$$;

revoke all on function public.signal_network_game_state_public_change()
  from public;

drop trigger if exists network_game_state_public_change
  on public.network_game_states;
create trigger network_game_state_public_change
after update on public.network_game_states
for each row execute function public.signal_network_game_state_public_change();

drop policy if exists "members observe round changes" on public.network_rounds;
revoke select on public.network_rounds from anon, authenticated;

alter publication supabase_realtime drop table public.network_rounds;
alter publication supabase_realtime add table public.network_round_public_events;

create or replace function public.v4_session_setup_json(p_session_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'mode', s.v4_session_mode,
    'players', coalesce(jsonb_agg(jsonb_build_object(
      'player_id', p.user_id,
      'clothing_count', p.v4_clothing_count,
      'accessories', coalesce(p.v4_accessories, '[]'::jsonb)
    ) order by p.role) filter (where p.v4_clothing_count is not null), '[]'::jsonb)
  ) from public.game_sessions s
  left join public.session_players p on p.session_id = s.id
  where s.id = p_session_id group by s.id;
$$;

create or replace function public.get_v4_session_setup(p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  return public.v4_session_setup_json(p_session_id);
end;
$$;

create or replace function public.submit_v4_session_setup(
  p_session_id uuid,
  p_clothing_count integer,
  p_accessories jsonb,
  p_mode text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text; v_accessories jsonb;
begin
  if auth.uid() is null or not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if p_clothing_count is null or p_clothing_count < 0
    or jsonb_typeof(p_accessories) <> 'array' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', item->>'id', 'name', item->>'name',
    'owner_player_id', auth.uid(), 'tags', coalesce(item->'tags','[]'::jsonb),
    'normally_active', coalesce((item->>'normally_active')::boolean, true),
    'temporary', coalesce((item->>'temporary')::boolean, false),
    'remote_controllable', coalesce((item->>'remote_controllable')::boolean, false)
  )), '[]'::jsonb) into v_accessories
  from jsonb_array_elements(p_accessories) item;
  select role into v_role from public.session_players
  where session_id = p_session_id and user_id = auth.uid();
  if v_role = 'PLAYER_1' then
    if p_mode not in ('presentiel','distance','hybrid') then
      raise exception 'ROUND_INVALID_ARGUMENT';
    end if;
    if exists(select 1 from public.game_sessions where id=p_session_id
      and v4_session_mode is not null and v4_session_mode<>p_mode) then
      raise exception 'ROUND_SESSION_MODE_IMMUTABLE';
    end if;
    update public.game_sessions set v4_session_mode = p_mode, updated_at = now()
    where id = p_session_id;
  elsif p_mode is not null then
    raise exception 'ROUND_NOT_ACTIVE_PLAYER';
  end if;
  update public.session_players set
    v4_clothing_count = p_clothing_count,
    v4_accessories = v_accessories
  where session_id = p_session_id and user_id = auth.uid();
  return public.v4_session_setup_json(p_session_id);
end;
$$;

revoke all on function public.v4_session_setup_json(uuid) from public;
revoke all on function public.get_v4_session_setup(uuid) from public;
revoke all on function public.submit_v4_session_setup(uuid,integer,jsonb,text) from public;
grant execute on function public.get_v4_session_setup(uuid) to authenticated;
grant execute on function public.submit_v4_session_setup(uuid,integer,jsonb,text) to authenticated;

create or replace function public.v4_public_compromise_cards(p_cards jsonb)
returns jsonb language sql immutable set search_path=public as $$
  select coalesce(
    jsonb_agg(item.value - 'snapshot_value' order by item.ordinality),
    '[]'::jsonb
  )
  from jsonb_array_elements(coalesce(p_cards, '[]'::jsonb))
    with ordinality item(value, ordinality);
$$;

create or replace function public.v4_public_negotiation(
  p_negotiation jsonb,
  p_include_private_snapshots boolean
) returns jsonb language plpgsql immutable set search_path=public as $$
declare
  v_result jsonb := p_negotiation;
begin
  if v_result is null or p_include_private_snapshots then return v_result; end if;
  if jsonb_typeof(v_result->'proposal') = 'object' then
    v_result := jsonb_set(
      v_result,
      '{proposal,cards}',
      public.v4_public_compromise_cards(v_result#>'{proposal,cards}'),
      true
    );
  end if;
  if jsonb_typeof(v_result->'final_offer') = 'object' then
    v_result := jsonb_set(
      v_result,
      '{final_offer,cards}',
      public.v4_public_compromise_cards(v_result#>'{final_offer,cards}'),
      true
    );
  end if;
  return v_result;
end;
$$;

revoke all on function public.v4_public_compromise_cards(jsonb) from public;
revoke all on function public.v4_public_negotiation(jsonb,boolean) from public;

create or replace function public.network_round_json(
  p_round_id uuid,
  p_requester uuid
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'schema_version',1,'round_id',r.id,'session_id',r.session_id,
    'session_round',r.round_key,'round_number',r.round_number,'phase',r.phase,
    'player_id',p_requester,'action_points',g.action_points,
    'hybrid_orientation',g.hybrid_orientation,'deck_cycle',g.deck_cycle,
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
      p_requester::text=r.initial_resolution->>'loser_player_id'
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

create or replace function public.resolve_network_initial_private(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_reveal record;
  v_first_player uuid;
  v_second_player uuid;
  v_first_choice jsonb;
  v_second_choice jsonb;
  v_first_value integer;
  v_second_value integer;
  v_winner uuid;
  v_loser uuid;
  v_winner_choice jsonb;
  v_opposite_value text;
  v_gap integer;
  v_gap_cost integer;
  v_high_value integer;
  v_points jsonb;
  v_inversion_allowed boolean;
  v_resolution jsonb;
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
      or v_command.player_id<>p_player_id or v_command.kind<>'INITIAL_RESOLVE'
      or v_command.command_payload is distinct from '{}'::jsonb then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  if v_round.phase<>'READY' then
    if v_round.initial_resolution is null then raise exception 'ROUND_INVALID_PHASE'; end if;
    insert into public.network_round_commands(
      command_id,session_id,round_id,player_id,kind,command_payload
    ) values(p_command_id,p_session_id,p_round_id,p_player_id,'INITIAL_RESOLVE','{}'::jsonb);
    return public.network_round_json(p_round_id,p_player_id);
  end if;

  for v_reveal in
    select player_id,choice_payload from public.network_round_reveals
    where round_id=p_round_id order by player_id
  loop
    if v_first_player is null then
      v_first_player:=v_reveal.player_id;
      v_first_choice:=v_reveal.choice_payload;
    elsif v_second_player is null then
      v_second_player:=v_reveal.player_id;
      v_second_choice:=v_reveal.choice_payload;
    else
      raise exception 'ROUND_READY_INCOMPLETE';
    end if;
  end loop;
  if v_first_player is null or v_second_player is null then
    raise exception 'ROUND_READY_INCOMPLETE';
  end if;
  if coalesce(v_first_choice#>>'{parameters,personal_value}','') !~ '^[0-9]+$'
    or coalesce(v_second_choice#>>'{parameters,personal_value}','') !~ '^[0-9]+$' then
    raise exception 'ROUND_RESOLUTION_MISMATCH';
  end if;
  v_first_value:=(v_first_choice#>>'{parameters,personal_value}')::integer;
  v_second_value:=(v_second_choice#>>'{parameters,personal_value}')::integer;
  if v_first_value not between 1 and 20 or v_second_value not between 1 and 20 then
    raise exception 'ROUND_RESOLUTION_MISMATCH';
  end if;
  if coalesce(v_first_choice#>>'{parameters,effective_direction}',
      v_first_choice#>>'{parameters,role}','GENERAL') <>
      coalesce(v_first_choice#>>'{parameters,native_direction}',
      v_first_choice#>>'{parameters,role}','GENERAL')
    or coalesce(v_second_choice#>>'{parameters,effective_direction}',
      v_second_choice#>>'{parameters,role}','GENERAL') <>
      coalesce(v_second_choice#>>'{parameters,native_direction}',
      v_second_choice#>>'{parameters,role}','GENERAL') then
    raise exception 'ROUND_DIRECTION_MISMATCH';
  end if;

  select action_points into v_points from public.network_game_states
  where session_id=p_session_id for update;
  v_gap:=abs(v_first_value-v_second_value);
  v_high_value:=greatest(v_first_value,v_second_value);
  if v_gap=0 then
    v_winner:=null;
    v_loser:=null;
    v_gap_cost:=0;
    v_inversion_allowed:=false;
  else
    if v_first_value>v_second_value then
      v_winner:=v_first_player; v_loser:=v_second_player;
      v_winner_choice:=v_first_choice;
    else
      v_winner:=v_second_player; v_loser:=v_first_player;
      v_winner_choice:=v_second_choice;
    end if;
    v_gap_cost:=least(v_gap,(v_points->>v_winner::text)::integer);
    v_opposite_value:=coalesce(
      v_winner_choice#>>'{parameters,opposite_personal_value}',
      ''
    );
    v_inversion_allowed:=case when v_opposite_value ~ '^[0-9]+$'
      then v_opposite_value::integer between 1 and 20
      else false end;
  end if;
  v_resolution:=jsonb_build_object(
    'tied',v_gap=0,'winner_player_id',v_winner,'loser_player_id',v_loser,
    'gap',v_gap,'gap_cost',v_gap_cost,'high_value',v_high_value,
    'action_points',v_points,'inversion_allowed',v_inversion_allowed
  );
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'INITIAL_RESOLVE','{}'::jsonb);
  update public.network_rounds set initial_resolution=v_resolution,
    phase=case when v_gap=0 then 'TIE_DECISION' else 'NEGOTIATION_PROPOSAL' end,
    updated_at=now() where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

revoke execute on function public.submit_network_initial_resolution(
  uuid,uuid,uuid,jsonb,text
) from authenticated;
revoke all on function public.resolve_network_initial_private(
  uuid,uuid,uuid,text
) from public;
grant execute on function public.resolve_network_initial_private(
  uuid,uuid,uuid,text
) to authenticated;

-- Keep every parameter that was covered by commit/reveal with the final
-- compromise. FINAL_RESOLVED deliberately stops exposing the opponent reveal,
-- so reconnecting clients must be able to rebuild the action from this durable
-- projection instead of from process-local reveal caches.
create or replace function public.v4_verified_final_resolution(
  p_round_id uuid,
  p_final_resolution jsonb
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_card jsonb;
  v_choice jsonb;
  v_reveal_player uuid;
  v_parameters jsonb;
  v_effective_spice jsonb;
  v_native_direction text;
  v_effective_direction text;
  v_compromise jsonb := '[]'::jsonb;
begin
  if p_final_resolution is null
    or jsonb_typeof(p_final_resolution->'compromise') <> 'array' then
    raise exception 'ROUND_ACTION_PARAMETERS_MISSING';
  end if;

  for v_card in
    select value
    from jsonb_array_elements(p_final_resolution->'compromise')
  loop
    select reveal.choice_payload, reveal.player_id
    into v_choice, v_reveal_player
    from public.network_round_reveals reveal
    where reveal.round_id = p_round_id
      and reveal.choice_payload#>>'{parameters,occurrence_id}' =
        v_card->>'occurrence_id'
    limit 1;

    if found then
      v_parameters := v_choice#>'{parameters,resolved_parameters}';
      v_effective_spice := v_choice#>'{parameters,effective_spice}';
      v_native_direction := coalesce(
        v_choice#>>'{parameters,native_direction}',
        v_choice#>>'{parameters,role}',
        'GENERAL'
      );
      v_effective_direction := coalesce(
        v_choice#>>'{parameters,effective_direction}',
        v_choice#>>'{parameters,role}',
        'GENERAL'
      );
      if coalesce((p_final_resolution->>'inverted')::boolean, false)
        and v_card->>'origin' = 'INITIAL_DUEL' then
        v_effective_direction := case v_effective_direction
          when 'FAIRE' then 'RECEVOIR'
          when 'RECEVOIR' then 'FAIRE'
          else v_effective_direction
        end;
      end if;

      if v_card->>'card_id' is distinct from v_choice->>'card_id'
        or v_card->>'variant_id' is distinct from v_choice->>'variant_id'
        or v_card->>'owner_player_id' is distinct from v_reveal_player::text
        or v_card->>'native_direction' is distinct from v_native_direction
        or v_card->>'effective_direction' is distinct from v_effective_direction then
        raise exception 'ROUND_ACTION_IDENTITY_MISMATCH';
      end if;
      if jsonb_typeof(v_parameters) <> 'object'
        or jsonb_typeof(v_effective_spice) <> 'number' then
        raise exception 'ROUND_ACTION_PARAMETERS_MISSING';
      end if;

      if coalesce(jsonb_typeof(v_card->'resolved_parameters'), 'null') <> 'null'
        and v_card->'resolved_parameters' is distinct from v_parameters then
        raise exception 'ROUND_ACTION_PARAMETERS_MISMATCH';
      end if;
      if coalesce(jsonb_typeof(v_card->'effective_spice'), 'null') <> 'null'
        and v_card->'effective_spice' is distinct from v_effective_spice then
        raise exception 'ROUND_ACTION_PARAMETERS_MISMATCH';
      end if;
      v_card := v_card || jsonb_build_object(
        'resolved_parameters', v_parameters,
        'effective_spice', v_effective_spice
      );
    elsif jsonb_typeof(v_card->'resolved_parameters') <> 'object'
      or jsonb_typeof(v_card->'effective_spice') <> 'number' then
      -- Non-initial compromise cards have no round reveal of their own. They
      -- must therefore already carry the parameters persisted with the
      -- accepted negotiation; inventing them here would be a reroll.
      raise exception 'ROUND_ACTION_PARAMETERS_MISSING';
    end if;
    v_compromise := v_compromise || jsonb_build_array(v_card);
  end loop;

  return jsonb_set(
    p_final_resolution,
    '{compromise}',
    v_compromise,
    true
  );
end;
$$;

revoke all on function public.v4_verified_final_resolution(uuid,jsonb)
  from public;

create or replace function public.persist_v4_resolved_action_parameters()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.final_resolution := public.v4_verified_final_resolution(
    new.id,
    new.final_resolution
  );
  return new;
end;
$$;

drop trigger if exists network_rounds_persist_v4_action_parameters
  on public.network_rounds;
create trigger network_rounds_persist_v4_action_parameters
before insert or update of final_resolution on public.network_rounds
for each row
when (new.final_resolution is not null)
execute function public.persist_v4_resolved_action_parameters();

create or replace function public.repair_v4_action_parameters(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_verified jsonb;
begin
  if auth.uid() is null or auth.uid() <> p_player_id
    or not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text, 0));
  select * into v_command from public.network_round_commands
  where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id
      or v_command.kind<>'REPAIR_V4_ACTION_PARAMETERS'
      or v_command.command_payload is distinct from '{}'::jsonb then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'FINAL_RESOLVED' then raise exception 'ROUND_INVALID_PHASE'; end if;
  v_verified := public.v4_verified_final_resolution(
    p_round_id,
    v_round.final_resolution
  );
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(
    p_command_id,p_session_id,p_round_id,p_player_id,
    'REPAIR_V4_ACTION_PARAMETERS','{}'::jsonb
  );
  if v_verified is distinct from v_round.final_resolution then
    update public.network_rounds set final_resolution=v_verified,updated_at=now()
    where id=p_round_id;
  end if;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

revoke all on function public.repair_v4_action_parameters(
  uuid,uuid,uuid,text
) from public;
grant execute on function public.repair_v4_action_parameters(
  uuid,uuid,uuid,text
) to authenticated;

create or replace function public.publish_v4_action_projection(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_command_id text,
  p_projection jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_required text;
  v_verified jsonb;
  v_card jsonb;
  v_projection_card jsonb;
  v_expected_targets jsonb;
  v_card_index integer := 0;
begin
  if auth.uid() is null or auth.uid() <> p_player_id
    or not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if jsonb_typeof(p_projection->'cards') <> 'array'
    or jsonb_typeof(p_projection->'required_clothing_player_ids') <> 'array'
    or p_projection::text ~* '"(pa|preferences|personal_value|opposite_personal_value)"[[:space:]]*:' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  for v_required in
    select jsonb_array_elements_text(p_projection->'required_clothing_player_ids')
  loop
    if not exists(select 1 from public.session_players
      where session_id=p_session_id and user_id=v_required::uuid) then
      raise exception 'ROUND_INVALID_ARGUMENT';
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtextextended(p_round_id::text, 0));
  select * into v_command from public.network_round_commands
  where command_id=p_command_id;
  if found then
    if v_command.session_id<>p_session_id or v_command.round_id<>p_round_id
      or v_command.player_id<>p_player_id or v_command.kind<>'PUBLISH_V4_ACTION'
      or v_command.command_payload is distinct from p_projection then
      raise exception 'ROUND_COMMAND_CONFLICT';
    end if;
    return public.network_round_json(p_round_id,p_player_id);
  end if;
  select * into v_round from public.network_rounds where id=p_round_id for update;
  if not found or v_round.session_id<>p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase<>'FINAL_RESOLVED' then raise exception 'ROUND_INVALID_PHASE'; end if;
  v_verified := public.v4_verified_final_resolution(
    p_round_id,
    v_round.final_resolution
  );
  if v_verified is distinct from v_round.final_resolution then
    update public.network_rounds set final_resolution=v_verified,updated_at=now()
    where id=p_round_id;
  end if;
  if jsonb_array_length(p_projection->'cards') <>
    jsonb_array_length(v_verified->'compromise') then
    raise exception 'ROUND_ACTION_PROJECTION_MISMATCH';
  end if;
  for v_card in
    select value from jsonb_array_elements(v_verified->'compromise')
  loop
    v_projection_card := p_projection->'cards'->v_card_index;
    if v_card->>'effective_direction' in ('RECEVOIR','SOLO') then
      v_expected_targets := jsonb_build_array(v_card->>'owner_player_id');
    elsif v_card->>'effective_direction' = 'FAIRE' then
      select coalesce(jsonb_agg(player.user_id::text order by player.user_id::text),'[]'::jsonb)
      into v_expected_targets
      from public.session_players player
      where player.session_id=p_session_id
        and player.user_id<>(v_card->>'owner_player_id')::uuid;
    else
      select coalesce(jsonb_agg(player.user_id::text order by player.user_id::text),'[]'::jsonb)
      into v_expected_targets
      from public.session_players player
      where player.session_id=p_session_id;
    end if;
    if v_projection_card->>'occurrence_id' is distinct from v_card->>'occurrence_id'
      or v_projection_card->>'card_id' is distinct from v_card->>'card_id'
      or v_projection_card->>'variant_id' is distinct from v_card->>'variant_id'
      or v_projection_card->>'direction' is distinct from v_card->>'effective_direction'
      or v_projection_card->'target_player_ids' is distinct from v_expected_targets
      or v_projection_card->'effective_spice' is distinct from v_card->'effective_spice'
      or coalesce(v_projection_card->'zone_id','null'::jsonb) is distinct from
        coalesce(v_card->'resolved_parameters'->'zone_id','null'::jsonb)
      or coalesce(v_projection_card->'accessory_id','null'::jsonb) is distinct from
        coalesce(v_card->'resolved_parameters'->'accessory_id','null'::jsonb)
      or v_projection_card->'parameters' is distinct from v_card->'resolved_parameters' then
      raise exception 'ROUND_ACTION_PROJECTION_MISMATCH';
    end if;
    v_card_index := v_card_index + 1;
  end loop;
  insert into public.network_round_commands(
    command_id,session_id,round_id,player_id,kind,command_payload
  ) values(p_command_id,p_session_id,p_round_id,p_player_id,'PUBLISH_V4_ACTION',p_projection);
  update public.network_rounds set
    v4_action_projection=coalesce(v4_action_projection,p_projection),updated_at=now()
  where id=p_round_id;
  return public.network_round_json(p_round_id,p_player_id);
end;
$$;

revoke all on function public.publish_v4_action_projection(
  uuid,uuid,uuid,text,jsonb
) from public;
grant execute on function public.publish_v4_action_projection(
  uuid,uuid,uuid,text,jsonb
) to authenticated;

-- V4: the resolved action is a shared ACTION_IN_PROGRESS state. The first
-- player who confirms "Terminé" closes it for both players. READY_NEXT stays
-- as the wire command name so deployed clients and idempotency keys remain
-- compatible.
drop function if exists public.ready_network_next_round(uuid, uuid, uuid, text);
drop function if exists public.ready_network_next_round(uuid, uuid, uuid, text, boolean);
create function public.ready_network_next_round(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_command_id text,
  p_no_playable_occurrences boolean default false,
  p_clothing_count integer default null
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
    'clothing_count', p_clothing_count
  );
  select * into v_command
  from public.network_round_commands
  where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id
      or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id
      or v_command.kind <> 'READY_NEXT'
      or v_command.command_payload is distinct from v_payload then
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
  if v_round.phase not in ('FINAL_RESOLVED', 'WAITING_NEXT') then
    raise exception 'ROUND_INVALID_PHASE';
  end if;
  if p_clothing_count is not null and p_clothing_count < 0 then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  if v_round.phase = 'WAITING_NEXT' and exists(
    select 1 from public.network_game_states
    where session_id = p_session_id and cycle_exhausted
  ) then
    raise exception 'ROUND_CYCLE_EXHAUSTED';
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
    if p_no_playable_occurrences then
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
  uuid, uuid, uuid, text, boolean, integer
) from public;
grant execute on function public.ready_network_next_round(
  uuid, uuid, uuid, text, boolean, integer
) to authenticated;

-- A hybrid context is a cycle-boundary decision. Enforce the same boundary on
-- the server so an older or modified client cannot change eligibility while an
-- action is being selected or resolved.
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
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

revoke all on function public.set_network_hybrid_orientation(
  uuid, uuid, uuid, text, text
) from public;
grant execute on function public.set_network_hybrid_orientation(
  uuid, uuid, uuid, text, text
) to authenticated;

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
    updated_at = now()
  where session_id = p_session_id;
  if p_choice in ('NEW_GAME','FINISH') then
    update public.game_sessions set status = 'closed' where id = p_session_id;
  end if;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

revoke all on function public.continue_network_deck_cycle(
  uuid,uuid,uuid,text,jsonb,text
) from public;
grant execute on function public.continue_network_deck_cycle(
  uuid,uuid,uuid,text,jsonb,text
) to authenticated;
