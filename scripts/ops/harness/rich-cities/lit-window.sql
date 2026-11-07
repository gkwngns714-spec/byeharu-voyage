-- W7 LIT WINDOW, read-only: supabase db query --linked -f scripts/ops/harness/rich-cities/lit-window.sql
-- Run before lighting convoy_rich_enabled and 30 minutes after. No game function is called except the STABLE rich_cities_on.
-- Fail, set the switch back to false: failed > 0, or max_s >= 55 (the job must fit its minute), or health.sh alerts.
begin transaction read only;
select public.rich_cities_on() as rich_on,
       (select jsonb_object_agg(k, n) from (select c.stage k, count(*) || ' / ' || sum(c.ducats) n from public.convoy_cargo c
          where c.created_at > now() - interval '30 minutes' group by 1) t) as funds_30m,
       (select count(*) from public.cargo_ships) as ships,
       (select count(*) from public.cargo_ships c where c.based_at is not null) as based,
       (select count(*) from public.cargo_ships c where c.home_port_id <> public.realm_capital(c.nation_id)) as away_from_capital,
       (select jsonb_build_object('runs', count(*), 'failed', count(*) filter (where d.status <> 'succeeded'),
               'avg_s', round(avg(extract(epoch from d.end_time - d.start_time))::numeric, 2),
               'max_s', round(max(extract(epoch from d.end_time - d.start_time))::numeric, 2))
          from cron.job_run_details d join cron.job j on j.jobid = d.jobid
         where j.jobname = 'byeharu-voyage:cargo-ships' and d.start_time > now() - interval '30 minutes') as job;
commit;
