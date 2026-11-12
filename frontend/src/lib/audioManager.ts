import { getSoundEnabled } from './audio';

type SoundName = 'night' | 'morning' | 'death' | 'save' | 'vote' | 'eject' | 'win' | 'lose' | 'role';
type ActiveSound = { source: AudioBufferSourceNode; gain: GainNode };

class AudioManager {
  private context: AudioContext | null = null;
  private active = new Map<string, ActiveSound>();
  private master: GainNode | null = null;

  private getContext() {
    if (typeof window === 'undefined' || !getSoundEnabled()) return null;
    const Ctor = window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctor) return null;
    this.context ||= new Ctor();
    if (this.context.state === 'suspended') void this.context.resume().catch(() => undefined);
    if (!this.master) {
      this.master = this.context.createGain();
      this.master.gain.value = 1;
      this.master.connect(this.context.destination);
    }
    return this.context;
  }

  async preload(urls: string[]) {
    const ctx = this.getContext();
    if (!ctx) return;
    await Promise.all(urls.map(async url => {
      try {
        const response = await fetch(url);
        if (!response.ok) return;
        await ctx.decodeAudioData(await response.arrayBuffer());
      } catch { /* optional sound asset; synthesized fallback remains available */ }
    }));
  }

  play(name: SoundName, volume = 0.7) {
    const ctx = this.getContext();
    if (!ctx || !this.master) return;
    const notes: Record<SoundName, number[]> = {
      night: [110, 82], morning: [523, 659, 784], death: [180, 82],
      save: [660, 880, 1174], vote: [740], eject: [330, 120],
      win: [523, 659, 784, 1047], lose: [392, 294, 196], role: [392, 587, 784]
    };
    const gain = ctx.createGain();
    gain.gain.value = Math.max(0, Math.min(1, volume));
    gain.connect(this.master);
    const oscillators = notes[name].map((frequency, index) => {
      const oscillator = ctx.createOscillator();
      oscillator.type = name === 'death' || name === 'eject' ? 'sawtooth' : 'sine';
      oscillator.frequency.value = frequency;
      oscillator.connect(gain);
      oscillator.start(ctx.currentTime + index * 0.12);
      oscillator.stop(ctx.currentTime + index * 0.12 + (name === 'night' ? 0.8 : 0.22));
      return oscillator;
    });
    window.setTimeout(() => { gain.disconnect(); oscillators.forEach(o => o.disconnect()); }, 1600);
  }

  fadeIn(name: SoundName, volume = 0.3) { this.play(name, volume); }
  stop(name?: string) {
    if (name) {
      const sound = this.active.get(name);
      if (sound) { sound.gain.gain.setTargetAtTime(0, sound.source.context.currentTime, 0.15); sound.source.stop(sound.source.context.currentTime + 0.6); this.active.delete(name); }
      return;
    }
    this.active.forEach(sound => { sound.gain.gain.setTargetAtTime(0, sound.source.context.currentTime, 0.15); sound.source.stop(sound.source.context.currentTime + 0.6); });
    this.active.clear();
  }
  setMuted(muted: boolean) {
    const ctx = this.getContext();
    if (ctx && this.master) this.master.gain.setTargetAtTime(muted ? 0 : 1, ctx.currentTime, 0.05);
  }
}
export const audioManager = new AudioManager();
