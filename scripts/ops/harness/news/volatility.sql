-- 0347 PROD CHECK (volatility), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/news/volatility.sql
-- Wanted: both 's'. These are the two live bodies 0347 re-cuts (its self-assert calls world.stats_now and client_rpc_entry_points; both must stay STABLE).
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile, p.prosecdef
  from pg_proc p
 where p.oid in (to_regprocedure('world.stats_now()'), to_regprocedure('public.client_rpc_entry_points()'))
 order by 1;
commit;
