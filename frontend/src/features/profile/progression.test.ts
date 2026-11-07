import { describe, expect, it } from 'vitest';
import { xpForNext, xpProgress } from './progression';

describe('profile progression', () => {
  it('uses a quadratic level threshold with a 100 XP minimum', () => {
    expect(xpForNext(1)).toBe(100);
    expect(xpForNext(2)).toBe(400);
    expect(xpForNext(5)).toBe(2500);
  });

  it('clamps progress to the current level range', () => {
    expect(xpProgress(0, 1)).toBe(0);
    expect(xpProgress(250, 2)).toBeCloseTo(50);
    expect(xpProgress(1000, 2)).toBe(100);
  });

  it('does not divide by zero for unusual level input', () => {
    expect(Number.isFinite(xpProgress(10, 0))).toBe(true);
  });
});
