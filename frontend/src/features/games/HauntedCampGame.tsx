import { useEffect, useMemo, useRef, useState } from 'react';
import { motion, useReducedMotion } from 'framer-motion';
import { Shield, Skull, Moon, Sun, Volume2, VolumeX, Clock3, Users, MessageCircle, Mic, MicOff, Trophy, Sparkles, RefreshCw, Flame, CheckCircle2, Check, X, Headphones, Plus } from 'lucide-react';
import { useHauntedGame } from '../../hooks/useHauntedGame';
import { playHauntedSound, startNightAmbience, stopNightAmbience, startMorningAmbience, stopMorningAmbience, preloadHauntedSounds, setHauntedAudioMuted, speakHauntedAnnouncement, playHauntedNarrator, stopHauntedNarrator, startCampMusic, stopCampMusic, unlockHauntedNarrator } from '../../lib/hauntedAudio';
import { getSoundEnabled, setSoundEnabled as persistSoundEnabled } from '../../lib/audio';
import type { HauntedRole } from '../../types/haunted';
import { getHauntedBotCount } from './hauntedNpcRoster';

type RosterMember = { user_id: string; profile?: { username?: string; avatar_url?: string | null; gender?: 'male' | 'female' | null } };
type ChatMessage = { id: string; user_id: string; body: string; created_at?: string };
type Props = {
  gameId: string; roomId: string; userId: string; isHost: boolean; roster: RosterMember[];
  messages: ChatMessage[]; voiceActive: boolean; voiceMuted: boolean; voiceStatus: string;
  voiceParticipantIds: string[]; voiceSpeakingIds: string[];
  onBack: () => void; onExit: () => void; onSendChat: (text: string) => Promise<void>;
  onToggleVoice: () => void; onToggleMute: () => void; onNightMute: (muted: boolean) => void;
  onRewardsUpdated: () => void;
};

const roleCopy: Record<HauntedRole, { name: string; title: string; description: string }> = {
  haunter: { name: 'المسكون', title: 'نتا المسكون', description: 'كل ليلة اختار لاعب حي باش تخرجو من المخيم. خليك مخفي وحاول ما يتكشفش أمرك.' },
  faqih: { name: 'الفقيه', title: 'نتا الفقيه', description: 'كل ليلة اختار لاعب تحميه. ما عندك حتى معلومة على المسكون، والنتيجة كتبان غير مع الصباح.' },
  villager: { name: 'مواطن', title: 'نتا من سكان المخيم', description: 'ما عندكش اختيار فالليل. نهاراً ناقش مع صحابك وصوّت على اللي شاك فيه.' }
};

function RoleMark({ role, size = 22 }: { role: HauntedRole; size?: number }) {
  if (role === 'haunter') return <Skull size={size} />;
  if (role === 'faqih') return <Shield size={size} />;
  return <Users size={size} />;
}

