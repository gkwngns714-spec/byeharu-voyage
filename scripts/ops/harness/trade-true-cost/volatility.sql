-- 0361 PROD CHECK (either side), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/trade-true-cost/volatility.sql
-- The four re-cut bodies, the read that leans on them, the three helpers (after the deploy) and every authority they compose: volatility (wanted: s or i on
-- every row), definer, settings and who may run it. Wanted: world.good_board, world.best_sales and world.trip_cost s, open to authenticated and not to anon;
-- world.board_legs, world.board_sell and (after) world.trip_leg, world.trip_hulls, world.trip_stop_seconds s and server only; the same rows before and after
-- but for the three helpers.
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile as volatile, p.prosecdef as definer, coalesce(p.proconfig::text, '') as settings,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_may, has_function_privilege('anon', p.oid, 'execute') as anon_may
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where (n.nspname, p.proname) in (('world', 'good_board'), ('world', 'best_sales'), ('world', 'trip_cost'), ('world', 'board_legs'), ('world', 'board_sell'), ('world', 'board_origin'),
                                  ('world', 'trip_leg'), ('world', 'trip_hulls'), ('world', 'trip_stop_seconds'), ('public', 'stores_topup'), ('public', 'stores_cost'),
                                  ('public', 'npc_leg_days'), ('public', 'port_fee'), ('public', 'fleet_stock_at_cost'), ('public', 'fleet_wage'), ('public', 'economy_closed'),
                                  ('public', 'supply_needs'), ('voyage', 'total_days'), ('public', 'wc_num'))
 order by 1;
commit;
