-- DIMA PLAY gameplay authorization fixes.
create or replace function public.submit_party_action(p_session_id uuid,p_action_key text,p_payload jsonb)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype; v_id bigint; v_target uuid; v_text text; v_secret private.game_session_secrets%rowtype;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id and status='active';
 if not found or not private.is_room_member(v_game.room_id) then raise exception 'GAME_NOT_AVAILABLE'; end if;
 if not exists(select 1 from public.game_players where session_id=p_session_id and user_id=v_user) then raise exception 'NOT_A_PLAYER'; end if;
 if p_action_key is null or p_action_key not in ('vote','answer','clue','guess') or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'INVALID_ACTION'; end if;
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
declare v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype; v_wolf uuid; v_voted uuid; v_winner uuid; v_prompt private.game_session_secrets%rowtype; v_player record; v_points integer; v_xp integer; v_coins integer; v_correct integer; v_result jsonb:='{}'::jsonb;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id and status='active' for update;
 if not found or v_game.created_by<>v_user or not private.is_room_member(v_game.room_id) then raise exception 'HOST_ONLY'; end if;
 if v_game.game_key='wolf' then
   select user_id into v_wolf from private.game_player_secrets where session_id=p_session_id and secret_role='wolf';
   select (payload->>'target_user_id')::uuid into v_voted from public.game_actions where session_id=p_session_id and action_key='vote' group by payload->>'target_user_id' order by count(*) desc,payload->>'target_user_id' limit 1;
   if v_voted=v_wolf then v_result:=jsonb_build_object('result','villagers_win','wolf',v_wolf); else v_result:=jsonb_build_object('result','wolf_wins','wolf',v_wolf); end if;
   for v_player in select user_id from public.game_players where session_id=p_session_id loop
     v_points:=case when v_voted=v_wolf and v_player.user_id<>v_wolf then 20 when v_voted is distinct from v_wolf and v_player.user_id=v_wolf then 30 else 5 end;
     update public.game_players set score=score+v_points where session_id=p_session_id and user_id=v_player.user_id;
   end loop;
 elsif v_game.game_key='who' then
   select (payload->>'target_user_id')::uuid into v_winner from public.game_actions where session_id=p_session_id and action_key='vote' group by payload->>'target_user_id' order by count(*) desc,payload->>'target_user_id' limit 1;
   if v_winner is not null then update public.game_players set score=score+15 where session_id=p_session_id and user_id=v_winner; end if;
   v_result:=jsonb_build_object('result','vote_complete','most_voted',v_winner);
 elsif v_game.game_key='ten_seconds' then
   select * into v_prompt from private.game_session_secrets where session_id=p_session_id;
   for v_player in select user_id,payload->>'text' as answer from public.game_actions where session_id=p_session_id and action_key='answer' loop
     select count(distinct lower(btrim(x))) into v_correct from regexp_split_to_table(v_player.answer,'[,،;؛]+') x
       where lower(btrim(x))=any(select lower(a) from unnest(v_prompt.accepted_answers) a);
     v_points:=least(coalesce(v_correct,0),3)*5;
     update public.game_players set score=score+v_points where session_id=p_session_id and user_id=v_player.user_id;
   end loop;
   v_result:=jsonb_build_object('result','answers_checked','prompt',v_prompt.prompt);
 elsif v_game.game_key='forbidden' then
   select * into v_prompt from private.game_session_secrets where session_id=p_session_id;
   for v_player in select user_id,payload->>'text' as clue from public.game_actions where session_id=p_session_id and action_key='clue' loop
     if not exists(select 1 from unnest(v_prompt.forbidden_words) w where lower(v_player.clue) like '%'||lower(w)||'%') then update public.game_players set score=score+10 where session_id=p_session_id and user_id=v_player.user_id; end if;
   end loop;
   for v_player in select user_id,payload->>'text' as answer from public.game_actions where session_id=p_session_id and action_key='guess' loop
     if lower(v_player.answer)=any(select lower(x) from unnest(v_prompt.accepted_answers) x) then update public.game_players set score=score+15 where session_id=p_session_id and user_id=v_player.user_id; end if;
   end loop;
   v_result:=jsonb_build_object('result','round_complete');
 end if;
 update public.game_sessions set status='completed',ended_at=now() where id=p_session_id;
 for v_player in select gp.user_id,gp.score from public.game_players gp where gp.session_id=p_session_id loop
   v_xp:=20+least(v_player.score,80); v_coins:=5+least(v_player.score/5,20);
   update public.profiles set xp=xp+v_xp,coins=coins+v_coins,level=1+floor(sqrt((xp+v_xp)::numeric/100))::int,games_played=games_played+1,total_score=total_score+v_player.score,wins=wins+case when v_player.score=(select max(score) from public.game_players where session_id=p_session_id) then 1 else 0 end where id=v_player.user_id;
   insert into public.player_achievements(user_id,achievement_id) values(v_player.user_id,'first_game') on conflict do nothing;
 end loop;
 return v_result||jsonb_build_object('leaderboard',(select jsonb_agg(jsonb_build_object('user_id',user_id,'score',score) order by score desc) from public.game_players where session_id=p_session_id));
end;
$$;

revoke all on function public.submit_party_action(uuid,text,jsonb) from public,anon;
revoke all on function public.finish_party_game(uuid) from public,anon;
grant execute on function public.submit_party_action(uuid,text,jsonb) to authenticated;
grant execute on function public.finish_party_game(uuid) to authenticated;
