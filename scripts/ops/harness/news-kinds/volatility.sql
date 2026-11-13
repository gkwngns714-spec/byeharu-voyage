-- 0362 PROD CHECK (first; before and after), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/news-kinds/volatility.sql
-- Wanted, before and after alike: 5 rows, every one volatile 'v', definer true, settings {search_path=public, pg_temp}, and no client may execute any (client false).
-- After the deploy the same five rows: a re-cut moves none of them. Only the catalog is read.
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile as volatile, p.prosecdef as definer, p.proconfig as settings,
       has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') as client
  from pg_proc p
 where p.oid = any (array(select to_regprocedure(f) from unnest(array['cmd.do_sell(uuid,jsonb)', 'cmd.do_buy(uuid,jsonb)', 'public.tick_price_snapshot(timestamp with time zone)', 'voyage.settle(uuid,timestamp with time zone)', 'public.capital_gift_one(timestamp with time zone,uuid)']) f))
 order by 1;
commit;
