-- 0345 PROD CHECK (volatility), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/ship-stores/volatility.sql
-- Wanted: every row provolatile 's' or 'i' before impact.sql calls it.
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile
  from pg_proc p
 where p.oid in (to_regprocedure('voyage.fleet_speed(uuid)'), to_regprocedure('voyage.endurance_mult(uuid)'), to_regprocedure('voyage.stores_need_days(numeric,numeric)'),
                 to_regprocedure('public.supply_reach(uuid)'), to_regprocedure('public.wc_num(text)'))
 order by 1;
commit;
