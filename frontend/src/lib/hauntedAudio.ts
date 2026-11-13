import { audioManager, type HauntedSound } from './audioManager';
import { getSoundEnabled } from './audio';

export function unlockHauntedNarrator() {
  if (typeof window === 'undefined' || !('speechSynthesis' in window)) return;
  try {
    window.speechSynthesis.resume();
    void window.speechSynthesis.getVoices();
  } catch { /* Audio unlock is best-effort on mobile browsers. */ }
}

export function startCampMusic() { audioManager.unlock(); audioManager.fadeIn('camp', 0.18); }
export function stopCampMusic() { audioManager.stop('camp'); }
export function startDiscussionAmbience() { audioManager.startDiscussionFire(); }
export function stopDiscussionAmbience() { audioManager.stopDiscussionFire(); }

export function preloadHauntedSounds() {
  void audioManager.preload(['role', 'death', 'save', 'vote', 'eject', 'win', 'lose']);
}
export function startNightAmbience() {
  audioManager.stop('morning');
  audioManager.fadeIn('night', 0.3);
}
export function stopNightAmbience() { audioManager.stop('night'); }
export function startMorningAmbience() {
  audioManager.stop('night');
  audioManager.fadeIn('morning', 0.3);
}
export function stopMorningAmbience() { audioManager.stop('morning'); }
export function playHauntedSound(name: Exclude<HauntedSound, 'night'> | 'night') {
  if (name === 'morning') startMorningAmbience();
  else audioManager.play(name, 0.7);
}

type SpeechQueueItem = { text: string; resolve: () => void };
let speechQueue: SpeechQueueItem[] = [];
let speechBusy = false;
let speechGeneration = 0;
let currentSpeechResolve: (() => void) | null = null;

/** Stop the current utterance and resolve every queued promise cleanly. */
export function stopHauntedNarrator() {
  speechGeneration++;
  const pending = speechQueue.splice(0);
  pending.forEach(item => item.resolve());
  const activeResolve = currentSpeechResolve;
  currentSpeechResolve = null;
  activeResolve?.();
  speechBusy = false;
  if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
    try { window.speechSynthesis.cancel(); } catch { /* best effort */ }
  }
}

export async function playHauntedNarrator(fallbackText: string): Promise<void> {
  if (typeof window === 'undefined' || !getSoundEnabled()) return;
  await speakHauntedAnnouncement(fallbackText);
}

export function setHauntedAudioMuted(muted: boolean) {
  audioManager.setMuted(muted);
  if (muted) stopHauntedNarrator();
}

/** Break long Darija narration into short, complete clauses for Android TTS. */
export function splitHauntedAnnouncementText(value: string): string[] {
  const normalized = value.replace(/\s+/g, ' ').trim();
  if (!normalized) return [];
  const sentences = normalized.split(/(?<=[،؛.!؟])\s+/u);
  const chunks: string[] = [];
  for (const sentence of sentences) {
    let rest = sentence.trim();
    while (rest.length > 104) {
      let cut = rest.lastIndexOf(' ', 104);
      if (cut < 42) cut = 104;
      chunks.push(rest.slice(0, cut).trim());
      rest = rest.slice(cut).trim();
    }
    if (rest) chunks.push(rest);
  }
  return chunks;
}

function chooseNarratorVoice(voices: SpeechSynthesisVoice[]): SpeechSynthesisVoice | undefined {
  const arabic = voices.filter(voice => voice.lang.toLowerCase().startsWith('ar'));
  if (!arabic.length) return undefined;
  const maleWords = /\b(male|man|masculine|badr|adil|yassine|mohamed|mohammed|ahmed|hamza|khaled|anas)\b|ذكر|رجالي|رجل/i;
  const femaleWords = /\b(female|woman|girl|feminine)\b|أنثى|نسائي|امرأة/i;
  const moroccanWords = /morocc|darija|maghreb|ar-ma|ma\b|مغربي/i;
  const naturalWords = /natural|enhanced|premium|google/i;
  return arabic
    .map(voice => {
      const name = voice.name.toLowerCase();
      const lang = voice.lang.toLowerCase();
      let score = 0;
      if (maleWords.test(name)) score += 100;
      if (femaleWords.test(name)) score -= 120;
      if (moroccanWords.test(name + ' ' + lang)) score += 45;
      if (lang === 'ar-ma') score += 35;
      if (lang === 'ar') score += 12;
      if (lang === 'ar-sa' || lang === 'ar-eg') score += 5;
      if (naturalWords.test(name)) score += 12;
      if (voice.default) score += 2;
      return { voice, score };
    })
    .sort((a, b) => b.score - a.score)[0]?.voice;
}

