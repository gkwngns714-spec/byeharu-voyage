# 2026-11-07: the baseline gate samples a quiet clock (chain baseline S1, still dark)

> **CI machinery only:** `.github/workflows/chain-baseline.yml`, `scripts/db/baseline/baseline.mjs`, `docs/CI.md`.
> No migration is touched (`supabase/migrations/` is byte for byte as on main), `scripts/db/baseline/pglite-allow.txt`
> is untouched, prod is not touched, and the baseline is still an artifact that is never committed.

## What was red

The nightly (`chain-baseline.yml`) was red four nights running: 41745153220 (11-04), 41942167566 (11-05),
42137738026 (11-06), 42314406184 (11-07). Last green: 41562338360 (11-03).

**Only the last one is this defect.** The first three died earlier, in D-chain's from-zero apply, on migration
0226's self-assert. That is a different defect and it is **not fixed here** (see "Not fixed here" below).

## The cause (run 42314406184, from its log and its artifact)

The gate compared D-chain with D-base, and the only differences were two lines:

```
< T public.contract_wind_runs 0            > T public.contract_wind_runs 1 ada88b47…
< T public.trade_contracts 4 18290932…     > T public.trade_contracts 4 46084495…
```

The chain's last migrations leave **6 of its 19 pg_cron jobs active**: `battles`, `cargo-ships`, `contract-wind`,
`history`, `navy`, `npc-refits` (scheduled by 0309, 0315, 0316, 0322, 0323, 0331; none of them stops its job, which is
what 0078 says a chain must do). Four of the six are `* * * * *`. `contract-wind` writes one receipt row a minute
into `public.contract_wind_runs` and expires and posts `public.trade_contracts`.

From the step times in the run's log:

| time (UTC, 11-07) | what |
|---|---|
| 01:04:03 – 01:04:25 | migrations 0309 .. 0334 start applying (0315, which schedules `contract-wind`, between 01:04:10 and 01:04:13); 22 s from the first to the last |
| 01:04:47 | `supabase start` returns |
| 01:04:50 – 01:05:12 | "D-chain — its lines": content-exact is read first, content-stable second |
| **01:05:00** | **the first minute boundary after `contract-wind` was scheduled: it fires, receipt slot 65 at 01:05:00.013614** |
| 01:05:12 – 01:05:24 | "Build": the pg_dump carries the receipt and the changed `trade_contracts` |
| 01:05:24 – | D-base loads that dump |

D-chain's own two files show it: `content-exact` (read before 01:05:00) has `contract_wind_runs 0`, its
`content-stable` (read after) has `contract_wind_runs 1`. D-base is a load of the dump, so it read 1.

