-- 0367 PROD CHECK (volatility), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/armada/volatility.sql
-- Run it after the deploy and BEFORE after.sql: every function after.sql calls must read 's' (stable) or 'i' (immutable). A 'v' here means after.sql is not to be run.
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile
  from pg_proc p
 where p.oid in ('world.armadas()'::regprocedure, 'voyage.fleet_speed_at(uuid,numeric)'::regprocedure, 'voyage.fleet_speed_alone_at(uuid,numeric)'::regprocedure,
                 'public.client_rpc_entry_points()'::regprocedure)
 order by 1;
commit;
