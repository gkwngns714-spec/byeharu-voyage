-- 0351 PROD CHECK (either side), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/best-sales/volatility-0351.sql
-- The two re-cut bodies, every function they call that the checks lean on, every function that asks the cap authority (world.buy_capacity, cmd.resolve_qty, world.trade_routes,
-- world.best_sales) and every function the checks above call: volatility (wanted: s or i on every row), definer, settings and who may run it.
-- Wanted: world.best_sales, world.buy_capacity and world.trade_routes s; open to authenticated as they are today and not to anon; public.fleet_buy_capacity, cmd.resolve_qty and
-- public.credit_on s and server only; the same rows before and after.
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile as volatile, p.prosecdef as definer, coalesce(p.proconfig::text, '') as settings,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_may, has_function_privilege('anon', p.oid, 'execute') as anon_may
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where (n.nspname, p.proname) in (('world', 'best_sales'), ('public', 'fleet_buy_capacity'), ('world', 'buy_capacity'), ('public', 'credit_on'), ('public', 'wc_num'), ('cmd', 'resolve_qty'), ('world', 'trade_routes'),
                                  ('world', 'quote'), ('world', 'board_sell'), ('world', 'good_board'), ('world', 'daily_cap_remaining'))
 order by 1;
commit;
