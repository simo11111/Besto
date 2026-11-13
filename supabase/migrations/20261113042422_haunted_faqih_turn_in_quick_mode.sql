-- Keep the sequential FAQIH turn active in both standard and quick modes.
CREATE OR REPLACE FUNCTION public.get_haunted_game_state(p_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_game public.haunted_games%rowtype;
  v_role text;
  v_vote uuid;
  v_night_target uuid;
  v_players jsonb;
  v_events jsonb;
  v_roles jsonb;
  v_night_ready boolean := false;
  v_haunter_chosen boolean := false;
  v_vote_count integer := 0;
begin
  if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
  select * into v_game from public.haunted_games where id=p_game_id;
  if not found or not exists(
    select 1 from public.room_members rm
    where rm.room_id=v_game.room_id and rm.user_id=v_user
  ) then raise exception 'ما عندكش الحق تشوف هاد اللعبة'; end if;
  select role into v_role from public.haunted_players
  where game_id=p_game_id and user_id=v_user and left_at is null;
  if v_role is null and v_game.status <> 'ended' then raise exception 'ماشي لاعب فهاد اللعبة'; end if;

  select target_id into v_vote from public.haunted_votes
  where game_id=p_game_id and round=v_game.round
    and vote_round=v_game.vote_round and voter_id=v_user;

  if v_game.status='night' then
    select case
      when v_role='haunter' then haunter_target
      when v_role='faqih' then faqih_target
      else null
    end into v_night_target
    from public.haunted_night_actions
    where game_id=p_game_id and round=v_game.round;

    select coalesce(haunter_target is not null
      and faqih_target is not null,false)
    into v_night_ready
    from public.haunted_night_actions
    where game_id=p_game_id and round=v_game.round;

    select coalesce(haunter_target is not null,false)
    into v_haunter_chosen
    from public.haunted_night_actions
    where game_id=p_game_id and round=v_game.round;
  end if;

  -- Keep individual vote totals private until the vote is resolved.
  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id',hp.user_id,
    'username',coalesce(p.username,n.display_name,'لاعب'),
    'avatar_url',p.avatar_url,
    'avatar_key',n.avatar_key,
    'gender',coalesce(p.gender,n.gender,'male'),
    'is_alive',hp.is_alive,
    'is_bot',hp.is_bot
  ) order by hp.created_at),'[]'::jsonb)
  into v_players
  from public.haunted_players hp
  left join public.profiles p on p.id=hp.user_id
  left join public.haunted_npcs n on n.user_id=hp.user_id
  where hp.game_id=p_game_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'round',e.round,'event_type',e.event_type,
    'payload',e.payload,'created_at',e.created_at
  ) order by e.created_at),'[]'::jsonb)
  into v_events from public.haunted_events e where e.game_id=p_game_id;

  select count(*) into v_vote_count from public.haunted_votes
  where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round;

  if v_game.status='ended' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'user_id',hp.user_id,'role',hp.role
    ) order by hp.created_at),'[]'::jsonb)
    into v_roles from public.haunted_players hp where hp.game_id=p_game_id;
  end if;

  return jsonb_build_object(
    'id',v_game.id,'room_id',v_game.room_id,'status',v_game.status,
    'round',v_game.round,'vote_round',v_game.vote_round,
    'game_mode',v_game.game_mode,'winner',v_game.winner,
    'phase_deadline_at',v_game.phase_deadline_at,
    'voting_open',v_game.voting_open,'role',v_role,'my_vote',v_vote,
    'my_night_target',v_night_target,
    'night_haunter_chosen',v_haunter_chosen,
    'players',v_players,'events',v_events,
    'roles',coalesce(v_roles,'[]'::jsonb),
    'night_actions_ready',v_night_ready,'vote_count',v_vote_count
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION private.notify_haunted_faqih_turn()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_human_faqih boolean := false;
begin
  if new.haunter_target is not null
     and (tg_op = 'INSERT' or old.haunter_target is distinct from new.haunter_target) then
    select exists (
      select 1
      from public.haunted_players
      where game_id = new.game_id
        and role = 'faqih'
        and is_alive
        and not is_bot
    ) into v_human_faqih;

    if v_human_faqih then
      update public.haunted_games
      set phase_deadline_at = now() + interval '30 seconds',
          bot_next_action_at = null
      where id = new.game_id
        and status = 'night';
    end if;

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
$function$
;
