import { useEffect, useMemo, useRef, useState } from 'react';
import { motion, useReducedMotion } from 'framer-motion';
import { Shield, Skull, Moon, Sun, Volume2, VolumeX, Clock3, Users, MessageCircle, Mic, MicOff, Trophy, Sparkles, RefreshCw, Flame, CheckCircle2, Check, X, LogOut, Plus, Settings } from 'lucide-react';
import { useHauntedGame } from '../../hooks/useHauntedGame';
import { playHauntedSound, startNightAmbience, stopNightAmbience, startMorningAmbience, stopMorningAmbience, preloadHauntedSounds, setHauntedAudioMuted, speakHauntedAnnouncement, playHauntedAnnouncementSegment, preloadHauntedAnnouncements, stopHauntedNarrator, startCampMusic, stopCampMusic, startDiscussionAmbience, stopDiscussionAmbience, unlockHauntedNarrator } from '../../lib/hauntedAudio';
import { getSoundEnabled, setSoundEnabled as persistSoundEnabled } from '../../lib/audio';
import type { HauntedRole } from '../../types/haunted';
import { getHauntedBotCount } from './hauntedNpcRoster';
import { canUseHauntedChat } from './hauntedRules';
import { getHauntedSeatPosition, getHauntedStableSeatOrder } from './hauntedSeatLayout';

type RosterMember = { user_id: string; profile?: { username?: string; avatar_url?: string | null; gender?: 'male' | 'female' | null } };
type ChatMessage = { id: string; user_id: string; body: string; created_at?: string };
type Props = {
  gameId: string; roomId: string; userId: string; isHost: boolean; maxPlayers: number; roster: RosterMember[];
  messages: ChatMessage[]; voiceActive: boolean;
  voiceParticipantIds: string[]; voiceSpeakingIds: string[];
  onBack: () => void; onExit: () => void; onSendChat: (text: string) => Promise<void>;
  onToggleVoice: () => void; onNightMute: (muted: boolean) => void;
  onRewardsUpdated: () => void;
};

const roleCopy: Record<HauntedRole, { name: string; title: string; description: string }> = {
  haunter: { name: 'المسكون', title: 'نتا المسكون', description: 'كل ليلة اختار لاعب حي باش يخرج من المخيم. خليك متخفي، وخلّي الشك يدور على شي حد آخر.' },
  faqih: { name: 'الفقيه', title: 'نتا الفقيه', description: 'من بعد اختيار المسكون، اختار لاعب حي تحميه. إلا كان هو الضحية، كتنجّيه. النتيجة كتبان مع الصباح.' },
  villager: { name: 'مواطن', title: 'نتا من سكان المخيم', description: 'ما عندكش اختيار فالليل. فالنهار ناقش القرائن مع صحابك وصوّت باش تكشف المسكون.' }
};

function RoleMark({ role, size = 22 }: { role: HauntedRole; size?: number }) {
  if (role === 'haunter') return <Skull size={size} />;
  if (role === 'faqih') return <Shield size={size} />;
  return <Users size={size} />;
}

function AnimeCampCharacter({ gender, seed }: { gender: 'male' | 'female'; seed: string }) {
  const female = gender === 'female';
  const variant = Math.abs(Array.from(seed || 'camp').reduce((sum, char) => sum + char.charCodeAt(0), 0)) % 4;
  // The atlas is a 4-column x 2-row sheet: male row first, female row second.
  const column = variant % 4;
  const left = '-' + (column * 100) + '%';
  const top = female ? '-100%' : '0%';
  return <div className={'haunted-anime-art is-'+(female?'female':'male')} role="img" aria-label={female?'شخصية أنمي':'شخصية أنمي'} style={{position:'relative',overflow:'hidden'}}>
    <img loading="lazy" decoding="async" src="https://gtsdrmfvtialuxhfxtvz.supabase.co/storage/v1/object/public/avatars/game-assets/haunted-anime-sprites-v1.png" alt="" style={{position:'absolute',width:'400%',height:'200%',maxWidth:'none',left,top,objectFit:'fill'}} />
  </div>;
}

