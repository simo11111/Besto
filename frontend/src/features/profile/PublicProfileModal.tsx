import { useEffect, useState } from 'react';
import { Award, Gamepad2, Gem, ShieldCheck, Trophy, UserPlus, X } from 'lucide-react';
import { supabase } from '../../lib/supabase';

type PublicProfile = {
  id: string; username: string; avatar_url: string | null; bio: string | null;
  xp: number; level: number; wins: number; games_played: number; total_score: number;
  streak_days: number; equipped_title: string | null; equipped_frame: string | null;
};

type Props = {
  userId: string; currentUserId: string; online: boolean; isFriend: boolean;
  onClose: () => void; onAddFriend: (username: string) => void;
};

export default function PublicProfileModal({ userId, currentUserId, online, isFriend, onClose, onAddFriend }: Props) {
  const [profile, setProfile] = useState<PublicProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let active = true;
    setLoading(true); setError(''); setProfile(null);
    if (!supabase) { setError('الخدمة ما متصلةش دابا.'); setLoading(false); return; }
    void supabase.from('profiles')
      .select('id,username,avatar_url,bio,xp,level,wins,games_played,total_score,streak_days,equipped_title,equipped_frame')
      .eq('id', userId).maybeSingle()
      .then(({ data, error: queryError }) => {
        if (!active) return;
        if (queryError) setError('ما قدرناش نجيبو البروفايل.'); else if (!data) setError('هاد البروفايل ما بقاش متاح.'); else setProfile(data as PublicProfile);
        setLoading(false);
      });
    return () => { active = false; };
  }, [userId]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return <div className="public-profile-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) onClose(); }}>
    <section className="public-profile-modal" role="dialog" aria-modal="true" aria-label="بروفايل اللاعب">
      <button className="public-profile-close" type="button" onClick={onClose} aria-label="إغلاق"><X size={19}/></button>
      {loading ? <div className="public-profile-state"><span className="public-profile-spinner"/>كنحمّلو البروفايل...</div> :
      error ? <div className="public-profile-state">{error}</div> : profile ? <>
        <div className="public-profile-cover"><span className="profile-cover-orbit orbit-one"/><span className="profile-cover-orbit orbit-two"/><span className="profile-cover-label">MIMOX PLAYER CARD</span></div>
        <div className="public-profile-identity">
          <div className={'public-profile-avatar '+(profile.equipped_frame||'default')}>{profile.avatar_url ? <img src={profile.avatar_url} alt={profile.username}/> : profile.username.slice(0,1).toUpperCase()}</div>
          <div className="public-profile-name"><h2>{profile.username}</h2><span className={'public-profile-status '+(online?'online':'')}>{online?'متصل الآن':'غير متصل'}</span><small>{profile.equipped_title||'لاعب MIMOX'} · المستوى {profile.level||1}</small></div>
        </div>
        {profile.bio && <p className="public-profile-bio">{profile.bio}</p>}
        <div className="public-profile-xp"><div><span>التقدم ديال اللاعب</span><b>{profile.xp.toLocaleString('en-US')} XP</b></div><div className="public-profile-xp-track"><span style={{width:Math.max(4,Math.min(100,(profile.xp%1000)/10))+'%'}}/></div></div>
        <div className="public-profile-stats">
          <div><Trophy/><b>{profile.wins.toLocaleString('en-US')}</b><small>انتصارات</small></div>
          <div><Gamepad2/><b>{profile.games_played.toLocaleString('en-US')}</b><small>مباريات</small></div>
          <div><Award/><b>{profile.total_score.toLocaleString('en-US')}</b><small>نقاط</small></div>
          <div><Gem/><b>{profile.streak_days.toLocaleString('en-US')}</b><small>أيام متتابعة</small></div>
        </div>
        <div className="public-profile-actions">
          {profile.id!==currentUserId && !isFriend && <button type="button" className="primary" onClick={()=>onAddFriend(profile.username)}><UserPlus size={16}/> إضافة صديق</button>}
          {isFriend && <span className="public-profile-friend"><ShieldCheck size={16}/> صديقك</span>}
          <button type="button" className="secondary" onClick={()=>{void navigator.clipboard?.writeText(profile.id);}}>نسخ Player ID</button>
        </div>
      </> : null}
    </section>
  </div>;
}
