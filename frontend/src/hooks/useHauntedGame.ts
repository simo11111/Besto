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
  openVoting: () => Promise<boolean>;
};

export function useHauntedGame(gameId: string | null, roomId: string, userId: string, isHost = false): HookResult {
  const [state, setState] = useState<HauntedState | null>(null);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const refreshRef = useRef<() => Promise<void>>(async () => undefined);
  const effectiveGameId = state?.id ?? gameId ?? null;

  const refresh = useCallback(async () => {
    if (!supabase || !effectiveGameId || !userId) return;
    setLoading(true);
    const { data, error: rpcError } = await supabase.rpc('get_haunted_game_state', { p_game_id: effectiveGameId });
    setLoading(false);
    if (rpcError) { setError(rpcError.message); return; }
    setError('');
    setState(data as HauntedState);
  }, [effectiveGameId, userId]);
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
    if (!supabase || !effectiveGameId) return false;
    setBusy(true); setError('');
    const { error: rpcError } = await supabase.rpc(name, { ...args, p_game_id: effectiveGameId });
    setBusy(false);
    if (rpcError) { setError(rpcError.message); return false; }
    await refreshRef.current();
    return true;
  }, [effectiveGameId]);

  const submitKill = useCallback((target: string) => callBoolean('submit_haunter_kill', { p_target: target }), [callBoolean]);
  const submitProtection = useCallback((target: string) => callBoolean('submit_faqih_protect', { p_target: target }), [callBoolean]);
  const advanceMorning = useCallback(() => callBoolean('advance_haunted_to_day', {}), [callBoolean]);
  const submitVote = useCallback((target: string) => callBoolean('submit_haunted_vote', { p_target: target }), [callBoolean]);

  const callResult = useCallback(async (name: string): Promise<HauntedPublicResult | null> => {
    if (!supabase || !effectiveGameId) return null;
    setBusy(true); setError('');
    const { data, error: rpcError } = await supabase.rpc(name, { p_game_id: effectiveGameId });
    setBusy(false);
    if (rpcError) { setError(rpcError.message); return null; }
    await refreshRef.current();
    return data as HauntedPublicResult;
  }, [effectiveGameId]);
  const resolveNight = useCallback(() => callResult('resolve_haunted_night'), [callResult]);
  const resolveVote = useCallback(() => callResult('resolve_haunted_vote'), [callResult]);
  const openVoting = useCallback(() => callBoolean('open_haunted_voting', {}), [callBoolean]);

  useEffect(() => {
    if (!supabase || !roomId || !userId) return;
    let cancelled = false;
    if (!effectiveGameId) {
      void supabase.rpc('get_latest_haunted_game', { p_room_id: roomId }).then(async ({ data, error: rpcError }) => {
        if (cancelled || rpcError || !data) return;
        const id = data as string;
        const { data: snapshot } = await supabase!.rpc('get_haunted_game_state', { p_game_id: id });
        if (!cancelled && snapshot) setState(snapshot as HauntedState);
      });
    } else void refreshRef.current();
    const discover = window.setInterval(async () => {
      if (cancelled || effectiveGameId || document.visibilityState !== 'visible') return;
      const { data } = await supabase!.rpc('get_latest_haunted_game', { p_room_id: roomId });
      if (!cancelled && data) {
        const { data: snapshot } = await supabase!.rpc('get_haunted_game_state', { p_game_id: data });
        if (!cancelled && snapshot) setState(snapshot as HauntedState);
      }
    }, 4000);
    return () => { cancelled = true; window.clearInterval(discover); };
  }, [effectiveGameId, roomId, userId]);

  useEffect(() => {
    if (!supabase || !state?.id || !isHost || state.status === 'ended') return;
    const client = supabase;
    let running = false;
    const runBots = async () => {
      if (running || document.visibilityState !== 'visible') return;
      running = true;
      try { await client.rpc('run_haunted_bot_turns', { p_game_id: state.id }); await refreshRef.current(); }
      finally { running = false; }
    };
    void runBots();
    const timer = window.setInterval(() => void runBots(), 2500);
    return () => window.clearInterval(timer);
  }, [state?.id, state?.status, isHost]);

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
    if (!state || !state.phase_deadline_at || state.status === 'ended' || !isHost) return;
    const deadline = new Date(state.phase_deadline_at).getTime();
    const timer = window.setTimeout(() => {
      if (state.status === 'night') void resolveNight();
      else if (state.status === 'morning') void advanceMorning();
      else if (state.status === 'day' && !state.voting_open) void openVoting();
      else if (state.status === 'day' && state.voting_open) void resolveVote();
    }, Math.max(0, deadline - Date.now()) + 250);
    return () => window.clearTimeout(timer);
  }, [state?.id, state?.status, state?.phase_deadline_at, state?.round, state?.vote_round, state?.voting_open, resolveNight, advanceMorning, resolveVote, openVoting, isHost]);

  return { state, loading, busy, error, refresh, start, submitKill, submitProtection, resolveNight, advanceMorning, submitVote, resolveVote, openVoting };
}
