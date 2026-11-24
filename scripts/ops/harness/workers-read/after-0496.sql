-- 0496 THE WORKERS AND THEIR ACTIONS, AFTER. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/workers-read/after-0496.sql
-- Expect: head 20260818000496; new_fns 11; cores_reach false (no core callable by anon, authenticated or service_role); doors 2 (the two
--   reads for authenticated, not anon); registered 2; reads 11 (the shape, the day's shape and the tick's period immutable, eight stable);
--   away_report_for = 5dbcb0d1c8778810ab48c6abe1aa94c8, registry = 16a15f96b3c5d0f71621f1d5ebc7fc82 (the chain's world at 0496).
--   workers: public.workers_for of THE COMPANY NAMED BELOW (put the owner's company name in place of the text between the quotes): one
--   row a fleet, then her party when the land is lit; workers_ms is that one read's time here (budget 100).
--   parties: her away report's land rows.
--   world.actions is NOT called here: it reads the caller (world.best_sales), so asked from this session it answers
--   {company: false}; its cost is the client's to see (its own `ms`), about a second a fleet.
-- ROLLBACK (forward, owner only) if cores_reach is true, doors or registered is not 2, or the away card fails to open: a migration
--   reversing the two hunks (0496's OLD texts) and dropping the eleven functions.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, the catalog, one players row by name, that company's fleets, jobs,
--   party and her ledger rows of the last 24 hours (the (player_id, created_at) index, once). public.workers_for and
--   public.away_parties_for are STABLE and write nothing. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
with me as (
  select p.id from public.players p where p.company_name = 'PUT THE COMPANY NAME HERE' and not p.is_npc limit 1
), t0 as (
  select clock_timestamp() as at
), w as (
  select public.workers_for(me.id) as rows, public.away_parties_for(me.id) as parties from me, t0
)
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where (n.nspname, p.proname) in (('world', 'workers'), ('world', 'actions'), ('public', 'workers_for'), ('public', 'sea_actions_for'),
                                                ('public', 'land_actions_for'), ('public', 'job_trip'), ('public', 'action_shape'), ('public', 'away_parties_for'),
                                                ('public', 'run_day'), ('public', 'action_over_day'), ('public', 'fleet_job_tick_s'))),
  'cores_reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                          or has_function_privilege('service_role', p.oid, 'execute')), false)
                    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where (n.nspname, p.proname) in (('public', 'workers_for'), ('public', 'sea_actions_for'), ('public', 'land_actions_for'),
                                                    ('public', 'job_trip'), ('public', 'action_shape'), ('public', 'away_parties_for'),
                                                    ('public', 'run_day'), ('public', 'action_over_day'), ('public', 'fleet_job_tick_s'))),
  'doors', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where (n.nspname, p.proname) in (('world', 'workers'), ('world', 'actions'))
               and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')),
  'registered', (select count(*) from public.client_rpc_entry_points() e
                  where (e.schema_name, e.function_name, e.arg_types) in (('world', 'workers', ''), ('world', 'actions', 'text')) and e.fn is not null),
  'reads', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where ((n.nspname, p.proname) in (('public', 'action_shape'), ('public', 'action_over_day'), ('public', 'fleet_job_tick_s')) and p.provolatile = 'i')
                or ((n.nspname, p.proname) in (('world', 'workers'), ('world', 'actions'), ('public', 'workers_for'), ('public', 'sea_actions_for'),
                                               ('public', 'land_actions_for'), ('public', 'job_trip'), ('public', 'away_parties_for'), ('public', 'run_day'))
                    and p.provolatile = 's')),
  'away_report_for', (select md5(replace(pg_get_functiondef('public.away_report_for(uuid)'::regprocedure), E'\r', ''))),
  'registry', (select md5(replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', ''))),
  'workers', (select w.rows from w),
  'parties', (select w.parties from w),
  'workers_ms', (select round(extract(epoch from clock_timestamp() - t0.at)::numeric * 1000, 1) from t0, w)
);
rollback;
