-- SEA COURSES AND A FASTER LISBON READ (0482), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/sea-courses/after-0482.sql
-- Expect, AS DEPLOYED (dark): head 20260818000482; knobs {sea_courses_enabled: false}; `tables` sea_courses 254 rows and the bytes the
-- self-assert printed, sea_reach_matrix 1 row; `matrix_kept` true (the kept matrix is the one built); `stable` true; `hunked` true (the
-- six bodies hold their 0482 lines); `client_reach` false; `triggers` 2.
-- THE COST, for the newest company's oldest idle fleet where she lies (her identity set for this transaction alone: set_config, local):
--   `best_sales_ms` ONE world.best_sales (before-0482: 2,603 ms at Lisbon, cut, 8 of 10 goods), `cut`, `goods`; `passages_ms` ONE
--   world.board_passages (before: 198 ms); `coursed` her paying sales a job can sail now (the switch's own reading: dark, remembered
--   courses only; before: 0 of 8), `coursed_stored` those every leg of which has a stored course (what lighting the switch gives).
-- LIT (30 minutes after lighting): `door` the knob true; `jobs` by kind and state, `stopped_by` (E_NO_COURSE should fall to 0 for
-- best jobs), `runs` the fleet-job receipts of the last 30 minutes; the gate green.
-- ROLLBACK if `client_reach` true, `stable` false, `matrix_kept` false, a fleet-job run's max ms over 8,000, or the gate goes red:
-- sea_courses_enabled false (owner); jobs and cards are then 0481's and 0480's exactly. The faster read changes no answer: it stays.
-- Reads: world_config by key, the catalog, the two new tables, players (companies), their fleets and queued orders, fleet_jobs and
-- fleet_job_runs (small), ONE world.best_sales, ONE world.board_passages, public.sea_reach_matrix_build (STABLE, once), the course
-- reads (STABLE). No function that writes is called. ROLLBACK: nothing to roll back (read only; ends with rollback).
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
), sales as materialized (
  select g.e ->> 'port' as port,
         array(select jsonb_array_elements_text(coalesce((select e -> 'stops' from jsonb_array_elements(ps.r) e
                                                          join public.ports p on p.id = (e ->> 'port_id')::uuid
                                                         where p.code = g.e ->> 'port' limit 1), '[]'::jsonb))) || (g.e ->> 'port') as codes
    from bs cross join ps cross join jsonb_array_elements(bs.r -> 'goods') g(e)
   where (g.e ->> 'pays')::boolean and g.e ->> 'port' is not null
), mx as materialized (
  select (select m.nm from public.sea_reach_matrix m where m.id = 1) is not distinct from b.nm and b.nm is not null as kept from public.sea_reach_matrix_build() b
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'sea\_courses\_%'),
  'tables', jsonb_build_object(
     'sea_courses', jsonb_build_object('rows', (select count(*) from public.sea_courses), 'courses', (select sum(cardinality(c.tos)) from public.sea_courses c),
                                       'bytes', pg_total_relation_size('public.sea_courses')),
     'sea_reach_matrix', jsonb_build_object('rows', (select count(*) from public.sea_reach_matrix), 'bytes', pg_total_relation_size('public.sea_reach_matrix'))),
  'matrix_kept', (select mx.kept from mx),
  'stable', (select bool_and(p.provolatile = 's') from pg_proc p
              where p.oid in ('public.sea_course(uuid,uuid)'::regprocedure, 'public.sale_lines(uuid,uuid,jsonb,jsonb)'::regprocedure,
                              'public.sea_courses_on()'::regprocedure, 'public.sea_reach_matrix_build()'::regprocedure,
                              'public.fleet_job_course(uuid,uuid,uuid)'::regprocedure, 'world.best_sales(uuid,uuid)'::regprocedure,
                              'voyage.reach_passage(uuid,uuid,uuid,numeric)'::regprocedure, 'world.board_trips(uuid,jsonb,jsonb)'::regprocedure)),
  'hunked', position('public.sea_course(p_from, p_to)' in pg_get_functiondef('public.fleet_job_course(uuid,uuid,uuid)'::regprocedure)) > 0
            and position('public.sale_lines(f.id, f.port_id, s.e' in pg_get_functiondef('public.fleet_job_plan(uuid)'::regprocedure)) > 0
            and position('public.sale_lines(f.id, f.port_id, s.e' in pg_get_functiondef('public.hq_board_for(uuid)'::regprocedure)) > 0
            and position('public.sea_reach_matrix m' in pg_get_functiondef('voyage.reach_passage(uuid,uuid,uuid,numeric)'::regprocedure)) > 0
            and position('''speed_parts'', voyage.fleet_speed_parts(p_fleet)' in pg_get_functiondef('world.best_sales(uuid,uuid)'::regprocedure)) > 0
            and position('p_ctx->''trip_hulls''' in pg_get_functiondef('world.board_trips(uuid,jsonb,jsonb)'::regprocedure)) > 0,
  'client_reach', has_function_privilege('authenticated', 'public.sea_course(uuid,uuid)', 'execute')
                  or has_function_privilege('authenticated', 'public.sale_lines(uuid,uuid,jsonb,jsonb)', 'execute')
                  or has_table_privilege('authenticated', 'public.sea_courses', 'select')
                  or has_table_privilege('authenticated', 'public.sea_reach_matrix', 'select'),
  'triggers', (select count(*) from pg_trigger t where t.tgname in ('sea_reach_matrix_on_reaches', 'sea_reach_matrix_on_ports') and not t.tgisinternal),
  'door', (select c.value from public.world_config c where c.key = 'sea_courses_enabled'),
  'jobs', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb)
             from (select j.kind || ':' || case when j.paused_reason is not null then 'stopped' when j.next_at > now() then 'waiting' else 'due_or_working' end as k,
                          count(*) as n
                     from public.fleet_jobs j group by 1) z),
  'stopped_by', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb)
                   from (select j.paused_reason as k, count(*) as n from public.fleet_jobs j where j.paused_reason is not null group by 1) z),
  'runs', (select jsonb_build_object('n', count(*), 'started', coalesce(sum((r.receipt ->> 'started')::int), 0),
                                     'stopped', coalesce(sum((r.receipt ->> 'stopped')::int), 0), 'mean_ms', round(avg(r.ms)), 'max_ms', max(r.ms))
             from public.fleet_job_runs r where r.at > now() - interval '30 minutes'),
  'at', (select p.code from bs join public.ports p on p.id = bs.port_id),
  'best_sales_ms', (select round(extract(epoch from bs.t1 - bs.t0) * 1000) from bs),
  'cut', (select bs.r -> 'cut' from bs),
  'goods', (select jsonb_array_length(bs.r -> 'goods') from bs),
  'passages_ms', (select round(extract(epoch from ps.t1 - ps.t0) * 1000) from ps),
  'paying', (select count(*) from sales),
  'coursed', (select count(*) from sales cross join bs where not (public.fleet_job_sails(bs.fleet, bs.port_id, sales.codes) ? 'missing')),
  'coursed_stored', (select count(*) from sales cross join bs
                      where not exists (select 1 from (select c, lag(c) over (order by k) as prev from unnest(array[(select p.code from public.ports p where p.id = bs.port_id)] || sales.codes) with ordinality u(c, k)) l
                                         where l.prev is not null and l.prev <> l.c
                                           and public.sea_course((select p.id from public.ports p where p.code = l.prev and p.kind = 'HARBOUR'),
                                                                 (select p.id from public.ports p where p.code = l.c and p.kind = 'HARBOUR')) is null)));
rollback;
