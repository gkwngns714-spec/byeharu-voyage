-- 0342 DARK PARITY SCENE: run by proof-0342.mjs on the world BEFORE the file and AFTER it, rolled back each time, beside the navy (0331), navy-comes (0333) and the-navy-hunts (0340) scenes.
-- It covers what 0342 cuts that those do not reach, where NO harbour the pirates hold is involved (the rule is then a no-op): in the dark prod has (navy off) the job's answer, her step, the hunt's targets of
-- Lisbon and the call's reader at two points of sea; and with the navy on and the pirates off, the capital's patrol as written (its stops), her first leg, an hour of upkeep to the harbour she lies at, and the escort's
-- answer for a ward bound for a crown harbour. It names only what existed before 0342.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  v_t    timestamptz := now();
  v_nat  uuid;
  v_cap  uuid;
  v_n    uuid;
  v_st   bigint;
  v_mark bigint;
  v_l1   uuid;
  c      public.cargo_ships%rowtype;
  v_s    text;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_bite', 'attack_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 90000000, reserve = 0;
  update public.ports p set crew_pool = 2000;
  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where n.code = 'PRT';
  perform public.tick_cargo_ships(v_t, v_nat);
  perform public.tick_cargo_ships(v_t, v_nat);
  insert into public.navy_realms (nation_id, ships, read_at) values (v_nat, 3, v_t) on conflict (nation_id) do update set ships = 3, read_at = v_t;
  v_n := public.navy_commission(v_nat, 1, v_cap, public.refit_yard(v_cap), v_cap, v_t);
  update public.ships s set crew = k.crew_required from public.ship_classes k where k.id = s.class_id and s.fleet_id = v_n;

  -- NAVY OFF (prod): the job's whole answer, her step, her row; the hunt's targets of Lisbon; the call's reader at the Tagus and off the Azores
  raise notice 'SCENE: job off %', public.tick_navy(v_t, v_nat);
  raise notice 'SCENE: step off %', public.navy_ship_step(v_n, v_t);
  raise notice 'SCENE: row off %', (select jsonb_build_array(x.mission, x.laid_up_at is not null, x.patrol is null) from public.navy_ships x where x.fleet_id = v_n);
  raise notice 'SCENE: targets %', (select md5(jsonb_agg(jsonb_build_array(t.sea_id, t.danger, t.port_id, t.nm) order by t.danger desc, t.nm, t.port_id)::text) from public.navy_hunt_targets(v_cap, v_t) t);
  raise notice 'SCENE: nearest % %', (select p.code from public.ports p where p.id = public.harbour_nearest(38.7, -9.1)), (select p.code from public.ports p where p.id = public.harbour_nearest(38.0, -27.0));

  -- NAVY ON, PIRATES OFF: she wakes, her stations and the capital's patrol are planned; the patrol's stops; her first leg; an hour of upkeep where she lies; the escort's answer for a ward bound for a crown harbour
  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';
  update public.navy_ships x set laid_up_at = null where x.fleet_id = v_n;
  perform public.navy_plan_step(v_t, v_nat);
  perform public.navy_plan_step(v_t, v_nat);
  select s.id into v_st from public.navy_stations s where s.nation_id = v_nat and s.port_id = v_cap and s.retired_at is null;
  raise notice 'SCENE: patrol %', (select jsonb_agg(p.code order by l.ord) from public.navy_patrol_legs l join public.ports p on p.id = l.to_port where l.station_id = v_st);
  raise notice 'SCENE: step on %', public.navy_ship_step(v_n, v_t);
  raise notice 'SCENE: ship on %', (select jsonb_build_array(x.mission, x.patrol is not null, x.leg, f.status, p.code) from public.navy_ships x join public.fleets f on f.id = x.fleet_id join public.voyages v on v.fleet_id = f.id and v.status = 'SAILING' join public.ports p on p.id = v.dest_port_id where x.fleet_id = v_n);
  select l.to_port into v_l1 from public.navy_patrol_legs l where l.station_id = v_st and l.ord = 1;
  update public.voyages v set status = 'ABORTED' where v.fleet_id = v_n and v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = v_l1, lat = null, lon = null, ready_at = null where f.id = v_n;
  update public.navy_realms r set paid_at = null where r.nation_id = v_nat;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  raise notice 'SCENE: pay % %', public.navy_pay(v_t, v_nat), (select jsonb_agg(jsonb_build_array(p.code, f.ducats) order by f.ducats, p.code) from public.treasury_flows f join public.ports p on p.id = f.port_id where f.id > v_mark and f.kind = 'NAVY_PAY');
  -- a cargo ship of her country at sea with funds: the escort's answer and her ward
  select x.* into c from public.cargo_ships x join public.fleets f on f.id = x.fleet_id
   where x.nation_id = v_nat and f.status = 'DOCKED' and x.out_load is null and not exists (select 1 from public.cargo_ship_aboard(x.fleet_id)) order by x.ord limit 1;
  if c.fleet_id is not null then
    update public.fleets f set ready_at = null where f.id = c.fleet_id;
    perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, 100000);
    v_s := public.cargo_ship_step(c.fleet_id, v_t);
    raise notice 'SCENE: ward % %', v_s, (select p.code from public.voyages v join public.ports p on p.id = v.dest_port_id where v.fleet_id = c.fleet_id and v.status = 'SAILING');
    update public.navy_ships x set patrol = null, leg = 0 where x.fleet_id = v_n;
    raise notice 'SCENE: escort % %', public.navy_escort_step(v_n, v_l1, true, v_t), (select jsonb_build_array(x.mission, x.escort_of = c.fleet_id) from public.navy_ships x where x.fleet_id = v_n);
  else
    raise notice 'SCENE: ward none';
  end if;

  raise exception using errcode = 'ZY342';
exception when sqlstate 'ZY342' then
  null;
end
$$;
