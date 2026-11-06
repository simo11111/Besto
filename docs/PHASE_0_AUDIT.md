# MIMOX — Phase 0 Engineering Audit

Audit basis: repository main at commit 3dd6e0ed3a961d1ac88e360ca6293c1b888f08b4, plus read-only inspection of the connected Supabase schema and live game prompts on 2026-11-06.

## Findings

1. **Schema drift:** live Supabase contains friendships, direct_messages and notifications, but migrations 001–019 do not define their full schema. Fresh installs are not reproducible.
2. **Ten Seconds correctness bug:** live quiz prompts 58–65 store accepted_answers as A/B/C/D, while the client submits selected option text. Those answers are scored as wrong. A single correct multiple-choice answer currently earns only 5 points.
3. **Frontend monolith:** App.tsx is about 83 KB and contains auth, rooms, voice, games, social, shop and profile.
4. **Mixed game architecture:** five party games use Postgres RPCs, while XO, Connect 4 and Rock/Paper/Scissors are local-only practice code. There is no typed game registry or common lifecycle.
5. **Missing competitive loop:** rematch, Elo/MMR, reconnect recovery and spectators are not implemented as a shared contract.
6. **Weak game feel:** game screens use inconsistent forms/counters, with unclear round phases, limited feedback and weak reveal/results moments.
7. **Social lifecycle gaps:** friend request schema is not versioned in migrations; invitation acceptance/expiry is not a unified realtime lifecycle.
8. **Brand inconsistency:** M/crown marks and neon purple styling do not match the requested friendly Moroccan mascot and calmer palette.
9. **Quality gates:** only a TypeScript/Vite production build is configured; no unit, SQL integration or two-player browser test suite is present.
10. **Configuration hygiene:** .env.example contains the real project URL and publishable key rather than placeholders.

## Decisions

- Preserve existing auth, rooms, voice and party game RPCs; changes remain backward-compatible.
- Ten Seconds supports two explicit challenge types: multiple-choice submits the option text; “name three” submits comma-separated answers.
- Rock/Paper/Scissors is removed from the product roadmap. XO/Four-in-a-Row bots are only fill-ins after real online engines exist.
- All scoring, timers, turn validation and secret roles remain server-authoritative.
- Work on a separate feature branch; do not merge or deploy before build and two-account validation.

## Roadmap

- **MVP improved:** mascot/design tokens, reproducible social schema, fixed Ten Seconds scoring, match arena, invite lifecycle, typed game registry, Four-in-a-Row and Moroccan Dama.
- **Growth:** Memory Duel, Word Duel, Draw & Guess, richer party prompts, ranked queues, rematch, seasons, events and admin content tools.
- **Scale:** reconnect/spectator support, matchmaking/MMR tuning, moderation, analytics, error monitoring, performance budgets and localization.
