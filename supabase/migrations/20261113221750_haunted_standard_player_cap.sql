-- Haunted Camp has ten NPC profiles and a ten-seat scene. Keep standard mode
-- aligned with that supported capacity even when the parent room allows 16.
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

 -- Quick mode is four players; standard mode is capped at ten.
 v_target := case when p_quick_mode then least(4,v_room_capacity) else least(10,v_room_capacity) end;
 if v_target < 4 then raise exception 'الغرفة خاصها تقبل على الأقل 4 لاعبين'; end if;
 if v_humans < 1 then
  raise exception 'خاص يكون لاعب واحد على الأقل فالغرفة';
 elsif v_humans > v_target then
  if p_quick_mode then
   raise exception 'الطور السريع كيسمح حتى 4 لاعبين فقط';
  else
   raise exception 'ليلة فالخيمة كتقبل حتى 10 لاعبين';
  end if;
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
$function$;
