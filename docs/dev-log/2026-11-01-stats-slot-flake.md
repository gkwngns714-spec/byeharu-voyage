# MAIN RED: a slot-boundary flake in the stats spec (0288 merge b217c07)

2026-11-01. Acceptance shard 3/3 on `b217c07` failed `tests/rpc.stats.spec.ts:57`, "the job writes one
rollup per slot and nothing on a second call in the same slot": expected `wrote` 0, received
**2257** — a full slot's rows (world + goods + cities + city_goods + merchants).

## Cause (from the numbers)

The spec called the job at **two different `now()` instants**: `beforeAll` ran
`tick_price_snapshot(now())` then `tick_stats(now())` (~lines 43–44), and the test called
`tick_stats(now())` again (~line 58). Each `now()` is evaluated at its own call. Two instants a few
seconds either side of a **15-minute stats-slot boundary** belong to two DIFFERENT slots, so the
second call legitimately wrote a new slot — 2257 rows is exactly one slot's worth. A flake of a few
seconds per 15-minute window, and not a product bug: nothing about the job changed.

## Fix (the same-slot premise becomes the test's own fact)

`beforeAll` now reads ONE instant from the world itself and keeps it:

```sql
select now()::text as result
```

and `tick_price_snapshot`, the setup `tick_stats`, and the test's second `tick_stats` all receive
that SAME instant (`'<at>'::timestamptz`). Two calls with one instant are in one slot by
construction, so the test proves the job's behaviour, not the clock's.

## Verification

- **`tests/rpc.stats.spec.ts`, the whole file: 7 passed, 0 failed (46.7 min)** — the local world
  build dominates the wall time; the same-slot test reads `wrote` 0 as its premise demands.
- **`tests/city.page.spec.ts` entry test on a served build of current main (`b217c07`): PASS
  21.4 s** — #436's `bringToFront` + poll fix is intact.
- `tsc -b`, `eslint .`, `npm run build` clean.
