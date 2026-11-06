# Every NPC ship has an origin (W6, migration 0322, owner row 287, dark)

Owner: *"each npc ships should have city of origin set. Once they are attacked and lost, it may lose some cargo/gold and HP. If everything is destroyed(HP), they should respawn at their origin city, funded by the city to start anew"*.

**State: built, dark, PR open, not deployed.** `npc_refits_enabled` false. Nothing changes for any ship until the owner lights it.

## What it does, lit

- Every merchant and cargo ship has one origin, read by `public.fleet_origin`.
- On a STORM, PIRATES or SHOAL_WATER day, if every hull she has is at 0 and she is an NPC ship, the voyage ends there. Hold lost, insurance paid as today (cause `WRECK`), funds aboard go back to the origin's purse, orders released, she lies `UNABLE_TO_SAIL` at the origin, event `RESPAWNED`.
- Hourly at :18 (`byeharu-voyage:npc-refits`): a city whose surplus covers the cost pays `npc_refit_share` (0.25) of the build cost of her hulls, as `REFIT`, to the nearest yard that is not itself, its own country first. Moved, two rows. Hull whole, crew from the quay above its floor, ready after `npc_refit_minutes` (30).
- A city that cannot pay: she waits and is asked hourly. `REFIT_WAITING` once a real day. No hull is restored unpaid.
- A paid merchant re-joins through `npc_tend_route`. A paid cargo ship closes her lap at home (`HOME`), loads again, and sails after the wait.

## Hot bodies re-cut (7 hunks, each once, each reversing; W10 please read)

`voyage.settle` (1), `public.npc_tend_route` (1), `public.cargo_ship_step` (2), `voyage.forced_home` (2), `public.tow_for` (1). #516 (0321) also hunks `public.tow_for`, on another line: applied in that order, green.

Moved, same statements: `voyage.lose_hold` (from `forced_home`), `public.yards_from` (from `tow_for`), `public.fleet_mend` (from `cargo_ship_step`, twice). `public.refit_yard` and the wreck read them, so there is one copy of each.

Dark cost: one read of the switch on a day that can take a hull (about 185 such days an hour on prod), one on a wrecked merchant's tend, one on each cargo step. The job reads one knob.

## Notes from the hand-off, checked

- `npc_refits_enabled` false, `npc_refit_share` 0.25, `npc_refit_minutes` 30, `ransom_share` 0.08: shipped as noted. **Added:** `npc_refits_per_run` 50.
- `fleet_origin` cargo_ships first: right. Prod: 0 NPC fleets without an origin, 0 houses with a null home, every home a harbour, none ice-closed.
- `refit_yard` from the tow query: right, the query itself was lifted into `public.yards_from`.
- `npc_wreck` on `forced_home`: same order of acts.
- **The notes said a hunk for each of STORM, PIRATES, SHOAL_WATER. One is enough:** one check after the day's row is written.
- `:18` is free: no job fires then.
- WORLD_POWERS section 1 stale: confirmed, `convoys_enabled` true, 50 cargo ships (32 at sea, 18 docked at reading). Row corrected.
- `crown_aid` cannot load a wreck: `cargo_ships_load` takes only a ship `DOCKED` with no open load. Proved with her as the first ship it would take.
- `tg_convoy_cargo_closes`: kept. A wreck's return is at the origin, which is the capital she loaded at. **W7 must keep origin = the port she loaded at, or a wreck raises inside `voyage.settle`.**
- #516 proof number: it took 29, this takes 30.

## Measured on prod (2026-11-06, read only)

- Hazard days in the last hour: STORM 114, PIRATES 50, SHOAL_WATER 21.
- Fleets with every hull at 0 today: 3 merchants (Derrota Cape Town docked at GOA, Derrota Genoa docked at BAR, Rejse Longyearbyen `UNABLE_TO_SAIL` at LNG). **Two wrecks lie `DOCKED` with no hull today; not looked into.** No cargo ship at 0. The job takes all three home on its first lit run.
- **Would their city pay today? 280 of 887 NPC fleets have a home whose surplus is under one refit.** 49 of 164 home cities have no surplus. The median home has 43,384 d.; a `carlat` costs 35,000 d., a `nau` 150,000 d. Those ships would wait, not sail. All refits at once: 51.5 M d. against 23.2 B d. of surplus world-wide, so this is about where the money is, not how much. **Owner should read this before lighting.**
- Wreck rate: **not measured.** Nothing counts hulls reaching 0 at sea today, and `TOWED` events are compacted (0 in 7 days).

