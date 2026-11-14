-- 0407 PROD CHECK, AFTER the deploy, read-only, ONE statement (the same read as before.sql, kept under its own name so the two outputs sit side by side):
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/ask-backoff/after.sql      at +30 min, +2 h and +24 h
-- One row, one jsonb column `r`.
-- BEFORE, wanted: head 20260818000406; applied false; hunks: every count 1 (each old text once in the live body: prod's bodies are the pre-images);
--   volatility s or i; knobs.npc_ask_job_ms 20000 (if the owner has set another value 0407 leaves it: say so in the after read).
-- AFTER, wanted: head 20260818000407; applied true; knobs.npc_ask_job_ms 12000 and npc_ask_broke_under 100; line.by_refused filling over the first hour
--   (everyone starts at 0 = due every 10 minutes, and moves to 2, 3, 4+ as she is refused).
-- WHAT IT MEASURES (both sides; write the before read down):
--   job[]        the waiting-asks job by 5-minute block, last 30 minutes: runs, asked / waiting / resumed a minute, spent_ms a minute (mean, max), ms a plan,
--                ms an open, quay_ms a minute (after 0407: the wait for the quay, apart), due_left at the block's end, the line.
--   beat[]       the arrivals beat by 5-minute block, last 30 minutes: beats, mean ms, p95 ms, beats over 1 s, asked by the beat's own hand, errors.
--   lap_starts[] the lap-start job by 10-minute block, last 30 minutes: started, plan ms a start, late, the largest due_left.
--   line         the laid-up now: n; due by the rule in force (public.npc_waiting_queue, STABLE); overdue; broke (purse under 100); and, after 0407,
--                by_refused {0, 1, 2, 3, 4+}; first_timers = laid up with at most one refusal, and the oldest of THEIR last asks in minutes
--                (first_oldest_min: what 0405 won must hold: about 10 to 11).
-- READING after the deploy, at +30 min, +2 h, +24 h (the back-off needs an hour to settle: everyone starts unrefused):
--   job.asked a minute falls from 9-12 toward resumed + line / 50 (about 5 to 7); job.spent_ms mean falls from 20,000 toward 8,000 to 12,000 and is no
--   longer pinned at the budget; due_left 0 or a handful; first_oldest_min stays near 10; beat mean and p95 fall back toward the read before 0405
--   (mean 442-555 ms, p95 1.5-2.0 s); lap starts' late falls back toward 41-46 per ten minutes. If job.spent_ms stays pinned at 12,000 with due_left
--   growing, the budget is under the demand: the owner raises npc_ask_job_ms. If quay_ms is most of what open_ms was, the opens were waiting, not working.
begin transaction read only;
with hk(ord, fn, old) as (values
  (1, 'public.npc_waiting_queue(timestamp with time zone)', E'    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id\n'),
  (2, 'public.npc_waiting_queue(timestamp with time zone)', E'                      public.wc_int(''npc_replan_within_minutes'') as w_min) w\n'),
  (3, 'public.npc_waiting_queue(timestamp with time zone)', E'         a.asked + make_interval(mins => w.e_min),\n'),
  (4, 'public.npc_plan(timestamp with time zone,uuid)', E'      if not v_pays and v_choose and not v_off and coalesce(v_aboard, 0) <= 0 then\n        v_waiting := v_waiting + 1;\n'),
  (5, 'public.tick_waiting_asks(boolean,uuid)', E'  v_wait_ms numeric := 0;\nbegin\n'),
  (6, 'public.tick_waiting_asks(boolean,uuid)', E'    v_t := clock_timestamp();\n    begin\n      v_b := public.waiting_ask_open(v_f, v_stamp);\n'),
  (7, 'public.tick_waiting_asks(boolean,uuid)', E'''wait_ms'', round(v_wait_ms),\n')
), body as (
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
    from (values ('public.npc_waiting_queue(timestamp with time zone)'), ('public.npc_plan(timestamp with time zone,uuid)'), ('public.tick_waiting_asks(boolean,uuid)')) f(fn)
), laid as (
  select nf.fleet_id, pl.ducats, coalesce((to_jsonb(nf) ->> 'refused')::int, 0) as refused,
         extract(epoch from (now() - greatest(sr.updated_at, coalesce(nf.asked_at, '-infinity'::timestamptz)))) / 60.0 as mins
    from public.npc_fleets nf
    join public.standing_routes sr on sr.id = nf.route_id
    join public.players pl on pl.id = sr.player_id
   where sr.paused_reason = 'laid_up'
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', exists (select 1 from public.world_config where key = 'npc_ask_broke_under'),
  'hunks', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.old, ''))) / length(hk.old)) from hk join body b on b.fn = hk.fn),
  'bodies', (select jsonb_object_agg(b.fn, md5(b.def)) from body b),
  'volatility', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile)
                   from pg_proc p where p.oid in ('public.npc_waiting_queue(timestamp with time zone)'::regprocedure, 'pg_catalog.pg_get_functiondef(oid)'::regprocedure,
                                                  'pg_catalog.md5(text)'::regprocedure)),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('npc_ask_job_ms', 'npc_ask_broke_under', 'npc_replan_every_minutes', 'npc_replan_within_minutes', 'npc_ask_every_seconds',
                             'npc_replan_sweep_ms', 'npc_route_candidates', 'npc_route_review_laps')),
  'job', (select jsonb_agg(to_jsonb(x) order by x.block) from (
            select to_char(date_trunc('hour', w.at) + floor(extract(minute from w.at) / 5) * interval '5 minutes', 'HH24:MI') as block, count(*) as runs,
                   round(avg((w.receipt->>'asked')::numeric), 1) as asked, round(avg((w.receipt->>'waiting')::numeric), 1) as waiting,
                   round(avg((w.receipt->>'resumed')::numeric), 1) as resumed,
                   round(avg((w.receipt->>'spent_ms')::numeric)) as spent_ms, max((w.receipt->>'spent_ms')::numeric) as spent_ms_max,
                   round(sum((w.receipt->>'plan_ms')::numeric) / nullif(sum((w.receipt->>'asked')::numeric), 0)) as ms_a_plan,
                   round(sum((w.receipt->>'open_ms')::numeric) / nullif(sum((w.receipt->>'resumed')::numeric + (w.receipt->>'gone')::numeric), 0)) as ms_an_open,
                   round(avg((w.receipt->>'wait_ms')::numeric)) as wait_ms, round(avg((w.receipt->>'quay_ms')::numeric)) as quay_ms,
                   max((w.receipt->>'open_ms_max')::numeric) as open_ms_max, sum((w.receipt->>'failed')::int) as failed, sum((w.receipt->>'late')::int) as late,
                   (array_agg((w.receipt->>'due_left')::int order by w.at desc))[1] as due_left, (array_agg((w.receipt->>'line')::int order by w.at desc))[1] as line,
                   round(avg(w.ms) / 1000.0, 1) as run_s
              from public.waiting_ask_runs w where w.at >= now() - interval '30 minutes' group by 1) x),
  'beat', (select jsonb_agg(to_jsonb(x) order by x.block) from (
            select to_char(date_trunc('hour', b.at) + floor(extract(minute from b.at) / 5) * interval '5 minutes', 'HH24:MI') as block, count(*) as beats,
                   round(avg(b.ms)) as ms_mean, round(percentile_cont(0.95) within group (order by b.ms)::numeric) as ms_p95,
                   count(*) filter (where b.ms > 1000) as over_1s, coalesce(sum(b.asked), 0) as asked, count(*) filter (where b.error is not null) as errors
              from public.arrivals_beats b where b.at >= now() - interval '30 minutes' group by 1) x),
  'lap_starts', (select jsonb_agg(to_jsonb(x) order by x.block) from (
            select to_char(date_trunc('hour', l.at) + floor(extract(minute from l.at) / 10) * interval '10 minutes', 'HH24:MI') as block, count(*) as runs,
                   sum((l.receipt->>'started')::int) as started,
                   round(sum((l.receipt->>'plan_ms')::numeric) / nullif(sum((l.receipt->>'started')::numeric + (l.receipt->>'settled')::numeric), 0)) as plan_ms_a_start,
                   sum((l.receipt->>'late')::int) as late, max((l.receipt->>'due_left')::int) as due_left_max
              from public.lap_start_runs l where l.at >= now() - interval '30 minutes' group by 1) x),
  'line', (select jsonb_build_object(
             'n', count(*),
             'due_by_the_rule', (select count(*) from public.npc_waiting_queue(now()) q where q.due_at <= now()),
             'overdue', count(*) filter (where l.mins >= 60), 'broke', count(*) filter (where l.ducats < 100),
             'by_refused', jsonb_build_object('0', count(*) filter (where l.refused = 0), '1', count(*) filter (where l.refused = 1), '2', count(*) filter (where l.refused = 2),
                                              '3', count(*) filter (where l.refused = 3), '4+', count(*) filter (where l.refused >= 4)),
             'first_timers', count(*) filter (where l.refused <= 1 and l.ducats >= 100),
             'first_oldest_min', round(max(l.mins) filter (where l.refused <= 1 and l.ducats >= 100)::numeric, 1),
             'mins_p50', round(percentile_cont(0.50) within group (order by l.mins)::numeric, 1), 'mins_max', round(max(l.mins)::numeric, 1))
             from laid l),
  'merchants', (select jsonb_build_object('at', s.at, 'laid_up', s.laid_up, 'sailing', s.sailing, 'docked', s.docked, 'fleets', s.fleets)
                  from public.stats_merchants s order by s.slot desc limit 1)
) as r;
commit;
