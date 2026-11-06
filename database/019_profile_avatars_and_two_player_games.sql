-- MIMOX profile avatars and two-player text-first game support.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('avatars','avatars',true,5242880,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Avatar images are publicly readable" on storage.objects;
create policy "Avatar images are publicly readable" on storage.objects for select using (bucket_id='avatars');
drop policy if exists "Users upload their own avatar" on storage.objects;
create policy "Users upload their own avatar" on storage.objects for insert to authenticated with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Users update their own avatar" on storage.objects;
create policy "Users update their own avatar" on storage.objects for update to authenticated using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text) with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

create or replace function public.update_my_profile(p_username text,p_bio text,p_avatar_url text default null)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_username is null or p_username !~ '^[A-Za-z0-9_]{3,20}$' then raise exception 'INVALID_USERNAME'; end if;
 if p_bio is null or char_length(p_bio)>120 then raise exception 'INVALID_BIO'; end if;
 if p_avatar_url is not null and (length(p_avatar_url)>2048 or p_avatar_url not like 'https://gtsdrmfvtialuxhfxtvz.supabase.co/storage/v1/object/public/avatars/%') then raise exception 'INVALID_AVATAR_URL'; end if;
 update public.profiles set username=p_username,bio=p_bio,avatar_url=coalesce(p_avatar_url,avatar_url),updated_at=now() where id=v_user;
end;
$function$;
revoke all on function public.update_my_profile(text,text,text) from public,anon;
grant execute on function public.update_my_profile(text,text,text) to authenticated;

create or replace function public.start_party_game(p_room_id uuid,p_game_key text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare
 v_user uuid:=auth.uid(); v_session uuid; v_prompt public.game_prompts%rowtype;
 v_target uuid; v_player_count integer;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_game_key not in ('wolf','who','forbidden','ten_seconds','impostor') then raise exception 'INVALID_GAME'; end if;
 if not private.is_room_member(p_room_id) then raise exception 'NOT_ROOM_MEMBER'; end if;
 perform 1 from public.rooms where id=p_room_id for update;
 if not exists(select 1 from public.room_members where room_id=p_room_id and user_id=v_user and role in ('owner','moderator')) then raise exception 'HOST_ONLY'; end if;
 select count(*) into v_player_count from public.room_members where room_id=p_room_id;
 if exists(select 1 from public.game_sessions where room_id=p_room_id and status='active') then raise exception 'GAME_ALREADY_ACTIVE'; end if;
 if p_game_key in ('impostor','wolf') and v_player_count<4 then raise exception 'NEED_FOUR_PLAYERS'; end if;
 if p_game_key='forbidden' and v_player_count<3 then raise exception 'NEED_THREE_PLAYERS'; end if;
 if p_game_key in ('who','ten_seconds') and v_player_count<2 then raise exception 'NEED_MORE_PLAYERS'; end if;
 insert into public.game_sessions(room_id,game_key,created_by) values(p_room_id,p_game_key,v_user) returning id into v_session;
 insert into public.game_players(session_id,user_id) select v_session,user_id from public.room_members where room_id=p_room_id;
 if p_game_key='wolf' then
  select user_id into v_target from public.game_players where session_id=v_session order by random() limit 1;
  insert into private.game_player_secrets(session_id,user_id,secret_role)
  select v_session,user_id,case when user_id=v_target then 'wolf' else 'villager' end from public.game_players where session_id=v_session;
 end if;
 if p_game_key in ('who','forbidden','ten_seconds','impostor') then
  select * into v_prompt from public.game_prompts where game_key=p_game_key and active order by random() limit 1;
  if not found then raise exception 'NO_GAME_PROMPTS'; end if;
  if p_game_key='impostor' then
   select user_id into v_target from public.game_players where session_id=v_session order by random() limit 1;
   insert into private.game_session_secrets(session_id,prompt,accepted_answers,forbidden_words,target_user_id,phase)
   values(v_session,v_prompt.prompt,v_prompt.accepted_answers,'{}'::text[],v_target,'asking');
   insert into private.game_player_secrets(session_id,user_id,secret_role)
   select v_session,user_id,case when user_id=v_target then 'impostor' else 'knows_word' end from public.game_players where session_id=v_session;
  else
   select user_id into v_target from public.game_players where session_id=v_session order by random() limit 1;
   insert into private.game_session_secrets(session_id,prompt,accepted_answers,forbidden_words,target_user_id,deadline_at)
   values(v_session,v_prompt.prompt,v_prompt.accepted_answers,v_prompt.forbidden_words,v_target,
     case when p_game_key='ten_seconds' then now()+interval '10 seconds' else null end);
  end if;
 end if;
 return v_session;
end;
$$;
revoke all on function public.start_party_game(uuid,text) from public,anon;
grant execute on function public.start_party_game(uuid,text) to authenticated;
