-- 0351 PROD CHECK (either side), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/best-sales/volatility-0351.sql
-- The re-cut body, every function it newly calls and every function the checks above call: volatility (wanted: s or i on every row), definer, settings and who may run it.
-- Wanted: world.best_sales s, open to authenticated and not to anon, before and after; public.fleet_buy_capacity and public.credit_on s and server only.
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile as volatile, p.prosecdef as definer, coalesce(p.proconfig::text, '') as settings,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_may, has_function_privilege('anon', p.oid, 'execute') as anon_may
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where (n.nspname, p.proname) in (('world', 'best_sales'), ('public', 'fleet_buy_capacity'), ('world', 'buy_capacity'), ('public', 'credit_on'), ('public', 'wc_num'),
                                  ('world', 'quote'), ('world', 'board_sell'), ('world', 'good_board'), ('world', 'daily_cap_remaining'))
 order by 1;
commit;
