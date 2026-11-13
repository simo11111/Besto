-- FAQIH is a core role in both standard and quick Haunted Camp modes.
CREATE OR REPLACE FUNCTION public.run_haunted_bot_turns(p_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_bot record; v_target uuid; v_message text; v_suspicion integer;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or not exists(select 1 from public.room_members where room_id=v_game.room_id and user_id=v_user and role in ('owner','moderator')) then raise exception 'غير مول الغرفة يقدر يشغل أدوار البوتات'; end if;
 if v_game.status='night' then
  if v_game.bot_next_action_at is null and (
    exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.is_alive and hp.role='haunter' and not exists(select 1 from public.haunted_night_actions na where na.game_id=p_game_id and na.round=v_game.round and na.haunter_target is not null))
    or exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.is_alive and hp.role='faqih'
      and exists(select 1 from public.haunted_night_actions na where na.game_id=p_game_id and na.round=v_game.round and na.haunter_target is not null and not na.resolved)
      and not exists(select 1 from public.haunted_night_actions na where na.game_id=p_game_id and na.round=v_game.round and na.faqih_target is not null))
  ) then
   update public.haunted_games set bot_next_action_at=now()+interval '3 seconds'+random()*interval '2 seconds' where id=p_game_id;
   return jsonb_build_object('ok',true,'waiting',true);
  end if;
  if v_game.bot_next_action_at is not null and v_game.bot_next_action_at>now() then return jsonb_build_object('ok',true,'waiting',true); end if;
  if not exists(select 1 from public.haunted_night_actions where game_id=p_game_id and round=v_game.round and haunter_target is not null) then
   select hp.user_id into v_bot from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.role='haunter' and hp.is_alive limit 1;
   if v_bot.user_id is not null then
    select hp.user_id,coalesce((select count(*) from public.haunted_votes hv where hv.game_id=p_game_id and hv.target_id=hp.user_id and hv.round<v_game.round),0) into v_target,v_suspicion
    from public.haunted_players hp where hp.game_id=p_game_id and hp.is_alive and hp.role<>'haunter'
    order by 2 desc,random() limit 1;
    insert into public.haunted_night_actions(game_id,round,haunter_target) values(p_game_id,v_game.round,v_target)
    on conflict(game_id,round) do update set haunter_target=excluded.haunter_target where public.haunted_night_actions.haunter_target is null and not public.haunted_night_actions.resolved;
    update public.haunted_games set bot_next_action_at=case when exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.is_alive and hp.role='faqih' and not exists(select 1 from public.haunted_night_actions na where na.game_id=p_game_id and na.round=v_game.round and na.faqih_target is not null)) then now()+interval '3 seconds'+random()*interval '2 seconds' else null end where id=p_game_id;
    return jsonb_build_object('ok',true,'action','haunter');
   end if;
  end if;
  if exists(select 1 from public.haunted_night_actions where game_id=p_game_id and round=v_game.round and haunter_target is not null and not resolved)
    and not exists(select 1 from public.haunted_night_actions where game_id=p_game_id and round=v_game.round and faqih_target is not null) then
   select hp.user_id into v_bot from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.role='faqih' and hp.is_alive limit 1;
   if v_bot.user_id is not null then
    select hp.user_id into v_target from public.haunted_players hp where hp.game_id=p_game_id and hp.is_alive
    order by coalesce((select count(*) from public.haunted_votes hv where hv.game_id=p_game_id and hv.target_id=hp.user_id and hv.round<v_game.round),0) desc,random() limit 1;
    insert into public.haunted_night_actions(game_id,round,faqih_target) values(p_game_id,v_game.round,v_target)
    on conflict(game_id,round) do update set faqih_target=excluded.faqih_target where public.haunted_night_actions.faqih_target is null and not public.haunted_night_actions.resolved;
    update public.haunted_games set bot_next_action_at=null where id=p_game_id;
    return jsonb_build_object('ok',true,'action','faqih');
   end if;
  end if;
 elsif v_game.status='day' then
  if not v_game.voting_open and v_game.phase_deadline_at<=now() then
   update public.haunted_games set voting_open=true,phase_deadline_at=now()+interval '30 seconds',bot_next_action_at=now()+interval '3 seconds' where id=p_game_id;
   insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'bot_chat',jsonb_build_object('message','تحل التصويت. عندكم 30 ثانية باش تختارو.','system',true));
   return jsonb_build_object('ok',true,'action','voting_opened');
  end if;
  if v_game.voting_open then
   if v_game.bot_next_action_at is null and exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.is_alive and not exists(select 1 from public.haunted_votes hv where hv.game_id=p_game_id and hv.round=v_game.round and hv.vote_round=v_game.vote_round and hv.voter_id=hp.user_id)) then
    update public.haunted_games set bot_next_action_at=now()+interval '2 seconds'+random()*interval '2 seconds' where id=p_game_id;
    return jsonb_build_object('ok',true,'waiting',true);
   end if;
   if v_game.bot_next_action_at is not null and v_game.bot_next_action_at<=now() then
    select hp.user_id,hp.role into v_bot from public.haunted_players hp
    where hp.game_id=p_game_id and hp.is_bot and hp.is_alive
      and not exists(select 1 from public.haunted_votes hv where hv.game_id=p_game_id and hv.round=v_game.round and hv.vote_round=v_game.vote_round and hv.voter_id=hp.user_id)
    order by hp.created_at limit 1;
    if v_bot.user_id is not null then
     select hp.user_id into v_target from public.haunted_players hp
     where hp.game_id=p_game_id and hp.is_alive and hp.user_id<>v_bot.user_id
     order by case when v_bot.role='haunter' then -coalesce((select count(*) from public.haunted_votes hv where hv.game_id=p_game_id and hv.target_id=hp.user_id and hv.round<v_game.round),0) else coalesce((select count(*) from public.haunted_votes hv where hv.game_id=p_game_id and hv.target_id=hp.user_id and hv.round<v_game.round),0) end desc,random()
     limit 1;
     insert into public.haunted_votes(game_id,round,vote_round,voter_id,target_id) values(p_game_id,v_game.round,v_game.vote_round,v_bot.user_id,v_target) on conflict do nothing;
     update public.haunted_players set voted_for=v_target where game_id=p_game_id and user_id=v_bot.user_id;
     update public.haunted_games set bot_next_action_at=case when exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.is_alive and not exists(select 1 from public.haunted_votes hv where hv.game_id=p_game_id and hv.round=v_game.round and hv.vote_round=v_game.vote_round and hv.voter_id=hp.user_id)) then now()+interval '2 seconds'+random()*interval '2 seconds' else null end where id=p_game_id;
     return jsonb_build_object('ok',true,'action','bot_vote');
    end if;
   end if;
  end if;
  if not exists(select 1 from public.haunted_events where game_id=p_game_id and round=v_game.round and event_type='bot_chat' and created_at>now()-interval '18 seconds') then
   select user_id into v_target from public.haunted_players where game_id=p_game_id and is_bot and is_alive order by random() limit 1;
   if v_target is not null then
    v_message:=case floor(random()*5)::integer when 0 then 'أنا كنقول خاصنا نركزو مزيان فالتصرفات ديال كل واحد.' when 1 then 'شي حاجة ما داخلاش ليا فهاد الليلة، واش حتى نتما لاحظتو؟' when 2 then 'ما تستعجلوش فالتصويت، جمعو القرائن قبل القرار.' when 3 then 'علاش ساكتين؟ كل واحد يقول شنو لاحظ.' else 'أنا باقي ما متأكدش، ولكن عندي شك فشي واحد.' end;
    insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'bot_chat',jsonb_build_object('bot_user_id',v_target,'message',v_message));
   end if;
  end if;
 end if;
 return jsonb_build_object('ok',true,'phase',v_game.status);
