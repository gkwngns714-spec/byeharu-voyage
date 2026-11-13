-- 0358 PROD CHECK (volatility), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/yard-sources/volatility.sql
-- Everything the re-cut read calls, and everything the checks in this folder call. Wanted: every provolatile is s or i (none v); world.yard_sources and world.price are definer-owned.
begin transaction read only;
select n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as fn, p.provolatile, p.prosecdef
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where (n.nspname = 'world' and p.proname in ('yard_sources', 'price', 'mid_price', 'price_terms', 'price_sides'))
    or (n.nspname = 'public' and p.proname in ('port_offered_goods', 'port_offers', 'culture_refuses', 'made_only_in', 'hull_unmade'))
 order by 1;
commit;
