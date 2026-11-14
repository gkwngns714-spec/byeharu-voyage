-- 0421 PROD CHECK, AFTER the deploy, read-only, ONE statement. Run it at +30 minutes (two Stats counts at the new cadence), and again at +3 h.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/pace-up/after.sql
-- IT READS THE GATE (the same three figures and limits as scripts/ops/harness/db-health/gate.sql), then what 0421 moved.
-- WANTED: gate_ok true, and inside the room the owner asked for (2026-11-15: "there should be a room"): beat_mean_ms under 1,000 (half the
--   gate's 2,000; ~100 expected), io_waiting 0 to 2 (half of 5), database_mb under 1,200 (the budget's warning; ~890 now, up to ~930 after
--   three days); hot10_mb (the ten biggest tables) under 600 of the ~700 MB the cache holds. head 20260818000421; applied true;
--   stats_schedule "6,21,36,51 * * * *", stats_active as before; pirate_add_minutes 5; contract_wind_retry_minutes 30;
--   stats_runs: a count at :06, :21, :36, :51, each about 25 s (23 to 36 s with 0419), none failed (cron_2h); wind_2h mean under 4,000 ms;
--   cron_2h: every job's failures as in the before-check (arrivals and waiting-asks show a "job canceled" or two at their minute's edge: normal).
-- IF THE GATE IS RED, OR beat_mean_ms > 1,000, OR io_waiting > 2: step back the Stats count first (the dev-log's "first to step back").
-- No game table. Reads: arrivals_beats (3,600 rows), stats_runs (newest 6), contract_wind_runs (a slot a minute), cron.job, cron.job_run_details
-- (2 hours), the catalog and the statistics views. Functions: now(), pg_backend_pid(), percentile_cont, round, jsonb builders.
begin transaction read only;
with beat as (
  select count(*) as beats, round(avg(b.ms)) as mean_ms, round((percentile_cont(0.95) within group (order by b.ms))::numeric) as p95_ms
    from public.arrivals_beats b where b.at > now() - interval '5 minutes'
), size as (
  select (sum(c.relpages)::numeric * 8192 / 1048576)::int as mb from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')
), io as (
  select count(*) filter (where a.wait_event_type = 'IO' and a.state = 'active') as waiting from pg_stat_activity a where a.pid <> pg_backend_pid()
), hot as (
  select ((c.relpages + coalesce(t.relpages, 0)
           + coalesce((select sum(ic.relpages) from pg_index i join pg_class ic on ic.oid = i.indexrelid where i.indrelid = c.oid), 0))::numeric * 8192 / 1048576)::int as mb
    from pg_class c join pg_namespace n on n.oid = c.relnamespace left join pg_class t on t.oid = c.reltoastrelid
   where c.relkind = 'r' and n.nspname not in ('pg_catalog', 'information_schema')
   order by 1 desc limit 10
)
select jsonb_build_object(
  'at', now(),
  'gate_ok', (coalesce((select mean_ms from beat), 0) <= 2000 and (select mb from size) <= 1500 and (select waiting from io) <= 5),
  'in_the_room', (coalesce((select mean_ms from beat), 0) <= 1000 and (select mb from size) <= 1200 and (select waiting from io) <= 2),
  'beat_mean_ms', (select mean_ms from beat), 'beat_p95_ms', (select p95_ms from beat), 'beats_5m', (select beats from beat),
  'database_mb', (select mb from size), 'io_waiting', (select waiting from io), 'hot10_mb', (select sum(mb) from hot),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', exists (select 1 from public.world_config wc where wc.key = 'pirate_add_minutes' and wc.description like '0421:%'),
  'stats_schedule', (select j.schedule from cron.job j where j.jobname = 'byeharu-voyage:stats'),
  'stats_active', (select j.active from cron.job j where j.jobname = 'byeharu-voyage:stats'),
  'pirate_add_minutes', (select wc.value from public.world_config wc where wc.key = 'pirate_add_minutes'),
  'contract_wind_retry_minutes', (select wc.value from public.world_config wc where wc.key = 'contract_wind_retry_minutes'),
  'stats_runs', (select jsonb_agg(jsonb_build_object('at', s.at, 'ms', round(s.ms), 'wrote', s.receipt -> 'wrote') order by s.at desc)
                   from (select * from public.stats_runs order by at desc limit 6) s),
  'wind_2h', (select jsonb_build_object('runs', count(*), 'mean_ms', round(avg(k.ms)), 'max_ms', round(max(k.ms)),
                                        'tried', sum((k.receipt ->> 'tried')::int), 'posted', sum((k.receipt ->> 'posted')::int))
                from public.contract_wind_runs k where k.at > now() - interval '2 hours'),
  'cron_2h', (select jsonb_object_agg(j.jobname, jsonb_build_object('runs', d.runs, 'failed', d.failed, 'mean_s', d.mean_s, 'max_s', d.max_s))
                from cron.job j
                join (select r.jobid, count(*) as runs, count(*) filter (where r.status <> 'succeeded') as failed,
                             round(avg(extract(epoch from r.end_time - r.start_time))::numeric, 2) as mean_s,
                             round(max(extract(epoch from r.end_time - r.start_time))::numeric, 2) as max_s
                        from cron.job_run_details r where r.start_time > now() - interval '2 hours' group by r.jobid) d on d.jobid = j.jobid)
) as r;
commit;
