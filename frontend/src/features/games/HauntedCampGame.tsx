import { useEffect, useMemo, useState } from 'react';
import { Shield, Skull, Moon, Sun, Volume2, VolumeX, Clock3, Users, MessageCircle, Mic, MicOff, Trophy, Sparkles, RefreshCw } from 'lucide-react';
import { useHauntedGame } from '../../hooks/useHauntedGame';
import { playHauntedSound, startNightAmbience, stopNightAmbience } from '../../lib/hauntedAudio';
import { getSoundEnabled, setSoundEnabled as persistSoundEnabled } from '../../lib/audio';
import type { HauntedRole } from '../../types/haunted';

type RosterMember = { user_id: string; profile?: { username?: string; avatar_url?: string | null } };
type ChatMessage = { id: string; user_id: string; body: string; created_at?: string };
type Props = {
  roomId: string; userId: string; isHost: boolean; roster: RosterMember[];
  messages: ChatMessage[]; voiceActive: boolean; voiceMuted: boolean; voiceStatus: string;
  onBack: () => void; onExit: () => void; onSendChat: (text: string) => Promise<void>;
  onToggleVoice: () => void; onToggleMute: () => void; onNightMute: (muted: boolean) => void;
  onRewardsUpdated: () => void;
};

const roleCopy: Record<HauntedRole, { name: string; icon: string; title: string; description: string }> = {
  haunter: { name: 'المسكون', icon: '👻', title: 'نتا المسكون', description: 'كل ليلة اختار لاعب حي باش تخرجو من المخيم. خليك مخفي وحاول ما يتكشفش أمرك.' },
  faqih: { name: 'الفقيه', icon: '🛡️', title: 'نتا الفقيه', description: 'كل ليلة اختار لاعب تحميه. ما عندك حتى معلومة على المسكون، والنتيجة كتبان غير مع الصباح.' },
  villager: { name: 'مواطن', icon: '🏕️', title: 'نتا من سكان المخيم', description: 'ما عندكش اختيار فالليل. نهاراً ناقش مع صحابك وصوّت على اللي شاك فيه.' }
};

