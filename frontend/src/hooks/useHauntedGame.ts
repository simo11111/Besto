import { useCallback, useEffect, useRef, useState } from 'react';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import type { HauntedPublicResult, HauntedState } from '../types/haunted';

type HookResult = {
  state: HauntedState | null;
  loading: boolean;
  busy: boolean;
  error: string;
  refresh: () => Promise<void>;
  start: (roomId: string, quickMode: boolean) => Promise<boolean>;
  submitKill: (target: string) => Promise<boolean>;
  submitProtection: (target: string) => Promise<boolean>;
  resolveNight: () => Promise<HauntedPublicResult | null>;
  advanceMorning: () => Promise<boolean>;
  submitVote: (target: string) => Promise<boolean>;
  resolveVote: () => Promise<HauntedPublicResult | null>;
};

export function useHauntedGame(gameId: string | null, roomId: string, userId: string, isHost: boolean): HookResult {
  const [state, setState] = useState<HauntedState | null>(null);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const refreshRef = useRef<() => Promise<void>>(async () => undefined);

  const refresh = useCallback(async () => {
    if (!supabase || !gameId || !userId) return;
    setLoading(true);
    const { data, error: rpcError } = await supabase.rpc('get_haunted_game_state', { p_game_id: gameId });
    setLoading(false);
    if (rpcError) { setError(rpcError.message); return; }
    setError('');
    setState(data as HauntedState);
  }, [gameId, userId]);
  refreshRef.current = refresh;

  const start = useCallback(async (targetRoomId: string, quickMode: boolean) => {
    if (!supabase) return false;
    setBusy(true); setError('');
    const { data, error: rpcError } = await supabase.rpc('start_haunted_game', { p_room_id: targetRoomId, p_quick_mode: quickMode });
    setBusy(false);
    if (rpcError) { setError(rpcError.message); return false; }
    const id = data as string;
    const { data: snapshot, error: stateError } = await supabase.rpc('get_haunted_game_state', { p_game_id: id });
    if (stateError) { setError(stateError.message); return false; }
    setState(snapshot as HauntedState);
    return true;
  }, []);

  const callBoolean = useCallback(async (name: string, args: Record<string, unknown>) => {
    if (!supabase) return false;
    setBusy(true); setError('');
    const { error: rpcError } = await supabase.rpc(name, args);
    setBusy(false);
    if (rpcError) { setError(rpcError.message); return false; }
    await refreshRef.current();
    return true;
  }, []);

  const submitKill = useCallback((target: string) => callBoolean('submit_haunter_kill', { p_game_id: gameId, p_target: target }), [callBoolean, gameId]);
  const submitProtection = useCallback((target: string) => callBoolean('submit_faqih_protect', { p_game_id: gameId, p_target: target }), [callBoolean, gameId]);
  const advanceMorning = useCallback(() => callBoolean('advance_haunted_to_day', { p_game_id: gameId }), [callBoolean, gameId]);
  const submitVote = useCallback((target: string) => callBoolean('submit_haunted_vote', { p_game_id: gameId, p_target: target }), [callBoolean, gameId]);

  const callResult = useCallback(async (name: string): Promise<HauntedPublicResult | null> => {
    if (!supabase || !gameId || !isHost) return null;
    setBusy(true); setError('');
    const { data, error: rpcError } = await supabase.rpc(name, { p_game_id: gameId });
    setBusy(false);
    if (rpcError) { setError(rpcError.message); return null; }
    await refreshRef.current();
    return data as HauntedPublicResult;
  }, [gameId, isHost]);
  const resolveNight = useCallback(() => callResult('resolve_haunted_night'), [callResult]);
  const resolveVote = useCallback(() => callResult('resolve_haunted_vote'), [callResult]);

  useEffect(() => {
    if (!supabase || !roomId || !userId) return;
    let cancelled = false;
    if (!gameId) {
      void supabase.rpc('get_active_haunted_game', { p_room_id: roomId }).then(async ({ data, error: rpcError }) => {
        if (cancelled || rpcError || !data) return;
        const id = data as string;
        const { data: snapshot } = await supabase!.rpc('get_haunted_game_state', { p_game_id: id });
        if (!cancelled && snapshot) setState(snapshot as HauntedState);
      });
    } else void refreshRef.current();
    return () => { cancelled = true; };
  }, [gameId, roomId, userId]);

  useEffect(() => {
    if (!supabase || !state?.id) return;
    const client = supabase;
    let channel: RealtimeChannel;
    const refreshOnVisible = () => { if (document.visibilityState === 'visible') void refreshRef.current(); };
    channel = client.channel('haunted-game:' + state.id)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'haunted_games', filter: 'id=eq.' + state.id }, () => void refreshRef.current())
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'haunted_events', filter: 'game_id=eq.' + state.id }, () => void refreshRef.current())
      .subscribe((status) => { if (status === 'SUBSCRIBED') void refreshRef.current(); });
    const poll = window.setInterval(() => { if (document.visibilityState === 'visible') void refreshRef.current(); }, 5000);
    document.addEventListener('visibilitychange', refreshOnVisible);
    return () => {
      window.clearInterval(poll);
      document.removeEventListener('visibilitychange', refreshOnVisible);
      void client.removeChannel(channel);
    };
  }, [state?.id]);

  useEffect(() => {
    if (!state || !isHost || !state.phase_deadline_at || state.status === 'ended') return;
    const deadline = new Date(state.phase_deadline_at).getTime();
    const timer = window.setTimeout(() => {
      if (state.status === 'night') void resolveNight();
      else if (state.status === 'morning') void advanceMorning();
      else if (state.status === 'day') void resolveVote();
    }, Math.max(0, deadline - Date.now()) + 150);
    return () => window.clearTimeout(timer);
  }, [state?.id, state?.status, state?.phase_deadline_at, state?.round, state?.vote_round, isHost, resolveNight, advanceMorning, resolveVote]);

  return { state, loading, busy, error, refresh, start, submitKill, submitProtection, resolveNight, advanceMorning, submitVote, resolveVote };
}
