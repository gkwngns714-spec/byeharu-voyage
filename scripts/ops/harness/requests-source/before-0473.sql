-- REQUESTS SAY WHERE TO BUY (0473), BEFORE. A PROD CHECK: read-only, ONE statement, small. The gate's beat is read first (5 minutes of
-- public.arrivals_beats); stop if beat_mean_ms is over 2,000.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/requests-source/before-0473.sql
-- Reads: world_config (the clock and hold knobs), ship_classes (the Barca's speed), the open hold-sized jobs (about 500 rows of a table of about
-- 2,000), each one's good's sellers (port_specialties by good) and the poster's row of sea_reaches (one jsonb lookup a seller). No function is
-- called but stable or immutable ones (now, public.clock_start is not called: the deadline is read from expires_day and game_day_seconds).
-- It answers: how far the nearest harbour that sells a hold job's good lies from the poster, in sailing minutes for a Barca, against the time left;
-- and how many jobs could not be done there and back in time.
begin transaction read only;
with k as (
  select (select (value #>> '{}')::numeric from public.world_config where key = 'time_compression') as tc,
         (select (value #>> '{}')::numeric from public.world_config where key = 'game_day_seconds') as gds,
         (select sc.speed_kn from public.ship_classes sc where sc.code = 'barca') as kn
), j as (
  select t.id, pp.code as port, g.code as good, t.expires_day,
         (select min((r.reaches ->> sp.code)::numeric)
            from public.port_specialties s join public.ports sp on sp.id = s.port_id and sp.kind = 'HARBOUR'
           where s.good_id = t.good_id and s.port_id <> t.port_id) as nm
    from public.trade_contracts t
    join public.ports pp on pp.id = t.port_id
    join public.goods g on g.id = t.good_id
    left join public.sea_reaches r on r.port_id = t.port_id
   where t.status = 'open' and t.size = 'hold'
), s as (
  select j.*, round(j.nm / k.kn * 3600 / k.tc) as sail_s from j, k
)
select jsonb_build_object(
  'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('time_compression', 'game_day_seconds', 'speed_scale', 'hold_requests_enabled', 'houses_board_enabled')
                or w.key like 'hold_request%'),
  'barca_kn', (select kn from k),
  'open_hold', (select count(*) from s),
  'no_seller', (select count(*) from s where s.nm is null),
  'sail_minutes', (select jsonb_build_object('p10', round((percentile_cont(0.1) within group (order by s.sail_s) / 60)::numeric, 1),
                                             'p50', round((percentile_cont(0.5) within group (order by s.sail_s) / 60)::numeric, 1),
                                             'p90', round((percentile_cont(0.9) within group (order by s.sail_s) / 60)::numeric, 1),
                                             'max', round(max(s.sail_s) / 60, 1)) from s),
  -- a job whose nearest seller is more than a quarter of its stand away one way (there and back in under half of it is 0473's rule)
  'far', (select count(*) from s, k where 2 * s.sail_s > 0.5 * ((s.expires_day - (select max(t2.posted_day) from public.trade_contracts t2 where t2.size = 'hold')) * k.gds)),
  'sample', (select jsonb_agg(x) from (select s.port, s.good, round(s.nm) as nm, round(s.sail_s / 60, 1) as sail_min from s order by s.port, s.good limit 12) x),
  'head', (select max(version) from supabase_migrations.schema_migrations));
rollback;
