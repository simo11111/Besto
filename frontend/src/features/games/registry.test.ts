import { describe, expect, it } from 'vitest';
import { games } from './registry';

describe('party game registry', () => {
  it('contains unique game keys', () => {
    const keys = games.map((game) => game.key);
    expect(new Set(keys).size).toBe(keys.length);
  });

  it('defines player guidance and a complete round flow for every game', () => {
    for (const game of games) {
      expect(game.name.length).toBeGreaterThan(0);
      expect(game.players.length).toBeGreaterThan(0);
      expect(game.rules.length).toBeGreaterThan(0);
      expect(game.roundFlow.length).toBeGreaterThan(0);
    }
  });

  it('keeps removed rock-paper-scissors out of the party catalog', () => {
    expect(games.some((game) => game.key === 'rps')).toBe(false);
  });
});
