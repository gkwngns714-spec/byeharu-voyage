-- COMBAT SPEED (0422), PROD READ 1 of 2: read-only, ONE statement, static. Run only after db-health/gate.sql is ok.
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/combat-speed/measure-speeds.sql
-- Per kind of fleet (public.fleet_kind's own tests, inlined as plain EXISTS probes: no function is called), over the voyages at sea now:
--   the knots each departed at (voyages.speed_profile's first segment, the figure voyage.depart froze from voyage.fleet_speed), as
--   percentiles; the miles and real minutes of a passage (eta - departed_at); the segments of a passage; and the arrivals a minute the ships
--   at sea make in a steady state (the sum of 1 / passage minutes). Then the fleets of each kind by status.
-- Reads public.voyages through its SAILING rows only (the partial index voyages_due_at), and public.fleets once.
begin transaction read only;
with v as (
  select case when exists (select 1 from public.cargo_ships c where c.fleet_id = v.fleet_id) then 'CARGO_SHIP'
              when exists (select 1 from public.npc_fleets n where n.fleet_id = v.fleet_id) then 'MERCHANT'
              when exists (select 1 from public.navy_ships n where n.fleet_id = v.fleet_id) then 'NAVY'
              when exists (select 1 from public.pirate_ships n where n.fleet_id = v.fleet_id) then 'PIRATE'
              else 'COMPANY' end as kind,
         (v.speed_profile ->> 0)::numeric as kn,
         v.total_nm as nm,
         extract(epoch from v.eta - v.departed_at) / 60.0 as mins,
         jsonb_array_length(v.path) as segs
    from public.voyages v
   where v.status = 'SAILING'
), f as (
  select case when exists (select 1 from public.cargo_ships c where c.fleet_id = f.id) then 'CARGO_SHIP'
              when exists (select 1 from public.npc_fleets n where n.fleet_id = f.id) then 'MERCHANT'
              when exists (select 1 from public.navy_ships n where n.fleet_id = f.id) then 'NAVY'
              when exists (select 1 from public.pirate_ships n where n.fleet_id = f.id) then 'PIRATE'
              else 'COMPANY' end as kind,
         f.status
    from public.fleets f
), fs as (
  select kind, jsonb_object_agg(status, n) as by_status, sum(n) as fleets
    from (select kind, status, count(*) as n from f group by 1, 2) x
   group by kind
), vs as (
  select kind, count(*) as at_sea,
         round((percentile_cont(0.1) within group (order by kn))::numeric, 2) as kn_p10,
         round((percentile_cont(0.25) within group (order by kn))::numeric, 2) as kn_p25,
         round((percentile_cont(0.5) within group (order by kn))::numeric, 2) as kn_median,
         round((percentile_cont(0.75) within group (order by kn))::numeric, 2) as kn_p75,
         round((percentile_cont(0.9) within group (order by kn))::numeric, 2) as kn_p90,
         round(min(kn), 2) as kn_min, round(max(kn), 2) as kn_max,
         round((percentile_cont(0.5) within group (order by nm))::numeric) as nm_median,
         round((percentile_cont(0.5) within group (order by mins))::numeric, 1) as mins_median,
         round((percentile_cont(0.5) within group (order by segs))::numeric, 1) as segs_median,
         round(sum(1.0 / greatest(mins, 0.5))::numeric, 2) as arrivals_per_min
    from v
   group by kind
)
select coalesce(vs.kind, fs.kind) as kind, fs.fleets, fs.by_status, vs.at_sea, vs.kn_p10, vs.kn_p25, vs.kn_median, vs.kn_p75, vs.kn_p90, vs.kn_min,
       vs.kn_max, vs.nm_median, vs.mins_median, vs.segs_median, vs.arrivals_per_min
  from vs full join fs on fs.kind = vs.kind
 order by 1;
commit;
