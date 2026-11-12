-- Qualify the room_members columns because room_id is also an OUT parameter
-- of this table-returning RPC.
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
 update public.room_members m set last_seen_at=now()
 where m.room_id=v_room_id and m.user_id=v_user and m.last_seen_at>=now()-interval '30 seconds';
 if not found then return; end if;
 update public.rooms r set status='playing',owner_id=v_owner,last_activity_at=now()
 where r.id=v_room_id and r.status<>'closed';
 if not found then return; end if;
 return query select r.id,r.code,r.name,r.is_private,r.max_players,r.status,r.game_key
 from public.rooms r where r.id=v_room_id;
end;
$function$;
revoke all on function public.get_my_active_haunted_room() from public,anon;
grant execute on function public.get_my_active_haunted_room() to authenticated;
