import { getSoundEnabled } from './audio';

export type HauntedSound = 'camp' | 'night' | 'morning' | 'death' | 'save' | 'vote' | 'eject' | 'win' | 'lose' | 'role';
type SoundConfig = { file: string; volume: number; loop?: boolean };
type AmbientVoice = { oscillators: OscillatorNode[]; gain: GainNode; filter: BiquadFilterNode };

const SOUND_CONFIG: Record<HauntedSound, SoundConfig> = {
  camp: { file: '/sounds/camp-theme.mp3', volume: 0.18, loop: true },
  night: { file: '/sounds/night-ambience.mp3', volume: 0.3, loop: true },
  morning: { file: '/sounds/morning-birds.mp3', volume: 0.3, loop: true },
  death: { file: '/sounds/death-sting.mp3', volume: 0.7 },
  save: { file: '/sounds/save-chime.mp3', volume: 0.7 },
  vote: { file: '/sounds/vote-click.mp3', volume: 0.7 },
  eject: { file: '/sounds/eject-whoosh.mp3', volume: 0.7 },
  win: { file: '/sounds/win-fanfare.mp3', volume: 0.7 },
  lose: { file: '/sounds/lose-drone.mp3', volume: 0.7 },
  role: { file: '/sounds/role-reveal.mp3', volume: 0.7 }
};

class AudioManager {
  private players = new Map<HauntedSound, HTMLAudioElement>();
  private ambient = new Map<HauntedSound, AmbientVoice>();
  private muted = !getSoundEnabled();
  private context: AudioContext | null = null;
  private discussionFire: { source: AudioBufferSourceNode; filter: BiquadFilterNode; gain: GainNode } | null = null;
  private campScore: { source: AudioBufferSourceNode; filter: BiquadFilterNode; gain: GainNode } | null = null;

