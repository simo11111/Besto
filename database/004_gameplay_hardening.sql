-- DIMA PLAY competitive game hardening and realtime feeds.
alter table private.game_session_secrets add column if not exists deadline_at timestamptz;

insert into public.game_prompts(game_key,prompt,accepted_answers,forbidden_words) values
 ('who','شكون فينا يقدر يضحك فأسوأ وقت؟',array[]::text[],array[]::text[]),
 ('who','شكون فينا يضيع الطريق حتى مع GPS؟',array[]::text[],array[]::text[]),
 ('who','شكون فينا يولي مشهور بلا ما يقصد؟',array[]::text[],array[]::text[]),
 ('who','شكون فينا يقدر ياكل نفس الماكلة أسبوع كامل؟',array[]::text[],array[]::text[])
on conflict do nothing;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_name text;
begin
 v_name:=regexp_replace(coalesce(new.raw_user_meta_data->>'username',''),'[^A-Za-z0-9_]','','g');
 if char_length(v_name) not between 3 and 20 then v_name:='player_'||substr(replace(new.id::text,'-',''),1,12); end if;
 begin
   insert into public.profiles(id,username) values(new.id,v_name) on conflict(id) do nothing;
 exception when unique_violation then
   insert into public.profiles(id,username) values(new.id,'player_'||substr(replace(new.id::text,'-',''),1,12)) on conflict(id) do nothing;
 end;
 return new;
end;
$$;
revoke all on function public.handle_new_user() from public,anon,authenticated;

create or replace function public.start_party_game(p_room_id uuid,p_game_key text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_session uuid; v_prompt public.game_prompts%rowtype; v_target uuid; v_player_count integer;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_game_key not in ('wolf','who','forbidden','ten_seconds') then raise exception 'INVALID_GAME'; end if;
 if not private.is_room_member(p_room_id) then raise exception 'NOT_ROOM_MEMBER'; end if;
 if not exists(select 1 from public.room_members where room_id=p_room_id and user_id=v_user and role in ('owner','moderator')) then raise exception 'HOST_ONLY'; end if;
 select count(*) into v_player_count from public.room_members where room_id=p_room_id;
 if v_player_count<2 then raise exception 'NEED_MORE_PLAYERS'; end if;
 if exists(select 1 from public.game_sessions where room_id=p_room_id and status='active') then raise exception 'GAME_ALREADY_ACTIVE'; end if;
 insert into public.game_sessions(room_id,game_key,created_by) values(p_room_id,p_game_key,v_user) returning id into v_session;
 insert into public.game_players(session_id,user_id) select v_session,user_id from public.room_members where room_id=p_room_id;
 if p_game_key='wolf' then
   select user_id into v_target from public.game_players where session_id=v_session order by random() limit 1;
   insert into private.game_player_secrets(session_id,user_id,secret_role)
   select v_session,user_id,case when user_id=v_target then 'wolf' else 'villager' end from public.game_players where session_id=v_session;
 end if;
 if p_game_key in ('who','forbidden','ten_seconds') then
   select * into v_prompt from public.game_prompts where game_key=p_game_key and active order by random() limit 1;
   if not found then raise exception 'NO_GAME_PROMPTS'; end if;
   insert into private.game_session_secrets(session_id,prompt,accepted_answers,forbidden_words,target_user_id,deadline_at)
   values(v_session,v_prompt.prompt,v_prompt.accepted_answers,v_prompt.forbidden_words,
     case when p_game_key='forbidden' then (select user_id from public.game_players where session_id=v_session order by random() limit 1) else null end,
     case when p_game_key='ten_seconds' then now()+interval '10 seconds' else null end);
 end if;
 return v_session;
end;
$$;

create or replace function public.get_my_game_secret(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype; v_secret private.game_session_secrets%rowtype; v_role text;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id;
 if not found or not private.is_room_member(v_game.room_id) then raise exception 'NO_ACCESS'; end if;
 select secret_role into v_role from private.game_player_secrets where session_id=p_session_id and user_id=v_user;
 select * into v_secret from private.game_session_secrets where session_id=p_session_id;
 if v_game.game_key='wolf' then return jsonb_build_object('role',coalesce(v_role,'villager')); end if;
 if v_game.game_key='forbidden' and v_secret.target_user_id=v_user then return jsonb_build_object('prompt',v_secret.prompt,'forbidden_words',to_jsonb(v_secret.forbidden_words),'is_clue_giver',true); end if;
 if v_game.game_key='ten_seconds' then return jsonb_build_object('prompt',v_secret.prompt,'deadline_at',v_secret.deadline_at); end if;
 if v_game.game_key='who' then return jsonb_build_object('prompt',v_secret.prompt); end if;
 return '{}'::jsonb;
end;
$$;

create or replace function public.submit_party_action(p_session_id uuid,p_action_key text,p_payload jsonb)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype; v_id bigint; v_target uuid; v_text text; v_secret private.game_session_secrets%rowtype;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id and status='active';
 if not found or not private.is_room_member(v_game.room_id) then raise exception 'GAME_NOT_AVAILABLE'; end if;
 if not exists(select 1 from public.game_players where session_id=p_session_id and user_id=v_user) then raise exception 'NOT_A_PLAYER'; end if;
 if p_action_key not in ('vote','answer','clue','guess') or jsonb_typeof(p_payload)<>'object' then raise exception 'INVALID_ACTION'; end if;
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
 if v_game.game_key='wolf' and p_action_key<>'vote' then raise exception 'INVALID_ACTION_FOR_GAME'; end if;
 if v_game.game_key='who' and p_action_key<>'vote' then raise exception 'INVALID_ACTION_FOR_GAME'; end if;
 if v_game.game_key='ten_seconds' and p_action_key<>'answer' then raise exception 'INVALID_ACTION_FOR_GAME'; end if;
 if v_game.game_key='forbidden' and p_action_key not in ('clue','guess') then raise exception 'INVALID_ACTION_FOR_GAME'; end if;
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
 if not found or v_game.created_by<>v_user then raise exception 'HOST_ONLY'; end if;
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
     select count(distinct lower(btrim(x))) into v_correct
       from regexp_split_to_table(v_player.answer,'[,،;؛\n]+') x
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

-- Hide live game submissions from other players; each player can only read their own submitted actions.
drop policy if exists "participants read game actions" on public.game_actions;
create policy "players read own game actions" on public.game_actions for select to authenticated using(user_id=(select auth.uid()));

do $$
begin
 alter publication supabase_realtime add table public.game_sessions;
 alter publication supabase_realtime add table public.game_players;
 alter publication supabase_realtime add table public.game_actions;
exception when duplicate_object then null;
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
