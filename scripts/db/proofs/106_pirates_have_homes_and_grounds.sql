-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 106 - PIRATES HAVE HOMES AND GROUNDS  (migration 0414; docs/dev-log/2026-11-14-pacific-pirates.md)
--
--   THE GUARD THE OWNER ASKED FOR (2026-11-14, of the seven wrecks: "make it so that this problem does not occur again"): no pirate ship may sit
--   unable to sail with no path to repair. Through the pirates' own job (public.tick_pirates), lit, rolled back with proof.mjs's transaction.
--
-- @pass PH_ORDER   the five hubs are held by the pirates and are not homes; the roster is the owner's order in SHIPS (Pacific 70, South Atlantic 40, North Atlantic 40, Indian 30) and every fleet has hulls; each hub has a haunt and a yard in reach
-- @pass PH_BUILT   a roster squadron is built as ONE fleet of four hulls with one lead ship, of kind PIRATE, at her hub; the hoard fell by her hulls' build cost to the ducat and the world total did not move; a second fleet of her house joins the same house
-- @pass PH_REBORN  a wreck whose home's purse is EMPTY is brought home by the job, lies pirate_respawn_minutes, and is whole, docked and stored again; another pirate purse paid the refit (her REFITTED event names the payer and the cost; the hoard falls by at least it, the world total does not move)
-- @pass PH_OLD     a ship of 0339 (a lone xebec of a home with no purse, the six that were stuck) is reborn by the same rule
-- @pass PH_LOUD    with EVERY pirate purse empty she is not mended unpaid and not left silent: she WAITS with a row in public.npc_refit_waits and a REFIT_WAITING event; the merchants' refit job does not touch her; the purse back, the job mends her
-- @pass PH_CAP     five pirate fleets cruising one sea press on it by pirate_pressure_max (1.0), not 2.5: its danger is at most twice the authored figure
-- ═══════════════════════════════════════════════════════════════════════════════
do $p$
declare
  v_now   timestamptz := now();
  v_pir   uuid := public.pirate_nation();
  v_cap   uuid := public.pirate_capital();
  v_ord   int;
  v_hub   uuid;
  v_f     uuid;
  v_f2    uuid;
  v_old   uuid;
  v_cost  bigint;
  v_flow0 bigint;
  v_flow1 bigint;
  v_tot0  numeric;
  v_tot1  numeric;
  v_sea   uuid;
  v_s     text;
