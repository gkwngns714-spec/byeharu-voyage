# 0437: a surplus cargo ship comes home now; a cargo ship with nothing on board says "Returning" (owner row 352)

## The owner, 2026-11-15 (after 0430 went live at 08:15 UTC)

- "there are still cargo ships that have 0 gold. if they are returning after they provided transport, instead of 0 gold, say it is returning."
- "you still haven't reduce the numbers right"

## What prod looked like

The lead's read at 08:51 UTC: 377 cargo ships, 107 laid up, 258 at sea, 12 in port; retire_later 175, retire_now 0; 125 "roaming" (sailing, nothing
on board, not bound home), falling slowly.

This slice's read at 09:03 UTC (`scripts/ops/harness/cargo-home/before.sql`, head 0432, gate green, beat 122 ms):

| figure | value |
|---|---|
| rows / laid up / in service | 377 / 114 / 263 |
| the shares (sum) / in service inside the share | 100 / 100 (89 of them at sea) |
| surplus in service (ord over the share) | **163** |
| of them at sea with gold, on a lap | 45 (3.96 M on board) |
| their circuit still to sail | 17 legs median, 35 p90, 37 max; 41,373 nm median, 60,319 max |
| of them sailing home empty | 70 |
| of them sailing empty to another city (legs begun before 0430) | 46 (70 in the whole fleet, every one after a DELIVERED; out 87 min median) |
| docked away / home on a lap / idle at home | 1 / 1 / 0 |
| minutes to arrival, the gold ships | 26 median, 76 p90, 97 max |
| minutes to arrival, the empty ships | 64 median, 194 p90, 383 max |
| a cargo ship's speed | 41.4 nm a real minute (median of the sailing voyages) |
| laid-up rows that never carried a ducat | 93 |
| knobs | cargo_fleet_total 100, convoy_retire_per_run 10, convoys lit, convoy_rich_enabled **true**, convoy_rebase_idle_days 7, game_day_seconds 300 |

## Root cause of the slow cut

1. **A surplus ship with gold on board sails her whole circuit first.** 0430 kept 0326's rule: "a ship at sea, or with funds aboard, takes no
   new load and lays up when she is home and empty", and its homeward hunk turns a ship home only when she is EMPTY. The retire
   (`public.cargo_ships_retire`) takes only a ship docked at home with no lap and nothing on board. A circuit visits every city of the realm,
   so the 45 gold ships still had 17 legs (median) to sail: ~17 hours at 41.4 nm a minute, ~24 hours for the last. That is the slow tail.
2. **An idle surplus ship at home could be sent to a new home first.** `convoy_rich_enabled` is lit on prod, so an idle ship whose home is not
   among her realm's richest harbours is rebased (`public.cargo_rebase`) once she has lain idle 7 voyage-days (35 real minutes). At 0430's
   deploy ~196 surplus ships were idle at home and the retire takes 10 a run, so some of them sailed off empty to a new home before the retire
   reached them (part of the 70 "sailing home").
3. **The 377 rows.** A laid-up ship stays a row: her book (`public.convoy_cargo`, append-only, a foreign key to `cargo_ships` with no
   cascade) and her events name her, and 0326 wakes a laid-up ship by her ord when a share rises. The Stats count (`public.stats_fleets_count`)
   and the Cargo list (`public.stats_fleet_list_rows`) counted every row: "Ships 377".

The roaming itself (cause of the 125) was 0430's: legs begun before 08:15 UTC, each turning home at its next port. It falls as they land.

## What 0437 does

- **A surplus ship comes home now** (`public.cargo_ship_step`, 4 hunks). Over her share, at the next port (after that city's delivery, which
  stands: she gives what the city is short first) she drops the rest of her circuit and sails ONE leg straight home with what is left on board
  (RECALLED; empty, 0430's HOMEWARD). At home the lap closes as before: the rest is RETURNED to the port it was loaded at (her home), so no gold
  is lost or made (`public.tg_convoy_cargo_closes` refuses a return anywhere else). Idle at home she waits for the retire (IDLE) and is never
  sent to a new home first. A ship at sea keeps her leg to its port: there is no course from open water, so the turn is at the next port.
- **The retire is unchanged** (0326): home, docked, no lap, nothing on board, 10 a run, highest ord first; writes `laid_up_at` only.
- **The decommission is the lay-up.** I looked for another path: the only delete of a ship anywhere is `public.cargo_hull`'s refit (it
  replaces a hull); there is no fleet delete. A cargo ship's row cannot go while her append-only book names her, and a delete through `players` (the only
  door: every table hangs off the house) cascades into `ledger` and `events`, which refuse a delete (append-only triggers). Even the 93 laid-up
  rows that never carried a ducat would have to be checked table by table; not done blind on a live world. So a laid-up ship is retired: off the map (0326), takes no step, no load, no row a minute, and now **out of the Stats count**
  (`stats_fleets_count`, `stats_fleet_list_rows`, one hunk each): the Ships and Cargo faces read the ships in service.
