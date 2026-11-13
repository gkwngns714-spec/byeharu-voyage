-- 0355 PROD CHECK (before-beats), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/captain-skills/before-beats.sql
-- The arrivals beat over the last 30 minutes, before the deploy. Wanted: n > 0, errors 0, avg_ms <= 3000, p95_ms < 5000 (docs/REPUTATION.md, R2 after-check).
-- Keep the row: after-beats.sql is read against it. Every arrival reads public.crew_terms (speed, storm, supplies), the body 0355 cuts.
begin transaction read only;
select count(*) as n,
       round(avg(ms)::numeric, 1) as avg_ms,
       round((percentile_cont(0.95) within group (order by ms))::numeric, 1) as p95_ms,
       count(*) filter (where error is not null) as errors,
       min(at) as first_beat,
       max(at) as last_beat
  from public.arrivals_beats
 where at >= now() - interval '30 minutes';
commit;
