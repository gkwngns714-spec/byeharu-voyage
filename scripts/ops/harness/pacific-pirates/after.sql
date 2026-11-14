-- after.sql: READ-ONLY, after 0414 (at once, then every hour of the first day). Wanted: head 20260818000414; five hubs; the roster 108 fleets; `built` rising toward 108;
-- `stuck` 0 from two hours after the deploy on (THE HEALTH FIGURE: a pirate fleet unable to sail for more than 3 hours); `pressure_over_cap` 0; the beat no slower than before.
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pacific-pirates/after.sql
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations), 'at', now(),
  'hubs', (select jsonb_object_agg(p.code, jsonb_build_object('ground', hb.ground, 'ordered', hb.ships,
              'fleets', (select count(*) from public.pirate_ships n where n.home_port = hb.port_id),
              'ships', (select count(*) from public.ships s join public.pirate_ships n on n.fleet_id = s.fleet_id where n.home_port = hb.port_id),
              'afloat', (select count(*) from public.ships s join public.pirate_ships n on n.fleet_id = s.fleet_id where n.home_port = hb.port_id and s.durability > 0),
              'purse', public.city_surplus(hb.port_id), 'crew_pool', p.crew_pool))
             from public.pirate_hubs hb join public.ports p on p.id = hb.port_id),
  'roster', (select jsonb_build_object('fleets', count(*), 'built', count(*) filter (where exists (select 1 from public.pirate_ships n where n.ord = r.ord))) from public.pirate_roster r),
  'pirate_fleets', (select jsonb_build_object('n', count(*), 'sailing', count(*) filter (where f.status = 'SAILING'), 'laid_up', count(*) filter (where n.laid_up_at is not null),
              'unpaid', count(*) filter (where n.unpaid_since is not null), 'wrecks', count(*) filter (where n.wrecked_at is not null),
              'stuck', count(*) filter (where f.status = 'UNABLE_TO_SAIL' and n.laid_up_at is null and coalesce(n.wrecked_at, n.fought_at, n.created_at) < now() - interval '3 hours'))
             from public.pirate_ships n join public.fleets f on f.id = n.fleet_id),
  'waiting_on_a_purse', (select count(*) from public.npc_refit_waits w join public.pirate_ships n on n.fleet_id = w.fleet_id),
  'pressure', (select jsonb_object_agg(s.code, sp.value) from public.sea_pressure sp join public.seas s on s.id = sp.sea_id),
  'pressure_over_cap', (select count(*) from public.sea_pressure sp where sp.value > public.wc_num('pirate_pressure_max')),
  'hoard', public.pirate_hoard(), 'room_today', public.pirate_spend_room(now()),
  'spent', (select jsonb_agg(to_jsonb(d) order by d.day desc) from (select * from public.pirate_spend_day order by day desc limit 3) d),
  'pirates_job', (select jsonb_build_object('runs_1h', count(*), 'avg_ms', round(avg(extract(epoch from d.end_time - d.start_time)) * 1000), 'max_ms', round(max(extract(epoch from d.end_time - d.start_time)) * 1000))
            from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'byeharu-voyage:pirates' and d.start_time > now() - interval '1 hour'),
  'navy_job', (select jsonb_build_object('avg_ms', round(avg(extract(epoch from d.end_time - d.start_time)) * 1000), 'max_ms', round(max(extract(epoch from d.end_time - d.start_time)) * 1000))
            from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'byeharu-voyage:navy' and d.start_time > now() - interval '1 hour'),
  'beat', (select jsonb_build_object('avg_ms', round(avg(extract(epoch from d.end_time - d.start_time)) * 1000), 'max_ms', round(max(extract(epoch from d.end_time - d.start_time)) * 1000))
            from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'byeharu-voyage:arrivals' and d.start_time > now() - interval '1 hour')
) as after;
commit;
