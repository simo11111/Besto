do $migration$
declare v_definition text; v_old text; v_new text;
begin
 select pg_get_functiondef('public.run_haunted_bot_turns(uuid)'::regprocedure) into v_definition;
 v_old := $old$or exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.is_alive and hp.role='faqih' and not exists(select 1 from public.haunted_night_actions na where na.game_id=p_game_id and na.round=v_game.round and na.faqih_target is not null))$old$;
 v_new := $new$or exists(select 1 from public.haunted_players hp where hp.game_id=p_game_id and hp.is_bot and hp.is_alive and hp.role='faqih'
      and exists(select 1 from public.haunted_night_actions na where na.game_id=p_game_id and na.round=v_game.round and na.haunter_target is not null and not na.resolved)
      and not exists(select 1 from public.haunted_night_actions na where na.game_id=p_game_id and na.round=v_game.round and na.faqih_target is not null))$new$;
 if position(v_old in v_definition)=0 then raise exception 'Could not locate faqih bot scheduling guard'; end if;
 execute replace(v_definition,v_old,v_new);
end;
$migration$;