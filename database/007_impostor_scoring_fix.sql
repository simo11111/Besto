-- Restore the original scorer for existing modes and isolate impostor scoring.
create or replace function public.finish_party_game(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype;
 v_wolf uuid; v_voted uuid; v_winner uuid; v_prompt private.game_session_secrets%rowtype;
 v_player record; v_points integer; v_xp integer; v_coins integer; v_correct integer;
 v_result jsonb:='{}'::jsonb;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id and status='active' for update;
 if not found or v_game.created_by<>v_user or not private.is_room_member(v_game.room_id) then raise exception 'HOST_ONLY'; end if;
 if v_game.game_key='impostor' then raise exception 'USE_IMPOSTOR_SCORER'; end if;
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
     if not exists(select 1 from unnest(v_prompt.forbidden_words) w where lower(v_player.clue) like '%'||lower(w)||'%') then
       update public.game_players set score=score+10 where session_id=p_session_id and user_id=v_player.user_id;
     end if;
   end loop;
   for v_player in select user_id,payload->>'text' as answer from public.game_actions where session_id=p_session_id and action_key='guess' loop
     if lower(v_player.answer)=any(select lower(x) from unnest(v_prompt.accepted_answers) x) then update public.game_players set score=score+15 where session_id=p_session_id and user_id=v_player.user_id; end if;
   end loop;
   v_result:=jsonb_build_object('result','round_complete');
 end if;
 update public.game_sessions set status='completed',ended_at=now() where id=p_session_id;
 for v_player in select gp.user_id,gp.score from public.game_players gp where gp.session_id=p_session_id loop
   v_xp:=20+least(v_player.score,80); v_coins:=5+least(v_player.score/5,20);
   update public.profiles set xp=xp+v_xp,coins=coins+v_coins,level=1+floor(sqrt((xp+v_xp)::numeric/100))::int,
     games_played=games_played+1,total_score=total_score+v_player.score,
     wins=wins+case when v_player.score=(select max(score) from public.game_players where session_id=p_session_id) then 1 else 0 end
     where id=v_player.user_id;
   insert into public.player_achievements(user_id,achievement_id) values(v_player.user_id,'first_game') on conflict do nothing;
 end loop;
 return v_result||jsonb_build_object('leaderboard',(select jsonb_agg(jsonb_build_object('user_id',user_id,'score',score) order by score desc) from public.game_players where session_id=p_session_id));
end;
$$;

create or replace function public.finish_impostor_game(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype; v_secret private.game_session_secrets%rowtype;
 v_impostor uuid; v_voted uuid; v_votes integer; v_players integer;
 v_player record; v_points integer; v_xp integer; v_coins integer; v_result jsonb:='{}'::jsonb;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id and status='active' for update;
 if not found or v_game.game_key<>'impostor' or v_game.created_by<>v_user or not private.is_room_member(v_game.room_id) then raise exception 'HOST_ONLY'; end if;
 select * into v_secret from private.game_session_secrets where session_id=p_session_id for update;
 if v_secret.phase<>'voting' then raise exception 'VOTING_NOT_OPEN'; end if;
 select count(*) into v_players from public.game_players where session_id=p_session_id;
 select count(*) into v_votes from public.game_actions where session_id=p_session_id and action_key='vote';
 if v_votes<>v_players then raise exception 'WAITING_FOR_VOTES'; end if;
 v_impostor:=v_secret.target_user_id;
 select (payload->>'target_user_id')::uuid into v_voted from public.game_actions
 where session_id=p_session_id and action_key='vote'
 group by payload->>'target_user_id' order by count(*) desc,payload->>'target_user_id' limit 1;
 if v_voted=v_impostor then v_result:=jsonb_build_object('result','impostor_caught','impostor',v_impostor,'word',v_secret.prompt);
 else v_result:=jsonb_build_object('result','impostor_escaped','impostor',v_impostor,'word',v_secret.prompt); end if;
 for v_player in select user_id from public.game_players where session_id=p_session_id loop
   v_points:=case when v_voted=v_impostor and v_player.user_id<>v_impostor then 20
                  when v_voted<>v_impostor and v_player.user_id=v_impostor then 35 else 5 end;
   update public.game_players set score=score+v_points where session_id=p_session_id and user_id=v_player.user_id;
 end loop;
 update private.game_session_secrets set phase='completed' where session_id=p_session_id;
 update public.game_sessions set status='completed',ended_at=now() where id=p_session_id;
 for v_player in select gp.user_id,gp.score from public.game_players gp where gp.session_id=p_session_id loop
   v_xp:=20+least(v_player.score,80); v_coins:=5+least(v_player.score/5,20);
   update public.profiles set xp=xp+v_xp,coins=coins+v_coins,level=1+floor(sqrt((xp+v_xp)::numeric/100))::int,
     games_played=games_played+1,total_score=total_score+v_player.score,
     wins=wins+case when v_player.score=(select max(score) from public.game_players where session_id=p_session_id) then 1 else 0 end
     where id=v_player.user_id;
   insert into public.player_achievements(user_id,achievement_id) values(v_player.user_id,'first_game') on conflict do nothing;
 end loop;
 return v_result||jsonb_build_object('leaderboard',(select jsonb_agg(jsonb_build_object('user_id',user_id,'score',score) order by score desc) from public.game_players where session_id=p_session_id));
end;
$$;

revoke all on function public.finish_impostor_game(uuid) from public,anon;
grant execute on function public.finish_impostor_game(uuid) to authenticated;
