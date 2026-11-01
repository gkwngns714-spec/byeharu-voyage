# 2026-11-01 — 0293: the journal starts over (the 2.1 M-row cache behind the 58-second Stats read)

**Branch** `journal-reset` · migration `supabase/migrations/20260818000293_the_journal_starts_over.sql` · deploys AFTER 0291 (laps) and 0292 (port_goods).
Owner, 2026-11-01: *"if there is a big load of data that is causing this slowness, remove them and start over, but with precaution method this slowness will
not happen again."*

## 1. The load
`world.stats_now()` = base row `public.stats_live` + the SUM of every row of the journal `public.stats_live_deltas` (0224). The count that folds the journal away
was dead 2026-10-30 18:21 → 2026-11-01 15:06 (see 0290/0291), so the journal grew to **2,147,539 rows / 250 MB** (+~7 rows/s). Measured on prod, read-only:
`world.stats_now()` **57.8 s per call** (CLI baseline 3.3 s) at 15:08 UTC; the Stats tab asks again the moment one answers. 0290 drains the journal 300,000 rows a
run, but only while a count has budget left; the first successful count (15:06, 109 s) did not reach its drain step in time.

## 2. Why starting over is safe
The journal is a CACHE of deltas against a base that every fold re-derives from the world's own totals (ducats by holder, escrows, accruals, fleets at sea). The
seed step 0224 used does exactly this from an empty journal. Nothing player-owned and no stats HISTORY row is touched.

## 3. What the migration does (one transaction)
`lock table public.stats_live_deltas in access exclusive mode` (writers queue, then commit after; 5 s lock timeout) → `truncate` (instant) →
`update public.stats_live set counted_through = clock_timestamp()` (the "trades since the count" window starts empty) → `stats_live_fold(clock_timestamp(), true)`
(base := aggregates, drift := {}, folded := 0). Self-assert: the journal is empty (exact under the lock); `stats_live` re-seeded; `world.stats_now()` serves exactly
the base; every function md5-unmoved; registry/walls/switches as found. Gates (local, once): `check-versions` 279 · `BYEHARU_PREFIX_CACHE=required proof.mjs
standing` 278 restored + 1 applied, **279/279 receipts** · `duplication.spec` 11/11.

## 4. PRECAUTIONS so a journal this size cannot form again
- 0290 (live): the count does bounded work and drains the journal 300,000 rows a run; the journal is also bounded by the count's own 15-minute fold.
- 0291 (laps) and 0292 (port_goods): the I/O the count competes with goes down; the count's visibility-map blocker is gone.
- Follow-up (0295, with the period fix): the drain runs FIRST in the count (not last), so a late run still drains; and the count's receipt records the journal's size so
  a growing journal is visible in `public.stats_runs` before it matters.

## 5. After-check (coordinator, read-only)
`select count(*) from public.stats_live_deltas` small and growing only ~7/s until the next fold; `world.stats_now()` well under a second; `public.stats_live`: folded 0,
drift {} at the commit; the next count `succeeded` and its fold keeps `drift` at 0 (a non-zero drift would mean a writer bypassed the journal — report it).
