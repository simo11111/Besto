alter table public.haunted_games add column if not exists voting_open boolean not null default false;
CREATE OR REPLACE FUNCTION public.advance_haunted_to_day(p_game_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_user) then raise exception 'ما عندكش الحق فهاد الغرفة'; end if;
 if v_game.status<>'morning' then return true; end if;
 if v_game.phase_deadline_at>now() then raise exception 'خلي لحظة باش يعلن الراوي نتيجة الصباح'; end if;
 update public.haunted_games set status='day',phase_deadline_at=now()+interval '4 minutes',voting_open=false where id=p_game_id;
 insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'bot_chat',jsonb_build_object('message','عندكم أربع دقايق للنقاش. جمعو القرائن قبل ما يتحل التصويت.','system',true));
 return true;
end; $function$
;

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
 select coalesce(jsonb_agg(jsonb_build_object('user_id',hp.user_id,'username',coalesce(p.username,n.display_name,'لاعب'),'avatar_url',p.avatar_url,'is_alive',hp.is_alive,'is_bot',hp.is_bot) order by hp.created_at),'[]'::jsonb) into v_players from public.haunted_players hp left join public.profiles p on p.id=hp.user_id left join public.haunted_npcs n on n.user_id=hp.user_id where hp.game_id=p_game_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'round',e.round,'event_type',e.event_type,'payload',e.payload,'created_at',e.created_at) order by e.created_at),'[]'::jsonb) into v_events from public.haunted_events e where e.game_id=p_game_id;
 if v_game.status='night' then select coalesce((haunter_target is not null and (v_game.game_mode='quick' or faqih_target is not null)),false) into v_night_ready from public.haunted_night_actions where game_id=p_game_id and round=v_game.round; end if;
 select count(*) into v_vote_count from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round;
 if v_game.status='ended' then select coalesce(jsonb_agg(jsonb_build_object('user_id',hp.user_id,'role',hp.role) order by hp.created_at),'[]'::jsonb) into v_roles from public.haunted_players hp where hp.game_id=p_game_id; end if;
 return jsonb_build_object('id',v_game.id,'room_id',v_game.room_id,'status',v_game.status,'round',v_game.round,'vote_round',v_game.vote_round,'game_mode',v_game.game_mode,'winner',v_game.winner,'phase_deadline_at',v_game.phase_deadline_at,'voting_open',v_game.voting_open,'role',v_role,'my_vote',v_vote,'players',v_players,'events',v_events,'roles',coalesce(v_roles,'[]'::jsonb),'night_actions_ready',v_night_ready,'vote_count',v_vote_count);
end; $function$
;

CREATE OR REPLACE FUNCTION public.open_haunted_voting(p_game_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or v_game.status<>'day' then raise exception 'التصويت ما متاحش دابا'; end if;
 if not (v_game.created_by=v_user or exists(select 1 from public.room_members where room_id=v_game.room_id and user_id=v_user and role in ('owner','moderator'))) then raise exception 'غير مول الغرفة يقدر يفتح التصويت بكري'; end if;
 if v_game.voting_open then return true; end if;
 update public.haunted_games set voting_open=true,phase_deadline_at=now()+interval '60 seconds' where id=p_game_id;
 insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'bot_chat',jsonb_build_object('message','تحل التصويت! عندكم دقيقة باش تختارو المشتبه فيه.','system',true));
 return true;
end; $function$
;

