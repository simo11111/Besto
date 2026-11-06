-- MIMOX room modes: support duel lobbies and return full room metadata on join.
create or replace function public.create_room(
  p_name text,
  p_private boolean default false,
  p_max_players integer default 10,
  p_game_key text default null,
  p_password text default null
)
returns table(room_id uuid, room_code text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_code text;
  v_room uuid;
  v_attempt integer;
  v_min_players integer;
  v_max_players integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 40 then raise exception 'INVALID_ROOM_NAME'; end if;
  if p_game_key is null or p_game_key not in ('wolf','who','forbidden','ten_seconds','impostor','connect4','dama') then
    raise exception 'INVALID_GAME';
  end if;
  v_min_players := case when p_game_key in ('wolf','impostor') then 4 when p_game_key = 'forbidden' then 3 else 2 end;
  v_max_players := case
    when p_game_key in ('connect4','dama') then 2
    when p_game_key in ('wolf','impostor','forbidden','ten_seconds') then 12
    else 16
  end;
  if p_max_players is null or p_max_players < v_min_players or p_max_players > v_max_players then raise exception 'INVALID_CAPACITY'; end if;
  if p_game_key in ('connect4','dama') and p_max_players <> 2 then raise exception 'DUEL_REQUIRES_TWO_SEATS'; end if;
  if p_private and (p_password is null or char_length(p_password)<4 or char_length(p_password)>32) then raise exception 'ROOM_PASSWORD_REQUIRED'; end if;
  perform 1 from auth.users where id=v_user for update;
  if (select count(*) from public.rooms where owner_id=v_user and created_at>now()-interval '1 hour')>=5 then raise exception 'ROOM_CREATE_RATE_LIMITED'; end if;
  for v_attempt in 1..5 loop
    v_code:=upper(substr(replace(extensions.gen_random_uuid()::text,'-',''),1,12));
    begin
      insert into public.rooms(code,owner_id,name,is_private,max_players,game_key,password_hash)
      values(v_code,v_user,btrim(p_name),coalesce(p_private,false),p_max_players,p_game_key,
        case when p_private then extensions.crypt(p_password,extensions.gen_salt('bf')) else null end)
      returning id into v_room;
      exit;
    exception when unique_violation then if v_attempt=5 then raise; end if;
    end;
  end loop;
  insert into public.room_members(room_id,user_id,role) values(v_room,v_user,'owner');
  return query select v_room,v_code;
end;
$function$;

drop function if exists public.join_room(text,text);
create function public.join_room(p_code text,p_password text default null)
returns table(room_id uuid,room_name text,room_code text,is_private boolean,max_players integer,game_key text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid:=auth.uid();
  v_room public.rooms%rowtype;
  v_count integer;
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
  select count(*) into v_count from public.room_members m where m.room_id=v_room.id;
  if v_count>=v_room.max_players then raise exception 'ROOM_FULL'; end if;
  insert into public.room_members(room_id,user_id,role,last_seen_at) values(v_room.id,v_user,'player',now());
  update public.rooms set last_activity_at=now() where id=v_room.id;
  return query select v_room.id,v_room.name,v_room.code,v_room.is_private,v_room.max_players,v_room.game_key;
end;
$function$;

revoke all on function public.create_room(text,boolean,integer,text,text) from public,anon;
grant execute on function public.create_room(text,boolean,integer,text,text) to authenticated;
revoke all on function public.join_room(text,text) from public,anon;
grant execute on function public.join_room(text,text) to authenticated;
