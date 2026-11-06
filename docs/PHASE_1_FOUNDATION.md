# MIMOX — Phase 1 Foundation

## Included

- Six standalone, editable SVG mascot expressions: idle, happy, win, sad, think and cheer.
- Replaced legacy M/crown marks in the PWA icon, login artwork, hero artwork and app brand marks.
- Added a mascot wordmark SVG.
- Added calm dark/light CSS design tokens and connected Tailwind colors to the tokens.
- Added reduced-motion-aware mascot animation.
- Extracted the game catalog into a typed registry and moved the reusable game card and XP progression calculations into feature modules.
- Split the login, signup, password-recovery and Supabase setup screens into `features/auth/AuthScreens.tsx`.
- Moved shared UI primitives into `features/shared/ui.tsx`, shared application types into `features/shared/types.ts`, and localized error mapping into `lib/errors.ts`.
- Extracted friendship, direct-message and notification reads into `features/social/api.ts`; `App.tsx` now delegates those queries to the social feature module.
- Extracted lobby and room snapshot queries into `features/rooms/api.ts`, keeping Supabase data access out of the main UI orchestrator.
- Added Vitest and focused unit tests for XP progression, the party-game registry and localized error handling; CI now runs tests before the production build.
- Added migration 020 to make friendships, direct messages and notifications reproducible, with RLS and column-level grants that preserve current app operations.
- Added migration 021 to fix Ten Seconds multiple-choice scoring.
- Added migration 022 to version the social and quick-match RPCs already used by the frontend (`send_friend_request`, `accept_friend_request`, `remove_friend`, `quick_match_room`), with explicit authentication checks and grants.
- Added migrations 023/024 to deduplicate equivalent friendship RLS policies, use scalar-subquery `auth.uid()` predicates, and remove the redundant notifications index.
- Replaced the live quiz rows' accepted answer letters (A/B/C/D) with the actual option text submitted by the UI.
- Replaced the real Supabase URL/key in .env.example with placeholders.

## Database changes applied

Migrations 020–024 were applied to the connected Supabase project on 2026-11-06. Migrations 020/021 were also registered in the migration history after confirming their schema changes were already present. Verification confirmed:
- Quiz rows 58–65 now store the correct answer text.
- finish_party_game contains the revised Ten Seconds score multiplier.
- Friendship, direct-message and notification policies exist with the intended table-specific access.
- The duplicate friendship SELECT policy and duplicate notifications inbox index were removed; the Supabase performance advisor no longer reports the social-policy init-plan or duplicate-index findings.

## Local verification

From the repository root:

```bash
npm install
npm test --workspace frontend
npm run build:frontend
```

CI runs the frontend unit tests before the production build. Cloudflare Pages previews are built from `mimox-phase1-foundation`; production remains on `main` until review and two-account validation.

## Test checklist

1. Sign in with two accounts.
2. Send a friend request, accept it from the recipient account, then exchange a direct message.
3. Send a room invitation and verify the notification appears only for the intended recipient.
4. Start Ten Seconds with at least two players.
5. Answer one multiple-choice prompt using the displayed option text; verify the correct answer receives 15 points.
6. Answer a “name three” prompt with comma-separated answers; verify each valid unique answer adds 15 points, up to three.
7. Wait for the server deadline and verify the host closes the round and the result is persisted.
8. Check PWA icon, login mascot, app header mascot and profile frame selector on a phone-sized viewport.

## Remaining Phase 1 work

- `App.tsx` is still the application orchestrator and needs further decomposition into dedicated rooms, games, shop and profile screens; routing is not yet introduced.
- Full invitation accept/decline/expiry state machine.
- Four-in-a-Row and Moroccan Dama online engines.
- Removal of the local practice mode and RPS code.
- Rematch, MMR, reconnect, spectators, admin, season pass and the new party games.
- Automated Playwright two-account and SQL integration suites; current Vitest coverage is limited to the registry and XP progression helpers.

These are intentionally deferred to the next phases; the current branch does not claim those systems are complete.
