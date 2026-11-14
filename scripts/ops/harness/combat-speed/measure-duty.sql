-- COMBAT SPEED (0424), PROD READ 2 of 2: read-only, ONE statement, static. Run only after db-health/gate.sql is ok.
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/combat-speed/measure-duty.sql
-- The knobs that pace a combat ship's duty (real-time lies, reach, steps) and where the navy and pirate ships stand now: the navy by mission and
-- at sea or not, the pirates by mission, at work in a sea (sea_id set: THE position for "who raids" and for the hunt), lying at a haunt, laid up.
-- Small tables only (public.world_config, public.navy_ships 43 rows, public.pirate_ships, public.fleets by primary key). No function is called.
begin transaction read only;
select jsonb_build_object(
  'knobs', (select jsonb_object_agg(wc.key, wc.value) from public.world_config wc
             where wc.key in ('time_compression', 'speed_scale', 'pirate_haunt_hours', 'navy_hunt_hours', 'navy_patrol_stops', 'navy_reach_nm',
                              'navy_steps_per_run', 'pirate_respawn_minutes', 'pirate_pressure', 'pirate_pressure_max', 'pirates_bite', 'navy_enabled',
                              'navy_hunts_per_run', 'fleet_speed_by_kind')),
  'navy', (select jsonb_object_agg(k, n) from (
             select n.mission || ':' || f.status || case when n.laid_up_at is not null then ':laid_up' else '' end as k, count(*) as n
               from public.navy_ships n join public.fleets f on f.id = n.fleet_id group by 1) x),
  'pirate', (select jsonb_object_agg(k, n) from (
             select p.mission || ':' || f.status || case when p.sea_id is not null then ':in_sea' else '' end
                    || case when p.haunt_since is not null then ':at_haunt' else '' end
                    || case when p.laid_up_at is not null then ':laid_up' else '' end as k, count(*) as n
               from public.pirate_ships p join public.fleets f on f.id = p.fleet_id group by 1) x)
) as duty;
commit;
