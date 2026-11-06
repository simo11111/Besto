import type { AppNotification, DirectMessage } from '../shared/types';
import type { supabase } from '../../lib/supabase';

type Client = NonNullable<typeof supabase>;

type FriendshipRow = {
  id: string;
  requester_id: string;
  addressee_id: string;
  status: 'pending' | 'accepted';
  created_at: string;
};

type FriendProfile = {
  id: string;
  username: string;
  avatar_url?: string | null;
  level: number;
  equipped_title: string;
};

type FriendRecord = FriendshipRow & { profile?: FriendProfile };

export async function fetchFriendships(client: Client, userId: string) {
  const { data, error } = await client
    .from('friendships')
    .select('id,requester_id,addressee_id,status,created_at')
    .or('requester_id.eq.' + userId + ',addressee_id.eq.' + userId)
    .order('updated_at', { ascending: false });
  if (error) throw error;

  const rows = (data ?? []) as FriendshipRow[];
  const ids = [...new Set(rows.flatMap((row) => [row.requester_id, row.addressee_id]).filter((id) => id !== userId))];
  const { data: profiles, error: profileError } = ids.length
    ? await client.from('profiles').select('id,username,avatar_url,level,equipped_title').in('id', ids)
    : { data: [], error: null };
  if (profileError) throw profileError;

  const profileRows = (profiles ?? []) as FriendProfile[];
  const mapped: FriendRecord[] = rows.map((row) => ({
    ...row,
    profile: profileRows.find((profile) => profile.id === (row.requester_id === userId ? row.addressee_id : row.requester_id)),
  }));

  return {
    friends: mapped.filter((row) => row.status === 'accepted'),
    requests: mapped.filter((row) => row.status === 'pending' && row.addressee_id === userId),
  };
}

export async function fetchDirectMessages(client: Client, userId: string, friendId: string): Promise<DirectMessage[]> {
  const { data, error } = await client
    .from('direct_messages')
    .select('id,sender_id,recipient_id,body,created_at,read_at')
    .or('and(sender_id.eq.' + userId + ',recipient_id.eq.' + friendId + '),and(sender_id.eq.' + friendId + ',recipient_id.eq.' + userId + ')')
    .order('created_at', { ascending: true })
    .limit(100);
  if (error) throw error;

  const messages = (data ?? []) as DirectMessage[];
  const { error: readError } = await client
    .from('direct_messages')
    .update({ read_at: new Date().toISOString() })
    .eq('sender_id', friendId)
    .eq('recipient_id', userId)
    .is('read_at', null);
  if (readError) throw readError;
  return messages;
}

export async function fetchNotifications(client: Client, userId: string): Promise<AppNotification[]> {
  const { data, error } = await client
    .from('notifications')
    .select('id,actor_id,kind,title,body,payload,created_at,read_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(30);
  if (error) throw error;
  return (data ?? []) as AppNotification[];
}
