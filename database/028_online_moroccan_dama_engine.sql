-- MIMOX Moroccan Dama: 8x8, 12 pieces per player, mandatory maximum capture.
alter table public.game_sessions drop constraint if exists game_sessions_game_key_check;
alter table public.game_sessions
  add constraint game_sessions_game_key_check
  check (game_key = any (array['wolf','who','forbidden','ten_seconds','impostor','connect4','dama']::text[]));

alter table public.duel_ratings drop constraint if exists duel_ratings_game_key_check;
alter table public.duel_ratings
  add constraint duel_ratings_game_key_check check (game_key in ('connect4','dama'));

create table if not exists public.dama_game_state (
  session_id uuid primary key references public.game_sessions(id) on delete cascade,
  board integer[] not null,
  first_player uuid not null references auth.users(id),
  second_player uuid not null references auth.users(id),
  current_player uuid not null references auth.users(id),
  winner_user_id uuid references auth.users(id),
  is_draw boolean not null default false,
  move_count integer not null default 0 check (move_count >= 0),
  quiet_moves integer not null default 0 check (quiet_moves between 0 and 50),
  version bigint not null default 0,
  updated_at timestamptz not null default now(),
  constraint dama_game_state_two_players check (first_player <> second_player),
  constraint dama_game_state_current_player check (current_player in (first_player, second_player)),
  constraint dama_game_state_board_size check (array_length(board, 1) = 64),
  constraint dama_game_state_board_values check (board <@ array[0,1,2,3,4]::integer[]),
  constraint dama_game_state_result check (not (is_draw and winner_user_id is not null))
);

alter table public.dama_game_state enable row level security;
drop policy if exists "Dama participants can read game state" on public.dama_game_state;
create policy "Dama participants can read game state"
  on public.dama_game_state for select to authenticated
  using (
    exists (
      select 1 from public.game_players gp
      where gp.session_id = dama_game_state.session_id
        and gp.user_id = (select auth.uid())
    )
  );
revoke all on table public.dama_game_state from anon, authenticated;
grant select on table public.dama_game_state to authenticated;

create or replace function private.dama_capture_paths(
  p_board integer[],
  p_player integer,
  p_from integer,
  p_position integer,
  p_captured integer[],
  p_path integer[],
  p_captured_kings integer
)
returns table(path integer[], captures integer[], captured_kings integer)
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_piece integer := p_board[p_position + 1];
  v_is_king boolean := v_piece in (3,4);
  v_row integer := p_position / 8;
  v_col integer := p_position % 8;
  v_dr integer[] := array[-1,-1,1,1];
  v_dc integer[] := array[-1,1,-1,1];
  v_dir integer;
  v_distance integer;
  v_landing_distance integer;
  v_enemy_row integer;
  v_enemy_col integer;
  v_landing_row integer;
  v_landing_col integer;
  v_enemy_index integer;
  v_enemy_distance integer;
  v_landing_index integer;
  v_enemy_piece integer;
  v_candidate_count integer := 0;
  v_returned boolean;
  v_next_board integer[];
  v_next_captured integer[];
  v_next_path integer[];
  v_nested record;
