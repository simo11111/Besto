-- Authorize private direct-message Realtime channels only for accepted friends.
create or replace function private.is_dm_participant_topic(p_topic text)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_sender uuid;
  v_recipient uuid;
  v_user uuid := auth.uid();
begin
  if v_user is null or p_topic !~ '^dm:[0-9a-fA-F-]{36}:[0-9a-fA-F-]{36}$' then return false; end if;
  v_sender := split_part(p_topic,':',2)::uuid;
  v_recipient := split_part(p_topic,':',3)::uuid;
  if v_user not in (v_sender,v_recipient) then return false; end if;
  return exists (
    select 1 from public.friendships f
    where f.status='accepted'
      and ((f.requester_id=v_sender and f.addressee_id=v_recipient)
        or (f.requester_id=v_recipient and f.addressee_id=v_sender))
  );
exception when invalid_text_representation then
  return false;
end;
$function$;

revoke all on function private.is_dm_participant_topic(text) from public,anon;
grant execute on function private.is_dm_participant_topic(text) to authenticated;

drop policy if exists "DM participants receive private typing" on realtime.messages;
create policy "DM participants receive private typing"
  on realtime.messages for select to authenticated
  using (private.is_dm_participant_topic(realtime.topic()));

drop policy if exists "DM participants send private typing" on realtime.messages;
create policy "DM participants send private typing"
  on realtime.messages for insert to authenticated
  with check (private.is_dm_participant_topic(realtime.topic()));
