-- AT-SEA (0423) DIAGNOSIS, CARGO SHIPS AND NAVY. A PROD READ: read-only, ONE statement, stable functions only.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/at-sea/measure-crown.sql
-- Reads cargo_ships (~370 rows) and navy_ships (~45) with their fleets by key; each cargo ship's newest book rows through convoy_cargo_fleet
-- (fleet_id, id); each navy ship's newest ended voyage through voyages_fleet_ended_0249; the purses of the harbours (port_treasury, ~250 rows);
-- the stations and their patrol legs; the circuits. No big table is scanned beyond an index.
-- WHAT IT ANSWERS:
--   cargo.state{}   every cargo ship: laid_up, sailing, wreck, home_loaded, home_idle (at home, nothing aboard), away (docked elsewhere), with surplus
--                   (ord above the country's number) and in_port_ready (port time over); last_loaded: hours since her newest LOADED row; loads_6h.
--   cargo.short     the harbours under their aid target now and what they need, per capital: what a load can carry.
--   cargo.nations[] per country: ships, in service, its number, sailing, idle at home, circuit legs and miles.
--   navy.state{}    every navy ship: sailing, laid_up, unpaid, over the number, wreck, ready_at ahead, at her station, by mission; in port minutes.
--   navy.stations   stations, with legs, without, retired; navy_realms' numbers.
begin transaction read only;
with c as (
  select x.fleet_id, x.nation_id, x.ord, x.home_port_id, x.circuit_id, x.leg, x.out_load, x.laid_up_at, f.status, f.port_id, f.ready_at,
         public.convoy_ships_of(x.nation_id) as wanted,
         (select a.aboard from public.cargo_ship_aboard(x.fleet_id) a) as aboard,
         (select b.created_at from public.convoy_cargo b where b.fleet_id = x.fleet_id and b.stage = 'LOADED' order by b.id desc limit 1) as last_loaded,
         (select b.stage from public.convoy_cargo b where b.fleet_id = x.fleet_id order by b.id desc limit 1) as last_stage
    from public.cargo_ships x join public.fleets f on f.id = x.fleet_id
), cs as (
  select c.*, case
           when c.laid_up_at is not null then 'laid_up'
           when c.status = 'SAILING' then 'sailing'
           when public.npc_wrecked(c.fleet_id) then 'wreck'
           when c.status <> 'DOCKED' then 'status_' || c.status
           when c.port_id = c.home_port_id and coalesce(c.aboard, 0) > 0 then 'home_loaded'
           when c.port_id = c.home_port_id then 'home_idle'
           else 'away' end as st
    from c
), sh as (
  select t.port_id, public.city_capital(t.port_id) as cap, public.city_aid_target(t.port_id) as target, public.treasury_balance(t.port_id) as bal
    from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
), n as (
  select x.fleet_id, x.nation_id, x.ord, x.station_port, x.mission, x.patrol, x.leg, x.unpaid_since, x.laid_up_at, f.status, f.port_id, f.ready_at,
         public.navy_size_of(x.nation_id) as size,
         (select max(v.eta) from public.voyages v where v.fleet_id = x.fleet_id and v.status <> 'SAILING') as last_in
    from public.navy_ships x join public.fleets f on f.id = x.fleet_id
), ns as (
  select n.*, case
           when n.status = 'SAILING' then 'sailing'
           when n.laid_up_at is not null then 'laid_up'
           when public.npc_wrecked(n.fleet_id) then 'wreck'
           when n.status <> 'DOCKED' then 'status_' || n.status
           when n.ready_at > now() then 'port_time'
           when n.mission = 'HUNT' then 'hunting'
           when n.port_id = n.station_port then 'at_station'
           else 'elsewhere' end as st
    from n
)
select jsonb_build_object(
  'at', now(),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('convoys_enabled', 'convoy_rich_enabled', 'convoy_armed_enabled', 'convoy_idle_every', 'convoy_commission_per_run',
                             'convoy_retire_per_run', 'convoy_ships_min', 'convoy_ships_max', 'convoy_rebase_idle_days', 'navy_enabled', 'navy_hunt_per_day',
                             'navy_steps_per_run', 'navy_patrol_stops', 'navy_hunt_hours', 'navy_escorts', 'navy_min', 'navy_max', 'navy_purse_unit',
                             'navy_build_hours', 'pirates_enabled', 'city_treasury_enabled', 'economy_closed', 'treasury_reserve_floor', 'crown_call_share',
                             'crown_call_cover', 'city_reserve_per_tier')),
  'cargo', jsonb_build_object(
     'n', (select count(*) from cs),
     'state', (select jsonb_object_agg(z.st, z.n) from (select cs.st, count(*) as n from cs group by cs.st) z),
     'surplus_in_service', (select count(*) from cs where cs.laid_up_at is null and cs.ord > cs.wanted),
     'home_idle_ready', (select count(*) from cs where cs.st = 'home_idle' and (cs.ready_at is null or cs.ready_at <= now())),
     'home_idle_out_load', (select count(*) from cs where cs.st = 'home_idle' and cs.out_load is not null),
     'away_no_circuit', (select count(*) from cs where cs.st = 'away' and cs.circuit_id is null),
     'last_stage', (select jsonb_object_agg(coalesce(z.s, 'none'), z.n) from (select cs.last_stage as s, count(*) as n from cs group by 1) z),
     'last_loaded_hours', (select jsonb_build_object('lt1', count(*) filter (where cs.last_loaded > now() - interval '1 hour'),
                                                     '1_6', count(*) filter (where cs.last_loaded <= now() - interval '1 hour' and cs.last_loaded > now() - interval '6 hours'),
                                                     '6_24', count(*) filter (where cs.last_loaded <= now() - interval '6 hours' and cs.last_loaded > now() - interval '24 hours'),
                                                     'gt24', count(*) filter (where cs.last_loaded <= now() - interval '24 hours'),
                                                     'never', count(*) filter (where cs.last_loaded is null)) from cs),
     'aboard_sailing', (select jsonb_build_object('n', count(*), 'with_funds', count(*) filter (where cs.aboard > 0), 'funds', coalesce(sum(cs.aboard), 0)) from cs where cs.st = 'sailing'),
     'short', (select jsonb_build_object('harbours', count(*), 'need', coalesce(sum(sh.target - sh.bal), 0), 'capitals', count(distinct sh.cap),
                                         'per_capital', (select jsonb_object_agg(p.code, z.need) from (select sh2.cap, sum(sh2.target - sh2.bal) as need from sh sh2
                                                           where sh2.target > 0 and sh2.bal < sh2.target and sh2.cap is not null group by sh2.cap) z join public.ports p on p.id = z.cap))
                 from sh where sh.target > 0 and sh.bal < sh.target and sh.cap is not null),
     'nations', (select jsonb_agg(jsonb_build_object('code', na.code, 'ships', z.ships, 'in_service', z.svc, 'wanted', z.wanted, 'sailing', z.sailing,
                                                     'home_idle', z.idle, 'laid_up', z.laid,
                                                     'circuits', (select count(*) from public.cargo_circuits ci where ci.nation_id = z.nation_id),
                                                     'legs', (select count(*) from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(z.nation_id, public.realm_capital(z.nation_id))),
                                                     'nm', (select round(sum(l.nm)) from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(z.nation_id, public.realm_capital(z.nation_id))))
                                  order by na.code)
                   from (select cs.nation_id, count(*) as ships, count(*) filter (where cs.laid_up_at is null) as svc, max(cs.wanted) as wanted,
                                count(*) filter (where cs.st = 'sailing') as sailing, count(*) filter (where cs.st = 'home_idle') as idle,
                                count(*) filter (where cs.st = 'laid_up') as laid
                           from cs group by cs.nation_id) z join public.nations na on na.id = z.nation_id)),
  'navy', jsonb_build_object(
     'n', (select count(*) from ns),
     'state', (select jsonb_object_agg(z.st, z.n) from (select ns.st, count(*) as n from ns group by ns.st) z),
     'mission', (select jsonb_object_agg(coalesce(z.m, 'none'), z.n) from (select ns.mission as m, count(*) as n from ns group by 1) z),
     'unpaid', (select count(*) from ns where ns.unpaid_since is not null),
     'over_number', (select count(*) from ns where ns.ord > ns.size),
     'on_patrol_in_port', (select count(*) from ns where ns.st <> 'sailing' and ns.patrol is not null),
     'in_port_min', (select jsonb_build_object('mean', round(avg(extract(epoch from now() - ns.last_in) / 60)::numeric, 1),
                                               'p50', round((percentile_cont(0.5) within group (order by extract(epoch from now() - ns.last_in) / 60))::numeric, 1),
                                               'max', round(max(extract(epoch from now() - ns.last_in) / 60)::numeric, 1))
                       from ns where ns.st <> 'sailing' and ns.laid_up_at is null),
     'stations', (select jsonb_build_object('n', count(*), 'retired', count(*) filter (where s.retired_at is not null),
                                            'no_legs', count(*) filter (where s.retired_at is null and not exists (select 1 from public.navy_patrol_legs l where l.station_id = s.id)),
                                            'legs', (select count(*) from public.navy_patrol_legs l),
                                            'ships_at_station_without_legs', (select count(*) from ns join public.navy_stations s2 on s2.port_id = ns.port_id and s2.nation_id = ns.nation_id and s2.retired_at is null
                                                                                where ns.st = 'at_station' and not exists (select 1 from public.navy_patrol_legs l where l.station_id = s2.id)))
                    from public.navy_stations s),
     'realms', (select jsonb_agg(jsonb_build_object('ships', r.ships, 'purse', r.purse, 'paid_at', r.paid_at, 'stations_at', r.stations_at)) from public.navy_realms r))
) as r;
commit;
