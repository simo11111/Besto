-- MIMOX: tighten catalog policy evaluation and index Haunted Camp foreign keys.
drop policy if exists games_catalog_admin_write on public.games_catalog;
create policy games_catalog_admin_insert on public.games_catalog
  for insert to authenticated
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'),'')='admin');
create policy games_catalog_admin_update on public.games_catalog
  for update to authenticated
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'),'')='admin')
  with check (coalesce((select auth.jwt()->'app_metadata'->>'role'),'')='admin');
create policy games_catalog_admin_delete on public.games_catalog
  for delete to authenticated
  using (coalesce((select auth.jwt()->'app_metadata'->>'role'),'')='admin');

create index if not exists haunted_games_created_by_idx on public.haunted_games(created_by);
create index if not exists haunted_night_actions_haunter_target_idx on public.haunted_night_actions(haunter_target);
create index if not exists haunted_night_actions_faqih_target_idx on public.haunted_night_actions(faqih_target);
create index if not exists haunted_night_actions_killed_user_idx on public.haunted_night_actions(killed_user_id);
create index if not exists haunted_night_actions_protected_user_idx on public.haunted_night_actions(protected_user_id);
create index if not exists haunted_players_voted_for_idx on public.haunted_players(voted_for);
create index if not exists haunted_votes_voter_idx on public.haunted_votes(voter_id);
create index if not exists haunted_votes_target_idx on public.haunted_votes(target_id);
