-- AT-SEA-2 (0425) DIAGNOSIS: why the navy still lies and the cargo ships stay home after 0423. A PROD READ: read-only, ONE statement, stable functions only.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/at-sea-2/measure.sql
-- Reads navy_ships (~45) and cargo_ships (~370) with their fleets by key; each cargo ship's newest LOADED row through convoy_cargo's (fleet_id, id)
-- index; the harbours' purses (port_treasury, ~250 rows). No big table is scanned beyond an index. Run scripts/ops/harness/db-health/gate.sql first.
-- WHAT IT ANSWERS:
--   navy.lying     the ships lying (mission HUNT, hunt_until ahead): at their station or away, and how long each lie has left. A lie with more left
--                  than navy_hunt_hours is one written under an older, longer knob ("stale"): 0423 moved the knob, not the rows.
--   cargo.nations  per country: idle at home (ready, with a circuit), at sea, at sea with funds, funds aboard, its cities' need now (target less
--                  purse, cities under target), and the room its idle ships' homes may give this run (public.cargo_load_room).
begin transaction read only;
with n as (
  select x.fleet_id, x.mission, x.hunt_port, x.hunt_until, x.station_port, x.patrol, f.status, f.port_id, f.ready_at,
         extract(epoch from x.hunt_until - now()) as left_s
    from public.navy_ships x join public.fleets f on f.id = x.fleet_id
), c as (
  select x.fleet_id, x.nation_id, x.home_port_id, x.laid_up_at, f.status, f.port_id, f.ready_at, x.ord,
         public.convoy_ships_of(x.nation_id) as wanted,
         (select a.aboard from public.cargo_ship_aboard(x.fleet_id) a) as aboard,
         (select b.created_at from public.convoy_cargo b where b.fleet_id = x.fleet_id and b.stage = 'LOADED' order by b.id desc limit 1) as last_loaded,
         exists (select 1 from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(x.nation_id, x.home_port_id)) as has_circuit
    from public.cargo_ships x join public.fleets f on f.id = x.fleet_id
), sh as (
  select public.city_capital(t.port_id) as cap, public.city_aid_target(t.port_id) as target, public.treasury_balance(t.port_id) as bal
    from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
), need as (
  select sh.cap, sum(sh.target - sh.bal)::bigint as need, count(*) as cities from sh where sh.target > 0 and sh.bal < sh.target and sh.cap is not null group by sh.cap
), idle as (
  select c.* from c where c.laid_up_at is null and c.status = 'DOCKED' and c.port_id = c.home_port_id and c.aboard is null
), nat as (
  select na.code, c.nation_id, public.realm_capital(c.nation_id) as cap,
         count(*) filter (where c.laid_up_at is null) as svc,
         count(*) filter (where c.status = 'SAILING') as sea,
         count(*) filter (where c.status = 'SAILING' and c.aboard > 0) as sea_funds,
         coalesce(sum(c.aboard), 0)::bigint as aboard,
         count(*) filter (where c.laid_up_at is null and c.status = 'DOCKED' and c.port_id = c.home_port_id and c.aboard is null) as idle,
         count(*) filter (where c.laid_up_at is null and c.status = 'DOCKED' and c.port_id = c.home_port_id and c.aboard is null and c.has_circuit and c.ord <= c.wanted) as idle_loadable,
         count(*) filter (where c.last_loaded > now() - interval '1 hour') as loaded_1h,
         count(*) filter (where c.last_loaded > now() - interval '6 hours') as loaded_6h,
         count(*) filter (where c.last_loaded is null) as never
    from c join public.nations na on na.id = c.nation_id group by na.code, c.nation_id
), nat2 as (
  select nat.*, coalesce(nd.need, 0) as need, coalesce(nd.cities, 0) as cities,
         (select coalesce(sum(public.cargo_load_room(h.home_port_id, nat.nation_id)), 0)::bigint
            from (select distinct i.home_port_id from idle i where i.nation_id = nat.nation_id) h) as idle_room
    from nat left join need nd on nd.cap = nat.cap
)
select jsonb_build_object(
  'at', now(),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('navy_hunt_hours', 'navy_own_sea_patrol', 'navy_steps_per_run', 'navy_hunt_per_day', 'convoy_loads_per_run', 'convoy_load_max',
                             'convoys_enabled', 'convoy_rich_enabled', 'crown_call_share', 'crown_call_cover', 'city_reserve_per_tier', 'port_prep_seconds')),
  'navy', jsonb_build_object(
     'n', (select count(*) from n),
     'sailing', (select count(*) from n where n.status = 'SAILING'),
     'sailing_hunt', (select count(*) from n where n.status = 'SAILING' and n.mission = 'HUNT'),
     'mission', (select jsonb_object_agg(coalesce(z.m, 'none'), z.k) from (select n.mission as m, count(*) as k from n group by 1) z),
     'lying', (select jsonb_build_object('n', count(*), 'at_station', count(*) filter (where n.hunt_port = n.station_port),
                                         'at_hunt_port', count(*) filter (where n.port_id = n.hunt_port),
                                         'stale', count(*) filter (where n.left_s > public.wc_num('navy_hunt_hours') * 3600 + 60),
                                         'left', jsonb_build_object('lt5m', count(*) filter (where n.left_s < 300), '5_60m', count(*) filter (where n.left_s >= 300 and n.left_s < 3600),
                                                                    '1_3h', count(*) filter (where n.left_s >= 3600 and n.left_s < 10800), '3_6h', count(*) filter (where n.left_s >= 10800 and n.left_s < 21600),
                                                                    'gt6h', count(*) filter (where n.left_s >= 21600)),
                                         'left_min_max', round((max(n.left_s) / 60)::numeric), 'left_min_p50', round((percentile_cont(0.5) within group (order by n.left_s) / 60)::numeric))
                 from n where n.status <> 'SAILING' and n.mission = 'HUNT' and n.hunt_until > now()),
     'docked_other', (select jsonb_object_agg(z.k, z.v) from (select case when n.ready_at > now() then 'port_time' when n.patrol is not null then 'on_patrol'
                                                                         when n.port_id = n.station_port then 'at_station' else 'elsewhere' end as k, count(*) as v
                                                                from n where n.status <> 'SAILING' and not (n.mission = 'HUNT' and coalesce(n.hunt_until > now(), false)) group by 1) z)),
  'cargo', jsonb_build_object(
     'totals', (select jsonb_build_object('svc', sum(svc), 'sea', sum(sea), 'sea_funds', sum(sea_funds), 'aboard', sum(aboard), 'idle', sum(idle), 'idle_loadable', sum(idle_loadable),
                                          'need', sum(need), 'cities_short', sum(cities), 'need_less_aboard', sum(greatest(need - aboard, 0)),
                                          'idle_room', sum(idle_room), 'loaded_1h', sum(loaded_1h), 'loaded_6h', sum(loaded_6h), 'never', sum(never),
                                          'nations_idle_and_open_need', count(*) filter (where idle_loadable > 0 and need > aboard),
                                          'ships_a_run_could_send', sum(least(idle_loadable, ceil(greatest(least(need - aboard, idle_room), 0) / 1000000.0)))) from nat2),
     'nations', (select jsonb_agg(jsonb_build_object('c', code, 'svc', svc, 'sea', sea, 'f', sea_funds, 'ab', aboard, 'idle', idle, 'il', idle_loadable,
                                                     'need', need, 'ct', cities, 'room', idle_room, 'l1', loaded_1h, 'l6', loaded_6h) order by svc desc) from nat2))
) as r;
commit;
