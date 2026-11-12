-- Haunted Camp solo mode and NPC support.
alter table public.haunted_players add column if not exists is_bot boolean not null default false;
create table if not exists public.haunted_npcs (
 user_id uuid primary key, display_name text not null, avatar_key text not null, personality text not null
);
alter table public.haunted_npcs enable row level security;
revoke all on public.haunted_npcs from anon, authenticated;
insert into public.haunted_npcs(user_id,display_name,avatar_key,personality) values
('b07a0000-0000-4000-8000-000000000001','حمزة','camp-01','هادئ وكيحلل'),
('b07a0000-0000-4000-8000-000000000002','سلمى','camp-02','كتشك بسرعة'),
('b07a0000-0000-4000-8000-000000000003','ياسين','camp-03','كيهضر بزاف'),
('b07a0000-0000-4000-8000-000000000004','مريم','camp-04','ذكية وكتلاحظ'),
('b07a0000-0000-4000-8000-000000000005','آدم','camp-05','ساخر'),
('b07a0000-0000-4000-8000-000000000006','نور','camp-06','كتدافع على صحابها'),
('b07a0000-0000-4000-8000-000000000007','أيوب','camp-07','متردد'),
('b07a0000-0000-4000-8000-000000000008','ليلى','camp-08','كتجمع الأدلة'),
('b07a0000-0000-4000-8000-000000000009','ريان','camp-09','مغامر'),
('b07a0000-0000-4000-8000-000000000010','هبة','camp-10','كتلاحظ التفاصيل')
on conflict(user_id) do update set display_name=excluded.display_name,avatar_key=excluded.avatar_key,personality=excluded.personality;
alter table public.haunted_players drop constraint if exists haunted_players_user_id_fkey;
alter table public.haunted_players drop constraint if exists haunted_players_voted_for_fkey;
alter table public.haunted_votes drop constraint if exists haunted_votes_voter_id_fkey;
alter table public.haunted_votes drop constraint if exists haunted_votes_target_id_fkey;
alter table public.haunted_night_actions drop constraint if exists haunted_night_actions_faqih_target_fkey;
alter table public.haunted_night_actions drop constraint if exists haunted_night_actions_haunter_target_fkey;
alter table public.haunted_night_actions drop constraint if exists haunted_night_actions_killed_user_id_fkey;
alter table public.haunted_night_actions drop constraint if exists haunted_night_actions_protected_user_id_fkey;
alter table public.haunted_results drop constraint if exists haunted_results_user_id_fkey;
alter table public.haunted_events drop constraint if exists haunted_events_event_type_check;
alter table public.haunted_events add constraint haunted_events_event_type_check check(event_type = any(array['game_started','night_started','night_resolved','player_ejected','vote_tied','vote_tie_resolved','new_night','game_ended','bot_chat']));
revoke all on function public.run_haunted_bot_turns(uuid) from public,anon;
grant execute on function public.run_haunted_bot_turns(uuid) to authenticated;

