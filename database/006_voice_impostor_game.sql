-- DIMA PLAY: voice-first impostor round.
alter table public.game_sessions drop constraint if exists game_sessions_game_key_check;
alter table public.game_sessions add constraint game_sessions_game_key_check
  check (game_key in ('wolf','who','forbidden','ten_seconds','impostor'));

alter table public.game_actions drop constraint if exists game_actions_action_key_check;
alter table public.game_actions add constraint game_actions_action_key_check
  check (action_key in ('vote','answer','clue','guess','ask'));

insert into public.game_prompts(game_key,prompt,accepted_answers,forbidden_words) values
 ('impostor','البحر',array['البحر'],array[]::text[]),
 ('impostor','البيتزا',array['البيتزا'],array[]::text[]),
 ('impostor','الطائرة',array['الطائرة'],array[]::text[]),
 ('impostor','المدرسة',array['المدرسة'],array[]::text[]),
 ('impostor','القهوة',array['القهوة'],array[]::text[]),
 ('impostor','كرة القدم',array['كرة القدم'],array[]::text[]),
 ('impostor','المطار',array['المطار'],array[]::text[]),
 ('impostor','الهاتف',array['الهاتف'],array[]::text[]),
 ('impostor','العرس',array['العرس'],array[]::text[]),
 ('impostor','القطار',array['القطار'],array[]::text[])
on conflict do nothing;

create or replace function public.start_party_game(p_room_id uuid,p_game_key text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
 v_user uuid:=auth.uid(); v_session uuid; v_prompt public.game_prompts%rowtype;
 v_target uuid; v_player_count integer;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_game_key not in ('wolf','who','forbidden','ten_seconds','impostor') then raise exception 'INVALID_GAME'; end if;
 if not private.is_room_member(p_room_id) then raise exception 'NOT_ROOM_MEMBER'; end if;
 if not exists(select 1 from public.room_members where room_id=p_room_id and user_id=v_user and role in ('owner','moderator')) then raise exception 'HOST_ONLY'; end if;
 select count(*) into v_player_count from public.room_members where room_id=p_room_id;
 if p_game_key='impostor' and v_player_count<4 then raise exception 'NEED_FOUR_PLAYERS'; end if;
 if p_game_key='wolf' and v_player_count<4 then raise exception 'NEED_FOUR_PLAYERS'; end if;
 if p_game_key in ('who','forbidden') and v_player_count<3 then raise exception 'NEED_THREE_PLAYERS'; end if;
 if p_game_key='ten_seconds' and v_player_count<2 then raise exception 'NEED_MORE_PLAYERS'; end if;
 insert into public.game_sessions(room_id,game_key,created_by) values(p_room_id,p_game_key,v_user) returning id into v_session;
 insert into public.game_players(session_id,user_id) select v_session,user_id from public.room_members where room_id=p_room_id;
 if p_game_key='wolf' then
   select user_id into v_target from public.game_players where session_id=v_session order by random() limit 1;
   insert into private.game_player_secrets(session_id,user_id,secret_role)
   select v_session,user_id,case when user_id=v_target then 'wolf' else 'villager' end
   from public.game_players where session_id=v_session;
 end if;
 if p_game_key in ('forbidden','ten_seconds','impostor') then
   select * into v_prompt from public.game_prompts where game_key=p_game_key and active order by random() limit 1;
   if not found then raise exception 'NO_GAME_PROMPTS'; end if;
   if p_game_key='impostor' then
     select user_id into v_target from public.game_players where session_id=v_session order by random() limit 1;
     insert into private.game_session_secrets(session_id,prompt,accepted_answers,forbidden_words,target_user_id,phase)
     values(v_session,v_prompt.prompt,v_prompt.accepted_answers,'{}'::text[],v_target,'asking');
     insert into private.game_player_secrets(session_id,user_id,secret_role)
     select v_session,user_id,case when user_id=v_target then 'impostor' else 'knows_word' end
     from public.game_players where session_id=v_session;
   else
     insert into private.game_session_secrets(session_id,prompt,accepted_answers,forbidden_words,target_user_id)
     values(v_session,v_prompt.prompt,v_prompt.accepted_answers,v_prompt.forbidden_words,
       (select user_id from public.game_players where session_id=v_session order by random() limit 1));
   end if;
 end if;
 return v_session;
end;
$$;

create or replace function public.get_my_game_secret(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype;
 v_secret private.game_session_secrets%rowtype; v_role text;
 v_player_count integer; v_asks integer; v_votes integer;
 v_asked boolean; v_voted boolean;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id;
 if not found or not private.is_room_member(v_game.room_id) then raise exception 'NO_ACCESS'; end if;
 select secret_role into v_role from private.game_player_secrets where session_id=p_session_id and user_id=v_user;
 select * into v_secret from private.game_session_secrets where session_id=p_session_id;
 if v_game.game_key='wolf' then return jsonb_build_object('role',coalesce(v_role,'villager')); end if;
 if v_game.game_key='forbidden' and v_secret.target_user_id=v_user then
   return jsonb_build_object('prompt',v_secret.prompt,'forbidden_words',to_jsonb(v_secret.forbidden_words),'is_clue_giver',true);
 end if;
 if v_game.game_key='ten_seconds' then return jsonb_build_object('prompt',v_secret.prompt); end if;
 if v_game.game_key='impostor' then
   select count(*) into v_player_count from public.game_players where session_id=p_session_id;
   select count(*) into v_asks from public.game_actions where session_id=p_session_id and action_key='ask';
   select count(*) into v_votes from public.game_actions where session_id=p_session_id and action_key='vote';
   select exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key='ask') into v_asked;
   select exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key='vote') into v_voted;
   return jsonb_build_object(
     'game_mode','impostor',
     'role',coalesce(v_role,'knows_word'),
     'is_impostor',v_role='impostor',
     'word',case when v_role='impostor' then null else v_secret.prompt end,
     'phase',v_secret.phase,
     'player_count',v_player_count,
     'asks_count',v_asks,
     'votes_count',v_votes,
     'has_asked',v_asked,
     'has_voted',v_voted
   );
 end if;
 return '{}'::jsonb;
