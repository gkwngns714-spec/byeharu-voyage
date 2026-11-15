# db-room runbook: getting the space back after 0428

**Nothing here has been run. Every step is the lead's to run, the owner's to approve.** 0428 stops the growth and makes the old rows go,
but PostgreSQL keeps freed space inside a table; only a rewrite (`VACUUM FULL`) gives it back to the disk. Sizes are prod's at
2026-11-15 00:42 UTC; the "after" sizes are estimates from each table's live rows and row width (the dev-log has the arithmetic).
Times are "throttled disk / not".

Every statement below is ONE call, on its own: VACUUM cannot run inside a transaction block, and two statements sent together are one
implicit transaction. Best in psql (one session), with `set lock_timeout = '3s';` sent first as its own statement, so a rewrite that
cannot get its table gives up instead of queueing the game behind it; or one line at a time in the dashboard's SQL editor; or
`npx --yes supabase@2.120.0 db query --linked "<the one statement>"`. They are kept here, not as .sql files: a harness .sql file is a
read-only prod check or a guarded local scene (`tests/harness.guard.spec.ts`), and these are neither.

## 0. Before anything

1. 0428 is deployed and `after.sql` reads as wanted.
2. **Wait for the trims to drain** (a rewrite before the rows go copies them): about **6 hours** after the deploy.
   - stats_good / stats_city: their day marks (`after.sql` `fold_marks`, unit `day`) reach now - 8 days (from 10-16: ~22 Stats runs, ~5.5 h);
     the hour marks reach now - 30 h (~3 h).
   - price_history_hour: `live` ~225,000 (the first price-snapshot run after the deploy prunes the hours past 8 days at once).
   - the churn tables: each swept once under the new settings (`last_av` after the deploy); usually within the hour.
3. `scripts/ops/harness/db-health/gate.sql`: green. Keep `daily.sql`'s answer as the "before".
4. Free disk for the largest rewrite (~50 MB of table plus as much WAL): check the dashboard.

## A. Tables the beat does not write: no pause (frees ~237 MB)

Each holds ACCESS EXCLUSIVE on its table for its length; the file says which job or screen waits and at which minute to run it.
Read the gate between two of them.

| statement (one call each) | table | now | after | frees | runs at |
|---|---|---|---|---|---|
| `vacuum (full, analyze) public.price_history_hour;` | price_history_hour | 155 | ~48 | ~107 | minute 3, 13, 23 ... (between price snapshots) |
| `vacuum (full, analyze) public.stats_good;` | stats_good | 103 | ~42 | ~61 | minute 8, 23, 38, 53 (after a Stats count, before the history job) |
| `vacuum (full, analyze) public.stats_city;` | stats_city | 76 | ~35 | ~41 | the same |
| `vacuum (full, analyze) public.stats_city_good;` | stats_city_good | 65 | ~47 | ~18 | the same |
| `vacuum (full, analyze) public.price_history;` | price_history | 24 | ~14 | ~10 | minute 3, 13, 23 ... |

After A: ~765 MB.

## B. Tables the beat writes: a short window with the clock stopped (frees ~175 MB)

First `select jobname, active from cron.job order by 1;` (write it down), then `select public.unwind_the_clock();` and wait 70 s (the minute
jobs in flight finish), then the rewrites below one at a time, then `select public.wind_the_clock();` (every defined job active again; a job
the first read showed inactive, set back by hand). About 1-2 minutes not throttled, 4-5 throttled. Players' own actions go on while the clock
is stopped; merchants, navy, pirates and arrivals wait and land when it starts (voyages are settled by the clock's time, nothing is lost). If one rewrite fails on its lock, wind the clock and do that table another time.

| statement (one call each) | table | now | after | frees |
|---|---|---|---|---|
| `vacuum (full, analyze) public.voyages;` | voyages | 84 | ~40 | ~44 |
| `vacuum (full, analyze) public.events;` | events | 49 | ~21 | ~28 |
| `vacuum (full, analyze) public.orders;` | orders | 37 | ~12 | ~25 |
| `vacuum (full, analyze) public.trade_daily;` | trade_daily | 27 | ~3 | ~24 |
| `vacuum (full, analyze) public.treasury_flows;` | treasury_flows | 21 | ~3 | ~18 |
| `vacuum (full, analyze) public.voyage_events;` | voyage_events | 46 | ~34 | ~12 |
| `vacuum (full, analyze) public.insured_voyages;` | insured_voyages | 14 | ~3 | ~11 |
| `vacuum (full, analyze) public.standing_route_laps;` | standing_route_laps | 11 | ~4 | ~7 |
| `vacuum (full, analyze) public.ledger;` | ledger | 10 | ~4 | ~6 |

After A and B: **~590 MB**. It then settles at **~650-680 MB**: each churn table carries up to ~15 % dead rows between passes (~20 MB),
0427's battles ~50 MB (about 100 rows a minute, kept 48 h), the day rows ~1 MB a day. Hot set ~450 MB of the ~700 MB cache.

## C. Optional, the owner's call: port_goods at fillfactor 50 (frees ~35 MB)

Inside B's window (after the ledger, before the wind): `alter table public.port_goods set (fillfactor = 50);`, then
`vacuum (full, analyze) public.port_goods;` (93 -> ~58 MB, ~15 s throttled). The slim-db RUNBOOK 3b
reasoning holds and is stronger since 0420: each row is repriced about once in 13 minutes, so half a page of room keeps every update on its
page. Watch `hot` against `upd` on port_goods for a day (within 2 %). Undo: fillfactor 30 and the rewrite again.

## No REINDEX needed

`VACUUM FULL` rebuilds a table's indexes. No other index is swollen (the largest outside these tables is port_goods' 8 MB key).

## After

1. `daily.sql`: `database_mb` and `hot_set_mb` under budget, no `dead_pct` line, cache hit climbing back over 99 % (it is counted since the
   last statistics reset, so it climbs slowly).
2. Nothing needs repeating: the 0428 settings keep each table at its live rows + ~15 %.
