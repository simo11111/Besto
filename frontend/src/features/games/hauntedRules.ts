export type HauntedVoteResult = { outcome: 'ejected' | 'revote' | 'no_ejection'; targetId: string | null };
export function resolveNightOutcome(killTarget: string | null, protectedTarget: string | null) {
  const saved = Boolean(killTarget && protectedTarget && killTarget === protectedTarget);
  return { killedUserId: killTarget && !saved ? killTarget : null, saved };
}
export function resolveVoteOutcome(votes: string[], voteRound: 1 | 2): HauntedVoteResult {
  if (!votes.length) return { outcome: 'no_ejection', targetId: null };
  const counts = new Map<string, number>();
  votes.forEach(target => counts.set(target, (counts.get(target) ?? 0) + 1));
  const highest = Math.max(...counts.values());
  const leaders = [...counts.entries()].filter(([, count]) => count === highest).map(([id]) => id);
  if (leaders.length > 1) return { outcome: voteRound === 1 ? 'revote' : 'no_ejection', targetId: null };
  return { outcome: 'ejected', targetId: leaders[0] };
}
export function getHauntedWinner(haunterId: string, ejectedId: string | null, livingVillagers: number) {
  if (ejectedId === haunterId) return 'villagers' as const;
  if (livingVillagers <= 1) return 'haunter' as const;
  return null;
}
