# Ops harness, kept for re-use

These are the scratch tools behind the 2026-10-18/19 measurements, copied from `~/dev/bv-harness` so they travel with the repo. They are **not** part of the build or CI. Source only: the 3 GB of worlds and node_modules they generate stay local and are rebuilt by `setup.mjs`.

- `raid/after-check.sh <start> <end>` is the PAIRED fight after-check, run READ-ONLY on prod. It compares each lit raid against the dark table on the same raid, prints the arrivals, reconcile and queue figures, and ends with a PASS or FAIL line. Run it after any change that lights or rebalances combat.
- `raid/paired.sql` is the query behind it. `raid/sim.mjs` replays prod's raids through `voyage.fight_resolve`.
- `sim/` holds the prod-shaped merchant world (`setup.mjs`, `prodlike.mjs`, `sim.mjs`, `measure*.mjs`). It keys loops by company and fleet. The older `laps-scratch` copy keyed them by fleet name, which was a bug.
- `live_*.sql` / `hunks*.sql` are dumps of live function bodies and migration hunks at the time. Re-dump from prod before re-using any of them.

Every prod query here runs inside `begin transaction read only` and calls only `provolatile` 's'/'i' functions.
