import type { Game, Room } from '../shared/types';
import type { supabase } from '../../lib/supabase';

type Client = NonNullable<typeof supabase>;

export type RoomMemberRow = {
  user_id: string;
  role: string;
  last_seen_at: string | null;
};

export type RoomMemberProfile = {
  id: string;
  username: string;
  avatar_url: string | null;
  gender: 'male' | 'female' | null;
  level: number;
  equipped_frame: string;
  equipped_title: string;
};

export type RoomChatMessage = {
  id: string;
  user_id: string;
  body: string;
  created_at: string;
};

export type RoomSnapshot = {
  members: RoomMemberRow[];
  memberError: unknown | null;
  profiles: RoomMemberProfile[];
  chat: RoomChatMessage[];
  chatError: unknown | null;
  sessions: Game[];
};

export async function fetchOpenRooms(client: Client): Promise<{ rooms: Room[]; error: unknown | null }> {
  await client.rpc('prune_stale_room_members');
  const { data, error } = await client
    .from('rooms')
    .select('id,code,name,is_private,max_players,status,game_key')
    .eq('status', 'open')
    .eq('is_private', false)
    .order('last_activity_at', { ascending: false })
    .limit(30);
  return { rooms: (data ?? []) as Room[], error };
}

export async function fetchRoomSnapshot(client: Client, roomId: string): Promise<RoomSnapshot> {
  const [{ data: members, error: memberError }, { data: chat, error: chatError }, { data: sessions }] = await Promise.all([
    client.from('room_members').select('user_id,role,last_seen_at').eq('room_id', roomId),
    client.from('chat_messages').select('id,user_id,body,created_at').eq('room_id', roomId).order('created_at', { ascending: true }).limit(60),
    client.from('game_sessions').select('id,game_key,status,created_by,result').eq('room_id', roomId).order('created_at', { ascending: false }).limit(1),
  ]);

  let profiles: RoomMemberProfile[] = [];
  if (!memberError) {
    const ids = (members ?? []).map((member) => member.user_id);
    const { data } = ids.length
      ? await client.from('profiles').select('id,username,avatar_url,gender,level,equipped_frame,equipped_title').in('id', ids)
      : { data: [] };
    profiles = (data ?? []) as RoomMemberProfile[];
  }

  return {
    members: (members ?? []) as RoomMemberRow[],
    memberError,
    profiles,
    chat: (chat ?? []) as RoomChatMessage[],
    chatError,
    sessions: (sessions ?? []) as Game[],
  };
}
