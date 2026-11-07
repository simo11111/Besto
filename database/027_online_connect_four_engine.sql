-- MIMOX online Four-in-a-Row: server-authoritative turns and Elo ratings.
alter table public.game_sessions drop constraint if exists game_sessions_game_key_check;
alter table public.game_sessions
  add constraint game_sessions_game_key_check
  check (game_key = any (array['wolf','who','forbidden','ten_seconds','impostor','connect4']::text[]));

create table if not exists public.duel_game_state (
  session_id uuid primary key references public.game_sessions(id) on delete cascade,
  board integer[] not null default array_fill(0, array[42]),
  first_player uuid not null references auth.users(id),
  second_player uuid not null references auth.users(id),
  current_player uuid not null references auth.users(id),
  winner_user_id uuid references auth.users(id),
  is_draw boolean not null default false,
  move_count integer not null default 0 check (move_count between 0 and 42),
  winning_cells integer[] not null default '{}'::integer[],
  version bigint not null default 0,
  updated_at timestamptz not null default now(),
  constraint duel_game_state_two_players check (first_player <> second_player),
  constraint duel_game_state_current_player check (current_player in (first_player, second_player)),
  constraint duel_game_state_board_size check (array_length(board, 1) = 42),
  constraint duel_game_state_board_values check (board <@ array[0,1,2]::integer[]),
  constraint duel_game_state_result check (not (is_draw and winner_user_id is not null))
);

create table if not exists public.duel_ratings (
  user_id uuid not null references auth.users(id) on delete cascade,
  game_key text not null check (game_key = 'connect4'),
  rating integer not null default 1000 check (rating >= 100),
  wins integer not null default 0 check (wins >= 0),
  losses integer not null default 0 check (losses >= 0),
  draws integer not null default 0 check (draws >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, game_key)
);

create index if not exists duel_ratings_leaderboard_idx
  on public.duel_ratings(game_key, rating desc, updated_at desc);

alter table public.duel_game_state enable row level security;
alter table public.duel_ratings enable row level security;

drop policy if exists "Duel participants can read game state" on public.duel_game_state;
create policy "Duel participants can read game state"
  on public.duel_game_state for select to authenticated
  using (
    exists (
      select 1 from public.game_players gp
      where gp.session_id = duel_game_state.session_id
        and gp.user_id = (select auth.uid())
    )
  );

drop policy if exists "Signed-in users can read duel ratings" on public.duel_ratings;
create policy "Signed-in users can read duel ratings"
  on public.duel_ratings for select to authenticated using (true);

revoke all on table public.duel_game_state from anon, authenticated;
grant select on table public.duel_game_state to authenticated;
revoke all on table public.duel_ratings from anon, authenticated;
grant select on table public.duel_ratings to authenticated;

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
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_game_key <> 'connect4' then raise exception 'INVALID_DUEL_GAME'; end if;
  select * into v_room from public.rooms where id = p_room_id and status = 'open' for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if not private.is_room_member(p_room_id) then raise exception 'NOT_ROOM_MEMBER'; end if;
  if not exists (select 1 from public.room_members where room_id = p_room_id and user_id = v_user and role in ('owner','moderator')) then raise exception 'HOST_ONLY'; end if;
  select array_agg(rm.user_id order by rm.joined_at, rm.user_id) into v_players from public.room_members rm where rm.room_id = p_room_id;
  if coalesce(cardinality(v_players), 0) <> 2 then raise exception 'DUEL_REQUIRES_TWO_PLAYERS'; end if;
  if exists (select 1 from public.game_sessions where room_id = p_room_id and status = 'active') then raise exception 'GAME_ALREADY_ACTIVE'; end if;
  insert into public.game_sessions(room_id, game_key, created_by) values (p_room_id, 'connect4', v_user) returning id into v_session;
  insert into public.game_players(session_id, user_id) select v_session, unnest(v_players);
  insert into public.duel_game_state(session_id, first_player, second_player, current_player) values (v_session, v_players[1], v_players[2], v_players[1]);
  return v_session;
