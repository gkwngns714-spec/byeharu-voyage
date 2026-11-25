-- ASSIGN, WHERE ITS TIME GOES (0503). A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/assign-fast/split.sql
-- Run it once before the deploy and once after. ONE run costs about what two Assign sheets cost (5 to 10 s before): not in a full minute's first
-- ten seconds. For the newest docked, idle company fleet (her identity set for this transaction alone: set_config, local).
-- Answers: `sea_actions_ms` the whole read; `best_sales_ms` its first part; then the rest, asked alone: `cards` her paying cards (8 at most);
--   `out_ms` public.job_trip there, the miles alone, one a harbour; `back_ms` the priced trip back, one a harbour; `home_ms` her home and back
--   (null while she has none); `reach_ms` one voyage.reach_passage from where she lies; `course_ms` 20 courses read; `segments_ms` the same 20
--   measured by voyage.segments_from_course; `judge_ms` the same 20 judged (public.fleet_job_leg_shut); `run_day_ms` a day of each card.
--   The parts asked alone share nothing with each other, so their sum is above sea_actions_ms once 0503's memo is in.
-- Expect after 0503: sea_actions_ms less best_sales_ms at 60 % of its before or less (locally 0.4 to 0.5), `closed` null, options as before.
-- Reads: the catalog, players, fleets, ports, orders, port_goods, goods, and STABLE reads. Nothing is written. ROLLBACK: nothing.
begin transaction read only;
with who as materialized (
  select f.player_id, f.id as fleet, f.port_id, pt.code,
         set_config('request.jwt.claim.sub', p.auth_uid::text, true) as a,
         set_config('request.jwt.claims', json_build_object('sub', p.auth_uid)::text, true) as b
    from public.fleets f join public.players p on p.id = f.player_id join public.ports pt on pt.id = f.port_id and pt.kind = 'HARBOUR'
   where f.status = 'DOCKED' and not p.is_npc
     and not exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active'))
     and not exists (select 1 from public.standing_routes r where r.fleet_id = f.id)
   order by p.created_at desc, f.created_at, f.id limit 1
), t0 as materialized (select clock_timestamp() as t from who
), bs as materialized (select world.best_sales(who.fleet, who.port_id) as r, t0.t as t0 from who, t0
), b1 as materialized (select bs.r, bs.t0, clock_timestamp() as t from bs
), sa as materialized (select public.sea_actions_for(who.player_id, who.fleet) as r, b1.t as t0 from who, b1
), s1 as materialized (select sa.r, sa.t0, clock_timestamp() as t from sa
), cards as materialized (
  select e->>'good' as good, g.id as gid, p.id as dest, p.code, (e->>'units')::numeric as units, coalesce((e->>'cost')::numeric, 0) as cost, (e->>'profit')::numeric as profit
    from b1 cross join lateral jsonb_array_elements(b1.r->'goods') e
    join public.ports p on p.code = e->>'port' and p.kind = 'HARBOUR' join public.goods g on g.code = e->>'good'
   where (e->>'pays')::boolean and (e->>'units')::numeric > 0 order by (e->>'profit')::numeric / greatest((e->>'seconds')::numeric, 1) desc limit 8
), dests as materialized (select distinct c.dest, c.code from cards c
), o1 as materialized (select count(public.job_trip(who.fleet, who.port_id, array[d.code], false)) as n, (select t from s1) as t0 from who, dests d
), o2 as materialized (select o1.*, clock_timestamp() as t from o1
), k1 as materialized (select count(public.job_trip(who.fleet, d.dest, array[who.code], true)) as n, (select t from o2) as t0 from who, dests d
), k2 as materialized (select k1.*, clock_timestamp() as t from k1
), h1 as materialized (select (select p.code from public.ports p where p.id = public.home_port_of(who.player_id)) as home, (select t from k2) as t0, who.* from who
), h2 as materialized (select h1.t0, case when h1.home is not null and h1.home <> h1.code then public.job_trip(h1.fleet, h1.port_id, array[h1.home, h1.code], true) end as r from h1
), h3 as materialized (select h2.*, clock_timestamp() as t from h2
), r1 as materialized (select count(x.port_id) as n, (select t from h3) as t0 from who, lateral voyage.reach_passage(who.player_id, who.fleet, who.port_id, (select sr.cap_nm from public.supply_reach(who.fleet) sr)) x
), r2 as materialized (select r1.*, clock_timestamp() as t from r1
), c1 as materialized (
  select p.id, public.fleet_job_course(who.fleet, who.port_id, p.id) as c, (select t from r2) as t0
    from who, (select q.id from (select p0.id, row_number() over (order by p0.code) as i from public.ports p0 where p0.kind = 'HARBOUR') q where q.i % 12 = 5 order by q.i limit 20) p
), c2 as materialized (select count(c1.c) as n, min(c1.t0) as t0, clock_timestamp() as t from c1
), g1 as materialized (select count(voyage.segments_from_course(c1.c)) as n, (select t from c2) as t0 from c1 where c1.c is not null
), g2 as materialized (select g1.*, clock_timestamp() as t from g1
), j1 as materialized (select count(public.fleet_job_leg_shut(who.fleet, c1.id, c1.c)) as n, (select t from g2) as t0 from who, c1 where c1.c is not null
), j2 as materialized (select j1.*, clock_timestamp() as t from j1
), d1 as materialized (
  select count(public.run_day(who.player_id, who.fleet, who.port_id, c.dest, c.gid, c.units, 3600, c.cost, c.cost + c.profit, c.profit)) as n, (select t from j2) as t0 from who, cards c
), d2 as materialized (select d1.*, clock_timestamp() as t from d1)
select json_build_object(
  'at', now(), 'head', (select max(version) from supabase_migrations.schema_migrations),
  'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
  'harbour', (select code from who), 'ships', (select count(*) from public.ships s, who where s.fleet_id = who.fleet),
  'goods', (select jsonb_array_length(r->'goods') from b1), 'cut', (select r->'cut' from b1), 'cards', (select count(*) from cards), 'dests', (select count(*) from dests),
  'options', (select jsonb_array_length(r->'options') from s1), 'closed', (select r->'closed' from s1),
  'best_sales_ms', (select round(extract(epoch from t - t0) * 1000) from b1),
  'sea_actions_ms', (select round(extract(epoch from t - t0) * 1000) from s1),
  'out_ms', (select round(extract(epoch from t - t0) * 1000) from o2),
  'back_ms', (select round(extract(epoch from t - t0) * 1000) from k2),
  'home_ms', (select case when r is not null then round(extract(epoch from t - t0) * 1000) end from h3),
  'reach_ms', (select round(extract(epoch from t - t0) * 1000) from r2),
  'courses', (select n from c2), 'course_ms', (select round(extract(epoch from t - t0) * 1000) from c2),
  'segments_ms', (select round(extract(epoch from t - t0) * 1000) from g2),
  'judge_ms', (select round(extract(epoch from t - t0) * 1000) from j2),
  'run_day_ms', (select round(extract(epoch from t - t0) * 1000) from d2)) as assign_split;
rollback;
