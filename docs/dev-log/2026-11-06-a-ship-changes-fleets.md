# 2026-11-06 - A ship changes fleets (migration 0321, slice W4, DARK)

Branch `a-ship-changes-fleets` · migration `supabase/migrations/20260818000321_a_ship_changes_fleets.sql` · proof `scripts/db/proofs/29_fleet_room.sql` · seam `tests/rpc.fleetroom.spec.ts`, `tests/fleets.move.spec.ts` · mutation harness `scripts/ops/harness/fleet-room/proof-0321.mjs` · prod check `scripts/ops/harness/fleet-room/before.sql`.

## The order
Owner row 180: *"Fleet, I want to create multiple fleet... assign multiple ships (total of 7)"*. Slice W4 of `docs/WORLD_POWERS.md`, which is F1 + F2 of `docs/FLEETS_AND_SLOTS.md`. It was picked over W6 because it needs no owner switch and nothing undeployed, and W11 needs it. No attack of any kind is in it: no-PvP stands.

## What is built, all dark (`fleet_room_bite` false)
| Part | Where |
|---|---|
| Bought steps (empty until F3) | `public.house_room` |
| The ladders, lit | `public.fleet_room_caps`, read only through `public.earned_caps`; hull cap in `public.house_ship_max` |
| A ship changes fleets | `public.move_ship`, `cmd.move_ship` |
| What the page may offer | `world.ship_moves` |
| An empty fleet | `cmd.enqueue`, `public.tow_for`, `world.fleets` hunks; the client below |
| The page | `src/features/fleets/MoveShip.tsx`: Move under a ship, a pop-up page of fleets and New fleet |
| Words | EN and KO; seven refusal codes, History's line |

New knobs, none on an existing key: `fleet_room_bite`, `fleet_hard_max` 5, `fleet_ship_top` 7, `fleet_room_levels` [3, 6], `fleet_room_prices`, `ship_room_prices` (the two prices stand unread until F3).

## Where the build differs from the design
- **`fleet_ship_max` stays 8.** The design moves it to 7 in F1, which would change every merchant's cap on deploy and is a knob write. Lit, `fleet_ship_top` 7 does that job.
- **Moving a ship is dark too.** The design left F2 open once F1 landed. This brief asked for dark, and one switch lights both, so the door can never run with the wrong caps.
- **Officers stay with the fleet is stale.** There are no fleet officers now; a captain's seat is per ship (`public.captain_seats`) and goes with her.
- **The client door is in this slice,** though the design files it under F5. Without it the new codes have no words, an empty fleet has no page, and lighting would give players nothing to press. The rest of F5 (fleet line, seven tiles, unlock rows, before and after) is not here.

## The empty fleet: the seam the design did not see
Design Q9 keeps a fleet whose last ship left. Three things it did not say, each found by reading or running:
1. **A DOCKED empty fleet is a free permanent presence.** Every presence test (donate, invest, forge, hire, the hall's `you.docked`, the quay) reads `status = 'DOCKED'`. The fleet stays in port with no ship there, against the NO-HOME law. So she lies **`UNABLE_TO_SAIL`**: `cmd.advance` runs nothing, `lap_starts_due` starts nothing, and `public.standing_route_state` already answers `blocked`, the design's word, with no hunk.
2. **A tow would have made her DOCKED again,** at a yard, for a fee. `public.tow_for` refuses `E_FLEET_EMPTY`. The client's tow note ignores her.
3. **`voyage.fleet_speed_at` raises `E_NO_SHIPS`.** Proof 29 hit this on its first full run. `world.fleets` asks it for every fleet, so one empty fleet would have failed the player's whole list and locked her out of the game. `world.fleets` now answers 0 for her. `tests/rpc.fleetroom.spec.ts` reads the whole list with an empty fleet in it. `world.good_board` raises the same code, so Command does not offer an empty fleet, and `E_NO_SHIPS` has words.

An order would wait on her and block the next ship, so `cmd.enqueue` refuses `E_FLEET_EMPTY`. The joining ship writes the fleet row first, so the `fleets_fill_market_requests` trigger on DOCKED sees no cargo and does not sell a moved ship's goods.

## Decided by default (the owner may reverse)
- One switch for the ladders and the door.
- A fleet's port time (`ready_at`) counts as busy, on both fleets. Otherwise a ship could skip her port time by moving to a rested fleet.
- A failed order standing in a queue is a record, not a busy fleet (0186).
- A flagship's heir: tier, then hold, then name.
- Levels and bought steps add up for fleets too: 2 + rungs reached + bought, at most 5.
- Lit, a merchant keeps today's hull cap; her per-fleet cap meets 7. The design's product would have raised her hulls from 8 to 14 and changed merchant spending.
- Wages owed stay on the fleet that owes them.

## What the owner should know before lighting (not now)
- Lit, a human's hull cap is fleets x ships per fleet. A new company is 2 x 2 = 4, which is less than today's 8 + Command. Nobody on prod holds more than 2 ships in a human fleet per the design's read of 10-25, but this must be re-read per company before F6: a company above its cap meets `E_SHIP_MAX` on any move, because the trigger checks it first.
- `house_room` stays empty until F3 is built, so lit without F3 the only ladders are levels.
- An empty fleet cannot be renamed or removed (Q10 stands), and no door renames any fleet today.
- Turning the switch off leaves any empty fleet empty, because the door that would refill her is shut.

## Measured
- Local, cached world, none from zero: the file applies, 7 hunks once each and reversing, self-assert 55-78 ms on the small world. It reads the catalog and config only.
- Proof 29: all 9 markers. 19 of 19 mutations red for the intended reason.
- Deploy order: 0318, 0319, 0320 from their branches, then 0321, then proof 29: green, self-assert 78 ms.
- Specs: `rpc.fleetroom`, `fleets.move` (a served build, headless, 390 wide) and `duplication`: 15 of 15.
- PROD CHECK at head 0318: all 7 pre-images occur exactly once; no room key, no `house_room`, no `move_ship`; no empty fleet; most ships in a fleet 3; `fleet_ship_max` 8.

## PROD CHECKS (read-only, `scripts/ops/harness/fleet-room/before.sql`, one SELECT, stable functions only)
**Run it again before deploying, at head 0320.** After the deploy, also read-only: `fleet_room_bite` false; `house_room` 0 rows. No after-check window is owed: nothing changes for anyone while dark.

## Rollback
`fleet_room_bite` stays false. To remove: a new forward migration swaps the file's old and new hunks, then drops what it created.

## Not verified
- Nothing has run on prod.
- Two real clients: PGlite has one connection, so the lock order and the `E_STALE` path are reasoned, not raced.
- A captain's seat moving with her ship: it is keyed by ship, no proof seats a captain.
- `world.fleets`' other figures on a real prod company with an empty fleet; only the built world.
- The Move button's look with the room lit, on a wide screen; the spec drives it at 390 wide and reads no picture.
- The 0319 file's `E_NOT_IN_USE` line in `codes.ts` duplicates this branch's: this branch's line stands at the same place on purpose so that the merge conflicts rather than doubling a key. Keep one on rebase.
