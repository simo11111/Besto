import { describe, expect, it } from 'vitest';
import { games } from './registry';

describe('ليلة فالخيمة game registry', () => {
  it('contains exactly one available game', () => {
    expect(games.map((game) => game.key)).toEqual(['haunted_camp']);
  });

  it('defines player guidance and a complete round flow', () => {
    const game = games[0];
    expect(game.name).toBe('ليلة فالخيمة');
    expect(game.players).toBe('4–10');
    expect(game.rules.length).toBeGreaterThan(0);
    expect(game.roundFlow.length).toBeGreaterThan(0);
    expect(game.minPlayers).toBe(4);
    expect(game.maxPlayers).toBe(10);
  });
});
