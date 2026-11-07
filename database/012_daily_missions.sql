create table if not exists public.daily_missions (
 mission_key text primary key,
 name text not null,
 description text not null,
 target_type text not null check (target_type in ('play','win','daily_claim')),
 target_count integer not null default 1 check(target_count>0),
 coins_reward integer not null default 0 check(coins_reward>=0),
 xp_reward integer not null default 0 check(xp_reward>=0),
 icon text not null default '🎯',
 active boolean not null default true
);
create table if not exists public.daily_mission_claims (
 user_id uuid not null references auth.users(id) on delete cascade,
 mission_key text not null references public.daily_missions(mission_key) on delete cascade,
 claim_date date not null default ((now() at time zone 'utc')::date),
 claimed_at timestamptz not null default now(),
 primary key(user_id,mission_key,claim_date)
);
alter table public.daily_missions enable row level security;
alter table public.daily_mission_claims enable row level security;
drop policy if exists "signed in read daily missions" on public.daily_missions;
create policy "signed in read daily missions" on public.daily_missions for select to authenticated using(active=true);
revoke all on public.daily_mission_claims from anon,authenticated;
grant select on public.daily_missions to authenticated;
insert into public.daily_missions(mission_key,name,description,target_type,target_count,coins_reward,xp_reward,icon) values
 ('play_one','سخّن اللعب','كمل مباراة وحدة اليوم','play',1,40,25,'🎮'),
 ('play_three','مدمن التحدي','كمل 3 مباريات اليوم','play',3,100,60,'🔥'),
 ('win_one','جيبها فالشبكة','ربح مباراة وحدة اليوم','win',1,80,50,'🏆'),
 ('daily_bonus','المواظب','جمع المكافأة اليومية','daily_claim',1,30,20,'🎁')
on conflict(mission_key) do update set name=excluded.name,description=excluded.description,target_type=excluded.target_type,target_count=excluded.target_count,coins_reward=excluded.coins_reward,xp_reward=excluded.xp_reward,icon=excluded.icon,active=true;
create or replace function public.get_daily_missions()
returns table(mission_key text,name text,description text,icon text,progress integer,target_count integer,coins_reward integer,xp_reward integer,claimed boolean)
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_today date:=(now() at time zone 'utc')::date;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 return query
 select m.mission_key,m.name,m.description,m.icon,
 least(m.target_count,case
  when m.target_type='daily_claim' then case when exists(select 1 from public.daily_reward_claims d where d.user_id=v_user and d.claim_date=v_today) then 1 else 0 end
  when m.target_type='play' then (select count(*)::int from public.game_players gp join public.game_sessions gs on gs.id=gp.session_id where gp.user_id=v_user and gs.status='completed' and (gs.ended_at at time zone 'utc')::date=v_today)
  when m.target_type='win' then (select count(*)::int from public.game_players gp join public.game_sessions gs on gs.id=gp.session_id where gp.user_id=v_user and gs.status='completed' and (gs.ended_at at time zone 'utc')::date=v_today and gp.score=(select max(gp2.score) from public.game_players gp2 where gp2.session_id=gp.session_id))
  else 0 end),
 m.target_count,m.coins_reward,m.xp_reward,
 exists(select 1 from public.daily_mission_claims c where c.user_id=v_user and c.mission_key=m.mission_key and c.claim_date=v_today)
 from public.daily_missions m where m.active order by m.mission_key;
end;
$$;
create or replace function public.claim_daily_mission(p_mission_key text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_today date:=(now() at time zone 'utc')::date; v_m public.daily_missions%rowtype; v_progress integer:=0;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into v_m from public.daily_missions where mission_key=p_mission_key and active;
 if not found then raise exception 'MISSION_NOT_FOUND'; end if;
 perform 1 from auth.users where id=v_user for update;
 if exists(select 1 from public.daily_mission_claims where user_id=v_user and mission_key=p_mission_key and claim_date=v_today) then raise exception 'MISSION_ALREADY_CLAIMED'; end if;
 if v_m.target_type='daily_claim' then
  select count(*)::int into v_progress from public.daily_reward_claims where user_id=v_user and claim_date=v_today;
 elsif v_m.target_type='play' then
  select count(*)::int into v_progress from public.game_players gp join public.game_sessions gs on gs.id=gp.session_id where gp.user_id=v_user and gs.status='completed' and (gs.ended_at at time zone 'utc')::date=v_today;
 elsif v_m.target_type='win' then
  select count(*)::int into v_progress from public.game_players gp join public.game_sessions gs on gs.id=gp.session_id where gp.user_id=v_user and gs.status='completed' and (gs.ended_at at time zone 'utc')::date=v_today and gp.score=(select max(gp2.score) from public.game_players gp2 where gp2.session_id=gp.session_id);
 end if;
 if v_progress<v_m.target_count then raise exception 'MISSION_NOT_COMPLETE'; end if;
 insert into public.daily_mission_claims(user_id,mission_key,claim_date) values(v_user,p_mission_key,v_today);
 update public.profiles set coins=coins+v_m.coins_reward,xp=xp+v_m.xp_reward,level=1+floor(sqrt((xp+v_m.xp_reward)::numeric/100))::int,updated_at=now() where id=v_user;
 return jsonb_build_object('mission',p_mission_key,'coins',v_m.coins_reward,'xp',v_m.xp_reward);
end;
$$;
revoke all on function public.get_daily_missions() from public,anon;
revoke all on function public.claim_daily_mission(text) from public,anon;
grant execute on function public.get_daily_missions() to authenticated;
grant execute on function public.claim_daily_mission(text) to authenticated;