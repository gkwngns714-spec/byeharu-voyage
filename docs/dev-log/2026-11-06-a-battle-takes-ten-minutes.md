# 0323: a battle takes ten minutes (W10, owner row 286, dark, probe only)

**What it does.** A fight can now be a row with a clock. `public.battle_open` opens one, `public.tick_battles` closes it when its time comes. A fleet at sea stands still for the whole battle and sails on from the same point, ten minutes later than she would have. A fleet in port or at anchor reads `IN_BATTLE`. Nothing lets a player attack: `battle_open` is no client door, it answers kind `PROBE` only, and `attack_enabled` is false. A human defender is refused.

## The hold

The design's plain BATTLE row cannot work. `voyage_events`' key is (voyage_id, day_index) and every settled day has a row, and a delay counts whole from the next day on, so a storm's point jumps back. So:

- A hold's row is at `voyage.hold_floor()` + n (1,000,001 up), above any real day. The highest day on prod is 58. Payload: `{delay_hours, from_day, held_from, held_until}`.
- `voyage.delay_before_day` counts it from `from_day`, the day she was on. That day's end, each later day and the arrival move by exactly the hold. `voyage.recompute_eta` sums every row and needs no hunk.
- `voyage.progress_nm` gives back `voyage.hold_unserved`, the part of the hold not yet passed, so the point stands still. It reads the row's two instants and no knob.
- `voyage.report_line` prints `from_day`.
- `voyage.settle` runs before the hold, so no day boundary falls inside it. **`voyage.settle` is not touched.**
- A sailing fleet stays `SAILING` (`voyage.assert_sailing_invariant`); `fleets.busy_until` is her clock.

## The hand-off's notes, checked

| Note | Found |
|---|---|
| `cmd.divert` refuses while `busy_until` is set | **False.** It never read it. Hunked: `E_FLEET_BUSY`. Without it a turn cuts a held voyage in two |
| Job `0-6,8-33,41-59 * * * *` | **Not used.** No reason for it anywhere in the repo, and a battle could wait 8 minutes past its 10. It is `* * * * *`, like every minute job here |
| `seaRoster` and `drift.ts` need a held ship to stand still | **True, and more.** A roster delta never re-served a voyage whose eta moved. `world.sea_roster` now serves `holds` and re-serves a fleet with a `busy_until` |
| `battles`, `battle_sides` as sketched | Two columns dropped: a side's fleet was read two ways, and `seed` is the battle's id |
| 0323 shares no body with 0321 or 0322 | **True.** 0321: `earned_caps`, `house_ship_max`, `cmd.enqueue`, `tow_for`, `client_rpc_entry_points`, `world.fleets`. 0322: `voyage.settle`, `npc_tend_route`, `cargo_ship_step`, `voyage.forced_home`, `tow_for`. Applied after both, all green |

## Bodies re-cut (hunks, each once and reversing)

