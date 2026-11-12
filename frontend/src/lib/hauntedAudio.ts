import { audioManager, type HauntedSound } from './audioManager';
import { getSoundEnabled } from './audio';

export function unlockHauntedNarrator() { if (typeof window !== 'undefined' && 'speechSynthesis' in window) { try { window.speechSynthesis.resume(); void window.speechSynthesis.getVoices(); } catch { /* Audio unlock is best-effort on mobile browsers. */ } } }

export function startCampMusic() { audioManager.fadeIn('camp', 0.18); }
export function stopCampMusic() { audioManager.stop('camp'); }
export function startDiscussionAmbience() { audioManager.startDiscussionFire(); }
export function stopDiscussionAmbience() { audioManager.stopDiscussionFire(); }

export function preloadHauntedSounds() {
  void audioManager.preload(['role','death','save','vote','eject','win','lose']);
}
export function startNightAmbience() {
  audioManager.stop('morning');
  audioManager.fadeIn('night', 0.3);
}
export function stopNightAmbience() {
  audioManager.stop('night');
}
export function startMorningAmbience() {
  audioManager.stop('night');
  audioManager.fadeIn('morning', 0.3);
}
export function stopMorningAmbience() {
  audioManager.stop('morning');
}
export function playHauntedSound(name: Exclude<HauntedSound, 'night'> | 'night') {
  if (name === 'morning') startMorningAmbience();
  else audioManager.play(name, 0.7);
}
let narratorAudio: HTMLAudioElement | null = null;
let narratorFinish: (() => void) | null = null;
let speechQueue: Array<{text:string;resolve:()=>void}> = [];
let speechBusy = false;
let speechGeneration = 0;
let announcementAudio: HTMLAudioElement | null = null;
let announcementFinish: (() => void) | null = null;
let announcementRun = 0;
let announcementsUrl: string | null = null;
let quickAnnouncementsUrl: string | null = null;
let faqihAnnouncementsUrl: string | null = null;
let announcementRequest: Promise<string | null> | null = null;
let currentSpeechResolve: (()=>void) | null = null;
export function stopHauntedNarrator() {
  announcementRun++;
  speechGeneration++;
  const pending = speechQueue.splice(0);
  pending.forEach(item => item.resolve());
  const activeResolve=currentSpeechResolve;currentSpeechResolve=null;activeResolve?.();
  speechBusy = false;
  if(typeof window!=='undefined'&&window.speechSynthesis)window.speechSynthesis.cancel();
  if(announcementAudio){announcementAudio.pause();announcementAudio.currentTime=0;announcementAudio=null;}
  const finishAnnouncement=announcementFinish;announcementFinish=null;finishAnnouncement?.();
  if(narratorAudio){narratorAudio.pause();narratorAudio.currentTime=0;narratorAudio=null;}
  const finish=narratorFinish;narratorFinish=null;finish?.();
}
export async function playHauntedNarrator(fallbackText: string): Promise<void> {
  if(typeof window==='undefined'||!getSoundEnabled())return;
  stopHauntedNarrator();
  let source='/sounds/narrator-night.mp3';
  try {
    const response=await fetch('/api/warm-narrator',{cache:'no-store'});
    if(response.ok){const result=await response.json() as {ready?:boolean;url?:string};if(result.ready&&result.url)source=result.url;}
  } catch { /* The Pages audio proxy remains a fallback if persistent storage is unavailable. */ }
  return new Promise(resolve=>{const audio=new Audio(source);narratorAudio=audio;audio.preload='auto';audio.volume=.96;audio.playbackRate=1.08;let finished=false;let usedFallback=source==='/sounds/narrator-night.mp3';
    const done=()=>{if(finished)return;finished=true;audio.onended=null;audio.onerror=null;if(narratorAudio===audio)narratorAudio=null;if(narratorFinish===done)narratorFinish=null;resolve();}; narratorFinish=done;
    audio.onended=done;
    audio.onerror=()=>{if(!usedFallback){usedFallback=true;audio.src='/sounds/narrator-night.mp3';void audio.play().catch(()=>{if(narratorAudio===audio)narratorAudio=null;void speakHauntedAnnouncement(fallbackText).then(done);});return;}if(narratorAudio===audio)narratorAudio=null;void speakHauntedAnnouncement(fallbackText).then(done);};
    void audio.play().catch(()=>{if(!usedFallback){usedFallback=true;audio.src='/sounds/narrator-night.mp3';void audio.play().catch(()=>{if(narratorAudio===audio)narratorAudio=null;void speakHauntedAnnouncement(fallbackText).then(done);});return;}if(narratorAudio===audio)narratorAudio=null;void speakHauntedAnnouncement(fallbackText).then(done);});});
}
export function setHauntedAudioMuted(muted: boolean) {
  audioManager.setMuted(muted);
  if (muted) stopHauntedNarrator();
}

