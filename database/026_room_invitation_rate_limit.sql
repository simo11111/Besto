-- Prevent notification spam and collapse duplicate pending invitations.
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
  v_recent_count integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_friend_id is null or p_friend_id = v_user then raise exception 'INVALID_RECIPIENT'; end if;

  select * into v_room
  from public.rooms
  where id = p_room_id and status = 'open'
  for update;

  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if not exists (select 1 from public.room_members where room_id = p_room_id and user_id = v_user) then
    raise exception 'NOT_ROOM_MEMBER';
  end if;
  if exists (select 1 from public.room_members where room_id = p_room_id and user_id = p_friend_id) then
    raise exception 'ALREADY_ROOM_MEMBER';
  end if;
  if not exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester_id = v_user and addressee_id = p_friend_id)
        or (requester_id = p_friend_id and addressee_id = v_user))
  ) then
    raise exception 'NOT_FRIENDS';
  end if;

  select id into v_notification
  from public.notifications
  where user_id = p_friend_id
    and actor_id = v_user
    and kind = 'room_invite'
    and payload->>'room_id' = p_room_id::text
    and coalesce(payload->>'status', 'pending') = 'pending'
    and read_at is null
    and created_at > now() - interval '15 minutes'
  order by created_at desc
  limit 1;

  if v_notification is not null then return v_notification; end if;

  select count(*) into v_recent_count
  from public.notifications
  where actor_id = v_user
    and user_id = p_friend_id
    and kind = 'room_invite'
    and created_at > now() - interval '1 hour';

  if v_recent_count >= 5 then raise exception 'INVITE_RATE_LIMITED'; end if;

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

revoke all on function public.send_room_invite(uuid, uuid) from public, anon;
grant execute on function public.send_room_invite(uuid, uuid) to authenticated;
