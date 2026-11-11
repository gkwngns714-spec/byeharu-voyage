-- 0350 PROD CHECK (either side), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/best-sales/volatility-0350.sql
-- Every function the checks above call, and the two re-cut bodies with the two new pieces: volatility (wanted: s or i on every row), definer, settings and who may run it.
-- Before the deploy world.good_mids and world.board_legs are absent (no row); after it, both read volatile s, and world.good_mids has no definer and no setting (plain SQL, on purpose).
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile as volatile, p.prosecdef as definer, coalesce(p.proconfig::text, '') as settings,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_may, has_function_privilege('anon', p.oid, 'execute') as anon_may
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where (n.nspname, p.proname) in (('world', 'mid_price'), ('world', 'mid_from_terms'), ('world', 'mid_terms'), ('public', 'wc_num'), ('world', 'good_mids'),
                                  ('world', 'board_legs'), ('world', 'board_sell'), ('world', 'best_sales'), ('world', 'good_board'))
 order by 1;
commit;