CREATE OR REPLACE FUNCTION private.award_haunted_achievements(p_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record;
begin
 for v in select user_id from public.haunted_results where game_id=p_game_id and exists(select 1 from public.profiles p where p.id=haunted_results.user_id) loop
  if (select coalesce(sum(successful_protections),0) from public.haunted_results where user_id=v.user_id)>=3 then insert into public.player_achievements(user_id,achievement_id) values(v.user_id,'faqih_three_saves') on conflict do nothing; end if;
  if exists(select 1 from public.haunted_results where user_id=v.user_id and haunter_undetected) then insert into public.player_achievements(user_id,achievement_id) values(v.user_id,'haunter_undetected') on conflict do nothing; end if;
  if exists(select 1 from public.haunted_results where user_id=v.user_id and was_first_victim) then insert into public.player_achievements(user_id,achievement_id) values(v.user_id,'first_victim') on conflict do nothing; end if;
  if (select coalesce(sum(correct_votes),0) from public.haunted_results where user_id=v.user_id)>=5 then insert into public.player_achievements(user_id,achievement_id) values(v.user_id,'voice_of_wisdom') on conflict do nothing; end if;
 end loop;
end; $function$


CREATE OR REPLACE FUNCTION private.finish_haunted_game(p_game_id uuid, p_winner text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 update public.rooms set status='open',last_activity_at=now() where id=v_game.room_id and status='playing';
 select jsonb_agg(jsonb_build_object('user_id',hp.user_id,'role',hp.role,'is_alive',hp.is_alive) order by hp.created_at) into v_reveals from public.haunted_players hp where hp.game_id=p_game_id;
 for v_player in select hp.user_id,hp.role,hp.is_bot from public.haunted_players hp where hp.game_id=p_game_id loop
  v_won:=(p_winner='haunter' and v_player.role='haunter') or (p_winner='villagers' and v_player.role<>'haunter');
  select count(*) into v_kills from public.haunted_night_actions na where na.game_id=p_game_id and na.haunter_target is not null and na.killed_user_id is not null and v_player.role='haunter';
  select count(*) into v_saves from public.haunted_night_actions na where na.game_id=p_game_id and na.faqih_target=na.haunter_target and na.resolved and v_player.role='faqih';
  select count(*) into v_correct from public.haunted_votes hv join public.haunted_players target on target.game_id=hv.game_id and target.user_id=hv.target_id where hv.game_id=p_game_id and hv.voter_id=v_player.user_id and target.role='haunter';
  select coalesce((select eliminated.user_id from (
   select (payload->>'killed_user_id')::uuid as user_id,created_at from public.haunted_events where game_id=p_game_id and event_type='night_resolved' and payload->>'killed_user_id' is not null
   union all select (payload->>'ejected_user_id')::uuid as user_id,created_at from public.haunted_events where game_id=p_game_id and event_type='player_ejected' and payload->>'ejected_user_id' is not null
  ) eliminated order by eliminated.created_at limit 1)=v_player.user_id,false) into v_first;
  select not exists(select 1 from public.haunted_votes hv join public.haunted_players hp on hp.game_id=hv.game_id and hp.user_id=hv.target_id where hv.game_id=p_game_id and hp.role='haunter') into v_undetected;
  v_xp:=case v_player.role when 'haunter' then v_kills*50+case when v_won then 150 else 0 end when 'faqih' then v_saves*50+case when v_won then 100 else 0 end else v_correct*30+case when v_won then 100 else 0 end end;
  insert into public.haunted_results(game_id,user_id,role,won,xp_earned,successful_kills,successful_protections,correct_votes,was_first_victim,haunter_undetected)
  values(p_game_id,v_player.user_id,v_player.role,v_won,v_xp,case when v_player.role='haunter' then v_kills else 0 end,case when v_player.role='faqih' then v_saves else 0 end,v_correct,v_first,v_undetected)
  on conflict(game_id,user_id) do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=1 and not v_player.is_bot and exists(select 1 from public.profiles where id=v_player.user_id) then
   update public.profiles set xp=xp+v_xp,coins=coins+5+least(v_xp/5,20),level=1+floor(sqrt((xp+v_xp)::numeric/100))::int,games_played=games_played+1,wins=wins+case when v_won then 1 else 0 end,total_score=total_score+v_xp,updated_at=now() where id=v_player.user_id;
   insert into public.player_achievements(user_id,achievement_id) values(v_player.user_id,'first_game') on conflict do nothing;
   if v_won then insert into public.player_achievements(user_id,achievement_id) values(v_player.user_id,'first_win') on conflict do nothing; end if;
   if (select games_played from public.profiles where id=v_player.user_id)>=10 then insert into public.player_achievements(user_id,achievement_id) values(v_player.user_id,'social') on conflict do nothing; end if;
  end if;
 end loop;
 perform private.award_haunted_achievements(p_game_id);
 insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'game_ended',jsonb_build_object('winner',p_winner,'roles',coalesce(v_reveals,'[]'::jsonb)));
 return jsonb_build_object('winner',p_winner,'roles',coalesce(v_reveals,'[]'::jsonb));
end; $function$


CREATE OR REPLACE FUNCTION public.get_haunted_game_state(p_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_role text; v_vote uuid; v_players jsonb; v_events jsonb; v_roles jsonb; v_night_ready boolean:=false; v_vote_count integer:=0;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id;
 if not found or not exists(select 1 from public.room_members rm where rm.room_id=v_game.room_id and rm.user_id=v_user) then raise exception 'ما عندكش الحق تشوف هاد اللعبة'; end if;
 select role into v_role from public.haunted_players where game_id=p_game_id and user_id=v_user;
 if v_role is null then raise exception 'ماشي لاعب فهاد اللعبة'; end if;
 select target_id into v_vote from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round and voter_id=v_user;
 select coalesce(jsonb_agg(jsonb_build_object('user_id',hp.user_id,'username',coalesce(p.username,n.display_name,'لاعب'),'avatar_url',p.avatar_url,'is_alive',hp.is_alive,'is_bot',hp.is_bot) order by hp.created_at),'[]'::jsonb)
 into v_players from public.haunted_players hp left join public.profiles p on p.id=hp.user_id left join public.haunted_npcs n on n.user_id=hp.user_id where hp.game_id=p_game_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'round',e.round,'event_type',e.event_type,'payload',e.payload,'created_at',e.created_at) order by e.created_at),'[]'::jsonb)
 into v_events from public.haunted_events e where e.game_id=p_game_id;
 if v_game.status='night' then
  select coalesce((haunter_target is not null and (v_game.game_mode='quick' or faqih_target is not null)),false) into v_night_ready from public.haunted_night_actions where game_id=p_game_id and round=v_game.round;
 end if;
 select count(*) into v_vote_count from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round;
 if v_game.status='ended' then
  select coalesce(jsonb_agg(jsonb_build_object('user_id',hp.user_id,'role',hp.role) order by hp.created_at),'[]'::jsonb) into v_roles from public.haunted_players hp where hp.game_id=p_game_id;
 end if;
 return jsonb_build_object('id',v_game.id,'room_id',v_game.room_id,'status',v_game.status,'round',v_game.round,'vote_round',v_game.vote_round,'game_mode',v_game.game_mode,'winner',v_game.winner,'phase_deadline_at',v_game.phase_deadline_at,'role',v_role,'my_vote',v_vote,'players',v_players,'events',v_events,'roles',coalesce(v_roles,'[]'::jsonb),'night_actions_ready',v_night_ready,'vote_count',v_vote_count);
