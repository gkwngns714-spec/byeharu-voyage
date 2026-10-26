# 2026-10-26 — Every figure is kept: the Stats tables fold instead of dropping, and every chart opens large (owner row 232, N1 of docs/NEWS_AND_MARKERS.md, migration 0246)

> *"i want to see in large graph, like sell and buy, for stats chart to when tapped. it needs data that saves for months too, get it?"*
> (2026-10-26, docs/OWNER_REQUESTS.md row 232.)

Server + client, one slice. `supabase/migrations/20260818000246_every_figure_is_kept.sql` (prod head is 0244; 0245 is another slice; the deploy renumbers).
Branch `osn-n1-stats-history`, cut from origin/main 1112dd8.

## What was being lost

0214's retention deleted, past 72 h (city goods 48 h), every slot of a UTC day but the last. The kept row's state is right but its
flows (`sold`, `bought`, `units`, `trades`, `minted`, `removed`, `moved`, `*_ducats`, `period`, `flows`) are 15 minutes' worth: 95 of every 96
slots' flows vanished each day. **10-20 -> 10-23 is already compacted that way and cannot be rebuilt** (stated in the migration header).
The price record (`price_history*`, 0226) has its own tiers and is untouched.

## Exact retention, per table (after this file)

| Table | Fine (15 min) | Hourly rows | Daily rows |
|---|---|---|---|
| `stats_world`, `stats_merchants` | 72 h (`stats_fine_hours`) | **for ever** (49 MB a year for both) | none (hourly is the floor) |
| `stats_good`, `stats_city` | 72 h | 30 d (`stats_hour_days`) | **for ever** |
| `stats_city_good` | 48 h (`stats_city_good_fine_hours`) | 7 d (`stats_city_good_hour_days`; 30 d would be ~375 MB) | **for ever** |
| `price_history*` | 24 h | 30 d | for ever — unchanged (0226) |

Nothing is ever pruned past the daily tier, so 1m, 1y and All have real data. Flows are ADDED, states are the LAST slot's, `n` says how many slots a row folds
(1 fine, up to 4 an hour, up to 96 a day; a legacy day row is 1 — it kept one slot).

## What the file does

