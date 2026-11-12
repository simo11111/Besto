export const hauntedTokens = {
  color: {
    night: '#0a0618', morning: '#1a0f2e', day: '#1e1338',
    violet: '#8b5cf6', violetGlow: '#a78bfa', gold: '#fbbf24',
    haunter: '#ef4444', safe: '#10b981', text: '#f5f3ff', muted: '#a1a1aa'
  },
  radius: { sm: 8, md: 12, lg: 16, pill: 999 },
  spacing: [4, 8, 12, 16, 24, 32, 48, 64] as const,
  volume: { ambient: 0.3, sfx: 0.7, voice: 1 }
} as const;
export type HauntedTokens = typeof hauntedTokens;
