-- Persist duration-card effects once, when the two-player action-completion
-- barrier moves a round from FINAL_RESOLVED to WAITING_NEXT.

begin;

-- Close the small backfill/trigger-installation race: action completion may
-- resume only after both the reconstructed state and its trigger are visible.
lock table public.network_rounds in share row exclusive mode;

alter table public.network_game_states
  add column if not exists v4_persistent_effects jsonb not null default '[]'::jsonb;

create or replace function public.v4_persistent_effects_valid(p_effects jsonb)
returns boolean language sql immutable set search_path=public as $$
  select jsonb_typeof(p_effects)='array'
    and not exists(
      select 1
      from jsonb_array_elements(p_effects) effect
      where jsonb_typeof(effect)<>'object'
        or coalesce(effect->>'card_id','')=''
        or coalesce(effect->>'target_player_id','')=''
        or coalesce(effect->>'remaining_actions','') !~ '^[1-3]$'
    );
$$;

alter table public.network_game_states
  drop constraint if exists network_game_states_v4_persistent_effects_check;
alter table public.network_game_states
  add constraint network_game_states_v4_persistent_effects_check
  check (public.v4_persistent_effects_valid(v4_persistent_effects));

create table if not exists public.network_v4_persistent_effect_definitions (
  card_id text primary key,
  duration_actions integer not null check (duration_actions=3)
);

insert into public.network_v4_persistent_effect_definitions(
  card_id,duration_actions
) values
  ('card.v4.033',3),
  ('card.v4.034',3),
  ('card.v4.035',3),
  ('card.v4.060',3),
  ('card.v4.061',3),
  ('card.v4.062',3),
  ('card.v4.063',3)
on conflict (card_id) do update
set duration_actions=excluded.duration_actions;

revoke all on public.network_v4_persistent_effect_definitions
  from anon,authenticated;
revoke update on public.network_game_states
  from anon,authenticated;

create or replace function public.v4_advance_persistent_effects(
  p_active jsonb,
  p_cards jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_active jsonb:=coalesce(p_active,'[]'::jsonb);
  v_card jsonb;
  v_target text;
  v_duration integer;
begin
  if jsonb_typeof(v_active)<>'array' or jsonb_typeof(p_cards)<>'array' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  for v_card in
    select value
    from jsonb_array_elements(p_cards) with ordinality
    order by ordinality
  loop
    -- Every projected card is one executed action. Existing effects tick
    -- before a possible new effect is installed, so activation does not
    -- consume its own duration.
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'card_id',effect->>'card_id',
        'target_player_id',effect->>'target_player_id',
        'remaining_actions',(effect->>'remaining_actions')::integer-1
      ) order by effect->>'card_id',effect->>'target_player_id'
    ),'[]'::jsonb)
    into v_active
    from jsonb_array_elements(v_active) effect
    where (effect->>'remaining_actions')::integer>1;

    select duration_actions into v_duration
    from public.network_v4_persistent_effect_definitions
    where card_id=v_card->>'card_id';
    if found then
      for v_target in
        select jsonb_array_elements_text(coalesce(
          v_card->'target_player_ids','[]'::jsonb
        ))
      loop
        select coalesce(jsonb_agg(effect order by
          effect->>'card_id',effect->>'target_player_id'
        ),'[]'::jsonb)
        into v_active
        from jsonb_array_elements(v_active) effect
        where effect->>'card_id' is distinct from v_card->>'card_id'
          or effect->>'target_player_id' is distinct from v_target;
        v_active:=v_active||jsonb_build_array(jsonb_build_object(
          'card_id',v_card->>'card_id',
          'target_player_id',v_target,
          'remaining_actions',v_duration
        ));
      end loop;
    end if;
  end loop;
  return v_active;
end;
$$;

revoke all on function public.v4_persistent_effects_valid(jsonb) from public;
revoke all on function public.v4_advance_persistent_effects(jsonb,jsonb)
  from public;

-- Existing active sessions are reconstructed only from rounds whose normal
-- execution barrier was crossed. FINAL_RESOLVED and SESSION_CLOSED rounds are
-- deliberately excluded, so an unexecuted projection cannot create an effect.
do $$
declare
  v_game record;
  v_round record;
  v_effects jsonb;
begin
  for v_game in
    select game.session_id
    from public.network_game_states game
    join public.game_sessions session on session.id=game.session_id
    where session.status<>'closed'
  loop
    v_effects:='[]'::jsonb;
    for v_round in
      select round.id,round.v4_action_projection
      from public.network_rounds round
      where round.session_id=v_game.session_id
        and round.phase in ('WAITING_NEXT','CLOSED')
      order by round.round_number
    loop
      v_effects:=public.v4_advance_persistent_effects(
        v_effects,
        coalesce(v_round.v4_action_projection->'cards','[]'::jsonb)
      );
    end loop;
    update public.network_game_states
    set v4_persistent_effects=v_effects
    where session_id=v_game.session_id;
  end loop;
end;
$$;

create or replace function public.apply_network_v4_persistent_effects()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if old.phase='FINAL_RESOLVED' and new.phase='WAITING_NEXT' then
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

drop trigger if exists network_v4_persistent_effects_on_action_close
  on public.network_rounds;
create trigger network_v4_persistent_effects_on_action_close
after update of phase on public.network_rounds
for each row
when (old.phase is distinct from new.phase)
execute function public.apply_network_v4_persistent_effects();

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
    'v4_persistent_effects',g.v4_persistent_effects,
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

commit;
