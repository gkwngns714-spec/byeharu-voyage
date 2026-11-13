-- 0398 PROD CHECK (volatility), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-light/volatility.sql
-- Run AFTER 0398 is deployed and before before.sql, after.sql or after-check.sql. Wanted: public.sea_conditions_ready() 's' and every other row 's' or 'i';
-- public.sea_conditions_light() 'v' (it is THE STEP: never called by a check, only by the lead to light).
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile
  from pg_proc p
 where p.oid in (to_regprocedure('public.sea_conditions_ready()'), to_regprocedure('public.sea_conditions_light()'), to_regprocedure('public.sea_conditions_on()'),
                 to_regprocedure('public.sea_refusal(integer,numeric,text[])'), to_regprocedure('public.harbour_zone(uuid)'), to_regprocedure('public.course_zones(jsonb)'),
                 to_regprocedure('public.title_level(uuid)'), to_regprocedure('public.fleet_wave(uuid)'), to_regprocedure('public.fleet_room_on()'))
 order by 1;
commit;