## Proof

- `scripts/db/proofs/30_every_npc_ship.sql`: 15 markers, real `voyage.settle`, tend, cargo step and job, economy closed, sea stubbed by name.
- `scripts/ops/harness/npc-origin/proof-0322.mjs`: real file and proof green, 30 mutations each red for its own reason; also green with 0321 applied first. Four mutations first came back wrong: two exposed real gaps in the proof (a queued order; the tow arm lit), now covered.
- Self-assert: catalog and arithmetic only, no game step, 120 ms locally on a world of prod's fleet count. `scripts/ops/harness/npc-origin/before.sql` read on prod at head 0320: every hunk once, nothing of 0322 there.
- Proofs 19 and 23 green locally with the file in. Proof 12 and the rest: CI.

## Decided by default

- Switch `npc_refits_enabled`: the design named none.
- A wreck is **every** hull at 0. A flagship at 0 with a hull left is towed, as today.
- `ransom_share`: knob and reader (`public.ransom_take`), no gold moves, no caller, until W11 / W17.
- No crew for cargo ships until W8.
- A merchant's crew stay aboard a wreck. The refit fills her shortfall from the quay above `npc_crew_pool_floor`, free; what is left she hires herself.
- The cost is the build cost of every hull she has: 44 merchants have 2, 7 have 3.
- A city pays when its surplus is at least the cost, so it can land exactly on its reserve.
- `npc_refits_per_run` 50; only a paid refit counts, so waiting wrecks cannot starve the rest.
- Wrecks found in port, from before the switch: same rule, hold lost, no claim (no voyage).
- Insurance cause `WRECK`.
- Respawning is free and pays no dock fee.
- `REFIT` is filed under Repairs in the Money log. Words: Refit, 재정비.
- `RESPAWNED`, `REFITTED`, `REFIT_WAITING` have no feed words: they land on NPC houses, which no player reads.

## Not verified

- A run under real `pg_cron` on prod: CI's disposable-chain checks the schedule; the job's commits are only run with `p_commit = false` in proof.
- Two wrecks of one city in one run, or lock contention with a sale: not tested. The job takes 2 s of lock wait and warns.
- The wait measured through `port_time_wake`: the proof reads `ready_at` and calls the same `cmd.advance`.
- Cost on prod while lit: dark only.

## Rows for the coordinator (not written here, parallel PRs)

**docs/OWNER_REQUESTS.md row 287:** `PART BUILT - W6 origin, wreck and refit, migration 0322, dark, PR open, not deployed. OPEN: loot and ransom payees W11, W17; W7, W8, W9.`

**docs/WORK_QUEUE.md, one line at the top:** `2026-11-06 **EVERY NPC SHIP HAS AN ORIGIN (W6, owner row 287) - migration 0322, DARK, PR open, NOT deployed, follows 0321:** one origin reader, a wreck (every hull at 0) lies at her origin, her city pays REFIT to a yard, moved, hourly at :18; a city that cannot pay waits. `npc_refits_enabled` false. Read before lighting: 280 of 887 NPC fleets have a home that cannot pay one refit today. Dev-log docs/dev-log/2026-11-06-every-npc-ship-has-an-origin.md.`

## PROD CHECKS

- Before deploy: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/npc-origin/before.sql`. Every `times` 1, `npc_keys`, `refit_word`, `ord_49`, `job` 0, both names null.
- After deploy: `scripts/ops/harness/npc-origin/after.sql`. `refits_on` false, `refit_rows` 0, `respawned` 0, `waits` 0, `job_active` true, `no_origin` 0, `no_refit_cost` 0.
- `bash scripts/ops/health.sh` (a new cron job is a load change, docs/OPS_HEALTH.md section 2; dark it reads one row).
