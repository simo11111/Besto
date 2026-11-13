export type HauntedSeatPosition = { left: number; top: number };

/**
 * Distribute seats around the fire. Even player counts are staggered by half
 * a seat so nobody sits directly in front of the flame at the top/bottom.
 */
export function getHauntedSeatPosition(index: number, total: number): HauntedSeatPosition {
  const count = Number.isFinite(total) ? Math.max(1, Math.floor(total)) : 1;
  const safeIndex = Number.isFinite(index) ? Math.max(0, Math.floor(index)) : 0;
  const step = (Math.PI * 2) / count;
  const stagger = count % 2 === 0 ? step / 2 : 0;
  const angle = safeIndex * step - Math.PI / 2 + stagger;
  const radiusX = count >= 8 ? 40 : count >= 6 ? 38 : 37;
  const radiusY = count >= 8 ? 29 : count >= 6 ? 31 : 30;
  return {
    left: Number((50 + radiusX * Math.cos(angle)).toFixed(3)),
    top: Number((50 + radiusY * Math.sin(angle)).toFixed(3)),
  };
}
