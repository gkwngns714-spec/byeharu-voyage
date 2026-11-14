-- PACE-UP (0421) MEASURE 2 of 3, read-only, ONE statement: the jobs' own receipt rings (each bounded: a slot a minute of the day, a second
-- of the hour, or a row a run), summed over their last 2 hours (the beat: 30 minutes), plus each ring's newest receipt as it stands.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/pace-up/measure-rings.sql
-- No game table. Functions: now(), round(), avg/max/count, percentile_cont, jsonb builders (stable or immutable).
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'beat_30m', (select jsonb_build_object('beats', count(*), 'mean_ms', round(avg(ms)), 'p95_ms', round((percentile_cont(0.95) within group (order by ms))::numeric),
                                         'max_ms', round(max(ms)), 'fleets_per_min', round(sum(fleets)::numeric / 30, 1), 'days_per_min', round(sum(days)::numeric / 30, 1),
                                         'asked_per_min', round(sum(asked)::numeric / 30, 2), 'errors', count(*) filter (where error is not null))
                 from public.arrivals_beats where at > now() - interval '30 minutes'),
  'compact_2h', (select jsonb_build_object('runs', count(*), 'mean_ms', round(avg(ms)), 'max_ms', round(max(ms)),
                                           'newest', (select c.receipt from public.compact_runs c order by c.at desc limit 1))
                   from public.compact_runs where at > now() - interval '2 hours'),
  'waiting_asks_2h', (select jsonb_build_object('runs', count(*), 'mean_ms', round(avg(ms)), 'max_ms', round(max(ms)),
                                                'newest', (select w.receipt from public.waiting_ask_runs w order by w.at desc limit 1))
                        from public.waiting_ask_runs where at > now() - interval '2 hours'),
  'lap_starts_2h', (select jsonb_build_object('runs', count(*), 'mean_ms', round(avg(ms)), 'max_ms', round(max(ms)),
                                              'newest', (select l.receipt from public.lap_start_runs l order by l.at desc limit 1))
                      from public.lap_start_runs where at > now() - interval '2 hours'),
  'contract_wind_2h', (select jsonb_build_object('runs', count(*), 'mean_ms', round(avg(ms)), 'max_ms', round(max(ms)),
                                                 'newest', (select k.receipt from public.contract_wind_runs k order by k.at desc limit 1))
                         from public.contract_wind_runs where at > now() - interval '2 hours'),
  'stats_last4', (select jsonb_agg(jsonb_build_object('at', s.at, 'ms', round(s.ms), 'receipt', s.receipt) order by s.at desc)
                    from (select * from public.stats_runs order by at desc limit 4) s),
  'history_last4', (select jsonb_agg(jsonb_build_object('at', h.at, 'ms', round(h.ms), 'receipt', h.receipt) order by h.at desc)
                      from (select * from public.history_runs order by at desc limit 4) h),
  'reconcile_last2', (select jsonb_agg(jsonb_build_object('at', r.at, 'ms', r.ms) order by r.at desc)
                        from (select at, ms from public.reconcile_runs order by at desc limit 2) r)
) as r;
commit;