So the gate sampled one database at three instants (lines, dump, D-base's lines) while a job rewrote tables between
them. It would fail on any night a minute boundary fell between the first and the last of those, and it will fail
again for every new job that writes data.

**Why D-chain had 0 runs in its 74 minutes of apply although the job was active for the tail (measured, not guessed):**
the job did not exist for 74 minutes. 0315 scheduled it about 01:04:12, which is 35 s before `supabase start` returned
(01:04:47) and 48 s before the first minute boundary (01:05:00). No boundary fell inside the apply, so nothing had fired
when the lines began. It is not that pg_cron waits for `supabase start`, and no migration removes a receipt. A chain whose tail crosses a boundary would show earlier runs; the new `quiesce` report prints
`cron.job_run_details` per job (count, first and last start) right after `supabase start`, so each run settles it.

## The design

The samples are made quiet, and the quiet is proven. No list of "the tables cron writes" exists anywhere.

1. **D-chain: `quiesce`** (new step, right after `supabase start`, before the first sample).
   - It reads `cron.job` as the chain left it and writes it to `d-chain/cron-as-left.json` (the file `build` reads) and
     `d-chain/cron-as-left.txt` (the cron lines, flags included). This happens before anything is touched.
   - It pauses **every active job in `cron.job`** with `cron.alter_job(jobid, active := false)`, waits 3 s for the
     launcher to re-read, waits until no `cron.job_run_details` row is `starting`, `connecting`, `sending` or `running`
     (the wait `scripts/ops/bv-deploy.sh` does), checks that no job is active, and marks the last run id
     (`d-chain/quiet-mark.json`).
   - It prints the pg_cron report (settings, processes, jobs, runs per job).
   - *Not `public.unwind_the_clock()`:* it is the same primitive, but it stops only the names `clock_jobs()` matches
     (`byeharu-voyage:%`, `voyage-tick-%`). The gate has to stop whatever is in `cron.job`, and a name pattern is a hand-kept
     list by another name. The check after the pause (no job active at all) is what makes it complete.
2. **D-chain: `quiet-check`** (new step after the build). Fails, naming the job and the time, if any job is active or any
   run started after the mark, i.e. during the lines, the dump or the row manifest.
3. **D-base is born paused.** The baseline's cron block schedules every job and leaves every job **inactive**. A job
   cannot fire between the load and our first step, because none is active. `supabase start` returns about 40 s after
   the file starts applying (run 42314406184: 01:05:53 to 01:06:33), so a baseline that started the clock at load would
   almost always have fired, at the next boundary, before a workflow step could pause it. `quiet-check` runs on D-base before and after its lines with no mark: any run since
   the database was created fails the job. The baseline's closing self-assert now also states it: `cron.job` has no
   active job (receipt: "N cron job(s) defined and none running").
4. **The flags the chain left running travel as DATA, not as load-time state.** `build` writes
   `baseline-clock.sql` (a separate file, one `cron.alter_job(..., active := true)` per job in `cron-as-left.json`).
   After the last sample the workflow applies it to D-base, reads `cron.job` back (`d-base/cron-as-left.txt`) and
   compares it with `d-chain/cron-as-left.txt`, the live read taken before the pause. A wrong name, a missed flag or a
   clock file that does not apply is a red.
5. `build` refuses to run unless the live `cron.job` is exactly the jobs saved before the pause (name, schedule, command)
   and none is active, so the dump cannot be taken from a clock that is running.

## What the gate proves now, exactly

Unchanged: catalog lines, content-exact (every row, uuids and clocks included, sequences, routines, ACLs, policies, roles,
default ACLs, namespaces), content-stable, the cron lines, D-base = D-pglite beyond `pglite-allow.txt`, 0018's default ACL
by behaviour with its positive control, proof 03, the PGlite receipt. Nothing is excluded, nothing is skipped, no compare
was removed.

Added: the as-left cron compare, the two cron-fired-during-sampling checks, build's refusal of a running clock, and the
closing self-assert's "none running".

**What it no longer proves, said plainly:** that `baseline.sql` ALONE, applied to a fresh database, leaves the chain's
active flags. It now leaves them all off. `baseline.sql` + `baseline-clock.sql` leaves exactly the chain's flags, and the
gate proves that pair.

## What S2 needs to know (changes what a fresh world looks like)

1. **A world loaded from `baseline.sql` has no job running; the chain's own fresh world has six.** `build.json` names them
   (`cron_running_as_left`) and `baseline-clock.sql` starts exactly those. S2 decides: append that block to the committed
   file (a fresh world equals the chain's, jobs ticking from the commit), or leave the clock stopped. Stopped is what
   0078 says a database built from the chain should be ("a database built from scratch now ends with its clock stopped")
   and what `docs/CHAIN_BASELINE.md` §1.2 says the baseline does ("jobs start inactive … `wind_the_clock()` remains the
   one switch"); the six running jobs are 0309..0331 not following that rule. `wind_the_clock()` starts all 19, not only the six.
2. The baseline carries any receipt a job wrote between the last migration and the pause. `quiet-mark.json` says how many
   runs there were (`runs_before_pause`). Cut S2's baseline from a from-zero run where it is 0.
3. While the six jobs stay active at the end of the chain, the tail migrations after them apply with ticks running
   (0078's hazard). The tail is 22 s today, shorter than a minute; a longer tail can cross a boundary. Not changed here.

## Not fixed here: three of the four reds were migration 0226, not this

Runs 41745153220, 41942167566 and 42137738026 failed inside D-chain's apply, before any baseline code ran:

```
ERROR: 0226 self-assert FAIL: the day folded day 2026-11-0N o 10.00 h 13.00 l 10.00 c 13.00 n 4 (SQLSTATE P0001)
```

at 01:00:27, 01:07:55 and 01:41:07 UTC. 0226 plants two finished hours at `date_trunc('hour', now()) - interval '26 hours'`
(`supabase/migrations/20260818000226_a_price_is_kept_for_years_both_ways.sql:612`) and expects one day row over both
(n 8). At UTC hour 01 the first planted hour is 23:00 and the second 00:00, which are two days, so the day folds into
two rows of n 4. The assert only passes when `now()` is not in UTC hour 01. Run 42314406184 applied 0226 at 00:59:39 UTC,
21 s before the hour began, and so reached the baseline gate. GitHub starts the `47 19 * * *` schedule about four and a half
hours late (these runs were created 00:13 to 00:33 UTC), and the from-zero apply reaches 0226 35 to 67 minutes after the
start, so the nightly lands in that hour often. **Until this is handled the nightly stays red on those nights whatever this
change does.** It is a frozen migration, so the fix is a patch in `src/lib/db/frozenAsserts.ts` (the one patch list; 0315
has one), which is chain machinery with its own CI cost, and it is not in this change.

## Measured on the real pg_cron (first snapshot-mode run, 42326939657, commit 70456fe)

- pg_cron in the CI Supabase: `cron.use_background_workers = off`, `cron.launch_active_jobs = on`, `cron.log_run = on`,
  one process `pg_cron launcher`. `cron.job_run_details` is populated with `succeeded` rows and start times, so the
  guards have something real to read. (In snapshot mode it carries main's history: 42 rows, last start 01:29:00, before
  this database's postmaster started at 02:02:08.)
- `quiesce`: 19 jobs, 6 active as left; paused; no run in flight; marked run id 532 at 02:02:48.
- D-chain's lines (02:02:48 to 02:03:12) and the dump (to 02:03:24) contain the 02:03:00 boundary; `quiet-check` at 02:03:24:
  no job active, no run after 532. D-base's lines (02:04:38 to 02:05:03) contain the 02:05:00 boundary: no run since the
  database was created. With the old workflow those four every-minute jobs were active across both.
- The gate: catalog, content-exact, content-stable, cron and the as-left cron lines all EQUAL; the PGlite receipt reads
  "177 tables / 256735 rows equal the chain at 0335, 19 cron job(s) defined and none running".

## Validation

(run ids below once the runs are green)
