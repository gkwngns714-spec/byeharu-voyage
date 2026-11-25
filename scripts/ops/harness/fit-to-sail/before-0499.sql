-- 0499 FIT TO SAIL, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/fit-to-sail/before-0499.sql
-- Expect: head 20260818000498; new_fns 0; hunked 9 (the nine bodies 0499 hunks are there); flag_rule 1 (voyage.sail_refusal still
--   reads her flagship itself: the text the hunk replaces, once). `stopped_unfit`: the jobs stopped on E_FLAGSHIP_DISABLED or
--   E_CREW_SHORT today (the reported ones), each with the hands on her quay: after the deploy each stays stopped until her repair or
--   her hire, then goes on by itself. `unfit_due`: jobs the next run would
--   plan for a fleet that cannot sail (each would issue its lines and count a run today; after, each waits). `slow_ticks`: the job
--   runs of the last 24 hours over 2 s, with their steps (plan_ms, open_ms): the ten-second tick, if it is still in the ring.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, the catalog, fleet_jobs (a small table) with its fleets and their
--   flagships by key, fleet_job_runs (a ring of 720 rows). No function that writes is called. Nothing to roll back.
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where (n.nspname, p.proname) in (('public', 'fleet_unfit'), ('public', 'port_hires'))),
  'hunked', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where (n.nspname, p.proname) in (('voyage', 'sail_refusal'), ('cmd', 'do_hire'), ('cmd', 'queue'), ('public', 'fleet_job_plan'), ('public', 'fleet_job_note'), ('public', 'fleet_jobs_due'),
                                               ('public', 'fleet_job_set_for'), ('public', 'fleet_job_open'), ('public', 'tick_fleet_jobs'))),
  'flag_rule', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'voyage' and p.proname = 'sail_refusal'
                   and p.prosrc like '%select coalesce(durability, 0) into v_flag from public.ships where fleet_id = p_fleet and is_flagship;%'),
  'stopped_unfit', (select coalesce(json_agg(json_build_object('fleet', j.fleet_id, 'kind', j.kind, 'runs', j.runs, 'last', j.last, 'status', f.status,
                                                               'code', j.paused_reason, 'port', (select p.code from public.ports p where p.id = f.port_id),
                                                               'hands_here', (select p.crew_pool from public.ports p where p.id = f.port_id),
                                                               'ships_short', (select count(*) from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = f.id and s.crew < c.crew_required),
                                                               'flagship_hull', (select s.durability from public.ships s where s.fleet_id = f.id and s.is_flagship))), '[]'::json)
                      from public.fleet_jobs j join public.fleets f on f.id = j.fleet_id where j.paused_reason in ('E_FLAGSHIP_DISABLED', 'E_CREW_SHORT')),
  'unfit_due', (select count(*) from public.fleet_jobs j join public.fleets f on f.id = j.fleet_id
                 where j.paused_reason is null and f.status = 'DOCKED'
                   and (coalesce((select s.durability from public.ships s where s.fleet_id = f.id and s.is_flagship), 0) <= 0
                        or exists (select 1 from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = f.id and s.crew < c.crew_required))),
  'slow_ticks', (select coalesce(json_agg(json_build_object('at', r.at, 'ms', r.ms, 'steps', r.receipt->'steps') order by r.at), '[]'::json)
                   from public.fleet_job_runs r where r.at > now() - interval '24 hours' and r.ms > 2000)
);
rollback;
