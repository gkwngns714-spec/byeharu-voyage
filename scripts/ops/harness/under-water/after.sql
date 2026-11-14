-- 0410 PROD CHECK AND THE STANDING HEALTH CHECK OF THE MERCHANTS' LAPS, read-only, ONE statement (the same read as before.sql):
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/under-water/after.sql      at +1 h, +3 h, +6 h and +24 h, and whenever asked
-- One row, one jsonb column `r`.
-- BEFORE, wanted: head 20260818000409; cut: every value false; hunks: every count 1 (each of the six hunks' old text occurs once in
--   the live body); volatility: every value s or i.
-- AFTER, wanted: head 20260818000410; cut: every value true.
-- WHAT IT MEASURES. ALL COSTS COUNTED: a house's result in a window is her closed laps' net BEFORE dock fees (net + the lap's own fees column,
--   which is 0 on laps closed before 0410) less the PORT_FEE rows of her ledger in the window (a merchant's ledger is kept 6 hours), so the
--   figure is the same on both sides of the deploy.
--   health.six_hours: houses that closed a lap in the last 360 minutes; under_water = those whose result is under nothing; under_water_pct;
--     bleed_k = the sum of the negative results (thousands); sum_k = the sum of all. health.hour: the same over 60 minutes (0406's measure).
--     AN HOUR IS NOISE: the price walks 3 % a minute (drift_sigma, a 60-second slot), so in any one hour about three houses in ten have a bad
--     hour and they are mostly different houses the next hour. Judge by six_hours.
--   laps_hour: laps closed in the last hour, the losing ones, the ones that traded nothing (and still paid a dock fee at every call).
--   newest_laps: over the orders still kept (each route's newest closed lap, the last hour): sales below cost (the cut-loss: `SELL <good> ALL`
--     with no limit) and what they lost; at-profit sales and what they made; SELLs refused E_PRICE_LIMIT and E_CITY_BROKE.
--   purse: the BUY lines standing on sailing merchants' routes, and those whose parcel (at its limit) is more than the purse of the city it is
--     bound for holds now (0410 sizes a parcel by that purse at the plan; other sales drain a purse after the plan, so this is not 0).
-- THE NUMBERS IT SHOULD STAY UNDER (read 2026-11-14 before 0410: six_hours 15.6 %, hour 27.8 to 33.2 %, sales below cost 1.28 M d. an hour in the
--   newest laps, purse.cannot_pay 232 of 918 lines):
--     health.six_hours.under_water_pct UNDER 12. Over 15 for two reads running = the fix did not hold or a new uncounted cost is live: read
--       public.lap_costs and proof 105.
--     purse.cannot_pay_pct UNDER 10.      newest_laps.below_cost_loss_k falling against the before read.
begin transaction read only;
with hk(ord, fn, old) as (values
  (1, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', E'  v_cost    numeric := 0;   -- 0406: what the kept parcels cost her here (the buy quotes'' totals)\n'),
  (2, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', E'  select * into k_to   from world.quote_terms(p_to, null, null);\n'),
  (3, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', E'      continue when v_q < 1;\n      select * into q_buy from world.quote_priced(p_from, v_good, v_q, ''buy'', null, null,\n'),
  (4, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', E'      v_cost   := v_cost + q_buy.total;     -- 0406\n'),
  (5, 'public.port_call(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)', E'  if v_fee > 0 then\n    select pl.ducats into v_purse from public.players pl where pl.id = p_player for update;\n'),
  (6, 'cmd.standing_route_close_lap(uuid,timestamp with time zone)', E'         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in - v_taxes - v_insure,\n')
), body as (
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
    from (values ('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'),
                 ('public.port_call(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)'),
                 ('cmd.standing_route_close_lap(uuid,timestamp with time zone)')) f(fn)
), lap as (
  select nf.player_id, l.closed_at, l.net + coalesce((to_jsonb(l)->>'fees')::bigint, 0) as gross, l.net, l.sold, l.bought
    from public.npc_fleets nf join public.standing_route_laps l on l.route_id = nf.route_id
   where l.closed_at > now() - interval '360 minutes'
), fee as (
  select g.player_id, g.created_at, -g.ducats_delta as fee
    from public.ledger g
   where g.kind = 'PORT_FEE' and g.created_at > now() - interval '360 minutes' and g.player_id in (select nh.player_id from public.npc_houses nh)
), house as (
  select nh.player_id,
         (select count(*) from lap where lap.player_id = nh.player_id) as laps6,
         (select coalesce(sum(lap.gross), 0) from lap where lap.player_id = nh.player_id)
           - (select coalesce(sum(fee.fee), 0) from fee where fee.player_id = nh.player_id) as res6,
         (select count(*) from lap where lap.player_id = nh.player_id and lap.closed_at > now() - interval '60 minutes') as laps1,
         (select coalesce(sum(lap.gross), 0) from lap where lap.player_id = nh.player_id and lap.closed_at > now() - interval '60 minutes')
           - (select coalesce(sum(fee.fee), 0) from fee where fee.player_id = nh.player_id and fee.created_at > now() - interval '60 minutes') as res1
    from public.npc_houses nh
), ord as (
  select o.verb, o.status, o.error_code, (o.args ? 'limit') as has_limit, (o.result->>'profit')::numeric as profit
    from public.orders o join public.standing_route_laps l on l.id = o.route_lap_id join public.npc_fleets nf on nf.route_id = l.route_id
   where l.closed_at > now() - interval '60 minutes' and o.verb = 'SELL'
), tb as (
  select t.port_id, public.treasury_balance(t.port_id) as bal from public.port_treasury t
), ln as (
  select l.qty * l.price_limit as cost, tb.bal
    from public.standing_route_lines l
    join public.npc_fleets nf on nf.route_id = l.route_id
    join public.standing_routes sr on sr.id = l.route_id and coalesce(sr.paused_reason, '') not in ('laid_up', 'error')
    join lateral (select count(*) as n from public.standing_route_stops s where s.route_id = l.route_id) c on true
    join public.standing_route_stops s2 on s2.route_id = l.route_id and s2.ord = (l.stop_ord + 1) % c.n
    join tb on tb.port_id = s2.port_id
   where l.kind = 'BUY'
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'cut', jsonb_build_object(
           'planner_reads_the_purse', (select bool_or(b.fn like 'public.npc_leg_lines%' and position('v_room' in b.def) > 0) from body b),
           'port_call_writes_the_book', (select bool_or(b.fn like 'public.port_call%' and position('set fees = x.fees + v_fee' in b.def) > 0) from body b),
           'book_takes_the_fees', (select bool_or(b.fn like 'cmd.standing_route_close_lap%' and position('- l.fees' in b.def) > 0) from body b),
           'fees_column', exists (select 1 from information_schema.columns k where k.table_schema = 'public' and k.table_name = 'standing_route_laps' and k.column_name = 'fees'),
           'list', to_regclass('public.lap_costs') is not null),
  'hunks', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.old, ''))) / length(hk.old)) from hk join body b on b.fn = hk.fn),
  'volatility', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile)
                   from pg_proc p where p.oid in ('public.treasury_balance(uuid)'::regprocedure, 'public.cargo_haul(uuid,uuid)'::regprocedure,
                                                  'public.city_treasury_on()'::regprocedure, 'public.economy_closed()'::regprocedure,
                                                  'pg_catalog.pg_get_functiondef(oid)'::regprocedure)),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('economy_closed', 'city_treasury_enabled', 'npc_min_return_pct', 'npc_sell_margin', 'drift_sigma', 'drift_slot_seconds', 'port_fee_base')),
  'health', jsonb_build_object(
     'six_hours', (select jsonb_build_object(
                     'houses_trading', count(*) filter (where h.laps6 > 0),
                     'under_water', count(*) filter (where h.laps6 > 0 and h.res6 < 0),
                     'under_water_pct', round(100.0 * count(*) filter (where h.laps6 > 0 and h.res6 < 0) / nullif(count(*) filter (where h.laps6 > 0), 0), 1),
                     'bleed_k', round(coalesce(sum(h.res6) filter (where h.laps6 > 0 and h.res6 < 0), 0) / 1000.0),
                     'sum_k', round(coalesce(sum(h.res6) filter (where h.laps6 > 0), 0) / 1000.0),
                     'should_stay_under_pct', 12) from house h),
     'hour', (select jsonb_build_object(
                     'houses_trading', count(*) filter (where h.laps1 > 0),
                     'under_water', count(*) filter (where h.laps1 > 0 and h.res1 < 0),
                     'under_water_pct', round(100.0 * count(*) filter (where h.laps1 > 0 and h.res1 < 0) / nullif(count(*) filter (where h.laps1 > 0), 0), 1),
                     'bleed_k', round(coalesce(sum(h.res1) filter (where h.laps1 > 0 and h.res1 < 0), 0) / 1000.0),
                     'sum_k', round(coalesce(sum(h.res1) filter (where h.laps1 > 0), 0) / 1000.0)) from house h)),
  'laps_hour', (select jsonb_build_object('laps', count(*), 'losing', count(*) filter (where lap.net < 0),
                                          'traded_nothing', count(*) filter (where lap.sold = 0 and lap.bought = 0),
                                          'traded_nothing_pct', round(100.0 * count(*) filter (where lap.sold = 0 and lap.bought = 0) / nullif(count(*), 0), 1))
                  from lap where lap.closed_at > now() - interval '60 minutes'),
  'newest_laps', (select jsonb_build_object(
                    'below_cost_sales', count(*) filter (where o.status = 'done' and o.profit < 0),
                    'below_cost_loss_k', round(coalesce(sum(o.profit) filter (where o.status = 'done' and o.profit < 0), 0) / 1000.0),
                    'sales_at_a_gain', count(*) filter (where o.status = 'done' and o.profit >= 0),
                    'gain_k', round(coalesce(sum(o.profit) filter (where o.status = 'done' and o.profit >= 0), 0) / 1000.0),
                    'refused_price', count(*) filter (where o.error_code = 'E_PRICE_LIMIT'),
                    'refused_city_broke', count(*) filter (where o.error_code = 'E_CITY_BROKE')) from ord o),
  'purse', (select jsonb_build_object('buy_lines', count(*), 'cannot_pay', count(*) filter (where ln.bal < ln.cost),
                                      'cannot_pay_pct', round(100.0 * count(*) filter (where ln.bal < ln.cost) / nullif(count(*), 0), 1),
                                      'their_cost_m', round(coalesce(sum(ln.cost) filter (where ln.bal < ln.cost), 0) / 1000000.0, 1),
                                      'should_stay_under_pct', 10) from ln),
  'fleets', (select jsonb_build_object('fleets', count(*), 'laid_up', count(*) filter (where sr.paused_reason = 'laid_up'),
                                       'sailing', count(*) filter (where f.status = 'SAILING'))
               from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id join public.fleets f on f.id = nf.fleet_id)
) as r;
commit;
