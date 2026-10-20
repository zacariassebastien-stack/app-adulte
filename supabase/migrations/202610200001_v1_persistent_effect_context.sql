-- Preserve frozen effect context; Sexting counts completed rounds, not cards.
begin;

create or replace function public.v4_advance_persistent_effects(p_active jsonb, p_cards jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_active jsonb;
  v_card jsonb;
  v_action jsonb;
  v_target text;
  v_targets jsonb;
  v_duration integer;
  v_unit text;
begin
  if jsonb_typeof(coalesce(p_active,'[]'::jsonb))<>'array' or jsonb_typeof(p_cards)<>'array' then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;
  -- A closed round consumes one turn, even when it contains several actions.
  -- Newly activated Sexting is installed below, after this tick.
  select coalesce(jsonb_agg(case when effect->>'unit'='turns'
    then effect||jsonb_build_object('remaining_actions',(effect->>'remaining_actions')::integer-1)
    else effect end),'[]'::jsonb) into v_active
  from jsonb_array_elements(coalesce(p_active,'[]'::jsonb)) effect
  where effect->>'unit' is distinct from 'turns' or (effect->>'remaining_actions')::integer>1;

  for v_card in select value from jsonb_array_elements(p_cards) with ordinality order by ordinality loop
    -- Preserve metadata while ticking only action-based effects per card.
    select coalesce(jsonb_agg(case when effect->>'unit'='turns' then effect
      else effect||jsonb_build_object('remaining_actions',(effect->>'remaining_actions')::integer-1) end
      order by effect->>'card_id',effect->>'target_player_id'),'[]'::jsonb)
    into v_active from jsonb_array_elements(v_active) effect
    where effect->>'unit'='turns' or (effect->>'remaining_actions')::integer>1;

    v_action:=v_card->'resolved_action';
    v_unit:=case when v_card->>'concept_id'='042' then 'turns' else 'actions' end;
    v_duration:=case when v_unit='turns' then 3
      else (v_action#>>'{parameters,duration_actions}')::integer end;
    if v_duration is not null then
      v_targets:=case when v_card->>'concept_id' in ('033','061')
        then v_action->'actor_player_ids' else v_action->'target_player_ids' end;
      for v_target in select jsonb_array_elements_text(coalesce(v_targets,'[]'::jsonb)) loop
        select coalesce(jsonb_agg(effect),'[]'::jsonb) into v_active
        from jsonb_array_elements(v_active) effect
        where effect->>'card_id' is distinct from v_card->>'concept_id'
          or effect->>'target_player_id' is distinct from v_target;
        v_active:=v_active||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
          'card_id',v_card->>'concept_id','target_player_id',v_target,
          'remaining_actions',v_duration,'unit',v_unit,
          'stage_id',v_action->>'stage_id','actor_player_ids',v_action->'actor_player_ids',
          'action_text',v_action->>'action_text',
          'instruction',v_action#>>'{parameters,persistent_instruction}'
        )));
      end loop;
    end if;
  end loop;
  return v_active;
end;
$$;

-- No historical snapshots or already active effects are removed or rewritten.
commit;
