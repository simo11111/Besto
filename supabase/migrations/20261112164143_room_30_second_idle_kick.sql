-- A room member must send their own heartbeat. An active haunted match must
-- never refresh every participant, otherwise an offline player is kept forever.
create or replace function public.prune_stale_room_members(p_room_id uuid default null)
returns integer language plpgsql security definer set search_path to ''
as $function$
declare v_removed integer:=0; v_room record; v_next uuid; v_count integer;
begin
 for v_room in select r.id,r.owner_id from public.rooms r
  where r.status<>'closed' and (p_room_id is null or r.id=p_room_id) for update
 loop
  delete from public.room_members m where m.room_id=v_room.id and m.last_seen_at<now()-interval '30 seconds';
  get diagnostics v_count=row_count; v_removed:=v_removed+v_count;
  if not exists(select 1 from public.room_members where room_id=v_room.id) then
   update public.rooms set status='closed',last_activity_at=now() where id=v_room.id;
  else
   if not exists(select 1 from public.room_members where room_id=v_room.id and user_id=v_room.owner_id) then
    select user_id into v_next from public.room_members where room_id=v_room.id order by last_seen_at desc,joined_at asc limit 1;
    update public.rooms set owner_id=v_next,last_activity_at=now() where id=v_room.id;
    update public.room_members set role='player' where room_id=v_room.id;
    update public.room_members set role='owner' where room_id=v_room.id and user_id=v_next;
   else update public.rooms set last_activity_at=now() where id=v_room.id;
   end if;
  end if;
 end loop;
 return v_removed;
end;
$function$;

create or replace function public.heartbeat_room(p_room_id uuid)
returns boolean language plpgsql security definer set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_owner uuid; v_game_id uuid; v_game_owner uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select hg.id,hg.created_by into v_game_id,v_game_owner
 from public.haunted_games hg join public.haunted_players hp on hp.game_id=hg.id
 where hg.room_id=p_room_id and hp.user_id=v_user and hp.is_bot=false and hg.status<>'ended'
 order by hg.created_at desc limit 1;
 perform public.prune_stale_room_members(p_room_id);
 select owner_id into v_owner from public.rooms where id=p_room_id and status<>'closed';
 if not found then return false; end if;
 update public.room_members set last_seen_at=now()
 where room_id=p_room_id and user_id=v_user and last_seen_at>=now()-interval '30 seconds';
 if not found then return false; end if;
 if v_game_id is not null then
  update public.rooms set status='playing',owner_id=v_game_owner,last_activity_at=now() where id=p_room_id and status<>'closed';
 else
  update public.rooms set last_activity_at=now() where id=p_room_id and status<>'closed';
 end if;
 perform public.prune_stale_room_members(p_room_id);
 return true;
end;
$function$;

create or replace function public.get_my_active_haunted_room()
returns table(room_id uuid,room_code text,room_name text,is_private boolean,max_players integer,status text,game_key text)
language plpgsql security definer set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_game_id uuid; v_room_id uuid; v_owner uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select hg.id,hg.room_id,hg.created_by into v_game_id,v_room_id,v_owner
 from public.haunted_games hg join public.haunted_players hp on hp.game_id=hg.id
 where hp.user_id=v_user and hp.is_bot=false and hg.status<>'ended'
 order by hg.created_at desc limit 1;
 if v_room_id is null then return; end if;
 perform public.prune_stale_room_members(v_room_id);
 update public.room_members set last_seen_at=now()
 where room_id=v_room_id and user_id=v_user and last_seen_at>=now()-interval '30 seconds';
 if not found then return; end if;
 update public.rooms set status='playing',owner_id=v_owner,last_activity_at=now()
 where id=v_room_id and status<>'closed';
 if not found then return; end if;
 return query select r.id,r.code,r.name,r.is_private,r.max_players,r.status,r.game_key
 from public.rooms r where r.id=v_room_id;
end;
$function$;

revoke all on function public.heartbeat_room(uuid) from public,anon;
grant execute on function public.heartbeat_room(uuid) to authenticated;
revoke all on function public.get_my_active_haunted_room() from public,anon;
grant execute on function public.get_my_active_haunted_room() to authenticated;
revoke all on function public.prune_stale_room_members(uuid) from public,anon;
grant execute on function public.prune_stale_room_members(uuid) to authenticated;
