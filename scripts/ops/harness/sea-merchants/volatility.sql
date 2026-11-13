-- 0397 PROD CHECK (volatility), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-merchants/volatility.sql
-- Run AFTER the deploy and before after.sql or after-lit.sql. Wanted: eight rows, every one provolatile 's' or 'i' (those two files call them).
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile
  from pg_proc p
 where p.oid in (to_regprocedure('public.sea_conditions_npc_on()'), to_regprocedure('public.npc_course_zones(jsonb)'), to_regprocedure('public.npc_sea_shut(numeric,uuid,jsonb)'),
                 to_regprocedure('public.npc_loop_sea_shut(uuid,jsonb)'), to_regprocedure('public.npc_feasible_legs(uuid,uuid,numeric,integer)'),
                 to_regprocedure('public.fleet_wave(uuid)'), to_regprocedure('public.course_zones(jsonb)'), to_regprocedure('public.sea_refusal(integer,numeric,text[])'))
 order by 1;
commit;
