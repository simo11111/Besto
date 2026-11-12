alter table public.haunted_players add column if not exists left_at timestamptz;

create or replace function public.prune_stale_room_members(p_room_id uuid default null)
returns integer language plpgsql security definer set search_path to ''
as $function$
declare v_removed integer:=0; v_room record; v_next uuid; v_count integer;
begin
 for v_room in select r.id,r.owner_id from public.rooms r where r.status<>'closed' and (p_room_id is null or r.id=p_room_id) for update
 loop
  with stale as (
   delete from public.room_members m where m.room_id=v_room.id and m.last_seen_at<now()-interval '30 seconds'
   returning m.room_id,m.user_id
  ), marked as (
   update public.haunted_players hp set left_at=coalesce(hp.left_at,now()),is_alive=false
   from stale s join public.haunted_games hg on hg.room_id=s.room_id
   where hp.game_id=hg.id and hp.user_id=s.user_id and hp.is_bot=false and hp.left_at is null and hg.status<>'ended'
   returning hp.user_id
  )
  select count(*) into v_count from stale;
  v_removed:=v_removed+v_count;
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

create or replace function public.leave_room(p_room_id uuid)
returns boolean language plpgsql security definer set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_owner uuid; v_next_owner uuid; v_removed integer;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select owner_id into v_owner from public.rooms where id=p_room_id for update;
 if not found then return false; end if;
 update public.haunted_players hp set left_at=coalesce(hp.left_at,now()),is_alive=false
 from public.haunted_games hg
 where hp.game_id=hg.id and hg.room_id=p_room_id and hp.user_id=v_user
  and hp.is_bot=false and hp.left_at is null and hg.status<>'ended';
 delete from public.room_members where room_id=p_room_id and user_id=v_user;
 get diagnostics v_removed=row_count;
 if v_removed=0 then return false; end if;
 if not exists(select 1 from public.room_members where room_id=p_room_id) then
  update public.rooms set status='closed',last_activity_at=now() where id=p_room_id;
 elsif v_owner=v_user then
  select user_id into v_next_owner from public.room_members where room_id=p_room_id order by last_seen_at desc,joined_at asc limit 1;
  update public.room_members set role='player' where room_id=p_room_id;
  update public.room_members set role='owner' where room_id=p_room_id and user_id=v_next_owner;
  update public.rooms set owner_id=v_next_owner,last_activity_at=now() where id=p_room_id;
 else update public.rooms set last_activity_at=now() where id=p_room_id;
 end if;
 return true;
end;
$function$;

create or replace function public.get_latest_haunted_game(p_room_id uuid)
returns uuid language plpgsql stable security definer set search_path to ''
as $function$
declare v_user uuid:=auth.uid(); v_game uuid;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 if not exists(select 1 from public.room_members where room_id=p_room_id and user_id=v_user) then raise exception 'ما عندكش الحق تشوف هاد الغرفة'; end if;
 select hg.id into v_game from public.haunted_games hg join public.haunted_players hp on hp.game_id=hg.id
 where hg.room_id=p_room_id and hp.user_id=v_user and hp.left_at is null and hg.status<>'ended'
 order by hg.created_at desc limit 1;
 return v_game;
end;
$function$;

create or replace function public.get_haunted_game_state(p_game_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
declare
 v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_role text; v_vote uuid;
 v_players jsonb; v_events jsonb; v_roles jsonb; v_night_ready boolean:=false; v_vote_count integer:=0;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id;
 if not found or not exists(select 1 from public.room_members rm where rm.room_id=v_game.room_id and rm.user_id=v_user) then raise exception 'ما عندكش الحق تشوف هاد اللعبة'; end if;
 select role into v_role from public.haunted_players where game_id=p_game_id and user_id=v_user and left_at is null;
 if v_role is null then raise exception 'ماشي لاعب فهاد اللعبة'; end if;
 select target_id into v_vote from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round and voter_id=v_user;
 select coalesce(jsonb_agg(jsonb_build_object(
  'user_id',hp.user_id,'username',coalesce(p.username,n.display_name,'لاعب'),'avatar_url',p.avatar_url,'avatar_key',n.avatar_key,
  'gender',coalesce(p.gender,n.gender,'male'),'is_alive',hp.is_alive,'is_bot',hp.is_bot
 ) order by hp.created_at),'[]'::jsonb) into v_players
 from public.haunted_players hp left join public.profiles p on p.id=hp.user_id left join public.haunted_npcs n on n.user_id=hp.user_id where hp.game_id=p_game_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'round',e.round,'event_type',e.event_type,'payload',e.payload,'created_at',e.created_at) order by e.created_at),'[]'::jsonb)
 into v_events from public.haunted_events e where e.game_id=p_game_id;
 if v_game.status='night' then
  select coalesce((haunter_target is not null and (v_game.game_mode='quick' or faqih_target is not null)),false) into v_night_ready
  from public.haunted_night_actions where game_id=p_game_id and round=v_game.round;
 end if;
 select count(*) into v_vote_count from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round;
 if v_game.status='ended' then
  select coalesce(jsonb_agg(jsonb_build_object('user_id',hp.user_id,'role',hp.role) order by hp.created_at),'[]'::jsonb) into v_roles
  from public.haunted_players hp where hp.game_id=p_game_id;
 end if;
 return jsonb_build_object(
  'id',v_game.id,'room_id',v_game.room_id,'status',v_game.status,'round',v_game.round,'vote_round',v_game.vote_round,
  'game_mode',v_game.game_mode,'winner',v_game.winner,'phase_deadline_at',v_game.phase_deadline_at,'voting_open',v_game.voting_open,
  'role',v_role,'my_vote',v_vote,'players',v_players,'events',v_events,'roles',coalesce(v_roles,'[]'::jsonb),
  'night_actions_ready',v_night_ready,'vote_count',v_vote_count
 );
end;
$function$;