begin
  if array_length(p_board,1) <> 64 or v_piece not in (1,2,3,4) then return; end if;

  for v_dir in 1..4 loop
    if not v_is_king then
      v_enemy_row := v_row + v_dr[v_dir];
      v_enemy_col := v_col + v_dc[v_dir];
      v_landing_row := v_row + (2 * v_dr[v_dir]);
      v_landing_col := v_col + (2 * v_dc[v_dir]);
      if v_enemy_row < 0 or v_enemy_row > 7 or v_enemy_col < 0 or v_enemy_col > 7
         or v_landing_row < 0 or v_landing_row > 7 or v_landing_col < 0 or v_landing_col > 7 then
        continue;
      end if;

      v_enemy_index := v_enemy_row * 8 + v_enemy_col;
      v_landing_index := v_landing_row * 8 + v_landing_col;
      v_enemy_piece := p_board[v_enemy_index + 1];

      if p_board[v_landing_index + 1] = 0
         and array_position(p_captured, v_enemy_index) is null
         and ((p_player = 1 and v_enemy_piece in (2,4)) or (p_player = 2 and v_enemy_piece in (1,3))) then
        v_candidate_count := v_candidate_count + 1;
        v_next_board := p_board;
        v_next_board[p_position + 1] := 0;
        v_next_board[v_landing_index + 1] := v_piece;
        v_next_captured := array_append(p_captured, v_enemy_index);
        v_next_path := array_append(p_path, v_landing_index);
        v_returned := false;

        for v_nested in
          select * from private.dama_capture_paths(
            v_next_board, p_player, p_from, v_landing_index,
            v_next_captured, v_next_path,
            p_captured_kings + case when v_enemy_piece in (3,4) then 1 else 0 end
          )
        loop
          path := v_nested.path;
          captures := v_nested.captures;
          captured_kings := v_nested.captured_kings;
          return next;
          v_returned := true;
        end loop;

        if not v_returned then
          path := v_next_path;
          captures := v_next_captured;
          captured_kings := p_captured_kings + case when v_enemy_piece in (3,4) then 1 else 0 end;
          return next;
        end if;
      end if;
    else
      v_enemy_index := -1;
      v_enemy_distance := -1;

      for v_distance in 1..7 loop
        v_enemy_row := v_row + v_dr[v_dir] * v_distance;
        v_enemy_col := v_col + v_dc[v_dir] * v_distance;
        if v_enemy_row < 0 or v_enemy_row > 7 or v_enemy_col < 0 or v_enemy_col > 7 then exit; end if;
        v_landing_index := v_enemy_row * 8 + v_enemy_col;
        v_enemy_piece := p_board[v_landing_index + 1];
        if v_enemy_piece = 0 then continue; end if;
        if array_position(p_captured, v_landing_index) is not null then exit; end if;
        if (p_player = 1 and v_enemy_piece in (2,4)) or (p_player = 2 and v_enemy_piece in (1,3)) then
          v_enemy_index := v_landing_index;
          v_enemy_distance := v_distance;
        end if;
        exit;
      end loop;

      if v_enemy_index >= 0 then
        v_enemy_piece := p_board[v_enemy_index + 1];
        for v_landing_distance in (v_enemy_distance + 1)..7 loop
          v_landing_row := v_row + v_dr[v_dir] * v_landing_distance;
          v_landing_col := v_col + v_dc[v_dir] * v_landing_distance;
          if v_landing_row < 0 or v_landing_row > 7 or v_landing_col < 0 or v_landing_col > 7 then exit; end if;
          v_landing_index := v_landing_row * 8 + v_landing_col;
          if p_board[v_landing_index + 1] <> 0 then exit; end if;

          v_candidate_count := v_candidate_count + 1;
          v_next_board := p_board;
          v_next_board[p_position + 1] := 0;
          v_next_board[v_landing_index + 1] := v_piece;
          v_next_captured := array_append(p_captured, v_enemy_index);
          v_next_path := array_append(p_path, v_landing_index);
          v_returned := false;

          for v_nested in
            select * from private.dama_capture_paths(
              v_next_board, p_player, p_from, v_landing_index,
              v_next_captured, v_next_path,
              p_captured_kings + case when v_enemy_piece in (3,4) then 1 else 0 end
            )
          loop
            path := v_nested.path;
            captures := v_nested.captures;
            captured_kings := v_nested.captured_kings;
            return next;
            v_returned := true;
          end loop;

          if not v_returned then
            path := v_next_path;
            captures := v_next_captured;
            captured_kings := p_captured_kings + case when v_enemy_piece in (3,4) then 1 else 0 end;
            return next;
          end if;
        end loop;
      end if;
    end if;
  end loop;

  if v_candidate_count = 0 and cardinality(p_captured) > 0 then
    path := p_path;
    captures := p_captured;
    captured_kings := p_captured_kings;
    return next;
  end if;
end;
$function$;

create or replace function private.dama_legal_moves(p_board integer[], p_player integer)
returns table(from_idx integer, path integer[], captures integer[], captured_kings integer)
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_from integer;
  v_piece integer;
  v_seq record;
  v_item jsonb;
  v_all jsonb := '[]'::jsonb;
  v_max_captures integer := 0;
  v_max_kings integer := 0;
  v_row integer;
  v_col integer;
  v_dr integer;
  v_dc integer;
  v_distance integer;
  v_destination integer;
