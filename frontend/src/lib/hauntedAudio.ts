import { audioManager, type HauntedSound } from './audioManager';
import { getSoundEnabled } from './audio';

export function unlockHauntedNarrator() { if (typeof window !== 'undefined' && 'speechSynthesis' in window) { try { window.speechSynthesis.resume(); void window.speechSynthesis.getVoices(); } catch { /* Audio unlock is best-effort on mobile browsers. */ } } }

export function startCampMusic() { audioManager.fadeIn('camp', 0.18); }
export function stopCampMusic() { audioManager.stop('camp'); }

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
export function stopHauntedNarrator() { if(announcementAudio){announcementAudio.pause();announcementAudio.currentTime=0;announcementAudio=null;} const finishAnnouncement=announcementFinish;announcementFinish=null;finishAnnouncement?.(); if(narratorAudio){narratorAudio.pause();narratorAudio.currentTime=0;narratorAudio=null;} const finish=narratorFinish;narratorFinish=null;finish?.(); }
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
  if (muted) { stopHauntedNarrator(); const pending=speechQueue.splice(0);pending.forEach(item=>item.resolve());speechBusy=false;if(typeof window!=='undefined'&&'speechSynthesis'in window)window.speechSynthesis.cancel(); }
}

/** Queue spoken announcements so one bot line never cuts off the previous one. */
let speechQueue: Array<{text:string;resolve:()=>void}> = [];
let speechBusy = false;

function speakNext() {
  if (typeof window === 'undefined' || !('speechSynthesis' in window) || speechBusy || !speechQueue.length) return;
  const synth = window.speechSynthesis;
  if (synth.paused) synth.resume();
  const item = speechQueue.shift();
  if (!item) return;
  const text = item.text;
  speechBusy = true;
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = 'ar-MA';
  utterance.rate = 0.86;
  utterance.pitch = 0.92;
  utterance.volume = 1;
  let begun = false;
  const begin = () => {
    if (begun) return;
    begun = true;
    const voices = synth.getVoices();
    const voice = voices.find(item => item.lang.toLowerCase() === 'ar-ma')
      || voices.find(item => item.lang.toLowerCase().startsWith('ar'))
      || voices.find(item => item.default)
      || voices[0];

    if (voice) utterance.voice = voice;
    utterance.onend = () => { speechBusy = false; item.resolve(); window.setTimeout(speakNext, 180); };
    utterance.onerror = () => { speechBusy = false; item.resolve(); window.setTimeout(speakNext, 180); };
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


type HauntedAnnouncementSegment = 'morning_safe' | 'morning_death' | 'discussion' | 'voting' | 'ejected' | 'win_villagers' | 'win_haunter';
const announcementSegments: Record<HauntedAnnouncementSegment, [number, number]> = {
  morning_safe: [0, 13.9],
  morning_death: [14.0, 29.1],
  discussion: [29.2, 45.3],
  voting: [45.4, 62.0],
  ejected: [62.1, 74.4],
  win_villagers: [74.5, 87.8],
  win_haunter: [87.9, 98.55],
};
let announcementsUrl: string | null = null;
let announcementAudio: HTMLAudioElement | null = null;
let announcementFinish: (() => void) | null = null;
let announcementRequest: Promise<string | null> | null = null;

async function getAnnouncementsUrl(): Promise<string | null> {
  if (announcementsUrl) return announcementsUrl;
  if (!announcementRequest) {
    announcementRequest = (async () => {
      const base = String(import.meta.env.VITE_SUPABASE_URL || '').replace(/\/+$/, '');
      if (!base) return null;
      const response = await fetch(base + '/functions/v1/cache-haunted-announcements', { method: 'GET', cache: 'no-store' });
      if (!response.ok) return null;
      const result = await response.json() as { ready?: boolean; url?: string };
      if (result.ready && typeof result.url === 'string') announcementsUrl = result.url;
      return announcementsUrl;
    })().catch(() => null).finally(() => { announcementRequest = null; });
  }
  return announcementRequest;
}

export async function playHauntedAnnouncementSegment(segment: HauntedAnnouncementSegment, fallbackText: string): Promise<void> {
  if (typeof window === 'undefined' || !getSoundEnabled()) return;
  if (announcementAudio) { announcementAudio.pause(); announcementAudio.currentTime = 0; announcementAudio = null; const finishPrevious = announcementFinish; announcementFinish = null; finishPrevious?.(); }
  const url = await getAnnouncementsUrl();
  if (!url) { await speakHauntedAnnouncement(fallbackText); return; }
  const [start, end] = announcementSegments[segment];
  await new Promise<void>(resolve => {
    const audio = new Audio(url);
    announcementAudio = audio;
    audio.preload = 'auto';
    audio.volume = 0.98;
    let finished = false;
    const finish = () => {
      if (finished) return;
      finished = true;
      audio.ontimeupdate = null;
      audio.onended = null;
      audio.onerror = null;
      if (announcementAudio === audio) announcementAudio = null;
      if (announcementFinish === finish) announcementFinish = null;
      resolve();
    };
    let playbackStarted = false;
    const beginPlayback = () => {
      if (playbackStarted || finished) return;
      playbackStarted = true;
      void audio.play().catch(() => { void speakHauntedAnnouncement(fallbackText).finally(finish); });
    };
    announcementFinish = finish;
    audio.onloadedmetadata = () => {
      if (start <= 0) { beginPlayback(); return; }
      audio.addEventListener('seeked', beginPlayback, { once: true });
      try {
        audio.currentTime = Math.min(start, Math.max(0, audio.duration - 0.2));
        if (Math.abs(audio.currentTime - start) < 0.05) beginPlayback();
      } catch { beginPlayback(); }
    };
    audio.ontimeupdate = () => { if (playbackStarted && audio.currentTime >= end) { audio.pause(); finish(); } };
    audio.onended = finish;
    audio.onerror = () => { if (announcementAudio === audio) announcementAudio = null; void speakHauntedAnnouncement(fallbackText).finally(finish); };
  });
}

export function preloadHauntedAnnouncements() { void getAnnouncementsUrl(); }
