-- Fix the table-returning resume RPC: its output column room_id shadows
-- the ON CONFLICT target names inside PL/pgSQL.
create or replace function public.get_my_active_haunted_room()
returns table(room_id uuid,room_code text,room_name text,is_private boolean,max_players integer,status text,game_key text)
language plpgsql security definer set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_room_id uuid; v_owner uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select hg.room_id,hg.created_by into v_room_id,v_owner
 from public.haunted_games hg join public.haunted_players hp on hp.game_id=hg.id
 where hp.user_id=v_user and hp.is_bot=false and hg.status<>'ended'
 order by hg.created_at desc limit 1;
 if v_room_id is null then return; end if;
 update public.rooms set status='playing',owner_id=v_owner,last_activity_at=now() where id=v_room_id;
 if not found then return; end if;
 insert into public.room_members(room_id,user_id,role,last_seen_at)
 select hg.room_id,hp.user_id,case when hp.user_id=hg.created_by then 'owner' else 'player' end,now()
 from public.haunted_games hg join public.haunted_players hp on hp.game_id=hg.id and hp.is_bot=false
 join auth.users u on u.id=hp.user_id
 where hg.room_id=v_room_id and hg.status<>'ended'
 on conflict on constraint room_members_pkey do update set role=excluded.role,last_seen_at=now();
 update public.room_members set last_seen_at=now()
 where public.room_members.room_id=v_room_id and public.room_members.user_id=v_user;
 return query select r.id,r.code,r.name,r.is_private,r.max_players,r.status,r.game_key
 from public.rooms r where r.id=v_room_id;
end;
$function$;
revoke all on function public.get_my_active_haunted_room() from public,anon;
grant execute on function public.get_my_active_haunted_room() to authenticated;
