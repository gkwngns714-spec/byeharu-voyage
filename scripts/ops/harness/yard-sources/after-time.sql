-- 0358 PROD CHECK (after: the time of the read, by hand), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/yard-sources/after-time.sql
-- Run AFTER the deploy, three times. The read is STABLE; it is called 10 times for the Barca at Lisbon and the wall clock is read around the calls (clock_timestamp: no EXPLAIN ANALYZE).
-- Wanted: ms_a_call under 250 (the body of 0349 measured 65 to 73 ms on prod for one call; on the local world the old body takes 7.4 ms and the new 7.9 ms).
begin transaction read only;
with t0 as materialized (select clock_timestamp() as c),
     run as materialized (select count(world.yard_sources((select id from public.ports where code = 'LIS'), 'barca')) as calls from t0, generate_series(1, 10)),
     t1 as materialized (select clock_timestamp() as c, run.calls from run)
select t1.calls, round((extract(epoch from t1.c - t0.c) * 1000 / t1.calls)::numeric, 1) as ms_a_call from t1, t0;
commit;
