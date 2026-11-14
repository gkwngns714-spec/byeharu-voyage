# The database budget

**In one paragraph.** The game runs on Supabase's smallest database: about 1 GB of memory, 2 processor cores, 60 connections, and a
disk that is fast only for a short allowance each day. On 2026-11-14 the game asked the disk for more than that, the allowance ran
out, and for about two and a half hours every ship, merchant and job waited on the disk (the arrivals beat went from 0.6 s to 12 s).
The causes had been building for weeks and nobody was watching. So now: the database has a size limit and a speed limit (below);
every new migration is checked by CI for the four mistakes that caused it; a deploy refuses to run while the database is unwell;
and the lead reads one health check once a day. The story: `docs/dev-log/2026-11-15-db-guard.md`.

## The instance (what we have)

| | | what running out looks like |
|---|---|---|
| Memory | ~1 GB, of which the cache (`shared_buffers`) is 256 MB; with the operating system's file cache, about **700 MB of data can stay in memory** | reads that used to come from memory come from the disk; the disk then becomes the limit |
| Cores | 2 | every job and player call queues; CPU near 100 % on the dashboard |
| Connections | 60 (`max_connections`) | "too many connections"; cron jobs fail with "job startup timeout" |
| Disk speed | a low **baseline** plus a daily **burst allowance**; the exact figures are on the Supabase dashboard (project → Reports / Database → Disk IO budget) | when the allowance is spent the disk drops to baseline: sessions wait on `IO` (`DataFileRead`, `DataFileWrite`, `WalWrite`), the beat slows to seconds, merchants pile up in port, cron jobs time out. That was 2026-11-14 |

A bigger compute size raises all four. It costs money and is the owner's decision alone.

## The budget (what we allow ourselves)

1. **Database size under 1,500 MB.** It was 2,826 MB on 2026-11-14 and 921 MB after the runbook. Warn at 1,200.
2. **The hot set fits in about 700 MB.** The ten biggest tables (heap plus indexes) are what the game reads all day; if they no longer
   fit in memory, every read goes to the disk.
3. **No job rewrites a whole table every minute.** (The market drift did: 156,621 rows a minute.) A per-minute job writes **at most
   about 5,000 rows a run**; anything more is spread over runs (as `drift_spread_runs` does) and its migration says why.
4. **Every table has a retention rule**, or is bounded by construction (one row a harbour, a ring of 3,600 slots).
5. **Autovacuum scales with the table.** A fixed threshold with scale factor 0 is allowed only at 20,000 dead rows or more; below that
   a busy table is vacuumed every few minutes, and each pass reads the whole table from disk (that was ~3,000 passes a day).
6. **Production reads are part of the budget.** A builder's analytic read costs the same disk as the game. At most ONE builder reads
   production at a time, a handful of targeted reads, and none while the gate below is red.

## Rules for a migration (CI enforces them: `tests/db.budget.spec.ts`)

For every migration after 0418 the spec fails the PR, in the required `build` check, unless the line it asks for is next to the
statement (in the statement, or in the comment block right above it):

| rule | what fails | the line that makes it pass |
|---|---|---|
| a. autovacuum | `autovacuum_vacuum_threshold` / `autovacuum_analyze_threshold` under **20,000** (or a value the reader cannot see, like `%s`) with the matching scale factor 0; or `autovacuum_enabled = false` | `-- budget: <reason, 10+ characters>` |
| b. retention | `CREATE TABLE` (not `TEMP`) | `-- retention: <rule or knob name>` or `-- retention: none, bounded by <why>` (next to it, or anywhere in the file naming the table) |
| c. cron | `cron.schedule(`, `cron.alter_job(`, `update cron.job … schedule`: any new job, any reschedule, anything in seconds | `-- budget: <expected rows touched per run, with a number and the word "rows">` |
| d. fillfactor | `fillfactor` under **50** | `-- budget: <reason>` |

The floors are constants at the top of the spec. The line is not a password: it is read in review, and it must be true. Also, not
checked by CI but required: a migration that adds load (more ships, more harbours, a faster job) says in its PR body how many extra
rows a minute it writes, and the lead reads the gate before deploying it.

## The deploy gate (`~/bin/bv-deploy.sh`, source `scripts/ops/bv-deploy.sh`)

Before it stops the clock, the deploy script runs one cheap read-only check, `scripts/ops/harness/db-health/gate.sql` (the catalog,
the statistics views and the beat's 3,600-row ring; no game table), and **refuses, with nothing pushed and the clock untouched**, when:

- the arrivals beat's mean over the last 5 minutes is **over 2 s**;
- the database is **over 1,500 MB**;
- **more than 5** sessions are waiting on the disk right now;
- or the PR's `build` check (which runs the budget spec) is not green.

The override is explicit and logged: `BV_DEPLOY_FORCE=1 BV_DEPLOY_REASON="why" ~/bin/bv-deploy.sh <pr>`; the reason is written into
`~/bv-push-logs/push-<version>.log`. After the push and the wind the script prints the same read once as the after-check.

## Once a day (the lead)

`npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/db-health/daily.sql`

Read its `over` list. Empty means nothing to do. Each line names the figure over budget and what it means (beat, size, disk waits, a
long transaction, an invalid index, a table whose vacuum is behind, the hot set over 700 MB, the cache hit rate under 99 %, an
autovacuum or fillfactor setting under the floor, a cron job in seconds). Act on it that day; for the retention windows table by
table, run `scripts/ops/harness/slim-db/health.sql`. There is deliberately no scheduled health job: it would cost the database itself.

## Signs of trouble, and the first three things to do

Signs: the beat over 2 s (the game feels slow; arrivals late); merchants waiting in port; cron "job startup timeout"; the Supabase
dashboard's disk IO budget falling; the database growing day on day.

1. **Stop adding load.** Tell every builder: no production reads, no deploys, no knob changes, until the gate is green. (Every extra
   read spends the same disk.)
2. **Read, once each, in this order** (each is one read-only statement):
   - `scripts/ops/harness/db-health/gate.sql`: how bad (beat, size, disk waits).
   - `scripts/ops/harness/db-health/waits.sql`: who waits on what right now, and which autovacuum is running.
   - `scripts/ops/harness/db-health/daily.sql`: which table or setting is over budget.
3. **Tell the owner** what the three reads say and propose one change: a migration that cuts the job or the table named (the
   2026-11-14 fixes were 0409, 0412, 0413, 0416), or maintenance from the runbook. A bigger compute size is his call.

Do not poll: read once, decide, then read once more after the change.

## Maintenance

`scripts/ops/harness/slim-db/RUNBOOK.md`: plain `VACUUM`, `REINDEX INDEX CONCURRENTLY` (no blocking lock), and `VACUUM FULL` (with
the clock stopped for the tables the beat writes). Every command there is the owner's to approve.
