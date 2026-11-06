import type { FormEvent, RefObject } from 'react';
import { ChevronLeft, Flame, Gamepad2, Gem, Star, Trophy } from 'lucide-react';
import { Achievement, PageHead, Stat } from '../shared/ui';
import type { Item, Profile } from '../shared/types';
import { xpForNext, xpProgress } from './progression';

type Props = {
  profile: Profile;
  items: Item[];
  inventory: string[];
  profileName: string;
  bio: string;
  busy: boolean;
  avatarBusy: boolean;
  avatarInputRef: RefObject<HTMLInputElement | null>;
  onAvatarUpload: (file?: File) => void;
  onEquipItem: (item: Item) => void;
  onSave: (event: FormEvent<HTMLFormElement>) => void;
  onSignOut: () => void;
  onOpenShop: () => void;
  onProfileNameChange: (value: string) => void;
  onBioChange: (value: string) => void;
  onCopyPlayerId: () => void;
};

export default function ProfileScreen({ profile, items, inventory, profileName, bio, busy, avatarBusy, avatarInputRef, onAvatarUpload, onEquipItem, onSave, onSignOut, onOpenShop, onProfileNameChange, onBioChange, onCopyPlayerId }: Props) {
  return <>
    <PageHead eyebrow="PLAYER PROFILE" title="البروفايل ديالك" subtitle="طور المستوى ديالك، جمع الإنجازات وزيّن الحساب." />
    <div className="profile-hero">
      <button type="button" className={'profile-avatar ' + profile.equipped_frame + ' profile-avatar-button'} onClick={() => avatarInputRef.current?.click()} title="بدّل صورة البروفايل">
        {profile.avatar_url ? <img src={profile.avatar_url} alt="صورة البروفايل" /> : profile.username.slice(0, 1).toUpperCase()}
      </button>
      <input ref={avatarInputRef} type="file" accept="image/*" hidden onChange={(event) => onAvatarUpload(event.target.files?.[0])} />
      <div className="profile-main">
        <h2>{profile.username}</h2>
        <p>{profile.equipped_title} · المستوى {profile.level}</p>
        <button type="button" className="player-id-copy" onClick={onCopyPlayerId}>Player ID: {profile.id.slice(0, 8)}… <span>نسخ</span></button>
        <div className="xp-track"><span style={{ width: xpProgress(profile.xp, profile.level) + '%' }} /></div>
        <small>{profile.xp} XP / {xpForNext(profile.level)} XP</small>
      </div>
      <div className="profile-currencies">
        <span><b className="currency-coin">C</b>{profile.coins.toLocaleString('en-US')}</span>
        <span><Gem size={16} />{(profile.gems || 0).toLocaleString('en-US')}</span>
      </div>
    </div>
    <section className="frame-selector">
      <div className="section-head"><div><div className="eyebrow">PROFILE CUSTOMIZATION</div><h3>الإطار ديال البروفايل</h3></div><button className="link-button" onClick={onOpenShop}>زيد إطارات <ChevronLeft size={15} /></button></div>
      <div className="frame-selector-grid">{items.filter((item) => item.category === 'frame' && inventory.includes(item.id)).map((item) => <button type="button" key={item.id} className={'frame-choice ' + (profile.equipped_frame === item.id ? 'active' : '')} onClick={() => onEquipItem(item)}><img src={'/cosmetics/' + item.id + '.svg'} alt={item.name} /><span>{item.name}</span>{profile.equipped_frame === item.id && <small>مجهز</small>}</button>)}</div>
      {!items.some((item) => item.category === 'frame' && inventory.includes(item.id)) && <p className="muted">ما عندك حتى إطار دابا. دخل للمتجر واختار الإطار اللي عجبك.</p>}
    </section>
    <div className="stat-grid"><Stat icon={<Trophy />} value={profile.wins} label="انتصارات" /><Stat icon={<Gamepad2 />} value={profile.games_played} label="مباريات" /><Stat icon={<Star />} value={profile.total_score} label="مجموع النقاط" /><Stat icon={<Flame />} value={profile.streak_days} label="سلسلة الأيام" /></div>
    <form className="profile-form" onSubmit={onSave}>
      <h3>تعديل المعلومات</h3>
      <button type="button" className="secondary" disabled={avatarBusy} onClick={() => avatarInputRef.current?.click()}>{avatarBusy ? 'كنرفع الصورة...' : 'تغيير صورة البروفايل'}</button>
      <label>اسم اللاعب<input value={profileName} onChange={(event) => onProfileNameChange(event.target.value)} minLength={3} maxLength={20} /></label>
      <label>نبذة قصيرة<textarea value={bio} onChange={(event) => onBioChange(event.target.value)} maxLength={120} /></label>
      <button className="primary" disabled={busy}>حفظ التغييرات</button>
    </form>
    <section className="section"><div className="section-head"><h2>الإنجازات</h2></div><div className="achievement-grid">
      <Achievement icon={<Gamepad2 />} name="أول لعيبة" desc="كمل أول لعبة" unlocked={profile.games_played > 0} />
      <Achievement icon={<Trophy />} name="أول فوز" desc="ربح أول مباراة" unlocked={profile.wins > 0} />
      <Achievement icon={<Flame />} name="مواظب" desc="دخل 3 أيام متتابعة" unlocked={profile.streak_days >= 3} />
      <Achievement icon={<Gem />} name="جامع الزينة" desc="شري أول عنصر" unlocked={inventory.length > 0} />
    </div></section>
    <button className="logout-button" onClick={onSignOut}>تسجيل الخروج من الحساب</button>
  </>;
}