export default function HauntedCampGame(props: Props) {
  const { gameId, roomId, userId, isHost, maxPlayers, roster, messages, onBack, onExit, onSendChat, voiceActive, voiceParticipantIds, voiceSpeakingIds, onToggleVoice, onNightMute, onRewardsUpdated } = props;
  const reduceMotion = useReducedMotion();
  const [quickMode, setQuickMode] = useState(false);
  const [revealed, setRevealed] = useState(false);
  const [confirmNightChoice, setConfirmNightChoice] = useState(false);
  const roleHideTimerRef = useRef<number | null>(null);
  const roleRevealGameRef = useRef<string | null>(null);
  const [target, setTarget] = useState('');
  const [chatText, setChatText] = useState('');
  const [now, setNow] = useState(Date.now());
  const [soundOn, setSoundOn] = useState(() => getSoundEnabled());
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [motionOn, setMotionOn] = useState(true);
  const [voicePreviewing, setVoicePreviewing] = useState(false);
  const [previousPhase, setPreviousPhase] = useState<string | null>(null);
  const [narratorVisible, setNarratorVisible] = useState(false);
  const [narratorText, setNarratorText] = useState('');
  const [nightIntroReady, setNightIntroReady] = useState(false);
  const narratorRunRef = useRef<string | null>(null);
  const previousVotingRef = useRef<boolean | null>(null);
  const previousHaunterChoiceRef = useRef<string | null>(null);
  const chatMessagesRef = useRef<HTMLDivElement | null>(null);
  const previousEventCountRef = useRef(0);
  const previousEventGameRef = useRef<string | null>(null);
  const { state, busy, error, start, submitKill, submitProtection, submitVote } =
    useHauntedGame(gameId || null, roomId, userId, isHost);

  const myRole = state?.role;
  const role = myRole ? roleCopy[myRole] : null;
  const alivePlayers = useMemo(() => state?.players.filter(p => p.is_alive) ?? [], [state?.players]);
  const targetPlayerCount = Math.min(quickMode ? 4 : 10, maxPlayers);
  const lobbyBotCount = getHauntedBotCount(roster.length, quickMode, targetPlayerCount);
  const secondsLeft = state?.phase_deadline_at ? Math.max(0, Math.ceil((new Date(state.phase_deadline_at).getTime() - now) / 1000)) : 0;
  const latestNight = [...(state?.events ?? [])].reverse().find(e => e.event_type === 'night_resolved');
  const latestVoteEvent = [...(state?.events ?? [])].reverse().find(e => ['player_ejected','vote_tie_resolved','vote_tied'].includes(e.event_type));
  const ejectedUserId = typeof latestVoteEvent?.payload.ejected_user_id === 'string' ? latestVoteEvent.payload.ejected_user_id : null;
  const isAlive = alivePlayers.some(player => player.user_id === userId);
  const aliveCount = alivePlayers.length;
  const voted = Boolean(state?.my_vote);
  const haunterChosen = Boolean(state?.night_haunter_chosen);
  const canUseRoomChat = canUseHauntedChat(state?.status, isAlive);

  useEffect(() => { preloadHauntedSounds(); setHauntedAudioMuted(!soundOn); if(soundOn)startCampMusic(); return()=>{stopCampMusic();if(roleHideTimerRef.current!==null)window.clearTimeout(roleHideTimerRef.current);}; }, []);
  useEffect(() => {
    if (!state?.id || !myRole || roleRevealGameRef.current === state.id) return;
    roleRevealGameRef.current = state.id;
    setRevealed(true);
    playHauntedSound('role');
    if (roleHideTimerRef.current !== null) window.clearTimeout(roleHideTimerRef.current);
    roleHideTimerRef.current = window.setTimeout(() => setRevealed(false), 8500);
  }, [state?.id, myRole]);
  useEffect(() => { setTarget(''); setConfirmNightChoice(false); setNightIntroReady(false); previousHaunterChoiceRef.current = null; }, [state?.status, state?.round]);
  useEffect(() => { if (state && state.status !== 'ended' && !isAlive && voiceActive) onToggleVoice(); }, [state?.id, state?.status, isAlive, voiceActive, onToggleVoice]);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);
  useEffect(() => {
    const panel = chatMessagesRef.current;
    if (panel) panel.scrollTo({ top: panel.scrollHeight, behavior: reduceMotion ? 'auto' : 'smooth' });
  }, [messages.length, state?.events.length, state?.round, reduceMotion]);
  const presentNarration = async (key: string, text: string, segment?: 'night' | 'night_quick' | 'faqih_awake' | 'morning_safe' | 'morning_death' | 'discussion' | 'voting' | 'tie' | 'ejected' | 'win_villagers' | 'win_haunter', afterSegmentText?: string) => {
    narratorRunRef.current = key;
    setNarratorText(text);
    setNarratorVisible(true);
    if (soundOn) {
      if (segment) await playHauntedAnnouncementSegment(segment, text);
      else await speakHauntedAnnouncement(text);
      if (afterSegmentText) await speakHauntedAnnouncement(afterSegmentText);
    } else {
      await new Promise(resolve => window.setTimeout(resolve, 1600));
    }
    if (narratorRunRef.current === key) setNarratorVisible(false);
  };

  useEffect(() => {
    const phase = state?.status ?? null;
    if (!phase || phase === previousPhase) return;
    if (phase === 'night') {
      preloadHauntedAnnouncements(); stopDiscussionAmbience(); startNightAmbience(); onNightMute(true);
      setNightIntroReady(false);
      void presentNarration(state!.id+':'+state!.round+':night','هبط الليل على المخيم. آ المسكون، دابا جا دورك. اختار ضحية وحدة فالسر، عندك الوقت اللي باين فالعداد.',state?.game_mode==='quick'?'night_quick':'night').finally(() => setNightIntroReady(true));
    } else if (phase === 'morning') {
      stopNightAmbience(); stopDiscussionAmbience(); startMorningAmbience(); onNightMute(false);
      const latest = [...(state?.events ?? [])].reverse().find(e => e.event_type === 'night_resolved');
      const killedId = typeof latest?.payload.killed_user_id === 'string' ? latest.payload.killed_user_id : null;
      if (killedId) { playHauntedSound('death'); const victim = state?.players.find(player => player.user_id === killedId)?.username || 'واحد من السكان'; void presentNarration(state!.id+':'+state!.round+':morning','صباح الخير يا سكان المخيم. للأسف، الليلة فقدنا واحد من صحابنا.','morning_death',victim+' خرج من المخيم. الدور ديالو غادي يبقى سري.'); }
      else { playHauntedSound('save'); void presentNarration(state!.id+':'+state!.round+':morning','صباح الخير يا سكان المخيم. الليلة دازت بسلام، وما مات حتى واحد.','morning_safe'); }
    } else if (phase === 'day') {
      stopNightAmbience(); stopMorningAmbience(); startDiscussionAmbience(); onNightMute(false);
      void presentNarration(state!.id+':'+state!.round+':day','طلع النهار. عندكم جوج دقايق تناقشو وتجمعو الشكوك. كل واحد يقول شنو لاحظ، ومن بعد غادي يتحل التصويت.','discussion');
    } else { stopNightAmbience(); stopMorningAmbience(); stopDiscussionAmbience(); onNightMute(false); setNarratorVisible(false); }
    if (phase === 'ended') {
      playHauntedSound(state?.winner === 'villagers' ? 'win' : 'lose');
      void (async () => {
        const ejected = [...(state?.events ?? [])].reverse().find(event => event.event_type === 'player_ejected' && event.round === state?.round);
        const lastNight = [...(state?.events ?? [])].reverse().find(event => event.event_type === 'night_resolved' && event.round === state?.round);
        const nightVictim = !ejected && typeof lastNight?.payload.killed_user_id === 'string'
          ? state?.players.find(player => player.user_id === lastNight.payload.killed_user_id)?.username
          : null;
        if (ejected) {
          const ejectedName = state?.players.find(player => player.user_id === String(ejected.payload.ejected_user_id || ''))?.username || 'واحد من السكان';
          await presentNarration(state!.id+':'+state!.round+':ejected', 'تحسم التصويت. واحد من سكان المخيم خرج من اللعبة.', 'ejected', ejectedName);
        } else if (nightVictim) {
          await presentNarration(state!.id+':'+state!.round+':last-dawn', 'صباح الخير يا سكان الخيمة. للأسف، واحد منكم ما بقاش بيناتنا.', 'morning_death', nightVictim+' خرج من المخيم. الدور ديالو غادي يبقى سري.');
        }
        await presentNarration(
          state!.id+':'+state!.round+':ended',
          state?.winner==='villagers'?'مبروك على سكان المخيم! قدرتو تكشفو المسكون وربحتو هاد الجولة.':'المسكون ربح هاد الجولة. قدر يبقى مخبي، وخلا الظلام يسيطر على المخيم.',
          state?.winner==='villagers'?'win_villagers':'win_haunter'
        );
      })();
    }
    setPreviousPhase(phase);
  }, [state?.status, state?.winner, previousPhase, onNightMute, soundOn]);
  useEffect(() => {
    if (!state || state.status !== 'night' || !haunterChosen || !nightIntroReady || state.my_night_target) return;
    const key = state.id + ':' + state.round;
    if (previousHaunterChoiceRef.current === key) return;
    previousHaunterChoiceRef.current = key;
    void presentNarration(key+(myRole==='faqih'?':faqih':':faqih-public'), myRole==='faqih'?'آ الفقيه، دابا جا دورك! المسكون اختار الضحية، وعندك 20 ثانية باش تختار لاعب حي تحميه. ضغط على الشخصية ديالو، والاختيار ديالك سري.':'المسكون اختار الضحية ديالو. دابا جا دور الفقيه، عندو 20 ثانية باش يحمي واحد من سكان المخيم.', 'faqih_awake');
  }, [state?.id, state?.round, state?.status, myRole, haunterChosen, nightIntroReady, soundOn, state?.my_night_target]);
  useEffect(() => {
    if (!state || state.status !== 'day') return;
    const previous = previousVotingRef.current; previousVotingRef.current = state.voting_open;
    if (previous === false && state.voting_open) void presentNarration(state.id+':'+state.round+':voting','دابا بدا التصويت. اختار اللاعب اللي كتشك فيه. صوتك سري، وعندك غير اختيار واحد.','voting');
  }, [state?.id, state?.round, state?.status, state?.voting_open, soundOn]);
  useEffect(() => { const node=chatMessagesRef.current; if(node)node.scrollTop=node.scrollHeight; }, [messages.length,state?.events.length]);
  useEffect(() => {
    if (!state) return;
    const count = state.events.length;
    if (previousEventGameRef.current !== state.id) {
      previousEventGameRef.current = state.id;
      previousEventCountRef.current = count;
      return;
    }
    if (count <= previousEventCountRef.current) return;
    const fresh = state.events.slice(previousEventCountRef.current);
    fresh.forEach(event => {
      if (event.event_type === 'faqih_turn_opened' && myRole !== 'faqih') { void presentNarration(state.id+':'+event.round+':faqih-public','المسكون اختار الضحية. دابا جا دور الفقيه باش يحمي لاعب واحد. الاختيار ديالو سري، وعندو عشرين ثانية.'); }
      if (event.event_type === 'bot_chat' && !event.payload.system && soundOn && event.payload.message) { const botName=state.players.find(player=>player.user_id===String(event.payload.bot_user_id))?.username||'واحد من سكان المخيم'; void speakHauntedAnnouncement(botName+' كيقول: '+String(event.payload.message)); }
      if (event.event_type === 'vote_tied' && soundOn) void playHauntedAnnouncementSegment('tie','كاين تعادل فالأصوات. غادي نعاودو التصويت بين المرشحين. اختارو بعناية.');
      if (event.event_type === 'vote_tie_resolved' && soundOn) speakHauntedAnnouncement('بقى التعادل، وما خرج حتى واحد من المخيم.');
      if (event.event_type === 'player_ejected' && state.status !== 'ended') { playHauntedSound('eject'); const id=String(event.payload.ejected_user_id||''); const name=state.players.find(player=>player.user_id===id)?.username||'واحد من السكان'; if(soundOn)void playHauntedAnnouncementSegment('ejected','تحسم التصويت. واحد من سكان المخيم خرج من اللعبة.',name); }
      if (event.event_type === 'game_ended') { onRewardsUpdated();  }
    });
    previousEventCountRef.current = count;
  }, [state?.id, state?.events.length, onRewardsUpdated, soundOn, state?.players, state?.winner, myRole]);
  useEffect(() => () => { stopHauntedNarrator(); stopNightAmbience(); stopMorningAmbience(); stopDiscussionAmbience(); onNightMute(false); }, [onNightMute]);

  async function startGame() {
    unlockHauntedNarrator();
    const ok = await start(roomId, quickMode);
    if (ok) { setRevealed(false); }
  }
  async function submitNightChoice() {
    if (!target || !state) return;
    const ok = myRole === 'haunter' ? await submitKill(target) : await submitProtection(target);
    if (ok) { setTarget(''); setConfirmNightChoice(false); playHauntedSound('vote'); }
  }
  if (!state && gameId) {
    return <section className="haunted-shell haunted-loading"><div className="haunted-stars" aria-hidden="true"/><div className="haunted-loading-fire"><span/><i/><b/></div><h1>كنوجدو المخيم…</h1><p>الراوي كيوزع الأدوار وكيشعل العافية. بقا معانا لحظة.</p></section>;
  }

  if (!state) {
    return <section className="haunted-shell haunted-lobby">
      <div className="haunted-stars" aria-hidden="true"/><div className="haunted-header"><span className="haunted-kicker">ليلة فالخيمة · الفقيه والمسكون</span><h1>ليلة فالخيمة</h1><p>ليلة طويلة، أسرار مخفية، وشكون غادي يخرج من الخيمة؟</p><button type="button" className="haunted-lobby-sound" onClick={()=>{unlockHauntedNarrator();const next=!soundOn;setSoundOn(next);persistSoundEnabled(next);setHauntedAudioMuted(!next);if(next)startCampMusic();else stopCampMusic();}}>{soundOn?<Volume2 size={16}/>:<VolumeX size={16}/>} {soundOn?'موسيقى المخيم شغالة':'شغّل موسيقى المخيم'}</button><button type="button" className="haunted-lobby-voice-test" disabled={voicePreviewing} onClick={()=>{unlockHauntedNarrator();if(!soundOn){setSoundOn(true);persistSoundEnabled(true);setHauntedAudioMuted(false);startCampMusic();}setVoicePreviewing(true);void speakHauntedAnnouncement('مرحبا بكم فليلة فالخيمة. خليو عينيكم مفتوحين، راه شي حد فيكم ماشي بريء.').finally(()=>setVoicePreviewing(false));}}><Mic size={15}/>{voicePreviewing?'الراوي كيهضر...':'جرّب صوت الراوي'}</button></div>
      <div className="haunted-lobby-grid"><div className="haunted-lobby-card"><h2><Users size={18}/> المخيم ديالكم</h2><p className="haunted-bot-note">حتى إلا كنت بوحدك، غادي ينضمو للمخيم {lobbyBotCount} شخصيات إضافية، كيتفاعلو وكيصوتو معاك.</p><div className="haunted-roster">{roster.map((player,index)=><div className="haunted-player" key={player.user_id}><span className="haunted-player-index">{String(index+1).padStart(2,'0')}</span><span className="haunted-avatar">{player.profile?.avatar_url?<img src={player.profile.avatar_url} alt=""/>:(player.profile?.username||'؟').slice(0,1)}</span><span className="haunted-player-name">{player.profile?.username||'لاعب'}</span>{player.user_id===userId&&<small>أنت</small>}</div>)}</div><div className="haunted-mode-toggle"><label><input type="checkbox" checked={quickMode} onChange={e=>setQuickMode(e.target.checked)}/> الطور السريع</label><small>{quickMode?'4 مشاركين إجمالاً، الفقيه حاضر، والباقي شخصيات من المخيم.':targetPlayerCount+' مشاركين إجمالاً، والباقي شخصيات من المخيم. تقدر تلعب حتى بوحدك.'}</small></div>{maxPlayers<4&&<p className="haunted-lobby-limit-note">ليلة فالخيمة كتحتاج غرفة فيها 4 مقاعد على الأقل.</p>}{roster.length>targetPlayerCount&&<p className="haunted-lobby-limit-note">هاد الطور كيسمح بحد أقصى {targetPlayerCount} لاعبين. نقصو عدد اللاعبين قبل البداية.</p>}{!isHost&&<p className="haunted-waiting">كنستناو مول الغرفة يبدا اللعبة…</p>}{isHost&&<button className="haunted-primary" disabled={busy||maxPlayers<4||roster.length<1||roster.length>targetPlayerCount} onClick={()=>void startGame()}>{busy?'كنوجدو المخيم...':<><Moon size={18}/> بدا الليلة الأولى</>}</button>}</div>
      <aside className="haunted-rules-card"><span className="haunted-kicker">كيفاش كتتلعب؟</span><h2>القواعد بسرعة</h2><ol><li>فالليل، المسكون كيختار ضحية والفقيه كيحمي لاعب بلا ما يعرف شكون المسكون.</li><li>فالصباح، كنعلنو غير واش مات شي حد ولا نجا المخيم.</li><li>فالنهار، ناقشو وصوّتو على اللي شاكين فيه.</li><li>إلا تطرد المسكون، المواطنين كيربحو. إلا بقاو مواطن أو أقل، المسكون كيربح.</li></ol><div className="haunted-role-legend"><span><Skull size={16}/> المسكون</span><span><Shield size={16}/> الفقيه</span><span><Users size={16}/> المواطنون</span></div></aside></div>
      {error&&<p className="haunted-error" role="alert">{error}</p>}
      <div className="haunted-footer-actions"><button className="haunted-ghost-button" onClick={onBack}>رجوع للّوبي</button></div>
    </section>;
  }

  return <section className={'haunted-shell haunted-phase-' + state.status + (motionOn ? '' : ' motion-off')} aria-label="ليلة فالخيمة">
    <div className="haunted-stars" aria-hidden="true"/><div className="haunted-mist" aria-hidden="true"/>
    <header className="haunted-topbar"><div><span className="haunted-kicker">ليلة فالخيمة · الجولة {state.round}</span><h1>ليلة فالخيمة</h1></div><div className="haunted-top-actions"><span className="haunted-round-pill">الجولة {state.round}</span>{role&&myRole&&<span className="haunted-round-pill"><RoleMark role={myRole} size={14}/> دورك: {role.name}</span>}<button className="haunted-icon-button" onClick={()=>{unlockHauntedNarrator();const next=!soundOn;setSoundOn(next);persistSoundEnabled(next);if(!next){stopNightAmbience();stopMorningAmbience();stopDiscussionAmbience();stopCampMusic();}else{startCampMusic();if(state.status==='night')startNightAmbience();else if(state.status==='morning')startMorningAmbience();else if(state.status==='day')startDiscussionAmbience();}setHauntedAudioMuted(!next);}} aria-label={soundOn?'كتم المؤثرات':'تشغيل المؤثرات'}>{soundOn?<Volume2/>:<VolumeX/>}</button><button className="haunted-icon-button" onClick={()=>setSettingsOpen(true)} aria-label="الإعدادات"><Settings size={18}/></button><button className="haunted-ghost-button" onClick={onBack}>اللوبي</button><button className="haunted-exit-top" onClick={onExit}><LogOut size={15}/> خروج</button></div></header>
    {settingsOpen&&<div className="haunted-settings-backdrop" role="presentation" onClick={()=>setSettingsOpen(false)}>
      <section className="haunted-settings-panel" role="dialog" aria-modal="true" aria-labelledby="haunted-settings-title" onClick={event=>event.stopPropagation()}>
        <div className="haunted-settings-heading"><h2 id="haunted-settings-title">إعدادات المخيم</h2><button type="button" className="haunted-icon-button" onClick={()=>setSettingsOpen(false)} aria-label="إغلاق"><X size={17}/></button></div>
        <label className="haunted-setting-row"><span><Volume2 size={17}/> الأصوات والمؤثرات</span><input type="checkbox" checked={soundOn} onChange={event=>{const next=event.target.checked;setSoundOn(next);persistSoundEnabled(next);setHauntedAudioMuted(!next);if(next){unlockHauntedNarrator();startCampMusic();}else{stopHauntedNarrator();stopCampMusic();stopNightAmbience();stopMorningAmbience();stopDiscussionAmbience();}}}/></label>
        <label className="haunted-setting-row"><span><Sparkles size={17}/> الحركات السينمائية</span><input type="checkbox" checked={motionOn} onChange={event=>setMotionOn(event.target.checked)}/></label>
        <p>الإعدادات كتطبق مباشرة على هاد الجهاز. اختيار الدور والتصويت كيبقاو سريين.</p>
      </section>
    </div>}
    {narratorVisible&&<motion.aside className="haunted-narrator-toast" role="status" aria-live="assertive" initial={reduceMotion?false:{opacity:0,y:-8}} animate={{opacity:1,y:0}} exit={{opacity:0,y:-5}} transition={{duration:.18}}>
      <span className="haunted-narrator-toast-icon"><Volume2 size={17}/></span><div><b>الراوي</b><p>{narratorText}</p></div><span className="haunted-narrator-toast-wave" aria-hidden="true"><i/><i/><i/><i/><i/></span>
    </motion.aside>}
    <div className="haunted-camp-scene" aria-label="مخيم اللاعبين حول النار">
      <div className="haunted-scene-sun" aria-hidden="true"/><div className="haunted-scene-moon" aria-hidden="true"/>
      <div className="haunted-scene-stars" aria-hidden="true"><i/><i/><i/><i/><i/><i/><i/><i/></div>
      <div className="haunted-scene-tent" aria-hidden="true"><span/><b/><i/></div>
      <div className="haunted-scene-ground" aria-hidden="true"><i/><b/></div>
      <div className="haunted-scene-firelight" aria-hidden="true"/>
      <div className="haunted-scene-smoke" aria-hidden="true"><i/><i/><i/><i/></div>
      <div className="haunted-campfire" aria-hidden="true"><i/><b/><em/><span/><strong/></div>
      <div className="haunted-scene-embers" aria-hidden="true"><i/><i/><i/><i/><i/><i/><i/><i/><i/><i/></div>
      {state.status==='night'&&isAlive&&nightIntroReady&&((myRole==='haunter'&&!state.my_night_target)||(myRole==='faqih'&&haunterChosen&&!state.my_night_target))&&<motion.div className="haunted-turn-center" initial={reduceMotion?false:{opacity:0,scale:.92,y:12}} animate={{opacity:1,scale:1,y:0}} transition={{duration:reduceMotion?0.01:.28}} role="status" aria-live="assertive"><span>{myRole==='faqih'?<Shield size={22}/>:<Skull size={22}/>}</span><b>{myRole==='faqih'?'دابا جا دورك آ الفقيه':'آ المسكون، اختار الضحية ديالك'}</b><small>{myRole==='faqih'?'اختار لاعب حي تحميه قبل ما يسالي الوقت.':'اختار لاعب حي واحد فالسر قبل ما يسالي الوقت.'}</small><em>{secondsLeft} ثانية باقية</em></motion.div>}
      {state.status==='night'&&isAlive&&(myRole==='haunter'||myRole==='faqih')&&<div className={'haunted-night-role-hint '+(myRole==='faqih'?'is-faqih':'is-haunter')} aria-live="polite"><span>{myRole==='haunter'?<Skull size={17}/>:<Shield size={17}/>}</span><b>{myRole==='haunter'?(state.my_night_target?'الضحية تحددات':'ختار شكون بغيتي تقتل'):(haunterChosen?(state.my_night_target?'الحماية تسجلات':'ختار شكون بغيتي تعتق'):'تسنى اختيار المسكون')}</b></div>}
      <div className={'haunted-camp-ring '+(state.players.length<=6?'is-six-or-fewer':'is-many')}>{getHauntedStableSeatOrder(state.players).map((player,index)=>{const {left,top}=getHauntedSeatPosition(index,state.players.length);const myNightTarget=state.my_night_target===player.user_id;
      const myVoteTarget=state.my_vote===player.user_id;
      const canChoose=player.is_alive&&isAlive&&!busy&&((state.status==='night'&&!state.my_night_target&&(myRole==='haunter'||(myRole==='faqih'&&haunterChosen))&&(myRole==='faqih'||player.user_id!==userId))||(state.status==='day'&&state.voting_open&&!voted&&player.user_id!==userId));
      const selected=target===player.user_id;
      const hasVoice=voiceParticipantIds.includes(player.user_id);
      const speaking=voiceSpeakingIds.includes(player.user_id);
      return <button type="button" aria-label={player.username+(player.is_alive?'':'، مقصي')+(myNightTarget?'، اختيارك تسجل':myVoteTarget?'، صوتك تسجل':'')+(speaking?'، كيهضر':'')} aria-pressed={selected||myNightTarget||myVoteTarget} disabled={!canChoose} className={'haunted-camp-seat '+(!player.is_alive?'is-out':'')+(canChoose?' is-selectable':'')+(selected?' is-selected':'')+(myNightTarget?' is-night-chosen':'')+(myVoteTarget?' is-my-vote':'')+(hasVoice?' has-voice':'')+(speaking?' is-speaking':'')} key={player.user_id} style={{left:left+'%',top:top+'%'}} onClick={()=>{if(!canChoose)return;setTarget(player.user_id);if(state.status==='night')setConfirmNightChoice(true);else if(state.status==='day'&&state.voting_open){void submitVote(player.user_id).then(ok=>{if(ok){setTarget('');playHauntedSound('vote');}});}}}>
        <span><AnimeCampCharacter gender={player.gender || roster.find(member=>member.user_id===player.user_id)?.profile?.gender || 'male'} seed={player.avatar_key || player.username}/></span>
        <b>{player.username}</b>
        {player.user_id===userId&&role&&<small className="haunted-self-role"><RoleMark role={myRole!} size={10}/> دورك: {role.name}</small>}
        {myNightTarget&&<small className="haunted-action-confirmed"><CheckCircle2 size={11}/> اختيارك تسجل</small>}
        {myVoteTarget&&<small className="haunted-action-confirmed"><CheckCircle2 size={11}/> صوتك تسجل</small>}
        {hasVoice&&<small className="haunted-seat-mic"><Mic size={11}/>{speaking?'كيهضر':'مايك'}</small>}
        {!player.is_alive&&<small className="haunted-eliminated-mark"><Skull size={13}/> مقصي</small>}
        {selected&&<i className="haunted-selected-flame"><Flame size={18}/></i>}
      </button>;})}</div>
      {state.status==='day'&&state.voting_open&&!voted&&isAlive&&<span className="haunted-scene-hint">ضغط على الشخصية باش تسجل صوتك مرة وحدة</span>}
    </div>
    <div className="haunted-phase-banner">
      {state.status==='night'?<><Moon/><span>الليل هبط على المخيم</span></>:state.status==='morning'?<><Sun/><span>طلع الصباح… شنو وقع فالليل؟</span></>:state.status==='day'?<><Sun/><span>وقت النقاش والتصويت</span></>:<><Trophy/><span>سالَت الحكاية</span></>}
      {state.status!=='ended'&&<strong>{state.status==='night'&&haunterChosen&&myRole==='faqih'?'وقت الفقيه':state.status==='night'&&haunterChosen?'اختيار الفقيه':state.status==='night'&&myRole==='haunter'?'وقت المسكون':state.status==='night'?'الاختيار السري':''}<Clock3 size={15}/>{Math.floor(secondsLeft/60).toString().padStart(2,'0')}:{(secondsLeft%60).toString().padStart(2,'0')}</strong>}
    </div>
    {revealed&&role&&<div className="haunted-role-overlay" role="dialog" aria-modal="true" aria-label="بطاقتك السرية" onClick={()=>setRevealed(false)}>
      <motion.article className={'haunted-role-card haunted-role-'+myRole} initial={reduceMotion?false:{rotateY:70,opacity:0,scale:.86,y:24}} animate={reduceMotion?{opacity:1,scale:1}:{rotateY:0,opacity:1,scale:1,y:0}} transition={{duration:reduceMotion?0.01:0.72,ease:[.2,.8,.2,1]}} onClick={e=>e.stopPropagation()}>
        <div className="haunted-role-card-aura"/><div className="haunted-role-card-inner"><span className="haunted-role-card-kicker">ليلة فالخيمة · الجولة {state.round}</span><RoleMark role={myRole!} size={52}/><small>الدور السري ديالك</small><h2>{role.name}</h2><strong>{role.title}</strong><p>{role.description}</p><span className="haunted-role-card-hint">خلي الدور سري · البطاقة غادي تختفي بوحدها</span><button type="button" className="haunted-role-close" onClick={()=>setRevealed(false)}><X size={17}/> فهمت</button></div>
      </motion.article>
    </div>}
    {confirmNightChoice&&target&&state.status==='night'&&<div className="haunted-confirm-overlay" role="dialog" aria-modal="true" aria-labelledby="haunted-confirm-title">
      <motion.section className="haunted-confirm-card" initial={reduceMotion?false:{opacity:0,scale:.9,y:18}} animate={{opacity:1,scale:1,y:0}} transition={{duration:.22}}>
        <span className="haunted-confirm-emblem">{myRole==='haunter'?<Skull size={30}/>:<Shield size={30}/>}</span><small>{myRole==='haunter'?'قرار المسكون · سري':'قرار الفقيه · سري'}</small>
        <h2 id="haunted-confirm-title">{myRole==='haunter'?'متأكد بغيتي تختار هاد الضحية؟':'متأكد بغيتي تحمي هاد اللاعب؟'}</h2>
        <div className="haunted-confirm-player"><span><AnimeCampCharacter gender={state.players.find(p=>p.user_id===target)?.gender||'male'} seed={state.players.find(p=>p.user_id===target)?.avatar_key||target}/></span><b>{state.players.find(p=>p.user_id===target)?.username||'اللاعب المختار'}</b></div>
        <p>{myRole==='haunter'?'إلا أكدتي، الاختيار غادي يتسجل وما تقدرش تبدلو.':'إلا أكدتي، الحماية غادي تتسجل بسرية حتى يطلع الصباح.'}</p>
        <div className="haunted-confirm-actions"><button type="button" className="haunted-secondary" disabled={busy} onClick={()=>setConfirmNightChoice(false)}><X size={17}/> تراجع</button><button type="button" className="haunted-primary" disabled={busy} onClick={()=>void submitNightChoice()}>{busy?'كنسجلو القرار...':<><Check size={18}/> نعم، متأكد</>}</button></div>
      </motion.section>
    </div>}

    {state.status==='night'&&<motion.div className="haunted-night-panel" initial={reduceMotion?false:{opacity:0,y:14}} animate={{opacity:1,y:0}} transition={{duration:reduceMotion?0.01:0.5}}><div className="haunted-moon"><Moon size={28}/></div><h2>{myRole==='haunter'?(state.my_night_target?'اختيارك تسجل':'اختار الضحية ديالك'):myRole==='faqih'?(state.my_night_target?'الاختيار ديالك تسجل':haunterChosen?'دابا دورك آ الفقيه: شكون غادي تحمي؟':'تسنى اختيار المسكون…'):'نعس… الليل ماشي وقت الكلام'}</h2><p>{myRole==='haunter'?(state.my_night_target?'تسجل اختيار الضحية ديالك. القرار بقى سري.':'ضغط على الشخصية ديال اللاعب اللي بغيتي تقتل. الاختيار ديالك سري.'):myRole==='faqih'?(state.my_night_target?'تسجلات الحماية ديالك بسرية. تسنى الصباح باش تعرف واش نجحات.':haunterChosen?'المسكون اختار الضحية. اختار دابا لاعب حي باش تحميه، والقرار ديالك سري.':'المسكون باقي ما اختارش الضحية. منين يسجل الاختيار غادي يوصلك الدور ديالك.'):'تسنى الصباح. الميكروفونات مكتومة فالليل.'}</p>{state.my_night_target&&<div className="haunted-night-choice-confirmed"><CheckCircle2 size={16}/> اختيارك تسجل. ما تقدرش تبدلو حتى يطلع الصباح.</div>}
      {!isAlive&&<p className="haunted-waiting">خرجتي من اللعبة، تقدر تبقى تتفرج ولكن ما تقدرش تختار أو تصوّت.</p>}
      {isAlive&&myRole==='faqih'&&!haunterChosen&&<p className="haunted-choice-hint">تسنى حتى يختار المسكون، عاد غادي يتحل ليك الاختيار ديال الحماية.</p>}{isAlive&&['haunter','faqih'].includes(myRole||'')&&(myRole!=='faqih'||haunterChosen)&&<p className="haunted-choice-hint"><Flame size={16}/> ضغط مباشرة على شخصية من الحلقة، وغادي يبان ليك تأكيد قبل تسجيل القرار.</p>}
      {myRole==='villager'&&<div className="haunted-waiting">القرارات الليلية كتتدار بسرية تامة.</div>}
    </motion.div>}

    {state.status==='morning'&&<motion.div className={'haunted-morning-panel '+(latestNight?.payload.killed_user_id?'has-death':'saved')} animate={reduceMotion?{}:latestNight?.payload.killed_user_id?{x:[0,-8,8,-8,8,0]}:{boxShadow:['0 0 0px #10b981','0 0 28px #10b981','0 0 0px #10b981']}} transition={{duration:reduceMotion?0.01:0.6,repeat:latestNight?.payload.killed_user_id?0:Infinity,repeatDelay:0.7}}><div className="haunted-sunrise"/><span className="haunted-morning-emoji">{latestNight?.payload.killed_user_id?<Skull size={34}/>:<Sparkles size={34}/>}</span><h2>{latestNight?.payload.killed_user_id?'لقينا لاعب ميت فالصباح':'نجا المخيم هاد الليلة!'}</h2><p>{latestNight?.payload.killed_user_id?('اللاعب '+(state.players.find(p=>p.user_id===latestNight.payload.killed_user_id)?.username||'المجهول')+' خرج من اللعبة. الدور ديالو باقي سري.'):'ما مات حتى واحد. ما كاين حتى كشف شكون تحمى ولا شكون حاول يقتل.'}</p><p className="haunted-auto-transition"><Clock3 size={15}/> الراوي غادي يفتح النقاش تلقائياً من بعد الإعلان.</p></motion.div>}

    {state.status==='day'&&<div className="haunted-day-grid"><section className="haunted-vote-panel">{!isAlive&&<div className="haunted-waiting">خرجتي من اللعبة. تقدر تتابع النقاش والنتائج بلا تصويت.</div>}{latestVoteEvent&&<div className="haunted-outcome-banner">{String(latestVoteEvent.payload.message||'نتيجة التصويت تسجلات.')}{ejectedUserId ? ' '+(state.players.find(p=>p.user_id===ejectedUserId)?.username||'لاعب')+' خرج من المخيم.' : null}</div>}<h2>{state.voting_open?<><CheckCircle2 size={20}/> التصويت مفتوح دابا</>:<><Flame size={20}/> جلسة النقاش فالمخيم</>}</h2><p>{state.voting_open?'اختار لاعب حي واحد. الأصوات كتبقى سرية حتى يتحسم التصويت.':'عندكم جوج دقايق للنقاش وجمع القرائن. هضرو باش تعرفو شكون هو المسكون. التصويت غادي يتحل بوحدو منين يسالي الوقت.'}</p>{!state.voting_open&&<p className="haunted-auto-transition"><Clock3 size={14}/> عندكم جوج دقايق فقط. التصويت كيتحل بوحدو منين يسالي الوقت.</p>}{voted&&<div className="haunted-vote-recorded"><CheckCircle2 size={16}/> صوتك تسجل. ما تقدرش تعاود تصوت فهاد الجولة.</div>}{state.voting_open&&<><div className="haunted-vote-direct-hint">{voted?<><CheckCircle2 size={16}/> صوتك تسجل. التصويت ديالك محسوب.</>:isAlive?'ضغط مباشرة على الشخصية اللي شاك فيها فالمخيم. غادي يتحسب صوتك بوحدو.':'خرجتي من اللعبة، تقدر غير تتابع النتيجة.'}</div><p className="haunted-vote-private-note">الأصوات سرية، والنتيجة كتبان غير ملي يسالي التصويت.</p></>}</section>
</div>}

    {state.status==='ended'&&<motion.div className={'haunted-end-panel '+(state.winner==='villagers'?'villagers-win':'haunter-win')} initial={reduceMotion?false:{opacity:0,scale:0.96,y:12}} animate={{opacity:1,scale:1,y:0}} transition={{duration:reduceMotion?0.01:0.55}}>{state.winner==='villagers'&&!reduceMotion&&<div className="haunted-confetti-layer" aria-hidden="true">{Array.from({length:18},(_,i)=><motion.i key={i} style={{left:(i*37)%100+'%'}} animate={{y:['-10vh','90vh'],rotate:[0,360],opacity:[1,1,0]}} transition={{duration:2.8,delay:(i%6)*0.12,ease:'linear'}} />)}</div>}<div className="haunted-win-icon">{state.winner==='villagers'?<Users size={36}/>:<Skull size={36}/>}</div><span className="haunted-kicker">THE CAMP HAS SPOKEN</span><h2>{state.winner==='villagers'?'المواطنين ربحو!':'المسكون سيطر على المخيم!'}</h2><p className="haunted-end-explanation">{state.winner==='villagers'?'المواطنين كشفو المسكون وطردوه من المخيم.':'المسكون ربح حيث بقاو المواطنين واحد أو أقل.'}</p><p className="haunted-end-roles-title">الأدوار الحقيقية ديال اللاعبين:</p><div className="haunted-role-reveal-list">{state.roles.map(item=>{const player=state.players.find(p=>p.user_id===item.user_id);return <div key={item.user_id}><span><RoleMark role={item.role} size={20}/></span><b>{player?.username||'لاعب'}</b><small>{roleCopy[item.role].name}</small></div>;})}</div><button className="haunted-primary" disabled={busy} onClick={()=>void startGame()}><RefreshCw/> لعبة جديدة</button><button className="haunted-secondary" onClick={onBack}>رجوع للّوبي</button></motion.div>}


    <section className="haunted-camp-chat"><h3><MessageCircle size={17}/> دردشة المخيم <span className="haunted-chat-count">{messages.length} رسائل</span><span className="haunted-chat-live"><i/> مباشر</span></h3>
    {(state.status==='day'||state.status==='morning')&&isAlive&&voiceParticipantIds.length>0&&<div className="haunted-voice-presence"><Mic size={12}/>{voiceParticipantIds.slice(0,4).map(id=>state.players.find(p=>p.user_id===id)?.username||'لاعب').join('، ')} {voiceSpeakingIds.length>0&&<span>· كاين اللي كيهضر</span>}</div>}
