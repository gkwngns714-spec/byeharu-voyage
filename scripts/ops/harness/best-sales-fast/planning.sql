-- PLANNING OR RUNNING? (world.best_sales' SQL-language readers on PostgreSQL 17). A PROD CHECK: read-only, ONE statement, about 250 small reads and two
-- voyage.reach_passage: under a second or two. Not in a full minute's first ten seconds.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/best-sales-fast/planning.sql
-- For each reader, over the newest docked company fleet's real ids: `one_site_ms` ONE call site asked ten times (its plan is kept for the statement's
--   run, so about 1 planning and 10 runs) and `ten_sites_ms` TEN call sites asked once each (10 plannings and 10 runs). Two warm calls come first.
--   plan_ms a call = (ten_sites_ms - one_site_ms) / 9;  run_ms a call = (one_site_ms - plan_ms) / 10.  A SQL reader that calls another plans that one
--   inside its own run, so run_ms holds it. `wc_*` is a plpgsql reader: its two figures should be alike.
-- Multiply plan_ms by the calls one best_sales makes (counted locally, Lisbon, one ship, prod's switches lit; docs/dev-log/2026-11-25-best-sales-fast.md).
-- `inline_*` is the same read written in the statement, ten rows. `reach_ms`: voyage.reach_passage twice (it plans its statements each time,
--   force_custom_plan); `edges_ms` its one large read alone (64,516 pairs, ordered), written here: what is left is its other statements and its loops.
-- `cold_ms`: one world.trip_hulls first of all in this new session, against its warm time.
-- Reads: the catalog, fleets, ships, players, ports, goods, sea_leg_asks and STABLE reads. set_config(..., true) is this transaction's identity only.
begin transaction read only;
with who as materialized (
  select f.player_id as pl, f.id as fl, f.port_id as po, (select s.id from public.ships s where s.fleet_id = f.id order by s.id limit 1) as sh,
         set_config('request.jwt.claim.sub', p.auth_uid::text, true) as a, set_config('request.jwt.claims', json_build_object('sub', p.auth_uid)::text, true) as b
    from public.fleets f join public.players p on p.id = f.player_id join public.ports pt on pt.id = f.port_id and pt.kind = 'HARBOUR'
   where f.status = 'DOCKED' and not p.is_npc and exists (select 1 from public.ships s where s.fleet_id = f.id)
   order by p.created_at desc, f.created_at, f.id limit 1
), c0 as materialized (select clock_timestamp() as t0, world.trip_hulls(fl) as v, clock_timestamp() as t from who
), w as materialized (
  select c0.t, world.trip_hulls(fl) as h, array[public.ship_cargo_tuns(sh), public.ship_hold_capacity(sh), public.ship_stores_space(sh), public.ship_stores_room(sh, 50), public.fleet_free_hold(fl),
         public.fleet_cargo_qty(fl, 'cinnamon'), public.storage_used(pl, po), public.wc_num('trade_step_tuns')] as warm, public.current_player_id() as me,
         clock_timestamp() as t1 from who, c0
), g as materialized (select g from generate_series(1, 10) g
),
-- one site, ten rows; then ten sites, one row
a1 as materialized (select count(public.ship_hold_capacity(sh)) v, (select t1 from w) t0 from who, g), a1t as materialized (select a1.*, clock_timestamp() t from a1),
a2 as materialized (select a1t.t t0, array[public.ship_hold_capacity(sh), public.ship_hold_capacity(sh), public.ship_hold_capacity(sh), public.ship_hold_capacity(sh), public.ship_hold_capacity(sh), public.ship_hold_capacity(sh), public.ship_hold_capacity(sh), public.ship_hold_capacity(sh), public.ship_hold_capacity(sh), public.ship_hold_capacity(sh)] v, clock_timestamp() t from who, a1t),
b1 as materialized (select count(public.ship_cargo_tuns(sh)) v, (select t from a2) t0 from who, g), b1t as materialized (select b1.*, clock_timestamp() t from b1),
b2 as materialized (select b1t.t t0, array[public.ship_cargo_tuns(sh), public.ship_cargo_tuns(sh), public.ship_cargo_tuns(sh), public.ship_cargo_tuns(sh), public.ship_cargo_tuns(sh), public.ship_cargo_tuns(sh), public.ship_cargo_tuns(sh), public.ship_cargo_tuns(sh), public.ship_cargo_tuns(sh), public.ship_cargo_tuns(sh)] v, clock_timestamp() t from who, b1t),
d1 as materialized (select count(public.ship_stores_space(sh)) v, (select t from b2) t0 from who, g), d1t as materialized (select d1.*, clock_timestamp() t from d1),
d2 as materialized (select d1t.t t0, array[public.ship_stores_space(sh), public.ship_stores_space(sh), public.ship_stores_space(sh), public.ship_stores_space(sh), public.ship_stores_space(sh), public.ship_stores_space(sh), public.ship_stores_space(sh), public.ship_stores_space(sh), public.ship_stores_space(sh), public.ship_stores_space(sh)] v, clock_timestamp() t from who, d1t),
e1 as materialized (select count(public.ship_stores_room(sh, 50)) v, (select t from d2) t0 from who, g), e1t as materialized (select e1.*, clock_timestamp() t from e1),
e2 as materialized (select e1t.t t0, array[public.ship_stores_room(sh, 50), public.ship_stores_room(sh, 50), public.ship_stores_room(sh, 50), public.ship_stores_room(sh, 50), public.ship_stores_room(sh, 50), public.ship_stores_room(sh, 50), public.ship_stores_room(sh, 50), public.ship_stores_room(sh, 50), public.ship_stores_room(sh, 50), public.ship_stores_room(sh, 50)] v, clock_timestamp() t from who, e1t),
f1 as materialized (select count(public.fleet_free_hold(fl)) v, (select t from e2) t0 from who, g), f1t as materialized (select f1.*, clock_timestamp() t from f1),
f2 as materialized (select f1t.t t0, array[public.fleet_free_hold(fl), public.fleet_free_hold(fl), public.fleet_free_hold(fl), public.fleet_free_hold(fl), public.fleet_free_hold(fl), public.fleet_free_hold(fl), public.fleet_free_hold(fl), public.fleet_free_hold(fl), public.fleet_free_hold(fl), public.fleet_free_hold(fl)] v, clock_timestamp() t from who, f1t),
h1 as materialized (select count(public.fleet_cargo_qty(fl, 'cinnamon')) v, (select t from f2) t0 from who, g), h1t as materialized (select h1.*, clock_timestamp() t from h1),
h2 as materialized (select h1t.t t0, array[public.fleet_cargo_qty(fl, 'cinnamon'), public.fleet_cargo_qty(fl, 'cinnamon'), public.fleet_cargo_qty(fl, 'cinnamon'), public.fleet_cargo_qty(fl, 'cinnamon'), public.fleet_cargo_qty(fl, 'cinnamon'), public.fleet_cargo_qty(fl, 'cinnamon'), public.fleet_cargo_qty(fl, 'cinnamon'), public.fleet_cargo_qty(fl, 'cinnamon'), public.fleet_cargo_qty(fl, 'cinnamon'), public.fleet_cargo_qty(fl, 'cinnamon')] v, clock_timestamp() t from who, h1t),
i1 as materialized (select count(public.storage_used(pl, po)) v, (select t from h2) t0 from who, g), i1t as materialized (select i1.*, clock_timestamp() t from i1),
i2 as materialized (select i1t.t t0, array[public.storage_used(pl, po), public.storage_used(pl, po), public.storage_used(pl, po), public.storage_used(pl, po), public.storage_used(pl, po), public.storage_used(pl, po), public.storage_used(pl, po), public.storage_used(pl, po), public.storage_used(pl, po), public.storage_used(pl, po)] v, clock_timestamp() t from who, i1t),
j1 as materialized (select count(public.current_player_id()) v, (select t from i2) t0 from who, g where g.g > 0), j1t as materialized (select j1.*, clock_timestamp() t from j1),
j2 as materialized (select j1t.t t0, array[public.current_player_id(), public.current_player_id(), public.current_player_id(), public.current_player_id(), public.current_player_id(), public.current_player_id(), public.current_player_id(), public.current_player_id(), public.current_player_id(), public.current_player_id()] v, clock_timestamp() t from who, j1t),
k1 as materialized (select count(world.trip_hulls(fl)) v, (select t from j2) t0 from who, g), k1t as materialized (select k1.*, clock_timestamp() t from k1),
k2 as materialized (select k1t.t t0, array[world.trip_hulls(fl), world.trip_hulls(fl), world.trip_hulls(fl), world.trip_hulls(fl), world.trip_hulls(fl), world.trip_hulls(fl), world.trip_hulls(fl), world.trip_hulls(fl), world.trip_hulls(fl), world.trip_hulls(fl)] v, clock_timestamp() t from who, k1t),
l1 as materialized (select count(world.trip_stow((select w.h from w), 10, 1)) v, (select t from k2) t0 from who, g where g.g > 0), l1t as materialized (select l1.*, clock_timestamp() t from l1),
l2 as materialized (select l1t.t t0, array[world.trip_stow(w.h, 10, 1), world.trip_stow(w.h, 10, 1), world.trip_stow(w.h, 10, 1), world.trip_stow(w.h, 10, 1), world.trip_stow(w.h, 10, 1), world.trip_stow(w.h, 10, 1), world.trip_stow(w.h, 10, 1), world.trip_stow(w.h, 10, 1), world.trip_stow(w.h, 10, 1), world.trip_stow(w.h, 10, 1)] v, clock_timestamp() t from w, l1t),
m1 as materialized (select count(x.v) v, (select t from l2) t0 from who, g, lateral (select b.hold as v from public.ship_base(sh) b where g.g > 0) x), m1t as materialized (select m1.*, clock_timestamp() t from m1),
m2 as materialized (select m1t.t t0, array[(select b.hold from public.ship_base(sh) b), (select b.hold from public.ship_base(sh) b), (select b.hold from public.ship_base(sh) b), (select b.hold from public.ship_base(sh) b), (select b.hold from public.ship_base(sh) b), (select b.hold from public.ship_base(sh) b), (select b.hold from public.ship_base(sh) b), (select b.hold from public.ship_base(sh) b), (select b.hold from public.ship_base(sh) b), (select b.hold from public.ship_base(sh) b)] v, clock_timestamp() t from who, m1t),
n1 as materialized (select count(public.wc_num('trade_step_tuns')) v, (select t from m2) t0 from g where g.g > 0), n1t as materialized (select n1.*, clock_timestamp() t from n1),
n2 as materialized (select n1t.t t0, array[public.wc_num('trade_step_tuns'), public.wc_num('trade_step_tuns'), public.wc_num('trade_step_tuns'), public.wc_num('trade_step_tuns'), public.wc_num('trade_step_tuns'), public.wc_num('trade_step_tuns'), public.wc_num('trade_step_tuns'), public.wc_num('trade_step_tuns'), public.wc_num('trade_step_tuns'), public.wc_num('trade_step_tuns')] v, clock_timestamp() t from n1t),
o1 as materialized (select count(x.v) v, (select t from n2) t0 from who, g, lateral (select coalesce(sum(coalesce((s.cargo ->> 'cinnamon')::numeric, 0)), 0) as v from public.ships s where s.fleet_id = who.fl and g.g > 0) x),
o1t as materialized (select o1.*, clock_timestamp() t from o1),
q1 as materialized (select count(x.port_id) v, (select t from o1t) t0 from who, lateral voyage.reach_passage(who.pl, who.fl, who.po, 1600) x), q1t as materialized (select q1.*, clock_timestamp() t from q1),
q2 as materialized (select count(x.port_id) v, (select t from q1t) t0 from who, lateral voyage.reach_passage(who.pl, who.fl, who.po, 1600) x), q2t as materialized (select q2.*, clock_timestamp() t from q2),
r1 as materialized (
  select cardinality(array_agg(coalesce(s.title_min <= 1, true) order by a.i, b.j)) v, (select t from q2t) t0
    from (select p.id, row_number() over (order by p.code) as i from public.ports p where p.kind = 'HARBOUR') a
   cross join (select p.id, row_number() over (order by p.code) as j from public.ports p where p.kind = 'HARBOUR') b
    left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = b.id), r1t as materialized (select r1.*, clock_timestamp() t from r1),
z(fn, one_ms, ten_ms) as (
  select 'ship_hold_capacity', (select extract(epoch from t - t0) * 1000 from a1t), (select extract(epoch from t - t0) * 1000 from a2)
  union all select 'ship_cargo_tuns', (select extract(epoch from t - t0) * 1000 from b1t), (select extract(epoch from t - t0) * 1000 from b2)
  union all select 'ship_stores_space', (select extract(epoch from t - t0) * 1000 from d1t), (select extract(epoch from t - t0) * 1000 from d2)
  union all select 'ship_stores_room', (select extract(epoch from t - t0) * 1000 from e1t), (select extract(epoch from t - t0) * 1000 from e2)
  union all select 'fleet_free_hold', (select extract(epoch from t - t0) * 1000 from f1t), (select extract(epoch from t - t0) * 1000 from f2)
  union all select 'fleet_cargo_qty', (select extract(epoch from t - t0) * 1000 from h1t), (select extract(epoch from t - t0) * 1000 from h2)
  union all select 'storage_used', (select extract(epoch from t - t0) * 1000 from i1t), (select extract(epoch from t - t0) * 1000 from i2)
  union all select 'current_player_id', (select extract(epoch from t - t0) * 1000 from j1t), (select extract(epoch from t - t0) * 1000 from j2)
  union all select 'trip_hulls', (select extract(epoch from t - t0) * 1000 from k1t), (select extract(epoch from t - t0) * 1000 from k2)
  union all select 'trip_stow', (select extract(epoch from t - t0) * 1000 from l1t), (select extract(epoch from t - t0) * 1000 from l2)
  union all select 'ship_base', (select extract(epoch from t - t0) * 1000 from m1t), (select extract(epoch from t - t0) * 1000 from m2)
  union all select 'wc_num (plpgsql under it)', (select extract(epoch from t - t0) * 1000 from n1t), (select extract(epoch from t - t0) * 1000 from n2)
)
select json_build_object(
  'server', current_setting('server_version'),
  'readers', (select json_agg(json_build_object('fn', z.fn, 'one_site_ms', round(z.one_ms::numeric, 2), 'ten_sites_ms', round(z.ten_ms::numeric, 2),
                                                'plan_ms', round(((z.ten_ms - z.one_ms) / 9)::numeric, 3))) from z),
  'inline_cargo_qty_ten_rows_ms', (select round((extract(epoch from t - t0) * 1000)::numeric, 2) from o1t),
  'reach_ms', (select json_build_array(round((extract(epoch from q1t.t - q1t.t0) * 1000)::numeric, 1), round((extract(epoch from q2t.t - q2t.t0) * 1000)::numeric, 1)) from q1t, q2t),
  'edges_ms', (select round((extract(epoch from t - t0) * 1000)::numeric, 1) from r1t),
  'cold_ms', (select round((extract(epoch from t - t0) * 1000)::numeric, 2) from c0), 'warm_block_ms', (select round((extract(epoch from t1 - t) * 1000)::numeric, 2) from w)) as planning;
rollback;
