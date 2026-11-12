import { useMemo, useState } from 'react';
import { Coins, Gift, Sparkles, Crown, Frame, Check, ShoppingBag } from 'lucide-react';
import { PageHead } from '../shared/ui';
import type { Item, Profile } from '../shared/types';

type Props = {
  items: Item[];
  inventory: string[];
  profile: Profile | null;
  friends: { profile?: { id: string; username: string } }[];
  giftRecipient: string;
  onGiftRecipientChange: (value: string) => void;
  giftItem: (item: Item) => void;
  busy: boolean;
  buyItem: (item: Item) => void;
  equipItem: (item: Item) => void;
};

type ShopFilter = 'all' | 'frame' | 'title';

export default function ShopScreen({ items, inventory, profile, friends, giftRecipient, onGiftRecipientChange, giftItem, busy, buyItem, equipItem }: Props) {
  const [filter, setFilter] = useState<ShopFilter>('all');
  const visibleItems = useMemo(() => items.filter(item => filter === 'all' || item.category === filter), [items, filter]);
  const coins = profile?.coins || 0;

  return <>
    <PageHead eyebrow="CAMP MARKET" title="سوق المخيم" subtitle="جمع ستايلك، زيّن بروفايلك، وخلي حضورك مميز وسط المخيم." />
    <section className="shop-hero">
      <div className="shop-hero-copy"><span><Sparkles size={15}/> متجر ليلة فالخيمة</span><h2>خلي شخصيتك تحكي عليك</h2><p>إطارات وألقاب حصرية، كتفتحها بالعملات اللي كتجمع من اللعب والمهمات.</p></div>
      <div className="shop-coin-card"><small>رصيدك الحالي</small><strong><Coins size={24}/> {coins.toLocaleString('en-US')}</strong><span>عملة المخيم</span></div>
    </section>
    {friends.length > 0 && <div className="gift-toolbar shop-gift-toolbar"><div><Gift size={20}/><span><b>هدية لصاحبك</b><small>اختار صديق وصيفط ليه زينة من المتجر.</small></span></div><select value={giftRecipient} onChange={event=>onGiftRecipientChange(event.target.value)}><option value="">اختار صديق</option>{friends.filter(friend=>friend.profile?.id).map(friend=><option key={friend.profile!.id} value={friend.profile!.id}>{friend.profile!.username}</option>)}</select></div>}
    <div className="shop-section-head"><div><span>COLLECTION</span><h2>مجموعة الزينة</h2><small>{items.length} قطعة متاحة · الأداء بالعملات فقط</small></div><div className="shop-filter-tabs"><button className={filter==='all'?'active':''} onClick={()=>setFilter('all')}>الكل</button><button className={filter==='frame'?'active':''} onClick={()=>setFilter('frame')}><Frame size={14}/> الإطارات</button><button className={filter==='title'?'active':''} onClick={()=>setFilter('title')}><Crown size={14}/> الألقاب</button></div></div>
    <div className="shop-grid shop-grid-premium">{visibleItems.map(item => {
      const equipped = (item.category === 'frame' && profile?.equipped_frame === item.id) || (item.category === 'title' && profile?.equipped_title === item.name);
      const owned = inventory.includes(item.id);
      return <article className={'shop-item shop-item-premium rarity-card ' + item.rarity} key={item.id}>
        <div className={'shop-preview shop-preview-premium cosmetic-preview ' + item.rarity + ' ' + item.category}><img src={'/cosmetics/' + item.id + '.svg'} alt={item.name} loading="lazy" /></div>
        <div className="shop-card-meta"><span className={'rarity rarity-pill ' + item.rarity}>{item.rarity==='legendary'?'أسطوري':item.rarity==='epic'?'ملحمي':'نادر'}</span><small>{item.category === 'frame' ? 'إطار بروفايل' : 'لقب اللاعب'}</small></div>
        <h3>{item.name}</h3>
        <div className="shop-item-bottom shop-item-bottom-premium"><b><Coins size={16}/>{item.price.toLocaleString('en-US')}</b>
          {owned ? <button className={equipped?'shop-equipped':'shop-equip'} disabled={equipped} onClick={() => equipItem(item)}>{equipped?<><Check size={14}/> مجهّز</>:'جهّز'}</button> : <button className="shop-buy" disabled={busy || coins < item.price} onClick={() => buyItem(item)}><ShoppingBag size={14}/> {coins < item.price ? 'العملات ما كافياش' : 'شري بالعملات'}</button>}
          {!owned&&friends.length>0&&<button className="gift-item-btn" disabled={busy||!giftRecipient} onClick={()=>giftItem(item)}><Gift size={14}/></button>}
        </div>
      </article>;
    })}</div>
    {visibleItems.length===0&&<div className="empty-state"><ShoppingBag/><b>ما كايناش زينة فهاد التصنيف دابا</b></div>}
  </>;
}
