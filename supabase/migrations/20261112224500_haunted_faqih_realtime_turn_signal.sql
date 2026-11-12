create or replace function private.notify_haunted_faqih_turn()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.haunter_target is not null
     and (tg_op = 'INSERT' or old.haunter_target is distinct from new.haunter_target) then
    insert into public.haunted_events(game_id, round, event_type, payload)
    values (
      new.game_id,
      new.round,
      'faqih_turn_opened',
      jsonb_build_object(
        'message', 'المسكون اختار الضحية. دابا جا دور الفقيه.',
        'role_turn', 'faqih'
      )
    );
  end if;
  return new;
end;
$function$;

revoke all on function private.notify_haunted_faqih_turn() from public, anon, authenticated;
drop trigger if exists haunted_faqih_turn_signal on public.haunted_night_actions;
create trigger haunted_faqih_turn_signal
after insert or update of haunter_target on public.haunted_night_actions
for each row execute function private.notify_haunted_faqih_turn();
