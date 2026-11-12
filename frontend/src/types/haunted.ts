export type HauntedRole = 'haunter' | 'faqih' | 'villager';
export type HauntedStatus = 'lobby' | 'night' | 'morning' | 'day' | 'ended';
export type HauntedWinner = 'villagers' | 'haunter' | null;
export type HauntedPlayer = {
  user_id: string;
  username: string;
  avatar_url: string | null;
  is_alive: boolean;
  is_bot?: boolean;
};
export type HauntedEvent = {
  id: string;
  round: number;
  event_type: string;
  payload: Record<string, unknown>;
  created_at: string;
};
export type HauntedState = {
  id: string;
  room_id: string;
  status: HauntedStatus;
  round: number;
  vote_round: number;
  game_mode: 'standard' | 'quick';
  winner: HauntedWinner;
  phase_deadline_at: string | null;
  role: HauntedRole;
  my_vote: string | null;
  players: HauntedPlayer[];
  events: HauntedEvent[];
  roles: Array<{ user_id: string; role: HauntedRole }>;
  night_actions_ready: boolean;
  vote_count: number;
  voting_open: boolean;
};
export type HauntedPublicResult = {
  killed_user_id?: string | null;
  saved?: boolean;
  result?: 'revote' | 'game_ended' | 'next_night';
  winner?: HauntedWinner;
  ejected_user_id?: string | null;
  round?: number;
};
