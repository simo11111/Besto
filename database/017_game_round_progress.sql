create or replace function public.get_my_game_secret(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype; v_secret private.game_session_secrets%rowtype; v_role text;
 v_players integer; v_votes integer; v_asks integer; v_hints integer; v_guesses integer; v_answers integer;
 v_targets integer; v_received integer; v_asked boolean; v_voted boolean; v_hinted boolean; v_answered boolean; v_clue boolean;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id;
 if not found or not private.is_room_member(v_game.room_id) then raise exception 'NO_ACCESS'; end if;
 if not exists(select 1 from public.game_players where session_id=p_session_id and user_id=v_user) then raise exception 'NOT_A_PLAYER'; end if;
 select count(*) into v_players from public.game_players where session_id=p_session_id;
 select secret_role into v_role from private.game_player_secrets where session_id=p_session_id and user_id=v_user;
 select * into v_secret from private.game_session_secrets where session_id=p_session_id;
 select count(*) into v_votes from public.game_actions where session_id=p_session_id and action_key='vote';
 select count(*) into v_asks from public.game_actions where session_id=p_session_id and action_key='ask';
 select count(*) into v_hints from public.game_actions where session_id=p_session_id and action_key='hint';
 select count(distinct payload->>'target_user_id') into v_targets from public.game_actions where session_id=p_session_id and action_key='ask';
 select count(*) into v_guesses from public.game_actions where session_id=p_session_id and action_key='guess';
 select count(*) into v_answers from public.game_actions where session_id=p_session_id and action_key='answer';
 select exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key='ask') into v_asked;
 select exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key='vote') into v_voted;
 select exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key='hint') into v_hinted;
 select exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key='answer') into v_answered;
 select exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key='clue') into v_clue;
 select count(*) into v_received from public.game_actions where session_id=p_session_id and action_key='ask' and payload->>'target_user_id'=v_user::text;
 if v_game.game_key='wolf' then
  return jsonb_build_object('role',coalesce(v_role,'villager'),'votes_count',v_votes,'player_count',v_players,'has_voted',v_voted);
 elsif v_game.game_key='who' then
  return jsonb_build_object('prompt',v_secret.prompt,'votes_count',v_votes,'player_count',v_players,'has_voted',v_voted);
 elsif v_game.game_key='forbidden' then
  return jsonb_build_object('prompt',case when v_secret.target_user_id=v_user then v_secret.prompt else null end,
   'forbidden_words',case when v_secret.target_user_id=v_user then to_jsonb(v_secret.forbidden_words) else '[]'::jsonb end,
   'is_clue_giver',v_secret.target_user_id=v_user,'clue_submitted',exists(select 1 from public.game_actions where session_id=p_session_id and action_key='clue'),
   'guesses_count',v_guesses,'player_count',v_players,'has_guessed',exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key='guess'));
 elsif v_game.game_key='ten_seconds' then
  return jsonb_build_object('prompt',v_secret.prompt,'deadline_at',v_secret.deadline_at,'answers_count',v_answers,'player_count',v_players,'has_answered',v_answered);
 elsif v_game.game_key='impostor' then
  return jsonb_build_object('game_mode','impostor','role',coalesce(v_role,'knows_word'),'is_impostor',v_role='impostor',
   'word',case when v_role='impostor' then null else v_secret.prompt end,'phase',v_secret.phase,'player_count',v_players,
   'asks_count',v_asks,'votes_count',v_votes,'has_asked',v_asked,'has_voted',v_voted,
   'questions_received',v_received,'has_hint',v_hinted,'targets_count',v_targets,'hints_count',v_hints);
 end if;
 return '{}'::jsonb;
end;
$$;
revoke all on function public.get_my_game_secret(uuid) from public,anon;
grant execute on function public.get_my_game_secret(uuid) to authenticated;