end;
$$;

create or replace function public.submit_party_action(p_session_id uuid,p_action_key text,p_payload jsonb)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
 v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype; v_id bigint;
 v_target uuid; v_text text; v_secret private.game_session_secrets%rowtype;
 v_count integer; v_total integer;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id and status='active' for update;
 if not found or not private.is_room_member(v_game.room_id) then raise exception 'GAME_NOT_AVAILABLE'; end if;
 if not exists(select 1 from public.game_players where session_id=p_session_id and user_id=v_user) then raise exception 'NOT_A_PLAYER'; end if;
 if p_action_key is null or p_action_key not in ('vote','answer','clue','guess','ask') or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'INVALID_ACTION'; end if;
 if v_game.game_key='impostor' then
   select * into v_secret from private.game_session_secrets where session_id=p_session_id for update;
   if p_action_key='ask' then
     if v_secret.phase<>'asking' then raise exception 'ASKING_PHASE_CLOSED'; end if;
     begin v_target:=(p_payload->>'target_user_id')::uuid; exception when others then raise exception 'INVALID_TARGET'; end;
     if v_target=v_user or not exists(select 1 from public.game_players where session_id=p_session_id and user_id=v_target) then raise exception 'INVALID_TARGET'; end if;
     if exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key='ask') then raise exception 'ACTION_ALREADY_SENT'; end if;
     insert into public.game_actions(session_id,user_id,action_key,payload) values(p_session_id,v_user,'ask',jsonb_build_object('target_user_id',v_target)) returning id into v_id;
     select count(*) into v_count from public.game_actions where session_id=p_session_id and action_key='ask';
     select count(*) into v_total from public.game_players where session_id=p_session_id;
     if v_count=v_total then update private.game_session_secrets set phase='voting' where session_id=p_session_id; end if;
     return v_id;
   elsif p_action_key='vote' then
     if v_secret.phase<>'voting' then raise exception 'VOTING_NOT_OPEN'; end if;
     begin v_target:=(p_payload->>'target_user_id')::uuid; exception when others then raise exception 'INVALID_TARGET'; end;
     if v_target=v_user or not exists(select 1 from public.game_players where session_id=p_session_id and user_id=v_target) then raise exception 'INVALID_TARGET'; end if;
     if exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key='vote') then raise exception 'ACTION_ALREADY_SENT'; end if;
     insert into public.game_actions(session_id,user_id,action_key,payload) values(p_session_id,v_user,'vote',jsonb_build_object('target_user_id',v_target)) returning id into v_id;
     return v_id;
   else raise exception 'INVALID_ACTION_FOR_GAME'; end if;
 end if;
 if v_game.game_key='ten_seconds' then
   select * into v_secret from private.game_session_secrets where session_id=p_session_id;
   if now()>v_secret.deadline_at then raise exception 'TIME_EXPIRED'; end if;
 end if;
 if p_action_key='vote' then
   begin v_target:=(p_payload->>'target_user_id')::uuid; exception when others then raise exception 'INVALID_TARGET'; end;
   if not exists(select 1 from public.game_players where session_id=p_session_id and user_id=v_target) or v_target=v_user then raise exception 'INVALID_TARGET'; end if;
 end if;
 if p_action_key in ('answer','clue','guess') then
   v_text:=btrim(coalesce(p_payload->>'text',''));
   if char_length(v_text) not between 1 and 240 then raise exception 'INVALID_TEXT'; end if;
   p_payload:=jsonb_build_object('text',v_text);
 end if;
 if v_game.game_key in ('wolf','who') and p_action_key<>'vote' then raise exception 'INVALID_ACTION_FOR_GAME'; end if;
 if v_game.game_key='ten_seconds' and p_action_key<>'answer' then raise exception 'INVALID_ACTION_FOR_GAME'; end if;
 if v_game.game_key='forbidden' then
   select target_user_id into v_target from private.game_session_secrets where session_id=p_session_id;
   if p_action_key not in ('clue','guess') then raise exception 'INVALID_ACTION_FOR_GAME'; end if;
   if p_action_key='clue' and v_user is distinct from v_target then raise exception 'ONLY_CLUE_GIVER'; end if;
   if p_action_key='guess' and v_user=v_target then raise exception 'CLUE_GIVER_CANNOT_GUESS'; end if;
 end if;
 if exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key=p_action_key) then raise exception 'ACTION_ALREADY_SENT'; end if;
 insert into public.game_actions(session_id,user_id,action_key,payload) values(p_session_id,v_user,p_action_key,p_payload) returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.finish_party_game(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype; v_secret private.game_session_secrets%rowtype;
 v_impostor uuid; v_voted uuid; v_votes integer; v_players integer;
 v_player record; v_points integer; v_xp integer; v_coins integer; v_result jsonb:='{}'::jsonb;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id and status='active' for update;
 if not found or v_game.created_by<>v_user or not private.is_room_member(v_game.room_id) then raise exception 'HOST_ONLY'; end if;
 if v_game.game_key='impostor' then
   select * into v_secret from private.game_session_secrets where session_id=p_session_id for update;
   if v_secret.phase<>'voting' then raise exception 'VOTING_NOT_OPEN'; end if;
   select count(*) into v_players from public.game_players where session_id=p_session_id;
   select count(*) into v_votes from public.game_actions where session_id=p_session_id and action_key='vote';
   if v_votes<>v_players then raise exception 'WAITING_FOR_VOTES'; end if;
   select target_user_id into v_impostor from private.game_session_secrets where session_id=p_session_id;
   select (payload->>'target_user_id')::uuid into v_voted
     from public.game_actions where session_id=p_session_id and action_key='vote'
     group by payload->>'target_user_id' order by count(*) desc,payload->>'target_user_id' limit 1;
   if v_voted=v_impostor then
     v_result:=jsonb_build_object('result','impostor_caught','impostor',v_impostor,'word',v_secret.prompt);
   else
     v_result:=jsonb_build_object('result','impostor_escaped','impostor',v_impostor,'word',v_secret.prompt);
   end if;
   for v_player in select user_id from public.game_players where session_id=p_session_id loop
     v_points:=case when v_voted=v_impostor and v_player.user_id<>v_impostor then 20
                    when v_voted<>v_impostor and v_player.user_id=v_impostor then 35 else 5 end;
     update public.game_players set score=score+v_points where session_id=p_session_id and user_id=v_player.user_id;
   end loop;
   update private.game_session_secrets set phase='completed' where session_id=p_session_id;
   update public.game_sessions set status='completed',ended_at=now() where id=p_session_id;
   for v_player in select gp.user_id,gp.score from public.game_players gp where gp.session_id=p_session_id loop
     v_xp:=20+least(v_player.score,80); v_coins:=5+least(v_player.score/5,20);
     update public.profiles set xp=xp+v_xp,coins=coins+v_coins,
       level=1+floor(sqrt((xp+v_xp)::numeric/100))::int,
       games_played=games_played+1,total_score=total_score+v_player.score,
       wins=wins+case when v_player.score=(select max(score) from public.game_players where session_id=p_session_id) then 1 else 0 end
       where id=v_player.user_id;
     insert into public.player_achievements(user_id,achievement_id) values(v_player.user_id,'first_game') on conflict do nothing;
   end loop;
   return v_result||jsonb_build_object('leaderboard',(select jsonb_agg(jsonb_build_object('user_id',user_id,'score',score) order by score desc) from public.game_players where session_id=p_session_id));
 end if;
 -- Preserve the established scoring path for the other game modes.
 return public.finish_party_game(p_session_id);
end;
$$;

revoke all on function public.start_party_game(uuid,text) from public,anon;
revoke all on function public.get_my_game_secret(uuid) from public,anon;
revoke all on function public.submit_party_action(uuid,text,jsonb) from public,anon;
revoke all on function public.finish_party_game(uuid) from public,anon;
grant execute on function public.start_party_game(uuid,text) to authenticated;
grant execute on function public.get_my_game_secret(uuid) to authenticated;
grant execute on function public.submit_party_action(uuid,text,jsonb) to authenticated;
grant execute on function public.finish_party_game(uuid) to authenticated;
