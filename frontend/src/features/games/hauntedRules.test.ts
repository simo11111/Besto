import { describe, expect, it } from 'vitest';
import { canUseHauntedChat, getHauntedWinner, resolveNightOutcome, resolveVoteOutcome } from './hauntedRules';

describe('haunted camp rules', () => {
  it('locks player chat throughout night and morning, including for living players', () => {
    expect(canUseHauntedChat('night', true)).toBe(false);
    expect(canUseHauntedChat('morning', true)).toBe(true);
  });
  it('allows living players to chat at dawn and during day, and everyone after the game ends', () => {
    expect(canUseHauntedChat('morning', true)).toBe(true);
    expect(canUseHauntedChat('day', true)).toBe(true);
    expect(canUseHauntedChat('day', false)).toBe(false);
    expect(canUseHauntedChat('ended', false)).toBe(true);
  });
  it('saves the target when faqih protects the same player', () => {
    expect(resolveNightOutcome('player-a', 'player-a')).toEqual({ killedUserId: null, saved: true });
  });
  it('kills the selected target when protection differs or is missing', () => {
    expect(resolveNightOutcome('player-a', 'player-b')).toEqual({ killedUserId: 'player-a', saved: false });
    expect(resolveNightOutcome('player-a', null)).toEqual({ killedUserId: 'player-a', saved: false });
  });
  it('starts a second ballot when the first ballot is tied', () => {
    expect(resolveVoteOutcome(['a','a','b','b'], 1)).toEqual({ outcome: 'revote', targetId: null });
  });
  it('ejects nobody when the second ballot is still tied', () => {
    expect(resolveVoteOutcome(['a','a','b','b'], 2)).toEqual({ outcome: 'no_ejection', targetId: null });
  });
  it('does not eject anyone when nobody votes before the deadline', () => {
    expect(resolveVoteOutcome([], 1)).toEqual({ outcome: 'no_ejection', targetId: null });
  });
  it('ejects the unique top-voted player', () => {
    expect(resolveVoteOutcome(['a','a','b'], 1)).toEqual({ outcome: 'ejected', targetId: 'a' });
  });
  it('awards villagers if the haunter is ejected and haunter if one villager remains', () => {
    expect(getHauntedWinner('ghost','ghost',4)).toBe('villagers');
    expect(getHauntedWinner('ghost',null,1)).toBe('haunter');
    expect(getHauntedWinner('ghost',null,2)).toBeNull();
  });
});
