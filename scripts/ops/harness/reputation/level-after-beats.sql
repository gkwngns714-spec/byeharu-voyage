-- 0356 PROD CHECK (after-beats), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/reputation/level-after-beats.sql
-- The arrivals beat over the last 30 minutes, read 30 minutes after the deploy. Wanted: n > 0, errors 0, avg_ms <= 3000, p95_ms < 5000, and no worse than
-- level-before-beats.sql's row beyond its own spread. A human's arrival now reads public.player_progress once (about 22 ms warm, 690 ms cold, measured
-- 2026-11-07); a merchant's arrival runs no new statement. A max_ms far above the row before is one cold human arrival: read it again 30 minutes later.
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
