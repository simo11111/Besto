import { describe, expect, it } from 'vitest';
import { games } from '../games/registry';
import { getRoomCapacityOptions, normalizeRoomCapacity } from './roomSetup';

describe('room setup rules', () => {
  it('locks competitive duels to exactly two seats', () => {
    for (const game of games.filter((item) => item.mode === 'duel')) {
      expect(getRoomCapacityOptions(game)).toEqual([2]);
      expect(normalizeRoomCapacity(game, 16)).toBe(2);
    }
  });
  it('never offers a party capacity below the minimum player count', () => {
    for (const game of games.filter((item) => item.mode === 'party')) {
      expect(getRoomCapacityOptions(game).every((capacity) => capacity >= game.minPlayers && capacity <= game.maxPlayers)).toBe(true);
    }
  });
  it('moves an invalid capacity to the nearest available size', () => {
    const wolf = games.find((item) => item.key === 'wolf')!;
    expect(normalizeRoomCapacity(wolf, 2)).toBe(4);
    expect(normalizeRoomCapacity(wolf, 16)).toBe(12);
  });
});
