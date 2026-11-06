# Ops harness, kept for re-use

These are the scratch tools behind the 2026-10-18/19 measurements, copied from `~/dev/bv-harness` so they travel with the repo. They are **not** part of the build or CI. Source only: the 3 GB of worlds and node_modules they generate stay local and are rebuilt by `setup.mjs`.

- `raid/after-check.sh <start> <end>` is the PAIRED fight after-check, run READ-ONLY on prod. It compares each lit raid against the dark table on the same raid, prints the arrivals, reconcile and queue figures, and ends with a PASS or FAIL line. Run it after any change that lights or rebalances combat.
- `raid/paired.sql` is the query behind it. `raid/sim.mjs` replays prod's raids through `voyage.fight_resolve`.
- `sim/` holds the prod-shaped merchant world (`setup.mjs`, `prodlike.mjs`, `sim.mjs`, `measure*.mjs`). It keys loops by company and fleet. The older `laps-scratch` copy keyed them by fleet name, which was a bug.
- `haul/` is the `haul_max` sweep of 2026-10-20 (0212): `sweep.mjs` lays the arrfast world over an image, applies the
  migrations, then measures `bands.sql` (the far-selling metric: a competent trader's best profit per day by route band)
  for each candidate value in a rolled-back transaction; `sum.mjs` prints the medians and the long ÷ short ratios.
- `speed/` is the 0220 pair of 2026-10-25 (ship speed ×3): `prep.mjs` lays the arrfast state over a merchant world, applies
  the migrations prod applied after that state and dumps the common ground ONCE; `arrfast/sim.mjs` with `ARRFAST_SETUP=0`
  then runs each arm on that dump (the after arm applies the migration under test before the kickoff); `players.mjs` +
  `player.sql` measure a starter's day (days quoted, ducats per real hour and laps per real day by band, through the game's
  own speed authority) before and after the migration in one rolled-back transaction.
- `armed-cargo/` is 0328: `proof-0328.mjs` (red first, the `rich-cities` scene and its own `dark-scene.sql` equal before and after the file, mutations red, the real file and proof 36 green, cached world; `--first=` applies 0327 before it), `before.sql` and `after.sql`, both read-only on prod.
- `fleet-follows-wealth/` is 0326: `proof-0326.mjs` (the file's absence red, 21 mutations red, the real file and proof 35 green, cached world; `--with=18,19,20,30,32` runs those after the file), `before.sql` (each hunk occurs once on prod, a pure SELECT).
- `rich-cities/` is 0324: `proof-0324.mjs` (red first, `dark-scene.sql` equal before and after the file, mutations red, the real file and proof 32 green, cached world), `before.sql` and `after.sql`, both read-only on prod.
- `battles/` is 0323: `proof-0323.mjs` (the file's absence red, mutations red, the real file and proof 31 green, cached world; `--first=` applies 0321 and 0322 before it), `before.sql`, read-only on prod.
- `two-sides/` is 0320: `proof-0320.mjs` (mutations red, the real file and proof 28's pure half green, on `mini-world.mjs`, no chain needed), `on-image.mjs` (the file and the whole proof on a kept world image), `golden.sql` (read-only on prod, take it before and after the deploy), `prod-check.sql` (read-only), `sides.mjs` (`raid/sim.mjs --sides`: real hulls on both sides).
- `a-day/` is 0317: `proof-0317.mjs` (mutations red, the real file and proof 26 green, cached world).
- `merchants-invest/` is 0313: `proof-0313.mjs` (mutations red, the real file and proof 21 green, cached world), `before.sql` and `after-check.sql`, both read-only on prod.
- `city-requests/proof-0318.mjs` is 0318: a draw's call count red first, mutations red, the real file green (`PROOF_WORLD=browser` uses the world image's cache where the preamble cache is short; it stops rather than replay from far back).
- `live_*.sql` / `hunks*.sql` are dumps of live function bodies and migration hunks at the time. Re-dump from prod before re-using any of them.

Every prod query here runs inside `begin transaction read only` and calls only `provolatile` 's'/'i' functions.
