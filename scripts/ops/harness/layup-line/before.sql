-- 0405 PROD CHECK, BEFORE the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/layup-line/before.sql
-- One row, one jsonb column `r`. Wanted: head 20260818000404; applied_already false; volatility: every value s or i (the reads below call nothing else);
-- jobs: 22 of the game's, byeharu-voyage:waiting-asks not among them. WRITE DOWN `bodies` (the md5 of the six live bodies the line runs through: after.sql
-- must read the same six, since 0405 re-cuts none), `line` (the laid-up now: n, due = last asked 10 or more minutes ago, minutes since the last ask p50 /
-- p90 / max; measured 2026-11-14 00:08 UTC: n 199, due 162, p50 21.9, p90 43.9, max 52.4), `beats` (the arrivals beat's last hour: beats, asked, ms mean /
-- p95 / max, errors; measured: 3,287 beats, asked 239, mean 468 ms) and `lap_starts` (the lap-start job's last hour: started, the median of its minutes'
-- p50 lag in ms). They are what after.sql is read against.
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied_already', to_regprocedure('public.tick_waiting_asks(boolean,uuid)') is not null or to_regclass('public.waiting_ask_runs') is not null
                     or exists (select 1 from public.world_config where key = 'npc_ask_job_ms'),
  'volatility', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile)
                   from pg_proc p where p.oid in ('public.clock_jobs()'::regprocedure, 'pg_catalog.pg_get_functiondef(oid)'::regprocedure, 'pg_catalog.md5(text)'::regprocedure)),
  'jobs', (select jsonb_build_object('n', count(*), 'waiting_asks', count(*) filter (where j.jobname = 'byeharu-voyage:waiting-asks'),
                                     'inactive', count(*) filter (where not j.active)) from public.clock_jobs() j),
  'bodies', (select jsonb_object_agg(f.fn, md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')))
               from (values ('public.tick_arrivals(timestamp with time zone)'), ('public.tick_arrivals_each_second(integer)'),
                            ('public.npc_ask_waiting(timestamp with time zone,timestamp with time zone)'), ('public.npc_waiting_queue(timestamp with time zone)'),
                            ('public.tick_lap_starts(boolean)'), ('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)')) f(fn)),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('npc_ask_every_seconds', 'npc_replan_sweep_ms', 'npc_replan_per_sweep_max', 'npc_replan_every_minutes', 'npc_replan_within_minutes',
                             'arrivals_tick_budget_ms', 'npc_traders_enabled', 'npc_fleet_max')),
  'line', (select jsonb_build_object('n', count(*), 'due', count(*) filter (where q.mins >= 10), 'overdue', count(*) filter (where q.mins >= 60),
                                     'mins_p50', round(percentile_cont(0.50) within group (order by q.mins)::numeric, 1),
                                     'mins_p90', round(percentile_cont(0.90) within group (order by q.mins)::numeric, 1),
                                     'mins_max', round(max(q.mins)::numeric, 1))
             from (select extract(epoch from (now() - greatest(sr.updated_at, coalesce(nf.asked_at, '-infinity'::timestamptz)))) / 60.0 as mins
                     from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
                    where sr.paused_reason = 'laid_up') q),
  'beats', (select jsonb_build_object('beats', count(*), 'beats_that_asked', count(*) filter (where b.asked > 0), 'asked', coalesce(sum(b.asked), 0),
                                      'ms_mean', round(avg(b.ms)), 'ms_p95', round(percentile_cont(0.95) within group (order by b.ms)::numeric),
                                      'ms_max', round(max(b.ms)), 'over_1s', count(*) filter (where b.ms > 1000), 'errors', count(*) filter (where b.error is not null))
              from public.arrivals_beats b where b.at >= now() - interval '60 minutes'),
  'lap_starts', (select jsonb_build_object('runs', count(*), 'started', sum((l.receipt->>'started')::int), 'late', sum((l.receipt->>'late')::int),
                                           'due_left_max', max((l.receipt->>'due_left')::int),
                                           'lag_p50_ms', round(percentile_cont(0.50) within group (order by (l.receipt->'lag_ms'->>'p50')::numeric)::numeric))
                   from public.lap_start_runs l where l.at >= now() - interval '60 minutes')
) as r;
commit;
