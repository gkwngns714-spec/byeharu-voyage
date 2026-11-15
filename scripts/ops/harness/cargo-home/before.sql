-- 0437 PROD CHECK (cargo-home): WHERE THE SURPLUS CARGO SHIPS ARE, AND HOW LONG EACH WILL TAKE TO COME HOME. Read-only, ONE statement, stable functions only.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/cargo-home/before.sql
-- Run scripts/ops/harness/db-health/gate.sql first (gate_ok true). One row, one jsonb column `r`. after.sql is the same read.
-- Reads cargo_ships (~377) with their fleets by key, each one's open load (public.cargo_ship_aboard: the (fleet_id, id) index of convoy_cargo), her
-- newest book row and SAILING voyage by fleet, her circuit's legs by key, cargo_fleet_sizes (~11), a few knobs, and the cargo job's last 3 runs
-- (cron.job_run_details by its key, newest first). No big table is scanned.
-- WHAT IT ANSWERS:
--   world: ships (rows), laid_up, in_service, stay (in service, ord inside the share), surplus (in service, ord over the share).
--   surplus, by where she is: sea_funds (sailing with gold aboard), sea_home (sailing home, empty), sea_roam (sailing, empty, NOT bound home),
--     port_funds_away, port_empty_away (docked away from home), home_lap (docked home, a lap still open), home_idle (docked home, no lap, nothing
--     aboard: the retire takes her this minute), home_funds (docked home with gold aboard, no lap), wreck.
--   eta_min: minutes until the sailing surplus arrive (p50, p90, max); legs_left: circuit legs still to sail for a surplus ship with gold aboard on
--     a lap, and their nm (p50, p90, max); nm_per_min: how far a cargo ship sails in a real minute (the median of the sailing voyages).
--   roam: the empty ships bound away from home: the stage of their newest book row, and minutes since they left (p50, max).
--   laid_up_never_loaded: laid-up rows with no book row at all. runs: the cargo job's last three runs (status; pg_cron keeps "1 row", not the answer).
-- WANTED, BEFORE 0437: surplus mostly sea_funds + sea_roam (the root cause: a surplus ship keeps her circuit while gold is aboard, and the retire only
--   takes a ship docked home with no lap). AFTER 0437 (+60 min): surplus 0 or a handful still on their last leg; laid_up = ships - in_service; in_service =
--   the sum of the shares (100); every run succeeded. At +30 min: sea_funds near 0 (each recalled at her next port), surplus falling.
begin transaction read only;
with c as (
  select x.fleet_id, x.nation_id, x.ord, x.laid_up_at, x.out_load, x.circuit_id, x.leg, x.home_port_id, f.status, f.port_id,
         coalesce((select z.ships from public.cargo_fleet_sizes z where z.nation_id = x.nation_id), 0) as share,
         (select a.aboard from public.cargo_ship_aboard(x.fleet_id) a) as aboard,
         (select b.stage from public.convoy_cargo b where b.fleet_id = x.fleet_id order by b.id desc limit 1) as last_stage,
         not exists (select 1 from public.convoy_cargo b where b.fleet_id = x.fleet_id) as never_loaded,
         v.dest_port_id as dest, v.eta, v.departed_at, v.total_nm, v.departed_at as dep
    from public.cargo_ships x
    join public.fleets f on f.id = x.fleet_id
    left join lateral (select o.dest_port_id, o.eta, o.departed_at, o.total_nm from public.voyages o
                        where o.fleet_id = x.fleet_id and o.status = 'SAILING' order by o.departed_at desc limit 1) v on true
), s as (
  select c.*,
         case when c.laid_up_at is not null then 'laid_up'
              when c.status = 'SAILING' and c.aboard > 0 then 'sea_funds'
              when c.status = 'SAILING' and c.dest = c.home_port_id then 'sea_home'
              when c.status = 'SAILING' then 'sea_roam'
              when c.status = 'UNABLE_TO_SAIL' then 'wreck'
              when c.port_id is distinct from c.home_port_id and c.aboard > 0 then 'port_funds_away'
              when c.port_id is distinct from c.home_port_id then 'port_empty_away'
              when c.out_load is not null or c.circuit_id is not null then 'home_lap'
              when c.aboard > 0 then 'home_funds'
              else 'home_idle' end as place
    from c
), sur as (
  select s.* from s where s.laid_up_at is null and s.ord > s.share
), lap as (
  select sur.fleet_id, count(l.ord) as legs_left, coalesce(sum(l.nm), 0) as nm_left
    from sur left join public.cargo_circuit_legs l on l.circuit_id = sur.circuit_id and l.ord > sur.leg
   where sur.aboard > 0 and sur.circuit_id is not null
   group by sur.fleet_id
), job as (
  select j.jobid from cron.job j where j.jobname = 'byeharu-voyage:cargo-ships'
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('cargo_fleet_total', 'convoy_retire_per_run', 'convoys_enabled', 'convoy_rich_enabled', 'convoy_idle_every', 'convoy_rebase_idle_days',
                             'convoy_loads_per_run', 'convoy_load_max', 'game_day_seconds')),
  'world', (select jsonb_build_object('ships', count(*), 'laid_up', count(*) filter (where s.laid_up_at is not null),
                                      'in_service', count(*) filter (where s.laid_up_at is null),
                                      'stay', count(*) filter (where s.laid_up_at is null and s.ord <= s.share),
                                      'surplus', count(*) filter (where s.laid_up_at is null and s.ord > s.share),
                                      'shares', (select sum(z.ships) from public.cargo_fleet_sizes z),
                                      'stay_at_sea', count(*) filter (where s.laid_up_at is null and s.ord <= s.share and s.status = 'SAILING'),
                                      'aboard', coalesce(sum(s.aboard) filter (where s.laid_up_at is null), 0)) from s),
  'surplus', (select jsonb_object_agg(x.place, x.n) from (select sur.place, count(*) as n from sur group by sur.place) x),
  'surplus_aboard', (select coalesce(sum(sur.aboard), 0) from sur),
  'eta_min', (select jsonb_build_object(
                'funds', jsonb_build_array(round((percentile_cont(0.5) within group (order by extract(epoch from sur.eta - now()) / 60) filter (where sur.place = 'sea_funds'))::numeric),
                                           round((percentile_cont(0.9) within group (order by extract(epoch from sur.eta - now()) / 60) filter (where sur.place = 'sea_funds'))::numeric),
                                           round((max(extract(epoch from sur.eta - now()) / 60) filter (where sur.place = 'sea_funds'))::numeric)),
                'empty', jsonb_build_array(round((percentile_cont(0.5) within group (order by extract(epoch from sur.eta - now()) / 60) filter (where sur.place in ('sea_home', 'sea_roam')))::numeric),
                                           round((percentile_cont(0.9) within group (order by extract(epoch from sur.eta - now()) / 60) filter (where sur.place in ('sea_home', 'sea_roam')))::numeric),
                                           round((max(extract(epoch from sur.eta - now()) / 60) filter (where sur.place in ('sea_home', 'sea_roam')))::numeric)))
                from sur),
  'legs_left', (select jsonb_build_object('ships', count(*),
                  'legs', jsonb_build_array(percentile_disc(0.5) within group (order by lap.legs_left), percentile_disc(0.9) within group (order by lap.legs_left), max(lap.legs_left)),
                  'nm', jsonb_build_array(round(percentile_cont(0.5) within group (order by lap.nm_left)), round(percentile_cont(0.9) within group (order by lap.nm_left)), round(max(lap.nm_left))))
                  from lap),
  'nm_per_min', (select round((percentile_cont(0.5) within group (order by s.total_nm / nullif(extract(epoch from s.eta - s.departed_at) / 60, 0)))::numeric, 1)
                   from s where s.status = 'SAILING' and s.eta > s.departed_at),
  'roam', (select jsonb_build_object('n', count(*),
                    'stages', (select jsonb_object_agg(coalesce(y.last_stage, 'none'), y.n) from (select s2.last_stage, count(*) as n from s s2 where s2.place = 'sea_roam' group by s2.last_stage) y),
                    'surplus', count(*) filter (where s.ord > s.share),
                    'out_min', jsonb_build_array(round((percentile_cont(0.5) within group (order by extract(epoch from now() - s.dep) / 60))::numeric),
                                                 round(max(extract(epoch from now() - s.dep) / 60)::numeric)),
                    'eta_min_p50', round((percentile_cont(0.5) within group (order by extract(epoch from s.eta - now()) / 60))::numeric))
             from s where s.place = 'sea_roam'),
  'laid_up_never_loaded', (select count(*) from s where s.laid_up_at is not null and s.never_loaded),
  'runs', (select jsonb_agg(jsonb_build_object('end', d.end_time, 'status', d.status, 'msg', left(d.return_message, 300)) order by d.runid desc)
             from (select r.runid, r.end_time, r.status, r.return_message from cron.job_run_details r join job on job.jobid = r.jobid order by r.runid desc limit 3) d)
) as r;
commit;
