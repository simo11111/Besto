export type GameSound = 'click'|'join'|'message'|'messageSent'|'submit'|'start'|'move'|'capture'|'countdown'|'timeout'|'victory'|'defeat'|'result'|'notification';

const STORAGE_KEY = 'mimox.sound.enabled';
let audioContext: AudioContext | null = null;

export function getSoundEnabled(): boolean {
  try { return window.localStorage.getItem(STORAGE_KEY) !== 'false'; }
  catch { return true; }
}

export function setSoundEnabled(enabled: boolean): void {
  try { window.localStorage.setItem(STORAGE_KEY, String(enabled)); }
  catch { /* Private browsing may block storage; sound still works for this session. */ }
}

function getAudioContext(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  const AudioContextConstructor = window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!AudioContextConstructor) return null;
  if (!audioContext) audioContext = new AudioContextConstructor();
  if (audioContext.state === 'suspended') void audioContext.resume().catch(() => undefined);
  return audioContext;
}

type Tone = { frequency: number; duration: number; delay?: number; endFrequency?: number; type?: OscillatorType; volume?: number };

function playTone(context: AudioContext, tone: Tone): void {
  const start = context.currentTime + (tone.delay || 0);
  const oscillator = context.createOscillator();
  const gain = context.createGain();
  oscillator.type = tone.type || 'sine';
  oscillator.frequency.setValueAtTime(tone.frequency, start);
  if (tone.endFrequency) oscillator.frequency.exponentialRampToValueAtTime(Math.max(1, tone.endFrequency), start + tone.duration);
  const peak = tone.volume ?? 0.075;
  gain.gain.setValueAtTime(0.0001, start);
  gain.gain.exponentialRampToValueAtTime(peak, start + Math.min(0.018, tone.duration / 3));
  gain.gain.exponentialRampToValueAtTime(0.0001, start + tone.duration);
  oscillator.connect(gain);
  gain.connect(context.destination);
  oscillator.start(start);
  oscillator.stop(start + tone.duration + 0.025);
}

const SOUND_MAP: Record<GameSound, Tone[]> = {
  click: [{ frequency: 620, duration: 0.045, volume: 0.035 }],
  join: [{ frequency: 440, duration: 0.09 }, { frequency: 660, duration: 0.13, delay: 0.08 }],
  message: [{ frequency: 740, duration: 0.07, volume: 0.045 }],
  messageSent: [{ frequency: 520, duration: 0.045, volume: 0.03 }],
  submit: [{ frequency: 520, duration: 0.07 }, { frequency: 780, duration: 0.09, delay: 0.07 }],
  start: [{ frequency: 392, duration: 0.1 }, { frequency: 523, duration: 0.1, delay: 0.09 }, { frequency: 784, duration: 0.16, delay: 0.18 }],
  move: [{ frequency: 440, duration: 0.065, type: 'triangle', volume: 0.06 }],
  capture: [{ frequency: 360, duration: 0.08, type: 'triangle' }, { frequency: 620, duration: 0.11, delay: 0.07 }],
  countdown: [{ frequency: 880, duration: 0.075, type: 'square', volume: 0.035 }],
  timeout: [{ frequency: 520, duration: 0.14, endFrequency: 260, type: 'triangle', volume: 0.06 }],
  victory: [{ frequency: 523, duration: 0.13 }, { frequency: 659, duration: 0.13, delay: 0.12 }, { frequency: 784, duration: 0.13, delay: 0.24 }, { frequency: 1047, duration: 0.24, delay: 0.36 }],
  defeat: [{ frequency: 392, duration: 0.16 }, { frequency: 330, duration: 0.18, delay: 0.15 }, { frequency: 247, duration: 0.26, delay: 0.31 }],
  result: [{ frequency: 587, duration: 0.12 }, { frequency: 784, duration: 0.18, delay: 0.12 }],
  notification: [{ frequency: 660, duration: 0.07 }, { frequency: 880, duration: 0.1, delay: 0.09 }]
};

export function playGameSound(name: GameSound): void {
  if (!getSoundEnabled()) return;
  const context = getAudioContext();
  if (!context) return;
  for (const tone of SOUND_MAP[name]) playTone(context, tone);
}
