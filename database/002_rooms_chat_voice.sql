-- DIMA PLAY core schema v2. Run after 001_initial.sql.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

alter table public.rooms drop constraint if exists rooms_code_check;
alter table public.rooms add constraint rooms_code_check check (code ~ '^[A-Z0-9]{6,12}$');
alter table public.profiles add column if not exists bio text not null default '' check (char_length(bio) <= 120);
alter table public.profiles add column if not exists xp bigint not null default 0 check (xp >= 0);
alter table public.profiles add column if not exists coins bigint not null default 100 check (coins >= 0);
alter table public.profiles add column if not exists level integer not null default 1 check (level >= 1);
alter table public.profiles add column if not exists wins integer not null default 0 check (wins >= 0);
alter table public.profiles add column if not exists games_played integer not null default 0 check (games_played >= 0);
alter table public.profiles add column if not exists equipped_frame text not null default 'default';
alter table public.profiles add column if not exists equipped_title text not null default 'لاعب جديد';
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_room_created_idx on public.chat_messages(room_id, created_at desc);

create table if not exists public.room_join_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index if not exists room_join_attempts_user_time_idx on public.room_join_attempts(user_id, attempted_at desc);

create or replace function private.is_room_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists(select 1 from public.room_members m where m.room_id=p_room_id and m.user_id=(select auth.uid()));
$$;
revoke all on function private.is_room_member(uuid) from public, anon;
grant execute on function private.is_room_member(uuid) to authenticated;

create or replace function private.is_room_member_topic(p_topic text)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
declare v_id text;
begin
  if p_topic !~ '^(room|voice|chat):[0-9a-fA-F-]{36}$' then return false; end if;
  v_id := split_part(p_topic, ':', 2);
  return private.is_room_member(v_id::uuid);
exception when invalid_text_representation then return false;
end;
$$;
revoke all on function private.is_room_member_topic(text) from public, anon;
grant execute on function private.is_room_member_topic(text) to authenticated;

-- Profiles are readable to signed-in users; sensitive progression fields are server-controlled.
alter table public.profiles enable row level security;
drop policy if exists "profiles readable by authenticated users" on public.profiles;
drop policy if exists "users create own profile" on public.profiles;
drop policy if exists "users update own profile" on public.profiles;
create policy "profiles visible to authenticated players" on public.profiles for select to authenticated using (true);
revoke insert, update, delete on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_name text;
begin
  v_name := regexp_replace(coalesce(new.raw_user_meta_data ->> 'username',''), '[^A-Za-z0-9_]', '', 'g');
  if char_length(v_name) not between 3 and 20 then
    v_name := 'player_' || substr(replace(new.id::text,'-',''),1,12);
  end if;
  insert into public.profiles(id,username) values(new.id,v_name)
  on conflict(id) do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Room visibility and roster.
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
drop policy if exists "authenticated users view public open rooms" on public.rooms;
drop policy if exists "owners view their rooms" on public.rooms;
drop policy if exists "members view their memberships" on public.room_members;
drop policy if exists "authenticated users view rooms they can access" on public.rooms;
drop policy if exists "room members view room roster" on public.room_members;
create policy "players view public rooms or their own rooms" on public.rooms for select to authenticated
using ((is_private=false and status<>'closed') or private.is_room_member(id));
create policy "room members view roster" on public.room_members for select to authenticated
using (private.is_room_member(room_id));
grant select on public.rooms, public.room_members to authenticated;

alter table public.chat_messages enable row level security;
drop policy if exists "room members read chat" on public.chat_messages;
create policy "members read room chat" on public.chat_messages for select to authenticated
using (private.is_room_member(room_id));
grant select on public.chat_messages to authenticated;
revoke insert, update, delete on public.chat_messages from anon, authenticated;

create or replace function public.create_room(p_name text,p_private boolean default false,p_max_players integer default 10)
returns table(room_id uuid,room_code text)
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_code text; v_room uuid; v_attempt integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 40 then raise exception 'INVALID_ROOM_NAME'; end if;
  if p_max_players is null or p_max_players not between 2 and 16 then raise exception 'INVALID_CAPACITY'; end if;
  perform 1 from auth.users where id=v_user for update;
  if (select count(*) from public.rooms where owner_id=v_user and created_at>now()-interval '1 hour')>=5 then raise exception 'ROOM_CREATE_RATE_LIMITED'; end if;
  for v_attempt in 1..5 loop
    v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
    begin
      insert into public.rooms(code,owner_id,name,is_private,max_players)
      values(v_code,v_user,btrim(p_name),coalesce(p_private,false),p_max_players) returning id into v_room;
      exit;
    exception when unique_violation then
      if v_attempt=5 then raise; end if;
    end;
  end loop;
  insert into public.room_members(room_id,user_id,role) values(v_room,v_user,'owner');
  return query select v_room,v_code;