end; $function$


CREATE OR REPLACE FUNCTION public.run_haunted_bot_turns(p_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_bot record; v_target uuid; v_messages text[]:=array[
 'أنا كنقول خاصنا نركزو مزيان فالتصرفات ديال كل واحد.',
 'شي حاجة ما داخلاش ليا فهاد الليلة...',
 'ما تستعجلوش فالتصويت، جمعو القرائن.',
 'علاش ساكتين؟ كل واحد يقول شنو لاحظ.',
 'أنا باقي ما متأكدش، ولكن عندي شك فشي واحد.'
]; v_msg text;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or not exists(select 1 from public.room_members where room_id=v_game.room_id and user_id=v_user and role in ('owner','moderator')) then raise exception 'غير مول الغرفة يقدر يشغل أدوار البوتات'; end if;
 if v_game.status='night' then
  if not exists(select 1 from public.haunted_night_actions where game_id=p_game_id and round=v_game.round and haunter_target is not null) then
   select hp.user_id into v_bot from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.role='haunter' and hp.is_alive;
   if v_bot.user_id is not null then
    select user_id into v_target from public.haunted_players where game_id=p_game_id and is_alive and role<>'haunter' order by random() limit 1;
    insert into public.haunted_night_actions(game_id,round,haunter_target) values(p_game_id,v_game.round,v_target) on conflict(game_id,round) do update set haunter_target=excluded.haunter_target where public.haunted_night_actions.haunter_target is null and not public.haunted_night_actions.resolved;
   end if;
  end if;
  if v_game.game_mode='standard' and not exists(select 1 from public.haunted_night_actions where game_id=p_game_id and round=v_game.round and faqih_target is not null) then
   select hp.user_id into v_bot from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.role='faqih' and hp.is_alive;
   if v_bot.user_id is not null then
    select user_id into v_target from public.haunted_players where game_id=p_game_id and is_alive order by random() limit 1;
    insert into public.haunted_night_actions(game_id,round,faqih_target) values(p_game_id,v_game.round,v_target) on conflict(game_id,round) do update set faqih_target=excluded.faqih_target where public.haunted_night_actions.faqih_target is null and not public.haunted_night_actions.resolved;
   end if;
  end if;
 elsif v_game.status='day' then
  for v_bot in select hp.user_id from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.is_alive and not exists(select 1 from public.haunted_votes hv where hv.game_id=p_game_id and hv.round=v_game.round and hv.vote_round=v_game.vote_round and hv.voter_id=hp.user_id) loop
   select user_id into v_target from public.haunted_players where game_id=p_game_id and is_alive and user_id<>v_bot.user_id order by random() limit 1;
   if v_target is not null then
    insert into public.haunted_votes(game_id,round,vote_round,voter_id,target_id) values(p_game_id,v_game.round,v_game.vote_round,v_bot.user_id,v_target) on conflict do nothing;
    update public.haunted_players set voted_for=v_target where game_id=p_game_id and user_id=v_bot.user_id;
   end if;
  end loop;
  if not exists(select 1 from public.haunted_events where game_id=p_game_id and round=v_game.round and event_type='bot_chat' and created_at>now()-interval '18 seconds') then
   select message into v_msg from unnest(v_messages) message order by random() limit 1;
   select user_id into v_target from public.haunted_players where game_id=p_game_id and is_bot and is_alive order by random() limit 1;
   if v_target is not null then insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'bot_chat',jsonb_build_object('bot_user_id',v_target,'message',v_msg)); end if;
  end if;
 end if;
 return jsonb_build_object('ok',true,'phase',v_game.status);
