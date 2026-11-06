-- DIMA PLAY: transactional room operations, chat and private Realtime signaling.
-- Run after 001_initial.sql in the Supabase SQL editor.
create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_room_created_idx on public.chat_messages(room_id, created_at desc);
alter table public.chat_messages enable row level security;

drop policy if exists "room members read chat" on public.chat_messages;
create policy "room members read chat" on public.chat_messages for select to authenticated
using (exists (select 1 from public.room_members m where m.room_id = chat_messages.room_id and m.user_id = auth.uid()));

-- Remove permissive client-side mutation paths. All room/chat writes go through checked RPCs.
drop policy if exists "users create own profile" on public.profiles;
drop policy if exists "users update own profile" on public.profiles;
drop policy if exists "authenticated users view public open rooms" on public.rooms;
drop policy if exists "owners view their rooms" on public.rooms;
drop policy if exists "members view their memberships" on public.room_members;
create policy "authenticated users view rooms they can access" on public.rooms for select to authenticated
using ((is_private = false and status <> 'closed') or exists (
  select 1 from public.room_members m where m.room_id = rooms.id and m.user_id = auth.uid()
));
create policy "room members view room roster" on public.room_members for select to authenticated
using (exists (select 1 from public.room_members mine where mine.room_id = room_members.room_id and mine.user_id = auth.uid()));

create or replace function public.create_room(p_name text, p_private boolean default false, p_max_players integer default 10)
returns table(room_id uuid, room_code text)
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_code text; v_room uuid;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 40 then raise exception 'INVALID_ROOM_NAME' using errcode = '22023'; end if;
  if p_max_players is null or p_max_players not between 2 and 16 then raise exception 'INVALID_CAPACITY' using errcode = '22023'; end if;
  for attempt in 1..5 loop
    v_code := upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8));
    begin
      insert into public.rooms(code, owner_id, name, is_private, max_players)
      values (v_code, v_user, btrim(p_name), coalesce(p_private, false), p_max_players)
      returning id into v_room;
      exit;
    exception when unique_violation then
      if attempt = 5 then raise; end if;
    end;
  end loop;
  insert into public.room_members(room_id, user_id, role) values (v_room, v_user, 'owner');
  return query select v_room, v_code;
end;
$$;

create or replace function public.join_room(p_code text)
returns table(room_id uuid, room_name text, room_code text)
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_room public.rooms%rowtype; v_count integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if p_code is null or p_code !~ '^[A-Za-z0-9]{6,8}$' then raise exception 'INVALID_ROOM_CODE' using errcode = '22023'; end if;
  select * into v_room from public.rooms r where r.code = upper(p_code) and r.status <> 'closed' for update;
  if not found then raise exception 'ROOM_NOT_FOUND' using errcode = 'P0002'; end if;
  if exists(select 1 from public.room_members m where m.room_id = v_room.id and m.user_id = v_user) then
    return query select v_room.id, v_room.name, v_room.code; return;
  end if;
  select count(*) into v_count from public.room_members m where m.room_id = v_room.id;
  if v_count >= v_room.max_players then raise exception 'ROOM_FULL' using errcode = '23514'; end if;
  insert into public.room_members(room_id, user_id, role) values (v_room.id, v_user, 'player');
  update public.rooms set last_activity_at = now() where id = v_room.id;
  return query select v_room.id, v_room.name, v_room.code;
end;
$$;

create or replace function public.leave_room(p_room_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  delete from public.room_members where room_id = p_room_id and user_id = v_user;
  update public.rooms set last_activity_at = now() where id = p_room_id;
  return found;
end;
$$;

create or replace function public.send_room_message(p_room_id uuid, p_body text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_id uuid;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode = '28000'; end if;
  if p_body is null or char_length(btrim(p_body)) not between 1 and 500 then raise exception 'INVALID_MESSAGE' using errcode = '22023'; end if;
  if not exists(select 1 from public.room_members where room_id = p_room_id and user_id = v_user) then raise exception 'NOT_ROOM_MEMBER' using errcode = '42501'; end if;
  insert into public.chat_messages(room_id,user_id,body) values(p_room_id,v_user,btrim(p_body)) returning id into v_id;
  update public.rooms set last_activity_at = now() where id = p_room_id;
  return v_id;
end;
$$;

revoke all on function public.create_room(text,boolean,integer) from public, anon;
revoke all on function public.join_room(text) from public, anon;
revoke all on function public.leave_room(uuid) from public, anon;
revoke all on function public.send_room_message(uuid,text) from public, anon;
grant execute on function public.create_room(text,boolean,integer) to authenticated;
grant execute on function public.join_room(text) to authenticated;
grant execute on function public.leave_room(uuid) to authenticated;
grant execute on function public.send_room_message(uuid,text) to authenticated;

-- Private Realtime Broadcast topics use room:<room UUID>; only current room members may subscribe/publish.
drop policy if exists "room members receive voice signals" on realtime.messages;
drop policy if exists "room members send voice signals" on realtime.messages;
create policy "room members receive voice signals" on realtime.messages for select to authenticated
using (exists (select 1 from public.room_members m where m.room_id::text = split_part(realtime.topic(), ':', 2) and m.user_id = auth.uid()));
create policy "room members send voice signals" on realtime.messages for insert to authenticated
with check (exists (select 1 from public.room_members m where m.room_id::text = split_part(realtime.topic(), ':', 2) and m.user_id = auth.uid()));
