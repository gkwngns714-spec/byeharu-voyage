# 2026-10-27 — Arrivals missed ~1 second in 5 (`osn-arrivals-gaps`, migration 0248)

Owner row 224: "no i want every 1 second". 0242 put `byeharu-voyage:arrivals` on `'1 seconds'`.

## The finding (prod, read-only)

`cron.job_run_details`, the hour to 07:40 UTC: 2,864 runs in 3,600 s (about 48 a minute), 1 failed,
p50 0.71 s, p95 2.31 s, max 9.85 s. pg_cron does not start a run while the last one is still going, so
every run over 1 s costs the next second.

- **The other jobs are not the main cause.** In minutes with no other job running, arrivals still made
  46-55 runs, with p50 0.6-0.9 s and p95 1.5-2.7 s. The other jobs (stats at :06/:21/:36/:51, reconcile at :07,
  the game-day drift run) push their minute down to 20-37 runs on top of that.
- **The one failure** (04:07:23) was a deadlock on a `players` row against the hourly reconcile
  (`voyage.settle`'s ships update, FK KEY SHARE). Separately, reconcile itself hit its 120 s statement timeout
  in 6 of the last 8 hours, in `npc_compact`'s `delete from public.events`. That is a separate defect, and it is queued.
- **What a run costs follows what it does.** Over 30 min, 1,308 runs were joined to the events and ledger
  rows each one wrote at its own instant:

| bucket | runs | avg s | events | ledger rows |
|---|---|---|---|---|
| < 0.3 s | 77 | 0.21 | 0.6 | 0.3 |
| 0.3-0.5 | 250 | 0.41 | 3.0 | 2.2 |
| 0.5-0.7 | 291 | 0.60 | 5.5 | 4.8 |
| 0.7-1 | 234 | 0.84 | 8.4 | 7.2 |
| 1-1.5 | 210 | 1.21 | 10.1 | 8.6 |
| 1.5-2 | 104 | 1.74 | 11.5 | 9.9 |
| 2-3 | 85 | 2.38 | 15.5 | 13.8 |
| 3-5 | 40 | 3.69 | 19.8 | 17.1 |
| > 5 | 17 | 6.87 | 43.2 | 39.3 |

  Runs that wrote no event and no ledger row (sea-days only): p50 0.53 s. The ask slot (every 15th second)
  made no difference. Per second, prod runs ~1.3 arrivals, 1.3 departures and ~1 trade.
- `pg_stat_statements.track = top` and `track_functions = none`, so the inner statements are not visible
  on prod.

## The cause

pg_cron (`cron.use_background_workers = off`) opens a **new connection, and so a new backend, for every run**.
A new backend has nothing cached. Every relation is loaded into its relcache again. Every PL/pgSQL function on
the arrival path (settle, advance, the route core, the trade doors, depart, insurance, provisioning) is compiled
again, and every statement in it is planned again. That happens every second, for runs whose own work takes
milliseconds. Going from 15 s to 1 s (0242) made fifteen times as many cold starts.

Local (PGlite, head 0247, prod's boolean switches, 835 merchants at sea):

- **A warm session**, 240 seconds of the clock run second by second: p50 62 ms, p95 195 ms, ~7 ms per fleet
  touched (2,585 fleets, 2,187 sea-days). That is wasm, which is slower per statement than a server, and it is
  still ten times faster per run than prod.
- **Cold vs warm**, the same second's run from the same dumped state, 15 samples:

| at | fleets | fresh engine (= a pg_cron run) | same engine, 2nd time |
|---|---|---|---|
| 61-63 | 1-2 | 369-537 ms | 125-185 ms |
| 121-123 | 9-17 | 815-1,187 ms | 450-778 ms |
| 181-183 | 10-26 | 625-1,131 ms | 353-753 ms |
| 241-243 | 5-15 | 566-891 ms | 230-544 ms |
| 301-303 | 4-10 | 515-818 ms | 266-377 ms |

  An empty run takes 31 ms cold and 7 ms warm. After one pass a fresh engine is still 5-6× slower per fleet
  than a session that has run for minutes. Its catalog caches, buffers and plans fill in path by path.
- `pg_stat_user_functions` (warm, by self time): crew_terms, world.ship_stats, wc (223 k calls), crew_pct,
  house_skill_scopes, voyage.settle. These are spread thin, and none dominates the way 0247's readers did.

Compute capacity is not the limit: the same work in one warm session fits in a fraction of a second.

## The fix (0248)

- `public.tick_arrivals_each_second()` is a procedure, with no definer and no SET, like
  `tick_market_drift_each_port`. **One session runs `public.tick_arrivals()` once a second until its minute
  ends.** Each run gets its own transaction, with a commit before and after, so its `now()` is that second's,
  just as a pg_cron run's was.
  - A beat waits for its whole second. A beat that ran past the next second starts at once.
  - A run that raises is rolled back alone, with a warning, and the next second runs.
  - It stops within a second when the job is switched off (`cron.job.active`, read every beat), so
    `unwind_the_clock()` and the deploy wait about a second, not a minute.
- `public.arrivals_beats` keeps one row per second of the hour (3,600 at most, overwritten), for the job's own
  record: instant, ms, fleets, days, asked, error. pg_cron now writes one `job_run_details` row a minute
  instead of 60.
- Cron: `byeharu-voyage:arrivals` changes from `'1 seconds'` / `select public.tick_arrivals()` to `'* * * * *'` /
  `call public.tick_arrivals_each_second()`. Name, owner and active flag are kept.
- **`public.tick_arrivals` and everything it calls are untouched.** The self-assert checks that its
  definition md5, ACL, volatility, definer and config are identical, so the game results are the same function
  at the same instants.

Rollback: `select cron.alter_job((select jobid from cron.job where jobname = 'byeharu-voyage:arrivals'), schedule := '1 seconds', command := 'select public.tick_arrivals()');`

## Measurements

Local (PGlite, cached prefix p0236 + 0248):
- 0248 self-assert ok.
- `call public.tick_arrivals_each_second(40)` on the merchant world: 40 beats, one per whole second.
  The first four worked through the 100 s backlog the switch left (10 s budget each). After that the beats landed
  on .000-.002 of each second, p50 81 ms (wasm), with 0-5 fleets each and no errors.

Prod before: see the table above (1 h to 07:40 UTC: 2,864 runs, about 48 a minute, p50 0.71 / p95 2.31 / max 9.85 s, 1 failed).

Prod after: (below, after the deploy)
