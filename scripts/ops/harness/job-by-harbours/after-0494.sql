-- 0494 A JOB SAILS HARBOUR BY HARBOUR, AFTER; ALSO THE 30-MINUTE CHECK (it alters live play: the jobs are lit). A PROD CHECK: read-only,
--   ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/job-by-harbours/after-0494.sql
-- Expect: head 20260818000494; new_fns 2, stable 2, client_reach false; knobs as before-0494.sql read them (none moved); bodies =
--   the chain's world at 0494: fleet_job_sails 83b19fb0350a3e0e01dae17aabfa9feb, fleet_job_plan 3a3cc9598bca5b549d18f0d62ff16536,
--   fleet_job_set_for 2e7e57044367984e12c391cb7ac60f87, fleet_jobs_due f471e46c71a83975ff3835c3cc1fd0d8,
--   fleet_job_open fc3fe1f07ad8806475f8949ba4812097, fleet_job_note 8cea4b10420eb2c15b2ea07a28132da1,
--   tick_fleet_jobs dc01d64892573005bd41fb6d41b6efd4; news 1 (the "update:0494" row).
--   WITHIN ONE TICK (2 minutes) of the push, each job before-0494.sql listed under `retry` with a chain: stopped no more (`jobs`:
--   paused null, last.ok true, last.to as before), its fleet under sail to the chain's first harbour. One with no chain: still stopped,
--   its sentence "she cannot sail from <A> to <B> harbour by harbour: ...", its last.at moving on by 10 minutes a try, never faster.
--   runs_30m: the fleet-jobs tick: failed 0; ms mean and max near what they were (a chained plan adds one pathfinder call, local 17-29 ms).
-- ROLLBACK (forward, owner only) if client_reach is true, a run's max ms is over 8,000, `failed` is above 0 in two runs, a stopped job's
--   last.at moves more often than every 10 minutes, or the gate goes red: QUICK fleet_jobs_enabled false (no job is asked; orders
--   already queued run out); FULL a migration reversing 0494's ten hunks (its OLD texts verbatim) and dropping public.fleet_job_legs
--   and public.fleet_job_leg_shut.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, fleet_jobs (one row a job), fleets,
--   ports, fleet_job_runs (a 720-slot ring), world_news by its key. No function is called but the catalog's. ROLLBACK: nothing (read only).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select json_object_agg(c.key, c.value) from public.world_config c
             where c.key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'assign_home_enabled', 'nav_leg_nm_base', 'sea_conditions_bite')),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname in ('fleet_job_legs', 'fleet_job_leg_shut')),
  'stable', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('fleet_job_legs', 'fleet_job_leg_shut') and p.provolatile = 's'),
  'client_reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                           or has_function_privilege('service_role', p.oid, 'execute')), false)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname in ('fleet_job_legs', 'fleet_job_leg_shut')),
  'bodies', (select json_object_agg(p.proname, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname in ('fleet_job_sails', 'fleet_job_plan', 'fleet_job_set_for', 'fleet_jobs_due',
                                                           'fleet_job_open', 'fleet_job_note', 'tick_fleet_jobs')),
  'news', (select count(*) from public.world_news n where n.key = 'update:0494'),
  'stopped', (select coalesce(json_object_agg(x.code, x.n), '{}'::json)
                from (select j.paused_reason as code, count(*) as n from public.fleet_jobs j where j.paused_reason is not null group by 1) x),
  'jobs', (select coalesce(json_agg(json_build_object(
                    'fleet', j.fleet_id, 'kind', j.kind, 'params', j.params, 'paused', j.paused_reason, 'runs', j.runs, 'last', j.last,
                    'lies_at', p.code, 'fleet_status', f.status)), '[]'::json)
             from (select * from public.fleet_jobs x
                    where x.paused_reason in ('E_LEG_TOO_FAR', 'E_ENDURANCE') or (x.last->>'at')::timestamptz > now() - interval '30 minutes'
                    order by (x.last->>'at')::timestamptz desc nulls last limit 12) j
             join public.fleets f on f.id = j.fleet_id
             left join public.ports p on p.id = f.port_id),
  'runs_30m', (select json_build_object('runs', count(*), 'ms_mean', round(avg(r.ms)), 'ms_max', max(r.ms),
                                        'started', sum((r.receipt->>'started')::int), 'stopped', sum((r.receipt->>'stopped')::int),
                                        'failed', sum((r.receipt->>'failed')::int), 'left', sum((r.receipt->>'left')::int),
                                        'plan_ms_max', max((select max((s->>'plan_ms')::numeric) from jsonb_array_elements(r.receipt->'steps') s)))
                 from public.fleet_job_runs r where r.at > now() - interval '30 minutes')
);
rollback;