begin
  -- PH_ORDER
  if (select count(*) from public.pirate_hubs hb join public.port_allegiance a on a.port_id = hb.port_id where a.nation_id = v_pir and not a.home) <> 5
     or (select jsonb_object_agg(g.ground, g.s) from (select hb.ground, sum(x.n) as s from public.pirate_hubs hb join public.pirate_roster r on r.hub_port = hb.port_id
                                                        join public.pirate_roster_hulls x on x.ord = r.ord group by 1) g)
        <> '{"PACIFIC": 70, "SOUTH_ATLANTIC": 40, "NORTH_ATLANTIC": 40, "INDIAN": 30}'::jsonb
     or exists (select 1 from public.pirate_hubs hb where not exists (select 1 from public.pirate_haunt_of(hb.port_id, 1001)) or public.refit_yard(hb.port_id) is null) then
    raise exception 'PROOF 106 FAIL: the hubs or the roster are not the order';
  end if;
  raise notice 'PASS: PH_ORDER — five hubs held by the pirates, none a home; the roster is 70 / 40 / 40 / 30 ships; each hub has a haunt and a yard in reach';

  -- the world lit as prod is, the hoard able to pay
  update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled', 'npc_refits_enabled') and value is distinct from 'true'::jsonb;
  if not public.pirates_on() or not public.npc_refits_on() then
    raise exception 'PROOF 106 FAIL: the pirates or the refit rule could not be lit in this world';
  end if;
  update public.port_treasury t set ducats = 1900000000 where t.port_id = v_cap;   -- the day's room is pirate_spend_day_pct of the hoard (a rate per real day the clock moves, 0413): the scene's hoard is sized so one day's room holds what the scene builds and mends
  update public.pirate_ships set laid_up_at = v_now where laid_up_at is null;   -- the proof's own fleets only are at work

  -- PH_BUILT
  select r.ord, r.hub_port into v_ord, v_hub from public.pirate_roster r join public.pirate_roster_hulls x on x.ord = r.ord group by r.ord, r.hub_port having sum(x.n) = 4 order by r.ord limit 1;
  select sum(x.n * c.build_cost)::bigint into v_cost from public.pirate_roster_hulls x join public.ship_classes c on c.code = x.class where x.ord = v_ord;
  v_tot0 := (world.stats_now() ->> 'total')::numeric;
  v_flow0 := public.pirate_hoard();
  v_f := public.pirate_commission_fleet(v_ord, public.refit_yard(v_hub), v_now);
  v_f2 := public.pirate_commission_fleet(v_ord - 1, public.refit_yard(v_hub), v_now);
  v_flow1 := public.pirate_hoard();
  v_tot1 := (world.stats_now() ->> 'total')::numeric;
  if v_f is null or v_f2 is null or (select count(*) from public.ships s where s.fleet_id = v_f) <> 4 or (select count(*) from public.ships s where s.fleet_id = v_f and s.is_flagship) <> 1
     or public.fleet_kind(v_f) <> 'PIRATE' or (select f.port_id from public.fleets f where f.id = v_f) <> v_hub
     or (select count(distinct n.player_id) from public.pirate_ships n where n.fleet_id in (v_f, v_f2)) <> 1
     or v_tot1 <> v_tot0
     or v_flow0 - v_flow1 <> v_cost + (select sum(x.n * c.build_cost)::bigint from public.pirate_roster_hulls x join public.ship_classes c on c.code = x.class where x.ord = v_ord - 1) then
    raise exception 'PROOF 106 FAIL: the squadron was not built as one fleet of four hulls paid by the hoard (hoard % then %, world % then %; fleets % %, cost %, capital %)', v_flow0, v_flow1, v_tot0, v_tot1, v_f, v_f2, v_cost, (select t.ducats from public.port_treasury t where t.port_id = v_cap);
  end if;
  raise notice 'PASS: PH_BUILT — roster fleet % is one PIRATE fleet of four hulls at her hub; the hoard paid the yard % and her house''s second fleet joined her house; the world total stayed %', v_ord, v_cost, v_tot1;

  -- PH_REBORN: wrecked away from home, her home's purse EMPTY; the job brings her home and, an hour on, mends her
  update public.port_treasury t set ducats = 0 where t.port_id = v_hub;
  update public.ships set durability = 0, crew = 0 where fleet_id = v_f;
  update public.fleets set status = 'UNABLE_TO_SAIL', port_id = (select c.to_port from public.npc_courses c where c.from_port = v_hub order by c.nm limit 1) where id = v_f;
  v_flow0 := public.pirate_hoard();
  v_tot0 := (world.stats_now() ->> 'total')::numeric;
  perform public.tick_pirates(v_now);
  if (select f.port_id from public.fleets f where f.id = v_f) <> v_hub or (select n.wrecked_at from public.pirate_ships n where n.fleet_id = v_f) is null
     or exists (select 1 from public.ships s where s.fleet_id = v_f and s.durability > 0) then
    raise exception 'PROOF 106 FAIL: the job did not bring the wreck home and stamp her hour';
  end if;
  perform public.tick_pirates(v_now + interval '30 minutes');
  if exists (select 1 from public.ships s where s.fleet_id = v_f and s.durability > 0) then
    raise exception 'PROOF 106 FAIL: she was mended before pirate_respawn_minutes';
  end if;
  perform public.tick_pirates(v_now + interval '61 minutes');
  v_flow1 := public.pirate_hoard();
  v_tot1 := (world.stats_now() ->> 'total')::numeric;
  if exists (select 1 from public.ships s where s.fleet_id = v_f and s.durability <= 0) or (select n.wrecked_at from public.pirate_ships n where n.fleet_id = v_f) is not null
     or (select f.status from public.fleets f where f.id = v_f) not in ('DOCKED', 'SAILING') or v_flow0 - v_flow1 < public.npc_refit_cost(v_f) or v_tot1 <> v_tot0
     or not exists (select 1 from public.events e where e.kind = 'REFITTED' and e.player_id = (select player_id from public.pirate_ships where fleet_id = v_f) and e.payload ->> 'payer' in ('CITY', 'HOARD') and (e.payload ->> 'cost')::bigint = public.npc_refit_cost(v_f))
     or (select sum(s.crew) from public.ships s where s.fleet_id = v_f) <= 0 then
    raise exception 'PROOF 106 FAIL: a wreck whose home''s purse is empty was not reborn whole, manned and paid for by another pirate purse (hoard % then %, world % then %)', v_flow0, v_flow1, v_tot0, v_tot1;
  end if;
  raise notice 'PASS: PH_REBORN — her home''s purse empty, the job brought the wreck home and an hour on she was whole, manned and at work; payer %; the hoard paid her refit cost to a yard and the world total stayed',
    (select e.payload ->> 'payer' from public.events e where e.kind = 'REFITTED' and e.player_id = (select player_id from public.pirate_ships where fleet_id = v_f) order by e.created_at desc limit 1);

  -- PH_OLD: one of 0339's ships, of a home that is no hub and has no purse
  select n.fleet_id into v_old from public.pirate_ships n where n.ord <= 1000 order by (n.home_port <> v_cap) desc, n.ord limit 1;
  if v_old is null then
    select a.port_id into v_hub from public.port_allegiance a where a.nation_id = v_pir and a.home and a.port_id <> v_cap order by a.port_id limit 1;
    v_old := public.pirate_commission(1, v_hub, public.refit_yard(v_hub), v_now);
  end if;
  update public.pirate_ships set laid_up_at = null, unpaid_since = null, wrecked_at = null where fleet_id = v_old;
  update public.port_treasury t set ducats = 0 where t.port_id = (select home_port from public.pirate_ships where fleet_id = v_old) and t.port_id <> v_cap;
  update public.ships set durability = 0 where fleet_id = v_old;
  update public.voyages set status = 'ABORTED' where fleet_id = v_old and status = 'SAILING';
  update public.fleets set status = 'UNABLE_TO_SAIL', ready_at = null, port_id = (select home_port from public.pirate_ships where fleet_id = v_old), lat = null, lon = null where id = v_old;
  perform public.tick_pirates(v_now + interval '2 hours');
  perform public.tick_pirates(v_now + interval '3 hours 1 minute');
  if exists (select 1 from public.ships s where s.fleet_id = v_old and s.durability <= 0) then
    raise exception 'PROOF 106 FAIL: a ship of 0339 at a home with no purse was not reborn (the fault of 2026-11-14 is back)';
  end if;
  raise notice 'PASS: PH_OLD — a lone xebec of 0339, wrecked at a home with no purse, is whole an hour on by the same rule';

  -- PH_LOUD: every pirate purse empty
  update public.ships set durability = 0 where fleet_id = v_f;
  update public.voyages set status = 'ABORTED' where fleet_id = v_f and status = 'SAILING';
  update public.fleets set status = 'UNABLE_TO_SAIL', ready_at = null, port_id = (select home_port from public.pirate_ships where fleet_id = v_f), lat = null, lon = null where id = v_f;
  update public.port_treasury t set ducats = 0 where t.port_id in (select a.port_id from public.port_allegiance a where a.nation_id = v_pir);
  perform public.tick_pirates(v_now + interval '5 hours');
  perform public.tick_pirates(v_now + interval '7 hours');
  call public.tick_npc_refits(false);
  if exists (select 1 from public.ships s where s.fleet_id = v_f and s.durability > 0)
     or not exists (select 1 from public.npc_refit_waits w where w.fleet_id = v_f)
     or not exists (select 1 from public.events e where e.kind = 'REFIT_WAITING' and e.player_id = (select player_id from public.pirate_ships where fleet_id = v_f)) then
    raise exception 'PROOF 106 FAIL: with every pirate purse empty she was mended unpaid, or she waits with no row and no event (a silent wreck)';
  end if;
  update public.port_treasury t set ducats = 1900000000 where t.port_id = v_cap;   -- the day's room is pirate_spend_day_pct of the hoard (a rate per real day the clock moves, 0413): the scene's hoard is sized so one day's room holds what the scene builds and mends
  perform public.tick_pirates(v_now + interval '7 hours 5 minutes');
  if exists (select 1 from public.ships s where s.fleet_id = v_f and s.durability <= 0) or exists (select 1 from public.npc_refit_waits w where w.fleet_id = v_f) then
    raise exception 'PROOF 106 FAIL: the purse back, the job did not mend her';
  end if;
  raise notice 'PASS: PH_LOUD — every pirate purse empty: no hull restored unpaid, a row in npc_refit_waits and a REFIT_WAITING event, the merchants'' refit job leaves her; the purse back, the job mends her';

  -- PH_CAP
  select s.id into v_sea from public.seas s where s.code = 'STH';
  delete from public.sea_pressure;
  update public.pirate_ships set sea_id = null;
  for v_ord in select r.ord from public.pirate_roster r where r.hub_port = (select p.id from public.ports p where p.code = 'PTC') and r.ord not in (select ord from public.pirate_ships) order by r.ord limit 3 loop
    perform public.pirate_commission_fleet(v_ord, public.refit_yard((select p.id from public.ports p where p.code = 'PTC')), v_now);
  end loop;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id in (select fleet_id from public.pirate_ships where ord > 1000);
  update public.fleets f set status = 'DOCKED' where f.id in (select fleet_id from public.pirate_ships where ord > 1000) and f.status not in ('SAILING', 'DOCKED');
  update public.pirate_ships set sea_id = v_sea, laid_up_at = null where ord > 1000;
  perform public.pirate_pressure_write(v_now);
  if (select count(*) from public.pirate_ships_cruising x where x.sea_id = v_sea) < 5 or (select sp.value from public.sea_pressure sp where sp.sea_id = v_sea) <> 1.0
     or voyage.sea_danger(v_sea, v_now) > 2 * voyage.sea_danger(v_sea, null) then
    raise exception 'PROOF 106 FAIL: % fleets in one sea press on it by %, not the cap 1.0', (select count(*) from public.pirate_ships_cruising x where x.sea_id = v_sea), (select sp.value from public.sea_pressure sp where sp.sea_id = v_sea);
  end if;
  raise notice 'PASS: PH_CAP — % pirate fleets cruising the South Pacific press on it by 1.0: danger % against the authored %', (select count(*) from public.pirate_ships_cruising x where x.sea_id = v_sea),
    voyage.sea_danger(v_sea, v_now), voyage.sea_danger(v_sea, null);
end
$p$;
