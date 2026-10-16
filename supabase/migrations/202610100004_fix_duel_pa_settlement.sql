-- Apply the already-resolved duel cost exactly once when the final result is
-- accepted directly. Corruption may replace the action, but never its PA cost.

create or replace function public.route_network_post_duel() returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_payer uuid;
  v_cost integer;
  v_current integer;
begin
  -- The private initial resolver calculates but deliberately does not apply
  -- the duel cost. A direct ACCEPT is the single settlement point. Bids and
  -- defenses already debit their own costs in their RPCs.
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

  -- Preserve the post-duel routing installed by 202610100003.
  if old.phase='READY' and new.phase='NEGOTIATION_PROPOSAL' then
    new.phase:='COUNTER_DECISION';
  elsif new.phase='FINAL_RESOLVED' and old.phase in (
    'COUNTER_DECISION','FINAL_DEFENSE_DECISION','TIE_DECISION'
  ) then
    new.phase:=case when new.final_resolution->>'retained_player_id' is null
      then 'RECOVERY' else 'CORRUPTION_DECISION' end;
  end if;
  return new;
end;
$$;
