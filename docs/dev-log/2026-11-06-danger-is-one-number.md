# Danger is one number (W15, Z1, migration 0330, no change to play)

Slice W15 of `docs/WORLD_POWERS.md` section 7.7, which is Z1 of `docs/PIRATES_AND_HAVENS.md`.

**State: built, PR open, not deployed.** Nothing to light. No roll, raid, quote or panel changes: this slice is what W17 stands on.

## What it does

- **One number.** `voyage.sea_danger(sea, at)` is `piracy_index × (1 + pressure)`, clamped to 0..1, four places. It is now the only reader of `seas.piracy_index`.
- **Frozen at departure.** `voyage.depart` writes `danger` into each segment beside `sea_id`. The roll, the raid, the quote and the panel read that, through one leaf, `voyage.leg_danger`. Late or on time, she rolls the danger she left into.
- **`public.sea_pressure`** exists, empty, closed. W17 is its first writer. Empty means no pressure, so every figure is `piracy_index` to the digit.
- **`voyage.sea_mix(sea, danger)` supersedes `voyage.sea_mix(sea)`**, which is dropped. Same body, with the figure passed in.
- **`world.sea_danger()`** serves each sea's level and reason. Not open to a client: Z2 opens it with the map.
- Two knobs, neither moving anything today: `sea_pressure_decay` 0.9, `sea_danger_bands` [0.1, 0.25, 0.4, 0.6].

Re-cut by hunks, each once and reversing: `voyage.depart` (1), `voyage.hazard_roll` (1), `voyage.settle` (1, the PIRATES arm), `voyage.risk_quote` (3), `voyage.waters_ahead` (3). `cmd.divert` needs no cut: it keeps sailed segments whole, and the onward water is a new voyage through `voyage.depart`. Proof 38 checks that.

## Proof

- `scripts/db/proofs/38_sea_danger.sql`: 14 markers. All 51 seas against byte copies of the old mix and draw: figure, frozen segment, mix, every day's roll, a real settled raid in each sea, the quote, the panel. Then pressure: formula, frozen against it, late equals on time with the sea moved between each day, a leg with no figure, a real turn, levels, one reader, closed to clients.
- `scripts/ops/harness/sea-danger/proof-0330.mjs`: red first (proof 38 fails with no file), dark parity equal, real file green, 20 mutations each red for its own reason, on the world at 0328.
- **Dark parity:** `dark-scene.sql` sails two voyages with fixed ids on two hulls of the built world through all 51 seas, one on the real mix, one where nearly every day is a raid, through the real settle and fight. 751 lines of quote, panel, every day's kind and payload: equal before and after the file, byte for byte.
- Self-assert: catalog and stable reads, plus one row of the empty table rolled back by a raised error. No game step. About 220 ms locally. It compares every sea's new mix with the old body before dropping it.
- Prod read-only, 2026-11-06, head 0328: `before.sql` found all 9 hunks once. 51 seas. `sea_pressure` absent. `piracy_index` read by `voyage.sea_mix(uuid)` and `voyage.settle` only, no view. 652 SAILING voyages, 11 segments on average, 46 at most.
- `voyage.freeze_danger` on 46 segments: 1.17 ms a call in PGlite, measured locally, not on prod.
- First runs found: `greatest(0, null)` is 0 in Postgres, so a null moment still read pressure, caught by the self-assert. The dark scene differed on its own: a fresh hull rolls its own stats, and the panel reads the clock. It now uses built hulls and departs ahead of the clock. Neither was the file.

## Decided by default

- **The voyages at sea are not written.** A segment frozen before 0330 has no figure, and `voyage.leg_danger` reads it as the sea as authored, which is what she departed into, because no pressure existed. Backfilling would have written 652 live rows under a table lock, and still left the 52,000 arrived voyages and a race with a departure in flight. Consequence: if Z2 re-authors `seas.piracy_index`, a voyage from before 0330 still at sea would read the new figure. None should be: Z2 follows this deploy by more than a voyage. Not checked; a voyage's length has no hard limit.
- **`world.sea_danger()` serves `level` 1 to 5, not a word.** The doc says five words (Calm, Watchful, Dangerous, Severe, Deadly). The game already words these levels in EN and KO in `src/components/ui/dangerTiers.ts` (Home waters, Quiet, Unsettled, Dangerous, Deadly). A second set would be a second vocabulary. Z2 can change the dict.
- **The level rule:** the authored level, moved one step for each band of `sea_danger_bands` the live figure has crossed from the authored figure, held to 1..5. The doc says only "moves when it crosses a band".
- **`world.sea_danger()` stays closed** until Z2, because it has no screen. Opening it needs the registry row and a grant. `reason` is always null: W17 brings causes.
- **`voyage.risk_quote` stays by voyage,** as 0213 built it. The doc's `risk_quote(plan)` has no reader: insurance quotes the voyage after departure.
- **A sea that does not exist has danger 0,** as the PIRATES arm's `coalesce` read it.
- **`p_at` null means the sea as authored.** That keeps `voyage.sea_danger` the only reader, for the legacy leg and the level.
- **`sea_pressure_decay` and `sea_danger_bands` are knobs**, not constants in the body.
- The doc's `raiders` segment key is not frozen here: it needs a pirate ship to name, and that is W17.

## Not verified

- Anything on prod. Nothing here has run there.
- Real-Postgres behaviour until CI's `disposable-chain`. Local runs are PGlite.
- The arrivals beat with the file: the design's bound (avg ≤ 3 s, p95 < 5 s) is read after deploy, not before. Departure cost is timed in PGlite only.
- A rebase on 0329 (W12): if it cuts any of these lines, the file refuses at deploy with "occurs 0 time(s)". `before.sql` must be re-run after 0329 lands.
- Interaction with pressure in live play: pressure has no writer, so only probes exercised it.

## Rows for the coordinator (not written here)

**docs/WORK_QUEUE.md, one line at the top:** `2026-11-06 **DANGER IS ONE NUMBER (W15, Z1) - migration 0330, no change to play** voyage.sea_danger is the one reader of piracy_index, each segment freezes its danger at departure, public.sea_pressure empty, world.sea_danger closed until Z2. PR open, not deployed; deploys after 0329.`

## PROD CHECKS

- Before deploy, after 0329 is on prod: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-danger/before.sql`. Every `times` 1, seas 51, `sea_danger_fn` null, `pressure_table` null, `old_mix` 1, `knobs` 0, `piracy_readers` exactly `voyage.sea_mix(uuid)` and `voyage.settle`, head 0329.
- After deploy: `scripts/ops/harness/sea-danger/after.sql`. Head 0330, `pressure_rows` 0, seas 51, `volatile` `ssss`, `off_by_a_digit` 0, `levels_moved` 0, `piracy_readers` exactly `voyage.sea_danger`, `frozen_wrong` 0, `sailing_frozen` rising towards `sailing`.
- `bash scripts/ops/health.sh`, and the arrivals beat for 30 minutes.
