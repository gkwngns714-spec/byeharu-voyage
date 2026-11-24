-- 0492 A FLEET BRINGS HER GOODS HOME, AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/assign-bring-home/after-0492.sql
-- Expect, AS DEPLOYED (dark): head 20260818000492; switch false; new_fns 3, client_reach false (none callable by anon, authenticated or
--   service_role), stable 3; bodies = the chain's world at 0492: fleet_job_note 070bf65c97c9306e58504976593ee258,
--   fleet_job_open 734896f692eec81e9770350089e09358, fleet_job_set_for 80862433b1f0ad64929d420481947ef0,
--   fleet_job_plan ce29b861184739a88e7338e943efdb81; jobs as before; jobs_with_new_keys 0 (dark, the door refuses end / times);
--   runs_30m: the fleet-jobs tick as before (started / stopped / failed, ms mean and max).
-- LIT (read 30 minutes after the owner lights assign_home_enabled): bring_home = the jobs with end 'store' (count, stopped and by code,
--   left); stored_30m = STORED events in the last 30 minutes (rows, units) against stored_prev_30m; runs_30m failed 0; the gate green.
-- ROLLBACK if client_reach true, a run's max ms over 8,000, `failed` above 0 in two runs, a bring-home job stopped on a code other than
--   E_SHED_FULL / E_NO_COURSE / E_INSUFFICIENT_FUNDS, or the gate goes red: assign_home_enabled false (owner). Bring-home and counted jobs
--   then stop at their next turn (E_NOT_IN_USE); every other job runs as before; orders already queued run out.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, fleet_jobs (one row a job),
--   fleet_job_runs (a 720-slot ring), events of kind STORED in the last hour (by the created_at index). No function that writes is
--   called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'assign_home_enabled'),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname in ('assign_home_on', 'fleet_job_end', 'fleet_job_ends')),
  'stable', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('assign_home_on', 'fleet_job_end', 'fleet_job_ends') and p.provolatile = 's'),
  'client_reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                           or has_function_privilege('service_role', p.oid, 'execute')), false)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname in ('assign_home_on', 'fleet_job_end', 'fleet_job_ends')),
  'bodies', (select json_object_agg(p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('fleet_job_set_for', 'fleet_job_plan', 'fleet_job_open', 'fleet_job_note')),
  'jobs', (select coalesce(json_object_agg(x.kind, x.n), '{}'::json)
             from (select j.kind, count(*) as n from public.fleet_jobs j group by j.kind) x),
  'jobs_with_new_keys', (select count(*) from public.fleet_jobs j where j.params ? 'end' or j.params ? 'times' or j.params ? 'left'),
  'bring_home', (select json_build_object('jobs', count(*), 'stopped', count(*) filter (where j.paused_reason is not null),
                                          'codes', coalesce(json_object_agg(j.paused_reason, 1) filter (where j.paused_reason is not null), '{}'::json),
                                          'counted', count(*) filter (where j.params ? 'left'))
                   from public.fleet_jobs j where j.params->>'end' = 'store'),
  'runs_30m', (select json_build_object('runs', count(*), 'started', coalesce(sum((r.receipt->>'started')::int), 0),
                                        'stopped', coalesce(sum((r.receipt->>'stopped')::int), 0), 'failed', coalesce(sum((r.receipt->>'failed')::int), 0),
                                        'ms_mean', round(avg(r.ms)), 'ms_max', max(r.ms))
                 from public.fleet_job_runs r where r.at > now() - interval '30 minutes'),
  'stored_30m', (select json_build_object('rows', count(*), 'units', coalesce(sum((e.payload->>'qty')::numeric), 0))
                   from public.events e where e.kind = 'STORED' and e.created_at > now() - interval '30 minutes'),
  'stored_prev_30m', (select json_build_object('rows', count(*), 'units', coalesce(sum((e.payload->>'qty')::numeric), 0))
                        from public.events e where e.kind = 'STORED' and e.created_at > now() - interval '60 minutes'
                                               and e.created_at <= now() - interval '30 minutes')
);
rollback;
