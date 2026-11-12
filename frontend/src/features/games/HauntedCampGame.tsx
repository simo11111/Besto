import { useEffect, useMemo, useState } from 'react';
import { motion, useReducedMotion } from 'framer-motion';
import { Shield, Skull, Moon, Sun, Volume2, VolumeX, Clock3, Users, MessageCircle, Mic, MicOff, Trophy, Sparkles, RefreshCw } from 'lucide-react';
import { useHauntedGame } from '../../hooks/useHauntedGame';
import { playHauntedSound, startNightAmbience, stopNightAmbience, startMorningAmbience, stopMorningAmbience, preloadHauntedSounds, setHauntedAudioMuted, speakHauntedAnnouncement } from '../../lib/hauntedAudio';
import { getSoundEnabled, setSoundEnabled as persistSoundEnabled } from '../../lib/audio';
import type { HauntedRole } from '../../types/haunted';
import { getHauntedBotCount } from './hauntedNpcRoster';

type RosterMember = { user_id: string; profile?: { username?: string; avatar_url?: string | null } };
type ChatMessage = { id: string; user_id: string; body: string; created_at?: string };
type Props = {
  gameId: string; roomId: string; userId: string; isHost: boolean; roster: RosterMember[];
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
  const { gameId, roomId, userId, isHost, roster, messages, onBack, onExit, onSendChat, voiceActive, voiceMuted, voiceStatus, onToggleVoice, onToggleMute, onNightMute, onRewardsUpdated } = props;
  const reduceMotion = useReducedMotion();
  const [quickMode, setQuickMode] = useState(false);
  const [revealed, setRevealed] = useState(false);
  const [target, setTarget] = useState('');
  const [chatText, setChatText] = useState('');
  const [now, setNow] = useState(Date.now());
  const [soundOn, setSoundOn] = useState(() => getSoundEnabled());
  const [previousPhase, setPreviousPhase] = useState<string | null>(null);
  const [previousVotingOpen, setPreviousVotingOpen] = useState(false);
  const [previousEventCount, setPreviousEventCount] = useState(0);
  const { state, busy, error, start, submitKill, submitProtection, resolveNight, advanceMorning, submitVote, resolveVote, openVoting, refresh } =
    useHauntedGame(gameId || null, roomId, userId, isHost);

  const myRole = state?.role;
  const role = myRole ? roleCopy[myRole] : null;
  const alivePlayers = useMemo(() => state?.players.filter(p => p.is_alive) ?? [], [state?.players]);
  const lobbyBotCount = getHauntedBotCount(roster.length, quickMode);
  const secondsLeft = state?.phase_deadline_at ? Math.max(0, Math.ceil((new Date(state.phase_deadline_at).getTime() - now) / 1000)) : 0;
  const latestNight = [...(state?.events ?? [])].reverse().find(e => e.event_type === 'night_resolved');
  const latestVoteEvent = [...(state?.events ?? [])].reverse().find(e => ['player_ejected','vote_tie_resolved','vote_tied'].includes(e.event_type));
  const ejectedUserId = typeof latestVoteEvent?.payload.ejected_user_id === 'string' ? latestVoteEvent.payload.ejected_user_id : null;
  const nightReady = Boolean(state?.night_actions_ready);
  const voteCount = Number(state?.vote_count ?? 0);
  const isAlive = alivePlayers.some(player => player.user_id === userId);
  const aliveCount = alivePlayers.length;
  const voted = Boolean(state?.my_vote);

  useEffect(() => { preloadHauntedSounds(); }, []);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 500);
    return () => window.clearInterval(timer);
  }, []);
  useEffect(() => {
    const phase = state?.status ?? null;
    if (!phase || phase === previousPhase) return;
    if (phase === 'night') { startNightAmbience(); onNightMute(true); if (soundOn) speakHauntedAnnouncement('سكان المخيم، هبط الليل. كل واحد يبقى فبلاصتو، والقرارات كتدار بسرية.'); }
    else if (phase === 'morning') { stopNightAmbience(); startMorningAmbience(); onNightMute(true); const latest = [...(state?.events ?? [])].reverse().find(e => e.event_type === 'night_resolved'); const killedId = typeof latest?.payload.killed_user_id === 'string' ? latest.payload.killed_user_id : null; if (killedId) { playHauntedSound('death'); const victim = state?.players.find(player => player.user_id === killedId)?.username || 'واحد من السكان'; if (soundOn) speakHauntedAnnouncement('طلع الصباح يا سكان الخيمة. لقينا '+victim+' خرج من المخيم هاد الليلة.'); } else { playHauntedSound('save'); if (soundOn) speakHauntedAnnouncement('طلع الصباح يا سكان الخيمة. الليلة دازت بسلام، ما مات حتى واحد.'); } }
    else { stopNightAmbience(); stopMorningAmbience(); onNightMute(false); if (phase === 'day' && soundOn) speakHauntedAnnouncement('طلع الصباح. عندكم أربع دقائق للنقاش. التصويت مازال ما تحلش.'); }
    if (phase === 'ended') playHauntedSound(state?.winner === 'villagers' ? 'win' : 'lose');
    setPreviousPhase(phase);
  }, [state?.status, state?.winner, previousPhase, onNightMute, soundOn]);
  useEffect(() => { if (state?.status !== 'day') { setPreviousVotingOpen(false); return; } if (state.voting_open && !previousVotingOpen && soundOn) speakHauntedAnnouncement('تحل التصويت دابا. اختار المشتبه فيه وصوّت قبل ما يسالي الوقت.'); setPreviousVotingOpen(Boolean(state.voting_open)); }, [state?.status, state?.voting_open, previousVotingOpen, soundOn]);
  useEffect(() => { setPreviousEventCount(0); }, [state?.id]);
  useEffect(() => {
    const count = state?.events.length ?? 0;
    if (count <= previousEventCount) return;
    const fresh = state?.events.slice(previousEventCount) ?? [];
    fresh.forEach(event => {
      if (event.event_type === 'player_ejected') { playHauntedSound('eject'); const id=String(event.payload.ejected_user_id||''); const name=state?.players.find(player=>player.user_id===id)?.username||'واحد من السكان'; if(soundOn)speakHauntedAnnouncement('تحسم التصويت، وخرج '+name+' من المخيم.'); }
      if (event.event_type === 'game_ended') { onRewardsUpdated(); if(soundOn)speakHauntedAnnouncement(state?.winner==='villagers'?'المواطنين ربحو! المسكون تكشف، والمخيم نجا.':'المسكون ربح! قدر يبقى مخفي حتى سيطر على المخيم.'); }
    });
    setPreviousEventCount(count);
  }, [state?.events, previousEventCount, onRewardsUpdated, soundOn, state?.players, state?.winner]);
  useEffect(() => () => { stopNightAmbience(); stopMorningAmbience(); onNightMute(false); }, [onNightMute]);

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
      <div className="haunted-stars" aria-hidden="true"/><div className="haunted-header"><span className="haunted-kicker">ليلة فالخيمة · الفقيه والمسكون</span><h1>ليلة فالخيمة</h1><p>ليلة طويلة، أسرار مخفية، وشكون غادي يخرج من الخيمة؟</p></div>
      <div className="haunted-lobby-grid"><div className="haunted-lobby-card"><h2><Users size={18}/> المخيم ديالكم</h2><p className="haunted-bot-note">حتى إلا كنت بوحدك، غادي يزيد {lobbyBotCount} بوتات كيلعبو وكيصوتو معاك.</p><div className="haunted-roster">{roster.map((player,index)=><div className="haunted-player" key={player.user_id}><span className="haunted-player-index">{String(index+1).padStart(2,'0')}</span><span className="haunted-avatar">{player.profile?.avatar_url?<img src={player.profile.avatar_url} alt=""/>:(player.profile?.username||'؟').slice(0,1)}</span><span className="haunted-player-name">{player.profile?.username||'لاعب'}</span>{player.user_id===userId&&<small>أنت</small>}</div>)}</div><div className="haunted-mode-toggle"><label><input type="checkbox" checked={quickMode} onChange={e=>setQuickMode(e.target.checked)}/> الطور السريع بلا فقيه</label><small>{quickMode?'4 مشاركين إجمالاً، والباقي بوتات.':'5 مشاركين إجمالاً، والباقي بوتات. تقدر تلعب حتى بوحدك.'}</small></div>{!isHost&&<p className="haunted-waiting">كنستناو مول الغرفة يبدا اللعبة…</p>}{isHost&&<button className="haunted-primary" disabled={busy||roster.length<1||roster.length>(quickMode?4:10)} onClick={()=>void startGame()}>{busy?'كنوجدو المخيم...':'🌙 بدا الليلة الأولى'}</button>}</div>
      <aside className="haunted-rules-card"><span className="haunted-kicker">كيفاش كتتلعب؟</span><h2>القواعد بسرعة</h2><ol><li>فالليل، المسكون كيختار ضحية والفقيه كيحمي لاعب بلا ما يعرف شكون المسكون.</li><li>فالصباح، كنعلنو غير واش مات شي حد ولا نجا المخيم.</li><li>فالنهار، ناقشو وصوّتو على اللي شاكين فيه.</li><li>إلا تطرد المسكون، المواطنين كيربحو. إلا بقاو مواطن أو أقل، المسكون كيربح.</li></ol><div className="haunted-role-legend"><span>👻 المسكون</span><span>🛡️ الفقيه</span><span>🏕️ المواطنون</span></div></aside></div>
      {error&&<p className="haunted-error" role="alert">{error}</p>}
      <div className="haunted-footer-actions"><button className="haunted-ghost-button" onClick={onBack}>رجوع للّوبي</button><button className="haunted-ghost-button" onClick={onExit}>خروج من الغرفة</button></div>
    </section>;
  }

  return <section className={'haunted-shell haunted-phase-' + state.status} aria-label="لعبة الفقيه والمسكون">
    <div className="haunted-stars" aria-hidden="true"/><div className="haunted-mist" aria-hidden="true"/>
    <header className="haunted-topbar"><div><span className="haunted-kicker">ليلة فالخيمة · الجولة {state.round}</span><h1>ليلة فالخيمة</h1></div><div className="haunted-top-actions"><span className="haunted-round-pill">الجولة {state.round}</span><button className="haunted-icon-button" onClick={()=>{const next=!soundOn;setSoundOn(next);persistSoundEnabled(next);if(!next){stopNightAmbience();stopMorningAmbience();}else if(state.status==='night')startNightAmbience();else if(state.status==='morning')startMorningAmbience();setHauntedAudioMuted(!next);}} aria-label={soundOn?'كتم المؤثرات':'تشغيل المؤثرات'}>{soundOn?<Volume2/>:<VolumeX/>}</button><button className="haunted-ghost-button" onClick={onBack}>اللوبي</button></div></header>
    <div className="haunted-camp-scene" aria-label="مخيم اللاعبين حول النار">
      <div className="haunted-scene-moon" aria-hidden="true"/>
      <div className="haunted-scene-tent" aria-hidden="true"><span/></div>
      <div className="haunted-campfire" aria-hidden="true"><i/><b/><span/></div>
      <div className="haunted-camp-ring">{state.players.map((player,index)=>{const angle=(index/Math.max(state.players.length,1))*Math.PI*2-Math.PI/2;const left=50+37*Math.cos(angle);const top=50+38*Math.sin(angle);return <div className={'haunted-camp-seat '+(!player.is_alive?'is-out':'')} key={player.user_id} style={{left:left+'%',top:top+'%'}}><span>{player.avatar_url?<img src={player.avatar_url} alt=""/>:(player.username||'؟').slice(0,1)}</span><b>{player.username}</b>{player.is_bot&&<small>بوت</small>}{!player.is_alive&&<small>خرج</small>}</div>;})}</div>
      <span className="haunted-scene-caption">المخيم ديالكم · {alivePlayers.length} باقيين حدا العافية</span>
    </div>
    <div className="haunted-phase-banner">
      {state.status==='night'?<><Moon/><span>الليل هبط على المخيم</span></>:state.status==='morning'?<><Sun/><span>طلع الصباح… شنو وقع فالليل؟</span></>:state.status==='day'?<><Sun/><span>وقت النقاش والتصويت</span></>:<><Trophy/><span>سالَت الحكاية</span></>}
      {state.status!=='ended'&&<strong><Clock3 size={15}/>{secondsLeft}ث</strong>}
    </div>
    {!revealed&&role&&<button className="haunted-role-cover" onClick={()=>{setRevealed(true);playHauntedSound('role');}}><span>🔒</span><b>كشف الدور السري ديالك</b><small>ما تورّيه حتى لواحد</small></button>}
    {revealed&&role&&<motion.article className="haunted-role-card" initial={reduceMotion?false:{rotateY:180,opacity:0}} animate={reduceMotion?{opacity:1}:{rotateY:0,opacity:1}} transition={{duration:reduceMotion?0.01:0.8,ease:'easeOut'}} style={{transformStyle:'preserve-3d',backfaceVisibility:'hidden'}}><div className="haunted-role-card-inner"><span>{role.icon}</span><small>الدور السري ديالك</small><h2>{role.title}</h2><p>{role.description}</p></div></motion.article>}

    {state.status==='night'&&<motion.div className="haunted-night-panel" initial={reduceMotion?false:{opacity:0,y:14}} animate={{opacity:1,y:0}} transition={{duration:reduceMotion?0.01:0.5}}><div className="haunted-moon">🌙</div><h2>{myRole==='haunter'?'اختار الضحية ديالك':myRole==='faqih'?'شكون غادي تعتق الليلة؟':'نعس… الليل ماشي وقت الكلام'}</h2><p>{myRole==='haunter'?'اختار لاعب حي واحد. القرار سري وما غادي يبان حتى واحد.':myRole==='faqih'?'اختار لاعب تحميه. ما غاديش تعرف واش الحماية نجحات حتى يطلع الصباح.':'تسنى الصباح. الميكروفونات مكتومة فالليل.'}</p>
      {!isAlive&&<p className="haunted-waiting">خرجتي من اللعبة، تقدر تبقى تتفرج ولكن ما تقدرش تختار أو تصوّت.</p>}
      {isAlive&&['haunter','faqih'].includes(myRole||'')&&<div className="haunted-target-grid">{alivePlayers.filter(p=>myRole==='haunter'?p.user_id!==userId:true).map(player=><button type="button" key={player.user_id} className={'haunted-target '+(target===player.user_id?'selected':'')} onClick={()=>setTarget(player.user_id)}><span>{player.avatar_url?<img src={player.avatar_url} alt=""/>:(player.username||'؟').slice(0,1)}</span><b>{player.username}</b></button>)}</div>}
      {isAlive&&['haunter','faqih'].includes(myRole||'')&&<button className="haunted-primary" disabled={busy||!target} onClick={()=>void submitNightChoice()}>{myRole==='haunter'?'🗡️ تأكيد اختيار الضحية':'🛡️ تأكيد الحماية'}</button>}
      {myRole==='villager'&&<div className="haunted-waiting">القرارات الليلية كتتدار بسرية تامة.</div>}
      {isHost&&<button className="haunted-secondary" disabled={busy||(!nightReady&&secondsLeft>0)} onClick={()=>void resolveNight()}>{busy?'كنحسبو...':'حسم الليل وكشف الصباح'}</button>}
    </motion.div>}

    {state.status==='morning'&&<motion.div className={'haunted-morning-panel '+(latestNight?.payload.killed_user_id?'has-death':'saved')} animate={reduceMotion?{}:latestNight?.payload.killed_user_id?{x:[0,-8,8,-8,8,0]}:{boxShadow:['0 0 0px #10b981','0 0 28px #10b981','0 0 0px #10b981']}} transition={{duration:reduceMotion?0.01:0.6,repeat:latestNight?.payload.killed_user_id?0:Infinity,repeatDelay:0.7}}><div className="haunted-sunrise"/><span className="haunted-morning-emoji">{latestNight?.payload.killed_user_id?'🪦':'✨'}</span><h2>{latestNight?.payload.killed_user_id?'لقينا لاعب ميت فالصباح':'نجا المخيم هاد الليلة!'}</h2><p>{latestNight?.payload.killed_user_id?('اللاعب '+(state.players.find(p=>p.user_id===latestNight.payload.killed_user_id)?.username||'المجهول')+' خرج من اللعبة. الدور ديالو باقي سري.'):'ما مات حتى واحد. ما كاين حتى كشف شكون تحمى ولا شكون حاول يقتل.'}</p>{isHost&&<button className="haunted-primary" disabled={busy||secondsLeft>0} onClick={()=>void advanceMorning()}>دخل لمرحلة النهار ☀️</button>}</motion.div>}

    {state.status==='day'&&<div className="haunted-day-grid"><section className="haunted-vote-panel">{!isAlive&&<div className="haunted-waiting">خرجتي من اللعبة. تقدر تتابع النقاش والنتائج بلا تصويت.</div>}{latestVoteEvent&&<div className="haunted-outcome-banner">{String(latestVoteEvent.payload.message||'نتيجة التصويت تسجلات.')}{ejectedUserId ? ' '+(state.players.find(p=>p.user_id===ejectedUserId)?.username||'لاعب')+' خرج من المخيم.' : null}</div>}<h2>{state.voting_open?'🗳️ التصويت مفتوح دابا':'🔥 جلسة النقاش فالمخيم'}</h2><p>{state.voting_open?'اختار لاعب حي واحد. الأصوات كتبقى سرية حتى يتحسم التصويت.':'عندكم 4 دقائق باش تناقشو وتجمعو القرائن. البوتات غادي تهضر معاكم، وما غادي يصوّت حتى يتحل التصويت.'}</p>{!state.voting_open&&<div className="haunted-discussion-timer"><Clock3/><b>{Math.floor(secondsLeft/60).toString().padStart(2,'0')}:{(secondsLeft%60).toString().padStart(2,'0')}</b><small>باقي على فتح التصويت</small></div>}{state.voting_open&&<><div className="haunted-target-grid">{isAlive&&alivePlayers.filter(p=>p.user_id!==userId).map(player=><button type="button" key={player.user_id} disabled={voted||busy} className={'haunted-target '+(target===player.user_id?'selected':'')} onClick={()=>setTarget(player.user_id)}><span>{player.avatar_url?<img src={player.avatar_url} alt=""/>:(player.username||'؟').slice(0,1)}</span><b>{player.username}</b></button>)}</div><button className="haunted-primary" disabled={busy||voted||!target||!isAlive} onClick={()=>void submitDayVote()}>{voted?'صوتك تسجل':'تأكيد التصويت'}</button><div className="haunted-vote-count"><b>{voteCount}/{aliveCount}</b><span>أصوات تسجلات</span><small>{state.vote_round===2?'إعادة التصويت بعد التعادل':'التصويت الأول'}</small></div>{isHost&&<button className="haunted-secondary" disabled={busy||(voteCount<aliveCount&&secondsLeft>0)} onClick={()=>void resolveVote()}>حسم التصويت</button>}</>}{!state.voting_open&&isHost&&<button className="haunted-primary" disabled={busy} onClick={()=>void openVoting()}>فتح التصويت دابا</button>}</section>
</div>}

    {state.status==='ended'&&<motion.div className={'haunted-end-panel '+(state.winner==='villagers'?'villagers-win':'haunter-win')} initial={reduceMotion?false:{opacity:0,scale:0.96,y:12}} animate={{opacity:1,scale:1,y:0}} transition={{duration:reduceMotion?0.01:0.55}}>{state.winner==='villagers'&&!reduceMotion&&<div className="haunted-confetti-layer" aria-hidden="true">{Array.from({length:18},(_,i)=><motion.i key={i} style={{left:(i*37)%100+'%'}} animate={{y:['-10vh','90vh'],rotate:[0,360],opacity:[1,1,0]}} transition={{duration:2.8,delay:(i%6)*0.12,ease:'linear'}} />)}</div>}<div className="haunted-win-icon">{state.winner==='villagers'?'🏕️':'👻'}</div><span className="haunted-kicker">THE CAMP HAS SPOKEN</span><h2>{state.winner==='villagers'?'المواطنين ربحو!':'المسكون سيطر على المخيم!'}</h2><p>ها الأدوار الحقيقية ديال جميع اللاعبين:</p><div className="haunted-role-reveal-list">{state.roles.map(item=>{const player=state.players.find(p=>p.user_id===item.user_id);return <div key={item.user_id}><span>{roleCopy[item.role].icon}</span><b>{player?.username||'لاعب'}</b><small>{roleCopy[item.role].name}</small></div>;})}</div><button className="haunted-primary" disabled={busy} onClick={()=>void startGame()}><RefreshCw/> لعبة جديدة</button><button className="haunted-secondary" onClick={onBack}>رجوع للّوبي</button></motion.div>}

    <section className="haunted-camp-chat"><h3><MessageCircle size={17}/> دردشة المخيم</h3><div className="haunted-chat-messages">{[...messages.slice(-8).map(m=>({id:m.id,user:m.user_id,text:m.body,created:m.created_at||''})),...(state.events||[]).filter(e=>e.event_type==='bot_chat').map(e=>({id:e.id,user:String(e.payload.bot_user_id||''),text:String(e.payload.message||''),created:e.created_at}))].sort((a,b)=>a.created.localeCompare(b.created)).slice(-12).map(m=><p key={m.id}><b>{m.user===userId?'أنت':state.players.find(p=>p.user_id===m.user)?.username||roster.find(p=>p.user_id===m.user)?.profile?.username||'لاعب'}:</b> {m.text}</p>)}</div><form onSubmit={e=>{e.preventDefault();if(chatText.trim()){void onSendChat(chatText.trim());setChatText('');}}}><input value={chatText} onChange={e=>setChatText(e.target.value)} maxLength={500} placeholder="كتب رسالة للمخيم..."/><button type="submit" disabled={!chatText.trim()}>إرسال</button></form><div className="haunted-voice-box"><div><Mic/><span><b>الصوت المباشر</b><small>{voiceStatus}</small></span></div><button onClick={onToggleVoice}>{voiceActive?'قطع الصوت':'دخل للصوت'}</button>{voiceActive&&<button onClick={onToggleMute}>{voiceMuted?<Mic/>:<MicOff/>}{voiceMuted?'حل المايك':'كتم المايك'}</button>}</div></section>
    {error&&<p className="haunted-error" role="alert">{error}</p>}
    <footer className="haunted-bottom-bar"><div><span>{aliveCount} باقيين أحياء</span><small>{state.game_mode==='quick'?'طور سريع · بلا فقيه':'طور عادي'}</small></div><button className="haunted-ghost-button" onClick={onExit}>خروج من الغرفة</button></footer>
  </section>;
}
