-- THE LISBON READ PLANS ONCE (0487), BEFORE. A PROD CHECK: read-only, ONE statement. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/lisbon-read/before-0487.sql
-- Expect: head 20260818000486; `readers` 27, `sql` 27, `md5_ok` 27 (each of the 27 readers is LANGUAGE sql with the body 0487 was
-- written against; 0487's self-assert refuses any other); `server` 17.x.
-- THE COST, for the newest company's idle fleet at Lisbon (her identity set for this transaction alone: set_config, local):
--   `best_sales_ms` ONE world.best_sales (2026-11-24 diagnosis: 2,706 ms, EXPLAIN ANALYZE; pg_stat_statements mean 2,271 ms over 208
--   board calls), `cut`, `goods`; then 80 calls each, over the goods Lisbon sells at every 32nd harbour by code (8 harbours x 10 goods): `want_left` (1.87 ms a
--   call), `quote` a sell of 20 (3.95 ms), `port_fee` (1.25 ms), `profit_tax` (0.58 ms), `city_bid_factor` (0.40 ms); `wc` 800 calls (24 us).
-- Reads: the catalog, world_config by key, players, fleets, ports, port_goods, goods, orders, and the STABLE reads above (all 27 readers
-- and every function world.best_sales calls are STABLE: diagnosis read 1). set_config(..., true) sets this transaction's identity only.
-- Nothing is written. ROLLBACK: nothing (ends with rollback).
begin transaction read only;
with rd as (
  select r.fn, p.oid, l.lanname, md5(replace(p.prosrc, E'\r', '')) = r.md5 as md5_ok
    from (values ('public.economy_closed()', 'f78659ae4bc972be757c25e547999998'), ('public.city_treasury_on()', 'edd922cbf5b7607570875c75d5e397d7'),
                 ('public.ship_stores_separate()', '072701313c80ebe489aa48f33c9ac796'), ('public.regard_on()', 'f9cf5e1d0a4829bed73d03bf6c33fdf6'),
                 ('public.world_events_on()', '50d4f15eb8420cb18fa0143b308441b7'), ('public.nation_race_on()', '195db19c46e348717cc068b5baee4fc1'),
                 ('public.price_impact_lit()', '9bdfe0755be06ae0656721dfb0557b17'), ('public.wants_lit()', '893a420aa27485b9e57d9158fd618d88'),
                 ('public.pirates_on()', '0f8e3252470d2a95c5ffd53d49b41360'), ('public.port_is_free(uuid)', '689788fa761e94f4ffeb6830dcdc8d02'),
                 ('public.pirate_home(uuid)', '8436e15a58f06b6901ddee450af0d970'), ('public.crown_house(uuid)', '16a77f26c77c1f3e9b555b5fec0baf46'),
                 ('public.running_cost_mult(uuid)', '15dbe5b056ace091e5df3f9019d039fc'), ('public.world_event_toll(uuid)', 'fcff32019e25dd77566bd46cb0af8567'),
                 ('public.treasury_balance(uuid)', '707eeee39e6223a034e3ac608bee6a98'), ('public.city_bid_factor(uuid)', '37200d1406b2aebfdcdf1c6fac30d895'),
                 ('public.works_factor(uuid,text,text)', '7909a61c0169eb81a8ff37155d4fb335'), ('public.regard_band(numeric)', '9f6fce83cdddf59b13599cac020216b0'),
                 ('public.stores_in_hold(numeric)', '5c520d9a77929ddbeb8a864f9ee29783'), ('voyage.stores_need_days(numeric,numeric)', 'cc09a0b1ae180130219ccd6d32a52372'),
                 ('public.npc_leg_days(numeric,numeric)', '3fdfe3d1c09b7d1145fddbfdd2a2de41'), ('voyage.fleet_speed_of(jsonb,numeric,jsonb)', '0a9afd9784bdb8078fbeb2fe9a2d94ad'),
                 ('public.clock_count(text,timestamp with time zone)', 'a558fe09fcec00c3b572c83fb19c0d15'),
                 ('public.want_period(timestamp with time zone)', '1c09bbed1321d26e6702aa8e059895f7'),
                 ('world.game_day(timestamp with time zone)', '4e02e28f964ad51a6019ee83d44d64fe'), ('public.event_want(uuid,uuid)', '4eb6272ceb04bac48be6769877c25e0d'),
                 ('world.want_left(uuid,uuid)', '008e3f6bdb30d75c745bdee667714a4c')) r(fn, md5)
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
