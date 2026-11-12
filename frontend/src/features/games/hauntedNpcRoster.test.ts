import { describe, expect, it } from 'vitest';
import { getHauntedBotCount } from './hauntedNpcRoster';

describe('Haunted Camp NPC roster', () => {
  it('fills standard games for a solo player', () => {
    expect(getHauntedBotCount(1, false)).toBe(4);
  });
  it('fills standard games for two humans', () => {
    expect(getHauntedBotCount(2, false)).toBe(3);
  });
  it('fills quick games for a solo player', () => {
    expect(getHauntedBotCount(1, true)).toBe(3);
  });
  it('does not add bots when the room already meets the target', () => {
    expect(getHauntedBotCount(5, false)).toBe(0);
    expect(getHauntedBotCount(4, true)).toBe(0);
  });
  it('rejects an empty lobby by returning zero bots', () => {
    expect(getHauntedBotCount(0, false)).toBe(0);
  });
});
