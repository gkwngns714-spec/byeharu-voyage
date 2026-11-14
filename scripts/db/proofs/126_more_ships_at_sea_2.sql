-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 126 - MORE SHIPS AT SEA, 2  (migration 0425; docs/dev-log/2026-11-15-at-sea-2.md; the owner, 2026-11-15: "why are there still ships
--   that are laid up, or in port this much? make it so that it fixes and have as much as ships available at sea possible.")
--
--   On the world's own navy and cargo ships, every scene rolled back with proof.mjs's transaction. EVERY MARKER FAILS ON THE RULES BEFORE 0425:
--   a lie written under the old six-hour navy_hunt_hours kept a ship in port to its old deadline (0423 moved the knob, not the rows), and a
--   capital loaded a city's need on as few ships as 1,000,000 a ship allowed.
--
-- @pass AS2_NAVY_AWAY   a hunter at another sea's harbour whose lie was written under the six-hour knob lies at most navy_hunt_hours from her next step, then SAILS home
-- @pass AS2_NAVY_HOME   a ship lying at her own station under the six-hour knob, her own sea the worst, sails her patrol at her next step (mission PATROL, a voyage)
-- @pass AS2_NAVY_FRESH  a lie written under the live knob is not shortened: she lies to its end
-- @pass AS2_CARGO       a capital whose city is short 1,000,000 loads it on four idle ships of 250,000 in one run (was one ship), and the world's money does not move
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
begin
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled', 'convoys_enabled', 'navy_enabled', 'pirates_bite');
  update public.world_config set value = 'false'::jsonb where key in ('convoy_rich_enabled', 'npc_refits_enabled', 'attack_enabled', 'regard_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  if not public.city_treasury_on() or not public.convoys_on() or not public.navy_hunts_on() then
    raise exception 'PROOF 126 FAIL: the purses, the cargo ships or the hunt cannot be lit in this world';
  end if;
  if public.wc_num('navy_hunt_hours') >= 1 or public.wc('navy_own_sea_patrol') <> 'true'::jsonb then
    raise exception 'PROOF 126 FAIL: the hunt''s knobs are not 0423''s (navy_hunt_hours %, navy_own_sea_patrol %)', public.wc_num('navy_hunt_hours'), public.wc('navy_own_sea_patrol');
  end if;
end
$$;

create function pg_temp.dock_126(p_fleet uuid, p_port uuid) returns void language sql as $f$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = p_port, lat = null, lon = null, ready_at = null, version = f.version + 1 where f.id = p_fleet;
$f$;

-- ── NAVY ──
do $$
declare
  v_t    timestamptz := now();
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid;
  v_own  uuid;
  n      uuid;
  v_s    text;
  t2     record;
  v_vo   public.voyages%rowtype;
  v_lie  interval := make_interval(secs => (public.wc_num('navy_hunt_hours') * 3600)::double precision);
  v_u    timestamptz;
begin
  delete from public.pirate_roster;
  v_cap := public.realm_capital(v_nat);
  v_own := (select p.sea_id from public.ports p where p.id = v_cap);
  -- the scene's ship is the realm's first: the rolls are struck (as proofs 48 and 120 do), no pressure anywhere
  update public.players p set company_name = 'struck ' || substr(md5(gen_random_uuid()::text), 1, 12)
   where p.id in (select x.player_id from public.navy_ships x);
  delete from public.navy_ships x where true;
  delete from public.sea_pressure;
  insert into public.navy_realms (nation_id, ships, read_at) values (v_nat, 25, v_t) on conflict (nation_id) do update set ships = 25, read_at = v_t;
  n := public.navy_commission(v_nat, 1, v_cap, public.refit_yard(v_cap), v_cap, v_t);
  update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = n;
  perform public.navy_plan_step(v_t, v_nat);
  perform public.navy_plan_step(v_t, v_nat);
  if not exists (select 1 from public.navy_patrol_legs l join public.navy_stations s on s.id = l.station_id where s.nation_id = v_nat and s.port_id = v_cap) then
    raise exception 'PROOF 126 FAIL: the capital''s station has no patrol in this world';
  end if;
  select t.port_id, t.sea_id into t2 from public.navy_hunt_targets(v_cap, v_t) t
   where t.sea_id <> v_own and public.cargo_circuit_plan(v_nat, t.port_id, v_cap) #> '{legs,0}' is not null
   order by t.nm, t.port_id limit 1;
  if t2.sea_id is null then
    raise exception 'PROOF 126 FAIL: no other sea''s harbour in reach of the capital with a course home';
  end if;

  -- AS2_NAVY_AWAY: at the hunt harbour of another sea, her lie written under the old knob: her arrival + 6 h
  perform pg_temp.dock_126(n, t2.port_id);
  update public.navy_ships x set mission = 'HUNT', hunt_port = t2.port_id, hunt_until = v_t + interval '6 hours', patrol = null, leg = 0, last_port = t2.port_id
   where x.fleet_id = n;
  v_s := public.navy_ship_step(n, v_t);
  v_u := (select x.hunt_until from public.navy_ships x where x.fleet_id = n);
  if v_s <> 'HUNTING' or v_u <> v_t + v_lie then
    raise exception 'PROOF 126 FAIL: a six-hour lie away from home: % until % (wanted HUNTING until % from now)', v_s, v_u, v_lie;
  end if;
  v_s := public.navy_ship_step(n, v_t + v_lie + interval '1 second');
  select * into v_vo from public.voyages v where v.fleet_id = n and v.status = 'SAILING';
  if v_s <> 'SAILED' or v_vo.dest_port_id is distinct from v_cap then
    raise exception 'PROOF 126 FAIL: past the knob''s lie she did not sail home: % (bound for %)', v_s, v_vo.dest_port_id;
  end if;
  raise notice 'PASS: AS2_NAVY_AWAY — a six-hour lie at % cut to % (her next step), then % home', (select p.code from public.ports p where p.id = t2.port_id), v_lie, v_s;

  -- AS2_NAVY_HOME: lying at her own station under the old knob (now + 5 h), her own sea the worst
  perform pg_temp.dock_126(n, v_cap);
  update public.navy_ships x set mission = 'HUNT', hunt_port = v_cap, hunt_until = v_t + interval '5 hours', patrol = null, leg = 0, last_port = v_cap
   where x.fleet_id = n;
  insert into public.sea_pressure (sea_id, value, updated_at) values (v_own, 400, v_t);
  v_s := public.navy_ship_step(n, v_t + interval '10 minutes');
  select * into v_vo from public.voyages v where v.fleet_id = n and v.status = 'SAILING';
  if v_s <> 'SAILED' or v_vo.id is null
     or (select x.mission || ':' || (x.patrol is not null)::text || ':' || (x.hunt_port is null and x.hunt_until is null)::text from public.navy_ships x where x.fleet_id = n) <> 'PATROL:true:true' then
    raise exception 'PROOF 126 FAIL: lying at her station under the old knob she did not sail her patrol: % %', v_s, (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n);
  end if;
  raise notice 'PASS: AS2_NAVY_HOME — a five-hour lie at her station ended: % on her patrol to %', v_s, (select p.code from public.ports p where p.id = v_vo.dest_port_id);

  -- AS2_NAVY_FRESH: at the hunt harbour, a lie under the knob (100 s) is kept to its end
  delete from public.sea_pressure;
  perform pg_temp.dock_126(n, t2.port_id);
  update public.navy_ships x set mission = 'HUNT', hunt_port = t2.port_id, hunt_until = v_t + interval '100 seconds', patrol = null, leg = 0, last_port = t2.port_id
   where x.fleet_id = n;
  v_s := public.navy_ship_step(n, v_t + interval '99 seconds');
  if v_s <> 'HUNTING' or (select x.hunt_until from public.navy_ships x where x.fleet_id = n) <> v_t + interval '100 seconds' then
    raise exception 'PROOF 126 FAIL: a lie under the knob was moved: %', v_s;
  end if;
  raise notice 'PASS: AS2_NAVY_FRESH — a 100 s lie (the knob: %) kept: %', v_lie, v_s;
end
$$;

-- ── CARGO SHIPS ──
do $$
declare
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid;
  v_city uuid;
  v_idle int;
  v_w0   numeric;
  v_w1   numeric;
  v_r    jsonb;
  v_big  bigint;
  v_i    int;
begin
  if public.wc_int('convoy_load_max') <> 250000 or public.wc_int('convoy_loads_per_run') < 4 then
    raise exception 'PROOF 126 FAIL: a load is % a ship and % ships a run, not 0425''s 250,000 and 20', public.wc_int('convoy_load_max'), public.wc_int('convoy_loads_per_run');
  end if;
  v_cap := public.realm_capital(v_nat);
  for v_i in 1 .. 4 loop
    perform public.tick_cargo_ships(now(), v_nat);
  end loop;
  -- every ship of the realm lies idle at her home, nothing aboard, port time over
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING' and v.fleet_id in (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat);
  update public.fleets f set status = 'DOCKED', port_id = c.home_port_id, lat = null, lon = null, ready_at = null
    from public.cargo_ships c where c.fleet_id = f.id and c.nation_id = v_nat;
  update public.cargo_ships c set out_load = null, circuit_id = null, leg = 0 where c.nation_id = v_nat;
  select count(*) into v_idle
    from public.cargo_ships_in_service c
   where c.nation_id = v_nat and c.ord <= public.convoy_ships_of(c.nation_id) and not exists (select 1 from public.cargo_ship_aboard(c.fleet_id))
     and exists (select 1 from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(c.nation_id, c.home_port_id));
  if v_idle < 5 then
    raise exception 'PROOF 126 FAIL: the scene needs five idle ships of Portugal on a circuit; it has %', v_idle;
  end if;
  select p.id into v_city from public.ports p where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap order by p.code limit 1;
  update public.port_treasury t set ducats = 1000000000 where t.port_id = v_cap;
  update public.port_treasury t set ducats = 0 where t.port_id = v_city;
  v_w0 := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) + public.funds_aboard();
  v_r := public.cargo_ships_load(jsonb_build_array(jsonb_build_object('port_id', v_city, 'cap', v_cap, 'target', 1000000)));
  v_w1 := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) + public.funds_aboard();
  select max(b.ducats) into v_big from public.convoy_cargo b join public.cargo_ships c on c.fleet_id = b.fleet_id where c.nation_id = v_nat and b.stage = 'LOADED';
  if (v_r->>'ships')::int <> 4 or (v_r->>'loaded')::bigint <> 1000000 or v_big > 250000 or v_w1 <> v_w0 then
    raise exception 'PROOF 126 FAIL: a city short 1,000,000: % (largest load %, money before %, after %)', v_r, v_big, v_w0, v_w1;
  end if;
  raise notice 'PASS: AS2_CARGO — a city short 1,000,000: one run loaded % ships with % d. (the largest %), % idle before; the money unmoved',
    v_r->'ships', v_r->'loaded', v_big, v_idle;
end
$$;
