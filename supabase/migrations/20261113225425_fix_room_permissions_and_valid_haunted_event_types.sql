grant execute on function public.prune_stale_room_members(uuid) to authenticated;
grant select on public.cosmetic_catalog to authenticated;
grant select on public.player_inventory to authenticated;

create or replace function private.close_empty_room_after_member_delete()
returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  update public.haunted_players hp
  set left_at=coalesce(hp.left_at,now()),is_alive=false
  from public.haunted_games hg
  where hp.game_id=hg.id and hg.room_id=old.room_id and hp.user_id=old.user_id
    and hp.is_bot=false and hp.left_at is null and hg.status<>'ended';

  if not exists(select 1 from public.room_members rm where rm.room_id=old.room_id) then
    update public.rooms set status='closed',last_activity_at=now()
    where id=old.room_id and status<>'closed';
    update public.haunted_games
    set status='ended',winner=null,voting_open=false,phase_deadline_at=now(),bot_next_action_at=null
    where room_id=old.room_id and status<>'ended';
  end if;
  return old;
end;
$function$;

create or replace function private.notify_haunted_faqih_turn()
returns trigger language plpgsql security definer set search_path to ''
as $function$
begin
  if new.haunter_target is not null
     and (tg_op='INSERT' or old.haunter_target is distinct from new.haunter_target) then
    update public.haunted_games
    set phase_deadline_at=now()+interval '30 seconds',bot_next_action_at=null
    where id=new.game_id and status='night';
    -- faqih_turn_opened is not in the event constraint; bot_chat is an allowed event.
    insert into public.haunted_events(game_id,round,event_type,payload)
    values(new.game_id,new.round,'bot_chat',
      jsonb_build_object('message','المسكون اختار الضحية. دابا جا دور الفقيه.','system',true,'role_turn','faqih'));
  end if;
  return new;
end;
$function$;
