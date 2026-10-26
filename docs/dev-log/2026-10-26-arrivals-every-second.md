# 2026-10-26 — Arrivals every second (owner row 224) — migration 0239

> *Money must move every 1 second, for real.* — and: *"change to 1 sec, compare how much server cost it needs"*

Migration `supabase/migrations/20260818000239_the_quay_is_read_every_second.sql`. Server only; the client is not touched.

## 1. Where a run's time goes today (measured)

### 1a. Prod, read-only (2026-10-26, 05:05–06:05 UTC, head 0237/0238)

| What | Number |
|---|---|
| `byeharu-voyage:arrivals` runs in the hour | 235 (cron `15 seconds`) |
| run time mean / p50 / p95 / max | **7.68 s** / 7.48 s / 10.58 s / 11.59 s |
| last 24 h | 5,699 runs, mean 5.36 s, **30,569 s of run time** |
| work in the hour (1 h of rows) | 5,158 arrivals, 32,952 sea-days, 1,573 lap starts, 17,174 ledger + 11,087 city-flow rows |
| work per 15-s run | 21.5 arrivals, 137 sea-days, 6.6 lap starts, 72 + 46 money rows |
| voyages at sea | 777 |

**The fixed part of a run** (work done whatever arrived), each timed on prod with a pure read of the same predicate
(every function in it `provolatile = 's'`, checked):

| Fixed part | Prod |
|---|---|
| candidate scan: `day_end_from(… delay_before_day(v.id, …) …)` over every voyage at sea | **71.3 ms** (774 at sea, 36 due; 9,726 buffers) |
| waiting-merchant queue (`npc_waiting_queue(now())`) | **12.4 ms** (1,118 buffers) |
| yard release, route wake, port-time wake | < 2 ms each locally (not timed on prod) |

So of a 7.68-s run, ~85 ms is fixed and **~7.6 s is per-event work** (sea-days, arrivals, merchants' lap starts).
Sampling `pg_stat_activity` four times during runs showed the arrivals backend twice in `IO / DataFileRead`: the
database is 1,005 MB on a 1 GB instance (`shared_buffers` 256 MB), and `voyages` alone has 25.7 M heap blocks read
from outside shared buffers since the last stats reset. Per-event work on prod is slow partly because it waits on disk.

### 1b. Local, the cached world (PGlite, chain to 0238; 850 fleets, 837 merchants switched on, 834 at sea, passages
spread over their length, then caught up and **warmed 240 one-second runs** before measuring)

Fixed part of a run, nothing due (median of 5):

| Fixed part | before 0239 | after 0239 |
|---|---|---|
| candidate scan | 34–51 ms (old predicate) | index on `due_at` (inside the 3 ms below) |
| waiting-merchant ask | 5–7 ms | skipped except on the 15th seconds |
| yard release / route wake / port-time wake | 1.1–1.6 / 2.1–3.2 / 1.4–1.7 ms | 0.6–0.9 / 0.8–1.3 / 1.2–1.5 ms |
| **a whole `tick_arrivals` with nothing due** | **28.1 ms** | **3.1 ms** |

Per-event costs: §2c.

## 2. What changed, and the proof

### 2a. The change (details in the migration header)
1. `voyages.due_at` — her next due instant, kept on the row by ONE trigger (`voyage.keep_due_at`), the exact
   expression the scan used to evaluate for every voyage every run; partial index `voyages_due_at`. A
   `time_compression` change re-keeps all voyages at sea (trigger on `world_config`).
