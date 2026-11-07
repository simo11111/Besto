-- MIMOX room safety: block new players from active matches and require two-seat duel rooms.
create or replace function public.join_room(p_code text,p_password text default null)
returns table(room_id uuid,room_name text,room_code text,is_private boolean,max_players integer,game_key text)
language plpgsql security definer set search_path = ''
as $function$
declare v_user uuid:=auth.uid(); v_room public.rooms%rowtype; v_count integer;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_code is null or p_code !~ '^[A-Za-z0-9]{6,12}$' then raise exception 'INVALID_ROOM_CODE'; end if;
 perform public.prune_stale_room_members(null);
 perform 1 from auth.users where id=v_user for update;
 delete from public.room_join_attempts where user_id=v_user and attempted_at<now()-interval '1 day';
 insert into public.room_join_attempts(user_id) values(v_user);
 select count(*) into v_count from public.room_join_attempts where user_id=v_user and attempted_at>now()-interval '1 minute';
 if v_count>10 then raise exception 'JOIN_RATE_LIMITED'; end if;
 select * into v_room from public.rooms r where r.code=upper(p_code) and r.status='open' for update;
 if not found then raise exception 'ROOM_NOT_FOUND'; end if;
 if v_room.is_private and (v_room.password_hash is null or p_password is null or extensions.crypt(p_password,v_room.password_hash)<>v_room.password_hash) then raise exception 'INVALID_ROOM_PASSWORD'; end if;
 if exists(select 1 from public.room_members m where m.room_id=v_room.id and m.user_id=v_user) then
  update public.room_members set last_seen_at=now() where room_id=v_room.id and user_id=v_user;
  return query select v_room.id,v_room.name,v_room.code,v_room.is_private,v_room.max_players,v_room.game_key;
  return;
 end if;
 if exists(select 1 from public.game_sessions s where s.room_id=v_room.id and s.status='active') then raise exception 'ROOM_GAME_IN_PROGRESS'; end if;
 select count(*) into v_count from public.room_members m where m.room_id=v_room.id;
 if v_count>=v_room.max_players then raise exception 'ROOM_FULL'; end if;
 insert into public.room_members(room_id,user_id,role,last_seen_at) values(v_room.id,v_user,'player',now());
 update public.rooms set last_activity_at=now() where id=v_room.id;
 return query select v_room.id,v_room.name,v_room.code,v_room.is_private,v_room.max_players,v_room.game_key;
end;
$function$;
do $migration$
declare
 v_definition text;
 v_original text := 'if not private.is_room_member(p_room_id) then raise exception ''NOT_ROOM_MEMBER''; end if;';
 v_corrected text := 'if not private.is_room_member(p_room_id) then raise exception ''NOT_ROOM_MEMBER''; end if; if v_room.max_players <> 2 then raise exception ''DUEL_REQUIRES_TWO_SEATS''; end if;';
begin
 v_definition:=pg_get_functiondef('public.start_duel_game(uuid,text)'::regprocedure);
 if position(v_original in v_definition)=0 then raise exception 'Expected start_duel_game membership guard was not found'; end if;
 execute replace(v_definition,v_original,v_corrected);
end;
$migration$;
