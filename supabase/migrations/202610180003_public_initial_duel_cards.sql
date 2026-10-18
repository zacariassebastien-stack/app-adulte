-- Add the two public action snapshots after initial resolution.
-- Existing fields and private reveal/value boundaries are preserved.
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
    -- Only resolved duel actions are public; never expose values or nonces.
    'initial_duel_cards',case when r.initial_resolution is null then '[]'::jsonb
      else coalesce((select jsonb_agg(
        v.choice_payload-'snapshot_value'-'inverted_resolution' order by v.player_id)
        from public.network_round_reveals v where v.round_id=r.id
          and v.choice_payload->'usage_schema_version'='1'::jsonb),'[]'::jsonb) end,
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