/** Speak one queued announcement at a time; no external TTS service or paid API. */
function speakNext() {
  if (typeof window === 'undefined' || !('speechSynthesis' in window) || speechBusy || !speechQueue.length) return;
  const synth = window.speechSynthesis;
  if (synth.paused) synth.resume();
  const item = speechQueue.shift();
  if (!item) return;
  const chunks = splitHauntedAnnouncementText(item.text);
  const generation = speechGeneration;
  currentSpeechResolve = item.resolve;
  speechBusy = true;
  let chunkIndex = 0;
  let watchdog: number | null = null;
  let activeUtterance: SpeechSynthesisUtterance | null = null;
  let voice = chooseNarratorVoice(synth.getVoices());

  const finishItem = () => {
    if (generation !== speechGeneration) return;
    if (watchdog !== null) window.clearTimeout(watchdog);
    activeUtterance = null;
    currentSpeechResolve = null;
    speechBusy = false;
    item.resolve();
    window.setTimeout(() => { if (generation === speechGeneration) speakNext(); }, 150);
  };

  const speakChunk = (retry = 0) => {
    if (generation !== speechGeneration) return;
    if (chunkIndex >= chunks.length) { finishItem(); return; }
    const utterance = new SpeechSynthesisUtterance(chunks[chunkIndex]);
    activeUtterance = utterance;
    utterance.lang = voice?.lang?.toLowerCase().startsWith('ar') ? voice.lang : 'ar-MA';
    // Lower pitch and a measured pace give the narrator a steadier, masculine delivery.
    utterance.rate = 0.88;
    utterance.pitch = 0.76;
    utterance.volume = 1;
    if (voice) utterance.voice = voice;

    const advance = () => {
      if (generation !== speechGeneration || activeUtterance !== utterance) return;
      if (watchdog !== null) window.clearTimeout(watchdog);
      activeUtterance = null;
      chunkIndex++;
      window.setTimeout(() => speakChunk(), 100);
    };
    utterance.onend = advance;
    utterance.onerror = event => {
      if (generation !== speechGeneration || activeUtterance !== utterance) return;
      if (watchdog !== null) window.clearTimeout(watchdog);
      activeUtterance = null;
      if (retry < 1 && event.error !== 'not-allowed' && event.error !== 'canceled' && event.error !== 'interrupted') {
        window.setTimeout(() => speakChunk(retry + 1), 220);
      } else {
        chunkIndex++;
        window.setTimeout(() => speakChunk(), 100);
      }
    };
    watchdog = window.setTimeout(() => {
      if (generation !== speechGeneration || activeUtterance !== utterance) return;
      activeUtterance = null;
      try { synth.cancel(); } catch { /* best effort */ }
      // Some Android engines omit onend; retry the same clause before advancing.
      if (retry < 1) window.setTimeout(() => speakChunk(retry + 1), 260);
      else { chunkIndex++; window.setTimeout(() => speakChunk(), 180); }
    }, Math.max(24000, chunks[chunkIndex].length * 420));
    synth.speak(utterance);
  };

  let voiceSelectionStarted = false;
  const begin = () => {
    if (generation !== speechGeneration || voiceSelectionStarted) return;
    voiceSelectionStarted = true;
    voice = chooseNarratorVoice(synth.getVoices());
    speakChunk();
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
      if (generation === speechGeneration && speechBusy && !synth.speaking) begin();
    }, 1200);
  }
}

export function speakHauntedAnnouncement(text: string): Promise<void> {
  if (typeof window === 'undefined' || !('speechSynthesis' in window) || !text.trim()) return Promise.resolve();
  return new Promise(resolve => {
    window.speechSynthesis.resume();
    speechQueue.push({ text: text.trim(), resolve });
    speakNext();
  });
}

export type HauntedAnnouncementSegment = 'night' | 'night_quick' | 'faqih_awake' | 'morning_safe' | 'morning_death' | 'discussion' | 'voting' | 'tie' | 'ejected' | 'win_villagers' | 'win_haunter';

/** All narration now uses the same device voice so the tone never jumps between clips. */
export async function playHauntedAnnouncementSegment(
  _segment: HauntedAnnouncementSegment,
  fallbackText: string,
  afterText?: string,
): Promise<void> {
  if (typeof window === 'undefined' || !getSoundEnabled()) return;
  await speakHauntedAnnouncement(fallbackText);
  if (afterText) await speakHauntedAnnouncement(afterText);
}

export function preloadHauntedAnnouncements() {
  if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
    try { void chooseNarratorVoice(window.speechSynthesis.getVoices()); } catch { /* best effort */ }
  }
}
