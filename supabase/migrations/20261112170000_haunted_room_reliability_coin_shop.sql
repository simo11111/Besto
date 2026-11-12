create or replace function public.quick_match_room(p_game_key text)
returns table(room_id uuid, room_code text, room_name text, max_players integer, game_key text)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_capacity integer;
  v_min_players integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_game_key is null or p_game_key not in ('wolf','who','forbidden','ten_seconds','impostor','haunted_camp') then
    raise exception 'INVALID_GAME';
  end if;

  v_min_players := case
    when p_game_key in ('wolf','impostor','haunted_camp') then 4
    when p_game_key='forbidden' then 3
    else 2
  end;
  v_capacity := case
    when p_game_key='haunted_camp' then 10
    when p_game_key in ('wolf','impostor') then 8
    when p_game_key='forbidden' then 6
    else 8
  end;

  perform public.prune_stale_room_members(null);

  select r.* into v_room
  from public.rooms r
  where r.status='open'
    and r.is_private=false
    and r.game_key=p_game_key
    and r.max_players>=v_min_players
    and (select count(*) from public.room_members m where m.room_id=r.id)<r.max_players
    and not exists(select 1 from public.game_sessions s where s.room_id=r.id and s.status='active')
    and not exists(select 1 from public.haunted_games hg where hg.room_id=r.id and hg.status<>'ended')
    and not exists(select 1 from public.room_members mine where mine.room_id=r.id and mine.user_id=v_user)
  order by r.last_activity_at asc
  for update skip locked
  limit 1;

  if found then
    insert into public.room_members(room_id,user_id,role,last_seen_at)
    values(v_room.id,v_user,'player',now());
    update public.rooms set last_activity_at=now() where id=v_room.id;
    return query select v_room.id,v_room.code,v_room.name,v_room.max_players,v_room.game_key;
    return;
  end if;

  perform 1 from auth.users where id=v_user for update;
  insert into public.rooms(code,owner_id,name,is_private,max_players,game_key)
  values(
    upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),
    v_user,
    case p_game_key when 'haunted_camp' then 'ليلة فالخيمة' when 'wolf' then 'غرفة شفتي الديب' when 'who' then 'غرفة شكون فينا' when 'forbidden' then 'غرفة ممنوع تقولها' when 'ten_seconds' then 'غرفة تحدي 10 ثواني' else 'غرفة شكون الكذاب' end,
    false,v_capacity,p_game_key
  ) returning * into v_room;

  insert into public.room_members(room_id,user_id,role,last_seen_at)
  values(v_room.id,v_user,'owner',now());

  return query select v_room.id,v_room.code,v_room.name,v_room.max_players,v_room.game_key;
end;
$function$;

create or replace function public.heartbeat_room(p_room_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  perform 1 from public.rooms where id=p_room_id and status<>'closed';
  if not found then return false; end if;

  -- Refresh this player before pruning stale members; otherwise a returning
  -- mobile client can prune its own membership after Android backgrounding.
  update public.room_members set last_seen_at=now()
  where room_id=p_room_id and user_id=v_user;
  if not found then return false; end if;

  perform public.prune_stale_room_members(p_room_id);
  update public.rooms set last_activity_at=now() where id=p_room_id and status<>'closed';
  return true;
end;
$function$;

create or replace function public.prune_stale_room_members(p_room_id uuid default null)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare v_removed integer:=0; v_room record; v_next uuid; v_count integer;
begin
  for v_room in
    select r.id,r.owner_id from public.rooms r
    where r.status<>'closed' and (p_room_id is null or r.id=p_room_id)
    for update
  loop
    -- Keep the room roster intact while its independent haunted-game state is active.
    delete from public.room_members m
    where m.room_id=v_room.id
      and m.last_seen_at < now()-interval '90 seconds'
      and not exists(select 1 from public.haunted_games hg where hg.room_id=v_room.id and hg.status<>'ended');
    get diagnostics v_count=row_count;
    v_removed:=v_removed+v_count;
    if not exists(select 1 from public.room_members where room_id=v_room.id) then
      update public.rooms set status='closed',last_activity_at=now() where id=v_room.id;
    else
      if not exists(select 1 from public.room_members where room_id=v_room.id and user_id=v_room.owner_id) then
        select user_id into v_next from public.room_members where room_id=v_room.id order by last_seen_at desc,joined_at asc limit 1;
        update public.rooms set owner_id=v_next,last_activity_at=now() where id=v_room.id;
        update public.room_members set role='player' where room_id=v_room.id;
        update public.room_members set role='owner' where room_id=v_room.id and user_id=v_next;
      end if;
      update public.rooms set last_activity_at=now() where id=v_room.id;
    end if;
  end loop;
  return v_removed;
end;
$function$;

update public.cosmetic_catalog set currency='coins',
  price=case id
    when 'frame_crown' then 1800
    when 'title_veteran' then 1900
    when 'frame_royal' then 2100
    when 'title_diamond' then 2200
    else price
  end
where currency='gems';

create or replace function public.purchase_cosmetic(p_cosmetic_id text)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_item public.cosmetic_catalog%rowtype;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_item from public.cosmetic_catalog where id=p_cosmetic_id;
  if not found then raise exception 'ITEM_NOT_FOUND'; end if;
  perform 1 from auth.users where id=v_user for update;
  if exists(select 1 from public.player_inventory where user_id=v_user and cosmetic_id=p_cosmetic_id) then raise exception 'ALREADY_OWNED'; end if;
  update public.profiles set coins=coins-v_item.price
  where id=v_user and coins>=v_item.price;
  if not found then raise exception 'NOT_ENOUGH_COINS'; end if;
  insert into public.player_inventory(user_id,cosmetic_id) values(v_user,p_cosmetic_id);
  return true;
end;
$function$;

create or replace function public.claim_daily_reward()
returns table(coins_awarded integer,xp_awarded integer,streak integer)
language plpgsql
security definer
set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_today date:=(now() at time zone 'utc')::date;
  v_streak integer:=1; v_coins integer; v_xp integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  perform 1 from auth.users where id=v_user for update;
  if exists(select 1 from public.daily_reward_claims where user_id=v_user and claim_date=v_today) then raise exception 'ALREADY_CLAIMED'; end if;
  select case when last_daily_claim=v_today-1 then streak_days+1 else 1 end
  into v_streak from public.profiles where id=v_user;
  v_streak:=coalesce(v_streak,1);
  v_coins:=50+least(v_streak,7)*10;
  v_xp:=25+least(v_streak,7)*5;
  insert into public.daily_reward_claims(user_id,claim_date,coins,xp) values(v_user,v_today,v_coins,v_xp);
  update public.profiles set coins=coins+v_coins,xp=xp+v_xp,
    level=1+floor(sqrt((xp+v_xp)::numeric/100))::int,
    streak_days=v_streak,last_daily_claim=v_today,updated_at=now()
  where id=v_user;
  return query select v_coins,v_xp,v_streak;
end;
$function$;