- `n smallint not null default 1` on the five tables; knobs `stats_hour_days` 30, `stats_city_good_hour_days` 7, `stats_fold_back_days` 14.
- One rule of a bucket and of a span, each in one place: `stats_bucket(at, unit)` (the row's OWN UTC hour / day), `stats_span_unit`, `stats_span_since`, `stats_map_sum` (key-wise sum of `period` / `flows`, a zero kind dropped).
- `public.stats_fold(table, unit, lo, hi)` — set-based, finished buckets only; one statement per table (update the bucket's last row, delete the rest); a lone row is never touched.
- `public.stats_compact(now)` — the tiers per table; `tick_stats` calls it in place of 0214's five deletes (3 hunks: declare, the retention block, the return gains `fold`). No new cron job.
- `world.stats_overview(p_hours, p_span)`, `world.stats_city(p_port, p_span)`, `world.stats_merchants(p_span)` take a span like `world.price_series`; the series is cut from the span's tier (1d fine, 1w / 1m hourly, 1y / All daily), so a line never mixes a 15-minute flow with an hour's. Each point has `n`; `span` is echoed; a bad span raises `E_BAD_SPAN`. A null span is the old window, so the previous client keeps working during the deploy. The registry (`client_rpc_entry_points`) follows the three argument lists.
- Client: `StatsChart` — every Stats line is a press target; pressing opens the SAME `Tray` as the Buy / Sell good page (bottom on a phone, side pane on a wide glass) with the shared `SpanPicker` over the SAME `SeriesChart`, drawn large. The span is the one `useChartSpan` store; `useLiveRead` gained a `refresh` key so a span press re-asks at once and keeps the figures on screen. Words: "All money" lost its "last {n} h" (the span is on the picker). No new words.

## Said plainly

- `stats_fold_back_days` is not in the design table: the fold looks 14 days back from each tier's edge instead of re-reading every daily row ever, every 15 minutes. A cron dead for more than 14 days leaves older fine rows unfolded until the knob is raised once; it never loses or double-counts.
- An hourly row's `at` is its last slot's own `at`, not the bucket's start.
- The bucket's chart point for 1w / 1m / 1y / All is built at read time from the stored rows, so rows older than this file (daily, n = 1) draw as daily points inside an hourly line — honest, and only until they age out of the picture.

## The proof (migration self-assert, rolled back)

- (b) the fold on all five tables with probe slots at fixed instants in 2001: 8 slots across 2 hours -> 2 hourly rows (flows 10 / 26, map key-sum with a zero kind dropped, state the last slot's, n = 4); 5 hourly rows across 2 days -> 2 daily rows (36 / 29, n 12 / 8); hour + fine rows -> one day row (55, n = 10); the later fine rows untouched; a second and a wide run remove nothing; neither lone daily row deleted or rewritten.
- (c) `tick_stats` carries the fold once and no `delete from public.stats_`; a count run two hours ahead returns `fold` — its ms is printed.
- (d) the reads over 1d 1w 1m 1y all on three faces, probe rows planted past every real one: series flows and `n` add up to the table's, one point per bucket, the 1w tier folds two probe hours into two points, a bad span raises.
- (a)(e) hunks reverse; ACL / volatility / definer / config; registry; helpers open to no client; walls 0.
- Spec `tests/stats.bigChart.spec.ts`: tap a chart, the tray opens, the page under it does not move, the span press switches the series (the server's echo `data-span`).

## PROD CHECKS (read-only; pure SELECTs, nothing volatile called; 2026-10-26 ~12:30 UTC)

- Live bodies re-read with `pg_get_functiondef` on prod: `tick_stats` (0232 + 0243 shape, retention block as the hunk assumes), `stats_overview`, `stats_city`, `stats_merchants`, `client_rpc_entry_points`. ACL: the three reads authenticated only; `tick_stats` / helpers postgres + service_role. `tick_stats` is `v`, every `stats_*` read and `stats_window_*` is `s`.
- Row counts: stats_world 291, stats_merchants 291, stats_good 162,385 (40 MB), stats_city 69,962 (25 MB), stats_city_good 340,165 (113 MB). Nothing older than 72 h except one row a day.
- The fold's own selection on prod, as a SELECT: buckets that would fold TODAY — city goods hourly (14 days back from the 48 h edge): 0; goods daily: 0; world hourly older than 72 h: 0. So the first count after deploy rewrites nothing; the first fold happens as rows age past 72 h / 48 h.
- Cost of the fold's scan, `EXPLAIN (ANALYZE)` of the grouping SELECT on the largest table (stats_city_good, 14 days back, no index on `at`): **275 ms** (parallel seq scan); the other four are smaller, so the fold adds ~1 s to a count that takes 12-18 s. An index on `at` would cut it; left out to keep the write path as it is.
- Identity on real data: stats_world grouped by UTC hour = 76 buckets over 291 rows, and sum(sold) is the same 1,242,128,022 both ways — the read's series is the table's flows, exactly.

## Local run (PGlite, cached chain prefix 233/234 restored; migration applied in 1.5 s)

Receipt: the fold on all five tables 117 ms; a count two hours ahead 1,071 ms of which the fold 11 ms (empty local history). Gates run before the push: `npm run build` (world image certified), `npx tsc --noEmit`, `npx eslint .`, and on port 4193 (headless, localhost) `tests/stats.bigChart.spec.ts`, `stats.tab`, `stats.filters`, `rpc.stats`, `rpc.surface`, `align` — all green (40 passed).
CI spec selection: automatic (rule S from the migration's defined names, rule N/G from `StatsChart.tsx` / `Overview.tsx`); no map entry to add.
