-- DB-HEALTH DAILY (docs/DATABASE_BUDGET.md, "Once a day"). THE one read the lead runs once a day. A PROD CHECK: read-only, ONE statement.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/db-health/daily.sql
-- There is deliberately NO scheduled health job: a job would itself cost the database every time it ran.
-- It reads only the catalog, the statistics views, cron.job (two dozen rows) and the arrivals beat's ring (3,600 rows at most).
-- No game table is scanned; only stable / immutable functions are called.
--
-- READ `over` FIRST: one line for every figure over its budget. Empty = nothing to do. Any line = act on it today (the doc says how).
--   beat_mean_ms        > 2,000 over the last 10 minutes                      (the deploy gate's limit)
--   database_mb         > 1,500 (catalog pages)                              (the ceiling)
--   database_mb         > 1,200                                              (a warning: the ceiling is near; find the growing table)
--   io_waiting          > 5 sessions on the disk now
--   oldest_xact_s       > 300: a transaction open five minutes holds back every vacuum
--   invalid_indexes     any: a REINDEX CONCURRENTLY was interrupted (RUNBOOK step 2: drop the _ccnew and run it again)
--   dead_pct            > 20 on a table over 50 MB: its vacuum is behind
--   hot_set_mb          > 700: the ten biggest tables' heap + indexes no longer fit the ~700 MB of cache the instance has
--   cache_hit_pct       < 99 since the statistics were reset: the game reads the disk
--   autovac_low         a table over 50 MB set to a fixed autovacuum threshold under 20,000 with scale factor 0, or autovacuum off
--   fillfactor_low      a table or index under fillfactor 50 (port_goods at 30 is known and left out: RUNBOOK 3b, the owner's call)
--   cron_sub_minute     a cron job scheduled in seconds
-- THE REST is context for the line that is over: the ten biggest tables, the cron jobs, the disk reads by who reads.
-- For the retention windows table by table (city_wants, stats, laps, the merchants' books): scripts/ops/harness/slim-db/health.sql.
begin transaction read only;
with beat as (
  select count(*) as beats, round(avg(b.ms)) as mean_ms,
         round((percentile_cont(0.95) within group (order by b.ms))::numeric) as p95_ms,
         count(*) filter (where b.error is not null) as errors
    from public.arrivals_beats b
   where b.at > now() - interval '10 minutes'
), size as (
  select (sum(c.relpages)::numeric * 8192 / 1048576)::int as mb from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')
), act as (
  select count(*) filter (where a.wait_event_type = 'IO' and a.state = 'active') as io_waiting,
         coalesce(round(extract(epoch from max(now() - a.xact_start) filter (where a.xact_start is not null and a.state <> 'idle'))), 0) as oldest_xact_s
    from pg_stat_activity a where a.pid <> pg_backend_pid()
), tbl as (
  select c.oid, n.nspname || '.' || c.relname as tbl, c.reltuples::bigint as rows, c.reloptions,
         (c.relpages::numeric * 8192 / 1048576)::int as heap_mb,
         ((c.relpages + coalesce(t.relpages, 0)
           + coalesce((select sum(ic.relpages) from pg_index i join pg_class ic on ic.oid = i.indexrelid where i.indrelid = c.oid), 0))::numeric
          * 8192 / 1048576)::int as mb
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    left join pg_class t on t.oid = c.reltoastrelid
   where c.relkind = 'r' and n.nspname not in ('pg_catalog', 'information_schema')
), top10 as (
  select t.*, s.n_live_tup as live, s.n_dead_tup as dead, s.last_autovacuum, s.autovacuum_count,
         round(100.0 * s.n_dead_tup / greatest(s.n_live_tup + s.n_dead_tup, 1), 1) as dead_pct
    from tbl t left join pg_stat_user_tables s on s.relid = t.oid
   order by t.mb desc limit 10
), opt as (
  select t.tbl, o.k, o.v
    from tbl t, lateral (select split_part(x, '=', 1) as k, split_part(x, '=', 2) as v from unnest(t.reloptions) x) o
), autovac_low as (
  select a.tbl, a.k || '=' || a.v as setting
    from opt a
   where (select t.mb from tbl t where t.tbl = a.tbl) > 50   -- a pass over a small table costs little; the 11-14 harm was 200-550 MB heaps
     and ((a.k in ('autovacuum_vacuum_threshold', 'autovacuum_analyze_threshold')
          and a.v ~ '^[0-9]+$' and a.v::bigint < 20000
          and exists (select 1 from opt b where b.tbl = a.tbl
                         and b.k = replace(a.k, '_threshold', '_scale_factor') and b.v ~ '^[0-9.]+$' and b.v::numeric = 0))
      or (a.k in ('autovacuum_enabled', 'toast.autovacuum_enabled') and a.v in ('false', 'off', '0', 'no')))
), ff_low as (
  select c.oid::regclass::text as rel, x as setting
    from pg_class c, unnest(c.reloptions) x
   where c.relkind in ('r', 'i', 'm') and x ~ '^fillfactor=[0-9]+$' and split_part(x, '=', 2)::int < 50
     -- KNOWN, deliberate: port_goods at 30 (0292; its every row was rewritten each minute). RUNBOOK 3b leaves raising it to the owner.
     and not (c.oid = to_regclass('public.port_goods') and x = 'fillfactor=30')
), cron_jobs as (
  select j.jobname, j.schedule, j.active from cron.job j
), hit as (
  select round(100.0 * sum(d.blks_hit) / greatest(sum(d.blks_hit + d.blks_read), 1), 2) as pct, min(d.stats_reset) as since
    from pg_stat_database d where d.datname = current_database()
), io as (
  select i.backend_type, sum(i.reads) as reads, sum(i.writes) as writes
    from pg_stat_io i where i.reads > 0 or i.writes > 0 group by i.backend_type
), over as (
  select 'beat_mean_ms ' || mean_ms || ' over 2,000 (10 min)' as line from beat where mean_ms > 2000
  union all select 'database_mb ' || mb || ' over the 1,500 ceiling' from size where mb > 1500
  union all select 'database_mb ' || mb || ' over the 1,200 warning: find the table that grows (top10)' from size where mb > 1200 and mb <= 1500
  union all select 'io_waiting ' || io_waiting || ' sessions on the disk (over 5)' from act where io_waiting > 5
  union all select 'oldest_xact_s ' || oldest_xact_s || ' (over 300): a long transaction holds every vacuum back' from act where oldest_xact_s > 300
  union all select 'invalid_index ' || i.indexrelid::regclass::text || ': drop it and rebuild (RUNBOOK step 2)' from pg_index i where not i.indisvalid
  union all select 'dead_pct ' || dead_pct || ' on ' || tbl || ' (' || mb || ' MB): its vacuum is behind' from top10 where dead_pct > 20 and mb > 50
  union all select 'hot_set_mb ' || sum(mb) || ': the ten biggest tables no longer fit ~700 MB of cache' from top10 having sum(mb) > 700
  union all select 'cache_hit_pct ' || pct || ' (under 99): the game reads the disk' from hit where pct < 99
  union all select 'autovac_low ' || tbl || ' ' || setting || ' (floor 20,000 with scale factor 0; or off)' from autovac_low
  union all select 'fillfactor_low ' || rel || ' ' || setting || ' (floor 50)' from ff_low
  union all select 'cron_sub_minute ' || jobname || ' "' || schedule || '"' from cron_jobs where schedule ~* 'second'
)
select jsonb_build_object(
  'at', now(),
  'over', (select coalesce(jsonb_agg(line), '[]'::jsonb) from over),
  'beat', (select jsonb_build_object('beats', beats, 'mean_ms', mean_ms, 'p95_ms', p95_ms, 'errors', errors) from beat),
  'database_mb', (select mb from size),
  'sessions', (select jsonb_build_object('io_waiting', io_waiting, 'oldest_xact_s', oldest_xact_s) from act),
  'top10', (select jsonb_agg(jsonb_build_object('table', tbl, 'mb', mb, 'heap_mb', heap_mb, 'rows', rows, 'dead_pct', dead_pct,
                                                'autovacuums', autovacuum_count, 'last_autovacuum', last_autovacuum) order by mb desc) from top10),
  'hot_set_mb', (select sum(mb) from top10),
  'cache_hit', (select jsonb_build_object('pct', pct, 'since', since) from hit),
  'disk_reads_by', (select jsonb_object_agg(backend_type, jsonb_build_object('reads', reads, 'writes', writes)) from io),
  'cron', (select jsonb_agg(jsonb_build_object('job', jobname, 'schedule', schedule, 'active', active) order by jobname) from cron_jobs)
) as r;
commit;