end;
$function$;

create or replace function public.submit_duel_move(p_session_id uuid, p_column integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_game public.game_sessions%rowtype;
  v_state public.duel_game_state%rowtype;
  v_board integer[];
  v_row integer;
  v_col integer := p_column;
  v_idx integer;
  v_mark integer;
  v_dr integer[] := array[0,1,1,1];
  v_dc integer[] := array[1,0,1,-1];
  v_dir integer;
  v_sign integer;
  v_step integer;
  v_r integer;
  v_c integer;
  v_check_idx integer;
  v_line_count integer;
  v_moves integer;
  v_cells integer[] := '{}'::integer[];
  v_winner uuid;
  v_draw boolean := false;
  v_next uuid;
  v_first_rating integer;
  v_second_rating integer;
  v_first_score numeric;
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
  if p_column is null or p_column < 0 or p_column > 6 then raise exception 'INVALID_COLUMN'; end if;
  select * into v_game from public.game_sessions where id = p_session_id and game_key = 'connect4' and status = 'active' for update;
  if not found then raise exception 'GAME_NOT_ACTIVE'; end if;
  select * into v_state from public.duel_game_state where session_id = p_session_id for update;
  if not found then raise exception 'GAME_STATE_NOT_FOUND'; end if;
  if v_user not in (v_state.first_player, v_state.second_player) then raise exception 'NOT_A_PLAYER'; end if;
  if v_state.current_player <> v_user then raise exception 'NOT_YOUR_TURN'; end if;

  v_board := v_state.board;
  v_mark := case when v_user = v_state.first_player then 1 else 2 end;
  v_row := 5;
  while v_row >= 0 loop
    v_idx := v_row * 7 + v_col + 1;
    if v_board[v_idx] = 0 then exit; end if;
    v_row := v_row - 1;
  end loop;
  if v_row < 0 then raise exception 'COLUMN_FULL'; end if;
  v_board[v_idx] := v_mark;
  v_moves := v_state.move_count + 1;

  for v_dir in 1..4 loop
    v_line_count := 1;
    v_cells := array[v_idx - 1];
    foreach v_sign in array array[-1, 1] loop
      for v_step in 1..3 loop
        v_r := v_row + (v_sign * v_step * v_dr[v_dir]);
        v_c := v_col + (v_sign * v_step * v_dc[v_dir]);
        if v_r < 0 or v_r > 5 or v_c < 0 or v_c > 6 then exit; end if;
        v_check_idx := v_r * 7 + v_c + 1;
        if v_board[v_check_idx] <> v_mark then exit; end if;
        v_line_count := v_line_count + 1;
        v_cells := array_append(v_cells, v_check_idx - 1);
      end loop;
    end loop;
    if v_line_count >= 4 then v_winner := v_user; exit; end if;
  end loop;

  if v_winner is null and v_moves = 42 then v_draw := true; end if;
  v_next := case when v_user = v_state.first_player then v_state.second_player else v_state.first_player end;

  update public.duel_game_state
  set board = v_board,
      current_player = case when v_winner is not null or v_draw then v_user else v_next end,
      winner_user_id = v_winner,
      is_draw = v_draw,
      move_count = v_moves,
      winning_cells = case when v_winner is not null then v_cells else '{}'::integer[] end,
      version = version + 1,
      updated_at = now()
  where session_id = p_session_id;

  if v_winner is not null or v_draw then
    update public.game_sessions
    set status = 'completed', ended_at = now(),
        result = jsonb_build_object('winner_user_id', v_winner, 'draw', v_draw, 'winning_cells', to_jsonb(case when v_winner is not null then v_cells else '{}'::integer[] end), 'move_count', v_moves)
    where id = p_session_id and status = 'active';

    update public.game_players
    set score = case when v_winner is not null and user_id = v_winner then 3 when v_draw then 1 else 0 end
    where session_id = p_session_id;

    select coalesce((select rating from public.duel_ratings where user_id = v_state.first_player and game_key = 'connect4'), 1000) into v_first_rating;
    select coalesce((select rating from public.duel_ratings where user_id = v_state.second_player and game_key = 'connect4'), 1000) into v_second_rating;
    v_first_score := case when v_draw then 0.5 when v_winner = v_state.first_player then 1.0 else 0.0 end;
    v_expected_first := 1.0 / (1.0 + power(10.0, (v_second_rating - v_first_rating)::numeric / 400.0));
    v_expected_second := 1.0 - v_expected_first;
    v_new_first_rating := greatest(100, round(v_first_rating + 32 * (v_first_score - v_expected_first))::integer);
    v_new_second_rating := greatest(100, round(v_second_rating + 32 * ((1.0 - v_first_score) - v_expected_second))::integer);

    insert into public.duel_ratings(user_id, game_key, rating, wins, losses, draws)
    values
      (v_state.first_player, 'connect4', v_new_first_rating, case when v_first_score = 1 then 1 else 0 end, case when v_first_score = 0 then 1 else 0 end, case when v_draw then 1 else 0 end),
      (v_state.second_player, 'connect4', v_new_second_rating, case when v_first_score = 0 then 1 else 0 end, case when v_first_score = 1 then 1 else 0 end, case when v_draw then 1 else 0 end)
    on conflict (user_id, game_key) do update
    set rating = excluded.rating, wins = public.duel_ratings.wins + excluded.wins,
        losses = public.duel_ratings.losses + excluded.losses, draws = public.duel_ratings.draws + excluded.draws, updated_at = now();

    v_first_xp := case when v_draw then 20 when v_first_score = 1 then 40 else 10 end;
    v_second_xp := case when v_draw then 20 when v_first_score = 0 then 40 else 10 end;
    v_first_coins := case when v_draw then 10 when v_first_score = 1 then 20 else 5 end;
    v_second_coins := case when v_draw then 10 when v_first_score = 0 then 20 else 5 end;

    update public.profiles p
    set xp = p.xp + case when p.id = v_state.first_player then v_first_xp else v_second_xp end,
        level = greatest(p.level, floor(sqrt((p.xp + case when p.id = v_state.first_player then v_first_xp else v_second_xp end)::numeric / 100))::integer + 1),
        coins = p.coins + case when p.id = v_state.first_player then v_first_coins else v_second_coins end,
        total_score = p.total_score + case when v_draw then 20 when (p.id = v_state.first_player and v_first_score = 1) or (p.id = v_state.second_player and v_first_score = 0) then 100 else 10 end,
        games_played = p.games_played + 1,
        wins = p.wins + case when (p.id = v_state.first_player and v_first_score = 1) or (p.id = v_state.second_player and v_first_score = 0) then 1 else 0 end,
        updated_at = now()
    where p.id in (v_state.first_player, v_state.second_player);
  end if;

  return jsonb_build_object(
    'session_id', p_session_id, 'move_count', v_moves,
    'current_player', case when v_winner is not null or v_draw then v_user else v_next end,
    'winner_user_id', v_winner, 'is_draw', v_draw,
    'winning_cells', to_jsonb(case when v_winner is not null then v_cells else '{}'::integer[] end),
    'version', v_state.version + 1
  );
end;
$function$;

revoke all on function public.start_duel_game(uuid, text) from public, anon;
revoke all on function public.submit_duel_move(uuid, integer) from public, anon;
grant execute on function public.start_duel_game(uuid, text) to authenticated;
grant execute on function public.submit_duel_move(uuid, integer) to authenticated;

do $publication$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'duel_game_state') then
    alter publication supabase_realtime add table public.duel_game_state;
  end if;
end;
$publication$;
