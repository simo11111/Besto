
alter table public.haunted_games add column if not exists bot_next_action_at timestamptz;

create or replace function public.open_haunted_voting(p_game_id uuid)
returns boolean language plpgsql security definer set search_path to ''
as $$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or v_game.status<>'day' then raise exception 'التصويت ما متاحش دابا'; end if;
 if not (v_game.created_by=v_user or exists(select 1 from public.room_members where room_id=v_game.room_id and user_id=v_user and role in ('owner','moderator'))) then raise exception 'غير مول الغرفة يقدر يفتح التصويت بكري'; end if;
 if v_game.voting_open then return true; end if;
 update public.haunted_games set voting_open=true,phase_deadline_at=now()+interval '30 seconds',bot_next_action_at=now()+interval '3 seconds' where id=p_game_id;
 insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'bot_chat',jsonb_build_object('message','تحل التصويت. عندكم 30 ثانية، اختارو بعناية.','system',true));
 return true;
end; $$;

create or replace function public.resolve_haunted_vote(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_alive integer; v_votes integer; v_top integer; v_top_count integer; v_ejected uuid; v_haunter uuid; v_villagers integer; v_winner text;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or not exists(select 1 from public.room_members where room_id=v_game.room_id and user_id=v_user) then raise exception 'ما عندكش الحق فهاد الغرفة'; end if;
 if v_game.status<>'day' or not v_game.voting_open then return jsonb_build_object('result','discussion'); end if;
 if v_game.phase_deadline_at>now() then
  select count(*) into v_votes from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round;
  select count(*) into v_alive from public.haunted_players where game_id=p_game_id and is_alive;
  return jsonb_build_object('result','waiting','votes',v_votes,'alive',v_alive,'seconds_left',ceil(extract(epoch from (v_game.phase_deadline_at-now()))));
 end if;
 select count(*) into v_alive from public.haunted_players where game_id=p_game_id and is_alive;
 select count(*) into v_votes from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round;
 select max(c),count(*) filter(where c=(select max(c2) from (select count(*) c2 from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round group by target_id) q)) into v_top,v_top_count
 from (select count(*) c from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round group by target_id) q;
 if v_top_count=1 then
  select target_id into v_ejected from public.haunted_votes where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round group by target_id having count(*)=v_top;
 end if;
 if v_top_count>1 and v_game.vote_round=1 then
  update public.haunted_games set vote_round=2,phase_deadline_at=now()+interval '30 seconds',voting_open=true,bot_next_action_at=now()+interval '3 seconds' where id=p_game_id;
  insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round,'vote_tied',jsonb_build_object('vote_round',2,'message','تعادل التصويت. غادي نعاودو التصويت لمدة 30 ثانية.'));
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
 update public.haunted_games set status='night',round=round+1,vote_round=1,phase_deadline_at=now()+interval '40 seconds',voting_open=false,bot_next_action_at=null where id=p_game_id;
 update public.haunted_players set voted_for=null,is_protected_this_night=false where game_id=p_game_id;
 insert into public.haunted_events(game_id,round,event_type,payload) values(p_game_id,v_game.round+1,'new_night',jsonb_build_object('message','رجع الليل للمخيم...','deadline_at',now()+interval '40 seconds'));
 return jsonb_build_object('result','next_night','round',v_game.round+1,'ejected_user_id',v_ejected);
end; $$;

create or replace function public.run_haunted_bot_turns(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
 v_user uuid:=auth.uid(); v_game public.haunted_games%rowtype; v_bot record; v_target uuid; v_message text; v_suspicion integer;
begin
 if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
 select * into v_game from public.haunted_games where id=p_game_id for update;
 if not found or not exists(select 1 from public.room_members where room_id=v_game.room_id and user_id=v_user and role in ('owner','moderator')) then raise exception 'غير مول الغرفة يقدر يشغل أدوار البوتات'; end if;
 if v_game.status='night' then
  if v_game.bot_next_action_at is null and (
    exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.is_alive and hp.role='haunter' and not exists(select 1 from public.haunted_night_actions na where na.game_id=p_game_id and na.round=v_game.round and na.haunter_target is not null))
    or exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.is_alive and hp.role='faqih' and not exists(select 1 from public.haunted_night_actions na where na.game_id=p_game_id and na.round=v_game.round and na.faqih_target is not null))
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
  if v_game.game_mode='standard' and not exists(select 1 from public.haunted_night_actions where game_id=p_game_id and round=v_game.round and faqih_target is not null) then
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
end; $$;

revoke all on function public.open_haunted_voting(uuid) from public,anon;
grant execute on function public.open_haunted_voting(uuid) to authenticated;
revoke all on function public.run_haunted_bot_turns(uuid) from public,anon;
grant execute on function public.run_haunted_bot_turns(uuid) to authenticated;
revoke all on function public.resolve_haunted_vote(uuid) from public,anon;
grant execute on function public.resolve_haunted_vote(uuid) to authenticated;
