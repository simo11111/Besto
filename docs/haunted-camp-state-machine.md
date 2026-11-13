# Haunted Camp — authoritative game flow

This document describes the server-side contract for the social deduction game.

## Room lifecycle
- The client sends a room heartbeat every 10 seconds while the room is active.
- A member is considered disconnected after 60 seconds without a heartbeat.
- A Supabase pg_cron job runs stale-member cleanup every 30 seconds.
- If the room owner disappears, ownership transfers to the most recently active remaining member.
- Deleting the final room member closes the room immediately and ends any active match as abandoned (winner is null).
- A reconnect inside the 60-second grace period keeps the same room and match. After that window, membership is removed and the player is marked as having left.

## Match setup
- Quick mode targets 4 seats.
- Standard mode targets up to 10 seats, limited by room capacity.
- NPCs fill empty seats.
- Both modes assign one Haunter (المسكون), one Faqih (الفقيه), and the remaining players as villagers (المواطنين).

## Night → morning
1. A new round starts at night with a 40-second Haunter selection window.
2. The Haunter chooses one living player. The server then opens a fresh 30-second Faqih protection window in both game modes.
3. NPC actions are delayed and serialized. They cannot submit a kill or vote after the relevant phase deadline.
4. Night resolution applies protection: if the Faqih protected the selected target, nobody dies; otherwise the target is eliminated.
5. If the win condition is already met, the match ends. Otherwise the game enters a 15-second morning announcement phase.

## Day → vote
1. At dawn, discussion opens for 2 minutes. Chat and voice are available to eligible living players.
2. At the end of discussion, voting opens for 30 seconds.
3. Individual vote counts remain private until resolution.
4. If the first vote is tied, a second 30-second vote is opened for tied candidates only.
5. If the second vote is also tied, nobody is ejected and the next night begins.

## Win conditions
- Villagers win immediately when the Haunter is ejected.
- The Haunter wins when one or fewer non-Haunter players remain alive.
- Otherwise, the next night begins and the cycle repeats.

## Access and concurrency invariants
- Night chat and microphone are locked; they reopen at dawn.
- Eliminated players can spectate but cannot vote or send messages.
- Game actions and phase transitions require current room membership and an active player row (left_at is null).
- Phase transitions are serialized by locking the game row, so multiple connected clients cannot resolve the same phase twice.
- The server remains authoritative for deadlines, roles, vote privacy, and win conditions.
