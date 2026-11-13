import { describe, expect, it } from 'vitest';
import { getHauntedBotCount } from './hauntedNpcRoster';

describe('Haunted Camp NPC roster', () => {
  it('fills the selected standard room capacity rather than always creating ten players', () => {
    expect(getHauntedBotCount(1, false, 6)).toBe(5);
    expect(getHauntedBotCount(2, false, 6)).toBe(4);
    expect(getHauntedBotCount(6, false, 6)).toBe(0);
  });

  it('fills a standard ten-player room when ten is selected', () => {
    expect(getHauntedBotCount(1, false, 10)).toBe(9);
    expect(getHauntedBotCount(3, false, 10)).toBe(7);
  });

  it('caps standard mode at ten even when the room supports sixteen', () => {
    expect(getHauntedBotCount(1, false, 16)).toBe(9);
    expect(getHauntedBotCount(10, false, 16)).toBe(0);
  });

  it('keeps quick mode at four total participants', () => {
    expect(getHauntedBotCount(1, true, 10)).toBe(3);
    expect(getHauntedBotCount(3, true, 6)).toBe(1);
    expect(getHauntedBotCount(4, true, 4)).toBe(0);
  });

  it('handles the minimum four-player standard room', () => {
    expect(getHauntedBotCount(1, false, 4)).toBe(3);
    expect(getHauntedBotCount(4, false, 4)).toBe(0);
  });

  it('fills an eight-player standard room', () => {
    expect(getHauntedBotCount(2, false, 8)).toBe(6);
  });

  it('never adds bots beyond the selected room capacity', () => {
    expect(getHauntedBotCount(7, false, 6)).toBe(0);
  });

  it('returns zero for invalid or empty lobbies', () => {
    expect(getHauntedBotCount(0, false, 6)).toBe(0);
    expect(getHauntedBotCount(Number.NaN, false, 6)).toBe(0);
    expect(getHauntedBotCount(1, false, Number.NaN)).toBe(0);
  });
});
