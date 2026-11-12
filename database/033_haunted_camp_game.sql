-- MIMOX: الفقيه والمسكون (Haunted Camp)
-- Migration 033. Secret roles and night decisions are never exposed through the Data API.

create table if not exists public.haunted_games (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  status text not null default 'night' check (status in ('lobby','night','morning','day','ended')),
  round integer not null default 1 check (round between 1 and 100),
  vote_round integer not null default 1 check (vote_round between 1 and 2),
  game_mode text not null default 'standard' check (game_mode in ('standard','quick')),
  winner text check (winner in ('villagers','haunter')),
  phase_deadline_at timestamptz,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create table if not exists public.haunted_players (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.haunted_games(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('haunter','faqih','villager')),
  is_alive boolean not null default true,
  is_protected_this_night boolean not null default false,
  voted_for uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(game_id,user_id)
);

create table if not exists public.haunted_night_actions (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.haunted_games(id) on delete cascade,
  round integer not null,
  haunter_target uuid references auth.users(id) on delete set null,
  faqih_target uuid references auth.users(id) on delete set null,
  resolved boolean not null default false,
  killed_user_id uuid references auth.users(id) on delete set null,
  protected_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(game_id,round)
);

create table if not exists public.haunted_votes (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.haunted_games(id) on delete cascade,
  round integer not null,
  vote_round integer not null default 1 check(vote_round in (1,2)),
  voter_id uuid not null references auth.users(id) on delete cascade,
  target_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(game_id,round,vote_round,voter_id),
  check(voter_id<>target_id)
);

create table if not exists public.haunted_events (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.haunted_games(id) on delete cascade,
  round integer not null,
  event_type text not null check (event_type in ('game_started','night_started','night_resolved','player_ejected','vote_tied','vote_tie_resolved','new_night','game_ended')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.haunted_results (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.haunted_games(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check(role in ('haunter','faqih','villager')),
  won boolean not null,
  xp_earned integer not null default 0,
  successful_kills integer not null default 0,
  successful_protections integer not null default 0,
  correct_votes integer not null default 0,
  was_first_victim boolean not null default false,
  haunter_undetected boolean not null default false,
  created_at timestamptz not null default now(),
  unique(game_id,user_id)
);

create index if not exists haunted_games_room_id_idx on public.haunted_games(room_id,created_at desc);
create index if not exists haunted_players_game_id_idx on public.haunted_players(game_id);
create index if not exists haunted_players_user_id_idx on public.haunted_players(user_id,game_id);
create index if not exists haunted_night_actions_game_round_idx on public.haunted_night_actions(game_id,round);
create index if not exists haunted_votes_game_round_idx on public.haunted_votes(game_id,round,vote_round);
create index if not exists haunted_events_game_round_idx on public.haunted_events(game_id,round,created_at);
create index if not exists haunted_results_user_id_idx on public.haunted_results(user_id,created_at desc);

alter table public.haunted_games enable row level security;
alter table public.haunted_players enable row level security;
alter table public.haunted_night_actions enable row level security;
alter table public.haunted_votes enable row level security;
alter table public.haunted_events enable row level security;
alter table public.haunted_results enable row level security;

drop policy if exists haunted_games_member_read on public.haunted_games;
create policy haunted_games_member_read on public.haunted_games for select to authenticated
using (exists(select 1 from public.room_members rm where rm.room_id=haunted_games.room_id and rm.user_id=(select auth.uid())));

drop policy if exists haunted_players_self_read on public.haunted_players;
create policy haunted_players_self_read on public.haunted_players for select to authenticated
using (user_id=(select auth.uid()) and exists(
  select 1 from public.haunted_games hg join public.room_members rm on rm.room_id=hg.room_id
  where hg.id=haunted_players.game_id and rm.user_id=(select auth.uid())
));

drop policy if exists haunted_votes_self_read on public.haunted_votes;
create policy haunted_votes_self_read on public.haunted_votes for select to authenticated
using (voter_id=(select auth.uid()) and exists(
  select 1 from public.haunted_games hg join public.room_members rm on rm.room_id=hg.room_id
  where hg.id=haunted_votes.game_id and rm.user_id=(select auth.uid())
));

drop policy if exists haunted_events_member_read on public.haunted_events;
create policy haunted_events_member_read on public.haunted_events for select to authenticated
using (exists(
  select 1 from public.haunted_games hg join public.room_members rm on rm.room_id=hg.room_id
  where hg.id=haunted_events.game_id and rm.user_id=(select auth.uid())
));

drop policy if exists haunted_results_self_read on public.haunted_results;
create policy haunted_results_self_read on public.haunted_results for select to authenticated
using (user_id=(select auth.uid()));

revoke all on public.haunted_games,public.haunted_players,public.haunted_night_actions,public.haunted_votes,public.haunted_events,public.haunted_results from anon,authenticated;
grant select on public.haunted_games,public.haunted_events to authenticated;
-- Column-level grants prevent role/protection/vote data from leaking via PostgREST.
grant select(id,game_id,user_id,is_alive,created_at) on public.haunted_players to authenticated;
grant select(id,game_id,round,vote_round,voter_id,target_id,created_at) on public.haunted_votes to authenticated;
grant select on public.haunted_results to authenticated;
grant usage on schema public to authenticated;

-- RPCs are the only write path. Each SECURITY DEFINER function pins search_path and checks auth.uid().
create or replace function public.start_haunted_game(p_room_id uuid,p_quick_mode boolean default false)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_count integer; v_game uuid; v_haunter uuid; v_faqih uuid;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب باش تبدا اللعبة'; end if;
 perform 1 from public.rooms where id=p_room_id and status='open' for update;
 if not found then raise exception 'الغرفة ما بقاتش متاحة'; end if;
 if not exists(select 1 from public.room_members where room_id=p_room_id and user_id=v_user and role in ('owner','moderator')) then
   raise exception 'غير مول الغرفة يقدر يبدا اللعبة';
 end if;
 select count(*) into v_count from public.room_members where room_id=p_room_id;
 if v_count<4 or v_count>10 then raise exception 'خاص يكونو بين 4 و10 لاعبين'; end if;
 if p_quick_mode and v_count<4 then raise exception 'الطور السريع خاصو 4 لاعبين على الأقل'; end if;
 if not p_quick_mode and v_count<5 then raise exception 'الطور العادي خاصو 5 لاعبين على الأقل؛ مع 4 اختار الطور السريع'; end if;
 if exists(select 1 from public.haunted_games where room_id=p_room_id and status<>'ended') then raise exception 'كاينة لعبة ديجا خدامة فهاد الغرفة'; end if;
 if exists(select 1 from public.game_sessions where room_id=p_room_id and status='active') then raise exception 'ساليو اللعبة اللي خدامة قبل';
 end if;
 insert into public.haunted_games(room_id,created_by,status,round,game_mode,phase_deadline_at)
 values(p_room_id,v_user,'night',1,case when p_quick_mode then 'quick' else 'standard' end,now()+interval '40 seconds')
 returning id into v_game;
 select user_id into v_haunter from public.room_members where room_id=p_room_id order by random() limit 1;
 if not p_quick_mode then
   select user_id into v_faqih from public.room_members where room_id=p_room_id and user_id<>v_haunter order by random() limit 1;
 end if;
 insert into public.haunted_players(game_id,user_id,role)
 select v_game,user_id,case when user_id=v_haunter then 'haunter' when user_id=v_faqih then 'faqih' else 'villager' end
 from public.room_members where room_id=p_room_id;
 insert into public.haunted_events(game_id,round,event_type,payload)
 values(v_game,1,'game_started',jsonb_build_object('player_count',v_count,'game_mode',case when p_quick_mode then 'quick' else 'standard' end)),
       (v_game,1,'night_started',jsonb_build_object('deadline_at',now()+interval '40 seconds'));
 return v_game;
end; $$;
revoke all on function public.start_haunted_game(uuid,boolean) from public,anon;
grant execute on function public.start_haunted_game(uuid,boolean) to authenticated;

create or replace function public.submit_haunter_kill(p_game_id uuid,p_target uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or v_game.status<>'night' then raise exception 'مرحلة الليل سالات'; end if;
 if not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_user and role='haunter' and is_alive) then raise exception 'هاد القرار غير ديال المسكون'; end if;
 if p_target is null or p_target=v_user or not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=p_target and is_alive) then raise exception 'اختار لاعب حي آخر'; end if;
 insert into public.haunted_night_actions(game_id,round,haunter_target) values(p_game_id,v_game.round,p_target)
 on conflict(game_id,round) do update set haunter_target=excluded.haunter_target
 where public.haunted_night_actions.haunter_target is null and not public.haunted_night_actions.resolved;
 if not found then raise exception 'اختيارك تسجل من قبل'; end if;
 return true;
end; $$;
revoke all on function public.submit_haunter_kill(uuid,uuid) from public,anon;
grant execute on function public.submit_haunter_kill(uuid,uuid) to authenticated;

create or replace function public.submit_faqih_protect(p_game_id uuid,p_target uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or v_game.status<>'night' then raise exception 'مرحلة الليل سالات'; end if;
 if not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_user and role='faqih' and is_alive) then raise exception 'هاد القرار غير ديال الفقيه'; end if;
 if p_target is null or not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=p_target and is_alive) then raise exception 'اختار لاعب حي'; end if;
 insert into public.haunted_night_actions(game_id,round,faqih_target) values(p_game_id,v_game.round,p_target)
 on conflict(game_id,round) do update set faqih_target=excluded.faqih_target
 where public.haunted_night_actions.faqih_target is null and not public.haunted_night_actions.resolved;
 if not found then raise exception 'الحماية ديالك تسجلات من قبل'; end if;
 return true;
end; $$;
revoke all on function public.submit_faqih_protect(uuid,uuid) from public,anon;
grant execute on function public.submit_faqih_protect(uuid,uuid) to authenticated;

create or replace function public.resolve_haunted_night(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_action public.haunted_night_actions%rowtype;
 v_killed uuid; v_protected uuid; v_alive integer; v_villagers integer; v_haunter uuid; v_result jsonb;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or v_game.created_by<>v_user then raise exception 'غير مول اللعبة يقدر يحسم الليل'; end if;
 if v_game.status<>'night' then raise exception 'الليل تحسم من قبل'; end if;
 select * into v_action from public.haunted_night_actions where game_id=p_game_id and round=v_game.round for update;
 if not found or v_action.haunter_target is null then
   if v_game.phase_deadline_at>now() then raise exception 'كنستناو المسكون يختار الهدف'; end if;
 end if;
 if v_game.game_mode='standard' and (v_action.faqih_target is null) and v_game.phase_deadline_at>now() then
   raise exception 'كنستناو الفقيه يختار الحماية';
 end if;
 v_killed:=case when v_action.haunter_target is null then null when v_action.haunter_target=v_action.faqih_target then null else v_action.haunter_target end;
 v_protected:=case when v_action.faqih_target is null then null else v_action.faqih_target end;
 if v_killed is not null then
   update public.haunted_players set is_alive=false where game_id=p_game_id and user_id=v_killed and is_alive;
 end if;
 update public.haunted_players set is_protected_this_night=(user_id=v_protected) where game_id=p_game_id;
 update public.haunted_night_actions set resolved=true,killed_user_id=v_killed,protected_user_id=v_protected where game_id=p_game_id and round=v_game.round;
 select user_id into v_haunter from public.haunted_players where game_id=p_game_id and role='haunter';
 select count(*) into v_villagers from public.haunted_players where game_id=p_game_id and role<>'haunter' and is_alive;
 select count(*) into v_alive from public.haunted_players where game_id=p_game_id and is_alive;
 if v_alive<=1 or v_villagers<=1 then
   update public.haunted_games set status='day',phase_deadline_at=now()+interval '1 second' where id=p_game_id;
 else
   update public.haunted_games set status='morning',phase_deadline_at=now()+interval '6 seconds' where id=p_game_id;
 end if;
 insert into public.haunted_events(game_id,round,event_type,payload)
 values(p_game_id,v_game.round,'night_resolved',jsonb_build_object('killed_user_id',v_killed,'saved',v_action.haunter_target is not null and v_killed is null,'message',case when v_killed is null then 'الليلة دازت بسلام، ما مات حتى واحد.' else 'لقينا واحد من اللاعبين ميت فالصباح.' end));
 v_result:=jsonb_build_object('killed_user_id',v_killed,'saved',v_action.haunter_target is not null and v_killed is null);
 if v_alive<=1 or v_villagers<=1 then
   perform private.finish_haunted_game(p_game_id,'haunter');
 end if;
 return v_result;
end; $$;
revoke all on function public.resolve_haunted_night(uuid) from public,anon;
grant execute on function public.resolve_haunted_night(uuid) to authenticated;

create or replace function public.advance_haunted_to_day(p_game_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or v_game.created_by<>v_user then raise exception 'غير مول اللعبة يقدر يبدل المرحلة'; end if;
 if v_game.status<>'morning' then raise exception 'مرحلة الصباح ما سالاتش'; end if;
 if v_game.phase_deadline_at>now() then raise exception 'خلي لحظة باش تبان نتيجة الصباح'; end if;
 update public.haunted_games set status='day',phase_deadline_at=now()+interval '60 seconds' where id=p_game_id;
 return true;
end; $$;
revoke all on function public.advance_haunted_to_day(uuid) from public,anon;
grant execute on function public.advance_haunted_to_day(uuid) to authenticated;

create or replace function public.submit_haunted_vote(p_game_id uuid,p_target uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or v_game.status<>'day' then raise exception 'التصويت ما مفتوحش دابا'; end if;
 if not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_user and is_alive) then raise exception 'غير اللاعبين الأحياء كيصوتو'; end if;
 if p_target is null or p_target=v_user or not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=p_target and is_alive) then raise exception 'اختار لاعب حي آخر'; end if;
 insert into public.haunted_votes(game_id,round,vote_round,voter_id,target_id)
 values(p_game_id,v_game.round,v_game.vote_round,v_user,p_target);
 update public.haunted_players set voted_for=p_target where game_id=p_game_id and user_id=v_user;
 return true;
exception when unique_violation then raise exception 'صوتك تسجل من قبل فهاد الجولة';
end; $$;
revoke all on function public.submit_haunted_vote(uuid,uuid) from public,anon;
grant execute on function public.submit_haunted_vote(uuid,uuid) to authenticated;

create or replace function public.resolve_haunted_vote(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_alive integer; v_votes integer;
 v_top integer; v_top_count integer; v_ejected uuid; v_haunter uuid; v_villagers integer; v_winner text; v_payload jsonb;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or v_game.created_by<>v_user then raise exception 'غير مول اللعبة يقدر يحسم التصويت'; end if;
 if v_game.status<>'day' then raise exception 'مرحلة التصويت ما مفتوحاش'; end if;
 select count(*) into v_alive from public.haunted_players where game_id=p_game_id and is_alive;
 select count(*) into v_votes from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round;
 if v_votes<v_alive and v_game.phase_deadline_at>now() then raise exception 'كنستناو باقي الأصوات'; end if;
 select max(c),count(*) filter(where c=(select max(c2) from (select count(*) c2 from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round group by target_id) q))
 into v_top,v_top_count from (select count(*) c from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round group by target_id) q;
 if v_top_count=1 then
   select target_id into v_ejected from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round group by target_id having count(*)=v_top;
 end if;
 if v_top_count>1 and v_game.vote_round=1 then
   update public.haunted_games set vote_round=2,phase_deadline_at=now()+interval '30 seconds' where id=p_game_id;
   insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'vote_tied',jsonb_build_object('vote_round',2,'message','تعادل التصويت! غادي نعاودو التصويت مرة أخرى.'));
   return jsonb_build_object('result','revote','vote_round',2);
 end if;
 if v_top_count=1 and v_ejected is not null then
   update public.haunted_players set is_alive=false where game_id=p_game_id and user_id=v_ejected and is_alive;
   insert into public.haunted_events(game_id,round,event_type,payload)
   values(p_game_id,v_game.round,'player_ejected',jsonb_build_object('ejected_user_id',v_ejected,'message','تم طرد لاعب من المخيم.'));
 elsif v_top_count>1 then
   insert into public.haunted_events(game_id,round,event_type,payload)
   values(p_game_id,v_game.round,'vote_tie_resolved',jsonb_build_object('ejected_user_id',null,'message','بقى التعادل، ما تطرد حتى واحد.'));
 end if;
 select user_id into v_haunter from public.haunted_players where game_id=p_game_id and role='haunter';
 select count(*) into v_villagers from public.haunted_players where game_id=p_game_id and role<>'haunter' and is_alive;
 if v_ejected=v_haunter then v_winner:='villagers';
 elsif v_villagers<=1 then v_winner:='haunter';
 end if;
 if v_winner is not null then
   perform private.finish_haunted_game(p_game_id,v_winner);
   return jsonb_build_object('result','game_ended','winner',v_winner,'ejected_user_id',v_ejected);
 end if;
 update public.haunted_games set status='night',round=round+1,vote_round=1,phase_deadline_at=now()+interval '40 seconds' where id=p_game_id;
 update public.haunted_players set voted_for=null,is_protected_this_night=false where game_id=p_game_id;
 insert into public.haunted_events(game_id,round,event_type,payload)
 values(p_game_id,v_game.round+1,'new_night',jsonb_build_object('message','رجع الليل للمخيم...','deadline_at',now()+interval '40 seconds'));
 return jsonb_build_object('result','next_night','round',v_game.round+1,'ejected_user_id',v_ejected);
end; $$;
revoke all on function public.resolve_haunted_vote(uuid) from public,anon;
grant execute on function public.resolve_haunted_vote(uuid) to authenticated;

create or replace function private.finish_haunted_game(p_game_id uuid,p_winner text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_game public.haunted_games%rowtype; v_player record; v_xp integer; v_kills integer; v_saves integer; v_correct integer; v_first boolean; v_undetected boolean; v_won boolean; v_reveals jsonb;
begin
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found then raise exception 'GAME_NOT_FOUND'; end if;
 if v_game.status='ended' then return jsonb_build_object('winner',v_game.winner); end if;
 if p_winner not in ('villagers','haunter') then raise exception 'INVALID_WINNER'; end if;
 update public.haunted_games set status='ended',winner=p_winner,ended_at=now(),phase_deadline_at=null where id=p_game_id;
 select jsonb_agg(jsonb_build_object('user_id',hp.user_id,'role',hp.role,'is_alive',hp.is_alive) order by hp.created_at)
 into v_reveals from public.haunted_players hp where hp.game_id=p_game_id;
 for v_player in select hp.user_id,hp.role from public.haunted_players hp where hp.game_id=p_game_id loop
   v_won:=(p_winner='haunter' and v_player.role='haunter') or (p_winner='villagers' and v_player.role<>'haunter');
   select count(*) into v_kills from public.haunted_night_actions na where na.game_id=p_game_id and na.haunter_target is not null and na.killed_user_id is not null and exists(select 1 from public.haunted_players h where h.game_id=p_game_id and h.user_id=v_player.user_id and h.role='haunter');
   select count(*) into v_saves from public.haunted_night_actions na where na.game_id=p_game_id and na.faqih_target=na.haunter_target and na.resolved and exists(select 1 from public.haunted_players h where h.game_id=p_game_id and h.user_id=v_player.user_id and h.role='faqih');
   select count(*) into v_correct from public.haunted_votes hv join public.haunted_players target on target.game_id=hv.game_id and target.user_id=hv.target_id
   where hv.game_id=p_game_id and hv.voter_id=v_player.user_id and target.role='haunter';
   select exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_player.user_id and not is_alive and created_at=(select min(created_at) from public.haunted_players where game_id=p_game_id and user_id=v_player.user_id)) into v_first;
   select v_player.role='haunter' and not exists(select 1 from public.haunted_votes hv join public.haunted_players h on h.game_id=hv.game_id and h.user_id=hv.target_id where hv.game_id=p_game_id and h.role='haunter') into v_undetected;
   v_xp:=case v_player.role when 'haunter' then v_kills*50+case when v_won then 150 else 0 end
         when 'faqih' then v_saves*50+case when v_won then 100 else 0 end
         else v_correct*30+case when v_won then 100 else 0 end end;
   insert into public.haunted_results(game_id,user_id,role,won,xp_earned,successful_kills,successful_protections,correct_votes,was_first_victim,haunter_undetected)
   values(p_game_id,v_player.user_id,v_player.role,v_won,v_xp,case when v_player.role='haunter' then v_kills else 0 end,case when v_player.role='faqih' then v_saves else 0 end,v_correct,v_first,v_undetected)
   on conflict(game_id,user_id) do nothing;
   if not exists(select 1 from public.haunted_results where game_id=p_game_id and user_id=v_player.user_id and created_at<now()-interval '1 second') then
     update public.profiles set xp=xp+v_xp,coins=coins+case when v_won then 10 else 5 end,
       level=1+floor(sqrt((xp+v_xp)::numeric/100))::int,
       games_played=games_played+1,wins=wins+case when v_won then 1 else 0 end,
       total_score=total_score+v_xp,updated_at=now()
     where id=v_player.user_id;
     insert into public.player_achievements(user_id,achievement_id)
     values(v_player.user_id,'first_game') on conflict do nothing;
   end if;
 end loop;
 insert into public.haunted_events(game_id,round,event_type,payload)
 values(p_game_id,v_game.round,'game_ended',jsonb_build_object('winner',p_winner,'roles',coalesce(v_reveals,'[]'::jsonb)));
 return jsonb_build_object('winner',p_winner,'roles',coalesce(v_reveals,'[]'::jsonb));
end; $$;
revoke all on function private.finish_haunted_game(uuid,text) from public,anon,authenticated;
grant usage on schema private to authenticated;

create or replace function public.end_haunted_game(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id;
 if not found or v_game.created_by<>v_user or v_game.status<>'ended' then raise exception 'اللعبة ما سالاتش أو ما عندكش الصلاحية'; end if;
 return private.finish_haunted_game(p_game_id,v_game.winner);
end; $$;
revoke all on function public.end_haunted_game(uuid) from public,anon;
grant execute on function public.end_haunted_game(uuid) to authenticated;

create or replace function public.get_haunted_game_state(p_game_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_role text; v_vote uuid; v_players jsonb; v_events jsonb; v_roles jsonb; v_night_ready boolean:=false; v_vote_count integer:=0;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id;
 if not found or not exists(select 1 from public.room_members rm where rm.room_id=v_game.room_id and rm.user_id=v_user) then raise exception 'ما عندكش الحق تشوف هاد اللعبة'; end if;
 select role into v_role from public.haunted_players where game_id=p_game_id and user_id=v_user;
 if v_role is null then raise exception 'ماشي لاعب فهاد اللعبة'; end if;
 select target_id into v_vote from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round and voter_id=v_user;
 select coalesce(jsonb_agg(jsonb_build_object('user_id',hp.user_id,'username',p.username,'avatar_url',p.avatar_url,'is_alive',hp.is_alive) order by hp.created_at),'[]'::jsonb)
 into v_players from public.haunted_players hp join public.profiles p on p.id=hp.user_id where hp.game_id=p_game_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'round',e.round,'event_type',e.event_type,'payload',e.payload,'created_at',e.created_at) order by e.created_at),'[]'::jsonb)
 into v_events from public.haunted_events e where e.game_id=p_game_id;
 if v_game.status='night' then
   select coalesce((haunter_target is not null and (v_game.game_mode='quick' or faqih_target is not null)),false) into v_night_ready from public.haunted_night_actions where game_id=p_game_id and round=v_game.round;
 end if;
 select count(*) into v_vote_count from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round;
 if v_game.status='ended' then
   select coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'role',role) order by created_at),'[]'::jsonb) into v_roles
   from public.haunted_players where game_id=p_game_id;
 end if;
 return jsonb_build_object('id',v_game.id,'room_id',v_game.room_id,'status',v_game.status,'round',v_game.round,'vote_round',v_game.vote_round,'game_mode',v_game.game_mode,'winner',v_game.winner,'phase_deadline_at',v_game.phase_deadline_at,'role',v_role,'my_vote',v_vote,'players',v_players,'events',v_events,'roles',coalesce(v_roles,'[]'::jsonb),'night_actions_ready',v_night_ready,'vote_count',v_vote_count);