export default function HauntedCampGame(props: Props) {
  const { roomId, userId, isHost, roster, messages, onBack, onExit, onSendChat, voiceActive, voiceMuted, voiceStatus, onToggleVoice, onToggleMute, onNightMute, onRewardsUpdated } = props;
  const [quickMode, setQuickMode] = useState(roster.length === 4);
  const [revealed, setRevealed] = useState(false);
  const [target, setTarget] = useState('');
  const [chatText, setChatText] = useState('');
  const [now, setNow] = useState(Date.now());
  const [soundOn, setSoundOn] = useState(() => getSoundEnabled());
  const [previousPhase, setPreviousPhase] = useState<string | null>(null);
  const [previousEventCount, setPreviousEventCount] = useState(0);
  const { state, busy, error, start, submitKill, submitProtection, resolveNight, advanceMorning, submitVote, resolveVote, refresh } =
    useHauntedGame(null, roomId, userId, isHost);

  const myRole = state?.role;
  const role = myRole ? roleCopy[myRole] : null;
  const alivePlayers = useMemo(() => state?.players.filter(p => p.is_alive) ?? [], [state?.players]);
  const secondsLeft = state?.phase_deadline_at ? Math.max(0, Math.ceil((new Date(state.phase_deadline_at).getTime() - now) / 1000)) : 0;
  const latestNight = [...(state?.events ?? [])].reverse().find(e => e.event_type === 'night_resolved');
  const latestVoteEvent = [...(state?.events ?? [])].reverse().find(e => ['player_ejected','vote_tie_resolved','vote_tied'].includes(e.event_type));
  const nightReady = Boolean(state?.night_actions_ready);
  const voteCount = Number(state?.vote_count ?? 0);
  const isAlive = alivePlayers.some(player => player.user_id === userId);
  const aliveCount = alivePlayers.length;
  const voted = Boolean(state?.my_vote);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 500);
    return () => window.clearInterval(timer);
  }, []);
  useEffect(() => {
    const phase = state?.status ?? null;
    if (!phase || phase === previousPhase) return;
    if (phase === 'night') { startNightAmbience(); onNightMute(true); }
    else { stopNightAmbience(); onNightMute(false); }
    if (phase === 'morning') playHauntedSound('morning');
    if (phase === 'day') playHauntedSound('morning');
    if (phase === 'ended') playHauntedSound(state?.winner === 'villagers' ? 'win' : 'lose');
    setPreviousPhase(phase);
  }, [state?.status, state?.winner, previousPhase, onNightMute]);
  useEffect(() => { setPreviousEventCount(0); }, [state?.id]);
  useEffect(() => {
    const count = state?.events.length ?? 0;
    if (count <= previousEventCount) return;
    const fresh = state?.events.slice(previousEventCount) ?? [];
    fresh.forEach(event => {
      if (event.event_type === 'night_resolved') {
        if (event.payload.killed_user_id) playHauntedSound('death');
        else if (event.payload.saved) playHauntedSound('save');
      }
      if (event.event_type === 'player_ejected') playHauntedSound('eject');
      if (event.event_type === 'game_ended') onRewardsUpdated();
    });
    setPreviousEventCount(count);
  }, [state?.events, previousEventCount, onRewardsUpdated]);
  useEffect(() => () => { stopNightAmbience(); onNightMute(false); }, [onNightMute]);

  async function startGame() {
    const ok = await start(roomId, quickMode);
    if (ok) { setRevealed(false); playHauntedSound('role'); }
  }
  async function submitNightChoice() {
    if (!target || !state) return;
    const ok = myRole === 'haunter' ? await submitKill(target) : await submitProtection(target);
    if (ok) { setTarget(''); playHauntedSound('vote'); }
  }
  async function submitDayVote() {
    if (!target) return;
    const ok = await submitVote(target);
    if (ok) { setTarget(''); playHauntedSound('vote'); }
  }

  if (!state) {
    return <section className="haunted-shell haunted-lobby">
      <div className="haunted-stars" aria-hidden="true"/><div className="haunted-header"><span className="haunted-kicker">MIMOX · SOCIAL DEDUCTION</span><h1>👻 الفقيه والمسكون</h1><p>ليلة طويلة، أسرار مخفية، وشكون غادي يخرج من الخيمة؟</p></div>
      <div className="haunted-lobby-grid"><div className="haunted-lobby-card"><h2><Users size={18}/> المخيم ديالكم</h2><div className="haunted-roster">{roster.map((player,index)=><div className="haunted-player" key={player.user_id}><span className="haunted-player-index">{String(index+1).padStart(2,'0')}</span><span className="haunted-avatar">{player.profile?.avatar_url?<img src={player.profile.avatar_url} alt=""/>:(player.profile?.username||'؟').slice(0,1)}</span><span className="haunted-player-name">{player.profile?.username||'لاعب'}</span>{player.user_id===userId&&<small>أنت</small>}</div>)}</div><div className="haunted-mode-toggle"><label><input type="checkbox" checked={quickMode} onChange={e=>setQuickMode(e.target.checked)}/> الطور السريع بلا فقيه (4–10 لاعبين)</label><small>{quickMode?'المسكون واحد والباقي مواطنين.':'المسكون والفقيه والمواطنين.'}</small></div>{!isHost&&<p className="haunted-waiting">كنستناو مول الغرفة يبدا اللعبة…</p>}<button className="haunted-primary" disabled={!isHost||busy||roster.length<(quickMode?4:5)||roster.length>10} onClick={()=>void startGame()}>{busy?'كنوجدو المخيم...':'🌙 بدا الليلة الأولى'}</button></div>
      <aside className="haunted-rules-card"><span className="haunted-kicker">كيفاش كتتلعب؟</span><h2>القواعد بسرعة</h2><ol><li>فالليل، المسكون كيختار ضحية والفقيه كيحمي لاعب بلا ما يعرف شكون المسكون.</li><li>فالصباح، كنعلنو غير واش مات شي حد ولا نجا المخيم.</li><li>فالنهار، ناقشو وصوّتو على اللي شاكين فيه.</li><li>إلا تطرد المسكون، المواطنين كيربحو. إلا بقاو مواطن أو أقل، المسكون كيربح.</li></ol><div className="haunted-role-legend"><span>👻 المسكون</span><span>🛡️ الفقيه</span><span>🏕️ المواطنون</span></div></aside></div>
      {error&&<p className="haunted-error" role="alert">{error}</p>}
      <div className="haunted-footer-actions"><button className="haunted-ghost-button" onClick={onBack}>رجوع للّوبي</button><button className="haunted-ghost-button" onClick={onExit}>خروج من الغرفة</button></div>
    </section>;
  }

  return <section className={'haunted-shell haunted-phase-' + state.status} aria-label="لعبة الفقيه والمسكون">
    <div className="haunted-stars" aria-hidden="true"/><div className="haunted-mist" aria-hidden="true"/>
    <header className="haunted-topbar"><div><span className="haunted-kicker">HAUNTED CAMP · ROUND {state.round}</span><h1>ليلة فالخيمة</h1></div><div className="haunted-top-actions"><span className="haunted-round-pill">الجولة {state.round}</span><button className="haunted-icon-button" onClick={()=>{const next=!soundOn;setSoundOn(next);persistSoundEnabled(next);}} aria-label={soundOn?'كتم المؤثرات':'تشغيل المؤثرات'}>{soundOn?<Volume2/>:<VolumeX/>}</button><button className="haunted-ghost-button" onClick={onBack}>اللوبي</button></div></header>
    <div className="haunted-phase-banner">
      {state.status==='night'?<><Moon/><span>الليل هبط على المخيم</span></>:state.status==='morning'?<><Sun/><span>طلع الصباح… شنو وقع فالليل؟</span></>:state.status==='day'?<><Sun/><span>وقت النقاش والتصويت</span></>:<><Trophy/><span>سالَت الحكاية</span></>}
      {state.status!=='ended'&&<strong><Clock3 size={15}/>{secondsLeft}ث</strong>}
    </div>
    {!revealed&&role&&<button className="haunted-role-cover" onClick={()=>{setRevealed(true);playHauntedSound('role');}}><span>🔒</span><b>كشف الدور السري ديالك</b><small>ما تورّيه حتى لواحد</small></button>}
    {revealed&&role&&<article className="haunted-role-card"><div className="haunted-role-card-inner"><span>{role.icon}</span><small>الدور السري ديالك</small><h2>{role.title}</h2><p>{role.description}</p></div></article>}

    {state.status==='night'&&<div className="haunted-night-panel"><div className="haunted-moon">🌙</div><h2>{myRole==='haunter'?'اختار الضحية ديالك':myRole==='faqih'?'شكون غادي تعتق الليلة؟':'نعس… الليل ماشي وقت الكلام'}</h2><p>{myRole==='haunter'?'اختار لاعب حي واحد. القرار سري وما غادي يبان حتى واحد.':myRole==='faqih'?'اختار لاعب تحميه. ما غاديش تعرف واش الحماية نجحات حتى يطلع الصباح.':'تسنى الصباح. الميكروفونات مكتومة فالليل.'}</p>
      {!isAlive&&<p className="haunted-waiting">خرجتي من اللعبة، تقدر تبقى تتفرج ولكن ما تقدرش تختار أو تصوّت.</p>}
      {isAlive&&['haunter','faqih'].includes(myRole||'')&&<div className="haunted-target-grid">{alivePlayers.filter(p=>myRole==='haunter'?p.user_id!==userId:true).map(player=><button type="button" key={player.user_id} className={'haunted-target '+(target===player.user_id?'selected':'')} onClick={()=>setTarget(player.user_id)}><span>{player.avatar_url?<img src={player.avatar_url} alt=""/>:(player.username||'؟').slice(0,1)}</span><b>{player.username}</b></button>)}</div>}
      {isAlive&&['haunter','faqih'].includes(myRole||'')&&<button className="haunted-primary" disabled={busy||!target} onClick={()=>void submitNightChoice()}>{myRole==='haunter'?'🗡️ تأكيد اختيار الضحية':'🛡️ تأكيد الحماية'}</button>}
      {myRole==='villager'&&<div className="haunted-waiting">القرارات الليلية كتتدار بسرية تامة.</div>}
      {isHost&&<button className="haunted-secondary" disabled={busy||(!nightReady&&secondsLeft>0)} onClick={()=>void resolveNight()}>{busy?'كنحسبو...':'حسم الليل وكشف الصباح'}</button>}
    </div>}

    {state.status==='morning'&&<div className={'haunted-morning-panel '+(latestNight?.payload.killed_user_id?'has-death':'saved')}><div className="haunted-sunrise"/><span className="haunted-morning-emoji">{latestNight?.payload.killed_user_id?'🪦':'✨'}</span><h2>{latestNight?.payload.killed_user_id?'لقينا لاعب ميت فالصباح':'نجا المخيم هاد الليلة!'}</h2><p>{latestNight?.payload.killed_user_id?('اللاعب '+(state.players.find(p=>p.user_id===latestNight.payload.killed_user_id)?.username||'المجهول')+' خرج من اللعبة. الدور ديالو باقي سري.'):'ما مات حتى واحد. ما كاين حتى كشف شكون تحمى ولا شكون حاول يقتل.'}</p>{isHost&&<button className="haunted-primary" disabled={busy||secondsLeft>0} onClick={()=>void advanceMorning()}>دخل لمرحلة النهار ☀️</button>}</div>}

    {state.status==='day'&&<div className="haunted-day-grid"><section className="haunted-vote-panel">{latestVoteEvent&&<div className="haunted-outcome-banner">{String(latestVoteEvent.payload.message||'نتيجة التصويت تسجلات.')}{latestVoteEvent.payload.ejected_user_id&&' '+(state.players.find(p=>p.user_id===latestVoteEvent.payload.ejected_user_id)?.username||'لاعب')+' خرج من المخيم.'}</div>}<h2>🗳️ شكون كتشُك فيه؟</h2><p>صوّت على لاعب حي. الأصوات ديالك سرية حتى يتحسم التصويت.</p><div className="haunted-target-grid">{alivePlayers.filter(p=>p.user_id!==userId).map(player=><button type="button" key={player.user_id} disabled={voted||busy} className={'haunted-target '+(target===player.user_id?'selected':'')} onClick={()=>setTarget(player.user_id)}><span>{player.avatar_url?<img src={player.avatar_url} alt=""/>:(player.username||'؟').slice(0,1)}</span><b>{player.username}</b></button>)}</div><button className="haunted-primary" disabled={busy||voted||!target} onClick={()=>void submitDayVote()}>{voted?'صوتك تسجل':'تأكيد التصويت'}</button><div className="haunted-vote-count"><b>{voteCount}/{aliveCount}</b><span>أصوات تسجلات</span><small>{state.vote_round===2?'إعادة التصويت بعد التعادل':'التصويت الأول'}</small></div>{isHost&&<button className="haunted-secondary" disabled={busy||(voteCount<aliveCount&&secondsLeft>0)} onClick={()=>void resolveVote()}>حسم التصويت</button>}</section>
      <section className="haunted-discussion"><h2><MessageCircle/> النقاش ديال النهار</h2><div className="haunted-chat-messages">{messages.slice(-10).map(m=><p key={m.id}><b>{m.user_id===userId?'أنت':roster.find(x=>x.user_id===m.user_id)?.profile?.username||'لاعب'}:</b> {m.body}</p>)}</div><form onSubmit={e=>{e.preventDefault();if(chatText.trim()){void onSendChat(chatText.trim());setChatText('');}}}><input value={chatText} onChange={e=>setChatText(e.target.value)} maxLength={500} placeholder="شارك الشكوك ديالك..."/><button type="submit" disabled={!chatText.trim()}>إرسال</button></form><div className="haunted-voice-box"><div><Mic/><span><b>الصوت المباشر</b><small>{voiceStatus}</small></span></div><button onClick={onToggleVoice}>{voiceActive?'قطع الصوت':'دخل للصوت'}</button>{voiceActive&&<button onClick={onToggleMute}>{voiceMuted?<Mic/>:<MicOff/>}{voiceMuted?'حل المايك':'كتم المايك'}</button>}</div></section></div>}

    {state.status==='ended'&&<div className="haunted-end-panel"><div className="haunted-win-icon">{state.winner==='villagers'?'🏕️':'👻'}</div><span className="haunted-kicker">THE CAMP HAS SPOKEN</span><h2>{state.winner==='villagers'?'المواطنين ربحو!':'المسكون سيطر على المخيم!'}</h2><p>ها الأدوار الحقيقية ديال جميع اللاعبين:</p><div className="haunted-role-reveal-list">{state.roles.map(item=>{const player=state.players.find(p=>p.user_id===item.user_id);return <div key={item.user_id}><span>{roleCopy[item.role].icon}</span><b>{player?.username||'لاعب'}</b><small>{roleCopy[item.role].name}</small></div>;})}</div><button className="haunted-primary" onClick={()=>void refresh()}><RefreshCw/> تحديث النتيجة</button><button className="haunted-secondary" onClick={onBack}>رجوع للّوبي</button></div>}

    {error&&<p className="haunted-error" role="alert">{error}</p>}
    <footer className="haunted-bottom-bar"><div><span>{aliveCount} باقيين أحياء</span><small>{state.game_mode==='quick'?'طور سريع · بلا فقيه':'طور عادي'}</small></div><button className="haunted-ghost-button" onClick={onExit}>خروج من الغرفة</button></footer>
  </section>;
}
