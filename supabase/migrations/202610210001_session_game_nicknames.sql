-- Optional session identity metadata; existing members/clients remain valid.
alter table public.session_players add column game_nickname text
  check (game_nickname is null or
    (game_nickname = btrim(game_nickname) and char_length(game_nickname) between 2 and 20));

create or replace function public.lobby_json(p_session_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', s.id, 'join_code', s.join_code, 'status', s.status, 'expires_at', s.expires_at,
    'players', coalesce(jsonb_agg(jsonb_build_object(
      'user_id', p.user_id, 'role', p.role, 'game_nickname', p.game_nickname
    ) order by p.role) filter (where p.user_id is not null), '[]'::jsonb)
  ) from public.game_sessions s
  left join public.session_players p on p.session_id = s.id
  where s.id = p_session_id group by s.id;
$$;

create function public.set_session_game_nickname(p_session_id uuid, p_nickname text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_name text := btrim(p_nickname);
begin
  if not public.is_session_member(p_session_id) then raise exception 'LOBBY_NOT_FOUND'; end if;
  if v_name is null or char_length(v_name) not between 2 and 20 then
    raise exception 'NICKNAME_INVALID';
  end if;
  update public.session_players set game_nickname = v_name
    where session_id = p_session_id and user_id = auth.uid()
      and game_nickname is distinct from v_name;
  return public.lobby_json(p_session_id);
end;
$$;
revoke all on function public.set_session_game_nickname(uuid, text) from public;
grant execute on function public.set_session_game_nickname(uuid, text) to authenticated;
