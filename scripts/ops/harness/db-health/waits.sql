-- DB-HEALTH WAITS (docs/DATABASE_BUDGET.md, "Signs of trouble", step 2): WHO is waiting on WHAT, right now. A PROD CHECK: read-only, ONE statement.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/db-health/waits.sql
-- Reads pg_stat_activity, pg_stat_progress_vacuum and cron.job only: no game table, no volatile function. Run it ONCE, not in a loop.
-- HOW TO READ IT (2026-11-14 for comparison: every session waited on IO / DataFileRead, DataFileWrite or WalWrite, and an autovacuum
-- of a 372 MB table had read for 100 s):
--   by_wait     sessions grouped by what they wait on. IO rows dominating = the disk is the limit (budget spent or a heavy reader).
--               Lock rows = something holds a lock (look at `sessions` for the oldest xact).
--   sessions    each active session: who (application_name: pg_cron's jobs say so; a builder's read is `postgres` via the CLI),
--               what it waits on, how long its statement and transaction have run, and the first 120 characters of the statement.
--   vacuums     autovacuum passes running now: which table, which phase, how far.
begin transaction read only;
with s as (
  select a.pid, a.backend_type, a.usename, a.application_name, a.state, a.wait_event_type, a.wait_event,
         round(extract(epoch from now() - a.query_start)) as query_s,
         round(extract(epoch from now() - a.xact_start)) as xact_s,
         left(regexp_replace(a.query, '\s+', ' ', 'g'), 120) as query
    from pg_stat_activity a
   where a.pid <> pg_backend_pid() and a.state is distinct from 'idle'
)
select jsonb_build_object(
  'at', now(),
  'by_wait', (select jsonb_agg(jsonb_build_object('wait', w.wt, 'sessions', w.n) order by w.n desc)
                from (select coalesce(s.wait_event_type || '/' || s.wait_event, 'running') as wt, count(*) as n from s group by 1) w),
  'sessions', (select jsonb_agg(jsonb_build_object('pid', pid, 'type', backend_type, 'user', usename, 'app', application_name,
                                                   'wait', wait_event_type || '/' || wait_event, 'query_s', query_s, 'xact_s', xact_s,
                                                   'query', query) order by xact_s desc nulls last) from s),
  'vacuums', (select jsonb_agg(jsonb_build_object('table', p.relid::regclass::text, 'phase', p.phase,
                                                  'scanned_pct', round(100.0 * p.heap_blks_scanned / greatest(p.heap_blks_total, 1), 1)))
                from pg_stat_progress_vacuum p),
  'cron_active', (select count(*) from cron.job j where j.active)
) as r;
commit;
