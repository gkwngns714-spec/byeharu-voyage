-- 0498 JOBS NEVER LOSE, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/jobs-never-lose/before-0498.sql
-- Expect: head 20260818000497; switch null (no row yet); new_fns 0; hunked 6 (the six bodies 0498 hunks are there).
--   The digests are printed for the record: 0498 refuses at the push if a hunk does not occur exactly once, and nothing changes.
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
  'switch', (select c.value from public.world_config c where c.key = 'jobs_wait_enabled'),
  'switches', (select json_object_agg(c.key, c.value) from public.world_config c where c.key in ('fleet_jobs_enabled', 'hq_board_enabled', 'assign_home_enabled', 'sea_courses_enabled')),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where (n.nspname, p.proname) in (('public', 'jobs_wait_on'), ('public', 'fleet_run_quote'), ('public', 'sale_fit'), ('public', 'cards_fit'))),
  'hunked', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where (n.nspname, p.proname) in (('public', 'fleet_job_plan'), ('public', 'fleet_job_note'), ('public', 'workers_for'), ('public', 'sea_actions_for'),
                                               ('public', 'hq_board_for'), ('public', 'run_day'))),
  'digests', (select json_object_agg(p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', ''))) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where (n.nspname, p.proname) in (('public', 'fleet_job_plan'), ('public', 'fleet_job_note'), ('public', 'workers_for'), ('public', 'sea_actions_for'),
                                                ('public', 'hq_board_for'), ('public', 'run_day')))
);
rollback;