`voyage.delay_before_day`, `voyage.progress_nm` (2), `voyage.report_line`, `voyage.fight` (the side cut to `voyage.fleet_hulls`), `voyage.fight_resolve` (2, the round's words cut to `voyage.fight_round_line`), `cmd.divert`, `world.voyage_view` (2), `world.sea_roster` (2). Proof 28 holds the old fight body whole, so it now also proves both fight cuts word for word.

## Decided by default

- At time_compression 960 a 10-minute hold is 160 sim-hours, about 7 voyage days. As with a storm those days stack at her arrival: stores drunk, wages owed, a hazard rolled on each.
- A fair wind may make up a hold's hours, as it makes up a storm's. "Arrival moves by the delay" is exact until then.
- The battle's line in a voyage's report stands last, after the arrival days: re-sorting needs a hunk in `voyage.settle`, which W6 cuts. It reads its true day.
- No `attacker_fleet`, `defender_fleet` or `seed` on `public.battles`.
- A probe writes hull on both sides, nothing else: no crew, gold, goods or regard. That is W11's table (section 4.3). The report promises no loot.
- The report goes to a human attacker only. A human defender is refused here.
- An `IN_BATTLE` fleet whose flagship is at 0 comes out `UNABLE_TO_SAIL`, as the arrival arm says. That line now stands in three bodies; a leaf belongs in the next slice that may cut `voyage.settle`.
- `standing_route_state` reads `IN_BATTLE` as blocked. Only a merchant at anchor in a probe could read it, and nothing opens a probe on prod.
- `tick_battles` lets a battle that raises fail the run, loudly. A hold ends by its own clock, so nothing at sea waits on it. A fleet `IN_BATTLE` does wait.

## Load (docs/OPS_HEALTH.md section 2: a new cron expression is a load change)

New minute job `byeharu-voyage:battles`, `* * * * *`: one read of a partial index, no write while no battle is due.

Dark cost, PGlite, one voyage of 9 settled days, median of 5:

| | Before | After |
|---|---|---|
| `voyage.delay_before_day` × 5,000 | 56 ms | 79 ms |
| `voyage.progress_nm` × 1,000 | 165 ms | 238 ms |
| A whole voyage settled day by day, median of 25 | 23.3 ms | 22.9 ms |

The first two are the one extra index probe, on wasm. The third is what the arrivals job actually does: no measurable change. Not measured on a populated world.

## Proof

- `scripts/db/proofs/31_battles.sql`, 12 markers.
- `scripts/ops/harness/battles/proof-0323.mjs`: red on the world without the file, 28 mutations red for the intended reason, the real file green, also after 0321 and 0322 (`--first`). Local, cached world, nothing from zero. Harness runs take about 10 s.
- `tests/battle.hold.spec.ts`: the client's half (roster, drift, card clock, History line), pure Node.
- `scripts/ops/harness/battles/before.sql`: read-only on prod. Run 2026-11-06 at head 0320: the eight bodies below, no hold row, highest day 58, no key of 0323, no sailing fleet with a `busy_until`, 906 fleets.

| Body | md5 on prod and in the cached world |
|---|---|
| `cmd.divert` | `f0d304a51023d708bd1b1f41b7aa0ec2` |
| `voyage.delay_before_day` | `980daf123d18c899512ad74b48db17c1` |
| `voyage.fight_resolve` | `507ab0d4a501a73f80d6e1cf380f82a1` |
| `voyage.fight` | `e9d66e50dabb52591827f55af706de77` |
| `voyage.progress_nm` | `38aee97f29ea70c0c71a786ac0b7d968` |
| `voyage.report_line` | `fd4f301b3d3f2d8f9339575d70c76d6f` |
| `world.sea_roster` | `61965b4d6971331c4701fa3282bda314` |
| `world.voyage_view` | `63fd8c2f6a84290d7af578858f651530` |

## Not verified

- A real ten-minute battle by the real clock, or the real job firing: the proof hands every call its instant.
- The self-assert's run time on prod, and the `fleets` re-check under load (906 rows, one `ALTER TABLE`, lock_timeout 5 s).
- Parity on a populated world: CI's and the local world hold few voyages (dark-parity marker on 2 locally). Prod cannot run a volatile probe.
- The card clock in a browser: the words and the arithmetic are held by a pure spec, no screen was opened. No server can reach it while dark.
- A held NPC's lap and route under `npc_tend_route`, past what a held voyage's eta does.

## Row text for the coordinator

- **Owner row 286:** W10 built, dark, probe only, PR open, not deployed: timed battles exist on the server, a ship stands still for the clock and sails on. Regional stations and WANTED stay open (W12, W14).
- **Queue line:** 0323 a battle takes ten minutes (W10, row 286): dark, probe only, PR open. Deploy after 0321 and 0322, in order, one at a time; run `scripts/ops/harness/battles/before.sql` first, then `health.sh`. After deploy: `attack_enabled` false, 0 rows in `battles`, job `byeharu-voyage:battles` active.
