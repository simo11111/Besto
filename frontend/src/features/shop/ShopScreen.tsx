import { Gem } from 'lucide-react';
import { PageHead } from '../shared/ui';
import type { Item, Profile } from '../shared/types';

type Props = {
  items: Item[];
  inventory: string[];
  profile: Profile | null;
  busy: boolean;
  buyItem: (item: Item) => void;
  equipItem: (item: Item) => void;
};

export default function ShopScreen({ items, inventory, profile, busy, buyItem, equipItem }: Props) {
  return <>
    <PageHead eyebrow="PLAYER MARKET" title="متجر الزينة" subtitle="صرف العملات ديالك على إطارات وألقاب نادرة." />
    <div className="shop-balance">
      <span><b className="currency-coin">C</b> {(profile?.coins || 0).toLocaleString('en-US')} Coins</span>
      <span><Gem size={16} /> {(profile?.gems || 0).toLocaleString('en-US')} Gems</span>
    </div>
    <div className="shop-grid">
      {items.map((item) => {
        const equipped = (item.category === 'frame' && profile?.equipped_frame === item.id)
          || (item.category === 'title' && profile?.equipped_title === item.name);
        const owned = inventory.includes(item.id);
        const balance = item.currency === 'gems' ? (profile?.gems || 0) : (profile?.coins || 0);
        return <article className="shop-item" key={item.id}>
          <div className={'shop-preview cosmetic-preview ' + item.rarity + ' ' + item.category}>
            <img src={'/cosmetics/' + item.id + '.svg'} alt={item.name} loading="lazy" />
          </div>
          <span className={'rarity ' + item.rarity}>{item.rarity}</span>
          <h3>{item.name}</h3>
          <small>{item.category === 'frame' ? 'إطار البروفايل' : 'لقب اللاعب'}</small>
          <div className="shop-item-bottom">
            <b>{item.currency === 'gems' ? <Gem size={15} /> : <span className="currency-coin small">C</span>}{item.price}</b>
            {owned
              ? <button className="secondary" disabled={equipped} onClick={() => equipItem(item)}>{equipped ? 'مجهّز' : 'جهّز'}</button>
              : <button className="primary" disabled={busy || balance < item.price} onClick={() => buyItem(item)}>شري</button>}
          </div>
        </article>;
      })}
    </div>
  </>;
}
