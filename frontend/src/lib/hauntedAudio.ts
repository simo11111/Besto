import { audioManager, type HauntedSound } from './audioManager';

export function preloadHauntedSounds() {
  void audioManager.preload();
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
export function setHauntedAudioMuted(muted: boolean) {
  audioManager.setMuted(muted);
  if (muted) {
    speechQueue = [];
    speechBusy = false;
    if (typeof window !== 'undefined' && 'speechSynthesis' in window) window.speechSynthesis.cancel();
  }
}

/** Queue spoken announcements so one bot line never cuts off the previous one. */
let speechQueue: string[] = [];
let speechBusy = false;

function speakNext() {
  if (typeof window === 'undefined' || !('speechSynthesis' in window) || speechBusy || !speechQueue.length) return;
  const synth = window.speechSynthesis;
  const text = speechQueue.shift();
  if (!text) return;
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
    utterance.onend = () => { speechBusy = false; window.setTimeout(speakNext, 180); };
    utterance.onerror = () => { speechBusy = false; window.setTimeout(speakNext, 180); };
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

export function speakHauntedAnnouncement(text: string) {
  if (typeof window === 'undefined' || !('speechSynthesis' in window) || !text.trim()) return;
  speechQueue.push(text.trim());
  if (speechQueue.length > 8) speechQueue = speechQueue.slice(-8);
  speakNext();
}