end; $function$


CREATE OR REPLACE FUNCTION public.start_haunted_game(p_room_id uuid, p_quick_mode boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_user uuid:=auth.uid(); v_humans integer; v_total integer; v_target integer;
 v_game uuid; v_haunter uuid; v_faqih uuid; v_bot record; v_i integer:=0;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب باش تبدا اللعبة'; end if;
 perform 1 from public.rooms where id=p_room_id and status='open' for update;
 if not found then raise exception 'الغرفة ما بقاتش متاحة'; end if;
 if not exists(select 1 from public.room_members where room_id=p_room_id and user_id=v_user and role in ('owner','moderator')) then
  raise exception 'غير مول الغرفة يقدر يبدا اللعبة';
 end if;
 select count(*) into v_humans from public.room_members where room_id=p_room_id;
 if v_humans<1 or v_humans>10 then raise exception 'اللعبة كتقبل من لاعب واحد حتى 10 لاعبين'; end if;
 v_target:=case when p_quick_mode then 4 else 5 end;
 if p_quick_mode and v_humans>4 then raise exception 'الطور السريع كيقبل حتى 4 لاعبين مع البوتات'; end if;
 v_total:=greatest(v_target,v_humans);
 if exists(select 1 from public.haunted_games where room_id=p_room_id and status<>'ended') then raise exception 'كاينة لعبة ديجا خدامة فهاد الغرفة'; end if;
 if exists(select 1 from public.game_sessions where room_id=p_room_id and status='active') then raise exception 'ساليو اللعبة اللي خدامة قبل'; end if;
 insert into public.haunted_games(room_id,created_by,status,round,game_mode,phase_deadline_at)
 values(p_room_id,v_user,'night',1,case when p_quick_mode then 'quick' else 'standard' end,now()+interval '40 seconds') returning id into v_game;
 update public.rooms set status='playing',last_activity_at=now() where id=p_room_id;
 insert into public.haunted_players(game_id,user_id,role,is_bot)
 select v_game,rm.user_id,'villager',false from public.room_members rm where rm.room_id=p_room_id;
 for v_bot in select user_id from public.haunted_npcs order by random() limit (v_total-v_humans) loop
  insert into public.haunted_players(game_id,user_id,role,is_bot) values(v_game,v_bot.user_id,'villager',true);
 end loop;
 select user_id into v_haunter from public.haunted_players where game_id=v_game order by random() limit 1;
 if not p_quick_mode then
  select user_id into v_faqih from public.haunted_players where game_id=v_game and user_id<>v_haunter order by random() limit 1;
 end if;
 update public.haunted_players set role=case when user_id=v_haunter then 'haunter' when user_id=v_faqih then 'faqih' else 'villager' end where game_id=v_game;
 insert into public.haunted_events(game_id,round,event_type,payload)
 values(v_game,1,'game_started',jsonb_build_object('player_count',v_total,'human_count',v_humans,'bot_count',v_total-v_humans,'game_mode',case when p_quick_mode then 'quick' else 'standard' end)),
 (v_game,1,'night_started',jsonb_build_object('deadline_at',now()+interval '40 seconds')),
 (v_game,1,'bot_chat',jsonb_build_object('bot_user_id',(select user_id from public.haunted_players where game_id=v_game and is_bot order by random() limit 1),'message','واش كاملين واجدين؟ الليلة غادي تكون طويلة...'));
 return v_game;
end; $function$