end; $$;
revoke all on function public.get_haunted_game_state(uuid) from public,anon;
grant execute on function public.get_haunted_game_state(uuid) to authenticated;

-- Realtime only broadcasts phase and public events; sensitive night-action and role rows are never published.
do $$
begin
  begin alter publication supabase_realtime add table public.haunted_games; exception when duplicate_object then null; when undefined_object then null; end;
  begin alter publication supabase_realtime add table public.haunted_events; exception when duplicate_object then null; when undefined_object then null; end;
end $$;
alter table public.haunted_games replica identity full;
alter table public.haunted_events replica identity full;

-- New achievement catalog entries are safe to upsert.
insert into public.achievements(id,name,description,icon,xp_reward,coin_reward) values
 ('faqih_three_saves','الفقيه اللي أنقذ 3 ليالي','حميتي اللاعبين ونجحتي فثلاث ليالي أو أكثر.','🛡️',50,10),
 ('haunter_undetected','المسكون اللي ما اكتشفش حتى مرة','ربحتي كمسكون وما تصوّت عليك حتى لاعب.','👻',75,15),
 ('first_victim','أول ضحية','كنت أول لاعب يخرج من المخيم.','🪦',10,2),
 ('voice_of_wisdom','صوت الحكمة','جمعتي خمسة تصويتات صحيحة ضد المسكون.','🗳️',50,10)
