-- DB-HEALTH GATE (docs/DATABASE_BUDGET.md, "The deploy gate"). A PROD CHECK: read-only, ONE statement, cheap.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/db-health/gate.sql
-- bv-deploy.sh runs it once BEFORE it stops the clock (and refuses to deploy when gate_ok is false), and once after the wind.
-- It reads ONLY the catalog (pg_class, pg_index, pg_namespace), the statistics views (pg_stat_activity, pg_stat_user_tables,
-- pg_stat_progress_vacuum) and the arrivals beat's ring (public.arrivals_beats: 3,600 rows at most, one a second of the hour).
-- No game table is scanned, and the only functions called are stable or immutable (now, pg_backend_pid, percentile_cont, round,
-- jsonb_build_object). The database size is the catalog's page count (pg_class.relpages, refreshed by vacuum and analyze), not
-- pg_database_size(), which is volatile: it can lag a few percent behind the files on disk.
--
-- THE GATE REFUSES (gate_ok false) WHEN ANY OF THESE IS TRUE (the limits are docs/DATABASE_BUDGET.md's):
--   beat_mean_ms   > 2,000   the arrivals beat's mean over the last 5 minutes (normal: 100-700 ms; 2026-11-14 at worst: ~12,000).
--                            No beat at all in 5 minutes (the clock is stopped) does not refuse; `beats` 0 says so.
--   database_mb    > 1,500   the whole database by the catalog (921 after the runbook of 2026-11-14; 2,826 before it).
--   io_waiting     > 5       sessions waiting on the disk right now (wait_event_type IO). On 2026-11-14 every session did.
-- PRINTED, NOT REFUSED ON: beat p95, the oldest open transaction, invalid indexes, the five biggest tables' dead-row share,
-- tables autovacuumed / autoanalyzed in the last hour (a table counts once however many passes it had) and passes running now.
begin transaction read only;
with beat as (
  select count(*) as beats, round(avg(b.ms)) as mean_ms,
         round((percentile_cont(0.95) within group (order by b.ms))::numeric) as p95_ms,
         count(*) filter (where b.error is not null) as errors
    from public.arrivals_beats b
   where b.at > now() - interval '5 minutes'
), size as (
  select (sum(c.relpages)::numeric * 8192 / 1048576)::int as mb
    from pg_class c
   where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')
), act as (
  select count(*) filter (where a.wait_event_type = 'IO' and a.state = 'active') as io_waiting,
         count(*) filter (where a.state = 'active') as active,
         coalesce(round(extract(epoch from max(now() - a.xact_start) filter (where a.xact_start is not null and a.state <> 'idle'))), 0) as oldest_xact_s
    from pg_stat_activity a
   where a.pid <> pg_backend_pid()
), big as (
  select c.oid, n.nspname || '.' || c.relname as tbl,
         ((c.relpages + coalesce(t.relpages, 0)
           + coalesce((select sum(ic.relpages) from pg_index i join pg_class ic on ic.oid = i.indexrelid where i.indrelid = c.oid), 0))::numeric
          * 8192 / 1048576)::int as mb
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    left join pg_class t on t.oid = c.reltoastrelid
   where c.relkind = 'r' and n.nspname not in ('pg_catalog', 'information_schema')
   order by mb desc
   limit 5
), g as (
  select (select mean_ms from beat) as beat_mean, (select mb from size) as db_mb, (select io_waiting from act) as io
)
select
  (coalesce(g.beat_mean, 0) <= 2000 and g.db_mb <= 1500 and g.io <= 5) as gate_ok,
  concat_ws('; ',
    case when g.beat_mean > 2000 then 'the beat is slow: mean ' || g.beat_mean || ' ms over 5 min (limit 2,000)' end,
    case when g.db_mb > 1500 then 'the database is over budget: ' || g.db_mb || ' MB (limit 1,500)' end,
    case when g.io > 5 then g.io || ' sessions wait on the disk now (limit 5)' end) as gate_why,
  'beat ' || coalesce(g.beat_mean::text, 'none') || ' ms mean / ' || coalesce((select p95_ms from beat)::text, '-') || ' ms p95 ('
    || (select beats from beat) || ' beats in 5 min); db ' || g.db_mb || ' MB; io waits ' || g.io
    || '; oldest xact ' || (select oldest_xact_s from act) || ' s' as gate_line,
  jsonb_build_object(
    'at', now(),
    'beat', (select jsonb_build_object('beats', beats, 'mean_ms', mean_ms, 'p95_ms', p95_ms, 'errors', errors, 'mean_under', 2000) from beat),
    'database_mb', jsonb_build_object('mb', g.db_mb, 'under', 1500, 'how', 'sum of pg_class.relpages'),
    'sessions', (select jsonb_build_object('io_waiting', io_waiting, 'io_under', 6, 'active', active, 'oldest_xact_s', oldest_xact_s) from act),
    'invalid_indexes', (select coalesce(jsonb_agg(i.indexrelid::regclass::text), '[]'::jsonb) from pg_index i where not i.indisvalid),
    'biggest5', (select jsonb_agg(jsonb_build_object('table', b.tbl, 'mb', b.mb, 'live', s.n_live_tup, 'dead', s.n_dead_tup,
                                                     'dead_pct', round(100.0 * s.n_dead_tup / greatest(s.n_live_tup + s.n_dead_tup, 1), 1),
                                                     'last_autovacuum', s.last_autovacuum) order by b.mb desc)
                   from big b left join pg_stat_user_tables s on s.relid = b.oid),
    'autovacuum', jsonb_build_object(
      'tables_vacuumed_last_hour', (select count(*) from pg_stat_user_tables s where s.last_autovacuum > now() - interval '1 hour'),
      'tables_analyzed_last_hour', (select count(*) from pg_stat_user_tables s where s.last_autoanalyze > now() - interval '1 hour'),
      'running_now', (select count(*) from pg_stat_progress_vacuum))
  ) as r
from g;
commit;