CREATE OR REPLACE FUNCTION public.resolve_haunted_night(p_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_action public.haunted_night_actions%rowtype;
 v_killed uuid; v_protected uuid; v_alive integer; v_villagers integer; v_haunter uuid; v_result jsonb;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_user) then raise exception 'ما عندكش الحق فهاد الغرفة'; end if;
 if v_game.status<>'night' then return jsonb_build_object('status',v_game.status); end if;
 if v_game.created_by<>v_user and v_game.phase_deadline_at>now() then raise exception 'مول اللعبة هو اللي يقدر يحسم قبل نهاية العداد'; end if;
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
   update public.haunted_games set status='morning',phase_deadline_at=now()+interval '15 seconds' where id=p_game_id;
 end if;
 insert into public.haunted_events(game_id,round,event_type,payload)
 values(p_game_id,v_game.round,'night_resolved',jsonb_build_object('killed_user_id',v_killed,'message',case when v_killed is null then 'الليلة دازت بسلام، ما مات حتى واحد.' else 'لقينا واحد من اللاعبين ميت فالصباح.' end));
 v_result:=jsonb_build_object('killed_user_id',v_killed);
 if v_alive<=1 or v_villagers<=1 then
   perform private.finish_haunted_game(p_game_id,'haunter');
 end if;
 return v_result;
end; $function$
;

CREATE OR REPLACE FUNCTION public.resolve_haunted_vote(p_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_alive integer; v_votes integer; v_top integer; v_top_count integer; v_ejected uuid; v_haunter uuid; v_villagers integer; v_winner text;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or not exists(select 1 from public.room_members where room_id=v_game.room_id and user_id=v_user) then raise exception 'ما عندكش الحق فهاد الغرفة'; end if;
 if v_game.status<>'day' or not v_game.voting_open then return jsonb_build_object('result','discussion'); end if;
 select count(*) into v_alive from public.haunted_players where game_id=p_game_id and is_alive;
 select count(*) into v_votes from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round;
 if v_votes<v_alive and v_game.phase_deadline_at>now() then return jsonb_build_object('result','waiting','votes',v_votes,'alive',v_alive); end if;
 select max(c),count(*) filter(where c=(select max(c2) from (select count(*) c2 from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round group by target_id) q)) into v_top,v_top_count from (select count(*) c from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round group by target_id) q;
 if v_top_count=1 then select target_id into v_ejected from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round group by target_id having count(*)=v_top; end if;
 if v_top_count>1 and v_game.vote_round=1 then
  update public.haunted_games set vote_round=2,phase_deadline_at=now()+interval '30 seconds',voting_open=true where id=p_game_id;
  insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'vote_tied',jsonb_build_object('vote_round',2,'message','تعادل التصويت! غادي نعاودو التصويت مرة أخرى.'));
  return jsonb_build_object('result','revote','vote_round',2);
 end if;
 if v_top_count=1 and v_ejected is not null then
  update public.haunted_players set is_alive=false where game_id=p_game_id and user_id=v_ejected and is_alive;
  insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'player_ejected',jsonb_build_object('ejected_user_id',v_ejected,'message','تم طرد لاعب من المخيم.'));
 elsif v_top_count>1 then
  insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'vote_tie_resolved',jsonb_build_object('ejected_user_id',null,'message','بقى التعادل، ما تطرد حتى واحد.'));
 end if;
 select user_id into v_haunter from public.haunted_players where game_id=p_game_id and role='haunter';
 select count(*) into v_villagers from public.haunted_players where game_id=p_game_id and role<>'haunter' and is_alive;
 if v_ejected=v_haunter then v_winner:='villagers'; elsif v_villagers<=1 then v_winner:='haunter'; end if;
 if v_winner is not null then perform private.finish_haunted_game(p_game_id,v_winner); return jsonb_build_object('result','game_ended','winner',v_winner,'ejected_user_id',v_ejected); end if;
 update public.haunted_games set status='night',round=round+1,vote_round=1,phase_deadline_at=now()+interval '40 seconds',voting_open=false where id=p_game_id;
 update public.haunted_players set voted_for=null,is_protected_this_night=false where game_id=p_game_id;
 insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round+1,'new_night',jsonb_build_object('message','رجع الليل للمخيم...','deadline_at',now()+interval '40 seconds'));
 return jsonb_build_object('result','next_night','round',v_game.round+1,'ejected_user_id',v_ejected);
