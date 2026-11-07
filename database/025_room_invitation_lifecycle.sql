-- Invitation lifecycle: issue room invites only from a room member to an accepted friend,
-- then allow the recipient to accept (including private rooms) or decline for 15 minutes.

create or replace function public.send_room_invite(p_room_id uuid, p_friend_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_notification uuid;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_friend_id is null or p_friend_id = v_user then raise exception 'INVALID_RECIPIENT'; end if;

  select * into v_room
  from public.rooms
  where id = p_room_id and status = 'open'
  for update;

  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if not exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = v_user
  ) then raise exception 'NOT_ROOM_MEMBER'; end if;
  if exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = p_friend_id
  ) then raise exception 'ALREADY_ROOM_MEMBER'; end if;
  if not exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester_id = v_user and addressee_id = p_friend_id)
        or (requester_id = p_friend_id and addressee_id = v_user))
  ) then raise exception 'NOT_FRIENDS'; end if;

  insert into public.notifications(user_id, actor_id, kind, title, body, payload)
  values (
    p_friend_id,
    v_user,
    'room_invite',
    'دعوة للعب',
    (select coalesce(username, 'صديقك') from public.profiles where id = v_user)
      || ' دعاك لغرفة ' || v_room.name,
    jsonb_build_object(
      'room_id', v_room.id,
      'room_code', v_room.code,
      'game_key', v_room.game_key,
      'status', 'pending'
    )
  )
  returning id into v_notification;

  return v_notification;
end;
$function$;

create or replace function public.respond_room_invite(p_notification_id uuid, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_notice public.notifications%rowtype;
  v_room public.rooms%rowtype;
  v_count integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_notification_id is null or p_accept is null then raise exception 'INVALID_INVITATION'; end if;

  select * into v_notice
  from public.notifications
  where id = p_notification_id and user_id = v_user and kind = 'room_invite'
  for update;

  if not found then raise exception 'INVITATION_NOT_FOUND'; end if;

  if v_notice.read_at is not null
     or coalesce(v_notice.payload->>'status', 'pending') <> 'pending' then
    return jsonb_build_object('status', coalesce(v_notice.payload->>'status', 'handled'));
  end if;

  if v_notice.created_at < now() - interval '15 minutes' then
    update public.notifications
    set read_at = now(), payload = payload || jsonb_build_object('status', 'expired')
    where id = p_notification_id;
    return jsonb_build_object('status', 'expired');
  end if;

  if not p_accept then
    update public.notifications
    set read_at = now(), payload = payload || jsonb_build_object('status', 'declined')
    where id = p_notification_id;
    return jsonb_build_object('status', 'declined');
  end if;

  if coalesce(v_notice.payload->>'room_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    update public.notifications
    set read_at = now(), payload = payload || jsonb_build_object('status', 'invalid')
    where id = p_notification_id;
    return jsonb_build_object('status', 'invalid');
  end if;

  perform public.prune_stale_room_members(null);

  select * into v_room
  from public.rooms
  where id = (v_notice.payload->>'room_id')::uuid and status = 'open'
  for update;

  if not found or v_room.code <> coalesce(v_notice.payload->>'room_code', '') then
    update public.notifications
    set read_at = now(), payload = payload || jsonb_build_object('status', 'unavailable')
    where id = p_notification_id;
    return jsonb_build_object('status', 'unavailable');
  end if;

  if not exists (
    select 1 from public.room_members
    where room_id = v_room.id and user_id = v_notice.actor_id
  ) then
    update public.notifications
    set read_at = now(), payload = payload || jsonb_build_object('status', 'unavailable')
    where id = p_notification_id;
    return jsonb_build_object('status', 'unavailable');
  end if;

  if exists (
    select 1 from public.room_members
    where room_id = v_room.id and user_id = v_user
  ) then
    update public.room_members set last_seen_at = now()
    where room_id = v_room.id and user_id = v_user;
  else
    select count(*) into v_count
    from public.room_members where room_id = v_room.id;
    if v_count >= v_room.max_players then
      return jsonb_build_object('status', 'full');
    end if;
    insert into public.room_members(room_id, user_id, role, last_seen_at)
    values (v_room.id, v_user, 'player', now());
  end if;

  update public.rooms set last_activity_at = now() where id = v_room.id;
  update public.notifications
  set read_at = now(), payload = payload || jsonb_build_object('status', 'accepted')
  where id = p_notification_id;

  return jsonb_build_object(
    'status', 'accepted',
    'room_id', v_room.id,
    'room_name', v_room.name,
    'room_code', v_room.code,
    'game_key', v_room.game_key,
    'max_players', v_room.max_players
  );
end;
$function$;

revoke all on function public.send_room_invite(uuid, uuid) from public, anon;
revoke all on function public.respond_room_invite(uuid, boolean) from public, anon;
grant execute on function public.send_room_invite(uuid, uuid) to authenticated;
grant execute on function public.respond_room_invite(uuid, boolean) to authenticated;