begin
  if array_length(p_board,1) <> 64 or p_player not in (1,2) then return; end if;

  for v_from in 0..63 loop
    v_piece := p_board[v_from + 1];
    if (p_player = 1 and v_piece not in (1,3)) or (p_player = 2 and v_piece not in (2,4)) then
      continue;
    end if;

    for v_seq in
      select * from private.dama_capture_paths(p_board,p_player,v_from,v_from,'{}'::integer[],'{}'::integer[],0)
    loop
      v_all := v_all || jsonb_build_array(jsonb_build_object(
        'from',v_from,'path',to_jsonb(v_seq.path),'captures',to_jsonb(v_seq.captures),'captured_kings',v_seq.captured_kings
      ));
      if cardinality(v_seq.captures) > v_max_captures then
        v_max_captures := cardinality(v_seq.captures);
        v_max_kings := v_seq.captured_kings;
      elsif cardinality(v_seq.captures) = v_max_captures then
        v_max_kings := greatest(v_max_kings,v_seq.captured_kings);
      end if;
    end loop;
  end loop;

  if jsonb_array_length(v_all) > 0 then
    for v_item in select value from jsonb_array_elements(v_all) as items(value) loop
      if jsonb_array_length(v_item->'captures') = v_max_captures
         and (v_item->>'captured_kings')::integer = v_max_kings then
        from_idx := (v_item->>'from')::integer;
        select array_agg(value::integer order by ord)
        into path
        from jsonb_array_elements_text(v_item->'path') with ordinality as values(value,ord);
        select array_agg(value::integer order by ord)
        into captures
        from jsonb_array_elements_text(v_item->'captures') with ordinality as values(value,ord);
        captured_kings := (v_item->>'captured_kings')::integer;
        return next;
      end if;
    end loop;
    return;
  end if;

  for v_from in 0..63 loop
    v_piece := p_board[v_from + 1];
    if (p_player = 1 and v_piece not in (1,3)) or (p_player = 2 and v_piece not in (2,4)) then
      continue;
    end if;
    v_row := v_from / 8;
    v_col := v_from % 8;

    if v_piece in (1,2) then
      v_dr := case when p_player = 1 then -1 else 1 end;
      for v_dc in -1..1 by 2 loop
        v_destination := (v_row + v_dr) * 8 + (v_col + v_dc);
        if v_row + v_dr between 0 and 7 and v_col + v_dc between 0 and 7
           and p_board[v_destination + 1] = 0 then
          from_idx := v_from;
          path := array[v_destination];
          captures := '{}'::integer[];
          captured_kings := 0;
          return next;
        end if;
      end loop;
    else
      for v_dr in -1..1 by 2 loop
        for v_dc in -1..1 by 2 loop
          for v_distance in 1..7 loop
            if v_row + v_dr * v_distance not between 0 and 7
               or v_col + v_dc * v_distance not between 0 and 7 then
              exit;
            end if;
            v_destination := (v_row + v_dr * v_distance) * 8 + (v_col + v_dc * v_distance);
            if p_board[v_destination + 1] <> 0 then exit; end if;
            from_idx := v_from;
            path := array[v_destination];
            captures := '{}'::integer[];
            captured_kings := 0;
            return next;
          end loop;
        end loop;
      end loop;
    end if;
  end loop;
end;
$function$;

