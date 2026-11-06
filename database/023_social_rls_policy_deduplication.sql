-- MIMOX Phase 1 hardening: consolidate equivalent social policies and
-- avoid per-row auth.uid() evaluation in the social RLS predicates.
-- This migration preserves the existing access rules and is safe on fresh installs.

drop policy if exists "Users view own friendships" on public.friendships;
drop policy if exists "friendships participants can read" on public.friendships;
create policy "friendships participants can read"
  on public.friendships
  for select
  to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));

drop policy if exists "friends can read direct messages" on public.direct_messages;
create policy "friends can read direct messages"
  on public.direct_messages
  for select
  to authenticated
  using (
    (select auth.uid()) in (sender_id, recipient_id)
    and exists (
      select 1
      from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester_id = direct_messages.sender_id and f.addressee_id = direct_messages.recipient_id)
          or
          (f.requester_id = direct_messages.recipient_id and f.addressee_id = direct_messages.sender_id)
        )
    )
  );

drop policy if exists "friends can send direct messages" on public.direct_messages;
create policy "friends can send direct messages"
  on public.direct_messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1
      from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester_id = direct_messages.sender_id and f.addressee_id = direct_messages.recipient_id)
          or
          (f.requester_id = direct_messages.recipient_id and f.addressee_id = direct_messages.sender_id)
        )
    )
  );

drop policy if exists "recipients mark messages read" on public.direct_messages;
create policy "recipients mark messages read"
  on public.direct_messages
  for update
  to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

drop policy if exists "users read own notifications" on public.notifications;
create policy "users read own notifications"
  on public.notifications
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "users insert notifications as actor" on public.notifications;
create policy "users insert notifications as actor"
  on public.notifications
  for insert
  to authenticated
  with check (actor_id = (select auth.uid()));

drop policy if exists "users update own notifications" on public.notifications;
create policy "users update own notifications"
  on public.notifications
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- 020 creates notifications_inbox_idx; the older equivalent index is redundant.
drop index if exists public.notifications_user_created_idx;
