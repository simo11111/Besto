-- DIMA PLAY: cover foreign-key lookups identified by Supabase Performance Advisor.
create index if not exists game_player_secrets_user_idx on private.game_player_secrets(user_id);
create index if not exists game_session_secrets_target_user_idx on private.game_session_secrets(target_user_id);
create index if not exists chat_messages_user_idx on public.chat_messages(user_id);
create index if not exists game_actions_user_idx on public.game_actions(user_id);
create index if not exists game_players_user_idx on public.game_players(user_id);
create index if not exists game_sessions_created_by_idx on public.game_sessions(created_by);
create index if not exists player_achievements_achievement_idx on public.player_achievements(achievement_id);
create index if not exists player_inventory_cosmetic_idx on public.player_inventory(cosmetic_id);
create index if not exists room_members_user_idx on public.room_members(user_id);
create index if not exists rooms_owner_idx on public.rooms(owner_id);
