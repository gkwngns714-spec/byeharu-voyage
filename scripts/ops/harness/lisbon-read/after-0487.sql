-- THE LISBON READ PLANS ONCE (0487), AFTER; ALSO THE 30-MINUTE CHECK. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/lisbon-read/after-0487.sql
-- Expect: head 20260818000487; `readers` 27, `plpgsql` 27, `md5_ok` 27 (each reader is the 0487 wrapper around its SQL body: these are the
-- md5s of the wrapped bodies as 0487 writes them; its self-assert proved each one reverses to the SQL body it found); `server` 17.x.
-- THE COST, the same reads as before-0487.sql, for the newest company's idle fleet at Lisbon: `best_sales_ms` ONE world.best_sales
-- (2,706 ms on 2026-11-24, before), `cut`, `goods`; then 80 calls each of want_left, a sell quote, port_fee, profit_tax and
-- city_bid_factor, and 800 wc (before, 2026-11-24, for 80: want_left 149.6 ms, quote 316.4 ms, port_fee 99.8 ms, profit_tax 46.6 ms,
-- city_bid_factor 32.3 ms; wc x800 19.3 ms). The 0487 self-assert's notice on the push also says the pieces before and after, timed on prod.
-- ROLLBACK (forward, if best_sales_ms is not lower or anything is red): a migration that writes each reader back as LANGUAGE sql with the
-- body inside its 0487 wrapper. The answers are the same either way.
-- Reads: as before-0487.sql. Nothing is written. ROLLBACK: nothing (ends with rollback).
begin transaction read only;
with rd as (
  select r.fn, p.oid, l.lanname, md5(replace(p.prosrc, E'\r', '')) = r.md5 as md5_ok
    from (values ('public.economy_closed()', '6ed6c98f7802e791a4decdff72a4d370'), ('public.city_treasury_on()', '0ef3d9141f24678e86a637074a414ae1'),
                 ('public.ship_stores_separate()', '985a89ccef871b2a10649cfad11e5a69'), ('public.regard_on()', '96f7276a4a8c881d73692202542184d5'),
                 ('public.world_events_on()', 'a4dcb3c0767d8a8f3ddaa9db889e13c1'), ('public.nation_race_on()', 'f98d997ea17710bc1116d3f775fd00c8'),
                 ('public.price_impact_lit()', '5160acc27c4fa4abd22190e4396c345e'), ('public.wants_lit()', 'e41813a286355645959a3473f3b06c77'),
                 ('public.pirates_on()', 'e1b4aad7625150cc814fa3c5c7cef58f'), ('public.port_is_free(uuid)', 'a9302b790321a3a4c169936037ea28fd'),
                 ('public.pirate_home(uuid)', 'b2db4c8d8728440f808d0bdeed6bfecb'), ('public.crown_house(uuid)', 'f6ed20b0b38c352f37e53873ad87212f'),
                 ('public.running_cost_mult(uuid)', '4ddcc1e1ecb5a71cbbed2de3040aa79b'), ('public.world_event_toll(uuid)', 'c05e8e811a0b61aad013e5d6504e36bd'),
                 ('public.treasury_balance(uuid)', 'c4358c80bb80d95bd3b61ae534baa361'), ('public.city_bid_factor(uuid)', 'fac0a70730e1d340294e17490887001d'),
                 ('public.works_factor(uuid,text,text)', '8639bfff1bd1daa53b37747cfa31f208'), ('public.regard_band(numeric)', '6999e00a46598d3c190ff4f072ed0c15'),
                 ('public.stores_in_hold(numeric)', '9b019f8d869ec79a0f5b3d06a45f33eb'), ('voyage.stores_need_days(numeric,numeric)', '2a4e9f08ccab06f3f977d7ade998be34'),
                 ('public.npc_leg_days(numeric,numeric)', '0662e47558a6a162ae25bbca0a250bbd'), ('voyage.fleet_speed_of(jsonb,numeric,jsonb)', '8634c1d3dcaa858bae1e794a988020a4'),
                 ('public.clock_count(text,timestamp with time zone)', '4f4e541361b85434b17382d5fbbd796a'),
                 ('public.want_period(timestamp with time zone)', '9dad6a5aa10557244e1d4c19a1f05fac'),
                 ('world.game_day(timestamp with time zone)', '0d757772b1ccb430e037658a3e15b5f2'), ('public.event_want(uuid,uuid)', '72901fe5e9a30d325b91b904c45dfc1d'),
                 ('world.want_left(uuid,uuid)', 'a8e555edf4a75384db8899bc817f63d8')) r(fn, md5)
    left join pg_proc p on p.oid = to_regprocedure(r.fn)
    left join pg_language l on l.oid = p.prolang
), who as materialized (
  select f.player_id, f.id as fleet, f.port_id,
         set_config('request.jwt.claim.sub', p.auth_uid::text, true) as a,
         set_config('request.jwt.claims', json_build_object('sub', p.auth_uid)::text, true) as b
    from public.fleets f join public.players p on p.id = f.player_id join public.ports pt on pt.id = f.port_id
   where pt.code = 'LIS' and f.status = 'DOCKED' and not p.is_npc
     and not exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active'))
   order by p.created_at desc, f.created_at, f.id limit 1
), pr as materialized (
  select who.fleet, who.player_id, h.id as port_id, g.id as good
    from who
   cross join (select p.id from (select p0.id, row_number() over (order by p0.code) as k from public.ports p0 where p0.kind = 'HARBOUR') p where p.k % 32 = 1) h
   cross join (select g0.id from public.port_goods pg join public.goods g0 on g0.id = pg.good_id
                where pg.port_id = (select port_id from who) and public.port_offers(pg.port_id, g0.id) order by g0.code limit 10) g
   limit 80
), t0 as materialized (select clock_timestamp() as t1 from who
), bs as materialized (select t0.t1 as t0, world.best_sales(who.fleet, who.port_id) as r, clock_timestamp() as t1 from t0, who
), wl as materialized (select bs.t1 as t0, (select count(x.mult) from pr cross join lateral world.want_left(pr.port_id, pr.good) x) as v, clock_timestamp() as t1 from bs
), q as materialized (select wl.t1 as t0, (select count(x.total) from pr cross join lateral world.quote(pr.port_id, pr.good, 20, 'sell', null, pr.fleet) x) as v, clock_timestamp() as t1 from wl
), pf as materialized (select q.t1 as t0, (select count(public.port_fee(pr.port_id, pr.player_id, 1000)) from pr) as v, clock_timestamp() as t1 from q
), pt as materialized (select pf.t1 as t0, (select count(public.profit_tax(pr.port_id, 1000, pr.player_id)) from pr) as v, clock_timestamp() as t1 from pf
), bf as materialized (select pt.t1 as t0, (select count(public.city_bid_factor(pr.port_id)) from pr) as v, clock_timestamp() as t1 from pt
), wc as materialized (select bf.t1 as t0, (select count(public.wc(case when k > 0 then 'time_compression' end)) from generate_series(1, 800) k) as v, clock_timestamp() as t1 from bf
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'server', current_setting('server_version'),
  'readers', (select count(*) from rd where rd.oid is not null),
  'sql', (select count(*) from rd where rd.lanname = 'sql'),
  'plpgsql', (select count(*) from rd where rd.lanname = 'plpgsql'),
  'md5_ok', (select count(*) from rd where rd.md5_ok),
  'not_ok', (select jsonb_agg(rd.fn) from rd where not coalesce(rd.md5_ok, false)),
  'at', (select p.code from who join public.ports p on p.id = who.port_id),
  'best_sales_ms', (select round(extract(epoch from bs.t1 - bs.t0)::numeric * 1000) from bs),
  'cut', (select bs.r -> 'cut' from bs),
  'goods', (select jsonb_array_length(bs.r -> 'goods') from bs),
  'pairs', (select count(*) from pr),
  'ms', jsonb_build_object(
    'want_left', (select round(extract(epoch from t1 - t0)::numeric * 1000, 1) from wl),
    'quote', (select round(extract(epoch from t1 - t0)::numeric * 1000, 1) from q),
    'port_fee', (select round(extract(epoch from t1 - t0)::numeric * 1000, 1) from pf),
    'profit_tax', (select round(extract(epoch from t1 - t0)::numeric * 1000, 1) from pt),
    'city_bid_factor', (select round(extract(epoch from t1 - t0)::numeric * 1000, 1) from bf),
    'wc_800', (select round(extract(epoch from t1 - t0)::numeric * 1000, 1) from wc))
) as r;
rollback;
