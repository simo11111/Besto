do $$
begin
 alter publication supabase_realtime add table public.room_members;
exception when duplicate_object then null;
end;
$$;
create index if not exists daily_mission_claims_mission_key_idx on public.daily_mission_claims(mission_key);
