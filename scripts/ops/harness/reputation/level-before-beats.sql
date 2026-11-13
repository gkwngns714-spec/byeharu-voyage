-- 0356 PROD CHECK (before-beats), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/reputation/level-before-beats.sql
-- The arrivals beat over the last 30 minutes, before the deploy. Wanted: n > 0, errors 0, avg_ms <= 3000, p95_ms < 5000 (docs/REPUTATION.md, R4 hot path).
-- Keep the row: level-after-beats.sql is read against it.
begin transaction read only;
select count(*) as n,
       round(avg(ms)::numeric, 1) as avg_ms,
       round((percentile_cont(0.95) within group (order by ms))::numeric, 1) as p95_ms,
       round(max(ms)::numeric, 1) as max_ms,
       count(*) filter (where error is not null) as errors,
       min(at) as first_beat,
       max(at) as last_beat
  from public.arrivals_beats
 where at >= now() - interval '30 minutes';
commit;
