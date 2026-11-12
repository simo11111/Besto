create or replace function public.heartbeat_room(p_room_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_owner uuid;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  select owner_id into v_owner from public.rooms where id=p_room_id and status<>'closed';
  if not found then return false; end if;

  -- A mobile player may have been pruned by an older build while the
  -- haunted match continued. Restore their room membership from the game roster.
  if not exists(select 1 from public.room_members where room_id=p_room_id and user_id=v_user)
     and exists(
       select 1 from public.haunted_players hp
       join public.haunted_games hg on hg.id=hp.game_id
       where hg.room_id=p_room_id and hg.status<>'ended' and hp.user_id=v_user
     ) then
    insert into public.room_members(room_id,user_id,role,last_seen_at)
    values(p_room_id,v_user,case when v_owner=v_user then 'owner' else 'player' end,now())
    on conflict(room_id,user_id) do update set last_seen_at=now();
  end if;

  update public.room_members set last_seen_at=now()
  where room_id=p_room_id and user_id=v_user;
  if not found then return false; end if;
  perform public.prune_stale_room_members(p_room_id);
  update public.rooms set last_activity_at=now() where id=p_room_id and status<>'closed';
  return true;
end;
$function$;