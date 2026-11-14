-- 0405 PROD CHECK, AFTER the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/layup-line/after.sql
-- Run it at +5, +15 and +30 minutes (the 30-minute after-check: this changes live play, merchants leave the line sooner). One row, one jsonb column `r`.
-- WANTED AT ONCE: head 20260818000405; made: all true; server_only true; knob 20000; job: scheduled 1, active true (bv-deploy winds the clock);
--   bodies: the same six md5 as before.sql read (0405 re-cuts no live body).
-- WANTED FROM +15 MINUTES: line.mins_p90 under 12 and line.mins_max under 15 (was p50 21.9, p90 43.9, max 52.4), line.overdue 0, line.due small (those due
--   in the last minute); asks.runs = the minutes passed, asks.asked several hundred an hour while the line is long, asks.failed 0 and asks.notes empty,
--   asks.spent_ms_max at or under about 20,500 (the budget plus one ask), asks.due_left_last 0 or a handful, asks.ms_an_ask near 300 to 600.
--   THE LAW, ARRIVALS FIRST: beats.ms_mean, ms_p95 and over_1s NOT ABOVE before.sql's (measured 468 ms mean), beats.errors not rising; beats.asked FALLS
--   toward 0 (the beat's hand finds nobody due). lap_starts.lag_p50_ms and late not above before.sql's.
--   line.n itself should fall over the half hour: a merchant now waits ten minutes, not n / 4.
-- IF NOT: beats slower or errors, or asks.failed rising: the owner sets npc_ask_job_ms 0 (the job then asks nobody; the beat's hand and the reconcile
--   remain as before) and reads asks.notes; the forward rollback draft is rollback-0405.sql.
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'made', jsonb_build_object('job_proc', to_regprocedure('public.tick_waiting_asks(boolean,uuid)') is not null,
                             'plan', to_regprocedure('public.waiting_ask_plan(uuid)') is not null,
                             'open', to_regprocedure('public.waiting_ask_open(uuid,timestamp with time zone)') is not null,
                             'book', to_regclass('public.waiting_ask_runs') is not null),
  'server_only', not has_function_privilege('authenticated', 'public.waiting_ask_plan(uuid)', 'execute')
                 and not has_function_privilege('anon', 'public.waiting_ask_plan(uuid)', 'execute')
                 and not has_table_privilege('authenticated', 'public.waiting_ask_runs', 'select'),
  'knob', (select w.value from public.world_config w where w.key = 'npc_ask_job_ms'),
  'job', (select jsonb_build_object('scheduled', count(*), 'active', bool_and(j.active), 'schedule', min(j.schedule), 'jobs_in_all', (select count(*) from public.clock_jobs()))
            from public.clock_jobs() j where j.jobname = 'byeharu-voyage:waiting-asks'),
  'bodies', (select jsonb_object_agg(f.fn, md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')))
               from (values ('public.tick_arrivals(timestamp with time zone)'), ('public.tick_arrivals_each_second(integer)'),
                            ('public.npc_ask_waiting(timestamp with time zone,timestamp with time zone)'), ('public.npc_waiting_queue(timestamp with time zone)'),
                            ('public.tick_lap_starts(boolean)'), ('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)')) f(fn)),
  'line', (select jsonb_build_object('n', count(*), 'due', count(*) filter (where q.mins >= 10), 'overdue', count(*) filter (where q.mins >= 60),
                                     'mins_p50', round(percentile_cont(0.50) within group (order by q.mins)::numeric, 1),
                                     'mins_p90', round(percentile_cont(0.90) within group (order by q.mins)::numeric, 1),
                                     'mins_max', round(max(q.mins)::numeric, 1))
             from (select extract(epoch from (now() - greatest(sr.updated_at, coalesce(nf.asked_at, '-infinity'::timestamptz)))) / 60.0 as mins
                     from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
                    where sr.paused_reason = 'laid_up') q),
  'asks', (select jsonb_build_object('runs', count(*), 'asked', sum((w.receipt->>'asked')::int), 'waiting', sum((w.receipt->>'waiting')::int),
                                     'resumed', sum((w.receipt->>'resumed')::int), 'gone', sum((w.receipt->>'gone')::int),
                                     'busy', sum((w.receipt->>'busy')::int), 'failed', sum((w.receipt->>'failed')::int), 'late', sum((w.receipt->>'late')::int),
                                     'spent_ms_mean', round(avg((w.receipt->>'spent_ms')::numeric)), 'spent_ms_max', max((w.receipt->>'spent_ms')::numeric),
                                     'ms_an_ask', round(sum((w.receipt->>'plan_ms')::numeric + (w.receipt->>'open_ms')::numeric) / nullif(sum((w.receipt->>'asked')::int), 0)),
                                     'plan_ms_max', max((w.receipt->>'plan_ms_max')::numeric), 'open_ms_max', max((w.receipt->>'open_ms_max')::numeric),
                                     'due_left_last', (array_agg((w.receipt->>'due_left')::int order by w.at desc))[1],
                                     'line_last', (array_agg((w.receipt->>'line')::int order by w.at desc))[1],
                                     'oldest_min_max', max((w.receipt->>'oldest_min')::numeric),
                                     'notes', coalesce(jsonb_agg(distinct w.receipt->'note') filter (where w.receipt->>'note' is not null), '[]'::jsonb))
             from public.waiting_ask_runs w where w.at >= now() - interval '30 minutes'),
  'beats', (select jsonb_build_object('beats', count(*), 'beats_that_asked', count(*) filter (where b.asked > 0), 'asked', coalesce(sum(b.asked), 0),
                                      'ms_mean', round(avg(b.ms)), 'ms_p95', round(percentile_cont(0.95) within group (order by b.ms)::numeric),
                                      'ms_max', round(max(b.ms)), 'over_1s', count(*) filter (where b.ms > 1000), 'errors', count(*) filter (where b.error is not null))
              from public.arrivals_beats b where b.at >= now() - interval '30 minutes'),
  'lap_starts', (select jsonb_build_object('runs', count(*), 'started', sum((l.receipt->>'started')::int), 'late', sum((l.receipt->>'late')::int),
                                           'due_left_max', max((l.receipt->>'due_left')::int),
                                           'lag_p50_ms', round(percentile_cont(0.50) within group (order by (l.receipt->'lag_ms'->>'p50')::numeric)::numeric))
                   from public.lap_start_runs l where l.at >= now() - interval '30 minutes'),
  'merchants', (select jsonb_build_object('at', s.at, 'laid_up', s.laid_up, 'sailing', s.sailing, 'docked', s.docked, 'fleets', s.fleets)
                  from public.stats_merchants s order by s.slot desc limit 1)
) as r;
commit;