on conflict(id) do update set name=excluded.name,description=excluded.description,icon=excluded.icon,xp_reward=excluded.xp_reward,coin_reward=excluded.coin_reward;

-- Award cumulative achievements after results are written.
create or replace function private.award_haunted_achievements(p_game_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare v record;
begin
 for v in select user_id from public.haunted_results where game_id=p_game_id loop
   if (select coalesce(sum(successful_protections),0) from public.haunted_results where user_id=v.user_id)>=3 then
     insert into public.player_achievements(user_id,achievement_id) values(v.user_id,'faqih_three_saves') on conflict do nothing;
   end if;
   if exists(select 1 from public.haunted_results where user_id=v.user_id and haunter_undetected) then
     insert into public.player_achievements(user_id,achievement_id) values(v.user_id,'haunter_undetected') on conflict do nothing;
   end if;
   if exists(select 1 from public.haunted_results where user_id=v.user_id and was_first_victim) then
     insert into public.player_achievements(user_id,achievement_id) values(v.user_id,'first_victim') on conflict do nothing;
   end if;
   if (select coalesce(sum(correct_votes),0) from public.haunted_results where user_id=v.user_id)>=5 then
     insert into public.player_achievements(user_id,achievement_id) values(v.user_id,'voice_of_wisdom') on conflict do nothing;
   end if;
 end loop;
end; $$;
revoke all on function private.award_haunted_achievements(uuid) from public,anon,authenticated;

-- Replace the finisher with an idempotent version and award achievements inside the same transaction.
create or replace function private.finish_haunted_game(p_game_id uuid,p_winner text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_game public.haunted_games%rowtype; v_player record; v_xp integer; v_kills integer; v_saves integer; v_correct integer; v_first boolean; v_undetected boolean; v_won boolean; v_reveals jsonb; v_inserted integer;
begin
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found then raise exception 'GAME_NOT_FOUND'; end if;
 if v_game.status='ended' then
   select coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'role',role) order by created_at),'[]'::jsonb) into v_reveals from public.haunted_players where game_id=p_game_id;
   return jsonb_build_object('winner',v_game.winner,'roles',coalesce(v_reveals,'[]'::jsonb));
 end if;
 if p_winner not in ('villagers','haunter') then raise exception 'INVALID_WINNER'; end if;
 update public.haunted_games set status='ended',winner=p_winner,ended_at=now(),phase_deadline_at=null where id=p_game_id;
 select jsonb_agg(jsonb_build_object('user_id',hp.user_id,'role',hp.role,'is_alive',hp.is_alive) order by hp.created_at)
 into v_reveals from public.haunted_players hp where hp.game_id=p_game_id;
 for v_player in select hp.user_id,hp.role from public.haunted_players hp where hp.game_id=p_game_id loop
   v_won:=(p_winner='haunter' and v_player.role='haunter') or (p_winner='villagers' and v_player.role<>'haunter');
   select count(*) into v_kills from public.haunted_night_actions na where na.game_id=p_game_id and na.haunter_target is not null and na.killed_user_id is not null and v_player.role='haunter';
   select count(*) into v_saves from public.haunted_night_actions na where na.game_id=p_game_id and na.faqih_target=na.haunter_target and na.resolved and v_player.role='faqih';
   select count(*) into v_correct from public.haunted_votes hv join public.haunted_players target on target.game_id=hv.game_id and target.user_id=hv.target_id where hv.game_id=p_game_id and hv.voter_id=v_player.user_id and target.role='haunter';
   select exists(select 1 from public.haunted_night_actions where game_id=p_game_id and round=1 and killed_user_id=v_player.user_id) into v_first;
   select not exists(select 1 from public.haunted_votes hv join public.haunted_players h on h.game_id=hv.game_id and h.user_id=hv.target_id where hv.game_id=p_game_id and h.role='haunter') into v_undetected;
   v_xp:=case v_player.role when 'haunter' then v_kills*50+case when v_won then 150 else 0 end
         when 'faqih' then v_saves*50+case when v_won then 100 else 0 end
         else v_correct*30+case when v_won then 100 else 0 end end;
   insert into public.haunted_results(game_id,user_id,role,won,xp_earned,successful_kills,successful_protections,correct_votes,was_first_victim,haunter_undetected)
   values(p_game_id,v_player.user_id,v_player.role,v_won,v_xp,case when v_player.role='haunter' then v_kills else 0 end,case when v_player.role='faqih' then v_saves else 0 end,v_correct,v_first,v_undetected)
   on conflict(game_id,user_id) do nothing;
   get diagnostics v_inserted=row_count;
   if v_inserted=1 then
     update public.profiles set xp=xp+v_xp,coins=coins+case when v_won then 10 else 5 end,
       level=1+floor(sqrt((xp+v_xp)::numeric/100))::int,
       games_played=games_played+1,wins=wins+case when v_won then 1 else 0 end,
       total_score=total_score+v_xp,updated_at=now() where id=v_player.user_id;
     insert into public.player_achievements(user_id,achievement_id) values(v_player.user_id,'first_game') on conflict do nothing;
   end if;
 end loop;
 perform private.award_haunted_achievements(p_game_id);
 insert into public.haunted_events(game_id,round,event_type,payload)
 values(p_game_id,v_game.round,'game_ended',jsonb_build_object('winner',p_winner,'roles',coalesce(v_reveals,'[]'::jsonb)));
 return jsonb_build_object('winner',p_winner,'roles',coalesce(v_reveals,'[]'::jsonb));
end; $$;


create or replace function public.get_active_haunted_game(p_room_id uuid)
returns uuid language plpgsql stable security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_game uuid;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 if not exists(select 1 from public.room_members where room_id=p_room_id and user_id=v_user) then
   raise exception 'ما عندكش الحق تشوف هاد الغرفة';
 end if;
 select id into v_game from public.haunted_games where room_id=p_room_id and status<>'ended' order by created_at desc limit 1;
 return v_game;
end; $$;
revoke all on function public.get_active_haunted_game(uuid) from public,anon;
grant execute on function public.get_active_haunted_game(uuid) to authenticated;
