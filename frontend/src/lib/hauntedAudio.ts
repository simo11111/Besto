import { getSoundEnabled } from './audio';

let context: AudioContext | null = null;
let ambience: { source: AudioBufferSourceNode; gain: GainNode; filter: BiquadFilterNode } | null = null;

function getContext() {
  if (typeof window === 'undefined' || !getSoundEnabled()) return null;
  const Ctor = window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Ctor) return null;
  context ||= new Ctor();
  if (context.state === 'suspended') void context.resume().catch(() => undefined);
  return context;
}
function tone(frequency: number, duration: number, wave: OscillatorType = 'sine', delay = 0, volume = 0.06) {
  const ctx = getContext(); if (!ctx) return;
  const start = ctx.currentTime + delay;
  const oscillator = ctx.createOscillator();
  const gain = ctx.createGain();
  oscillator.type = wave;
  oscillator.frequency.setValueAtTime(frequency, start);
  gain.gain.setValueAtTime(0.0001, start);
  gain.gain.exponentialRampToValueAtTime(volume, start + 0.025);
  gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);
  oscillator.connect(gain); gain.connect(ctx.destination);
  oscillator.start(start); oscillator.stop(start + duration + 0.03);
}
export function startNightAmbience() {
  const ctx = getContext(); if (!ctx || ambience) return;
  const buffer = ctx.createBuffer(1, ctx.sampleRate * 3, ctx.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < data.length; i += 1) data[i] = (Math.random() * 2 - 1) * 0.18;
  const source = ctx.createBufferSource();
  const filter = ctx.createBiquadFilter();
  const gain = ctx.createGain();
  source.buffer = buffer; source.loop = true;
  filter.type = 'lowpass'; filter.frequency.value = 360;
  gain.gain.value = 0.075;
  source.connect(filter); filter.connect(gain); gain.connect(ctx.destination);
  source.start();
  ambience = { source, gain, filter };
}
export function stopNightAmbience() {
  if (!ambience) return;
  const active = ambience; ambience = null;
  try { active.gain.gain.setTargetAtTime(0.0001, active.source.context.currentTime, 0.18); active.source.stop(active.source.context.currentTime + 0.7); } catch { /* already stopped */ }
}
export function playHauntedSound(name: 'role'|'morning'|'death'|'save'|'vote'|'eject'|'win'|'lose') {
  if (!getSoundEnabled()) return;
  if (name === 'role') { tone(392, .12); tone(587, .15, 'triangle', .12); tone(784, .22, 'sine', .25); }
  if (name === 'morning') { tone(523, .18); tone(659, .18, 'sine', .13); tone(784, .26, 'sine', .26); }
  if (name === 'death') { tone(180, .5, 'sawtooth', 0, .09); tone(82, .6, 'sine', .08, .07); }
  if (name === 'save') { tone(660, .14); tone(880, .2, 'sine', .12); tone(1174, .24, 'sine', .24); }
  if (name === 'vote') tone(740, .07, 'square', 0, .025);
  if (name === 'eject') { tone(330, .16, 'sawtooth', 0, .05); tone(120, .28, 'sawtooth', .12, .04); }
  if (name === 'win') { tone(523, .16); tone(659, .16, 'sine', .14); tone(784, .16, 'sine', .28); tone(1047, .32, 'sine', .42); }
  if (name === 'lose') { tone(392, .22, 'triangle'); tone(294, .24, 'triangle', .2); tone(196, .4, 'sine', .42); }
}
