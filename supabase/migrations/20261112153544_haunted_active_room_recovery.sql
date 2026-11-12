-- Recover active Haunted Camp matches whose room membership was pruned by an older deployment.
-- No game history, accounts, or unrelated room data are deleted.
with active_rooms as (
 select distinct on (hg.room_id) hg.room_id,hg.created_by from public.haunted_games hg
 join auth.users u on u.id=hg.created_by where hg.status<>'ended' order by hg.room_id,hg.created_at desc
)
update public.rooms r set status='playing',owner_id=a.created_by,last_activity_at=now() from active_rooms a where r.id=a.room_id;
insert into public.room_members(room_id,user_id,role,last_seen_at)
select hg.room_id,hp.user_id,case when hp.user_id=hg.created_by then 'owner' else 'player' end,now()
from public.haunted_games hg join public.haunted_players hp on hp.game_id=hg.id and hp.is_bot=false
join auth.users u on u.id=hp.user_id where hg.status<>'ended'
on conflict(room_id,user_id) do update set role=excluded.role,last_seen_at=now();

create or replace function public.heartbeat_room(p_room_id uuid)
returns boolean language plpgsql security definer set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_owner uuid; v_game_id uuid; v_game_owner uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select hg.id,hg.created_by into v_game_id,v_game_owner from public.haunted_games hg
 join public.haunted_players hp on hp.game_id=hg.id
 where hg.room_id=p_room_id and hp.user_id=v_user and hp.is_bot=false and hg.status<>'ended'
 order by hg.created_at desc limit 1;
 if v_game_id is not null then
  update public.rooms set status='playing',owner_id=v_game_owner,last_activity_at=now() where id=p_room_id;
  if not found then return false; end if;
  insert into public.room_members(room_id,user_id,role,last_seen_at)
  select hg.room_id,hp.user_id,case when hp.user_id=hg.created_by then 'owner' else 'player' end,now()
  from public.haunted_games hg join public.haunted_players hp on hp.game_id=hg.id and hp.is_bot=false
  join auth.users u on u.id=hp.user_id where hg.id=v_game_id
  on conflict(room_id,user_id) do update set role=excluded.role,last_seen_at=now();
  update public.room_members set last_seen_at=now() where room_id=p_room_id and user_id=v_user;
  perform public.prune_stale_room_members(p_room_id);
  return true;
 end if;
 select owner_id into v_owner from public.rooms where id=p_room_id and status<>'closed';
 if not found then return false; end if;
 update public.room_members set last_seen_at=now() where room_id=p_room_id and user_id=v_user;
 if not found then return false; end if;
 perform public.prune_stale_room_members(p_room_id);
 update public.rooms set last_activity_at=now() where id=p_room_id and status<>'closed';
 return true;
end;
$function$;
revoke all on function public.heartbeat_room(uuid) from public,anon;
grant execute on function public.heartbeat_room(uuid) to authenticated;

create or replace function public.get_my_active_haunted_room()
returns table(room_id uuid,room_code text,room_name text,is_private boolean,max_players integer,status text,game_key text)
language plpgsql security definer set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_room_id uuid; v_owner uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select hg.room_id,hg.created_by into v_room_id,v_owner from public.haunted_games hg
 join public.haunted_players hp on hp.game_id=hg.id
 where hp.user_id=v_user and hp.is_bot=false and hg.status<>'ended'
 order by hg.created_at desc limit 1;
 if v_room_id is null then return; end if;
 update public.rooms set status='playing',owner_id=v_owner,last_activity_at=now() where id=v_room_id;
 if not found then return; end if;
 insert into public.room_members(room_id,user_id,role,last_seen_at)
 select hg.room_id,hp.user_id,case when hp.user_id=hg.created_by then 'owner' else 'player' end,now()
 from public.haunted_games hg join public.haunted_players hp on hp.game_id=hg.id and hp.is_bot=false
 join auth.users u on u.id=hp.user_id where hg.room_id=v_room_id and hg.status<>'ended'
 on conflict(room_id,user_id) do update set role=excluded.role,last_seen_at=now();
 update public.room_members set last_seen_at=now() where room_id=v_room_id and user_id=v_user;
 return query select r.id,r.code,r.name,r.is_private,r.max_players,r.status,r.game_key from public.rooms r where r.id=v_room_id;
end;
$function$;
revoke all on function public.get_my_active_haunted_room() from public,anon;
grant execute on function public.get_my_active_haunted_room() to authenticated;

create or replace function public.quick_match_room(p_game_key text default 'haunted_camp')
returns table(room_id uuid,room_code text,room_name text,max_players integer,game_key text)
language plpgsql security definer set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_room public.rooms%rowtype; v_capacity integer; v_min_players integer;
 v_game_key text:=coalesce(nullif(btrim(p_game_key),''),'haunted_camp');
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 if v_game_key not in ('wolf','who','forbidden','ten_seconds','impostor','haunted_camp') then raise exception 'INVALID_GAME'; end if;
 v_min_players:=case when v_game_key in ('wolf','impostor','haunted_camp') then 4 when v_game_key='forbidden' then 3 else 2 end;
 v_capacity:=case when v_game_key='haunted_camp' then 10 when v_game_key in ('wolf','impostor') then 8 when v_game_key='forbidden' then 6 else 8 end;
 perform public.prune_stale_room_members(null);
 select r.* into v_room from public.rooms r where r.status='open' and r.is_private=false and r.game_key=v_game_key
  and r.max_players>=v_min_players and (select count(*) from public.room_members m where m.room_id=r.id)<r.max_players
  and not exists(select 1 from public.game_sessions s where s.room_id=r.id and s.status='active')
  and not exists(select 1 from public.haunted_games hg where hg.room_id=r.id and hg.status<>'ended')
  and not exists(select 1 from public.room_members mine where mine.room_id=r.id and mine.user_id=v_user)
 order by r.last_activity_at asc for update skip locked limit 1;
 if found then
  insert into public.room_members(room_id,user_id,role,last_seen_at) values(v_room.id,v_user,'player',now());
  update public.rooms set last_activity_at=now() where id=v_room.id;
  return query select v_room.id,v_room.code,v_room.name,v_room.max_players,v_room.game_key; return;
 end if;
 perform 1 from auth.users where id=v_user for update;
 insert into public.rooms(code,owner_id,name,is_private,max_players,game_key)
 values(upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),v_user,
  case v_game_key when 'haunted_camp' then 'ليلة فالخيمة' when 'wolf' then 'غرفة شفتي الديب' when 'who' then 'غرفة شكون فينا' when 'forbidden' then 'غرفة ممنوع تقولها' when 'ten_seconds' then 'غرفة تحدي 10 ثواني' else 'غرفة شكون الكذاب' end,
  false,v_capacity,v_game_key) returning * into v_room;
 insert into public.room_members(room_id,user_id,role,last_seen_at) values(v_room.id,v_user,'owner',now());
 return query select v_room.id,v_room.code,v_room.name,v_room.max_players,v_room.game_key;
end;
$function$;
revoke all on function public.quick_match_room(text) from public,anon;
grant execute on function public.quick_match_room(text) to authenticated;
