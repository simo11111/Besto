export function getHauntedBotCount(humanCount: number, quickMode: boolean, roomCapacity = quickMode ? 4 : 10): number {
  if (!Number.isFinite(humanCount) || humanCount < 1 || !Number.isFinite(roomCapacity)) return 0;
  const totalPlayers = Math.max(0, Math.floor(Math.min(quickMode ? 4 : 10, roomCapacity)));
  return Math.max(0, totalPlayers - Math.floor(humanCount));
}
