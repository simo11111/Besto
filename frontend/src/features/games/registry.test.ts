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
    const keys: string[] = games.map((game) => game.key);
    expect(keys).not.toContain('rps');
  });
  it('keeps online duels two-player and separate from party matchmaking', () => {
    const duels = games.filter((game) => game.mode === 'duel');
    expect(duels.map((game) => game.key).sort()).toEqual(['connect4', 'dama']);
    for (const game of duels) {
      expect(game.minPlayers).toBe(2);
      expect(game.maxPlayers).toBe(2);
    }
    expect(games.filter((game) => game.mode === 'party').every((game) => game.maxPlayers >= game.minPlayers)).toBe(true);
  });

});
