-- Verify current-round duel cards against their owner's reveal without
-- confusing canonical discard arguments with a colliding occurrence ID.

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
    v_choice := null;
    v_reveal_player := null;

    if v_card->>'origin' = 'INITIAL_DUEL' then
      select reveal.choice_payload, reveal.player_id
      into v_choice, v_reveal_player
      from public.network_round_reveals reveal
      where reveal.round_id = p_round_id
        and reveal.player_id::text = v_card->>'owner_player_id'
        and reveal.choice_payload#>>'{parameters,occurrence_id}' =
          v_card->>'occurrence_id'
      limit 1;

      if not found then
        raise exception 'ROUND_ACTION_IDENTITY_MISMATCH';
      end if;

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
      if coalesce((p_final_resolution->>'inverted')::boolean, false) then
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
      -- AUCTION and CORRUPTION cards were already reconstructed and validated
      -- before entering the final resolution. Never bind them to an unrelated
      -- current-round reveal merely because an occurrence ID collides.
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
