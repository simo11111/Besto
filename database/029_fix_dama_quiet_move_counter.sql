-- Count a move by a man as progress even when it promotes on the final square.
do $migration$
declare
  v_definition text;
  v_original text := 'v_quiet:=case when v_capture_count>0 or v_piece in (1,2) then 0 else least(50,v_state.quiet_moves+1) end;';
  v_corrected text := 'v_quiet:=case when v_capture_count>0 or v_state.board[v_from+1] in (1,2) then 0 else least(50,v_state.quiet_moves+1) end;';
begin
  v_definition := pg_get_functiondef('public.submit_dama_move(uuid,integer[])'::regprocedure);
  if position(v_original in v_definition)=0 then raise exception 'Expected quiet-move expression was not found'; end if;
  execute replace(v_definition,v_original,v_corrected);
end;
$migration$;