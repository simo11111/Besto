-- MIMOX Phase 1 follow-up: version the social and matchmaking RPCs used by the frontend.
-- These functions already exist in the connected database; this migration makes fresh installs reproducible.
-- Keep all privileged operations server-side and pin the function search path.

create or replace function public.send_friend_request(p_username text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_target uuid;
  v_id uuid;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_username is null or char_length(btrim(p_username)) not between 3 and 20 then
    raise exception 'INVALID_USERNAME';
  end if;

  select id into v_target
  from public.profiles
  where lower(username) = lower(btrim(p_username))
    and id <> v_user;

  if v_target is null then raise exception 'PLAYER_NOT_FOUND'; end if;

  if exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester_id = v_user and addressee_id = v_target)
        or (requester_id = v_target and addressee_id = v_user))
  ) then
    raise exception 'ALREADY_FRIENDS';
  end if;

  select id into v_id
  from public.friendships
  where requester_id = v_target
    and addressee_id = v_user
    and status = 'pending';

  if v_id is not null then
    update public.friendships
    set status = 'accepted', updated_at = now()
    where id = v_id;
    return v_id;
  end if;

  insert into public.friendships(requester_id, addressee_id)
  values (v_user, v_target)
  on conflict (requester_id, addressee_id)
  do update set status = 'pending', updated_at = now()
  returning id into v_id;

  return v_id;
end;
$function$;

create or replace function public.accept_friend_request(p_request_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  update public.friendships
  set status = 'accepted', updated_at = now()
  where id = p_request_id
    and addressee_id = auth.uid()
    and status = 'pending';

  return found;
end;
$function$;

create or replace function public.remove_friend(p_friend_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  delete from public.friendships
  where id = p_friend_id
    and (requester_id = auth.uid() or addressee_id = auth.uid());

  return found;
end;
$function$;

create or replace function public.quick_match_room(p_game_key text)
returns table (
  room_id uuid,
  room_code text,
  room_name text,
  max_players integer,
  game_key text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_capacity integer;
  v_min_players integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_game_key is null or p_game_key not in ('wolf', 'who', 'forbidden', 'ten_seconds', 'impostor') then
    raise exception 'INVALID_GAME';
  end if;

  v_min_players := case
    when p_game_key in ('wolf', 'impostor') then 4
    when p_game_key = 'forbidden' then 3
    else 2
  end;
  v_capacity := case
    when p_game_key in ('wolf', 'impostor') then 8
    when p_game_key = 'forbidden' then 6
    else 8
  end;

  perform public.prune_stale_room_members(null);

  select r.* into v_room
  from public.rooms r
  where r.status = 'open'
    and r.is_private = false
    and r.game_key = p_game_key
    and r.max_players >= v_min_players
    and (select count(*) from public.room_members m where m.room_id = r.id) < r.max_players
    and not exists (
      select 1 from public.game_sessions s
      where s.room_id = r.id and s.status = 'active'
    )
    and not exists (
      select 1 from public.room_members mine
      where mine.room_id = r.id and mine.user_id = v_user
    )
  order by r.last_activity_at asc
  for update skip locked
  limit 1;

  if found then
    insert into public.room_members(room_id, user_id, role)
    values (v_room.id, v_user, 'player');

    update public.rooms set last_activity_at = now() where id = v_room.id;

    return query
    select v_room.id, v_room.code, v_room.name, v_room.max_players, v_room.game_key;
    return;
  end if;

  perform 1 from auth.users where id = v_user for update;

  insert into public.rooms(code, owner_id, name, is_private, max_players, game_key)
  values (
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
    v_user,
    case p_game_key
      when 'wolf' then 'غرفة شفتي الديب'
      when 'who' then 'غرفة شكون فينا'
      when 'forbidden' then 'غرفة ممنوع تقولها'
      when 'ten_seconds' then 'غرفة تحدي 10 ثواني'
      else 'غرفة شكون الكذاب'
    end,
    false,
    v_capacity,
    p_game_key
  )
  returning * into v_room;

  insert into public.room_members(room_id, user_id, role)
  values (v_room.id, v_user, 'owner');

  return query
  select v_room.id, v_room.code, v_room.name, v_room.max_players, v_room.game_key;
end;
$function$;

revoke all on function public.send_friend_request(text) from public, anon;
revoke all on function public.accept_friend_request(uuid) from public, anon;
revoke all on function public.remove_friend(uuid) from public, anon;
revoke all on function public.quick_match_room(text) from public, anon;

grant execute on function public.send_friend_request(text) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
grant execute on function public.quick_match_room(text) to authenticated;
