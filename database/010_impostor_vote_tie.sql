-- Resolve tied top votes explicitly instead of arbitrarily choosing one player.
create or replace function public.finish_impostor_game(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype; v_secret private.game_session_secrets%rowtype;
 v_impostor uuid; v_voted uuid; v_votes integer; v_players integer;
 v_top_votes integer; v_top_candidates integer;
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
 select max(vote_count),count(*) filter(where vote_count=(select max(vote_count) from (
   select count(*) as vote_count from public.game_actions where session_id=p_session_id and action_key='vote' group by payload->>'target_user_id'
 ) counts))
 into v_top_votes,v_top_candidates
 from (select count(*) as vote_count from public.game_actions where session_id=p_session_id and action_key='vote' group by payload->>'target_user_id') counts;
 if v_top_candidates=1 then
   select (payload->>'target_user_id')::uuid into v_voted
   from public.game_actions where session_id=p_session_id and action_key='vote'
   group by payload->>'target_user_id' having count(*)=v_top_votes limit 1;
 end if;
 if v_top_candidates>1 then
   v_result:=jsonb_build_object('result','vote_tied','impostor',v_impostor,'word',v_secret.prompt);
 elsif v_voted=v_impostor then
   v_result:=jsonb_build_object('result','impostor_caught','impostor',v_impostor,'word',v_secret.prompt);
 else
   v_result:=jsonb_build_object('result','impostor_escaped','impostor',v_impostor,'word',v_secret.prompt);
 end if;
 for v_player in select user_id from public.game_players where session_id=p_session_id loop
   v_points:=case when v_top_candidates=1 and v_voted=v_impostor and v_player.user_id<>v_impostor then 20
                  when (v_top_candidates>1 or v_voted is distinct from v_impostor) and v_player.user_id=v_impostor then 35 else 5 end;
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