  private getContext() {
    if (typeof window === 'undefined') return null;
    const Ctor = window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctor) return null;
    this.context ||= new Ctor();
    if (this.context.state === 'suspended') void this.context.resume().catch(() => undefined);
    return this.context;
  }

  private getPlayer(name: HauntedSound) {
    let player = this.players.get(name);
    if (!player && typeof Audio !== 'undefined') {
      const config = SOUND_CONFIG[name];
      player = new Audio(config.file);
      player.preload = 'auto';
      player.loop = Boolean(config.loop);
      player.volume = config.volume;
      this.players.set(name, player);
    }
    return player ?? null;
  }

  async preload(names: HauntedSound[] = Object.keys(SOUND_CONFIG) as HauntedSound[]) {
    await Promise.all(names.map(async name => {
      const player = this.getPlayer(name);
      if (!player) return;
      try {
        player.load();
        if (player.readyState < HTMLMediaElement.HAVE_FUTURE_DATA) {
          await new Promise<void>(resolve => {
            const done = () => {
              player.removeEventListener('canplaythrough', done);
              player.removeEventListener('error', done);
              resolve();
            };
            player.addEventListener('canplaythrough', done, { once: true });
            player.addEventListener('error', done, { once: true });
          });
        }
      } catch { /* Optional licensed MP3s may be absent; synthesized audio remains available. */ }
    }));
  }

  play(name: HauntedSound, volume?: number) {
    if (this.muted || !getSoundEnabled()) return;
    const config = SOUND_CONFIG[name];
    const player = this.getPlayer(name);
    if (player) {
      player.loop = Boolean(config.loop);
      player.volume = Math.max(0, Math.min(1, volume ?? config.volume));
      if (!config.loop) player.currentTime = 0;
      void player.play().catch(() => this.playFallback(name));
      return;
    }
    this.playFallback(name);
  }

  fadeIn(name: HauntedSound, volume?: number) {
    if (this.muted || !getSoundEnabled()) return;
    const target = Math.max(0, Math.min(1, volume ?? SOUND_CONFIG[name].volume));
    const player = this.getPlayer(name);
    if (!player) { this.startAmbientFallback(name, target); return; }
    player.loop = true;
    player.volume = 0;
    void player.play().then(() => {
      const started = performance.now();
      const step = (now: number) => {
        if (this.muted || player.paused) return;
        const progress = Math.min(1, (now - started) / 1400);
        player.volume = target * progress;
        if (progress < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    }).catch(() => this.startAmbientFallback(name, target));
  }

  stop(name?: HauntedSound) {
    if (!name || name === 'camp') this.stopCampScore();
    const entries = name ? [[name, this.players.get(name)] as const] : [...this.players.entries()];
    entries.forEach(([key, player]) => {
      if (!player) return;
      const start = player.volume;
      const started = performance.now();
      const fade = (now: number) => {
        const progress = Math.min(1, (now - started) / 450);
        player.volume = start * (1 - progress);
        if (progress < 1) requestAnimationFrame(fade);
        else { player.pause(); player.currentTime = 0; player.volume = SOUND_CONFIG[key].volume; }
      };
      requestAnimationFrame(fade);
    });
    const ambientEntries = name ? [[name, this.ambient.get(name)] as const] : [...this.ambient.entries()];
    ambientEntries.forEach(([key, voice]) => {
      if (!voice) return;
      const ctx = this.context;
      if (!ctx) return;
      voice.gain.gain.cancelScheduledValues(ctx.currentTime);
      voice.gain.gain.setTargetAtTime(0.0001, ctx.currentTime, 0.16);
      window.setTimeout(() => {
        voice.oscillators.forEach(oscillator => { try { oscillator.stop(); oscillator.disconnect(); } catch { /* already stopped */ } });
        voice.filter.disconnect();
        voice.gain.disconnect();
        this.ambient.delete(key);
      }, 750);
    });
  }

  startDiscussionFire() {
    if (this.muted || !getSoundEnabled() || this.discussionFire) return;
    const ctx = this.getContext();
    if (!ctx) return;
    const length = Math.max(1, Math.floor(ctx.sampleRate * 2.4));
    const buffer = ctx.createBuffer(1, length, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    let brown = 0;
    for (let i = 0; i < length; i++) {
      brown = (brown + 0.018 * (Math.random() * 2 - 1)) / 1.018;
      data[i] = brown * 3.2;
    }
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.loop = true;
    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 1450;
    filter.Q.value = 0.55;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, ctx.currentTime);
    gain.gain.setTargetAtTime(0.012, ctx.currentTime, 1.8);
    source.connect(filter);
    filter.connect(gain);
    gain.connect(ctx.destination);
    source.start();
    this.discussionFire = { source, filter, gain };
  }

  stopDiscussionFire() {
    const fire = this.discussionFire;
    if (!fire) return;
    this.discussionFire = null;
    const ctx = this.context;
    if (ctx) {
      fire.gain.gain.cancelScheduledValues(ctx.currentTime);
      fire.gain.gain.setTargetAtTime(0.0001, ctx.currentTime, 0.18);
    }
    window.setTimeout(() => {
      try { fire.source.stop(); } catch { /* already stopped */ }
      fire.source.disconnect();
      fire.filter.disconnect();
      fire.gain.disconnect();
    }, 900);
  }

  setMuted(muted: boolean) {
    this.muted = muted;
    if (muted) {
      this.players.forEach(player => { player.pause(); player.currentTime = 0; });
      this.stop();
      this.stopDiscussionFire();
    }
  }

  private startAmbientFallback(name: HauntedSound, volume: number) {
    if (name === 'camp') { this.startCampScore(volume); return; }
    if (name !== 'night' && name !== 'morning') { this.playFallback(name); return; }
    const ctx = this.getContext();
    if (!ctx || this.ambient.has(name)) return;
    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = name === 'night' ? 520 : name === 'camp' ? 760 : 1800;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, ctx.currentTime);
    gain.gain.setTargetAtTime(Math.max(0.006, volume * (name === 'camp' ? 0.16 : 0.11)), ctx.currentTime, 1.4);
    filter.connect(gain);
    gain.connect(ctx.destination);
    const frequencies = name === 'night' ? [55, 82.41, 110] : name === 'camp' ? [65.41, 98, 130.81, 164.81, 196] : [261.63, 392, 523.25];
    const oscillators = frequencies.map((frequency, index) => {
      const oscillator = ctx.createOscillator();
      oscillator.type = name === 'night' ? (index === 0 ? 'triangle' : 'sine') : name === 'camp' && index === 0 ? 'triangle' : 'sine';
      oscillator.frequency.value = frequency;
      oscillator.detune.value = index * (name === 'night' ? 4 : name === 'camp' ? 2 : -3);
      oscillator.connect(filter);
      oscillator.start();
      return oscillator;
    });
    this.ambient.set(name, { oscillators, gain, filter });
  }

  private startCampScore(volume: number) {
    if (this.muted || this.campScore) return;
    const ctx = this.getContext();
    if (!ctx) return;

    // A 12-second original ambient loop: low D-minor pads with sparse,
    // soft plucked notes. One looping buffer keeps CPU use low on phones.
    const sampleRate = 22050;
    const seconds = 12;
    const frames = sampleRate * seconds;
    const buffer = ctx.createBuffer(1, frames, sampleRate);
    const data = buffer.getChannelData(0);

    const addTone = (frequency: number, start: number, duration: number, amplitude: number, kind: 'pad' | 'pluck') => {
      const first = Math.max(0, Math.floor(start * sampleRate));
      const last = Math.min(frames, Math.floor((start + duration) * sampleRate));
      const phaseStep = (Math.PI * 2 * frequency) / sampleRate;
      for (let i = first; i < last; i++) {
        const t = i / sampleRate - start;
        const progress = t / duration;
        const attack = kind === 'pad' ? Math.min(1, t / 0.55) : Math.min(1, t / 0.012);
        const envelope = kind === 'pad'
          ? attack * Math.min(1, (1 - progress) / 0.24) * (0.84 + 0.16 * Math.sin(t * 1.1))
          : attack * Math.pow(1 - progress, 2.25);
        const phase = phaseStep * (i - first);
        const tone = kind === 'pad'
          ? Math.sin(phase) + 0.18 * Math.sin(phase * 2)
          : Math.sin(phase) + 0.28 * Math.sin(phase * 2.01) + 0.08 * Math.sin(phase * 3.02);
        data[i] += tone * envelope * amplitude;
      }
    };

    // Soft continuous low bed.
    addTone(73.42, 0, seconds, 0.075, 'pad');
    addTone(110.00, 0, seconds, 0.038, 'pad');

    const chords = [
      { start: 0, notes: [146.83, 174.61, 220.00] },
      { start: 3, notes: [116.54, 146.83, 174.61] },
      { start: 6, notes: [130.81, 164.81, 196.00] },
      { start: 9, notes: [110.00, 130.81, 164.81] },
    ];
    chords.forEach(chord => chord.notes.forEach((note, index) =>
      addTone(note, chord.start, 3.25, index === 0 ? 0.038 : 0.024, 'pad')
    ));

    const melody = [
      [0.55, 293.66], [1.65, 349.23], [2.8, 392.00], [4.15, 349.23],
      [5.3, 293.66], [6.55, 261.63], [7.65, 293.66], [8.85, 349.23],
      [10.1, 392.00], [11.2, 349.23],
    ] as const;
    melody.forEach(([start, note], index) => {
      addTone(note, start, 0.9, 0.028, 'pluck');
      if (index % 3 === 1) addTone(note * 2, start + 0.035, 0.38, 0.008, 'pluck');
    });

    // Tiny edge fades prevent a click where the buffer loops.
    const fadeFrames = Math.floor(sampleRate * 0.08);
    for (let i = 0; i < fadeFrames; i++) {
      const fade = i / fadeFrames;
      data[i] *= fade;
      data[frames - 1 - i] *= fade;
    }

    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.loop = true;
    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 1850;
    filter.Q.value = 0.45;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, ctx.currentTime);
    gain.gain.setTargetAtTime(Math.max(0.012, Math.min(0.055, volume * 0.25)), ctx.currentTime, 1.5);
    source.connect(filter);
    filter.connect(gain);
    gain.connect(ctx.destination);
    source.start();
    this.campScore = { source, filter, gain };
  }

  private stopCampScore() {
    const score = this.campScore;
    if (!score) return;
    this.campScore = null;
    const ctx = this.context;
    if (ctx) {
      score.gain.gain.cancelScheduledValues(ctx.currentTime);
      score.gain.gain.setTargetAtTime(0.0001, ctx.currentTime, 0.22);
    }
    window.setTimeout(() => {
      try { score.source.stop(); } catch { /* already stopped */ }
      score.source.disconnect();
      score.filter.disconnect();
      score.gain.disconnect();
    }, 1100);
  }

  private playFallback(name: HauntedSound) {
    if (this.muted) return;
    const ctx = this.getContext();
    if (!ctx) return;
    const patterns: Record<Exclude<HauntedSound, 'camp' | 'night' | 'morning'>, { notes: number[]; duration: number; wave: OscillatorType; gap: number }> = {
      death: { notes: [196, 146.83, 82.41], duration: 0.48, wave: 'triangle', gap: 0.08 },
      save: { notes: [659.25, 830.61, 987.77], duration: 0.42, wave: 'sine', gap: 0.09 },
      vote: { notes: [740], duration: 0.09, wave: 'triangle', gap: 0 },
      eject: { notes: [330, 220, 110], duration: 0.32, wave: 'sawtooth', gap: 0.07 },
      win: { notes: [523.25, 659.25, 783.99, 1046.5], duration: 0.55, wave: 'sine', gap: 0.12 },
      lose: { notes: [392, 293.66, 196, 146.83], duration: 0.58, wave: 'triangle', gap: 0.16 },
      role: { notes: [392, 587.33, 783.99], duration: 0.34, wave: 'sine', gap: 0.11 }
    };
    if (name === 'camp' || name === 'night' || name === 'morning') { this.startAmbientFallback(name, 0.3); return; }
    const pattern = patterns[name];
    const master = ctx.createGain();
    master.gain.setValueAtTime(0.0001, ctx.currentTime);
    master.connect(ctx.destination);
    pattern.notes.forEach((frequency, index) => {
      const start = ctx.currentTime + index * pattern.gap;
      const oscillator = ctx.createOscillator();
      const envelope = ctx.createGain();
      oscillator.type = pattern.wave;
      oscillator.frequency.setValueAtTime(frequency, start);
      if (name === 'death' || name === 'lose' || name === 'eject') {
        oscillator.frequency.exponentialRampToValueAtTime(Math.max(45, frequency * 0.72), start + pattern.duration);
      }
      envelope.gain.setValueAtTime(0.0001, start);
      envelope.gain.linearRampToValueAtTime(name === 'vote' ? 0.035 : 0.085, start + 0.018);
      envelope.gain.exponentialRampToValueAtTime(0.0001, start + pattern.duration);
      oscillator.connect(envelope);
      envelope.connect(master);
      oscillator.start(start);
      oscillator.stop(start + pattern.duration + 0.025);
      oscillator.addEventListener('ended', () => { oscillator.disconnect(); envelope.disconnect(); }, { once: true });
    });
    window.setTimeout(() => master.disconnect(), 1800);
  }
}

export const audioManager = new AudioManager();
export const hauntedSoundFiles = Object.entries(SOUND_CONFIG).map(([name, config]) => ({ name: name as HauntedSound, url: config.file }));
