-- A HARBOUR IS ASKED ONCE (0488), BEFORE. A PROD CHECK: read-only, ONE statement. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/harbour-reuse/before-0488.sql
-- Expect: head 20260818000487; `bodies` 6, `md5_ok` 6 (each of the six bodies 0488 re-cuts is the one it was written against; its
--   self-assert refuses any other); `new` 0 (none of the nine new pieces yet); `lit` 16 of 16 (the switches 0488's probe lights are all
--   on: its probe then skips the dark pass); `server` 17.x.
-- THE COST, for the newest company's idle fleet at Lisbon (her identity set for this transaction alone: set_config, local, as
--   lisbon-read/before-0487.sql did): `best_sales_ms` ONE world.best_sales (after 0487: 1,777-1,957 ms, not cut), `cut`, `goods`;
--   then 80 calls each, over the goods Lisbon sells at every 32nd harbour by code (8 harbours x 10 goods): a sell quote of 20
--   (`quote`), `quote_terms` with her fleet, `port_fee` (cargo 1,000) and `profit_tax` (profit 1,000). ONE call of best_sales: it is time-budgeted (2.5 s), so it is never compared with another call; the
--   80-call reads say where the time went.
-- Reads: the catalog, world_config by key, players, fleets, ports, port_goods, goods, orders, and STABLE reads (world.best_sales and
--   every function it calls are STABLE). set_config(..., true) sets this transaction's identity only. Nothing is written.
-- ROLLBACK: nothing (ends with rollback).
begin transaction read only;
with rd as (
  select r.fn, p.oid, md5(replace(p.prosrc, E'\r', '')) = r.md5 as md5_ok
    from (values ('world.best_sales(uuid,uuid)', '3f71e6c4c3e6ab4241af0d546e2bdec5'), ('world.board_sell(uuid,uuid,jsonb)', '081f8ae0ac7be74eebb5dfc13a277cf1'),
                 ('world.quote_terms(uuid,uuid,uuid)', 'bfa36c9da145c6069bf3e82305d0e193'),
                 ('world.spread_effective_pair(uuid,uuid,uuid,boolean)', '72d155cfc975946ddedd0638979175a9'),
                 ('public.port_fee(uuid,uuid,numeric)', '4b843a11bf97913cbb6a54867ce40c91'), ('public.profit_tax(uuid,numeric,uuid)', '38d1efc7e3e15ddf6150e056dbd75c20')) r(fn, md5)
    left join pg_proc p on p.oid = to_regprocedure(r.fn)
), nw as (
  select count(*) as n
    from unnest(array['world.spread_parts(uuid,uuid)', 'world.spread_purser(uuid,uuid)', 'world.spread_pair_from(uuid,uuid,uuid,boolean,numeric[],numeric)',
                      'world.quote_quay(uuid,uuid)', 'world.quote_terms_from(uuid,uuid,uuid,numeric[],numeric)', 'public.port_fee_terms(uuid,uuid)',
                      'public.port_fee_of(numeric[],numeric)', 'public.profit_tax_at(boolean,numeric,numeric)', 'world.board_sell_memo(uuid,uuid,jsonb,jsonb)']) u
   where to_regprocedure(u) is not null
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
), q as materialized (select bs.t1 as t0, (select count(x.total) from pr cross join lateral world.quote(pr.port_id, pr.good, 20, 'sell', null, pr.fleet) x) as v, clock_timestamp() as t1 from bs
), qt as materialized (select q.t1 as t0, (select count(x.q_spread) from pr cross join lateral world.quote_terms(pr.port_id, pr.good, pr.fleet) x) as v, clock_timestamp() as t1 from q
), pf as materialized (select qt.t1 as t0, (select count(public.port_fee(pr.port_id, pr.player_id, 1000)) from pr) as v, clock_timestamp() as t1 from qt
), pt as materialized (select pf.t1 as t0, (select count(public.profit_tax(pr.port_id, 1000, pr.player_id)) from pr) as v, clock_timestamp() as t1 from pf
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'server', current_setting('server_version'),
  'bodies', (select count(*) from rd where rd.oid is not null),
  'md5_ok', (select count(*) from rd where rd.md5_ok),
  'not_ok', (select jsonb_agg(rd.fn) from rd where not coalesce(rd.md5_ok, false)),
  'new', (select n from nw),
  'lit', (select count(*) from public.world_config c
           where c.value = 'true'::jsonb
             and c.key in ('economy_closed', 'city_treasury_enabled', 'city_wants', 'world_events_enabled', 'regard_enabled', 'nation_race_enabled',
                           'price_impact', 'pirates_bite', 'pirate_ports_free', 'ship_stores_separate', 'influence_enabled', 'logbook_enabled',
                           'goods_mastery_enabled', 'first_hour_enabled', 'near_choice_enabled', 'levels_bite')),
  'at', (select p.code from who join public.ports p on p.id = who.port_id),
  'best_sales_ms', (select round(extract(epoch from bs.t1 - bs.t0)::numeric * 1000) from bs),
  'cut', (select bs.r -> 'cut' from bs),
  'goods', (select jsonb_array_length(bs.r -> 'goods') from bs),
  'pairs', (select count(*) from pr),
  'ms', jsonb_build_object(
    'quote', (select round(extract(epoch from t1 - t0)::numeric * 1000, 1) from q),
    'quote_terms', (select round(extract(epoch from t1 - t0)::numeric * 1000, 1) from qt),
    'port_fee', (select round(extract(epoch from t1 - t0)::numeric * 1000, 1) from pf),
    'profit_tax', (select round(extract(epoch from t1 - t0)::numeric * 1000, 1) from pt))
) as r;
rollback;