end; $function$
;

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
   if v_bot.user_id is not null then select user_id into v_target from public.haunted_players where game_id=p_game_id and is_alive and role<>'haunter' order by random() limit 1; insert into public.haunted_night_actions(game_id,round,haunter_target) values(p_game_id,v_game.round,v_target) on conflict(game_id,round) do update set haunter_target=excluded.haunter_target where public.haunted_night_actions.haunter_target is null and not public.haunted_night_actions.resolved; end if;
  end if;
  if v_game.game_mode='standard' and not exists(select 1 from public.haunted_night_actions where game_id=p_game_id and round=v_game.round and faqih_target is not null) then
   select hp.user_id into v_bot from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.role='faqih' and hp.is_alive;
   if v_bot.user_id is not null then select user_id into v_target from public.haunted_players where game_id=p_game_id and is_alive order by random() limit 1; insert into public.haunted_night_actions(game_id,round,faqih_target) values(p_game_id,v_game.round,v_target) on conflict(game_id,round) do update set faqih_target=excluded.faqih_target where public.haunted_night_actions.faqih_target is null and not public.haunted_night_actions.resolved; end if;
  end if;
 elsif v_game.status='day' then
  if not v_game.voting_open and v_game.phase_deadline_at<=now() then
   update public.haunted_games set voting_open=true,phase_deadline_at=now()+interval '60 seconds' where id=p_game_id;
   insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'bot_chat',jsonb_build_object('message','تحل التصويت! عندكم دقيقة باش تختارو المشتبه فيه.','system',true));
  elsif v_game.voting_open then
   for v_bot in select hp.user_id from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.is_alive and not exists(select 1 from public.haunted_votes hv where hv.game_id=p_game_id and hv.round=v_game.round and hv.vote_round=v_game.vote_round and hv.voter_id=hp.user_id) loop
    select user_id into v_target from public.haunted_players where game_id=p_game_id and is_alive and user_id<>v_bot.user_id order by random() limit 1;
    if v_target is not null then insert into public.haunted_votes(game_id,round,vote_round,voter_id,target_id) values(p_game_id,v_game.round,v_game.vote_round,v_bot.user_id,v_target) on conflict do nothing; update public.haunted_players set voted_for=v_target where game_id=p_game_id and user_id=v_bot.user_id; end if;
   end loop;
  end if;
  if not exists(select 1 from public.haunted_events where game_id=p_game_id and round=v_game.round and event_type='bot_chat' and created_at>now()-interval '18 seconds') then
   select message into v_msg from unnest(v_messages) message order by random() limit 1;
   select user_id into v_target from public.haunted_players where game_id=p_game_id and is_bot and is_alive order by random() limit 1;
   if v_target is not null then insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'bot_chat',jsonb_build_object('bot_user_id',v_target,'message',v_msg)); end if;
  end if;
 end if;
 return jsonb_build_object('ok',true,'phase',v_game.status);
end; $function$
;

CREATE OR REPLACE FUNCTION public.submit_haunted_vote(p_game_id uuid, p_target uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or v_game.status<>'day' or not v_game.voting_open then raise exception 'التصويت باقي ما تحلش'; end if;
 if v_game.phase_deadline_at<=now() then raise exception 'وقت التصويت سالا'; end if;
 if not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=v_user and is_alive) then raise exception 'غير اللاعبين الأحياء كيصوتو'; end if;
 if p_target is null or p_target=v_user or not exists(select 1 from public.haunted_players where game_id=p_game_id and user_id=p_target and is_alive) then raise exception 'اختار لاعب حي آخر'; end if;
 insert into public.haunted_votes(game_id,round,vote_round,voter_id,target_id) values(p_game_id,v_game.round,v_game.vote_round,v_user,p_target);
 update public.haunted_players set voted_for=p_target where game_id=p_game_id and user_id=v_user;
 return true;
exception when unique_violation then raise exception 'صوتك تسجل من قبل فهاد الجولة';
end; $function$
;
revoke all on function public.open_haunted_voting(uuid) from public,anon;
grant execute on function public.open_haunted_voting(uuid) to authenticated;
