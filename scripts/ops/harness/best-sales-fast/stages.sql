-- WHERE ONE world.best_sales GOES, STAGE BY STAGE, AND HOW FAST THE MACHINE IS. A PROD CHECK: read-only, ONE statement, about 7 s on prod (two whole reads, 4.6 s
-- of it). NOT in a full minute's first ten seconds. The local figures are in the dev log: the yardsticks' ratio is the machine's.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/best-sales-fast/stages.sql
-- YARDSTICKS (no table): `cpu_float` sum of 400,000 square roots; `cpu_numeric` 100,000 numeric products; `cpu_power` 4,500 numeric powers (a read's price steps);
--   `calls` 3,000 calls of a small plpgsql reader (public.economy_closed; a read makes about 18,000 small calls); `port_rows` 2,540 port_goods rows by good_id.
-- STAGES, asked as best_sales' body asks them, for the newest docked company fleet (her identity for this transaction alone: set_config, local):
--   whole_1 the read first in this session (plans cold), whole_2 the same again at the end (warm); offered; origin (world.board_origin, its one reach_passage
--   inside); hulls (trip_hulls and fleet_speed_parts); legs (world.board_legs, nothing walked); amounts (board_amount a good); capacity (fleet_buy_capacity a
--   good: the sale allowances and the purse's quotes); half (world.price and the half-coin buy quote a good); sells (world.board_sell_memo a good, the first
--   good's memo handed to the rest). The top-up and the choice of cards are what is left: whole_2 less the sum of offered .. sells.
-- INSIDE `sells`, asked alone for FIVE goods (n is the count; scale by goods / 5): mids (world.good_mids), quotes (world.quote sells of the priced rows), quay
--   (world.quote_quay a harbour), dock (public.port_fee_terms a harbour), tax (world.tax_rate a harbour), trips (world.board_trips a good over its rows).
--   `quotes` reads its own terms, so it holds a quay read each: take n x quay's ms a call off it.
-- Reads: the catalog, fleets, ships, players, ports, goods, port_goods and STABLE reads. Nothing is written. ROLLBACK: nothing.
begin transaction read only;
with who as materialized (
  select f.player_id as pl, f.id as fl, f.port_id as po, pt.code, p.ducats as purse,
         set_config('request.jwt.claim.sub', p.auth_uid::text, true) as a, set_config('request.jwt.claims', json_build_object('sub', p.auth_uid)::text, true) as b
    from public.fleets f join public.players p on p.id = f.player_id join public.ports pt on pt.id = f.port_id and pt.kind = 'HARBOUR'
   where f.status = 'DOCKED' and not p.is_npc and exists (select 1 from public.ships s where s.fleet_id = f.id)
   order by p.created_at desc, f.created_at, f.id limit 1
),
y0 as materialized (select clock_timestamp() t from who),
y1 as materialized (select (select sum(sqrt(g::float8)) from generate_series(1, 400000) g where y0.t is not null) v, y0.t t0 from y0), y1t as materialized (select y1.t0, y1.v, clock_timestamp() t from y1),
y2 as materialized (select (select sum(g::numeric * 1.0312 * 0.985) from generate_series(1, 100000) g where y1t.t is not null) v, y1t.t t0 from y1t), y2t as materialized (select y2.t0, y2.v, clock_timestamp() t from y2),
y3 as materialized (select (select sum(power(1234.5::numeric / g, 0.35)) from generate_series(1, 4500) g where y2t.t is not null) v, y2t.t t0 from y2t), y3t as materialized (select y3.t0, y3.v, clock_timestamp() t from y3),
y4 as materialized (select (select count(*) filter (where public.economy_closed()) from generate_series(1, 3000) g where y3t.t is not null and g > 0) v, y3t.t t0 from y3t), y4t as materialized (select y4.t0, y4.v, clock_timestamp() t from y4),
gl as materialized (select g.id, g.code, row_number() over (order by g.code) i from who join public.port_goods pg on pg.port_id = who.po join public.goods g on g.id = pg.good_id
                     where (select t from y4t) is not null and public.port_offers(who.po, g.id)),
y5 as materialized (select (select sum(pg.stock) from public.port_goods pg where pg.good_id in (select id from gl)) v, (select count(*) from gl) n, y4t.t t0 from y4t), y5t as materialized (select y5.*, clock_timestamp() t from y5),
w1 as materialized (select world.best_sales(who.fl, who.po) r, y5t.t t0 from who, y5t), w1t as materialized (select w1.*, clock_timestamp() t from w1),
s1 as materialized (select count(g.id) n, (select t from w1t) t0 from who join public.port_goods pg on pg.port_id = who.po join public.goods g on g.id = pg.good_id where (select t from w1t) is not null and public.port_offers(who.po, g.id)),
s1t as materialized (select s1.*, clock_timestamp() t from s1),
s2 as materialized (select world.board_origin(who.fl) o, s1t.t t0 from who, s1t), s2t as materialized (select s2.*, clock_timestamp() t from s2),
s3 as materialized (select world.trip_hulls(who.fl) h, voyage.fleet_speed_parts(who.fl) p, s2t.t t0 from who, s2t), s3t as materialized (select s3.*, clock_timestamp() t from s3),
o as materialized (select s2t.o || jsonb_build_object('trip_fleet', who.fl, 'trip_hulls', s3t.h, 'speed_parts', s3t.p, 'basis', 'asked', 'units', 1, 'src', jsonb_build_object('code', who.code),
                                                      'src_cut', false, 'lean', true) as c, s3t.t from who, s2t, s3t),
s4 as materialized (select world.board_legs(who.fl, o.c || jsonb_build_object('only', '[]'::jsonb)) l, o.t t0 from who, o), s4t as materialized (select s4.*, clock_timestamp() t from s4),
s5 as materialized (select gl.id, gl.code, gl.i, a.units, a.basis, (select t from s4t) t0 from who, gl, lateral world.board_amount(who.fl, gl.id, null) a where (select t from s4t) is not null),
s5t as materialized (select count(*) n, min(s5.t0) t0, clock_timestamp() t from s5),
s6 as materialized (select gl.id, gl.i, public.fleet_buy_capacity(who.fl, gl.id) c, s5t.t t0 from who, gl, s5t), s6t as materialized (select count(*) n, min(s6.t0) t0, clock_timestamp() t from s6),
s7 as materialized (
  select s6.id, s6.i, x.n, qb.units, qb.total, s6t.t t0
    from who, s6t, s6
    join lateral (select greatest(1, least(floor(who.purse * 0.5 / q.ask), greatest((s6.c->>'max_qty')::numeric, 1))) as n from world.price(who.po, s6.id) q where q.ask > 0) x on true
    join lateral world.quote(who.po, s6.id, x.n, 'buy', null, who.fl) qb on true),
s7t as materialized (select count(*) n, min(s7.t0) t0, clock_timestamp() t from s7),
ctx as materialized (select s7.id, s7.i, s7.units, o.c || jsonb_build_object('legs', s4t.l, 'units', s7.units, 'basis', 'asked', 'fit', false, 'src', jsonb_build_object('code', who.code, 'units', s7.units, 'cost', s7.total)) as c
                       from who, o, s4t, s7, s7t where s7.units > 0),
s8a as materialized (select m.o_rows, m.o_memo, ctx.i, (select t from s7t) t0 from who, ctx, lateral world.board_sell_memo(ctx.id, who.fl, ctx.c, null) m where ctx.i = (select min(i) from ctx)),
s8at as materialized (select s8a.*, clock_timestamp() t from s8a),
s8b as materialized (select ctx.id, ctx.i, m.o_rows from who, s8at, ctx, lateral world.board_sell_memo(ctx.id, who.fl, ctx.c, s8at.o_memo) m where ctx.i <> s8at.i),
s8t as materialized (select (select count(*) from s8b) + 1 n, (select t0 from s8at) t0, (select t from s8at) t1, (select clock_timestamp() from (select count(*) from s8b) z) t),
rw as materialized (
  select z.gid, (r->>'port') as code, p.id as port, (r->>'units')::numeric as n, z.i
    from (select ctx.id as gid, s8at.o_rows as rr, s8at.i from s8at join ctx on ctx.i = s8at.i union all select s8b.id, s8b.o_rows, s8b.i from s8b) z
   cross join lateral jsonb_array_elements(z.rr) r join public.ports p on p.code = r->>'port'
   where z.i <= (select min(i) + 4 from ctx) and (select t from s8t) is not null),
hb as materialized (select distinct rw.port from rw),
m1 as materialized (select count(x.mid) n, (select t from s8t) t0 from gl, lateral world.good_mids(gl.id) x where gl.i <= 5 and (select count(*) from hb) >= 0 and (select t from s8t) is not null), m1t as materialized (select m1.*, clock_timestamp() t from m1),
m2 as materialized (select count(q.total) n, (select t from m1t) t0 from who, rw, lateral world.quote(rw.port, rw.gid, rw.n, 'sell', null, who.fl) q where rw.n > 0 and (select t from m1t) is not null), m2t as materialized (select m2.*, clock_timestamp() t from m2),
m3 as materialized (select count(world.quote_quay(hb.port, who.fl)) n, (select t from m2t) t0 from who, hb where (select t from m2t) is not null), m3t as materialized (select m3.*, clock_timestamp() t from m3),
m4 as materialized (select count(*) filter (where public.port_fee_terms(hb.port, who.pl) is not null) v, count(*) n, (select t from m3t) t0 from who, hb where (select t from m3t) is not null), m4t as materialized (select m4.*, clock_timestamp() t from m4),
m5 as materialized (select count(world.tax_rate(hb.port, who.pl)) n, (select t from m4t) t0 from who, hb where (select t from m4t) is not null), m5t as materialized (select m5.*, clock_timestamp() t from m5),
m6 as materialized (
  select count(world.board_trips(who.fl, ctx.c || jsonb_build_object('buy', jsonb_build_object('units', ctx.units, 'bulk', g.bulk), 'only', (select jsonb_agg(rw.port) from rw where rw.gid = ctx.id)), (select l from s4t))) n,
         (select t from m5t) t0
    from who, ctx join public.goods g on g.id = ctx.id where ctx.i <= (select min(i) + 4 from ctx) and (select t from m5t) is not null), m6t as materialized (select m6.*, clock_timestamp() t from m6),
w2 as materialized (select world.best_sales(who.fl, who.po) r, m6t.t t0 from who, m6t), w2t as materialized (select w2.*, clock_timestamp() t from w2),
k(stage, n, ms) as (
  select 'cpu_float', 400000, extract(epoch from t - t0) * 1000 from y1t union all select 'cpu_numeric', 100000, extract(epoch from t - t0) * 1000 from y2t
  union all select 'cpu_power', 4500, extract(epoch from t - t0) * 1000 from y3t union all select 'calls', 3000, extract(epoch from t - t0) * 1000 from y4t
  union all select 'port_rows', n * 254, extract(epoch from t - t0) * 1000 from y5t union all select 'whole_1', 1, extract(epoch from t - t0) * 1000 from w1t
  union all select 'offered', n, extract(epoch from t - t0) * 1000 from s1t union all select 'origin', 1, extract(epoch from t - t0) * 1000 from s2t
  union all select 'hulls', 1, extract(epoch from t - t0) * 1000 from s3t union all select 'legs', 1, extract(epoch from t - t0) * 1000 from s4t
  union all select 'amounts', n, extract(epoch from t - t0) * 1000 from s5t union all select 'capacity', n, extract(epoch from t - t0) * 1000 from s6t
  union all select 'half', n, extract(epoch from t - t0) * 1000 from s7t union all select 'sells', n, extract(epoch from t - t0) * 1000 from s8t
  union all select 'in_sells: mids', n, extract(epoch from t - t0) * 1000 from m1t union all select 'in_sells: quotes', n, extract(epoch from t - t0) * 1000 from m2t
  union all select 'in_sells: quay', n, extract(epoch from t - t0) * 1000 from m3t union all select 'in_sells: dock', n, extract(epoch from t - t0) * 1000 from m4t
  union all select 'in_sells: tax', n, extract(epoch from t - t0) * 1000 from m5t union all select 'in_sells: trips', n, extract(epoch from t - t0) * 1000 from m6t
  union all select 'whole_2', 1, extract(epoch from t - t0) * 1000 from w2t)
select json_build_object(
  'server', current_setting('server_version'), 'harbour', (select code from who), 'goods', (select count(*) from gl), 'ships', (select count(*) from public.ships s, who where s.fleet_id = who.fl),
  'cut', (select json_build_array((select r->'cut' from w1t), (select r->'cut' from w2t))),
  'stages', (select json_agg(json_build_object('s', stage, 'n', n, 'ms', round(ms::numeric, 1), 'each', round((ms / nullif(n, 0))::numeric, 3))) from k),
  'sum_of_stages', (select round(sum(ms)::numeric) from k where stage in ('offered', 'origin', 'hulls', 'legs', 'amounts', 'capacity', 'half', 'sells'))) as stages;
rollback;
