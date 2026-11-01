# 2026-11-01 — 0291: the laps keep their map (why 0290's first count still timed out)

**Branch** `laps-vacuum` · migration `supabase/migrations/20260818000291_the_laps_keep_their_map.sql` · one `ALTER TABLE … SET (autovacuum…)`,
no row, function or value moves. Deploys FIRST of the queued migrations (it unblocks the Stats count); the `port_goods` rewrite is 0292.

## 1. What happened
0290 went live at 14:44 UTC (head `20260818000290`, push rc 0, PR #442 merged). Its first count, `14:51:00`, still failed — 120.7 s,
`canceling statement due to statement timeout`, inside `public.stats_merchants_window`. So the backlog 0290 bounds was not the whole story.

## 2. Measured (read-only, prod, 14:54–15:05 UTC)
| phase, run alone | wall (CLI overhead ≈ 3 s included) |
|---|---|
| `stats_window_totals` / `founded` / `goods` / `cities` / `city_goods`, 120 min | 7.3 / 3.5 / 2.6 / 3.9 / 2.6 s |
| **`stats_merchants_window(now() − 24 h, now())`** | **> 115 s (killed by my own client timeout)** — it was ~12 s on 10-30 |

The plan is right (`Index Only Scan using standing_route_laps_window`, 0287's covering partial index) but the scan is not index-only:
`EXPLAIN (ANALYZE, BUFFERS)` on the plain lap read — **1 h: rows 833, Heap Fetches 833; 3 h: rows 3,222, Heap Fetches 3,264** (every row is a heap read).
`pg_class`: `standing_route_laps` 29,094 pages, **18,461 all-visible = 63.5 %**; last autovacuum 11:17; 20,366 dead rows; default thresholds
(trigger at 33,511 dead rows or 34,461 inserts). A lap is inserted at start and UPDATED at close (`closed_at`, the index key, so never HOT) ~1,500 an
hour; every page touched since the last vacuum is unmapped. ~36,000 laps in 24 h × a random heap read on a saturated disk = the 115 s.

## 3. Why only this table
`events`, `ledger`, `voyages`, `voyage_events`, `price_history`, `treasury_flows` already carry `autovacuum_vacuum_scale_factor = 0,
autovacuum_vacuum_threshold = 1000..2000` (0224 / 0226 / 0275) and are 97–100 % all-visible, vacuumed within minutes. `standing_route_laps` — the
largest of the lap-close and merchants-window readers — was left on the defaults. (`port_goods` is also on defaults; its rewrite is 0292.)

## 4. The change and what it should do
`alter table public.standing_route_laps set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 500,
autovacuum_vacuum_insert_scale_factor = 0, autovacuum_vacuum_insert_threshold = 500, autovacuum_analyze_scale_factor = 0,
autovacuum_analyze_threshold = 2000)`. The table already has ~20,000 dead rows, so autovacuum starts within about a minute of the commit, maps the
~10,600 unmapped pages once, and then runs about every 20 minutes over only the pages touched since. Expected: heap fetches of the 24 h window fall from
~all rows to the newest pages only; the merchants phase returns to seconds; the next `:06/:21/:36/:51` count succeeds.

## 5. Gates (local, once, on the file as committed)
`check-versions` 279 distinct, no collisions · `BYEHARU_PREFIX_CACHE=required proof.mjs standing`: 278 restored from `p0278`, 1 applied, **279 / 279 with a
self-assert receipt**, world-guard ok, exit 0 · `tests/duplication.spec.ts` 11/11. No TypeScript touched (tsc/eslint not applicable).

## 6. PROD CHECKS (read-only, before the PR) and the AFTER-CHECK
Before: head `20260818000290`; `standing_route_laps` `reloptions` null; relpages 29,094 / relallvisible 18,461; the 1 h window Heap Fetches 833 of 833.
After (coordinator, 30 min): `reloptions` carry the six options; `relallvisible / relpages` rises above 95 % within minutes of the first autovacuum
(`pg_stat_user_tables.last_autovacuum` advances); the same 1 h `EXPLAIN (ANALYZE, BUFFERS)` shows a small `Heap Fetches`; `stats_merchants_window(24 h)` returns
in seconds; the next stats cron run is `succeeded` with a receipt in `public.stats_runs` (`skipped` = the 43 h span, `phases.merchants` in seconds).
Forward rollback: `alter table public.standing_route_laps reset (…the six…)`.