end; $function$
;

CREATE OR REPLACE FUNCTION public.start_haunted_game(p_room_id uuid, p_quick_mode boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_user uuid := auth.uid();
 v_humans integer;
 v_total integer;
 v_target integer;
 v_room_capacity integer;
 v_game uuid;
 v_haunter uuid;
 v_faqih uuid;
 v_bot record;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب باش تبدا اللعبة'; end if;

 select max_players into v_room_capacity
 from public.rooms
 where id=p_room_id and status='open'
 for update;
 if not found then raise exception 'الغرفة ما بقاتش متاحة'; end if;

 if not exists(
   select 1 from public.room_members
   where room_id=p_room_id and user_id=v_user and role in ('owner','moderator')
 ) then
  raise exception 'غير مول الغرفة يقدر يبدا اللعبة';
 end if;

 select count(*) into v_humans
 from public.room_members
 where room_id=p_room_id;

 v_target := case when p_quick_mode then least(4,v_room_capacity) else v_room_capacity end;
 if v_target < 4 then raise exception 'الغرفة خاصها تقبل على الأقل 4 لاعبين'; end if;
 if v_humans < 1 or v_humans > v_target then
  raise exception 'عدد اللاعبين فالغرفة تجاوز الطاقة الاستيعابية المختارة';
 end if;

 v_total := v_target;

 if exists(select 1 from public.haunted_games where room_id=p_room_id and status<>'ended') then
  raise exception 'كاينة لعبة ديجا خدامة فهاد الغرفة';
 end if;
 if exists(select 1 from public.game_sessions where room_id=p_room_id and status='active') then
  raise exception 'ساليو اللعبة اللي خدامة قبل';
 end if;
 if (select count(*) from public.haunted_npcs) < (v_total-v_humans) then
  raise exception 'ما كايناش شخصيات بوتات كافية باش نكملو العدد المطلوب';
 end if;

 insert into public.haunted_games(room_id,created_by,status,round,game_mode,phase_deadline_at)
 values(p_room_id,v_user,'night',1,case when p_quick_mode then 'quick' else 'standard' end,now()+interval '40 seconds')
 returning id into v_game;

 update public.rooms set status='playing',last_activity_at=now() where id=p_room_id;

 insert into public.haunted_players(game_id,user_id,role,is_bot)
 select v_game,rm.user_id,'villager',false
 from public.room_members rm where rm.room_id=p_room_id;

 for v_bot in
  select user_id from public.haunted_npcs
  where not exists(
   select 1 from public.haunted_players hp
   where hp.game_id=v_game and hp.user_id=haunted_npcs.user_id
  )
  order by random()
  limit (v_total-v_humans)
 loop
  insert into public.haunted_players(game_id,user_id,role,is_bot)
  values(v_game,v_bot.user_id,'villager',true);
 end loop;

 select user_id into v_haunter
 from public.haunted_players where game_id=v_game
 order by random() limit 1;

 select user_id into v_faqih
 from public.haunted_players
 where game_id=v_game and user_id<>v_haunter
 order by random() limit 1;

 update public.haunted_players
 set role=case when user_id=v_haunter then 'haunter'
               when user_id=v_faqih then 'faqih'
               else 'villager' end
 where game_id=v_game;

 insert into public.haunted_events(game_id,round,event_type,payload)
 values
 (v_game,1,'game_started',jsonb_build_object(
   'player_count',v_total,'human_count',v_humans,
   'bot_count',v_total-v_humans,
   'room_capacity',v_room_capacity,
   'game_mode',case when p_quick_mode then 'quick' else 'standard' end
 )),
 (v_game,1,'night_started',jsonb_build_object('deadline_at',now()+interval '40 seconds')),
 (v_game,1,'bot_chat',jsonb_build_object(
   'bot_user_id',(select user_id from public.haunted_players where game_id=v_game and is_bot order by random() limit 1),
   'message','واش كاملين واجدين؟ الليلة غادي تكون طويلة...'
 ));

 return v_game;
end;
$function$
;