- **The word** (`public.cargo_ship_state`, new, stable, server-only): LOADED, RETURNING, HOME, LAID_UP. Served as `state` on the map card
  (`world.cargo_ship_card`; `next` and `stops_left` only while she is loaded inside her share, so a ship going home no longer lists the circuit
  she dropped) and on the Stats page (`world.stats_fleet`, `cargo.state`). The client (`src/live/cargoState.ts`, the one map) prints
  "Returning / 귀환 중", "At home / 모항 정박" or "Laid up / 정박 중" where it printed 0 gold (`CargoSheet`, the Stats fleet page); a loaded ship
  shows her gold as before.

Decided by default: (a) a load taken while she was inside her share and not yet gone sails its first leg as before (its first city was short of
it), then she is recalled; an earlier draft put it back ashore at once, which broke proof 35's lap and threw away a delivery a city needed.
(b) A surplus ship lays up at HOME only, as the brief says: laying up at the first city of her realm would be faster (~1 h) but would move her
home and, with gold on board, could not return it where it was loaded.

## Expected timeline to 100 in service (from the 09:03 read)

- The 70 sailing home: they dock in 64 min (median), 194 (p90), 383 (max), and lay up within a minute of docking.
- The 46 empty on old legs: their port in 38 min (median), then one leg home.
- The 45 with gold: their next port in 26 min (median), 97 at most, then one leg home (before 0437: 17 legs, ~17 h median, ~24 h at most).
- So about half the surplus retires within the first hour, most within ~3 hours, the last when the longest homeward leg ends (~6-7 hours).
  Estimated in service: 263 -> ~180 at +1 h, ~110-120 at +3 h, 100 by ~+7 h (the homeward legs' lengths are not read; the empties' etas stand in). The Stats faces read the in-service count from the next count after the deploy.
- The floor is the sea: a leg already under way is not cut (no course from open water home).

## Load (rows a minute)

No job, table or knob. The lay-ups are one row each, at most 10 a run, ~163 in all over the hours above, then 0. A recalled ship sails one leg
instead of up to 37, and 163 fewer ships in service step, pay upkeep and write voyages: **fewer rows a minute than today**.

## Proofs

- Migration self-assert (CI world: no cargo ship, convoys dark; the probe lights them): 10 hunks once each and reversing; catalog unmoved; probe
  "a PRT ship (ord 2, share 1) at ACC with 5,000: RECALLED home to LIS, HOME (5,000 returned), IDLE at a home that is no origin, laid up; states
  HOME, LOADED, RETURNING, LAID_UP", 147 ms.
- Proof 138 (new) 6/6: CH_INSHARE, CH_RECALL, CH_RETIRE, CH_IDLE, CH_STATE, CH_COUNT. Each fails before 0437.
- Cargo proofs green: 18 (6/6), 19 (9/9), 20 (8/8), 36 (17/17), 131 (5/5); also 30, 32, 34, 35, 116, 128, 130, 132.
- Proof 116 updated: its laid-up cargo ship is no longer counted (0437's rule): fleets v_made - 1, laid_up 0.
- Prod reads before the PR (all read-only, gate green): `before.sql` (the table above), `hunks.sql` (every hunk once on prod's bodies at head
  0432; `cargo_ship_state` absent), `probe-select.sql` (the probe would use PRT, share 9, next ord 51, cities AGA..ISL each with a course home).

## After the deploy

`scripts/ops/harness/cargo-home/after.sql` at +30 and +60 min: `surplus.sea_funds` near 0 by +60 (each recalled at her next port),
`world.surplus` falling, `world.in_service` toward 100, every cargo run `succeeded`. Rollback (owner only, a draft):
`scripts/ops/harness/cargo-home/rollback-0437.sql` (tested locally: reverses every hunk and drops the function; `hunks.sql` then answers ok).
