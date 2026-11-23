-- SEA COURSES AND A FASTER LISBON READ (0482), BEFORE. A PROD CHECK: read-only, ONE statement. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/sea-courses/before-0482.sql
-- Expect: head 20260818000481; knobs {} (none of sea_courses_*); absent true (no public.sea_courses, no public.sea_course);
-- `fn` the md5 of every body 0482 hunks or reads, equal to the chain's (the hunks' anchors are then the chain's, once each);
-- `world` the harbours, their roadsteads and the raster digested, equal to the world scripts/build-sea-courses.mjs plotted on
-- (data/sea-courses.json: `harbours` 254); `course_join_nm` the door's join allowance.
-- THE COST, for the newest company's oldest idle fleet where she lies (her identity set for this transaction alone: set_config, local):
--   `best_sales_ms` ONE world.best_sales (STABLE; `cut` its own 2.5 s budget ran out), `paying`, and `coursed` how many paying sales a
--   job could sail today (public.fleet_job_sails, 0481: remembered courses only).
--   WHERE IT GOES: `captains` her fleet's seated captains and their active traits; `crew_ms` 200 public.crew_pct reads as a Lisbon read
--   asks them (one 'spread' and one 'category_spread' per quote, over the goods Lisbon sells, ten times), `terms_ms` 20
--   public.crew_terms, `progress_ms` 12 public.player_progress, `passages_ms` ONE world.board_passages, `wc_ms` 2,000 public.wc.
--   `track` the server's track_functions and, when it is on, the 25 functions with the most own time since the statistics were reset.
-- Reads: world_config by key, the catalog, pg_stat_user_functions, players (companies), their fleets, ships, seats and queued orders, the
-- harbours, sea_reaches and sea_raster, and the STABLE reads above. No function that writes is called. ROLLBACK: nothing (ends with rollback).
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
), gl as materialized (
  select g.id from bs join public.port_goods pg on pg.port_id = bs.port_id join public.goods g on g.id = pg.good_id
   where public.port_offers(bs.port_id, g.id) order by g.code limit 10
), cp as materialized (
  select bs.t1 as t0, (select sum(public.crew_pct(bs.fleet, null, 'spread', gl.id) + public.crew_pct(bs.fleet, null, 'category_spread', gl.id))
                         from gl cross join generate_series(1, 10) k) as s, clock_timestamp() as t1 from bs
), ct as materialized (
  select cp.t1 as t0, (select count(*) from generate_series(1, 20) k cross join lateral public.crew_terms(bs.fleet, now()) t) as n,
         clock_timestamp() as t1 from cp, bs
), pp as materialized (
  select ct.t1 as t0, (select count(public.player_progress(case when k > 0 then bs.player_id end)) from generate_series(1, 12) k) as n, clock_timestamp() as t1 from ct, bs
), ps as materialized (
  select pp.t1 as t0, world.board_passages(bs.player_id, bs.fleet, bs.port_id, (select sr.cap_nm from public.supply_reach(bs.fleet) sr)) as r,
         clock_timestamp() as t1 from pp, bs
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
), wcs as materialized (
  select sails.t1 as t0, (select count(public.wc(case when k > 0 then 'time_compression' end)) from generate_series(1, 2000) k) as n, clock_timestamp() as t1 from sails
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'beat', (select jsonb_build_object('beats', count(*), 'mean_ms', round(avg(b.ms))) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'sea\_courses\_%'),
  'absent', to_regclass('public.sea_courses') is null and to_regprocedure('public.sea_course(uuid,uuid)') is null,
  'lit', (select jsonb_object_agg(c.key, c.value) from public.world_config c
           where c.key in ('fleet_jobs_enabled', 'hq_board_enabled', 'skills_bite', 'crew_bite', 'levels_bite', 'economy_closed', 'near_choice_enabled', 'first_hour_enabled')),
  'fn', (select jsonb_object_agg(p.oid::regprocedure::text, md5(replace(pg_get_functiondef(p.oid), E'\r', '')))
           from pg_proc p
          where p.oid in ('public.fleet_job_course(uuid,uuid,uuid)'::regprocedure, 'public.fleet_job_plan(uuid)'::regprocedure,
                          'public.hq_board_for(uuid)'::regprocedure, 'public.crew_pct(uuid,uuid,text,uuid,timestamptz)'::regprocedure,
                          'public.crew_terms(uuid,timestamptz)'::regprocedure, 'world.best_sales(uuid,uuid)'::regprocedure,
                          'world.board_sell(uuid,uuid,jsonb)'::regprocedure, 'world.spread_effective_pair(uuid,uuid,uuid,boolean)'::regprocedure,
                          'voyage.path_refusal(jsonb,numeric,numeric,numeric,numeric,numeric,numeric,numeric)'::regprocedure,
                          'cmd.do_sail(uuid,jsonb)'::regprocedure)),
  'world', (select jsonb_build_object(
              'harbours', count(*),
              'roadsteads', md5(string_agg(p.code || ':' || sr.roadstead_lat::text || ':' || sr.roadstead_lon::text, ',' order by p.code collate "C")),
              'raster', (select md5(r.cells) || ':' || r.cols || 'x' || r.rows || ':' || r.cell_deg from public.sea_raster r where r.id = 1))
              from public.ports p join public.sea_reaches sr on sr.port_id = p.id where p.kind = 'HARBOUR'),
  'course_join_nm', (select c.value from public.world_config c where c.key = 'course_join_nm'),
  'companies', (select count(*) from hu),
  'idle', (select count(*) from idle),
  'at', (select p.code from bs join public.ports p on p.id = bs.port_id),
  'best_sales_ms', (select round(extract(epoch from bs.t1 - bs.t0) * 1000) from bs),
  'cut', (select bs.r -> 'cut' from bs),
  'goods', (select jsonb_array_length(bs.r -> 'goods') from bs),
  'paying', (select count(*) from bs cross join jsonb_array_elements(bs.r -> 'goods') g where (g ->> 'pays')::boolean and g ->> 'port' is not null),
  'coursed', (select sails.n from sails),
  'captains', (select jsonb_build_object('ships', (select count(*) from public.ships s where s.fleet_id = bs.fleet),
                                         'seated', count(distinct cs.player_officer_id),
                                         'active_traits', (select count(*) from public.captain_seats c2 join public.ships s2 on s2.id = c2.ship_id
                                                             join public.captain_active ca on ca.player_officer_id = c2.player_officer_id
                                                            where s2.fleet_id = bs.fleet))
                 from bs left join public.ships s on s.fleet_id = bs.fleet left join public.captain_seats cs on cs.ship_id = s.id group by bs.fleet),
  'crew_ms', (select round(extract(epoch from cp.t1 - cp.t0) * 1000) from cp),
  'crew_sum', (select cp.s from cp),
  'terms_ms', (select round(extract(epoch from ct.t1 - ct.t0) * 1000) from ct),
  'terms_rows', (select ct.n / 20 from ct),
  'progress_ms', (select round(extract(epoch from pp.t1 - pp.t0) * 1000) from pp),
  'passages_ms', (select round(extract(epoch from ps.t1 - ps.t0) * 1000) from ps),
  'sails_ms', (select round(extract(epoch from sails.t1 - sails.t0) * 1000) from sails),
  'wc_ms', (select round(extract(epoch from wcs.t1 - wcs.t0) * 1000) from wcs),
  'track', jsonb_build_object('setting', current_setting('track_functions'),
             'top', (select jsonb_agg(jsonb_build_object('fn', z.f, 'calls', z.calls, 'self_ms', z.self_ms, 'total_ms', z.total_ms))
                       from (select s.schemaname || '.' || s.funcname as f, s.calls, round(s.self_time::numeric) as self_ms, round(s.total_time::numeric) as total_ms
                               from pg_stat_user_functions s order by s.self_time desc limit 25) z)));
rollback;
