-- MIMOX: additive completion for Haunted Camp (migration 034).
-- The earlier 033 migration is already deployed; never reuse migration numbers.

create table if not exists public.games_catalog (
  id text primary key,
  name text not null,
  slug text not null unique,
  is_enabled boolean not null default false,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.games_catalog enable row level security;
drop policy if exists games_catalog_public_read on public.games_catalog;
create policy games_catalog_public_read on public.games_catalog
  for select to anon, authenticated using (true);
drop policy if exists games_catalog_admin_write on public.games_catalog;
create policy games_catalog_admin_write on public.games_catalog
  for all to authenticated
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'),'') = 'admin')
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'),'') = 'admin');
revoke all on public.games_catalog from anon, authenticated;
grant select on public.games_catalog to anon, authenticated;
grant insert, update, delete on public.games_catalog to authenticated;

insert into public.games_catalog(id,name,slug,is_enabled,config)
values (
  'haunted_camp',
  'ليلة فالخيمة — الفقيه والمسكون',
  'haunted_camp',
  true,
  '{"min_players":4,"max_players":10,"standard_min_players":5,"quick_players":4,"roles":["haunter","faqih","villager"]}'::jsonb
)
on conflict (id) do update
set name=excluded.name, slug=excluded.slug, config=excluded.config;

create or replace function private.guard_haunted_feature_flag()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if not exists (
    select 1 from public.games_catalog
    where id='haunted_camp' and is_enabled=true
  ) then
    raise exception 'اللعبة موقوفة مؤقتاً من الإدارة';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_haunted_feature_flag() from public, anon, authenticated;

drop trigger if exists haunted_feature_flag_guard on public.haunted_games;
create trigger haunted_feature_flag_guard
before insert on public.haunted_games
for each row execute function private.guard_haunted_feature_flag();

-- A room that has ended must return to the lobby on refresh, not trap players
-- in the previous End screen and prevent a fresh game.
create or replace function public.get_latest_haunted_game(p_room_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_game uuid;
begin
  if v_user is null then
    raise exception 'خاصك تدخل للحساب';
  end if;

  if not exists (
    select 1 from public.room_members
    where room_id=p_room_id and user_id=v_user
  ) then
    raise exception 'ما عندكش الحق تشوف هاد الغرفة';
  end if;

  select hg.id into v_game
  from public.haunted_games hg
  join public.haunted_players hp on hp.game_id=hg.id
  where hg.room_id=p_room_id
    and hp.user_id=v_user
    and hg.status <> 'ended'
  order by hg.created_at desc
  limit 1;

  return v_game;
end;
$$;
revoke all on function public.get_latest_haunted_game(uuid) from public, anon;
grant execute on function public.get_latest_haunted_game(uuid) to authenticated;

-- Award the premium currency exactly once per result row. The unique
-- (game_id,user_id) constraint makes retries idempotent.
create or replace function private.award_haunted_gems()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_gems integer := 0;
  v_game_ended_at timestamptz;
begin
  if new.won then
    v_gems := case new.role
      when 'haunter' then 3
      when 'faqih' then 3
      else 2
    end;
  end if;

  -- First win of the UTC day: +20 XP, once per player per day.
  if new.won then
    select coalesce(ended_at, created_at) into v_game_ended_at
    from public.haunted_games where id=new.game_id;

    if not exists (
      select 1
      from public.haunted_results hr
      join public.haunted_games hg on hg.id=hr.game_id
      where hr.user_id=new.user_id
        and hr.won=true
        and hr.game_id<>new.game_id
        and (coalesce(hg.ended_at,hg.created_at) at time zone 'utc')::date
            = (coalesce(v_game_ended_at,now()) at time zone 'utc')::date
    ) then
      update public.profiles set xp=xp+20, total_score=total_score+20,
        level=1+floor(sqrt((xp+20)::numeric/100))::int, updated_at=now()
      where id=new.user_id;
    end if;
  end if;

  if v_gems > 0 then
    update public.profiles set gems=coalesce(gems,0)+v_gems, updated_at=now()
    where id=new.user_id;
  end if;
  return new;
end;
$$;
revoke all on function private.award_haunted_gems() from public, anon, authenticated;

drop trigger if exists haunted_result_currency_award on public.haunted_results;
create trigger haunted_result_currency_award
after insert on public.haunted_results
for each row execute function private.award_haunted_gems();

create index if not exists haunted_games_active_room_idx
  on public.haunted_games(room_id,created_at desc) where status <> 'ended';
