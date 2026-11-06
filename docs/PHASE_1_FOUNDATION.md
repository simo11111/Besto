# MIMOX — Phase 1 Foundation

## Included

- Six standalone, editable SVG mascot expressions: idle, happy, win, sad, think and cheer.
- Replaced legacy M/crown marks in the PWA icon, login artwork, hero artwork and app brand marks.
- Added a mascot wordmark SVG.
- Added calm dark/light CSS design tokens and connected Tailwind colors to the tokens.
- Added reduced-motion-aware mascot animation.
- Extracted the game catalog into a typed registry and moved the reusable game card and XP progression calculations into feature modules.
- Added migration 020 to make friendships, direct messages and notifications reproducible, with RLS and column-level grants that preserve current app operations.
- Added migration 021 to fix Ten Seconds multiple-choice scoring.
- Replaced the live quiz rows' accepted answer letters (A/B/C/D) with the actual option text submitted by the UI.
- Replaced the real Supabase URL/key in .env.example with placeholders.

## Database changes applied

Migrations 020 and 021 were executed against the connected Supabase project on 2026-11-06. Verification confirmed:
- Quiz rows 58–65 now store the correct answer text.
- finish_party_game contains the revised Ten Seconds score multiplier.
- Friendship, direct-message and notification policies exist with the intended table-specific access.

## Test checklist

1. Sign in with two accounts.
2. Send a friend request, accept it from the recipient account, then exchange a direct message.
3. Send a room invitation and verify the notification appears only for the intended recipient.
4. Start Ten Seconds with at least two players.
5. Answer one multiple-choice prompt using the displayed option text; verify the correct answer receives 15 points.
6. Answer a “name three” prompt with comma-separated answers; verify each valid unique answer adds 15 points, up to three.
7. Wait for the server deadline and verify the host closes the round and the result is persisted.
8. Check PWA icon, login mascot, app header mascot and profile frame selector on a phone-sized viewport.

## Not included yet

- Full App.tsx decomposition and routing.
- Full invitation accept/decline/expiry state machine.
- Four-in-a-Row and Moroccan Dama online engines.
- Removal of the local practice mode and RPS code.
- Rematch, MMR, reconnect, spectators, admin, season pass and the new party games.
- Automated Vitest/Playwright/SQL integration suites.

These are intentionally deferred to the next phases; the current branch does not claim those systems are complete.
