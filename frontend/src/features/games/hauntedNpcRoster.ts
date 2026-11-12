export function getHauntedBotCount(humanCount: number, quickMode: boolean): number {
  if (!Number.isFinite(humanCount) || humanCount < 1) return 0;
  const totalPlayers = quickMode ? 4 : 5;
  return Math.max(0, totalPlayers - Math.floor(humanCount));
}
