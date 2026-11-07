-- 0331 PROD CHECK AFTER DEPLOY, read-only, one statement: supabase db query --linked -f scripts/ops/harness/navy/after.sql
-- Every function read here is STABLE: public.navy_on, public.navy_size_for, public.realm_purse, public.cargo_figures. No game function is called; public.navy_station_plan is STABLE and may be asked for one country by hand.
-- Wanted: navy_on false; every count 0; job active; job_failed 0; sizes as in the dev-log's table, for today's purses.
begin transaction read only;
select public.navy_on() as navy_on,
       (select count(*) from public.navy_ships) as ships,
       (select count(*) from public.navy_realms) as realms,
       (select count(*) from public.navy_stations) as stations,
       (select count(*) from public.treasury_flows f where f.kind in ('BUILD_NAVY', 'NAVY_PAY')) as flows,
       (select bool_and(j.active) from cron.job j where j.jobname = 'byeharu-voyage:navy') as job_active,
       (select count(*) from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'byeharu-voyage:navy' and d.status = 'failed') as job_failed,
       public.cargo_figures() ? 'navy_ships' as figure_served,
       (select jsonb_object_agg(n.code, public.navy_size_for(public.realm_purse(g.nation_id))) from public.great_powers g join public.nations n on n.id = g.nation_id) as sizes,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
