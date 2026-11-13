create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

create or replace function public.prune_stale_room_members(p_room_id uuid default null::uuid)
returns integer language plpgsql security definer set search_path to ''
as $function$
declare v_removed integer := 0; v_room record; v_next uuid; v_count integer;
begin
  for v_room in
    select r.id,r.owner_id from public.rooms r
    where r.status <> 'closed' and (p_room_id is null or r.id=p_room_id)
    for update
  loop
    with stale as (
      delete from public.room_members m
      where m.room_id=v_room.id and m.last_seen_at < now()-interval '60 seconds'
      returning m.room_id,m.user_id
    ), marked as (
      update public.haunted_players hp
      set left_at=coalesce(hp.left_at,now()),is_alive=false
      from stale s join public.haunted_games hg on hg.room_id=s.room_id
      where hp.game_id=hg.id and hp.user_id=s.user_id and hp.is_bot=false
        and hp.left_at is null and hg.status<>'ended'
      returning hp.user_id
    )
    select count(*) into v_count from stale;
    v_removed:=v_removed+v_count;

    if not exists(select 1 from public.room_members where room_id=v_room.id) then
      update public.rooms set status='closed',last_activity_at=now() where id=v_room.id;
    elsif not exists(select 1 from public.room_members where room_id=v_room.id and user_id=v_room.owner_id) then
      select user_id into v_next from public.room_members where room_id=v_room.id
      order by last_seen_at desc,joined_at asc limit 1;
      update public.rooms set owner_id=v_next,last_activity_at=now() where id=v_room.id;
      update public.room_members set role='player' where room_id=v_room.id;
      update public.room_members set role='owner' where room_id=v_room.id and user_id=v_next;
    else
      update public.rooms set last_activity_at=now() where id=v_room.id;
    end if;
  end loop;
  return v_removed;
end;
$function$;

create or replace function private.close_empty_room_after_member_delete()
returns trigger language plpgsql security definer set search_path to ''
as $function$
declare v_game record;
begin
  update public.haunted_players hp
  set left_at=coalesce(hp.left_at,now()),is_alive=false
  from public.haunted_games hg
  where hp.game_id=hg.id and hg.room_id=old.room_id and hp.user_id=old.user_id
    and hp.is_bot=false and hp.left_at is null and hg.status<>'ended';

  if not exists(select 1 from public.room_members rm where rm.room_id=old.room_id) then
    update public.rooms set status='closed',last_activity_at=now()
    where id=old.room_id and status<>'closed';
    for v_game in
      update public.haunted_games
      set status='ended',winner=null,voting_open=false,
          phase_deadline_at=now(),bot_next_action_at=null
      where room_id=old.room_id and status<>'ended'
      returning id,round
    loop
      insert into public.haunted_events(game_id,round,event_type,payload)
      values(v_game.id,v_game.round,'game_abandoned',
        jsonb_build_object('message','تسدات اللعبة حيث خرجو جميع اللاعبين من الغرفة.','system',true));
    end loop;
  end if;
  return old;
end;
$function$;

drop trigger if exists room_members_close_empty_room on public.room_members;
create trigger room_members_close_empty_room after delete on public.room_members
for each row execute function private.close_empty_room_after_member_delete();

create or replace function public.heartbeat_room(p_room_id uuid)
returns boolean language plpgsql security definer set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_game_id uuid;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  perform public.prune_stale_room_members(p_room_id);
  if not exists(select 1 from public.rooms where id=p_room_id and status<>'closed') then return false; end if;
  update public.room_members set last_seen_at=now()
  where room_id=p_room_id and user_id=v_user and last_seen_at>=now()-interval '60 seconds';
  if not found then return false; end if;

  select hg.id into v_game_id from public.haunted_games hg
  join public.haunted_players hp on hp.game_id=hg.id
  where hg.room_id=p_room_id and hp.user_id=v_user and hp.is_bot=false
    and hp.left_at is null and hg.status<>'ended'
  order by hg.created_at desc limit 1;

  if v_game_id is not null then
    update public.rooms set status='playing',last_activity_at=now()
    where id=p_room_id and status<>'closed';
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
declare v_user uuid:=auth.uid(); v_room_id uuid;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  select hg.room_id into v_room_id from public.haunted_games hg
  join public.haunted_players hp on hp.game_id=hg.id
  where hp.user_id=v_user and hp.is_bot=false and hp.left_at is null and hg.status<>'ended'
  order by hg.created_at desc limit 1;
  if v_room_id is null then return; end if;
  perform public.prune_stale_room_members(v_room_id);
  update public.room_members set last_seen_at=now()
  where room_id=v_room_id and user_id=v_user and last_seen_at>=now()-interval '60 seconds';
  if not found then return; end if;
  update public.rooms set status='playing',last_activity_at=now()
  where id=v_room_id and status<>'closed';
  if not found then return; end if;
  return query select r.id,r.code,r.name,r.is_private,r.max_players,r.status,r.game_key
  from public.rooms r where r.id=v_room_id;
end;
$function$;