/** Queue spoken announcements so one bot line never cuts off the previous one. */
function speakNext() {
  if (typeof window === 'undefined' || !('speechSynthesis' in window) || speechBusy || !speechQueue.length) return;
  const synth = window.speechSynthesis;
  if (synth.paused) synth.resume();
  const item = speechQueue.shift();
  if (!item) return;
  const text = item.text;
  const generation = speechGeneration;
  currentSpeechResolve=item.resolve;
  speechBusy = true;
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = 'ar-MA';
  utterance.rate = 0.86;
  utterance.pitch = 0.72;
  utterance.volume = 1;
  let begun = false;
  const begin = () => {
    if (begun || generation !== speechGeneration) return;
    begun = true;
    const voices = synth.getVoices();
    const voice = voices.find(item => item.lang.toLowerCase() === 'ar-ma')
      || voices.find(item => item.lang.toLowerCase().startsWith('ar'))
      || voices.find(item => item.default)
      || voices[0];

    if (voice) utterance.voice = voice;
    utterance.onend = () => { if(generation !== speechGeneration)return; currentSpeechResolve=null; speechBusy = false; item.resolve(); window.setTimeout(()=>{if(generation===speechGeneration)speakNext();},180); };
    utterance.onerror = () => { if(generation !== speechGeneration)return; currentSpeechResolve=null; speechBusy = false; item.resolve(); window.setTimeout(()=>{if(generation===speechGeneration)speakNext();},180); };
    synth.speak(utterance);
  };
  if (synth.getVoices().length) begin();
  else {
    const onVoicesChanged = () => {
      synth.removeEventListener('voiceschanged', onVoicesChanged);
      begin();
    };
    synth.addEventListener('voiceschanged', onVoicesChanged);
    window.setTimeout(() => {
      synth.removeEventListener('voiceschanged', onVoicesChanged);
      if (speechBusy && !synth.speaking) begin();
    }, 900);
  }
}

export function speakHauntedAnnouncement(text: string): Promise<void> {
  if(typeof window==='undefined'||!('speechSynthesis'in window)||!text.trim())return Promise.resolve();
  return new Promise(resolve=>{window.speechSynthesis.resume();speechQueue.push({text:text.trim(),resolve});if(speechQueue.length>8){const dropped=speechQueue.splice(0,speechQueue.length-8);dropped.forEach(item=>item.resolve());}speakNext();});
}



export type HauntedAnnouncementSegment = 'night' | 'night_quick' | 'faqih_awake' | 'morning_safe' | 'morning_death' | 'discussion' | 'voting' | 'tie' | 'ejected' | 'win_villagers' | 'win_haunter';

const announcementSegments: Record<HauntedAnnouncementSegment, [number, number]> = {
  night: [30.98, 42.40],
  night_quick: [0, 7.15],
  faqih_awake: [0, 9.334],
  morning_safe: [44.15, 53.98],
  morning_death: [55.63, 66.10],
  discussion: [68.05, 81.35],
  voting: [82.98, 93.90],
  tie: [95.45, 103.12],
  ejected: [104.43, 113.22],
  win_villagers: [114.84, 123.30],
  win_haunter: [124.73, 132.03],
};