<div className="haunted-chat-messages" ref={chatMessagesRef} role="log" aria-live="polite" aria-relevant="additions">{[...messages.slice(-8).map(m=>({id:m.id,user:m.user_id,system:false,bot:Boolean(state.players.find(p=>p.user_id===m.user_id)?.is_bot),text:m.body,created:m.created_at||''})),...(state.events||[]).filter(e=>e.event_type==='bot_chat'&&e.round===state.round).filter(e=>state.voting_open?!/عندكم 4 دقائق|جمعو القرائن|النقاش/i.test(String(e.payload.message||'')):!/تحل التصويت|التصويت مفتوح/i.test(String(e.payload.message||''))).map(e=>({id:e.id,user:String(e.payload.bot_user_id||''),system:Boolean(e.payload.system),bot:Boolean(state.players.find(p=>p.user_id===String(e.payload.bot_user_id||''))?.is_bot),text:String(e.payload.message||''),created:e.created_at}))].sort((a,b)=>a.created.localeCompare(b.created)).slice(-12).map(m=><p key={m.id} className={'haunted-chat-line '+(m.system?'is-system':m.user===userId?'is-mine':m.bot?'is-bot':'is-other')}><span className="haunted-chat-meta"><b>{m.user===userId?'أنت':m.system?'الراوي':state.players.find(p=>p.user_id===m.user)?.username||roster.find(p=>p.user_id===m.user)?.profile?.username||'لاعب'}</b><time>{m.created&&Number.isFinite(Date.parse(m.created))?new Date(m.created).toLocaleTimeString('ar-MA',{hour:'2-digit',minute:'2-digit'}):''}</time></span><span className="haunted-chat-body">{m.text}</span></p>)}{messages.length===0&&!(state.events||[]).some(e=>e.event_type==='bot_chat'&&e.round===state.round)&&<div className="haunted-chat-empty"><MessageCircle size={16}/> بداو النقاش، أول رسالة كتسخّن المخيم.</div>}</div>{canUseRoomChat?<form className="haunted-chat-compose" onSubmit={e=>{e.preventDefault();if(chatText.trim()&&canUseRoomChat){void onSendChat(chatText.trim());setChatText('');}}}><input value={chatText} onChange={e=>setChatText(e.target.value)} maxLength={500} placeholder="كتب رسالة للمخيم..."/><div className="haunted-chat-actions">{(state.status==='day'||state.status==='morning')&&<><button type="button" className={'haunted-inline-mic '+(voiceActive?'is-active':'is-off')+(voiceSpeakingIds.includes(userId)?' is-speaking':'')} onClick={onToggleVoice} aria-label={voiceActive?'قطع المايك':'فتح المايك'} aria-pressed={voiceActive} title={voiceActive?'المايك شاعل — اضغط باش تسدو':'المايك مسدود — اضغط باش تحلو'}>{voiceActive?<><Mic size={17}/>{voiceSpeakingIds.includes(userId)&&<span className="haunted-mic-speaking" aria-hidden="true"><i/><i/><i/></span>}</>:<span className="haunted-mic-off-icon"><Mic size={16}/><Plus size={9}/></span>}</button></>}<button type="submit" disabled={!chatText.trim()}>إرسال</button></div></form>:state.status==='night'&&isAlive?<div className="haunted-spectator-note"><Moon size={14}/> الشات والمايك مسدودين فالليل. تقدر ترجع تهضر ملي يطلع الصباح.</div>:<div className="haunted-spectator-note"><Skull size={14}/> خرجتي من اللعبة. تقدر تشوف الشات واللعب، ولكن ما تقدرش تكتب ولا تدخل للمايك.</div>}</section>
    {error&&<p className="haunted-error" role="alert">{error}</p>}

  </section>;
}
