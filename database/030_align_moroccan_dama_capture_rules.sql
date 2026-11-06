-- Moroccan/Algerian Dama: men capture forward only; promotion ends the capture sequence.
do $migration$
declare
  v_definition text;
  v_original_start text := '  if array_length(p_board,1) <> 64 or v_piece not in (1,2,3,4) then return; end if;';
  v_corrected_start text := '  if array_length(p_board,1) <> 64 or v_piece not in (1,2,3,4) then return; end if;
  if cardinality(p_captured)>0 and ((v_piece=1 and v_row=0) or (v_piece=2 and v_row=7)) then
    path:=p_path;
    captures:=p_captured;
    captured_kings:=p_captured_kings;
    return next;
    return;
  end if;';
  v_original_loop text := '  for v_dir in 1..4 loop';
  v_corrected_loop text := '  for v_dir in 1..4 loop
    if not v_is_king and ((p_player=1 and v_dr[v_dir]<>-1) or (p_player=2 and v_dr[v_dir]<>1)) then continue; end if;';
begin
  v_definition:=pg_get_functiondef('private.dama_capture_paths(integer[],integer,integer,integer,integer[],integer[],integer)'::regprocedure);
  if position(v_original_start in v_definition)=0 or position(v_original_loop in v_definition)=0 then
    raise exception 'Dama capture helper source did not match expected version';
  end if;
  v_definition:=replace(v_definition,v_original_start,v_corrected_start);
  v_definition:=replace(v_definition,v_original_loop,v_corrected_loop);
  execute v_definition;
end;
$migration$;