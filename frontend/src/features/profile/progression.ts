export const xpForNext = (level: number): number => Math.max(100, level * level * 100);

export const xpProgress = (xp: number, level: number): number => {
  const floor = Math.max(0, (level - 1) * (level - 1) * 100);
  const ceiling = xpForNext(level);
  return Math.max(0, Math.min(100, ((xp - floor) / Math.max(1, ceiling - floor)) * 100));
};
