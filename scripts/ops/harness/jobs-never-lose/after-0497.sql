-- 0497 JOBS NEVER LOSE, AFTER. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/jobs-never-lose/after-0497.sql
-- Expect: head 20260818000497; switch false (DARK: nothing changes for a player); new_fns 4; reach false (no new function callable by
--   anon, authenticated or service_role); waiting 0 (no job waits `low` while dark).
-- LIT LATER (the owner's switch, never thrown here): `waiting` then counts the jobs that wait for a price, each asked again at its
--   next_at; none should have paused_reason set by the wait.
-- ROLLBACK (forward, owner only): jobs_wait_enabled false; or a migration reversing the eleven hunks and dropping the four functions.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, fleet_jobs (a small table).
--   No function that writes is called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'jobs_wait_enabled'),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where (n.nspname, p.proname) in (('public', 'jobs_wait_on'), ('public', 'fleet_run_quote'), ('public', 'sale_fit'), ('public', 'cards_fit'))),
  'reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                    or has_function_privilege('service_role', p.oid, 'execute')), false)
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where (n.nspname, p.proname) in (('public', 'jobs_wait_on'), ('public', 'fleet_run_quote'), ('public', 'sale_fit'), ('public', 'cards_fit'))),
  'waiting', (select count(*) from public.fleet_jobs j where j.last->>'wait' = 'low'),
  'jobs', (select count(*) from public.fleet_jobs)
);
rollback;
