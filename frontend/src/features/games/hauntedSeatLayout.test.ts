import { describe, expect, it } from 'vitest';
import { getHauntedSeatPosition } from './hauntedSeatLayout';

describe('Haunted Camp seat layout', () => {
  it('keeps every seat inside the scene for 4–10 players', () => {
    for (let total = 4; total <= 10; total++) {
      for (let index = 0; index < total; index++) {
        const seat = getHauntedSeatPosition(index, total);
        expect(seat.left).toBeGreaterThan(5);
        expect(seat.left).toBeLessThan(95);
        expect(seat.top).toBeGreaterThan(15);
        expect(seat.top).toBeLessThan(85);
      }
    }
  });

  it('stagger even player counts so the fire is not covered at the bottom center', () => {
    for (const total of [4, 6, 8, 10]) {
      const seats = Array.from({ length: total }, (_, index) => getHauntedSeatPosition(index, total));
      expect(seats.every(seat => Math.abs(seat.left - 50) > 0.1)).toBe(true);
    }
  });

  it('returns stable coordinates and handles a single participant safely', () => {
    expect(getHauntedSeatPosition(0, 1)).toEqual(getHauntedSeatPosition(0, 1));
    expect(getHauntedSeatPosition(0, 1).left).toBe(50);
  });
});

  it('keeps the same seat order when realtime player rows arrive in a different order', async () => {
    const { getHauntedStableSeatOrder } = await import('./hauntedSeatLayout');
    const first = [{ user_id: 'user-c' }, { user_id: 'user-a' }, { user_id: 'user-b' }];
    const reordered = [{ user_id: 'user-b' }, { user_id: 'user-c' }, { user_id: 'user-a' }];
    expect(getHauntedStableSeatOrder(first).map(p => p.user_id))
      .toEqual(getHauntedStableSeatOrder(reordered).map(p => p.user_id));
  });
