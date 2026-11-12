import type { GameDefinition } from '../games/registry';
export const ROOM_CAPACITIES = [2, 4, 6, 8, 10, 12, 16] as const;
export function getRoomCapacityOptions(game: Pick<GameDefinition, 'mode' | 'minPlayers' | 'maxPlayers'>): number[] {
  return ROOM_CAPACITIES.filter((capacity) => capacity >= game.minPlayers && capacity <= game.maxPlayers);
}
export function normalizeRoomCapacity(game: Pick<GameDefinition, 'mode' | 'minPlayers' | 'maxPlayers'>, currentCapacity: number): number {
  const options = getRoomCapacityOptions(game);
  if (options.includes(currentCapacity)) return currentCapacity;
  return options.find((capacity) => capacity >= currentCapacity) ?? options[options.length - 1] ?? game.minPlayers;
}
