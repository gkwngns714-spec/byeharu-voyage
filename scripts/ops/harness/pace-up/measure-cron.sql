-- PACE-UP (0421) MEASURE 1 of 3, read-only, ONE statement: every pg_cron job, its cadence, and its runs in the last 2 hours.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/pace-up/measure-cron.sql
-- Reads cron.job (23 rows) and cron.job_run_details (purged daily by byeharu-voyage:cron-purge). No game table. No function but
-- now(), round(), extract(), percentile_cont() and jsonb builders (stable or immutable).
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'jobs', (select jsonb_agg(jsonb_build_object(
             'job', j.jobname, 'schedule', j.schedule, 'active', j.active, 'command', left(j.command, 80),
             'runs_2h', coalesce(d.runs, 0), 'failed_2h', coalesce(d.failed, 0),
             'mean_s', d.mean_s, 'p95_s', d.p95_s, 'max_s', d.max_s, 'last_error', d.last_error) order by j.jobname)
             from cron.job j
             left join (
               select r.jobid, count(*) as runs,
                      count(*) filter (where r.status <> 'succeeded') as failed,
                      round(avg(extract(epoch from r.end_time - r.start_time))::numeric, 3) as mean_s,
                      round((percentile_cont(0.95) within group (order by extract(epoch from r.end_time - r.start_time)))::numeric, 3) as p95_s,
                      round(max(extract(epoch from r.end_time - r.start_time))::numeric, 3) as max_s,
                      left(max(r.return_message) filter (where r.status <> 'succeeded'), 120) as last_error
                 from cron.job_run_details r
                where r.start_time > now() - interval '2 hours'
                group by r.jobid) d on d.jobid = j.jobid)
) as r;
commit;