2. `tick_arrivals` reads `v.due_at <= p_now` (two code hunks + two comment hunks).
3. Partial indexes for the yard release (`fleets_repair_due`) and the route wake (`standing_routes_hold_due`).
4. Waiting merchants asked once every `npc_ask_every_seconds` (15) of the clock (`public.npc_ask_slot`).
5. Cron `byeharu-voyage:arrivals`: `15 seconds` → `1 seconds`, done by the migration (`cron.alter_job`, active
   flag kept as found). `wind_the_clock()` only flips `active`, so after a deploy it starts the job on `1 seconds`.
   pg_cron never overlaps a job with itself ("only one instance of each specific job at a time … If a second instance
   is triggered before the first finishes, it's queued", github.com/citusdata/pg_cron README), and the scans already
   lock FOR UPDATE SKIP LOCKED, so no advisory lock is added.

### 2b. Self-assert (runs in the migration, own probe rows, rolled back)
- the re-cut body reverses to its pre-image; ACL / volatility / definer / config unmoved; no client can execute the
  new functions; registry and walls unmoved;
- every voyage at sea: `due_at` = the old scan's expression; no voyage not at sea keeps one;
- `npc_ask_slot` is `floor(epoch) mod 15 = 0` (fixed instants in 2000, no time of day);
- the cadence reads `1 seconds` where pg_cron exists;
- **a probe arrival settles in one run, nothing else touched:** a probe company sails Lisbon → Funchal, her passage is
  moved whole into 1999, and ONE `tick_arrivals('2000-01-01 00:00:01')` (before every real due instant; asserted that
  nothing else is due then and that it is not an ask slot) settles all her days and docks her at FNC: touched 1,
  asked 0, `due_at` null; every merchant's fleet and voyage at sea has the same digest after; the OLD body from the
  same state answers the same;
- doubling `time_compression` re-keeps every voyage at sea (rolled back).

### 2c. Timing loop (local PGlite, the warmed world above, a run every 1 s of wall time, 100 runs)

Same world, same warm-up, same machine, one after the other (the world keeps sailing, so the two runs do not see
identical events; the per-run event counts are given):

| 100 runs at 1 s | before (live body, 0238) | after (0239) |
|---|---|---|
| p50 | 491 ms | **320 ms** |
| p95 | 1,588 ms | 2,210 ms |
| max | 3,243 ms | 4,626 ms |
| mean | 611 ms | **584 ms** |
| a run: arrivals / sea-days / fleets touched | 2.51 / 9.58 / 10.48 | 2.40 / 10.04 / 11.02 |
| a run with nothing due | 28.1 ms | **3.1 ms** |

**Where a second's work goes (after 0239)**, each pass run on its own every second for 60 s on the warmed world:

| Pass | ms a second | items a second | ms an item |
|---|---|---|---|
| arrivals (settle at eta: last days, docking, her queue) | 183.1 | 2.85 | 64.3 |
| sea-days (settle of a day that ended) | 40.6 | 7.77 | 5.2 |
| **route wakes (a merchant's lap start: `cmd.advance` after her rest)** | **350.5** | 0.98 | **356.5** |
| yard release | 2.9 | 0.03 | 86.1 |
| port-time wake (dark) | 1.7 | 0 | – |

At prod's event rates (1.43 arrivals, 9.2 sea-days, 0.44 lap starts a second) these local costs make ≈ 300 ms of work
a second on wasm. **The goal "1–3 arrivals in < 300 ms" holds for a second without a lap start** (3 ms + 1–3 × 64 ms +
~9 × 5 ms ≈ 110–240 ms here), **and not for a second in which a merchant starts a lap** (~360 ms each, here). That is
the merchants' re-planning (`npc_tend_route` / route core), not this job's scan, and 0239 does not change it. The
p95 / max are those seconds (and several lap starts falling in one second). Prod's per-event work is slower than
these numbers (§1a: disk waits), so prod runs will be longer than local ones; §5c measures them after the deploy.

## 3. What else assumed a 15-s beat

| Place | Assumes 15 s? | Action |
|---|---|---|
| `src/app/AppShell.tsx:46-55` (the client's read beat, 7.5 s) | No — derived from `time_compression` (12 reads per voyage-day) | none |
| `src/features/stats/MoneyLog.tsx:20-29` (Money log, asks every second, `LATE_MS` 20 s) | Its comment names the 15-s job; the 20-s overlap still covers a 10-s run | none (comment only) |
| PR #334 (money feed drip, merged) | Feeds a batch row by row; batches are now one second's worth | none |
| `arrivals_tick_budget_ms` (10 000) | Was "the next run's", every 15 s | kept; description amended |
| `scripts/ops/harness/raid/after-check.sh` (arrivals avg ≤ 3 s, p95 < 5 s) | Bounds per run; runs get shorter | none |
| `byeharu-voyage:cron-purge` (keeps 2 days of `cron.job_run_details`) | 4 rows/min → 60 rows/min for this job | kept (see §4) |
| Roster / sea traffic reads | Positions are computed from time (`where_now`), not from the job | none |
| `time_compression` | Not a cadence | none |

## 4. Server cost: 15 s today vs 1 s

Plan: Supabase **Pro** with the **Micro** compute (owner). Micro = shared CPU (the docs give no core count for the
shared sizes), 1 GB RAM, 60 direct connections; disk baseline 11 MB/s and 500 IOPS, burst to 261 MB/s / 11,800 IOPS
from an IO budget (https://supabase.com/docs/guides/platform/compute-and-disk). Pro is "from $25/month" and includes
"$10/month in compute credits", which covers one Micro; Small (2 GB) is $15/month, Medium (4 GB) $60, Large (2
dedicated vCPU, 8 GB) $110; egress 250 GB included, then $0.09/GB (https://supabase.com/pricing).

| | 15 s (today) | 1 s, without 0239 | 1 s, with 0239 |
|---|---|---|---|
| runs an hour | 240 | 3,600 | 3,600 |
| fixed part a run (prod) | ~85 ms | ~85 ms | index reads; ~1–3 ms expected (local 3 ms on wasm) — **re-measure after deploy (§5c)** |
| fixed part an hour | ~20 s | ~306 s | ~4–11 s |
| per-event work an hour (same events) | ~1,823 s (7.6 s × 240) | ~1,823 s | ~1,823 s |
| **job run time an hour** | **~1,843 s** (last hour; 24-h average 1,274 s) | ~2,130 s | **~1,830–1,835 s + connection starts** |
| as a share of one CPU core, continuously | ~51 % | ~59 % | ~51 % |
| connections | 1 at a time, 240 opened/h | 1 at a time, 3,600/h | 1 at a time, 3,600/h (pg_cron opens a libpq connection per run; `cron.use_background_workers = off`). The cost of a connection start was not measured. |
| commits an hour | 240 | 3,600 | 3,600 (money rows the same in total, smaller batches) |
| `cron.job_run_details` kept (2 days) | ~13,000 rows, 5.2 MB (all jobs, measured) | ~180,000 rows, ~70 MB | ~180,000 rows, ~70 MB (≈ 400 B a row, measured) — two row writes a run go to WAL |
| egress | — | unchanged | unchanged (no client read changes; the Money log already asks every second) |

"Run time" is time inside the job, not pure CPU: part of it is waiting on disk (§1a). It is the honest upper bound
for the CPU the job uses.

**Verdict:** with 0239, one run a second does the same work as today in smaller pieces, so the job's load stays
about where it is (~51 % of one core, the same as now). It fits the Micro instance the owner already pays for inside
Pro's $10 compute credit; no compute add-on is needed for the 1-s change. Without 0239, the same change would add
~290 s an hour (+16 %) of pure overhead. What would make each second's work faster is memory, not cadence: the
database (1,005 MB) no longer fits a Micro's 1 GB, and runs wait on disk reads. Small (2 GB) costs $15/month, i.e. $5
more than the credit; whether it removes the disk waits is NOT measured.

## 5. PROD CHECKS (read-only, pure SELECTs, one statement per block; run by me on 2026-10-26, head 0238)

Every function called is `pg_get_functiondef`, `replace`, `length` (built-ins). No EXPLAIN ANALYZE.

### 5a. The hunks on the LIVE `tick_arrivals` (after 0237). Expect `1,1 / 2,1 / 3,1 / 4,1`.

```sql
select h.n, (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as occurs
  from (select replace(pg_get_functiondef('public.tick_arrivals(timestamptz)'::regprocedure), E'\r', '') as def) d,
       (values (1, $h$  -- the next run's (the job runs every 15 s).
$h$),
               (2, $h$  v_k       numeric := public.wc_num('time_compression');   -- 0169: the candidate scan's knob, once a run
$h$),
               (3, $h$              -- 0169: voyage.day_ends_at(v.id, n) composed from the row in hand (voyage.day_end_from over
              -- voyage.delay_before_day), the knob read once a run — the same test, one read a voyage
              and (v.eta <= p_now
                   or voyage.day_end_from(v.eta, v.departed_at, v.last_settled_day + 1,
                                          voyage.delay_before_day(v.id, v.last_settled_day + 1), v_k) <= p_now)
$h$),
               (4, $h$  begin
    v_asked := public.npc_ask_waiting(p_now, v_t0 + v_budget);
$h$)) h(n, old)
 order by h.n
```
Result: `1,1` `2,1` `3,1` `4,1`.

### 5b. Nothing this file creates exists yet; the probe's harbours are there. Expect `0,0,0,0,0,15 seconds,2`.

```sql
select (select count(*) from pg_attribute where attrelid = 'public.voyages'::regclass and attname = 'due_at' and not attisdropped) as due_at_cols,
       (select count(*) from pg_class where relname in ('voyages_due_at', 'fleets_repair_due', 'standing_routes_hold_due')) as index_names_taken,
       (select count(*) from pg_proc where proname in ('keep_due_at', 'due_at_follows_the_clock', 'npc_ask_slot')) as fn_names_taken,
       (select count(*) from public.world_config where key = 'npc_ask_every_seconds') as knob_taken,
       (select count(*) from pg_trigger where tgname in ('voyages_keep_due_at', 'world_config_time_compression_keeps_due_at')) as trg_taken,
       (select schedule from cron.job where jobname = 'byeharu-voyage:arrivals') as arrivals_schedule,
       (select count(*) from public.sea_reaches r join public.ports p on p.id = r.port_id where p.code in ('LIS', 'FNC') and p.kind = 'HARBOUR') as probe_reaches
```
Result: `0,0,0,0,0,15 seconds,2`.

### 5c. AFTER the deploy (for the deployer). Expect `1 seconds`, mean well under 1 s, and ~3,600 runs an hour.

```sql
select (select schedule from cron.job where jobname = 'byeharu-voyage:arrivals') as schedule,
       count(*) as runs, round(avg(extract(epoch from end_time - start_time))::numeric, 3) as mean_s,
       round((percentile_cont(0.5) within group (order by extract(epoch from end_time - start_time)))::numeric, 3) as p50_s,
       round((percentile_cont(0.95) within group (order by extract(epoch from end_time - start_time)))::numeric, 3) as p95_s,
       round(max(extract(epoch from end_time - start_time))::numeric, 3) as max_s,
       round(sum(extract(epoch from end_time - start_time))::numeric, 0) as run_seconds
  from cron.job_run_details where jobid = (select jobid from cron.job where jobname = 'byeharu-voyage:arrivals')
   and start_time > now() - interval '1 hour'
```

### 5d. AFTER the deploy: the new scan's plan (plain EXPLAIN, not executed). Expect an Index Scan on `voyages_due_at`.

```sql
explain select v.fleet_id from public.voyages v where v.status = 'SAILING' and v.due_at <= now() order by v.eta
```
