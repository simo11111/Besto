create or replace function public.leave_room(p_room_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare
 v_user uuid:=auth.uid(); v_owner uuid; v_next_owner uuid; v_removed integer;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select owner_id into v_owner from public.rooms where id=p_room_id for update;
 if not found then return false; end if;
 delete from public.room_members where room_id=p_room_id and user_id=v_user;
 get diagnostics v_removed=row_count;
 if v_removed=0 then return false; end if;
 if v_owner=v_user then
  select user_id into v_next_owner from public.room_members where room_id=p_room_id order by joined_at,user_id limit 1;
  if v_next_owner is null then
   update public.rooms set status='closed',last_activity_at=now() where id=p_room_id;
  else
   update public.room_members set role='owner' where room_id=p_room_id and user_id=v_next_owner;
   update public.rooms set owner_id=v_next_owner,last_activity_at=now() where id=p_room_id;
  end if;
 else
  update public.rooms set last_activity_at=now() where id=p_room_id;
 end if;
 return true;
end;
$$;
revoke all on function public.leave_room(uuid) from public,anon;
grant execute on function public.leave_room(uuid) to authenticated;
