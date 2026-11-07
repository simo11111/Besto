-- MIMOX Phase 1: reproducible social schema and Ten Seconds answer repair.
-- Idempotent; safe after migrations 001-019 and on the existing project.

create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  addressee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friendships_not_self check (requester_id <> addressee_id),
  constraint friendships_request_pair_unique unique (requester_id, addressee_id)
);
create index if not exists friendships_addressee_status_idx on public.friendships(addressee_id,status,created_at desc);
create index if not exists friendships_requester_status_idx on public.friendships(requester_id,status,created_at desc);

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 1500),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint direct_messages_not_self check (sender_id <> recipient_id)
);
create index if not exists direct_messages_conversation_idx on public.direct_messages(sender_id,recipient_id,created_at desc);
create index if not exists direct_messages_recipient_idx on public.direct_messages(recipient_id,created_at desc);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  kind text not null,
  title text not null,
  body text not null default '',
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_inbox_idx on public.notifications(user_id,created_at desc);

alter table public.friendships enable row level security;
alter table public.direct_messages enable row level security;
alter table public.notifications enable row level security;
drop policy if exists "friendships participants can read" on public.friendships;
create policy "friendships participants can read" on public.friendships for select to authenticated using (auth.uid() in (requester_id,addressee_id));
drop policy if exists "direct message participants can read" on public.direct_messages;
drop policy if exists "friends can read direct messages" on public.direct_messages;
create policy "friends can read direct messages" on public.direct_messages for select to authenticated
using (auth.uid() in (sender_id,recipient_id) and exists (
  select 1 from public.friendships f where f.status='accepted'
  and ((f.requester_id=direct_messages.sender_id and f.addressee_id=direct_messages.recipient_id)
    or (f.requester_id=direct_messages.recipient_id and f.addressee_id=direct_messages.sender_id))
));
drop policy if exists "friends can send direct messages" on public.direct_messages;
create policy "friends can send direct messages" on public.direct_messages for insert to authenticated
with check (sender_id=auth.uid() and exists (
  select 1 from public.friendships f where f.status='accepted'
  and ((f.requester_id=direct_messages.sender_id and f.addressee_id=direct_messages.recipient_id)
    or (f.requester_id=direct_messages.recipient_id and f.addressee_id=direct_messages.sender_id))
));
drop policy if exists "recipients mark messages read" on public.direct_messages;
create policy "recipients mark messages read" on public.direct_messages for update to authenticated
using (recipient_id=auth.uid()) with check (recipient_id=auth.uid());

drop policy if exists "users read own notifications" on public.notifications;
create policy "users read own notifications" on public.notifications for select to authenticated using (user_id=auth.uid());
drop policy if exists "users insert notifications as actor" on public.notifications;
create policy "users insert notifications as actor" on public.notifications for insert to authenticated with check (actor_id=auth.uid());
drop policy if exists "users update own notifications" on public.notifications;
create policy "users update own notifications" on public.notifications for update to authenticated
using (user_id=auth.uid()) with check (user_id=auth.uid());

revoke all on public.friendships,public.direct_messages,public.notifications from anon;
revoke insert,update,delete on public.friendships from authenticated;
revoke insert,update on public.direct_messages,public.notifications from authenticated;
grant select on public.friendships to authenticated;
grant select on public.direct_messages,public.notifications to authenticated;
grant insert(sender_id,recipient_id,body) on public.direct_messages to authenticated;
grant update(read_at) on public.direct_messages to authenticated;
grant insert(user_id,actor_id,kind,title,body,payload) on public.notifications to authenticated;
grant update(read_at) on public.notifications to authenticated;

create or replace function public.decline_friend_request(p_request_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $function$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  delete from public.friendships where id=p_request_id and addressee_id=auth.uid() and status='pending';
  return found;
end;
$function$;
revoke all on function public.decline_friend_request(uuid) from public,anon;
grant execute on function public.decline_friend_request(uuid) to authenticated;

-- The previous seed stored A/B/C/D while the client submits the selected option text.
update public.game_prompts set accepted_answers=array['المريخ']::text[] where id=58 and game_key='ten_seconds';
update public.game_prompts set accepted_answers=array['3']::text[] where id=59 and game_key='ten_seconds';
update public.game_prompts set accepted_answers=array['طوكيو']::text[] where id=60 and game_key='ten_seconds';
update public.game_prompts set accepted_answers=array['الهادئ']::text[] where id=61 and game_key='ten_seconds';
update public.game_prompts set accepted_answers=array['366']::text[] where id=62 and game_key='ten_seconds';
update public.game_prompts set accepted_answers=array['الفهد']::text[] where id=63 and game_key='ten_seconds';
update public.game_prompts set accepted_answers=array['H2O']::text[] where id=64 and game_key='ten_seconds';
update public.game_prompts set accepted_answers=array['7']::text[] where id=65 and game_key='ten_seconds';

do $function$
begin
  begin alter publication supabase_realtime add table public.friendships; exception when duplicate_object then null; when undefined_object then null; end;
  begin alter publication supabase_realtime add table public.direct_messages; exception when duplicate_object then null; when undefined_object then null; end;
  begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; when undefined_object then null; end;
end;
$function$;