function AnimeCampCharacter({ gender, seed }: { gender: 'male' | 'female'; seed: string }) {
  const female = gender === 'female';
  const palettes = [
    { robe:'#473d86', shadow:'#242044', trim:'#e2c7ff', hair:'#20192e', eye:'#78d9ff', skin:'#f4c7ae' },
    { robe:'#246d78', shadow:'#173b49', trim:'#a6f0e8', hair:'#38251e', eye:'#74e4d2', skin:'#e9b997' },
    { robe:'#934b39', shadow:'#512b2b', trim:'#ffd6a2', hair:'#261c2b', eye:'#e6a6ff', skin:'#f0c5a8' },
    { robe:'#465d9a', shadow:'#25345f', trim:'#c9dcff', hair:'#432b24', eye:'#9ecbff', skin:'#f0c3a6' },
    { robe:'#8a416d', shadow:'#482342', trim:'#ffc8e5', hair:'#241b2b', eye:'#ffb3d7', skin:'#f4c4ad' },
    { robe:'#526d42', shadow:'#293c2a', trim:'#d4e9a4', hair:'#29232a', eye:'#c5e98e', skin:'#e8b99b' },
    { robe:'#a06b2f', shadow:'#53391f', trim:'#ffe0a1', hair:'#30202a', eye:'#ffd27e', skin:'#f1c5a8' },
    { robe:'#674a9a', shadow:'#34234e', trim:'#e0c4ff', hair:'#1e1a30', eye:'#c8a9ff', skin:'#edbfa5' },
    { robe:'#3c6385', shadow:'#1e354d', trim:'#b6e6ff', hair:'#3b2a24', eye:'#9be4ff', skin:'#f0c2a8' },
    { robe:'#8b4b4b', shadow:'#48262f', trim:'#ffd0b7', hair:'#211c2a', eye:'#ffb49d', skin:'#f1c1a6' },
  ];
  const hash = Array.from(seed || 'camp').reduce((sum,char)=>((sum*31)+char.charCodeAt(0))>>>0,7);
  const variant = hash % palettes.length;
  const c = palettes[variant];
  const uid = 'anime'+hash.toString(36);
  const longHair = female && variant % 3 !== 1;

  const spiky = !female && variant % 3 !== 1;
  return <svg className={'haunted-anime-art '+(female?'is-female':'is-male')} viewBox="0 0 140 180" role="img" aria-label={female?'شخصية أنمي أنثى':'شخصية أنمي ذكر'}>
    <defs>
      <linearGradient id={uid+'robe'} x1="0" y1="0" x2="1" y2="1"><stop stopColor={c.robe}/><stop offset=".58" stopColor={c.shadow}/><stop offset="1" stopColor={c.robe}/></linearGradient>
      <linearGradient id={uid+'hair'} x1="0" y1="0" x2=".8" y2="1"><stop stopColor={c.hair}/><stop offset=".55" stopColor="#171522"/><stop offset="1" stopColor={c.robe}/></linearGradient>
      <linearGradient id={uid+'skin'} x1="0" y1="0" x2="0" y2="1"><stop stopColor="#ffe0c8"/><stop offset="1" stopColor={c.skin}/></linearGradient>
      <linearGradient id={uid+'gold'} x1="0" y1="0" x2="1" y2="1"><stop stopColor="#fff1b5"/><stop offset=".5" stopColor="#d99b45"/><stop offset="1" stopColor="#fff0b4"/></linearGradient>
    </defs>
    <ellipse cx="70" cy="169" rx="47" ry="7" fill="#03040b" opacity=".5"/>
    {/* crossed legs and boots */}
    <path d="M48 117 Q23 128 18 145 Q17 154 31 155 Q53 155 71 140 L91 124 L79 111Z" fill={c.shadow} stroke={c.trim} strokeWidth="2.2"/>
    <path d="M77 117 Q100 122 119 143 Q126 152 115 157 Q95 160 74 144 L55 132Z" fill={c.shadow} stroke={c.trim} strokeWidth="2.2"/>
    <path d="M18 145 Q10 154 20 160 Q38 164 55 152 L63 143 L50 138Z" fill="#171522" stroke={c.trim} strokeWidth="1.7"/>
    <path d="M106 143 Q119 145 127 154 Q126 163 110 163 L91 154Z" fill="#171522" stroke={c.trim} strokeWidth="1.7"/>
    <path d="M29 149 Q42 153 54 145 M96 149 Q108 155 119 154" fill="none" stroke={c.trim} strokeWidth="1.2" opacity=".8"/>
    {/* hair behind shoulders */}
    {female&&longHair&&<path d="M43 50 Q29 56 31 89 L25 127 Q29 140 43 127 L54 78 M91 49 Q109 59 106 93 L116 126 Q112 140 98 127 L87 78Z" fill={'url(#'+uid+'hair)'} stroke="#171321" strokeWidth="2"/>}
    {/* robe silhouette */}
    <path d="M48 78 Q70 67 91 79 Q104 96 111 130 Q90 145 70 139 Q45 146 27 130 Q34 94 48 78Z" fill={'url(#'+uid+'robe)'} stroke={c.trim} strokeWidth="2.2"/>
    <path d="M53 80 L69 111 L88 81 L98 129 Q72 141 41 129Z" fill={c.shadow} opacity=".55"/>
    <path d="M57 80 L70 105 L84 80 L78 132 L64 132Z" fill={c.robe} stroke={c.trim} strokeWidth="1.5"/>
    {/* wide sleeves */}
    <path d="M48 84 Q28 83 22 105 Q17 119 33 128 L48 112 L59 96Z" fill={'url(#'+uid+'robe)'} stroke={c.trim} strokeWidth="2"/>
    <path d="M91 84 Q111 84 119 106 Q123 119 108 129 L91 112 L81 96Z" fill={'url(#'+uid+'robe)'} stroke={c.trim} strokeWidth="2"/>
    <path d="M25 111 L39 119 M115 111 L101 119" stroke={c.trim} strokeWidth="2.4" strokeLinecap="round"/>
    {/* hands */}
    <path d="M35 122 Q42 117 48 122 L52 130 Q46 137 38 132Z" fill={'url(#'+uid+'skin)'} stroke="#a86f65" strokeWidth="1"/>
    <path d="M104 122 Q98 117 92 122 L88 130 Q94 137 102 132Z" fill={'url(#'+uid+'skin)'} stroke="#a86f65" strokeWidth="1"/>
    {/* collar, belt and ornamental embroidery */}
    <path d="M52 79 L70 98 L88 79 L81 74 L70 86 L59 74Z" fill={c.shadow} stroke={c.trim} strokeWidth="1.8"/>
    <path d="M42 119 Q70 128 98 119" fill="none" stroke={c.trim} strokeWidth="2.1"/>
    <path d="M45 128 Q70 136 95 128" fill="none" stroke={c.trim} strokeWidth="1" opacity=".65"/>
    <path d="M70 91 L70 120 M63 105 L70 112 L77 105" fill="none" stroke={c.trim} strokeWidth="1.4"/>
    <circle cx="70" cy="102" r="5.5" fill={'url(#'+uid+'gold)'} stroke="#fff0b2" strokeWidth="1"/>
    <circle cx="70" cy="102" r="2" fill="#fff7d4"/>
    {/* neck and face */}
    <path d="M59 65 L58 80 Q70 89 82 80 L80 64Z" fill={'url(#'+uid+'skin)'}/>
    <path d="M47 40 Q49 23 70 23 Q93 23 94 44 L90 66 Q82 79 70 80 Q56 77 49 65Z" fill={'url(#'+uid+'skin)'} stroke="#9e6c68" strokeWidth="1.2"/>
    <ellipse cx="50" cy="54" rx="3.5" ry="6" fill={c.skin}/><ellipse cx="91" cy="54" rx="3.5" ry="6" fill={c.skin}/>
    {/* eyes with iris, highlights and brows */}
    <path d="M53 51 Q61 44 67 51 Q62 61 55 57Z M74 51 Q81 44 88 51 Q86 59 78 57Z" fill="#fff8f3"/>
    <ellipse cx="61" cy="53" rx="3.3" ry="5" fill={c.eye}/><ellipse cx="81" cy="53" rx="3.3" ry="5" fill={c.eye}/>
    <ellipse cx="61" cy="54" rx="1.4" ry="3.1" fill="#171522"/><ellipse cx="81" cy="54" rx="1.4" ry="3.1" fill="#171522"/>
    <circle cx="62" cy="51" r="1.4" fill="#fff"/><circle cx="82" cy="51" r="1.4" fill="#fff"/>
    <path d="M52 47 Q60 42 67 47 M74 47 Q82 42 89 47" fill="none" stroke={c.hair} strokeWidth="2.2" strokeLinecap="round"/>
    <path d="M69 60 Q71 62 73 60 M66 68 Q70 71 74 68" fill="none" stroke="#a65d66" strokeWidth="1.4" strokeLinecap="round"/>
    <ellipse cx="53" cy="63" rx="4" ry="2" fill="#f08e9c" opacity=".3"/><ellipse cx="87" cy="63" rx="4" ry="2" fill="#f08e9c" opacity=".3"/>
    {/* signature hair silhouettes */}
    {female
      ? <path d={longHair?"M44 50 Q32 25 48 13 Q66 0 85 13 Q103 27 91 53 L84 45 L80 31 Q70 40 62 31 Q55 43 48 42 L47 61Z":"M44 48 Q34 25 49 13 Q68 2 86 15 Q100 29 91 50 L82 42 L76 34 L68 41 L60 31 L52 43Z"} fill={'url(#'+uid+'hair)'} stroke="#171321" strokeWidth="2"/>
      : <path d={spiky?"M43 45 Q34 27 42 18 L33 10 L53 15 Q56 1 69 8 L76 1 L81 17 Q98 9 101 24 L94 31 L94 50 L84 39 L78 32 L70 42 L62 31 L54 44Z":"M43 48 Q36 26 50 14 Q71 0 88 16 Q98 27 91 49 L82 40 L76 31 L67 40 L59 30 L51 43Z"} fill={'url(#'+uid+'hair)'} stroke="#171321" strokeWidth="2"/>}
    {/* fringe shine and strands */}
    <path d="M48 23 Q61 9 78 18 M54 30 Q62 22 68 21 M80 22 Q89 24 91 32" fill="none" stroke="#fff" strokeOpacity=".18" strokeWidth="2.2" strokeLinecap="round"/>
    {female&&<><path d="M41 22 Q27 13 27 28 Q31 37 45 35 M96 22 Q110 13 111 28 Q107 37 94 35" fill="none" stroke={c.trim} strokeWidth="3" strokeLinecap="round"/><circle cx="43" cy="29" r="3" fill={c.trim}/><circle cx="97" cy="29" r="3" fill={c.trim}/></>}
    {!female&&variant%4===0&&<path d="M53 17 L70 8 L87 17" fill="none" stroke={c.trim} strokeWidth="2.5" strokeLinecap="round"/>}
    {/* shoulder ornaments and fine anime linework */}
    <circle cx="48" cy="88" r="3" fill={'url(#'+uid+'gold)'}/><circle cx="92" cy="88" r="3" fill={'url(#'+uid+'gold)'}/>
    <path d="M47 91 Q39 100 43 111 M93 91 Q101 100 97 111 M56 89 Q61 96 62 103 M84 89 Q79 96 78 103" fill="none" stroke={c.trim} strokeWidth="1.15" opacity=".75"/>
    <path d="M47 98 L53 103 L47 108 M93 98 L87 103 L93 108" fill="none" stroke="#fff0c7" strokeWidth=".9" opacity=".55"/>
    <path d="M54 34 Q59 29 65 31 M76 31 Q84 28 88 35 M50 39 Q55 35 59 36 M83 36 Q88 34 91 40" fill="none" stroke="#fff" strokeWidth="1.1" opacity=".34" strokeLinecap="round"/>
    <path d="M55 58 Q61 64 67 59 M73 59 Q80 64 86 58" fill="none" stroke="#fff" strokeWidth=".75" opacity=".4"/>
    <circle cx="58" cy="52" r=".8" fill="#fff"/><circle cx="78" cy="52" r=".8" fill="#fff"/>
    <path d="M64 117 L70 123 L76 117 M60 125 L70 131 L80 125" fill="none" stroke="#fff0bf" strokeWidth="1" opacity=".65"/>
    {female?<><path d="M42 38 Q35 42 39 50 M98 38 Q105 42 101 50" fill="none" stroke={c.trim} strokeWidth="1.4"/><circle cx="39" cy="52" r="2" fill={'url(#'+uid+'gold)'}/><circle cx="101" cy="52" r="2" fill={'url(#'+uid+'gold)'}/></>:<path d="M48 27 Q70 19 92 27" fill="none" stroke={c.trim} strokeWidth="1.8" opacity=".55"/>}
  </svg>;
}
export default function HauntedCampGame(props: Props) {
  const { gameId, roomId, userId, isHost, roster, messages, onBack, onExit, onSendChat, voiceActive, voiceMuted, voiceStatus, voiceParticipantIds, voiceSpeakingIds, onToggleVoice, onToggleMute, onNightMute, onRewardsUpdated } = props;
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
  const [previousPhase, setPreviousPhase] = useState<string | null>(null);
  const [narratorVisible, setNarratorVisible] = useState(false);
  const [narratorText, setNarratorText] = useState('');
  const narratorRunRef = useRef<string | null>(null);
  const previousVotingRef = useRef<boolean | null>(null);
  const chatMessagesRef = useRef<HTMLDivElement | null>(null);
  const previousEventCountRef = useRef(0);
  const previousEventGameRef = useRef<string | null>(null);
  const { state, busy, error, start, submitKill, submitProtection, submitVote } =
    useHauntedGame(gameId || null, roomId, userId, isHost);

  const myRole = state?.role;
  const role = myRole ? roleCopy[myRole] : null;
  const alivePlayers = useMemo(() => state?.players.filter(p => p.is_alive) ?? [], [state?.players]);
  const lobbyBotCount = getHauntedBotCount(roster.length, quickMode);
  const secondsLeft = state?.phase_deadline_at ? Math.max(0, Math.ceil((new Date(state.phase_deadline_at).getTime() - now) / 1000)) : 0;
  const latestNight = [...(state?.events ?? [])].reverse().find(e => e.event_type === 'night_resolved');
  const latestVoteEvent = [...(state?.events ?? [])].reverse().find(e => ['player_ejected','vote_tie_resolved','vote_tied'].includes(e.event_type));
  const ejectedUserId = typeof latestVoteEvent?.payload.ejected_user_id === 'string' ? latestVoteEvent.payload.ejected_user_id : null;
  const voteCount = Number(state?.vote_count ?? 0);
  const isAlive = alivePlayers.some(player => player.user_id === userId);
  const aliveCount = alivePlayers.length;
  const voted = Boolean(state?.my_vote);

  useEffect(() => { preloadHauntedSounds(); setHauntedAudioMuted(!soundOn); if(soundOn)startCampMusic(); return()=>{stopCampMusic();if(roleHideTimerRef.current!==null)window.clearTimeout(roleHideTimerRef.current);}; }, []);
  useEffect(() => {
    if (!state?.id || !myRole || roleRevealGameRef.current === state.id) return;
    roleRevealGameRef.current = state.id;
    setRevealed(true);
    playHauntedSound('role');
    if (roleHideTimerRef.current !== null) window.clearTimeout(roleHideTimerRef.current);
    roleHideTimerRef.current = window.setTimeout(() => setRevealed(false), 6200);
  }, [state?.id, myRole]);
  useEffect(() => { setTarget(''); setConfirmNightChoice(false); }, [state?.status, state?.round]);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);
  const presentNarration = (key: string, text: string, useGeneratedVoice = false) => {
    narratorRunRef.current = key; setNarratorText(text); setNarratorVisible(true);
    void (async () => {
      if (soundOn) { if (useGeneratedVoice) await playHauntedNarrator(text); else await speakHauntedAnnouncement(text); }
      else await new Promise(resolve => window.setTimeout(resolve, 1800));
      if (narratorRunRef.current === key) setNarratorVisible(false);
    })();
  };

  useEffect(() => {
    const phase = state?.status ?? null;
    if (!phase || phase === previousPhase) return;
    if (phase === 'night') {
      startNightAmbience(); onNightMute(true);
      presentNarration(state!.id+':'+state!.round+':night', state?.game_mode==='quick'?'هبط الليل على المخيم. المسكون، اختار الضحية ديالك لهاد الليلة. القرار سري وعندك وقت محدود.':'هبط الليل على المخيم. المسكون، اختار الضحية ديالك لهاد الليلة. والفقيه، اختار شكون تحمي بسرية. عندكم وقت محدود، وكل اختيار محسوب.', true);
    } else if (phase === 'morning') {
      stopNightAmbience(); startMorningAmbience(); onNightMute(true);
      const latest = [...(state?.events ?? [])].reverse().find(e => e.event_type === 'night_resolved');
      const killedId = typeof latest?.payload.killed_user_id === 'string' ? latest.payload.killed_user_id : null;
      if (killedId) { playHauntedSound('death'); const victim = state?.players.find(player => player.user_id === killedId)?.username || 'واحد من السكان'; presentNarration(state!.id+':'+state!.round+':morning','طلع الصباح يا سكان الخيمة. لقينا '+victim+' خرج من المخيم هاد الليلة.'); }
      else { playHauntedSound('save'); presentNarration(state!.id+':'+state!.round+':morning','طلع الصباح يا سكان الخيمة. الليلة دازت بسلام، ما مات حتى واحد.'); }
    } else if (phase === 'day') {
      stopNightAmbience(); stopMorningAmbience(); onNightMute(false);
      presentNarration(state!.id+':'+state!.round+':day','رجع النهار للمخيم. عندكم أربع دقائق للنقاش وجمع القرائن. من بعد غادي يتحل التصويت، وكل واحد يختار بشوية ديال التركيز.');
    } else { stopNightAmbience(); stopMorningAmbience(); onNightMute(false); setNarratorVisible(false); }
    if (phase === 'ended') playHauntedSound(state?.winner === 'villagers' ? 'win' : 'lose');
    setPreviousPhase(phase);
  }, [state?.status, state?.winner, previousPhase, onNightMute, soundOn]);
  useEffect(() => {
    if (!state || state.status !== 'day') return;
    const previous = previousVotingRef.current; previousVotingRef.current = state.voting_open;
    if (previous === false && state.voting_open) presentNarration(state.id+':'+state.round+':voting','تحل التصويت. عندكم ثلاثين ثانية باش تختارو اللاعب اللي شاكين فيه. القرار سري، اختارو بعناية.');
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
      if (event.event_type === 'bot_chat' && !event.payload.system && soundOn && event.payload.message) { const botName=event.payload.system?'الراوي':state.players.find(player=>player.user_id===String(event.payload.bot_user_id))?.username||'واحد من البوتات'; speakHauntedAnnouncement(botName+' كيقول: '+String(event.payload.message)); }
      if (event.event_type === 'vote_tied' && soundOn) speakHauntedAnnouncement('وقع تعادل فالتصويت. غادي نعاودو التصويت بين المشتبه فيهم.');
      if (event.event_type === 'vote_tie_resolved' && soundOn) speakHauntedAnnouncement('بقى التعادل، وما خرج حتى واحد من المخيم.');
      if (event.event_type === 'player_ejected') { playHauntedSound('eject'); const id=String(event.payload.ejected_user_id||''); const name=state.players.find(player=>player.user_id===id)?.username||'واحد من السكان'; if(soundOn)speakHauntedAnnouncement('تحسم التصويت، وخرج '+name+' من المخيم.'); }
      if (event.event_type === 'game_ended') { onRewardsUpdated(); if(soundOn)speakHauntedAnnouncement(state.winner==='villagers'?'المواطنين ربحو! المسكون تكشف، والمخيم نجا.':'المسكون ربح! قدر يبقى مخفي حتى سيطر على المخيم.'); }
    });
    previousEventCountRef.current = count;
  }, [state?.id, state?.events.length, onRewardsUpdated, soundOn, state?.players, state?.winner]);
  useEffect(() => () => { stopHauntedNarrator(); stopNightAmbience(); stopMorningAmbience(); onNightMute(false); }, [onNightMute]);

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
  async function submitDayVote() {
    if (!target) return;
    const ok = await submitVote(target);
    if (ok) { setTarget(''); playHauntedSound('vote'); }
  }

  if (!state && gameId) {
    return <section className="haunted-shell haunted-loading"><div className="haunted-stars" aria-hidden="true"/><div className="haunted-loading-fire"><span/><i/><b/></div><h1>كنوجدو المخيم…</h1><p>الراوي كيوزع الأدوار وكيشعل العافية. بقا معانا لحظة.</p></section>;
  }

  if (!state) {
    return <section className="haunted-shell haunted-lobby">
      <div className="haunted-stars" aria-hidden="true"/><div className="haunted-header"><span className="haunted-kicker">ليلة فالخيمة · الفقيه والمسكون</span><h1>ليلة فالخيمة</h1><p>ليلة طويلة، أسرار مخفية، وشكون غادي يخرج من الخيمة؟</p></div>
      <div className="haunted-lobby-grid"><div className="haunted-lobby-card"><h2><Users size={18}/> المخيم ديالكم</h2><p className="haunted-bot-note">حتى إلا كنت بوحدك، غادي ينضمو للمخيم {lobbyBotCount} شخصيات إضافية، كيتفاعلو وكيصوتو معاك.</p><div className="haunted-roster">{roster.map((player,index)=><div className="haunted-player" key={player.user_id}><span className="haunted-player-index">{String(index+1).padStart(2,'0')}</span><span className="haunted-avatar">{player.profile?.avatar_url?<img src={player.profile.avatar_url} alt=""/>:(player.profile?.username||'؟').slice(0,1)}</span><span className="haunted-player-name">{player.profile?.username||'لاعب'}</span>{player.user_id===userId&&<small>أنت</small>}</div>)}</div><div className="haunted-mode-toggle"><label><input type="checkbox" checked={quickMode} onChange={e=>setQuickMode(e.target.checked)}/> الطور السريع بلا فقيه</label><small>{quickMode?'4 مشاركين إجمالاً، والباقي بوتات.':'10 مشاركين إجمالاً، والباقي بوتات. تقدر تلعب حتى بوحدك.'}</small></div>{!isHost&&<p className="haunted-waiting">كنستناو مول الغرفة يبدا اللعبة…</p>}{isHost&&<button className="haunted-primary" disabled={busy||roster.length<1||roster.length>(quickMode?4:10)} onClick={()=>void startGame()}>{busy?'كنوجدو المخيم...':<><Moon size={18}/> بدا الليلة الأولى</>}</button>}</div>
      <aside className="haunted-rules-card"><span className="haunted-kicker">كيفاش كتتلعب؟</span><h2>القواعد بسرعة</h2><ol><li>فالليل، المسكون كيختار ضحية والفقيه كيحمي لاعب بلا ما يعرف شكون المسكون.</li><li>فالصباح، كنعلنو غير واش مات شي حد ولا نجا المخيم.</li><li>فالنهار، ناقشو وصوّتو على اللي شاكين فيه.</li><li>إلا تطرد المسكون، المواطنين كيربحو. إلا بقاو مواطن أو أقل، المسكون كيربح.</li></ol><div className="haunted-role-legend"><span><Skull size={16}/> المسكون</span><span><Shield size={16}/> الفقيه</span><span><Users size={16}/> المواطنون</span></div></aside></div>
      {error&&<p className="haunted-error" role="alert">{error}</p>}
      <div className="haunted-footer-actions"><button className="haunted-ghost-button" onClick={onBack}>رجوع للّوبي</button><button className="haunted-ghost-button" onClick={onExit}>خروج من الغرفة</button></div>
    </section>;
  }

  return <section className={'haunted-shell haunted-phase-' + state.status} aria-label="ليلة فالخيمة">
    <div className="haunted-stars" aria-hidden="true"/><div className="haunted-mist" aria-hidden="true"/>
    <header className="haunted-topbar"><div><span className="haunted-kicker">ليلة فالخيمة · الجولة {state.round}</span><h1>ليلة فالخيمة</h1></div><div className="haunted-top-actions"><span className="haunted-round-pill">الجولة {state.round}</span><button className="haunted-icon-button" onClick={()=>{unlockHauntedNarrator();const next=!soundOn;setSoundOn(next);persistSoundEnabled(next);if(!next){stopNightAmbience();stopMorningAmbience();stopCampMusic();}else{startCampMusic();if(state.status==='night')startNightAmbience();else if(state.status==='morning')startMorningAmbience();}setHauntedAudioMuted(!next);}} aria-label={soundOn?'كتم المؤثرات':'تشغيل المؤثرات'}>{soundOn?<Volume2/>:<VolumeX/>}</button><button className="haunted-ghost-button" onClick={onBack}>اللوبي</button></div></header>
    {narratorVisible ? <motion.section className="haunted-narrator-stage" role="status" aria-live="assertive" initial={reduceMotion?false:{opacity:0,scale:.97}} animate={{opacity:1,scale:1}} transition={{duration:.35}}>
      <div className="haunted-narrator-orb"><span/><i/><b/><em/></div><span className="haunted-narrator-kicker"><Volume2 size={15}/> الراوي كيهضر</span><h2>اسمع الإعلان</h2><p>{narratorText}</p><div className="haunted-narrator-wave" aria-hidden="true">{Array.from({length:25},(_,i)=><i key={i} style={{'--wave-delay':(i%7)*.09+'s'} as React.CSSProperties}/>)}</div><small>غادي ترجع الكلسة والشعلة منين يسالي الراوي الإعلان</small>
    </motion.section> : <>
    <div className="haunted-camp-scene" aria-label="مخيم اللاعبين حول النار">
      <div className="haunted-scene-moon" aria-hidden="true"/>
      <div className="haunted-scene-tent" aria-hidden="true"><span/></div>
      <div className="haunted-campfire" aria-hidden="true"><i/><b/><span/></div>
      <div className="haunted-camp-ring">{state.players.map((player,index)=>{const angle=(index/Math.max(state.players.length,1))*Math.PI*2-Math.PI/2;const ringX=state.players.length>=8?40:32;const ringY=state.players.length>=8?28:30;const left=50+ringX*Math.cos(angle);const top=50+ringY*Math.sin(angle);const canChoose=player.is_alive&&isAlive&&((state.status==='night'&&(myRole==='haunter'||myRole==='faqih')&&(myRole==='faqih'||player.user_id!==userId))||(state.status==='day'&&state.voting_open&&!voted&&player.user_id!==userId));const selected=target===player.user_id;const hasVoice=voiceParticipantIds.includes(player.user_id);const speaking=voiceSpeakingIds.includes(player.user_id);return <button type="button" aria-label={player.username+(player.is_alive?'':'، مقصي')+(speaking?'، كيهضر':'')} aria-pressed={selected} disabled={!canChoose} className={'haunted-camp-seat '+(!player.is_alive?'is-out':'')+(canChoose?' is-selectable':'')+(selected?' is-selected':'')+(hasVoice?' has-voice':'')+(speaking?' is-speaking':'')} key={player.user_id} style={{left:left+'%',top:top+'%'}} onClick={()=>{if(!canChoose)return;setTarget(player.user_id);if(state.status==='night')setConfirmNightChoice(true);else if(state.status==='day'&&state.voting_open){void submitVote(player.user_id).then(ok=>{if(ok){setTarget('');playHauntedSound('vote');}});}}}><span><AnimeCampCharacter gender={player.gender || roster.find(member=>member.user_id===player.user_id)?.profile?.gender || 'male'} seed={player.avatar_key || player.username}/></span><b>{player.username}</b>{hasVoice&&<small className="haunted-seat-mic"><Mic size={11}/>{speaking?'كيهضر':'مايك'}</small>}{!player.is_alive&&<small className="haunted-eliminated-mark"><Skull size={13}/> مقصي</small>}{selected&&<i className="haunted-selected-flame"><Flame size={18}/></i>}</button>;})}</div>
      <span className="haunted-scene-caption">المخيم ديالكم · {alivePlayers.length} باقيين حدا العافية</span>{state.status==='day'&&state.voting_open&&!voted&&isAlive&&<span className="haunted-scene-hint">ضغط على الشخصية اللي شاك فيها باش تصوّت</span>}
    </div>
    <div className="haunted-phase-banner">
      {state.status==='night'?<><Moon/><span>الليل هبط على المخيم</span></>:state.status==='morning'?<><Sun/><span>طلع الصباح… شنو وقع فالليل؟</span></>:state.status==='day'?<><Sun/><span>وقت النقاش والتصويت</span></>:<><Trophy/><span>سالَت الحكاية</span></>}
      {state.status!=='ended'&&<strong><Clock3 size={15}/>{secondsLeft}ث</strong>}
    </div>
    </>}
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

    {!narratorVisible&&state.status==='night'&&<motion.div className="haunted-night-panel" initial={reduceMotion?false:{opacity:0,y:14}} animate={{opacity:1,y:0}} transition={{duration:reduceMotion?0.01:0.5}}><div className="haunted-moon"><Moon size={28}/></div><h2>{myRole==='haunter'?'اختار الضحية ديالك':myRole==='faqih'?'شكون غادي تعتق الليلة؟':'نعس… الليل ماشي وقت الكلام'}</h2><p>{myRole==='haunter'?'اختار لاعب حي واحد. القرار سري وما غادي يبان حتى واحد.':myRole==='faqih'?'اختار لاعب تحميه. ما غاديش تعرف واش الحماية نجحات حتى يطلع الصباح.':'تسنى الصباح. الميكروفونات مكتومة فالليل.'}</p>
      {!isAlive&&<p className="haunted-waiting">خرجتي من اللعبة، تقدر تبقى تتفرج ولكن ما تقدرش تختار أو تصوّت.</p>}
      {isAlive&&['haunter','faqih'].includes(myRole||'')&&<p className="haunted-choice-hint"><Flame size={16}/> ضغط مباشرة على شخصية من الحلقة، وغادي يبان ليك تأكيد قبل تسجيل القرار.</p>}
      {myRole==='villager'&&<div className="haunted-waiting">القرارات الليلية كتتدار بسرية تامة.</div>}
    </motion.div>}

    {!narratorVisible&&state.status==='morning'&&<motion.div className={'haunted-morning-panel '+(latestNight?.payload.killed_user_id?'has-death':'saved')} animate={reduceMotion?{}:latestNight?.payload.killed_user_id?{x:[0,-8,8,-8,8,0]}:{boxShadow:['0 0 0px #10b981','0 0 28px #10b981','0 0 0px #10b981']}} transition={{duration:reduceMotion?0.01:0.6,repeat:latestNight?.payload.killed_user_id?0:Infinity,repeatDelay:0.7}}><div className="haunted-sunrise"/><span className="haunted-morning-emoji">{latestNight?.payload.killed_user_id?<Skull size={34}/>:<Sparkles size={34}/>}</span><h2>{latestNight?.payload.killed_user_id?'لقينا لاعب ميت فالصباح':'نجا المخيم هاد الليلة!'}</h2><p>{latestNight?.payload.killed_user_id?('اللاعب '+(state.players.find(p=>p.user_id===latestNight.payload.killed_user_id)?.username||'المجهول')+' خرج من اللعبة. الدور ديالو باقي سري.'):'ما مات حتى واحد. ما كاين حتى كشف شكون تحمى ولا شكون حاول يقتل.'}</p><p className="haunted-auto-transition"><Clock3 size={15}/> الراوي غادي يفتح النقاش تلقائياً من بعد الإعلان.</p></motion.div>}

    {!narratorVisible&&state.status==='day'&&<div className="haunted-day-grid"><section className="haunted-vote-panel">{!isAlive&&<div className="haunted-waiting">خرجتي من اللعبة. تقدر تتابع النقاش والنتائج بلا تصويت.</div>}{latestVoteEvent&&<div className="haunted-outcome-banner">{String(latestVoteEvent.payload.message||'نتيجة التصويت تسجلات.')}{ejectedUserId ? ' '+(state.players.find(p=>p.user_id===ejectedUserId)?.username||'لاعب')+' خرج من المخيم.' : null}</div>}<h2>{state.voting_open?<><CheckCircle2 size={20}/> التصويت مفتوح دابا</>:<><Flame size={20}/> جلسة النقاش فالمخيم</>}</h2><p>{state.voting_open?'اختار لاعب حي واحد. الأصوات كتبقى سرية حتى يتحسم التصويت.':'عندكم 4 دقائق للنقاش وجمع القرائن. شخصيات المخيم غادي تشارك فالحوار، والتصويت ما كيتحل حتى يسالي الوقت.'}</p>{!state.voting_open&&<div className="haunted-discussion-timer"><Clock3/><b>{Math.floor(secondsLeft/60).toString().padStart(2,'0')}:{(secondsLeft%60).toString().padStart(2,'0')}</b><small>باقي على فتح التصويت</small></div>}{state.voting_open&&<><div className="haunted-target-grid">{isAlive&&alivePlayers.filter(p=>p.user_id!==userId).map(player=><button type="button" key={player.user_id} disabled={voted||busy} className={'haunted-target '+(target===player.user_id?'selected':'')} onClick={()=>setTarget(player.user_id)}><span>{player.avatar_url?<img src={player.avatar_url} alt=""/>:(player.username||'؟').slice(0,1)}</span><b>{player.username}</b></button>)}</div><button className="haunted-primary" disabled={busy||voted||!target||!isAlive} onClick={()=>void submitDayVote()}>{voted?'صوتك تسجل':'تأكيد التصويت'}</button><div className="haunted-vote-count"><b>{voteCount}/{aliveCount}</b><span>أصوات تسجلات</span><small>{state.vote_round===2?'إعادة التصويت بعد التعادل':'التصويت الأول'}</small></div></>}{!state.voting_open&&<p className="haunted-auto-transition"><Clock3 size={15}/> التصويت غادي يتحل تلقائياً ملي يسالي وقت النقاش.</p>}</section>
</div>}

    {state.status==='ended'&&<motion.div className={'haunted-end-panel '+(state.winner==='villagers'?'villagers-win':'haunter-win')} initial={reduceMotion?false:{opacity:0,scale:0.96,y:12}} animate={{opacity:1,scale:1,y:0}} transition={{duration:reduceMotion?0.01:0.55}}>{state.winner==='villagers'&&!reduceMotion&&<div className="haunted-confetti-layer" aria-hidden="true">{Array.from({length:18},(_,i)=><motion.i key={i} style={{left:(i*37)%100+'%'}} animate={{y:['-10vh','90vh'],rotate:[0,360],opacity:[1,1,0]}} transition={{duration:2.8,delay:(i%6)*0.12,ease:'linear'}} />)}</div>}<div className="haunted-win-icon">{state.winner==='villagers'?<Users size={36}/>:<Skull size={36}/>}</div><span className="haunted-kicker">THE CAMP HAS SPOKEN</span><h2>{state.winner==='villagers'?'المواطنين ربحو!':'المسكون سيطر على المخيم!'}</h2><p>ها الأدوار الحقيقية ديال جميع اللاعبين:</p><div className="haunted-role-reveal-list">{state.roles.map(item=>{const player=state.players.find(p=>p.user_id===item.user_id);return <div key={item.user_id}><span><RoleMark role={item.role} size={20}/></span><b>{player?.username||'لاعب'}</b><small>{roleCopy[item.role].name}</small></div>;})}</div><button className="haunted-primary" disabled={busy} onClick={()=>void startGame()}><RefreshCw/> لعبة جديدة</button><button className="haunted-secondary" onClick={onBack}>رجوع للّوبي</button></motion.div>}


    {!narratorVisible&&<section className="haunted-camp-chat"><h3><MessageCircle size={17}/> دردشة المخيم <span className="haunted-chat-live">مباشر</span></h3>{inviteDrawerOpen&&
    {state.status==='day'&&<section className="haunted-voice-dock" aria-label="الصوت المباشر">
        <div className="haunted-voice-dock-head"><span><Mic size={16}/> الصوت المباشر</span><small>{state.status==='day'?'الصوت متاح فالنقاش':'المايك غادي يتحل مع بداية النقاش'}</small></div>
        <div className="haunted-voice-dock-people">{state.players.filter(player=>voiceParticipantIds.includes(player.user_id)).slice(0,6).map(player=><span key={player.user_id} className={'haunted-voice-person '+(voiceSpeakingIds.includes(player.user_id)?'is-speaking':'')}><span className="haunted-voice-avatar">{player.avatar_url?<img src={player.avatar_url} alt=""/>:(player.username||'؟').slice(0,1)}</span><span className="haunted-voice-person-copy"><b>{player.username}</b><small>{voiceSpeakingIds.includes(player.user_id)?'كيهضر دابا':'متصل بالصوت'}</small></span><Mic size={13}/></span>)}{!voiceParticipantIds.length&&<small className="haunted-voice-empty">مازال حتى واحد ما دخل للصوت</small>}</div>
        <div className="haunted-voice-dock-actions"><span className={voiceActive?'is-connected':''}>{voiceActive?(voiceMuted?'الميك مكتوم':'الميك خدام'):voiceStatus}</span><button type="button" disabled={state.status!=='day'} className={voiceActive?'is-active':''} onClick={onToggleVoice}>{voiceActive?<><Headphones size={16}/> خروج من الصوت</>:<><Mic size={16}/> دخول للصوت</>}</button>{voiceActive&&<button type="button" className={voiceMuted?'is-muted':''} onClick={onToggleMute}>{voiceMuted?<><Mic size={16}/> حل المايك</>:<><MicOff size={16}/> كتم</>}</button>}</div>
      </section>}
<div className="haunted-chat-messages" ref={chatMessagesRef} role="log" aria-live="polite" aria-relevant="additions">{[...messages.slice(-8).map(m=>({id:m.id,user:m.user_id,system:false,text:m.body,created:m.created_at||''})),...(state.events||[]).filter(e=>e.event_type==='bot_chat'&&e.round===state.round).filter(e=>state.voting_open?!/عندكم 4 دقائق|جمعو القرائن|النقاش/i.test(String(e.payload.message||'')):!/تحل التصويت|التصويت مفتوح/i.test(String(e.payload.message||''))).map(e=>({id:e.id,user:String(e.payload.bot_user_id||''),system:Boolean(e.payload.system),text:String(e.payload.message||''),created:e.created_at}))].sort((a,b)=>a.created.localeCompare(b.created)).slice(-12).map(m=><p key={m.id} className={'haunted-chat-line '+(m.system?'is-system':m.user===userId?'is-mine':'is-other')}><b>{m.user===userId?'أنت':m.system?'الراوي':state.players.find(p=>p.user_id===m.user)?.username||roster.find(p=>p.user_id===m.user)?.profile?.username||'لاعب'}:</b> {m.text}</p>)}</div><form className="haunted-chat-compose" onSubmit={e=>{e.preventDefault();if(chatText.trim()){void onSendChat(chatText.trim());setChatText('');}}}><input value={chatText} onChange={e=>setChatText(e.target.value)} maxLength={500} placeholder="كتب رسالة للمخيم..."/><button type="submit" disabled={!chatText.trim()}>إرسال</button></form></section>}
    {error&&<p className="haunted-error" role="alert">{error}</p>}
    <footer className="haunted-bottom-bar"><div><span>{aliveCount} باقيين أحياء</span><small>{state.game_mode==='quick'?'طور سريع · بلا فقيه':'طور عادي'}</small></div><button className="haunted-ghost-button" onClick={onExit}>خروج من الغرفة</button></footer>
  </section>;
}
