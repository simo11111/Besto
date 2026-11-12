do $migration$
declare v_definition text; v_old text; v_new text;
begin
 select pg_get_functiondef('public.get_haunted_game_state(uuid)'::regprocedure) into v_definition;
 v_old := $old$if v_role is null then raise exception 'ماشي لاعب فهاد اللعبة'; end if;$old$;
 v_new := $new$if v_role is null and v_game.status <> 'ended' then raise exception 'ماشي لاعب فهاد اللعبة'; end if;$new$;
 if position(v_old in v_definition)=0 then raise exception 'Could not locate non-player state guard'; end if;
 execute replace(v_definition,v_old,v_new);
end;
$migration$;