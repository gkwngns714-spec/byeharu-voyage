-- LISBON READ, DIAGNOSIS 2 (run on prod 2026-11-24 as its read 3 of 3, before 0487; answered 2026-11-24 on prod, for 80 calls each: quote 316.4 ms, want_left 149.6, daily_cap_remaining 139.4, world.price 93.7,
-- quote_terms 93.9, port_fee 99.8, spread_effective_pair 55.4, profit_tax 46.6, city_bid_factor 32.3, world.spread 32.0, tax_rate 17.4,
-- mid_terms 10.4, crew_pct 5.8, treasury_balance 5.2; fleet_buy_capacity x10 126.5; wc x800 19.3. Settings: auto_explain at 10 s without
-- analyze, pgaudit.log none, plpgsql_check profiler off: none of them in the way.)
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/lisbon-read/diagnose-2.sql
-- LISBON READ, THE QUOTE'S PARTS (prod read 3 of 3). A plain SELECT; read-only; every function called is STABLE or IMMUTABLE (read 1),
-- except set_config(..., true), this transaction's identity only. Ends with rollback.
begin transaction read only;
with who as materialized (
  select f.player_id, p.auth_uid, f.id as fleet, f.port_id,
         set_config('request.jwt.claim.sub', p.auth_uid::text, true) as a,
         set_config('request.jwt.claims', json_build_object('sub', p.auth_uid)::text, true) as b
    from public.fleets f join public.players p on p.id = f.player_id join public.ports pt on pt.id = f.port_id
   where pt.code = 'LIS' and f.status = 'DOCKED' and not p.is_npc
     and not exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active'))
   order by p.created_at desc, f.created_at, f.id limit 1
), gl as materialized (
  select g.id from who join public.port_goods pg on pg.port_id = who.port_id join public.goods g on g.id = pg.good_id
   where public.port_offers(who.port_id, g.id)
), pr as materialized (
  select who.fleet, who.player_id, pp.port_id, gl.id as good
    from who cross join gl
   cross join lateral (select pg.port_id from public.port_goods pg where pg.good_id = gl.id order by pg.port_id limit 8) pp
), t0 as materialized (select clock_timestamp() as t1 from pr limit 1
), q as materialized (select t0.t1 as t0, (select count(x.total) from pr cross join lateral world.quote(pr.port_id, pr.good, 20, 'sell', null, pr.fleet) x) as v, clock_timestamp() as t1 from t0
), qt as materialized (select q.t1 as t0, (select count(x.q_bidf) from pr cross join lateral world.quote_terms(pr.port_id, pr.good, pr.fleet) x) as v, clock_timestamp() as t1 from q
), mt as materialized (select qt.t1 as t0, (select count(x.m_base) from pr cross join lateral world.mid_terms(pr.port_id, pr.good) x) as v, clock_timestamp() as t1 from qt
), sp as materialized (select mt.t1 as t0, (select count(x.q_spread) from pr cross join lateral world.spread_effective_pair(pr.port_id, pr.good, pr.fleet, true) x) as v, clock_timestamp() as t1 from mt
), ws as materialized (select sp.t1 as t0, (select count(world.spread(pr.port_id)) from pr) as v, clock_timestamp() as t1 from sp
), bf as materialized (select ws.t1 as t0, (select count(public.city_bid_factor(pr.port_id)) from pr) as v, clock_timestamp() as t1 from ws
), tb as materialized (select bf.t1 as t0, (select count(public.treasury_balance(pr.port_id)) from pr) as v, clock_timestamp() as t1 from bf
), gm as materialized (select tb.t1 as t0, (select count(public.goods_mastery_bid(pr.fleet, pr.good, 0.1)) from pr) as v, clock_timestamp() as t1 from tb
), tr as materialized (select gm.t1 as t0, (select count(world.tax_rate(pr.port_id)) from pr) as v, clock_timestamp() as t1 from gm
), wl as materialized (select tr.t1 as t0, (select count(x.mult) from pr cross join lateral world.want_left(pr.port_id, pr.good) x) as v, clock_timestamp() as t1 from tr
), cp as materialized (select wl.t1 as t0, (select count(public.crew_pct(pr.fleet, null, 'spread', pr.good)) from pr) as v, clock_timestamp() as t1 from wl
), iv as materialized (select cp.t1 as t0, (select count(public.investor_shave(pr.player_id, pr.port_id)) from pr) as v, clock_timestamp() as t1 from cp
), hg as materialized (select iv.t1 as t0, (select count(public.haggle_concession(pr.player_id, pr.port_id, pr.good)) from pr) as v, clock_timestamp() as t1 from iv
), pf as materialized (select hg.t1 as t0, (select count(public.port_fee(pr.port_id, pr.player_id, 1000)) from pr) as v, clock_timestamp() as t1 from hg
), pt as materialized (select pf.t1 as t0, (select count(public.profit_tax(pr.port_id, 1000, pr.player_id)) from pr) as v, clock_timestamp() as t1 from pf
), dc as materialized (select pt.t1 as t0, (select count(world.daily_cap_remaining(pr.player_id, pr.port_id, pr.good)) from pr) as v, clock_timestamp() as t1 from pt
), wp as materialized (select dc.t1 as t0, (select count(x.ask) from pr cross join lateral world.price(pr.port_id, pr.good) x) as v, clock_timestamp() as t1 from dc
), bc as materialized (select wp.t1 as t0, (select count(public.fleet_buy_capacity(who.fleet, gl.id)) from who cross join gl) as v, clock_timestamp() as t1 from wp
), wc as materialized (select bc.t1 as t0, (select count(public.wc(case when k > 0 then 'time_compression' end)) from generate_series(1, 800) k) as v, clock_timestamp() as t1 from bc
), ms as (
  select x.k, round(extract(epoch from x.t1 - x.t0)::numeric * 1000, 1) as ms, x.v
    from (select 'quote' k, t0, t1, v from q union all select 'quote_terms', t0, t1, v from qt union all select 'mid_terms', t0, t1, v from mt
          union all select 'spread_effective_pair', t0, t1, v from sp union all select 'world.spread', t0, t1, v from ws
          union all select 'city_bid_factor', t0, t1, v from bf union all select 'treasury_balance', t0, t1, v from tb
          union all select 'goods_mastery_bid', t0, t1, v from gm union all select 'tax_rate', t0, t1, v from tr
          union all select 'want_left', t0, t1, v from wl union all select 'crew_pct', t0, t1, v from cp
          union all select 'investor_shave', t0, t1, v from iv union all select 'haggle_concession', t0, t1, v from hg
          union all select 'port_fee', t0, t1, v from pf union all select 'profit_tax', t0, t1, v from pt
          union all select 'daily_cap_remaining', t0, t1, v from dc union all select 'world.price', t0, t1, v from wp
          union all select 'fleet_buy_capacity', t0, t1, v from bc union all select 'wc', t0, t1, v from wc) x
)
select jsonb_build_object(
  'pairs', (select count(*) from pr), 'goods', (select count(*) from gl),
  'ms', (select jsonb_object_agg(ms.k, jsonb_build_array(ms.ms, ms.v)) from ms),
  'switches', (select jsonb_object_agg(c.key, c.value) from public.world_config c where jsonb_typeof(c.value) = 'boolean'),
  'flows', (select jsonb_build_object('lis', (select count(*) from public.treasury_flows f join who on f.port_id = who.port_id),
                                      'est_all', (select c.reltuples from pg_class c where c.oid = 'public.treasury_flows'::regclass))),
  'settings', (select jsonb_object_agg(n, current_setting(n, true)) from unnest(array['auto_explain.log_min_duration', 'auto_explain.log_analyze',
                 'auto_explain.log_nested_statements', 'auto_explain.log_timing', 'auto_explain.sample_rate', 'auto_explain.log_buffers',
                 'pgaudit.log', 'pgaudit.log_level', 'pgaudit.log_catalog', 'pgaudit.log_relation', 'plpgsql_check.profiler', 'plpgsql_check.mode',
                 'plan_filter.statement_cost_limit', 'log_min_duration_statement', 'log_statement', 'session_user', 'current_user']) n),
  'role_settings', (select jsonb_agg(jsonb_build_object('role', r.rolname, 'db', s.setdatabase <> 0, 'cfg', s.setconfig))
                      from pg_db_role_setting s left join pg_roles r on r.oid = s.setrole),
  'who', (select jsonb_build_object('ships', (select count(*) from public.ships s where s.fleet_id = who.fleet),
                                    'seated', (select count(*) from public.ships s join public.captain_seats cs on cs.ship_id = s.id where s.fleet_id = who.fleet))
            from who)
) as r;
rollback;