create or replace function public.start_duel_game(p_room_id uuid, p_game_key text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_players uuid[];
  v_session uuid;
  v_board integer[] := array_fill(0,array[64]);
  v_row integer;
  v_col integer;
  v_idx integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_game_key not in ('connect4','dama') then raise exception 'INVALID_DUEL_GAME'; end if;
  select * into v_room from public.rooms where id=p_room_id and status='open' for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if not private.is_room_member(p_room_id) then raise exception 'NOT_ROOM_MEMBER'; end if;
  if not exists (select 1 from public.room_members where room_id=p_room_id and user_id=v_user and role in ('owner','moderator')) then raise exception 'HOST_ONLY'; end if;
  select array_agg(rm.user_id order by rm.joined_at,rm.user_id) into v_players
  from public.room_members rm where rm.room_id=p_room_id;
  if coalesce(cardinality(v_players),0) <> 2 then raise exception 'DUEL_REQUIRES_TWO_PLAYERS'; end if;
  if exists (select 1 from public.game_sessions where room_id=p_room_id and status='active') then raise exception 'GAME_ALREADY_ACTIVE'; end if;

  insert into public.game_sessions(room_id,game_key,created_by)
  values (p_room_id,p_game_key,v_user) returning id into v_session;
  insert into public.game_players(session_id,user_id) select v_session,unnest(v_players);

  if p_game_key='connect4' then
    insert into public.duel_game_state(session_id,first_player,second_player,current_player)
    values (v_session,v_players[1],v_players[2],v_players[1]);
  else
    for v_row in 0..2 loop
      for v_col in 0..7 loop
        if (v_row+v_col)%2=1 then
          v_idx:=v_row*8+v_col;
          v_board[v_idx+1]:=2;
        end if;
      end loop;
    end loop;
    for v_row in 5..7 loop
      for v_col in 0..7 loop
        if (v_row+v_col)%2=1 then
          v_idx:=v_row*8+v_col;
          v_board[v_idx+1]:=1;
        end if;
      end loop;
    end loop;
    insert into public.dama_game_state(session_id,board,first_player,second_player,current_player)
    values (v_session,v_board,v_players[1],v_players[2],v_players[1]);
  end if;
  return v_session;
end;
$function$;

create or replace function public.submit_dama_move(p_session_id uuid, p_path integer[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_game public.game_sessions%rowtype;
  v_state public.dama_game_state%rowtype;
  v_player integer;
  v_opponent integer;
  v_board integer[];
  v_from integer;
  v_to integer;
  v_piece integer;
  v_move_path integer[];
  v_move record;
  v_capture integer;
  v_capture_count integer;
  v_quiet integer;
  v_winner uuid;
  v_draw boolean := false;
  v_next uuid;
  v_first_score numeric;
  v_first_rating integer;
  v_second_rating integer;
  v_expected_first numeric;
  v_expected_second numeric;
  v_new_first_rating integer;
  v_new_second_rating integer;
  v_first_xp integer;
  v_second_xp integer;
  v_first_coins integer;
  v_second_coins integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_path is null or cardinality(p_path)<2 or cardinality(p_path)>13 then raise exception 'INVALID_MOVE_PATH'; end if;

  select * into v_game from public.game_sessions
  where id=p_session_id and game_key='dama' and status='active' for update;
  if not found then raise exception 'GAME_NOT_ACTIVE'; end if;

  select * into v_state from public.dama_game_state where session_id=p_session_id for update;
  if not found then raise exception 'GAME_STATE_NOT_FOUND'; end if;
  if v_user not in (v_state.first_player,v_state.second_player) then raise exception 'NOT_A_PLAYER'; end if;
  if v_state.current_player<>v_user then raise exception 'NOT_YOUR_TURN'; end if;

  v_player:=case when v_user=v_state.first_player then 1 else 2 end;
  v_opponent:=case when v_player=1 then 2 else 1 end;
  v_from:=p_path[1];
  v_move_path:=p_path[2:cardinality(p_path)];

  select * into v_move
  from private.dama_legal_moves(v_state.board,v_player)
  where from_idx=v_from and path=v_move_path
  limit 1;

  if not found then raise exception 'ILLEGAL_MOVE_OR_CAPTURE_PRIORITY'; end if;

  v_board:=v_state.board;
  v_piece:=v_board[v_from+1];
  v_board[v_from+1]:=0;
  v_capture_count:=cardinality(v_move.captures);
  foreach v_capture in array v_move.captures loop
    v_board[v_capture+1]:=0;
  end loop;
  v_to:=v_move_path[cardinality(v_move_path)];

  if v_piece=1 and v_to/8=0 then v_piece:=3; end if;
  if v_piece=2 and v_to/8=7 then v_piece:=4; end if;
  v_board[v_to+1]:=v_piece;

  v_quiet:=case when v_capture_count>0 or v_piece in (1,2) then 0 else least(50,v_state.quiet_moves+1) end;
  if not exists (
    select 1 from unnest(v_board) as pieces(piece)
    where (v_opponent=1 and piece in (1,3)) or (v_opponent=2 and piece in (2,4))
  ) then
    v_winner:=v_user;
  elsif not exists (select 1 from private.dama_legal_moves(v_board,v_opponent)) then
    v_winner:=v_user;
  elsif v_quiet>=50 then
    v_draw:=true;
  end if;
  v_next:=case when v_user=v_state.first_player then v_state.second_player else v_state.first_player end;

  update public.dama_game_state
  set board=v_board,current_player=v_next,winner_user_id=v_winner,is_draw=v_draw,
      move_count=v_state.move_count+1,quiet_moves=v_quiet,version=version+1,updated_at=now()
  where session_id=p_session_id;

  if v_winner is not null or v_draw then
    update public.game_sessions
    set status='completed',ended_at=now(),
        result=jsonb_build_object('winner_user_id',v_winner,'draw',v_draw,'move_count',v_state.move_count+1)
    where id=p_session_id and status='active';

    update public.game_players
    set score=case when v_winner is not null and user_id=v_winner then 3 when v_draw then 1 else 0 end
    where session_id=p_session_id;

    select coalesce((select rating from public.duel_ratings where user_id=v_state.first_player and game_key='dama'),1000) into v_first_rating;
    select coalesce((select rating from public.duel_ratings where user_id=v_state.second_player and game_key='dama'),1000) into v_second_rating;
    v_first_score:=case when v_draw then 0.5 when v_winner=v_state.first_player then 1.0 else 0.0 end;
    v_expected_first:=1.0/(1.0+power(10.0,(v_second_rating-v_first_rating)::numeric/400.0));
    v_expected_second:=1.0-v_expected_first;
    v_new_first_rating:=greatest(100,round(v_first_rating+32*(v_first_score-v_expected_first))::integer);
    v_new_second_rating:=greatest(100,round(v_second_rating+32*((1.0-v_first_score)-v_expected_second))::integer);

    insert into public.duel_ratings(user_id,game_key,rating,wins,losses,draws)
    values
      (v_state.first_player,'dama',v_new_first_rating,case when v_first_score=1 then 1 else 0 end,case when v_first_score=0 then 1 else 0 end,case when v_draw then 1 else 0 end),
      (v_state.second_player,'dama',v_new_second_rating,case when v_first_score=0 then 1 else 0 end,case when v_first_score=1 then 1 else 0 end,case when v_draw then 1 else 0 end)
    on conflict (user_id,game_key) do update
    set rating=excluded.rating,wins=duel_ratings.wins+excluded.wins,
        losses=duel_ratings.losses+excluded.losses,draws=duel_ratings.draws+excluded.draws,updated_at=now();

    v_first_xp:=case when v_draw then 20 when v_first_score=1 then 40 else 10 end;
    v_second_xp:=case when v_draw then 20 when v_first_score=0 then 40 else 10 end;
    v_first_coins:=case when v_draw then 10 when v_first_score=1 then 20 else 5 end;
    v_second_coins:=case when v_draw then 10 when v_first_score=0 then 20 else 5 end;

    update public.profiles p
    set xp=p.xp+case when p.id=v_state.first_player then v_first_xp else v_second_xp end,
        level=greatest(p.level,floor(sqrt((p.xp+case when p.id=v_state.first_player then v_first_xp else v_second_xp end)::numeric/100))::integer+1),
        coins=p.coins+case when p.id=v_state.first_player then v_first_coins else v_second_coins end,
        total_score=p.total_score+case when v_draw then 20 when (p.id=v_state.first_player and v_first_score=1) or (p.id=v_state.second_player and v_first_score=0) then 100 else 10 end,
        games_played=p.games_played+1,
        wins=p.wins+case when (p.id=v_state.first_player and v_first_score=1) or (p.id=v_state.second_player and v_first_score=0) then 1 else 0 end,
        updated_at=now()
    where p.id in (v_state.first_player,v_state.second_player);
  end if;

  return jsonb_build_object(
    'session_id',p_session_id,'move_count',v_state.move_count+1,
    'current_player',v_next,'winner_user_id',v_winner,'is_draw',v_draw,'version',v_state.version+1
  );
end;
$function$;

revoke all on function private.dama_capture_paths(integer[],integer,integer,integer,integer[],integer[],integer) from public,anon,authenticated;
revoke all on function private.dama_legal_moves(integer[],integer) from public,anon,authenticated;
revoke all on function public.submit_dama_move(uuid,integer[]) from public,anon;
grant execute on function public.submit_dama_move(uuid,integer[]) to authenticated;

do $publication$
begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='dama_game_state') then
    alter publication supabase_realtime add table public.dama_game_state;
  end if;
end;
$publication$;
