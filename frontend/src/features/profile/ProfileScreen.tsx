import type { FormEvent, RefObject } from 'react';
import { Flame, Gamepad2, Star, Trophy } from 'lucide-react';
import { Achievement, PageHead, Stat } from '../shared/ui';
import type { Profile } from '../shared/types';
import { xpForNext, xpProgress } from './progression';

type Props = {
  profile: Profile;
  profileName: string;
  bio: string;
  gender: 'male' | 'female';
  busy: boolean;
  avatarBusy: boolean;
  avatarInputRef: RefObject<HTMLInputElement>;
  onAvatarUpload: (file?: File) => void;
  onSave: (event: FormEvent<HTMLFormElement>) => void;
  onSignOut: () => void;
  onProfileNameChange: (value: string) => void;
  onBioChange: (value: string) => void;
  onGenderChange: (value: 'male' | 'female') => void;
  onCopyPlayerId: () => void;
};

export default function ProfileScreen({ profile, profileName, bio, gender, busy, avatarBusy, avatarInputRef, onAvatarUpload, onSave, onSignOut, onProfileNameChange, onBioChange, onGenderChange, onCopyPlayerId }: Props) {
  return <>
    <PageHead eyebrow="PLAYER PROFILE" title="البروفايل ديالك" subtitle="طور المستوى ديالك، جمع الإنجازات وخلي بصمتك فالمخيم." />
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
    </div>
    <div className="stat-grid"><Stat icon={<Trophy />} value={profile.wins} label="انتصارات" /><Stat icon={<Gamepad2 />} value={profile.games_played} label="مباريات" /><Stat icon={<Star />} value={profile.total_score} label="مجموع النقاط" /><Stat icon={<Flame />} value={profile.streak_days} label="سلسلة الأيام" /></div>
    <form className="profile-form" onSubmit={onSave}>
      <h3>تعديل المعلومات</h3>
      <button type="button" className="secondary" disabled={avatarBusy} onClick={() => avatarInputRef.current?.click()}>{avatarBusy ? 'كنرفع الصورة...' : 'تغيير صورة البروفايل'}</button>
      <label>اسم اللاعب<input value={profileName} onChange={(event) => onProfileNameChange(event.target.value)} minLength={3} maxLength={20} /></label>
      <label>الشخصية ديالك فالمخيم
        <select value={gender} onChange={(event) => onGenderChange(event.target.value as 'male' | 'female')}>
          <option value="female">أنثى — شخصية أنمي بنت</option>
          <option value="male">ذكر — شخصية أنمي ولد</option>
        </select>
      </label>
      <label>نبذة قصيرة<textarea value={bio} onChange={(event) => onBioChange(event.target.value)} maxLength={120} /></label>
      <button className="primary" disabled={busy}>حفظ التغييرات</button>
    </form>
    <section className="section"><div className="section-head"><h2>الإنجازات</h2></div><div className="achievement-grid">
      <Achievement icon={<Gamepad2 />} name="أول لعيبة" desc="كمل أول لعبة" unlocked={profile.games_played > 0} />
      <Achievement icon={<Trophy />} name="أول فوز" desc="ربح أول مباراة" unlocked={profile.wins > 0} />
      <Achievement icon={<Flame />} name="مواظب" desc="دخل 3 أيام متتابعة" unlocked={profile.streak_days >= 3} />
      <Achievement icon={<Star />} name="مستكشف المخيم" desc="شارك فـ5 مباريات" unlocked={profile.games_played >= 5} />
    </div></section>
    <button className="logout-button" onClick={onSignOut}>تسجيل الخروج من الحساب</button>
  </>;
}
