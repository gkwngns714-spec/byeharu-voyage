-- 0498 THE NEAR ROUND, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/near-round/before-0498.sql
-- Expect: head 20260818000497; switch null (no row yet); new_fns 0; hunked 4 (the four bodies 0498 hunks are there); jobs_wait
--   printed for the reader (0498 changes neither switch).
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
  'switch', (select c.value from public.world_config c where c.key = 'near_round_enabled'),
  'jobs_wait', (select c.value from public.world_config c where c.key = 'jobs_wait_enabled'),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where (n.nspname, p.proname) in (('public', 'near_round_on'), ('public', 'near_round_params'), ('public', 'lines_nm'),
                                                ('public', 'near_round_sentence'), ('public', 'near_round_action'))),
  'hunked', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where (n.nspname, p.proname) in (('public', 'fleet_job_set_for'), ('public', 'fleet_job_plan'), ('public', 'workers_for'), ('public', 'sea_actions_for')))
);
rollback;
