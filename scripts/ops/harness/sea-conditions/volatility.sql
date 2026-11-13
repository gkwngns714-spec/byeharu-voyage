-- PROD CHECK (volatility), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-conditions/volatility.sql
-- Wanted: nine rows, every one provolatile 's' or 'i', before impact.sql calls them. A missing row is a function prod does not hold: stop.
begin transaction read only;
select p.oid::regprocedure::text as fn, p.provolatile
  from pg_proc p
 where p.oid in (to_regprocedure('public.title_level(uuid)'), to_regprocedure('public.player_progress(uuid)'), to_regprocedure('public.fleet_wave(uuid)'),
                 to_regprocedure('public.course_zones(jsonb)'), to_regprocedure('public.sea_refusal(integer,numeric,text[])'),
                 to_regprocedure('public.wc_num(text)'), to_regprocedure('public.wc_int(text)'),
                 to_regprocedure('voyage.gc_distance_nm(double precision,double precision,double precision,double precision)'),
                 to_regprocedure('world.ship_stat(uuid,text)'))
 order by 1;
commit;
