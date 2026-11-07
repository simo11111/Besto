export const CONNECT_FOUR_ROWS = 6;
export const CONNECT_FOUR_COLUMNS = 7;
export type Disc = 0 | 1 | 2;
export type ConnectFourBoard = Disc[];

export function createEmptyBoard(): ConnectFourBoard {
  return Array<Disc>(CONNECT_FOUR_ROWS * CONNECT_FOUR_COLUMNS).fill(0);
}

export function dropDisc(
  board: readonly Disc[],
  column: number,
  disc: Exclude<Disc, 0>
): ConnectFourBoard | null {
  if (board.length !== CONNECT_FOUR_ROWS * CONNECT_FOUR_COLUMNS) return null;
  if (!Number.isInteger(column) || column < 0 || column >= CONNECT_FOUR_COLUMNS) return null;
  const next = [...board];
  for (let row = CONNECT_FOUR_ROWS - 1; row >= 0; row -= 1) {
    const index = row * CONNECT_FOUR_COLUMNS + column;
    if (next[index] === 0) {
      next[index] = disc;
      return next;
    }
  }
  return null;
}

export function getWinningCells(board: readonly Disc[], lastIndex: number): number[] {
  if (board.length !== CONNECT_FOUR_ROWS * CONNECT_FOUR_COLUMNS) return [];
  if (!Number.isInteger(lastIndex) || lastIndex < 0 || lastIndex >= board.length) return [];
  const disc = board[lastIndex];
  if (disc === 0) return [];

  const row = Math.floor(lastIndex / CONNECT_FOUR_COLUMNS);
  const column = lastIndex % CONNECT_FOUR_COLUMNS;
  const directions = [[0, 1], [1, 0], [1, 1], [1, -1]] as const;

  for (const [rowStep, columnStep] of directions) {
    const line = [lastIndex];
    for (const sign of [-1, 1] as const) {
      for (let step = 1; step <= 3; step += 1) {
        const nextRow = row + sign * step * rowStep;
        const nextColumn = column + sign * step * columnStep;
        if (
          nextRow < 0 ||
          nextRow >= CONNECT_FOUR_ROWS ||
          nextColumn < 0 ||
          nextColumn >= CONNECT_FOUR_COLUMNS
        ) break;
        const index = nextRow * CONNECT_FOUR_COLUMNS + nextColumn;
        if (board[index] !== disc) break;
        line.push(index);
      }
    }
    if (line.length >= 4) return line;
  }
  return [];
}

export function isBoardFull(board: readonly Disc[]): boolean {
  return board.length === CONNECT_FOUR_ROWS * CONNECT_FOUR_COLUMNS && board.every((cell) => cell !== 0);
}
