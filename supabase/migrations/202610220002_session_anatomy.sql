-- Anatomies are supplied by each participant during preparation, then frozen.
alter table public.session_players add column session_anatomy text
  check (session_anatomy in ('PENIS','VULVE'));

create function public.freeze_session_anatomy() returns trigger
language plpgsql set search_path=public as $$
begin
  if new.session_anatomy is distinct from old.session_anatomy and (
    exists(select 1 from public.network_game_states where session_id=old.session_id and setup_status='ACCEPTED')
    or exists(select 1 from public.network_rounds where session_id=old.session_id)
  ) then raise exception 'ROUND_SESSION_SETUP_IMMUTABLE'; end if;
  return new;
end; $$;
create trigger session_anatomy_frozen before update of session_anatomy on public.session_players
for each row execute function public.freeze_session_anatomy();

create or replace function public.v4_session_setup_json(p_session_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('mode',s.v4_session_mode,'style',g.deck_style,
    'status',coalesce(g.setup_status,'DRAFT'),'revision',coalesce(g.setup_revision,0),
    'players',coalesce((select jsonb_agg(jsonb_build_object(
      'player_id',p.user_id,'anatomy',p.session_anatomy,
      'clothing_count',coalesce(p.v4_clothing_count,0),
      'environment_ready',p.v4_clothing_count is not null,
      'inventory_ready',p.v4_available_accessories is not null,
      'available_accessories',coalesce(p.v4_available_accessories,'[]'::jsonb),
      'accessories',coalesce(p.v4_accessories,'[]'::jsonb)) order by p.role)
      from public.session_players p where p.session_id=s.id),'[]'::jsonb))
  from public.game_sessions s left join public.network_game_states g on g.session_id=s.id
  where s.id=p_session_id;
$$;

create function public.register_v4_setup_profile(p_session_id uuid,p_accessories jsonb,p_anatomy text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  if p_anatomy is null or p_anatomy not in ('PENIS','VULVE') then raise exception 'ROUND_INVALID_ARGUMENT'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text,0));
  -- Only auth.uid(): never accept another player's structural profile in p_players.
  update public.session_players set session_anatomy=p_anatomy
    where session_id=p_session_id and user_id=auth.uid();
  perform public.register_v4_setup_accessories(p_session_id,p_accessories);
  return public.v4_session_setup_json(p_session_id);
end; $$;
revoke all on function public.register_v4_setup_profile(uuid,jsonb,text) from public,anon;
grant execute on function public.register_v4_setup_profile(uuid,jsonb,text) to authenticated;

create function public.require_setup_anatomies() returns trigger
language plpgsql set search_path=public as $$
begin
  if new.setup_status='ACCEPTED' and old.setup_status is distinct from 'ACCEPTED'
    and (select count(*) from public.session_players where session_id=new.session_id and session_anatomy is not null)<>2
    then raise exception 'ROUND_SETUP_NOT_READY'; end if;
  return new;
end; $$;
create trigger setup_requires_anatomies before update of setup_status on public.network_game_states
for each row execute function public.require_setup_anatomies();

alter function public.open_network_game_round(uuid,uuid,text) rename to open_anatomy_prepared_network_game_round;
revoke all on function public.open_anatomy_prepared_network_game_round(uuid,uuid,text) from public,anon,authenticated;
create function public.open_network_game_round(p_session_id uuid,p_player_id uuid,p_command_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or auth.uid()<>p_player_id or not public.is_session_member(p_session_id) then raise exception 'ROUND_NOT_MEMBER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_session_id::text,0));
  if (select count(*) from public.session_players where session_id=p_session_id and session_anatomy is not null)<>2
    then raise exception 'ROUND_SETUP_NOT_READY'; end if;
  return public.open_anatomy_prepared_network_game_round(p_session_id,p_player_id,p_command_id);
end; $$;
revoke all on function public.open_network_game_round(uuid,uuid,text) from public,anon;
grant execute on function public.open_network_game_round(uuid,uuid,text) to authenticated;
