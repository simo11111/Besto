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
}

/** Speak short phase announcements with the device's Arabic voice when available. */
export function speakHauntedAnnouncement(text: string) {
  if (typeof window === 'undefined' || !('speechSynthesis' in window) || !text.trim()) return;
  const synth = window.speechSynthesis;
  synth.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = 'ar-MA';
  utterance.rate = 0.88;
  utterance.pitch = 0.94;
  utterance.volume = 1;
  let spoken = false;
  const speakWithAvailableVoice = () => {
    if (spoken) return;
    spoken = true;
    const voices = synth.getVoices();
    const voice = voices.find(item => item.lang.toLowerCase() === 'ar-ma')
      || voices.find(item => item.lang.toLowerCase().startsWith('ar'))
      || voices.find(item => item.lang.toLowerCase().startsWith('fr'));
    if (voice) utterance.voice = voice;
    synth.speak(utterance);
  };
  const onVoicesChanged = () => {
    if (synth.getVoices().length) {
      window.clearTimeout(fallbackTimer);
      synth.removeEventListener('voiceschanged', onVoicesChanged);
      speakWithAvailableVoice();
    }
  };
  const fallbackTimer = window.setTimeout(() => {
    synth.removeEventListener('voiceschanged', onVoicesChanged);
    speakWithAvailableVoice();
  }, 900);
  synth.addEventListener('voiceschanged', onVoicesChanged);
  if (synth.getVoices().length) onVoicesChanged();
}
