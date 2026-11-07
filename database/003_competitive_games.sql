-- DIMA PLAY competitive layer: XP, levels, daily rewards, cosmetics, achievements and party games.
alter table public.profiles add column if not exists total_score bigint not null default 0 check(total_score>=0);
alter table public.profiles add column if not exists streak_days integer not null default 0 check(streak_days>=0);
alter table public.profiles add column if not exists last_daily_claim date;

create table if not exists public.game_sessions(
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.rooms(id) on delete cascade,
 game_key text not null check(game_key in ('wolf','who','forbidden','ten_seconds')),
 status text not null default 'active' check(status in ('active','completed','cancelled')),
 round_number integer not null default 1 check(round_number between 1 and 20),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 ended_at timestamptz
);
create index if not exists game_sessions_room_created_idx on public.game_sessions(room_id,created_at desc);
create table if not exists public.game_players(
 session_id uuid not null references public.game_sessions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 score integer not null default 0,
 joined_at timestamptz not null default now(),
 primary key(session_id,user_id)
);
create table if not exists private.game_player_secrets(
 session_id uuid not null references public.game_sessions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 secret_role text,
 primary key(session_id,user_id)
);
create table if not exists private.game_session_secrets(
 session_id uuid primary key references public.game_sessions(id) on delete cascade,
 prompt text not null,
 accepted_answers text[] not null default '{}',
 forbidden_words text[] not null default '{}',
 target_user_id uuid references auth.users(id),
 phase text not null default 'playing'
);
create table if not exists public.game_actions(
 id bigint generated always as identity primary key,
 session_id uuid not null references public.game_sessions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 action_key text not null check(action_key in ('vote','answer','clue','guess')),
 payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists game_actions_session_user_idx on public.game_actions(session_id,user_id,action_key);

create table if not exists public.daily_reward_claims(
 user_id uuid not null references auth.users(id) on delete cascade,
 claim_date date not null,
 coins integer not null,
 xp integer not null,
 claimed_at timestamptz not null default now(),
 primary key(user_id,claim_date)
);
create table if not exists public.cosmetic_catalog(
 id text primary key,
 name text not null,
 category text not null check(category in ('frame','title')),
 price integer not null check(price>=0),
 rarity text not null default 'common',
 preview text not null
);
create table if not exists public.player_inventory(
 user_id uuid not null references auth.users(id) on delete cascade,
 cosmetic_id text not null references public.cosmetic_catalog(id),
 purchased_at timestamptz not null default now(),
 primary key(user_id,cosmetic_id)
);
create table if not exists public.achievements(
 id text primary key,
 name text not null,
 description text not null,
 icon text not null,
 xp_reward integer not null default 0,
 coin_reward integer not null default 0
);
create table if not exists public.player_achievements(
 user_id uuid not null references auth.users(id) on delete cascade,
 achievement_id text not null references public.achievements(id),
 unlocked_at timestamptz not null default now(),
 primary key(user_id,achievement_id)
);
create table if not exists public.game_prompts(
 id bigint generated always as identity primary key,
 game_key text not null,
 prompt text not null,
 accepted_answers text[] not null default '{}',
 forbidden_words text[] not null default '{}',
 active boolean not null default true
);

insert into public.cosmetic_catalog(id,name,category,price,rarity,preview) values
 ('frame_neon','إطار نيون','frame',250,'rare','💠'),
 ('frame_fire','إطار اللهب','frame',500,'epic','🔥'),
 ('frame_crown','إطار الملك','frame',900,'legendary','👑'),
 ('title_pro','PRO PLAYER','title',300,'rare','⚡'),
 ('title_legend','أسطورة اللمة','title',700,'epic','🏆'),
 ('title_wolf','صياد الذئاب','title',450,'rare','🐺')
on conflict(id) do nothing;
insert into public.achievements(id,name,description,icon,xp_reward,coin_reward) values
 ('first_game','أول لعيبة','كمل أول لعبة ديالك','🎮',50,25),
 ('first_win','أول فوز','ربح أول جولة','🏆',100,50),
 ('social','ولد اللمة','لعب 10 مباريات','🤝',150,100),
 ('streak3','مواظب','دخل 3 أيام متتابعة','🔥',100,75),
 ('collector','جامع الزينة','شري أول عنصر تجميلي','💎',50,25)
on conflict(id) do nothing;
insert into public.game_prompts(game_key,prompt,accepted_answers,forbidden_words) values
 ('ten_seconds','سمي 3 فواكه حمراء',array['تفاح','فراولة','كرز','رمان','بطيخ'],array[]::text[]),
 ('ten_seconds','سمي 3 مدن مغربية',array['فاس','الرباط','سلا','طنجة','مراكش','أكادير','وجدة','مكناس','تطوان'],array[]::text[]),
 ('ten_seconds','سمي 3 حيوانات كتعيش فالغابة',array['أسد','نمر','ذئب','ثعلب','دب','غزال'],array[]::text[]),
 ('forbidden','الكلمة هي: بيتزا',array['بيتزا'],array['عجين','فرن','جبن','طماطم']),
 ('forbidden','الكلمة هي: كرة القدم',array['كرة القدم','كورة','فوتبول'],array['مرمى','لاعب','حكم','هدف']),
 ('forbidden','الكلمة هي: هاتف',array['هاتف','تلفون','موبايل'],array['اتصال','شاشة','بطارية','تطبيق'])
on conflict do nothing;

alter table public.game_sessions enable row level security;
alter table public.game_players enable row level security;
alter table public.game_actions enable row level security;
alter table public.daily_reward_claims enable row level security;
alter table public.cosmetic_catalog enable row level security;
alter table public.player_inventory enable row level security;
alter table public.achievements enable row level security;
alter table public.player_achievements enable row level security;
alter table public.game_prompts enable row level security;
create policy "room members read game sessions" on public.game_sessions for select to authenticated using(private.is_room_member(room_id));
create policy "participants read game roster" on public.game_players for select to authenticated using(exists(select 1 from public.game_sessions s where s.id=session_id and private.is_room_member(s.room_id)));
create policy "participants read game actions" on public.game_actions for select to authenticated using(exists(select 1 from public.game_sessions s where s.id=session_id and private.is_room_member(s.room_id)));
create policy "signed in read cosmetic catalog" on public.cosmetic_catalog for select to authenticated using(true);
create policy "players read own inventory" on public.player_inventory for select to authenticated using(user_id=(select auth.uid()));
create policy "signed in read achievements" on public.achievements for select to authenticated using(true);
create policy "players read achievement list" on public.player_achievements for select to authenticated using(true);
create policy "signed in read game prompts" on public.game_prompts for select to authenticated using(false);
grant select on public.game_sessions,public.game_players,public.game_actions,public.cosmetic_catalog,public.player_inventory,public.achievements,public.player_achievements to authenticated;
revoke all on public.daily_reward_claims,public.game_prompts from anon,authenticated;
revoke insert,update,delete on public.game_sessions,public.game_players,public.game_actions,public.player_inventory,public.player_achievements from anon,authenticated;

create or replace function public.claim_daily_reward()
returns table(coins_awarded integer,xp_awarded integer,streak integer)
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_today date:=(now() at time zone 'utc')::date; v_streak integer:=1; v_coins integer; v_xp integer;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 perform 1 from auth.users where id=v_user for update;
 if exists(select 1 from public.daily_reward_claims where user_id=v_user and claim_date=v_today) then raise exception 'ALREADY_CLAIMED'; end if;
 select case when last_daily_claim=v_today-1 then streak_days+1 else 1 end into v_streak from public.profiles where id=v_user;
 v_streak:=coalesce(v_streak,1);
 v_coins:=50+least(v_streak,7)*10; v_xp:=25+least(v_streak,7)*5;
 insert into public.daily_reward_claims(user_id,claim_date,coins,xp) values(v_user,v_today,v_coins,v_xp);
 update public.profiles set coins=coins+v_coins,xp=xp+v_xp,level=1+floor(sqrt((xp+v_xp)::numeric/100))::int,streak_days=v_streak,last_daily_claim=v_today,updated_at=now() where id=v_user;
 return query select v_coins,v_xp,v_streak;
end;
$$;

create or replace function public.purchase_cosmetic(p_cosmetic_id text)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_item public.cosmetic_catalog%rowtype;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_item from public.cosmetic_catalog where id=p_cosmetic_id;
 if not found then raise exception 'ITEM_NOT_FOUND'; end if;
 perform 1 from auth.users where id=v_user for update;
 if exists(select 1 from public.player_inventory where user_id=v_user and cosmetic_id=p_cosmetic_id) then raise exception 'ALREADY_OWNED'; end if;
 update public.profiles set coins=coins-v_item.price where id=v_user and coins>=v_item.price;
 if not found then raise exception 'NOT_ENOUGH_COINS'; end if;
 insert into public.player_inventory(user_id,cosmetic_id) values(v_user,p_cosmetic_id);
 return true;
end;
$$;

create or replace function public.equip_cosmetic(p_cosmetic_id text)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_item public.cosmetic_catalog%rowtype;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select c.* into v_item from public.cosmetic_catalog c join public.player_inventory i on i.cosmetic_id=c.id where i.user_id=v_user and c.id=p_cosmetic_id;
 if not found then raise exception 'ITEM_NOT_OWNED'; end if;
 if v_item.category='frame' then update public.profiles set equipped_frame=p_cosmetic_id where id=v_user;
 else update public.profiles set equipped_title=v_item.name where id=v_user; end if;
 return true;
end;
$$;

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
 insert into public.game_sessions(room_id,game_key,created_by) values(p_room_id,p_game_key,v_user) returning id into v_session;
 insert into public.game_players(session_id,user_id) select v_session,user_id from public.room_members where room_id=p_room_id;
 if p_game_key='wolf' then
   select user_id into v_target from public.game_players where session_id=v_session order by random() limit 1;
   insert into private.game_player_secrets(session_id,user_id,secret_role) select v_session,user_id,case when user_id=v_target then 'wolf' else 'villager' end from public.game_players where session_id=v_session;
 end if;
 if p_game_key in ('forbidden','ten_seconds') then
   select * into v_prompt from public.game_prompts where game_key=p_game_key and active order by random() limit 1;
   if not found then raise exception 'NO_GAME_PROMPTS'; end if;
   insert into private.game_session_secrets(session_id,prompt,accepted_answers,forbidden_words,target_user_id)
   values(v_session,v_prompt.prompt,v_prompt.accepted_answers,v_prompt.forbidden_words,(select user_id from public.game_players where session_id=v_session order by random() limit 1));
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
 if v_game.game_key='ten_seconds' then return jsonb_build_object('prompt',v_secret.prompt); end if;
 return '{}'::jsonb;
end;
$$;

create or replace function public.submit_party_action(p_session_id uuid,p_action_key text,p_payload jsonb)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype; v_id bigint; v_target uuid; v_text text;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id and status='active';
 if not found or not private.is_room_member(v_game.room_id) then raise exception 'GAME_NOT_AVAILABLE'; end if;
 if not exists(select 1 from public.game_players where session_id=p_session_id and user_id=v_user) then raise exception 'NOT_A_PLAYER'; end if;
 if p_action_key not in ('vote','answer','clue','guess') or jsonb_typeof(p_payload)<>'object' then raise exception 'INVALID_ACTION'; end if;
 if exists(select 1 from public.game_actions where session_id=p_session_id and user_id=v_user and action_key=p_action_key) then raise exception 'ACTION_ALREADY_SENT'; end if;
 if p_action_key='vote' then
   begin v_target:=(p_payload->>'target_user_id')::uuid; exception when others then raise exception 'INVALID_TARGET'; end;
   if not exists(select 1 from public.game_players where session_id=p_session_id and user_id=v_target) then raise exception 'INVALID_TARGET'; end if;
 end if;
 if p_action_key in ('answer','clue','guess') then
   v_text:=btrim(coalesce(p_payload->>'text',''));
   if char_length(v_text) not between 1 and 240 then raise exception 'INVALID_TEXT'; end if;
   p_payload:=jsonb_build_object('text',v_text);
 end if;
 insert into public.game_actions(session_id,user_id,action_key,payload) values(p_session_id,v_user,p_action_key,p_payload) returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.finish_party_game(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_game public.game_sessions%rowtype; v_wolf uuid; v_voted uuid; v_winner uuid; v_prompt private.game_session_secrets%rowtype; v_player record; v_points integer; v_xp integer; v_coins integer; v_result jsonb:='{}'::jsonb;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_game from public.game_sessions where id=p_session_id and status='active' for update;
 if not found or v_game.created_by<>v_user then raise exception 'HOST_ONLY'; end if;
 if v_game.game_key='wolf' then
   select user_id into v_wolf from private.game_player_secrets where session_id=p_session_id and secret_role='wolf';
   select (payload->>'target_user_id')::uuid into v_voted from public.game_actions where session_id=p_session_id and action_key='vote' group by payload->>'target_user_id' order by count(*) desc,payload->>'target_user_id' limit 1;
   if v_voted=v_wolf then v_winner:=null; v_result:=jsonb_build_object('result','villagers_win','wolf',v_wolf); else v_winner:=v_wolf; v_result:=jsonb_build_object('result','wolf_wins','wolf',v_wolf); end if;
   for v_player in select user_id from public.game_players where session_id=p_session_id loop
     v_points:=case when v_voted=v_wolf and v_player.user_id<>v_wolf then 20 when v_voted<>v_wolf and v_player.user_id=v_wolf then 30 else 5 end;
     update public.game_players set score=score+v_points where session_id=p_session_id and user_id=v_player.user_id;
   end loop;
 elsif v_game.game_key='who' then
   select (payload->>'target_user_id')::uuid into v_winner from public.game_actions where session_id=p_session_id and action_key='vote' group by payload->>'target_user_id' order by count(*) desc,payload->>'target_user_id' limit 1;
   update public.game_players set score=score+15 where session_id=p_session_id and user_id=v_winner;
   v_result:=jsonb_build_object('result','vote_complete','most_voted',v_winner);
 elsif v_game.game_key='ten_seconds' then
   select * into v_prompt from private.game_session_secrets where session_id=p_session_id;
   for v_player in select user_id,payload->>'text' as answer from public.game_actions where session_id=p_session_id and action_key='answer' loop
     v_points:=case when lower(v_player.answer)=any(select lower(x) from unnest(v_prompt.accepted_answers) x) then 10 else 0 end;
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
   update public.profiles set xp=xp+v_xp,coins=coins+v_coins,level=1+floor(sqrt((xp+v_xp)::numeric/100))::int,games_played=games_played+1,total_score=total_score+v_player.score,wins=wins+case when v_player.score=(select max(score) from public.game_players where session_id=p_session_id) then 1 else 0 end where id=v_player.user_id;
   insert into public.player_achievements(user_id,achievement_id) values(v_player.user_id,'first_game') on conflict do nothing;
 end loop;
 return v_result||jsonb_build_object('leaderboard',(select jsonb_agg(jsonb_build_object('user_id',user_id,'score',score) order by score desc) from public.game_players where session_id=p_session_id));
end;
$$;

revoke all on function public.claim_daily_reward() from public,anon;
revoke all on function public.purchase_cosmetic(text) from public,anon;
revoke all on function public.equip_cosmetic(text) from public,anon;
revoke all on function public.start_party_game(uuid,text) from public,anon;
revoke all on function public.get_my_game_secret(uuid) from public,anon;
revoke all on function public.submit_party_action(uuid,text,jsonb) from public,anon;
revoke all on function public.finish_party_game(uuid) from public,anon;
grant execute on function public.claim_daily_reward() to authenticated;
grant execute on function public.purchase_cosmetic(text) to authenticated;
grant execute on function public.equip_cosmetic(text) to authenticated;
grant execute on function public.start_party_game(uuid,text) to authenticated;
grant execute on function public.get_my_game_secret(uuid) to authenticated;
grant execute on function public.submit_party_action(uuid,text,jsonb) to authenticated;
grant execute on function public.finish_party_game(uuid) to authenticated;
