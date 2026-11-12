import { describe, expect, it } from 'vitest';
import { games } from '../games/registry';
import { getRoomCapacityOptions, normalizeRoomCapacity } from './roomSetup';

describe('room setup rules', () => {
  it('offers only valid capacities for ليلة فالخيمة', () => {
    const haunted = games[0];
    expect(getRoomCapacityOptions(haunted)).toEqual([4, 6, 8, 10]);
    expect(getRoomCapacityOptions(haunted).every((capacity) => capacity >= haunted.minPlayers && capacity <= haunted.maxPlayers)).toBe(true);
  });

  it('normalizes invalid capacities to the nearest available size', () => {
    const haunted = games[0];
    expect(normalizeRoomCapacity(haunted, 2)).toBe(4);
    expect(normalizeRoomCapacity(haunted, 8)).toBe(8);
    expect(normalizeRoomCapacity(haunted, 16)).toBe(10);
  });
});
