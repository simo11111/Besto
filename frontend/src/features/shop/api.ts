import type { Item } from '../shared/types';
import type { supabase } from '../../lib/supabase';

type Client = NonNullable<typeof supabase>;

export async function fetchShopInventory(client: Client, userId: string) {
  const [{ data: catalog, error }, { data: owned, error: ownedError }] = await Promise.all([
    client.from('cosmetic_catalog').select('*').order('price'),
    client.from('player_inventory').select('cosmetic_id').eq('user_id', userId),
  ]);
  return {
    items: (catalog ?? []) as Item[],
    inventory: (owned ?? []).map((item) => item.cosmetic_id as string),
    catalogError: error,
    inventoryError: ownedError,
  };
}
