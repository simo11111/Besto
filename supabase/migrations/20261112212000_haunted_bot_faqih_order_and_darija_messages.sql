do $migration$
declare v_definition text; v_old text; v_new text;
begin
 select pg_get_functiondef('public.run_haunted_bot_turns(uuid)'::regprocedure) into v_definition;
 v_old := $old$if v_game.game_mode='standard' and not exists(select 1 from public.haunted_night_actions where game_id=p_game_id and round=v_game.round and faqih_target is not null) then$old$;
 v_new := $new$if v_game.game_mode='standard'
   and exists(select 1 from public.haunted_night_actions where game_id=p_game_id and round=v_game.round and haunter_target is not null and not resolved)
   and not exists(select 1 from public.haunted_night_actions where game_id=p_game_id and round=v_game.round and faqih_target is not null) then$new$;
 if position(v_old in v_definition)=0 then raise exception 'Could not locate bot faqih phase condition'; end if;
 execute replace(v_definition,v_old,v_new);
 select pg_get_functiondef('public.resolve_haunted_vote(uuid)'::regprocedure) into v_definition;
 v_definition := replace(v_definition,'تعادل التصويت. غادي نعاودو التصويت لمدة 30 ثانية.','كاين تعادل فالأصوات. غادي نعاودو التصويت 30 ثانية.');
 v_definition := replace(v_definition,'بقى التعادل، ما تطرد حتى واحد.','بقى التعادل، وما خرج حتى واحد من المخيم.');
 v_definition := replace(v_definition,'تم طرد لاعب من المخيم.','خرج لاعب من المخيم.');
 execute v_definition;
 select pg_get_functiondef('public.resolve_haunted_night(uuid)'::regprocedure) into v_definition;
 v_definition := replace(v_definition,'لقينا واحد من اللاعبين ميت فالصباح.','لقينا واحد من سكان المخيم مات فالليل.');
 execute v_definition;
 select pg_get_functiondef('public.open_haunted_voting(uuid)'::regprocedure) into v_definition;
 v_definition := replace(v_definition,'تحل التصويت. عندكم 30 ثانية باش تختارو.','تحل التصويت. عندكم 30 ثانية، اختارو اللي شاكين فيه.');
 execute v_definition;
end;
$migration$;