-- PA balances are already settled transactionally by every spending RPC,
-- including counter-bids and final defenses. Recovery is the only PA credit;
-- its accepted gain is recorded once in network_round_commands before crediting
-- the balance. Reconstruct gross spending from those canonical facts instead
-- of maintaining another consumption ledger (also covers existing sessions).
create or replace function public.network_total_pa_spent(
  p_session_id uuid, p_action_points jsonb
) returns bigint language sql stable set search_path=public as $$
  select greatest(0::bigint,
    coalesce((select sum(100 - balance.value::bigint)
      from jsonb_each_text(p_action_points) balance),0)
    + coalesce((select sum((command_payload->>'gain')::bigint)
      from public.network_round_commands
      where session_id=p_session_id and kind='RECOVERY_RESOLVE'),0)
  );
$$;

create or replace function public.network_spice_for_pa(
  p_style text, p_total bigint
) returns integer language sql immutable as $$
  select case p_style
    when 'SOFT' then case when p_total>=150 then 4 when p_total>=100 then 3 when p_total>=40 then 2 else 1 end
    when 'EPICE' then case when p_total>=120 then 4 when p_total>=75 then 3 when p_total>=30 then 2 else 1 end
    when 'INTENABLE' then case when p_total>=90 then 4 when p_total>=55 then 3 when p_total>=20 then 2 else 1 end
  end;
$$;

create or replace function public.update_network_pa_spice()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  -- The stored ceiling never falls, including on Recovery or cycle changes.
  -- Ignore any legacy client-requested ceiling: only settled PA can unlock it.
  new.v4_unlocked_spice:=greatest(old.v4_unlocked_spice,
    public.network_spice_for_pa(new.deck_style,
      public.network_total_pa_spent(new.session_id,new.action_points)));
  return new;
end;
$$;

create trigger network_pa_spice
before update of action_points,deck_style,v4_unlocked_spice
on public.network_game_states
for each row execute function public.update_network_pa_spice();

-- Preserve the RPC signature for older clients; a pool projection can no
-- longer publish a ceiling. Reads/retries simply return the canonical state.
create or replace function public.publish_network_v4_unlocked_spice(
  p_session_id uuid,p_round_id uuid,p_player_id uuid,
  p_unlocked_spice integer,p_command_id text
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or auth.uid()<>p_player_id then
    raise exception 'ROUND_IDENTITY_MISMATCH';
  end if;
  if not public.is_session_member(p_session_id) then
    raise exception 'ROUND_NOT_MEMBER';
  end if;
  if not exists(select 1 from public.network_rounds
    where id=p_round_id and session_id=p_session_id) then
    raise exception 'ROUND_NOT_FOUND';
  end if;
  return public.get_current_network_game_round(p_session_id,p_player_id);
end;
$$;

revoke all on function public.network_total_pa_spent(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.network_spice_for_pa(text,bigint) from public,anon,authenticated;
revoke all on function public.update_network_pa_spice() from public,anon,authenticated;

-- Apply PA thresholds to sessions already in progress without lowering a
-- previously unlocked level. New sessions retain the existing default of 1.
update public.network_game_states set v4_unlocked_spice=v4_unlocked_spice;
