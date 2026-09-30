-- Depends on 202609300002_network_corruption_recovery.sql.
-- A Recovery proposal identifies the public action but must not disclose its
-- private profile-derived gain before the partner has accepted it.

create function public.enforce_network_recovery_proposal_privacy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_proposal jsonb;
begin
  if old.phase = 'RECOVERY' and new.phase = 'RECOVERY_RESPONSE' then
    select proposal.value
      into v_proposal
      from jsonb_each(new.recovery_by_player) as proposal
     where not (old.recovery_done ? proposal.key)
     order by proposal.key
     limit 1;

    if v_proposal is null
       or not (v_proposal ? 'gain')
       or (v_proposal->>'gain')::integer <> 0
       or not (v_proposal ? 'completed')
       or (v_proposal->>'completed')::boolean
       or v_proposal->>'response' is not null then
      raise exception 'ROUND_RECOVERY_PROPOSAL_PRIVATE';
    end if;
  end if;
  return new;
end;
$$;

create trigger network_rounds_recovery_proposal_privacy
before update on public.network_rounds
for each row execute function public.enforce_network_recovery_proposal_privacy();

revoke all on function public.enforce_network_recovery_proposal_privacy()
  from public;
