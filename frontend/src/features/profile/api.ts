import type { DailyMission, Profile } from '../shared/types';
import type { supabase } from '../../lib/supabase';

type Client = NonNullable<typeof supabase>;

export async function fetchProfile(client: Client, userId: string) {
  const { data, error } = await client.from('profiles').select('*').eq('id', userId).single();
  return { profile: data as Profile | null, error };
}

export async function fetchLeaderboard(client: Client) {
  const { data, error } = await client
    .from('profiles')
    .select('id,username,avatar_url,level,xp,coins,wins,games_played,total_score,equipped_frame,equipped_title,bio,streak_days,last_daily_claim')
    .gt('total_score', 0)
    .order('total_score', { ascending: false })
    .limit(50);
  return { profiles: ((data ?? []).filter((profile) => Number(profile.total_score) > 0)) as Profile[], error };
}

export async function fetchDailyMissions(client: Client) {
  const { data, error } = await client.rpc('get_daily_missions');
  return { missions: (data ?? []) as DailyMission[], error };
}
