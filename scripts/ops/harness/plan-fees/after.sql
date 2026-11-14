-- 0406 PROD CHECK, AFTER the deploy, read-only, ONE statement (the same read as before.sql, kept as its own file so the two outputs sit side by side):
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/plan-fees/after.sql      at +1 h, +3 h and +24 h
-- One row, one jsonb column `r`.
-- BEFORE, wanted: head 20260818000404 or ...0405; cut.plan_has_fee and cut.leg_has_cost false; hunks: every count 1 (each of the eight hunks' old
--   text occurs once in the live body: prod's bodies are the pre-images); volatility: every value s or i; fee_knobs as the dev-log reads them
--   (port_fee_base 250, port_fee_pct 0.005) with economy_closed and city_treasury_enabled true.
-- AFTER, wanted: head 20260818000406; cut.plan_has_fee and cut.leg_has_cost true; cut.md5 npc_plan fe17cbde7ee7aadb84ebc5657bc8fef0 and npc_leg_lines
--   fbea55693fbf12054c8edd8fe29dcfee (the cached chain's bodies with the eight hunks). `hunks` is a BEFORE gauge only: three of the old texts are the first
--   line of their new text and still count 1 after the cut.
-- WHAT IT MEASURES (both sides; a lap's book does NOT keep the dock fee, so the fee is read from the ledger): for every merchant house, the last 60
--   minutes: `net` = the sum of her closed laps' net (standing_route_laps, by its closed_at index), `fees` = the PORT_FEE rows of her ledger (by the
--   (player_id, created_at) index; a merchant's ledger is kept 6 hours, so an hour is whole). hour.houses_trading = houses that closed a lap;
--   hour.under_water = of those, the houses whose net less fees is under nothing; hour.under_water_pct; hour.laps and the laps of the houses under
--   water; hour.net_m and hour.fees_m (millions); hour.bleed_k = the sum of the negative (net - fees), thousands. fleets: laid up, sailing.
-- READING after the deploy (at +1 h, +3 h, +24 h): under_water_pct and bleed_k FALL (no loop is planned for less than its fees; what remains is the
--   market moving between plan and sale, and refused sales); fleets.laid_up may RISE by the merchants who were sailing at a loss; hour.laps may fall
--   by their laps. broke_houses (purse under 1,000 with a laid-up fleet) should stop growing over days.
begin transaction read only;
with hk(ord, fn, old) as (values
  (1, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', E'  v_wages   numeric;\n  v_kept    int := 0;\n'),
  (2, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', E'      v_budget := v_budget - q_buy.total;   -- 0129\n'),
  (3, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', E'  return jsonb_build_object(''lines'', v_lines, ''profit'', v_profit, ''wages'', v_wages,\n                            ''nm'', v_nm, ''any'', v_any);\n'),
  (4, 'public.npc_plan(timestamp with time zone,uuid)', E'  v_sea_d   numeric;     -- 0142: the loop''s days at sea\n'),
  (5, 'public.npc_plan(timestamp with time zone,uuid)', E'        v_wages  := 0;       -- 0142\n        v_rep    := false;   -- 0142\n'),
  (6, 'public.npc_plan(timestamp with time zone,uuid)', E'            v_leg  := public.npc_leg_lines(sr.id, v_from, v_to, v_hold, v_crew, v_speed);\n            v_memo := v_memo || jsonb_build_object(v_key, v_leg);\n'),
  (7, 'public.npc_plan(timestamp with time zone,uuid)', E'          v_wages  := v_wages + coalesce((v_leg->>''wages'')::numeric, 0);   -- 0142\n'),
  (8, 'public.npc_plan(timestamp with time zone,uuid)', E'        v_net   := v_profit - public.wages_from_profit(v_wages, v_profit)\n                   - public.stores_cost(sr.player_id, v_crew * public.wc_num(''water_per_crew_day'') * v_sea_d,\n                                        v_crew * public.wc_num(''food_per_crew_day'') * v_sea_d);\n')
), body as (
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
    from (values ('public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)'), ('public.npc_plan(timestamp with time zone,uuid)')) f(fn)
), house as (
  select nh.player_id,
         (select coalesce(sum(l.net), 0) from public.npc_fleets nf join public.standing_route_laps l on l.route_id = nf.route_id
           where nf.player_id = nh.player_id and l.closed_at > now() - interval '60 minutes') as net,
         (select count(*) from public.npc_fleets nf join public.standing_route_laps l on l.route_id = nf.route_id
           where nf.player_id = nh.player_id and l.closed_at > now() - interval '60 minutes') as laps,
         (select coalesce(-sum(g.ducats_delta), 0) from public.ledger g
           where g.player_id = nh.player_id and g.created_at > now() - interval '60 minutes' and g.kind = 'PORT_FEE') as fees
    from public.npc_houses nh
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'cut', (select jsonb_build_object('plan_has_fee', bool_or(b.fn like 'public.npc_plan%' and position('v_fees' in b.def) > 0),
                                    'leg_has_cost', bool_or(b.fn like 'public.npc_leg_lines%' and position('''cost'', v_cost' in b.def) > 0),
                                    'md5', jsonb_object_agg(b.fn, md5(b.def))) from body b),
  'hunks', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.old, ''))) / length(hk.old)) from hk join body b on b.fn = hk.fn),
  'volatility', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile)
                   from pg_proc p where p.oid in ('public.port_fee(uuid,uuid,numeric)'::regprocedure, 'pg_catalog.pg_get_functiondef(oid)'::regprocedure,
                                                  'pg_catalog.md5(text)'::regprocedure)),
  'fee_knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
                 where w.key in ('port_fee_base', 'port_fee_pct', 'country_tax_factor', 'economy_closed', 'city_treasury_enabled', 'npc_min_return_pct')),
  'hour', (select jsonb_build_object(
             'houses_trading', count(*) filter (where h.laps > 0),
             'under_water', count(*) filter (where h.laps > 0 and h.net - h.fees < 0),
             'under_water_pct', round(100.0 * count(*) filter (where h.laps > 0 and h.net - h.fees < 0) / nullif(count(*) filter (where h.laps > 0), 0), 1),
             'laps', sum(h.laps), 'laps_of_the_under_water', sum(h.laps) filter (where h.laps > 0 and h.net - h.fees < 0),
             'net_m', round(sum(h.net) / 1000000.0, 2), 'fees_m', round(sum(h.fees) / 1000000.0, 2),
             'bleed_k', round(coalesce(sum(h.net - h.fees) filter (where h.net - h.fees < 0), 0) / 1000.0, 1),
             'fees_with_no_lap_k', round(coalesce(sum(h.fees) filter (where h.laps = 0), 0) / 1000.0, 1))
             from house h),
  'fleets', (select jsonb_build_object('fleets', count(*), 'laid_up', count(*) filter (where sr.paused_reason = 'laid_up'),
                                       'sailing', count(*) filter (where f.status = 'SAILING'))
               from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id join public.fleets f on f.id = nf.fleet_id),
  'broke_houses', (select count(distinct pl.id) from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
                     join public.players pl on pl.id = nf.player_id
                    where sr.paused_reason = 'laid_up' and pl.ducats < 1000)
) as r;
commit;
