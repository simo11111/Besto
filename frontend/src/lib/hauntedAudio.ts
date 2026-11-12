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
  window.speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = 'ar-MA';
  utterance.rate = 0.92;
  utterance.pitch = 0.92;
  const voices = window.speechSynthesis.getVoices();
  const arabicVoice = voices.find(voice => voice.lang.toLowerCase().startsWith('ar-ma'))
    || voices.find(voice => voice.lang.toLowerCase().startsWith('ar'));
  if (arabicVoice) utterance.voice = arabicVoice;
  window.speechSynthesis.speak(utterance);
}
