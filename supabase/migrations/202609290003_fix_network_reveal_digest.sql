-- Supabase installs pgcrypto in the `extensions` schema. The Phase 6.3A
-- function uses a restricted search_path, so digest must be schema-qualified.
create or replace function public.submit_network_round_reveal(
  p_session_id uuid,
  p_round_id uuid,
  p_player_id uuid,
  p_choice_payload jsonb,
  p_nonce text,
  p_command_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_round public.network_rounds%rowtype;
  v_command public.network_round_commands%rowtype;
  v_expected text;
  v_envelope text;
begin
  if auth.uid() is null or auth.uid() <> p_player_id then raise exception 'ROUND_IDENTITY_MISMATCH'; end if;
  if not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_choice_payload is null or jsonb_typeof(p_choice_payload) <> 'object'
    or p_nonce is null or length(p_nonce) = 0
    or p_command_id is null or length(trim(p_command_id)) = 0 then
    raise exception 'ROUND_INVALID_ARGUMENT';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_command_id, 0));
  select * into v_command from public.network_round_commands where command_id = p_command_id;
  if found then
    if v_command.session_id <> p_session_id or v_command.round_id <> p_round_id
      or v_command.player_id <> p_player_id or v_command.kind <> 'REVEAL'
      or not exists (
        select 1 from public.network_round_reveals
        where command_id = p_command_id and choice_payload = p_choice_payload and nonce = p_nonce
      ) then raise exception 'ROUND_COMMAND_CONFLICT'; end if;
    return public.network_round_json(p_round_id, p_player_id);
  end if;

  select * into v_round from public.network_rounds where id = p_round_id for update;
  if not found or v_round.session_id <> p_session_id then raise exception 'ROUND_NOT_FOUND'; end if;
  if v_round.phase <> 'REVEAL' then raise exception 'ROUND_REVEAL_CLOSED'; end if;

  select digest into v_expected from public.network_round_commits
  where round_id = p_round_id and player_id = p_player_id;
  if v_expected is null then raise exception 'ROUND_COMMIT_MISSING'; end if;

  v_envelope := '[' || to_jsonb(v_round.round_key)::text || ',' || to_jsonb(p_player_id::text)::text || ','
    || to_jsonb(public.canonical_jsonb(p_choice_payload))::text || ',' || to_jsonb(p_nonce)::text || ']';
  if encode(extensions.digest(convert_to(v_envelope, 'UTF8'), 'sha256'::text), 'hex') <> v_expected then
    raise exception 'ROUND_REVEAL_MISMATCH';
  end if;

  insert into public.network_round_commands(command_id, session_id, round_id, player_id, kind)
  values (p_command_id, p_session_id, p_round_id, p_player_id, 'REVEAL');
  insert into public.network_round_reveals(round_id, player_id, choice_payload, nonce, command_id)
  values (p_round_id, p_player_id, p_choice_payload, p_nonce, p_command_id);

  update public.network_rounds
  set phase = case
      when (select count(*) from public.network_round_reveals where round_id = p_round_id) = 2
        then 'READY'
      else phase
    end,
    updated_at = now()
  where id = p_round_id;
  return public.network_round_json(p_round_id, p_player_id);
end;
$$;

revoke all on function public.submit_network_round_reveal(uuid, uuid, uuid, jsonb, text, text) from public;
grant execute on function public.submit_network_round_reveal(uuid, uuid, uuid, jsonb, text, text) to authenticated;
