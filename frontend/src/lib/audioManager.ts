import { getSoundEnabled } from './audio';

export type HauntedSound = 'night' | 'morning' | 'death' | 'save' | 'vote' | 'eject' | 'win' | 'lose' | 'role';
type SoundConfig = { file: string; volume: number; loop?: boolean };
const SOUND_CONFIG: Record<HauntedSound, SoundConfig> = {
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
  private muted = !getSoundEnabled();
  private context: AudioContext | null = null;

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
            const done = () => { player.removeEventListener('canplaythrough', done); player.removeEventListener('error', done); resolve(); };
            player.addEventListener('canplaythrough', done, { once: true });
            player.addEventListener('error', done, { once: true });
          });
        }
      } catch { /* fallback is generated locally if an optional MP3 is absent */ }
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
    const player = this.getPlayer(name);
    if (!player) { this.playFallback(name); return; }
    const target = Math.max(0, Math.min(1, volume ?? SOUND_CONFIG[name].volume));
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
    }).catch(() => this.playFallback(name));
  }

  stop(name?: HauntedSound) {
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
  }

  setMuted(muted: boolean) {
    this.muted = muted;
    this.players.forEach(player => {
      if (muted) { player.pause(); player.currentTime = 0; }
    });
  }

  private playFallback(name: HauntedSound) {
    if (this.muted || typeof window === 'undefined') return;
    const Ctor = window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctor) return;
    this.context ||= new Ctor();
    const ctx = this.context;
    if (ctx.state === 'suspended') void ctx.resume().catch(() => undefined);
    const notes: Record<HauntedSound, number[]> = {
      night: [110, 82], morning: [523, 659, 784], death: [180, 82], save: [660, 880, 1174],
      vote: [740], eject: [330, 120], win: [523, 659, 784, 1047], lose: [392, 294, 196], role: [392, 587, 784]
    };
    const gain = ctx.createGain();
    gain.gain.value = name === 'night' || name === 'morning' ? 0.045 : 0.07;
    gain.connect(ctx.destination);
    const oscillators = notes[name].map((frequency, index) => {
      const oscillator = ctx.createOscillator();
      oscillator.type = name === 'death' || name === 'eject' ? 'sawtooth' : 'sine';
      oscillator.frequency.value = frequency;
      oscillator.connect(gain);
      oscillator.start(ctx.currentTime + index * 0.12);
      oscillator.stop(ctx.currentTime + index * 0.12 + (name === 'night' ? 0.8 : 0.22));
      return oscillator;
    });
    window.setTimeout(() => { gain.disconnect(); oscillators.forEach(oscillator => oscillator.disconnect()); }, 1600);
  }
}

export const audioManager = new AudioManager();
export const hauntedSoundFiles = Object.entries(SOUND_CONFIG).map(([name, config]) => ({ name: name as HauntedSound, url: config.file }));
