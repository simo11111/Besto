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
export function stopHauntedNarrator() { if(typeof window!=='undefined'&&window.speechSynthesis)window.speechSynthesis.cancel(); if(narratorAudio){narratorAudio.pause();narratorAudio.currentTime=0;narratorAudio=null;} const finish=narratorFinish;narratorFinish=null;finish?.(); }
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

/** The previous combined ElevenLabs take included spoken production directions.
 * Until a clean Darija recording is available, never play that faulty file.
 * Speak only the exact in-game announcement text supplied by the game state.
 */
export async function playHauntedAnnouncementSegment(segment: HauntedAnnouncementSegment, fallbackText: string): Promise<void> {
  void segment;
  await speakHauntedAnnouncement(fallbackText);
}

export function preloadHauntedAnnouncements() {}
