-- ATTACKS, PROD CHECK (after-job), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/attacks/after-job.sql
-- Line 5 of the after-check of lighting attack_enabled (docs/COMBAT_LOG.md 3.6): NO FAILED RUN OF THE BATTLES JOB. PROD ONLY: it reads pg_cron's own tables (cron.job, cron.job_run_details),
-- which the local PGlite world does not have. The 30 minutes before now.
--   job_active   WANTED true: byeharu-voyage:battles is scheduled and active (0323: every minute, select public.tick_battles()).
--   runs         its runs in the window (about 30).       failed  WANTED 0: runs that did not succeed.       messages  what the failed ones said.
--   slowest_s    the longest run, in seconds: a run is one read of a partial index when no battle is due, and at most 50 battles otherwise. Above 5 s, read the battles (after-battles.sql).
--   last_run     when it last ran: more than 2 minutes ago means the job is not running.
begin transaction read only;
with w as (select now() - interval '30 minutes' as a, now() as b),
r as (
  select d.status, d.start_time, extract(epoch from d.end_time - d.start_time) as s, d.return_message
    from cron.job j join cron.job_run_details d on d.jobid = j.jobid, w
   where j.jobname = 'byeharu-voyage:battles' and d.start_time >= w.a and d.start_time < w.b)
select (select bool_or(j.active) from cron.job j where j.jobname = 'byeharu-voyage:battles') as job_active,
       (select j.schedule from cron.job j where j.jobname = 'byeharu-voyage:battles' limit 1) as schedule,
       (select count(*) from r) as runs,
       (select count(*) from r where r.status <> 'succeeded') as failed,
       (select coalesce(jsonb_agg(distinct r.return_message), '[]'::jsonb) from r where r.status <> 'succeeded') as messages,
       (select round(max(r.s)::numeric, 2) from r) as slowest_s,
       (select max(r.start_time) from r) as last_run,
       now() as read_at;
commit;
