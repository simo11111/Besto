import { describe, expect, it } from 'vitest';
import { createEmptyBoard, dropDisc, getWinningCells, isBoardFull } from './connectFour';

describe('Four-in-a-Row rules', () => {
  it('creates an empty 6 by 7 board', () => {
    expect(createEmptyBoard()).toHaveLength(42);
    expect(createEmptyBoard().every((cell) => cell === 0)).toBe(true);
  });
  it('drops a disc to the lowest free row', () => {
    const first = dropDisc(createEmptyBoard(), 3, 1);
    expect(first?.[38]).toBe(1);
    const second = first && dropDisc(first, 3, 2);
    expect(second?.[31]).toBe(2);
  });
  it('rejects invalid columns and full columns', () => {
    expect(dropDisc(createEmptyBoard(), -1, 1)).toBeNull();
    expect(dropDisc(createEmptyBoard(), 7, 1)).toBeNull();
    const fullColumn = Array.from({ length: 42 }, (_, index) => index % 7 === 2 ? 1 as const : 0 as const);
    expect(dropDisc(fullColumn, 2, 2)).toBeNull();
  });
  it('detects horizontal, vertical and diagonal wins', () => {
    const horizontal = createEmptyBoard();
    [0, 1, 2, 3].forEach((column) => { horizontal[35 + column] = 1; });
    expect(getWinningCells(horizontal, 38)).toHaveLength(4);
    const vertical = createEmptyBoard();
    [2, 3, 4, 5].forEach((row) => { vertical[row * 7 + 1] = 2; });
    expect(getWinningCells(vertical, 36)).toHaveLength(4);
    const diagonal = createEmptyBoard();
    diagonal[35] = 1; diagonal[29] = 1; diagonal[23] = 1; diagonal[17] = 1;
    expect(getWinningCells(diagonal, 17)).toHaveLength(4);
  });
  it('does not report a win for an unfinished line', () => {
    const board = createEmptyBoard();
    board[35] = 1; board[36] = 1; board[37] = 1;
    expect(getWinningCells(board, 37)).toEqual([]);
  });
  it('detects a full board', () => {
    expect(isBoardFull(Array.from({ length: 42 }, (_, index) => (index % 2 ? 1 : 2) as 1 | 2))).toBe(true);
    expect(isBoardFull(createEmptyBoard())).toBe(false);
  });
});
