-- Lock room chat for every player while Haunted Camp is in night or morning.
-- The UI is only a convenience; this RPC guard is the authoritative enforcement.
create or replace function public.send_room_message(p_room_id uuid,p_body text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_count integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_body is null or char_length(btrim(p_body)) not between 1 and 500 then
    raise exception 'INVALID_MESSAGE';
  end if;
  if not private.is_room_member(p_room_id) then raise exception 'NOT_ROOM_MEMBER'; end if;

  if exists (
    select 1
    from public.haunted_games hg
    where hg.room_id = p_room_id
      and hg.status in ('night', 'morning')
  ) then
    raise exception 'NIGHT_CHAT_LOCKED';
  end if;

  if exists (
    select 1
    from public.haunted_games hg
    where hg.room_id = p_room_id
      and hg.status <> 'ended'
      and not exists (
        select 1
        from public.haunted_players hp
        where hp.game_id = hg.id
          and hp.user_id = v_user
          and hp.is_alive
          and hp.left_at is null
      )
  ) then
    raise exception 'SPECTATOR_READ_ONLY';
  end if;

  perform 1 from auth.users where id = v_user for update;
  select count(*) into v_count
  from public.chat_messages
  where room_id = p_room_id
    and user_id = v_user
    and created_at > now() - interval '1 minute';
  if v_count >= 15 then raise exception 'MESSAGE_RATE_LIMITED'; end if;

  insert into public.chat_messages(room_id, user_id, body)
  values (p_room_id, v_user, btrim(p_body))
  returning id into v_id;
  update public.rooms set last_activity_at = now() where id = p_room_id;
  return v_id;
end;
$$;

revoke all on function public.send_room_message(uuid,text) from public, anon;
grant execute on function public.send_room_message(uuid,text) to authenticated;