async function getAnnouncementsUrl(): Promise<string | null> {
  if (announcementsUrl) return announcementsUrl;
  if (!announcementRequest) {
    announcementRequest = (async () => {
      const base = String(import.meta.env.VITE_SUPABASE_URL || '').replace(/\/+$/, '');
      if (!base) return null;
      const response = await fetch(base + '/functions/v1/cache-haunted-announcements', { method: 'GET', cache: 'no-store' });
      if (!response.ok) return null;
      const result = await response.json() as { ready?: boolean; url?: string; quick_url?: string; faqih_url?: string };
      if (result.ready && typeof result.url === 'string') announcementsUrl = result.url;
      if (result.ready && typeof result.quick_url === 'string') quickAnnouncementsUrl = result.quick_url;
      if (result.ready && typeof result.faqih_url === 'string') faqihAnnouncementsUrl = result.faqih_url;
      return announcementsUrl;
    })().catch(() => null).finally(() => { announcementRequest = null; });
  }
  return announcementRequest;
}

export async function playHauntedAnnouncementSegment(segment: HauntedAnnouncementSegment, fallbackText: string, afterText?: string): Promise<void> {
  if (typeof window === 'undefined' || !getSoundEnabled()) return;
  const currentRun = ++announcementRun;

  if (announcementAudio) {
    announcementAudio.pause();
    announcementAudio.currentTime = 0;
    announcementAudio = null;
    const finishPrevious = announcementFinish;
    announcementFinish = null;
    finishPrevious?.();
  }

  const masterUrl = await getAnnouncementsUrl();
  if (currentRun !== announcementRun) return;
  const url = segment === 'night_quick' ? quickAnnouncementsUrl : segment === 'faqih_awake' ? faqihAnnouncementsUrl : masterUrl;
  if (!url) {
    await speakHauntedAnnouncement(fallbackText);
    if (afterText) await speakHauntedAnnouncement(afterText);
    return;
  }

  const [start, end] = announcementSegments[segment];
  const played = await new Promise<boolean>(resolve => {
    const audio = new Audio(url);
    announcementAudio = audio;
    audio.preload = 'auto';
    audio.volume = 0.98;
    audio.playbackRate = segment === 'faqih_awake' ? 0.88 : 0.9;
    let finished = false;
    let playbackStarted = false;
    const finish = (ok: boolean) => {
      if (finished) return;
      finished = true;
      audio.ontimeupdate = null;
      audio.onended = null;
      audio.onerror = null;
      if (announcementAudio === audio) announcementAudio = null;
      if (announcementFinish === finishDone) announcementFinish = null;
      resolve(ok);
    };
    const finishDone = () => finish(true);
    const beginPlayback = () => {
      if (playbackStarted || finished) return;
      playbackStarted = true;
      void audio.play().catch(() => finish(false));
    };
    announcementFinish = finishDone;
    audio.onloadedmetadata = () => {
      audio.addEventListener('seeked', beginPlayback, { once: true });
      try {
        const safeStart = Math.min(start, Math.max(0, audio.duration - 0.25));
        audio.currentTime = safeStart;
        if (Math.abs(audio.currentTime - safeStart) < 0.05) beginPlayback();
      } catch {
        beginPlayback();
      }
    };
    audio.ontimeupdate = () => {
      if (playbackStarted && audio.currentTime >= end) {
        audio.pause();
        finish(true);
      }
    };
    audio.onended = () => finish(true);
    audio.onerror = () => finish(false);
  });

  if (currentRun !== announcementRun) return;
  if (!played) await speakHauntedAnnouncement(fallbackText);
  if (currentRun !== announcementRun) return;
  if (afterText) await speakHauntedAnnouncement(afterText);
}

export function preloadHauntedAnnouncements() {
  void getAnnouncementsUrl();
}
