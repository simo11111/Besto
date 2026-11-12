-- Cache the JWT function result once per statement in catalog policies.
drop policy if exists games_catalog_admin_insert on public.games_catalog;
drop policy if exists games_catalog_admin_update on public.games_catalog;
drop policy if exists games_catalog_admin_delete on public.games_catalog;
create policy games_catalog_admin_insert on public.games_catalog for insert to authenticated
with check (coalesce(((select auth.jwt())->'app_metadata'->>'role'),'')='admin');
create policy games_catalog_admin_update on public.games_catalog for update to authenticated
using (coalesce(((select auth.jwt())->'app_metadata'->>'role'),'')='admin')
with check (coalesce(((select auth.jwt())->'app_metadata'->>'role'),'')='admin');
create policy games_catalog_admin_delete on public.games_catalog for delete to authenticated
using (coalesce(((select auth.jwt())->'app_metadata'->>'role'),'')='admin');
