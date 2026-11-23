-- STANDING FLEET JOBS (0481), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/fleet-jobs/after-0481.sql
-- Expect, AS DEPLOYED (dark): head 20260818000481; knobs fleet_jobs_enabled false, fleet_jobs_per_tick 4, fleet_jobs_budget_ms 1500,
-- fleet_jobs_runs 12, fleet_jobs_wait_s 900; `registered` 4; `client_reach` false; `stable` true (the seven reads STABLE); `hunked` true;
-- `cron` {schedule "*/2 * * * *", active true}; `door` {"on": false} while dark; `jobs` {} and `runs` 0 (dark writes nothing).
-- THE COST OF ONE `best` PLAN for a real company, read here without a job row: the newest company's oldest idle fleet, her identity set
-- for this transaction alone (set_config, local: nothing is written): `best_sales_ms` world.best_sales, `passages_ms` world.board_passages,
-- `sails_ms` public.fleet_job_sails over her paying sales (the remembered courses, hers included), `coursed` how many of them a job could
-- sail now. A plan is about best_sales_ms + passages_ms + sails_ms.
-- LIT (read 30 minutes after lighting): `door` {"on": true, ...}; `jobs` by kind and state; `runs` the receipts of the last 30 minutes
-- (fleet_job_runs) with started / waited / stopped / failed and the run's ms (mean, max); the gate green.
-- ROLLBACK if `client_reach` true, `stable` false, a run's max ms over 8,000, `failed` above 0 in two runs, or the gate goes red:
-- fleet_jobs_enabled false (owner); the tick then returns at once and orders already queued run out.
-- Reads: world_config by key, the catalog, cron.job by name, players (companies), their fleets and queued orders, fleet_jobs and
-- fleet_job_runs (small: one row a job, a 720-slot ring), ONE world.best_sales, ONE world.board_passages, the course reads (STABLE), and
-- world.away_report (STABLE). No function that writes is called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
with hu as materialized (
  select p.id, p.auth_uid, p.created_at from public.players p where not p.is_npc
), idle as materialized (
  select hu.id as player_id, hu.auth_uid, hu.created_at as founded, f.id as fleet, f.port_id, f.created_at
    from hu join public.fleets f on f.player_id = hu.id
   where f.status = 'DOCKED' and f.port_id is not null
     and not exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active'))
), who as materialized (
  select i.*, set_config('request.jwt.claim.sub', i.auth_uid::text, true) as a,
         set_config('request.jwt.claims', json_build_object('sub', i.auth_uid)::text, true) as b
    from idle i order by i.founded desc, i.created_at, i.fleet limit 1
), t0 as materialized (
  select who.*, clock_timestamp() as t0 from who
), bs as materialized (
  select t0.*, world.best_sales(t0.fleet, t0.port_id) as r, clock_timestamp() as t1 from t0
), ps as materialized (
  select bs.t1 as t0, world.board_passages(bs.player_id, bs.fleet, bs.port_id, (select sr.cap_nm from public.supply_reach(bs.fleet) sr)) as r,
         clock_timestamp() as t1 from bs
), sails as materialized (
  select ps.t1 as t0,
         (select count(*) from jsonb_array_elements(bs.r -> 'goods') g
           where (g ->> 'pays')::boolean and g ->> 'port' is not null
             and not (public.fleet_job_sails(bs.fleet, bs.port_id,
                        array(select jsonb_array_elements_text(coalesce((select e -> 'stops' from jsonb_array_elements(ps.r) e
                                                                         join public.ports p on p.id = (e ->> 'port_id')::uuid
                                                                        where p.code = g ->> 'port' limit 1), '[]'::jsonb))) || (g ->> 'port')) ? 'missing')) as n,
         clock_timestamp() as t1
    from ps, bs
), door as materialized (
  select world.away_report() as r from sails
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'fleet\_jobs\_%'),
  'registered', (select count(*) from public.client_rpc_entry_points() e
                  where (e.schema_name, e.function_name) in (('cmd', 'set_fleet_job'), ('cmd', 'clear_fleet_job'), ('cmd', 'fleet_jobs_seen'), ('world', 'away_report'))
                    and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute')),
  'client_reach', has_function_privilege('anon', 'world.away_report()', 'execute')
                  or has_function_privilege('authenticated', 'public.fleet_job_plan(uuid)', 'execute')
                  or has_function_privilege('authenticated', 'public.fleet_job_open(uuid,jsonb)', 'execute')
                  or has_function_privilege('authenticated', 'public.fleet_job_set_for(uuid,uuid,text,jsonb)', 'execute')
                  or has_function_privilege('authenticated', 'public.tick_fleet_jobs(boolean)', 'execute')
                  or has_table_privilege('authenticated', 'public.fleet_jobs', 'select'),
  'stable', (select bool_and(p.provolatile = 's') from pg_proc p
              where p.oid in ('world.away_report()'::regprocedure, 'public.away_report_for(uuid)'::regprocedure, 'public.fleet_job_plan(uuid)'::regprocedure,
                              'public.fleet_jobs_due()'::regprocedure, 'public.fleet_job_course(uuid,uuid,uuid)'::regprocedure,
                              'public.fleet_job_sails(uuid,uuid,text[])'::regprocedure, 'public.fleet_jobs_on()'::regprocedure)),
  'hunked', position('''set_fleet_job''' in pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure)) > 0,
  'cron', (select jsonb_build_object('schedule', j.schedule, 'active', j.active, 'command', j.command) from cron.job j where j.jobname = 'byeharu-voyage:fleet-jobs'),
  'door', (select case when door.r ->> 'on' = 'false' then door.r else door.r - 'jobs' end from door),
  'jobs', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb)
             from (select j.kind || ':' || case when j.paused_reason is not null then 'stopped' when j.next_at > now() then 'waiting' else 'due_or_working' end as k,
                          count(*) as n
                     from public.fleet_jobs j group by 1) z),
  'stopped_by', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb)
                   from (select j.paused_reason as k, count(*) as n from public.fleet_jobs j where j.paused_reason is not null group by 1) z),
  'runs', (select jsonb_build_object('n', count(*), 'started', coalesce(sum((r.receipt ->> 'started')::int), 0),
                                     'waited', coalesce(sum((r.receipt ->> 'waited')::int), 0), 'stopped', coalesce(sum((r.receipt ->> 'stopped')::int), 0),
                                     'failed', coalesce(sum((r.receipt ->> 'failed')::int), 0), 'left', coalesce(sum((r.receipt ->> 'left')::int), 0),
                                     'mean_ms', round(avg(r.ms)), 'max_ms', max(r.ms))
             from public.fleet_job_runs r where r.at > now() - interval '30 minutes'),
  'at', (select p.code from bs join public.ports p on p.id = bs.port_id),
  'best_sales_ms', (select round(extract(epoch from bs.t1 - bs.t0) * 1000) from bs),
  'cut', (select bs.r -> 'cut' from bs),
  'passages_ms', (select round(extract(epoch from ps.t1 - ps.t0) * 1000) from ps),
  'sails_ms', (select round(extract(epoch from sails.t1 - sails.t0) * 1000) from sails),
  'paying', (select count(*) from bs cross join jsonb_array_elements(bs.r -> 'goods') g where (g ->> 'pays')::boolean and g ->> 'port' is not null),
  'coursed', (select sails.n from sails));
rollback;