end;
$$;

create or replace function public.join_room(p_code text)
returns table(room_id uuid,room_name text,room_code text)
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_room public.rooms%rowtype; v_count integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_code is null or p_code !~ '^[A-Za-z0-9]{6,12}$' then raise exception 'INVALID_ROOM_CODE'; end if;
  perform 1 from auth.users where id=v_user for update;
  delete from public.room_join_attempts where user_id=v_user and attempted_at<now()-interval '1 day';
  insert into public.room_join_attempts(user_id) values(v_user);
  select count(*) into v_count from public.room_join_attempts where user_id=v_user and attempted_at>now()-interval '1 minute';
  if v_count>10 then raise exception 'JOIN_RATE_LIMITED'; end if;
  select * into v_room from public.rooms r where r.code=upper(p_code) and r.status<>'closed' for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if exists(select 1 from public.room_members m where m.room_id=v_room.id and m.user_id=v_user) then
    return query select v_room.id,v_room.name,v_room.code; return;
  end if;
  select count(*) into v_count from public.room_members m where m.room_id=v_room.id;
  if v_count>=v_room.max_players then raise exception 'ROOM_FULL'; end if;
  insert into public.room_members(room_id,user_id,role) values(v_room.id,v_user,'player');
  update public.rooms set last_activity_at=now() where id=v_room.id;
  return query select v_room.id,v_room.name,v_room.code;
end;
$$;

create or replace function public.leave_room(p_room_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_removed integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  delete from public.room_members where room_id=p_room_id and user_id=v_user;
  get diagnostics v_removed=row_count;
  update public.rooms set last_activity_at=now() where id=p_room_id;
  return v_removed>0;
end;
$$;

create or replace function public.send_room_message(p_room_id uuid,p_body text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_count integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_body is null or char_length(btrim(p_body)) not between 1 and 500 then raise exception 'INVALID_MESSAGE'; end if;
  if not private.is_room_member(p_room_id) then raise exception 'NOT_ROOM_MEMBER'; end if;
  perform 1 from auth.users where id=v_user for update;
  select count(*) into v_count from public.chat_messages where room_id=p_room_id and user_id=v_user and created_at>now()-interval '1 minute';
  if v_count>=15 then raise exception 'MESSAGE_RATE_LIMITED'; end if;
  insert into public.chat_messages(room_id,user_id,body) values(p_room_id,v_user,btrim(p_body)) returning id into v_id;
  update public.rooms set last_activity_at=now() where id=p_room_id;
  return v_id;
end;
$$;

create or replace function public.update_my_profile(p_username text,p_bio text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_username is null or p_username !~ '^[A-Za-z0-9_]{3,20}$' then raise exception 'INVALID_USERNAME'; end if;
  if p_bio is null or char_length(p_bio)>120 then raise exception 'INVALID_BIO'; end if;
  update public.profiles set username=p_username,bio=p_bio,updated_at=now() where id=v_user;
end;
$$;

revoke all on function public.create_room(text,boolean,integer) from public,anon;
revoke all on function public.join_room(text) from public,anon;
revoke all on function public.leave_room(uuid) from public,anon;
revoke all on function public.send_room_message(uuid,text) from public,anon;
revoke all on function public.update_my_profile(text,text) from public,anon;
grant execute on function public.create_room(text,boolean,integer) to authenticated;
grant execute on function public.join_room(text) to authenticated;
grant execute on function public.leave_room(uuid) to authenticated;
grant execute on function public.send_room_message(uuid,text) to authenticated;
grant execute on function public.update_my_profile(text,text) to authenticated;

-- Realtime authorization is membership-scoped. Topics: room:<uuid>, voice:<uuid>, chat:<uuid>.
drop policy if exists "room members receive voice signals" on realtime.messages;
drop policy if exists "room members send voice signals" on realtime.messages;
create policy "room members receive private signals" on realtime.messages for select to authenticated
using (private.is_room_member_topic(realtime.topic()));
create policy "room members send private signals" on realtime.messages for insert to authenticated
with check (private.is_room_member_topic(realtime.topic()));

do $$
begin
  alter publication supabase_realtime add table public.chat_messages;
exception when duplicate_object then null;
end;
$$;

-- All public RPCs below run with fixed search_path and explicit auth checks.
