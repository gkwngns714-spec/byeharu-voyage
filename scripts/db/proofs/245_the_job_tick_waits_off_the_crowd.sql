-- PROOF 245 - THE JOB TICK WAITS OFF THE CROWD, FOR pg_cron ALONE  (migration 0536; docs/dev-log/2026-11-25-best-sales-fast.md)
-- @pass TW_RULE   to second 25 for pg_cron's session; nothing past it, nothing for any other session, nothing for none
-- @pass TW_HAND   a run by hand (p_commit false) with a job due does not wait, whoever the session says it is; the job is started
-- @pass TW_SHAPE  in the procedure the wait is only when p_commit and a job is due, each second its own transaction, and what is due is read after it
do $p$
declare
  c_a  constant uuid := '00000000-0536-4000-8000-000000000245';
  v_a  uuid;
  v_f  uuid;
  v_t  timestamptz;
  v_j  record;
  v_d  text := replace(pg_get_functiondef('public.tick_fleet_jobs(boolean)'::regprocedure), E'\r', '');
begin
  if public.job_tick_wait_s(0, 'pg_cron') <> 25 or public.job_tick_wait_s(24.5, 'pg_cron') <> 0.5 or public.job_tick_wait_s(25, 'pg_cron') <> 0 or public.job_tick_wait_s(59, 'pg_cron') <> 0
     or public.job_tick_wait_s(0, 'PostgREST') <> 0 or public.job_tick_wait_s(0, '') <> 0 or public.job_tick_wait_s(0, null) <> 0 then
    raise exception 'TW_RULE: the wait is not to second 25 for pg_cron alone';
  end if;
  raise notice 'PASS: TW_RULE - 25 s at second 0, 0.5 at 24.5, none from 25 on and none for another session';

  v_a := public.new_house(c_a, 'Casa do Compasso 245', 'PRT');
  select f.id into v_f from public.fleets f where f.player_id = v_a;
  update public.players p set ducats = 5000000 where p.id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled');
  update public.fleet_jobs set next_at = now() + interval '1 day' where player_id <> v_a;
  perform cmd.assume_identity(c_a);
  perform cmd.set_fleet_job(v_f, 'best', '{}'::jsonb);
  if not exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_f) then
    raise exception 'TW_HAND: her job is not due: the scene proves nothing';
  end if;
  perform set_config('application_name', 'pg_cron', true);
  v_t := clock_timestamp();
  call public.tick_fleet_jobs(false);
  select * into v_j from public.fleet_jobs j where j.fleet_id = v_f;
  if clock_timestamp() - v_t > interval '8 seconds' or v_j.last is null then
    raise exception 'TW_HAND: a run by hand waited (% s) or did not ask her job: %', round(extract(epoch from clock_timestamp() - v_t), 1), to_jsonb(v_j);
  end if;
  raise notice 'PASS: TW_HAND - a run by hand asked her job in % s', round(extract(epoch from clock_timestamp() - v_t), 2);

  if v_d !~ 'if p_commit and exists \(select 1 from public\.fleet_jobs_due\(\)\) then\s+commit;\s+for k in 1 \.\. 30 loop'
     or v_d !~ 'perform pg_sleep\(least\(v_off, 1\)\);\s+commit;\s+end loop;'
     or position('job_tick_wait_s(extract' in v_d) > position('from (select x.* from public.fleet_jobs_due() x' in v_d) then
    raise exception 'TW_SHAPE: the procedure does not wait as written';
  end if;
  raise notice 'PASS: TW_SHAPE - only when p_commit and a job is due; a second a transaction; what is due is read after';
end
$p$;
