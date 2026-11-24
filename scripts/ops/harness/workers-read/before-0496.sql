-- 0496 THE WORKERS AND THEIR ACTIONS, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/workers-read/before-0496.sql
-- Expect: head 20260818000495 (0493, 0494 and 0495 are in); new_fns 0;
--   away_report_for = 37f33753b35dc0f64f897bd4761e9473 and registry = f88ccef5eedd0363a898ea032b9def6b (the chain's world at 0494, so
--   0496's two hunks occur there exactly once, as its self-assert proved on that world); away_hunk 1; registry_hunk 1.
--   A different digest or count: 0496 refuses at the push (its hunk count), nothing changes. 0495 (`dividend-hourly`) touches neither body;
--   if it does after all, the digest moves and the two counts decide.
--   The switches are printed for the reader: 0496 has none of its own and changes none (its probe sets them inside a rolled-back block).
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog. No player's row is read and no
--   function that writes is called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switches', (select json_object_agg(c.key, c.value) from public.world_config c
                where c.key in ('fleet_jobs_enabled', 'land_enabled', 'assign_home_enabled', 'sea_courses_enabled', 'land_smith_enabled')),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where (n.nspname, p.proname) in (('world', 'workers'), ('world', 'actions'), ('public', 'workers_for'), ('public', 'sea_actions_for'),
                                                ('public', 'land_actions_for'), ('public', 'job_trip'), ('public', 'action_shape'), ('public', 'away_parties_for'))),
  'away_report_for', (select md5(replace(pg_get_functiondef('public.away_report_for(uuid)'::regprocedure), E'\r', ''))),
  'registry', (select md5(replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', ''))),
  'away_hunk', (select (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old)
                  from (select replace(pg_get_functiondef('public.away_report_for(uuid)'::regprocedure), E'\r', '') as def,
                               '''since'', min(x.seen), ''runs'', coalesce(sum(x.runs), 0), ''earned'', coalesce(sum(x.earned), 0))'::text as old) d),
  'registry_hunk', (select (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old)
                      from (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def,
                                   '(''world'',       ''away_report'',           ''''),'::text as old) d)
);
rollback;
