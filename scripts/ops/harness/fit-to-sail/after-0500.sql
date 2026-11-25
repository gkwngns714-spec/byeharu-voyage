-- 0500 FIT TO SAIL, AFTER. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/fit-to-sail/after-0500.sql
-- Expect: head 20260818000500; new_fns 2; reach false (neither new function is callable by a client role); flag_rule 0, one_rule 1 and queue_at 1
--   (voyage.sail_refusal asks public.fleet_unfit). `waiting_unfit`: jobs that wait for a repair or for crew (last.wait
--   E_FLAGSHIP_DISABLED or E_CREW_SHORT): each
--   has no pending order and its runs did not move. `stopped_unfit`: jobs stopped on the code before the deploy: each stays so until
--   her repair. `failed_since`: orders failed E_FLAGSHIP_DISABLED in the last hour by a fleet that has a job: 0 an hour after the deploy (a wrecked fleet's
--   lines are no longer issued). `ticks`: the last hour's job runs: how many, the slowest, and every run over 2 s with its steps, which
--   now carry collect_ms, wait_ms and quay_ms beside plan_ms and open_ms: the part a slow tick spent its time in.
-- ROLLBACK (forward, owner only): a migration reversing the fifteen hunks and dropping public.fleet_unfit and public.port_hires. QUICK: fleet_jobs_enabled
--   false stops every job (the owner's switch; never thrown here).
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, the catalog, fleet_jobs (a small table) with its fleets and their
--   flagships by key, the orders of those few fleets by their fleet index, fleet_job_runs (a ring of 720 rows). No function that
--   writes is called. Nothing to roll back.
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where (n.nspname, p.proname) in (('public', 'fleet_unfit'), ('public', 'port_hires'))),
  'reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                    or has_function_privilege('service_role', p.oid, 'execute')), false)
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace where (n.nspname, p.proname) in (('public', 'fleet_unfit'), ('public', 'port_hires'))),
  'flag_rule', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'voyage' and p.proname = 'sail_refusal'
                   and p.prosrc like '%select coalesce(durability, 0) into v_flag from public.ships where fleet_id = p_fleet and is_flagship;%'),
  'queue_at', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'cmd' and p.proname = 'queue' and p.prosrc like '%''at'', o.executed_at%'),
  'one_rule', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'voyage' and p.proname = 'sail_refusal' and p.prosrc like '%v_gate := public.fleet_unfit(p_fleet);%'),
  'waiting_unfit', (select coalesce(json_agg(json_build_object('fleet', j.fleet_id, 'kind', j.kind, 'runs', j.runs, 'last', j.last, 'next_at', j.next_at, 'status', f.status,
                                                               'pending', (select count(*) from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active')))), '[]'::json)
                      from public.fleet_jobs j join public.fleets f on f.id = j.fleet_id where j.paused_reason is null and j.last->>'wait' in ('E_FLAGSHIP_DISABLED', 'E_CREW_SHORT')),
  'stopped_unfit', (select coalesce(json_agg(json_build_object('fleet', j.fleet_id, 'kind', j.kind, 'code', j.paused_reason, 'runs', j.runs, 'status', f.status,
                                                               'flagship_hull', (select s.durability from public.ships s where s.fleet_id = f.id and s.is_flagship))), '[]'::json)
                      from public.fleet_jobs j join public.fleets f on f.id = j.fleet_id where j.paused_reason in ('E_FLAGSHIP_DISABLED', 'E_CREW_SHORT')),
  'failed_since', (select count(*) from public.fleet_jobs j join public.orders o on o.fleet_id = j.fleet_id
                    where o.status = 'failed' and o.error_code in ('E_FLAGSHIP_DISABLED', 'E_CREW_SHORT')
                      and o.executed_at > now() - interval '1 hour'),
  'ticks', (select json_build_object('runs', count(*), 'max_ms', max(r.ms),
                                     'over_2s', coalesce(json_agg(json_build_object('at', r.at, 'ms', r.ms, 'steps', r.receipt->'steps') order by r.at) filter (where r.ms > 2000), '[]'::json))
              from public.fleet_job_runs r where r.at > now() - interval '1 hour')
);
rollback;
