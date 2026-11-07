-- DIMA PLAY security hardening.
-- These tables are accessed only by postgres-owned SECURITY DEFINER RPCs.
-- Enable RLS as defense in depth and deny direct API-role access.
alter table public.room_join_attempts enable row level security;
revoke all on table public.room_join_attempts from public, anon, authenticated;

alter table private.game_player_secrets enable row level security;
revoke all on table private.game_player_secrets from public, anon, authenticated;

alter table private.game_session_secrets enable row level security;
revoke all on table private.game_session_secrets from public, anon, authenticated;
