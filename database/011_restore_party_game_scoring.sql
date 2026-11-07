-- Restore the shared scoring path for non-impostor party games.
-- Migration 006 accidentally replaced this function with a self-call for these modes.
create or replace function public.finish_party_game(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 v_user uuid:=auth.uid();
 v_game public.game_sessions%rowtype;
 v_secret private.game_session_secrets%rowtype;
 v_wolf uuid; v_voted uuid; v_winner uuid;
 v_player record; v_points integer; v_xp integer; v_coins integer;
 v_result jsonb:='{}'::jsonb;
 v_players integer; v_actions integer;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id and status='active' for update;
 if not found or v_game.created_by<>v_user or not private.is_room_member(v_game.room_id) then raise exception 'HOST_ONLY'; end if;
 select count(*) into v_players from public.game_players where session_id=p_session_id;
 if v_players<1 then raise exception 'NO_PLAYERS'; end if;

 if v_game.game_key='wolf' then
   select count(*) into v_actions from public.game_actions where session_id=p_session_id and action_key='vote';
   if v_actions<>v_players then raise exception 'WAITING_FOR_VOTES'; end if;
   select user_id into v_wolf from private.game_player_secrets where session_id=p_session_id and secret_role='wolf';
   select (payload->>'target_user_id')::uuid into v_voted
   from public.game_actions where session_id=p_session_id and action_key='vote'
   group by payload->>'target_user_id' order by count(*) desc,payload->>'target_user_id' limit 1;
   if v_voted=v_wolf then
     v_result:=jsonb_build_object('result','villagers_win','wolf',v_wolf);
   else
     v_result:=jsonb_build_object('result','wolf_wins','wolf',v_wolf);
   end if;
   for v_player in select user_id from public.game_players where session_id=p_session_id loop
     v_points:=case when v_voted=v_wolf and v_player.user_id<>v_wolf then 20
                    when v_voted is distinct from v_wolf and v_player.user_id=v_wolf then 30 else 5 end;
     update public.game_players set score=score+v_points where session_id=p_session_id and user_id=v_player.user_id;
   end loop;
 elsif v_game.game_key='who' then
   select count(*) into v_actions from public.game_actions where session_id=p_session_id and action_key='vote';
   if v_actions<>v_players then raise exception 'WAITING_FOR_VOTES'; end if;
   select (payload->>'target_user_id')::uuid into v_winner
   from public.game_actions where session_id=p_session_id and action_key='vote'
   group by payload->>'target_user_id' order by count(*) desc,payload->>'target_user_id' limit 1;
   update public.game_players set score=score+15 where session_id=p_session_id and user_id=v_winner;
   v_result:=jsonb_build_object('result','vote_complete','most_voted',v_winner);
 elsif v_game.game_key='ten_seconds' then
   select * into v_secret from private.game_session_secrets where session_id=p_session_id;
   if v_secret.deadline_at is not null and now()<v_secret.deadline_at then raise exception 'TIME_REMAINING'; end if;
   for v_player in select user_id,payload->>'text' as answer from public.game_actions where session_id=p_session_id and action_key='answer' loop
     v_points:=case when lower(v_player.answer)=any(select lower(x) from unnest(v_secret.accepted_answers) x) then 10 else 0 end;
     update public.game_players set score=score+v_points where session_id=p_session_id and user_id=v_player.user_id;
   end loop;
   v_result:=jsonb_build_object('result','answers_checked','prompt',v_secret.prompt);
 elsif v_game.game_key='forbidden' then
   select * into v_secret from private.game_session_secrets where session_id=p_session_id;
   select count(*) into v_actions from public.game_actions where session_id=p_session_id and action_key='clue';
   if v_actions<1 then raise exception 'WAITING_FOR_CLUE'; end if;
   for v_player in select user_id,payload->>'text' as clue from public.game_actions where session_id=p_session_id and action_key='clue' loop
     if not exists(select 1 from unnest(v_secret.forbidden_words) w where lower(v_player.clue) like '%'||lower(w)||'%') then
       update public.game_players set score=score+10 where session_id=p_session_id and user_id=v_player.user_id;
     end if;
   end loop;
   for v_player in select user_id,payload->>'text' as answer from public.game_actions where session_id=p_session_id and action_key='guess' loop
     if lower(v_player.answer)=any(select lower(x) from unnest(v_secret.accepted_answers) x) then
       update public.game_players set score=score+15 where session_id=p_session_id and user_id=v_player.user_id;
     end if;
   end loop;
   v_result:=jsonb_build_object('result','round_complete','word',v_secret.prompt);
 else
   raise exception 'INVALID_GAME';
 end if;

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
end;
$$;
revoke all on function public.finish_party_game(uuid) from public,anon;
grant execute on function public.finish_party_game(uuid) to authenticated;
