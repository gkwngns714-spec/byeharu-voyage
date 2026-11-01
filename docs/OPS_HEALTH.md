# OPS HEALTH — how this game is kept from silently getting slow again (2026-11-01)

**The incident.** On 2026-10-30 (~00:35 UTC) the market was set to tick every minute (`game_day_seconds` 2880 → 60, `drift_slot_seconds` 900 → 60, drift cron
`*/10` → `* * * * *`; `docs/dev-log/2026-10-30-drift-every-minute.md`). That made the database rewrite its biggest table (`port_goods`, 154,734 rows) 8–16× more often on the
smallest compute, so the disk saturated; the Stats count, an unbounded job already near its 120 s limit, died on 10-30 18:21 and nobody saw it for a day; its backlog (a 2.1 M-row
journal) made every Stats read take a minute; the laps table was never given the autovacuum settings its siblings had, so the count's 24 h merchants read did a heap fetch per row.
Nothing alarmed: failures lived only in `cron.job_run_details`.

## 1. Run `bash scripts/ops/health.sh` at the START of every session and after EVERY deploy
Read-only. It prints the numbers and an `ALERT:` line for each threshold that trips:
| alert | meaning / first move |
|---|---|
| database restarted < 6 h ago | outage or crash; caches are cold; look for a gap in `cron.job_run_details` |
| cron job failing > 20 % over 2 h | read its last `return_message`; a timeout names the statement |
| Stats count older than 45 min | `public.stats_runs`, the last `byeharu-voyage:stats` runs |
| journal > 300,000 rows | `world.stats_now()` sums all of it per call; check the count and the drain |
| big table < 90 % all-visible | index-only scans turn into heap fetches; give the table the `scale_factor = 0, threshold ~500–2000` autovacuum options its siblings have |
| table with more dead rows than live | bloat; rewrite (CLUSTER) with a fillfactor, as 0292 did for `port_goods` |
| WAL > 70 MB/min (30 s window) | the write path is saturating the disk (the post-0292 baseline is ~47 MB/min: the every-minute market itself); look at the minute jobs and what else started writing |
| port_goods updates < 80 % HOT | a long snapshot is pinning dead versions, or the table needs the rewrite again |

## 2. The CADENCE-CHANGE PROTOCOL (the rule the incident was missing)
Any change to `game_day_seconds`, `drift_slot_seconds`, a drift/regen knob or ANY cron expression is a load change, not a tweak. Before it:
1. **Write the new write rate down.** `port_goods` has 154,734 rows; a tick rewrites every row whose slot/day advanced, so one tick a minute = ~154 k row versions a minute.
2. **Measure BEFORE:** `bash scripts/ops/health.sh` (WAL MB/min, cron avg/max).
3. **Change, wait 30 minutes, run `health.sh` again.** A new ALERT or a doubled cron average is a stop-and-revert signal, not something to wait out.
4. **Keep the revert ready** (for the 10-30 move: 900 / theta 0.90 / sigma 0.02 / clamp 0.20 / 2880 / `*/10 * * * *`). Owner-directed changes are still measured and reported.

## 3. Standing design rules this incident wrote
- Every periodic job does a BOUNDED amount of work per run and carries what is left to the next run (the Stats count, 0290: window cap, fold batches, journal drain, a time budget).
- Every table that is updated or deleted at volume carries per-table autovacuum options and, if rewritten wholesale each minute, a fillfactor (0291 laps, 0292 port_goods).
- Derived caches (the stats journal) may always be wiped and re-seeded from the world (0293); history tables are not caches and are never wiped to save time.

## 4. The migration runner is NOT a transaction block (measured 2026-11-01; applies to `supabase db push` and `supabase migration up`)
A migration file is sent statement by statement in the CLI's pipeline, not inside BEGIN … COMMIT. PGlite (the local proof) runs the file as one block and hides all of this, so ONLY the
real-Postgres CI job (`disposable-chain`) and the prod push show it. Learned the hard way (0292, 0293):
- A bare top-level `LOCK TABLE` is refused: `LOCK TABLE can only be used in transaction blocks`. Put every statement that needs the lock inside ONE `DO` block, together with what it protects.
- A `create temp table … on commit drop` did not survive past the table rewrite (`relation "clock_0292" does not exist`). Use session-lived scratch tables and drop them in the last assert.
- `ANALYZE`/`VACUUM`-style utility statements are not part of a migration; CLUSTER of one named table, ALTER TABLE and TRUNCATE work. Raise `statement_timeout` with a session-level
  `set_config(..., false)` in the guard and `reset` it at the end of the file (a transaction-local setting does not reach the next statement).
- Never dispatch `migrations-apply-proof.yml` by hand: a manual dispatch applies the WHOLE chain from zero and every PR's `disposable-chain` waits for it. After a `bv-deploy.sh` merge
  (which fires no workflow) dispatch ONLY `acceptance.yml --ref main`.