create or replace function private.notify_haunted_faqih_turn()
returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  if new.haunter_target is not null
     and (tg_op='INSERT' or old.haunter_target is distinct from new.haunter_target) then
    update public.haunted_games
    set phase_deadline_at=now()+interval '30 seconds',bot_next_action_at=null
    where id=new.game_id and status='night';
    insert into public.haunted_events(game_id,round,event_type,payload)
    values(new.game_id,new.round,'faqih_turn_opened',
      jsonb_build_object('message','المسكون اختار الضحية. دابا جا دور الفقيه.','role_turn','faqih'));
  end if;
  return new;
end;
$function$;

do $migration$
declare v_def text;
begin
  select pg_get_functiondef('public.advance_haunted_to_day(uuid)'::regprocedure) into v_def;
  v_def:=replace(v_def,
    $old$if not found or not exists (
    select 1 from public.haunted_players
    where game_id = p_game_id and user_id = v_user
  ) then$old$,
    $new$if not found
    or not exists(select 1 from public.room_members rm where rm.room_id=v_game.room_id and rm.user_id=v_user)
    or not exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.user_id=v_user and hp.left_at is null)
  then$new$);
  if position('rm.room_id=v_game.room_id' in v_def)=0 then
    raise exception 'Could not harden advance_haunted_to_day membership check';
  end if;
  execute v_def;

  select pg_get_functiondef('public.resolve_haunted_night(uuid)'::regprocedure) into v_def;
  v_def:=replace(v_def,
    $old$if not found or not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_user) then$old$,
    $new$if not found
  or not exists(select 1 from public.room_members rm where rm.room_id=v_game.room_id and rm.user_id=v_user)
  or not exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.user_id=v_user and hp.left_at is null) then$new$);
  if position('rm.room_id=v_game.room_id' in v_def)=0 then
    raise exception 'Could not harden resolve_haunted_night membership check';
  end if;
  execute v_def;

  select pg_get_functiondef('public.open_haunted_voting(uuid)'::regprocedure) into v_def;
  v_def:=replace(v_def,
    $old$if not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_user) then$old$,
    $new$if not exists(select 1 from public.room_members rm where rm.room_id=v_game.room_id and rm.user_id=v_user)
  or not exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.user_id=v_user and hp.left_at is null) then$new$);
  if position('rm.room_id=v_game.room_id' in v_def)=0 then
    raise exception 'Could not harden open_haunted_voting membership check';
  end if;
  execute v_def;

  select pg_get_functiondef('public.submit_haunter_kill(uuid,uuid)'::regprocedure) into v_def;
  v_def:=replace(v_def,
    $old$if not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_user and role='haunter' and is_alive) then$old$,
    $new$if not exists(select 1 from public.room_members rm where rm.room_id=v_game.room_id and rm.user_id=v_user)
  or not exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.user_id=v_user and hp.role='haunter' and hp.is_alive and hp.left_at is null) then$new$);
  if position('hp.left_at is null' in v_def)=0 then raise exception 'Could not harden submit_haunter_kill'; end if;
  execute v_def;

  select pg_get_functiondef('public.submit_faqih_protect(uuid,uuid)'::regprocedure) into v_def;
  v_def:=replace(v_def,
    $old$if not exists(
    select 1 from public.haunted_players
    where game_id=p_game_id and user_id=v_user and role='faqih' and is_alive
  ) then$old$,
    $new$if not exists(select 1 from public.room_members rm where rm.room_id=v_game.room_id and rm.user_id=v_user)
    or not exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.user_id=v_user and hp.role='faqih' and hp.is_alive and hp.left_at is null) then$new$);
  if position('hp.left_at is null' in v_def)=0 then raise exception 'Could not harden submit_faqih_protect'; end if;
  execute v_def;

  select pg_get_functiondef('public.submit_haunted_vote(uuid,uuid)'::regprocedure) into v_def;
  v_def:=replace(v_def,
    $old$if not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_user and is_alive) then$old$,
    $new$if not exists(select 1 from public.room_members rm where rm.room_id=v_game.room_id and rm.user_id=v_user)
  or not exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.user_id=v_user and hp.is_alive and hp.left_at is null) then$new$);
  if position('hp.left_at is null' in v_def)=0 then raise exception 'Could not harden submit_haunted_vote'; end if;
  execute v_def;

  select pg_get_functiondef('public.run_haunted_bot_turns(uuid)'::regprocedure) into v_def;
  v_def:=replace(v_def,
    $old$if v_game.status='night' then
  if v_game.bot_next_action_at is null$old$,
    $new$if v_game.status='night' then
  if v_game.phase_deadline_at<=now() then
    return jsonb_build_object('ok',true,'action','night_deadline_reached');
  end if;
  if v_game.bot_next_action_at is null$new$);
  v_def:=replace(v_def,
    $old$  if v_game.voting_open then
   if v_game.bot_next_action_at is null$old$,
    $new$  if v_game.voting_open then
   if v_game.phase_deadline_at<=now() then
    return jsonb_build_object('ok',true,'action','vote_deadline_reached');
   end if;
   if v_game.bot_next_action_at is null$new$);
  if position('night_deadline_reached' in v_def)=0 or position('vote_deadline_reached' in v_def)=0 then
    raise exception 'Could not guard bot actions at phase deadlines';
  end if;
  execute v_def;
end;
$migration$;

select cron.schedule('haunted-room-stale-cleanup','30 seconds','select public.prune_stale_room_members(null);');
