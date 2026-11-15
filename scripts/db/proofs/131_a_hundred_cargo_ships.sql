-- ═════════════════════════════════════════════════════════════════════════════
-- PROOF 131 - A HUNDRED CARGO SHIPS  (migration 0430; docs/dev-log/2026-11-15-a-hundred-cargo-ships.md; the owner, 2026-11-15: "each countries
--   including pirates should have cargo ships that are proportional to their size"; "reduce the cargo ship number to 100"; "i see cargoships
--   without money, just roaming around in ocean")
--
--   On the world's own flags and the REAL job, commission, load, voyage engine and retire; the sea stubbed quiet; every scene rolled back. The
--   economy is closed and the purses lit, as on prod. EVERY MARKER FAILS ON THE RULES BEFORE 0430: the number was a curve of cash from 20 to 50
--   for the ten crowns and none for the pirates (~360 ships), and an emptied ship sailed the rest of her circuit.
--
-- @pass C100_SHARE    the shares sum to cargo_fleet_total (100) exactly; every great power with a harbour, the pirates too, keeps at least 1; the rest goes by harbours (the largest remainder, checked by hand); 40 sums to 40; under the count of powers each keeps 1
-- @pass C100_SETTLE   the settle writes each share exactly (no dead band) once an hour; a harbour that changes flag moves the two shares and the sum stays; a power with no harbour loses its row and convoy_ships_of answers 0
-- @pass C100_KNOBS    convoy_ships_min, max, span and band are gone and no body names them; convoy_retire_per_run is 10
-- @pass C100_RETIRE   a share cut from 14 to 2: one run lays up the 10 highest idle ords at home, the next the last 2; a ship at sea is left; no gold moves
-- @pass C100_HOMEWARD a loaded ship emptied at her first city sails ONE leg straight home (HOMEWARD), docks there and closes her lap (HOME); one with funds still aboard sails on to the next city of her circuit; no gold moves
-- ═════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_nat   uuid;
  v_ned   uuid;
  v_pir   uuid;
  v_cap   uuid;
  v_stop  uuid;
  v_stop2 uuid;
  v_port  uuid;
  v_fl    uuid;
  v_n     int;
  v_r     jsonb;
  v_s     text;
  v_w     bigint;
  v_now   timestamptz := now();
  v_guard int;
  v_hand  jsonb;
  v_mine  jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'npc_traders_enabled', 'standing_routes_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('npc_refits_enabled', 'convoy_rich_enabled', 'attack_enabled', 'pirates_bite');
  update public.world_config set value = to_jsonb(1) where key = 'convoy_idle_every';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;

  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_131;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$
  select false, null::text, 0.5::numeric, 1::numeric
$b$
  $f$;
  execute $f$
create function pg_temp.arrive(p_fleet uuid)
returns void
language plpgsql
as $b$
declare
  v_id  uuid;
  v_eta timestamptz;
  v_g   int := 0;
begin
  select o.id, o.eta into v_id, v_eta from public.voyages o where o.fleet_id = p_fleet and o.status = 'SAILING';
  loop
    v_g := v_g + 1;
    perform voyage.settle(p_fleet, v_eta);
    exit when (select f.status from public.fleets f where f.id = p_fleet) <> 'SAILING' or v_g > 50;
    v_eta := (select o.eta from public.voyages o where o.id = v_id);
  end loop;
  update public.fleets f set ready_at = null where f.id = p_fleet;
end
$b$
  $f$;
  execute $f$
create function pg_temp.w()
returns bigint
language sql
as $b$
  select (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)::bigint
       + (select sum(p.ducats) from public.players p)::bigint + public.funds_aboard()
$b$
  $f$;
  execute $f$
create function pg_temp.settle()
returns int
language plpgsql
as $b$
begin
  update public.cargo_fleet_sizes set read_at = '-infinity';
  return public.convoy_fleet_settle(now());
end
$b$
  $f$;
  execute $f$
create function pg_temp.harbours(p_nat uuid)
returns int
language sql
as $b$
  select count(*)::int from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' where a.nation_id = p_nat
$b$
  $f$;

  select id into v_nat from public.nations where code = 'PRT';
  select id into v_ned from public.nations where code = 'NLD';
  select g.nation_id into v_pir from public.great_powers g where g.pirate;
  v_cap := public.realm_capital(v_nat);

  -- ── THE SHARE ──
  perform pg_temp.settle();
  if (select sum(s.ships) from public.cargo_fleet_sizes s) <> 100 or public.wc_int('cargo_fleet_total') <> 100
     or exists (select 1 from public.great_powers g where pg_temp.harbours(g.nation_id) > 0 and public.convoy_ships_of(g.nation_id) < 1)
     or public.convoy_ships_of(v_pir) < 1 then
    raise exception 'PROOF 131 FAIL: the shares: %', (select jsonb_object_agg(n.code, s.ships) from public.cargo_fleet_sizes s join public.nations n on n.id = s.nation_id);
  end if;
  if exists (select 1 from public.great_powers a, public.great_powers b
              where pg_temp.harbours(a.nation_id) > pg_temp.harbours(b.nation_id) and public.convoy_ships_of(a.nation_id) < public.convoy_ships_of(b.nation_id)) then
    raise exception 'PROOF 131 FAIL: a country with more harbours keeps fewer ships';
  end if;
  -- by hand: 1 each, the rest by harbours, floors, then the largest remainders
  with s as (select g.nation_id, n.code, pg_temp.harbours(g.nation_id)::numeric as h from public.great_powers g join public.nations n on n.id = g.nation_id),
       q as (select s.*, 1 + (100 - (select count(*) from s where h > 0)) * s.h / (select sum(h) from s) as quota from s where s.h > 0),
       r as (select q.*, floor(q.quota)::int as base, row_number() over (order by q.quota - floor(q.quota) desc, q.h desc, q.code) as rk from q)
  select jsonb_object_agg(r.code, r.base + case when r.rk <= 100 - (select sum(base) from r) then 1 else 0 end) into v_hand from r;
  select jsonb_object_agg(n.code, s.ships) into v_mine from public.cargo_fleet_sizes s join public.nations n on n.id = s.nation_id;
  if v_hand <> v_mine then
    raise exception 'PROOF 131 FAIL: the shares are not the largest remainder by harbours: % by hand, % written', v_hand, v_mine;
  end if;
  update public.world_config set value = to_jsonb(40) where key = 'cargo_fleet_total';
  perform pg_temp.settle();
  if (select sum(s.ships) from public.cargo_fleet_sizes s) <> 40 or exists (select 1 from public.cargo_fleet_sizes s where s.ships < 1) then
    raise exception 'PROOF 131 FAIL: a total of 40 is not shared to 40';
  end if;
  update public.world_config set value = to_jsonb(5) where key = 'cargo_fleet_total';
  perform pg_temp.settle();
  if exists (select 1 from public.cargo_fleet_sizes s where s.ships <> 1) or (select count(*) from public.cargo_fleet_sizes) <> (select count(*) from public.great_powers g where pg_temp.harbours(g.nation_id) > 0) then
    raise exception 'PROOF 131 FAIL: under the count of powers each does not keep 1';
  end if;
  update public.world_config set value = to_jsonb(100) where key = 'cargo_fleet_total';
  perform pg_temp.settle();
  raise notice 'PASS: C100_SHARE — %; by hand the same; 40 shares to 40; 5 gives each power 1', v_mine;

  -- ── THE SETTLE ──
  update public.cargo_fleet_sizes s set ships = 33 where s.nation_id = v_nat;
  v_n := public.convoy_fleet_settle(now() + interval '59 minutes');   -- each call on its own line: an OR's order is the planner's
  if v_n <> 0 or public.convoy_ships_of(v_nat) <> 33 then
    raise exception 'PROOF 131 FAIL: the shares were read inside the hour';
  end if;
  v_n := public.convoy_fleet_settle(now() + interval '61 minutes');
  if v_n < 1 or public.convoy_ships_of(v_nat) <> (v_mine ->> 'PRT')::int then
    raise exception 'PROOF 131 FAIL: a hand-set number did not go back to the share after the hour (no band): %', public.convoy_ships_of(v_nat);
  end if;
  -- a harbour of Castile-Spain goes to the Netherlands (the home-city guard and the flag triggers are off for this scene: the share reads the flags only)
  set local session_replication_role = replica;
  update public.port_allegiance a set nation_id = v_ned
   where a.port_id = (select a2.port_id from public.port_allegiance a2 join public.ports p on p.id = a2.port_id and p.kind = 'HARBOUR'
                       join public.nations n on n.id = a2.nation_id where n.code = 'ESP' and p.code <> n.capital_port_code order by p.code limit 1);
  perform pg_temp.settle();
  v_n := public.convoy_ships_of(v_ned);
  if (select sum(s.ships) from public.cargo_fleet_sizes s) <> 100 or public.convoy_ships_of(v_ned) < (v_mine ->> 'NLD')::int
     or public.convoy_ships_of((select id from public.nations where code = 'ESP')) > (v_mine ->> 'ESP')::int then
    raise exception 'PROOF 131 FAIL: a flag change: %', (select jsonb_object_agg(n.code, s.ships) from public.cargo_fleet_sizes s join public.nations n on n.id = s.nation_id);
  end if;
  -- the Netherlands lose every harbour: no row, 0 ships
  update public.port_allegiance a set nation_id = (select id from public.nations where code = 'ESP') where a.nation_id = v_ned;
  perform pg_temp.settle();
  set local session_replication_role = origin;
  if exists (select 1 from public.cargo_fleet_sizes s where s.nation_id = v_ned) or public.convoy_ships_of(v_ned) <> 0
     or (select sum(s.ships) from public.cargo_fleet_sizes s) <> 100 then
    raise exception 'PROOF 131 FAIL: a power with no harbour kept a share';
  end if;
  raise notice 'PASS: C100_SETTLE — read hourly, exact; NLD % -> % with a Spanish harbour, sum 100; with none: no row, 0', (v_mine ->> 'NLD'), v_n;

  -- ── THE KNOBS ──
  if exists (select 1 from public.world_config c where c.key in ('convoy_ships_min', 'convoy_ships_max', 'convoy_ships_span', 'convoy_ships_band'))
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) ~ ('convoy_ships_' || '(min|max|span|band)'))
     or public.wc_int('convoy_retire_per_run') <> 10 then
    raise exception 'PROOF 131 FAIL: a retired knob stands or is read, or the retire is not 10 a run';
  end if;
  raise notice 'PASS: C100_KNOBS — four knobs gone, no body names them; 10 lay up a run';

  -- ── THE RETIRE ── Portugal at 14 ships, then a share of 2
  update public.cargo_fleet_sizes s set ships = 1, read_at = v_now + interval '2 hours';
  update public.cargo_fleet_sizes s set ships = 14 where s.nation_id = v_nat;
  update public.port_treasury t set ducats = 100000000, reserve = 0 where t.port_id = v_cap;
  v_guard := 0;
  while (select count(*) from public.cargo_ships c where c.nation_id = v_nat) < 14 loop
    perform public.tick_cargo_ships(v_now, v_nat);
    v_guard := v_guard + 1;
    if v_guard > 4 then
      raise exception 'PROOF 131 FAIL: Portugal''s 14 ships were not made';
    end if;
  end loop;
  -- ord 14 takes a load and sails: at sea, she is left
  update public.cargo_ships c set laid_up_at = v_now where c.nation_id = v_nat and c.ord <= 13;
  v_stop := (select l.to_port from public.cargo_circuit_legs l join public.cargo_circuits k on k.id = l.circuit_id where k.nation_id = v_nat order by l.ord limit 1);
  v_r := public.cargo_ships_load(jsonb_build_array(jsonb_build_object('port_id', v_stop, 'target', public.treasury_balance(v_stop) + 5000, 'cap', v_cap)));
  update public.cargo_ships c set laid_up_at = null where c.nation_id = v_nat and c.ord <= 13;
  v_fl := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 14);
  if public.cargo_ship_step(v_fl, v_now) <> 'SAILED' then
    raise exception 'PROOF 131 FAIL: ord 14 did not sail with her load: %', v_r;
  end if;
  update public.cargo_fleet_sizes s set ships = 2 where s.nation_id = v_nat;
  v_w := pg_temp.w();
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r ->> 'retired')::int <> 10 or exists (select 1 from public.cargo_ships c where c.nation_id = v_nat and c.laid_up_at is not null and c.ord not between 4 and 13) then
    raise exception 'PROOF 131 FAIL: the first run did not lay up ords 13 down to 4: %', v_r;
  end if;
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r ->> 'retired')::int <> 1 or (select count(*) from public.cargo_ships_in_service c where c.nation_id = v_nat) <> 3
     or (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_fl) is not null then
    raise exception 'PROOF 131 FAIL: the second run: ord 3 lays up, ord 14 at sea stays: %', v_r;
  end if;
  if pg_temp.w() <> v_w then
    raise exception 'PROOF 131 FAIL: the lay-ups moved gold';
  end if;
  raise notice 'PASS: C100_RETIRE — 10 then 1 laid up (13..3), ord 14 at sea left in service, no gold moved';

  -- ── HOMEWARD ── ord 14 docks at her first city; the city's reserve takes all she carries: she sails straight home
  v_w := pg_temp.w();
  update public.port_treasury t set reserve = public.treasury_balance(v_stop) + 10000000 where t.port_id = v_stop;
  perform pg_temp.arrive(v_fl);
  if (select f.port_id from public.fleets f where f.id = v_fl) <> v_stop then
    raise exception 'PROOF 131 FAIL: ord 14 did not dock at her first city';
  end if;
  v_s := public.cargo_ship_step(v_fl, v_now);
  if v_s <> 'HOMEWARD' or exists (select 1 from public.cargo_ship_aboard(v_fl))
     or (select o.dest_port_id from public.voyages o where o.fleet_id = v_fl and o.status = 'SAILING') <> v_cap
     or not exists (select 1 from public.convoy_cargo b where b.fleet_id = v_fl and b.stage = 'DELIVERED' and b.port_id = v_stop) then
    raise exception 'PROOF 131 FAIL: emptied at her first city she did not sail straight home: %', v_s;
  end if;
  perform pg_temp.arrive(v_fl);
  v_s := public.cargo_ship_step(v_fl, v_now);
  if v_s <> 'HOME' or (select c.circuit_id is not null or c.out_load is not null from public.cargo_ships c where c.fleet_id = v_fl)
     or (select f.port_id from public.fleets f where f.id = v_fl) <> v_cap then
    raise exception 'PROOF 131 FAIL: home, her lap did not close: %', v_s;
  end if;
  if pg_temp.w() <> v_w then
    raise exception 'PROOF 131 FAIL: the homeward lap moved gold: % -> %', v_w, pg_temp.w();
  end if;
  -- with funds still aboard after her first city (it needs nothing), she sails on to the next city
  update public.port_treasury t set reserve = 0 where t.port_id = v_stop;
  update public.cargo_fleet_sizes s set ships = 14 where s.nation_id = v_nat;
  update public.cargo_ships c set laid_up_at = v_now where c.nation_id = v_nat and c.ord <> 14;
  v_r := public.cargo_ships_load(jsonb_build_array(jsonb_build_object('port_id', v_stop, 'target', public.treasury_balance(v_stop) + 5000, 'cap', v_cap)));
  v_s := case when exists (select 1 from public.cargo_ship_aboard(v_fl)) then public.cargo_ship_step(v_fl, v_now) end;
  if v_s is distinct from 'SAILED' then
    raise exception 'PROOF 131 FAIL: ord 14 did not load and sail again: %', v_r;
  end if;
  update public.port_treasury t set ducats = 1000000000000 where t.port_id = v_stop;   -- now it needs nothing
  perform pg_temp.arrive(v_fl);
  v_s := public.cargo_ship_step(v_fl, v_now);
  v_stop2 := (select l.to_port from public.cargo_circuit_legs l join public.cargo_circuits k on k.id = l.circuit_id where k.nation_id = v_nat and l.ord = 2);
  if not exists (select 1 from public.cargo_ship_aboard(v_fl)) or v_s <> 'SAILED'
     or (select o.dest_port_id from public.voyages o where o.fleet_id = v_fl and o.status = 'SAILING') is distinct from v_stop2 then
    raise exception 'PROOF 131 FAIL: with funds aboard she did not go on to the next city: %', v_s;
  end if;
  raise notice 'PASS: C100_HOMEWARD — emptied at her first city she sailed straight home and closed her lap there; with funds aboard she went on; no gold moved';

  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_stub_131;
  alter function voyage.hazard_roll_real_131(uuid, integer) rename to hazard_roll;
end
$$;
