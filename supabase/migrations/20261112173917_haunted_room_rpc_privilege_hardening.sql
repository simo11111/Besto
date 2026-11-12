revoke all on function public.prune_stale_room_members(uuid) from public, anon, authenticated;
grant execute on function public.prune_stale_room_members(uuid) to service_role;
revoke all on function public.leave_room(uuid) from public, anon;
grant execute on function public.leave_room(uuid) to authenticated;
revoke all on function public.get_latest_haunted_game(uuid) from public, anon;
grant execute on function public.get_latest_haunted_game(uuid) to authenticated;
revoke all on function public.get_haunted_game_state(uuid) from public, anon;
grant execute on function public.get_haunted_game_state(uuid) to authenticated;
