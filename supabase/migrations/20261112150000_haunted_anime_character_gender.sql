alter table public.profiles add column if not exists gender text;
alter table public.haunted_npcs add column if not exists gender text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='profiles_gender_check' and conrelid='public.profiles'::regclass) then
    alter table public.profiles add constraint profiles_gender_check check (gender is null or gender in ('male','female'));
  end if;
  if not exists (select 1 from pg_constraint where conname='haunted_npcs_gender_check' and conrelid='public.haunted_npcs'::regclass) then
    alter table public.haunted_npcs add constraint haunted_npcs_gender_check check (gender in ('male','female'));
  end if;
end $$;

update public.haunted_npcs
set gender = case when display_name in ('سلمى','ليلى','مريم','نور','هبة') then 'female' else 'male' end
where gender is null;

create or replace function public.set_my_haunted_gender(p_gender text)
returns boolean language plpgsql security definer set search_path to ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
  if p_gender not in ('male','female') then raise exception 'اختار شخصية ذكر أو أنثى'; end if;
  update public.profiles set gender=p_gender, updated_at=now() where id=v_user;
  if not found then raise exception 'البروفايل ما تلقاش'; end if;
  return true;
end;
$$;
revoke all on function public.set_my_haunted_gender(text) from public, anon;
grant execute on function public.set_my_haunted_gender(text) to authenticated;

create or replace function public.get_haunted_game_state(p_game_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare
  v_user uuid:=auth.uid();
  v_game public.haunted_games%rowtype;
  v_role text;
  v_vote uuid;
  v_players jsonb;
  v_events jsonb;
  v_roles jsonb;
  v_night_ready boolean:=false;
  v_vote_count integer:=0;
begin
  if v_user is null then raise exception 'خاصك تدخل للحساب'; end if;
  select * into v_game from public.haunted_games where id=p_game_id;
  if not found or not exists(select 1 from public.room_members rm where rm.room_id=v_game.room_id and rm.user_id=v_user) then
    raise exception 'ما عندكش الحق تشوف هاد اللعبة';
  end if;
  select role into v_role from public.haunted_players where game_id=p_game_id and user_id=v_user;
  if v_role is null then raise exception 'ماشي لاعب فهاد اللعبة'; end if;
  select target_id into v_vote from public.haunted_votes
    where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round and voter_id=v_user;
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
    'id',e.id,'round',e.round,'event_type',e.event_type,'payload',e.payload,'created_at',e.created_at
  ) order by e.created_at),'[]'::jsonb)
  into v_events from public.haunted_events e where e.game_id=p_game_id;
  if v_game.status='night' then
    select coalesce((haunter_target is not null and (v_game.game_mode='quick' or faqih_target is not null)),false)
    into v_night_ready from public.haunted_night_actions
    where game_id=p_game_id and round=v_game.round;
  end if;
  select count(*) into v_vote_count from public.haunted_votes
    where game_id=p_game_id and round=v_game.round and vote_round=v_game.vote_round;
  if v_game.status='ended' then
    select coalesce(jsonb_agg(jsonb_build_object('user_id',hp.user_id,'role',hp.role) order by hp.created_at),'[]'::jsonb)
    into v_roles from public.haunted_players hp where hp.game_id=p_game_id;
  end if;
  return jsonb_build_object(
    'id',v_game.id,'room_id',v_game.room_id,'status',v_game.status,'round',v_game.round,
    'vote_round',v_game.vote_round,'game_mode',v_game.game_mode,'winner',v_game.winner,
    'phase_deadline_at',v_game.phase_deadline_at,'voting_open',v_game.voting_open,
    'role',v_role,'my_vote',v_vote,'players',v_players,'events',v_events,
    'roles',coalesce(v_roles,'[]'::jsonb),'night_actions_ready',v_night_ready,'vote_count',v_vote_count
  );
end;
$$;
revoke all on function public.get_haunted_game_state(uuid) from public, anon;
grant execute on function public.get_haunted_game_state(uuid) to authenticated;
