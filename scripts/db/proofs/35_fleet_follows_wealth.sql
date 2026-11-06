-- ═════════════════════════════════════════════════════════════════════════════
-- PROOF 35 — CARGO SHIPS FOLLOW WEALTH  (migration 0326, owner 2026-11-06: "bigger country with more cash - max 50, min 20"; "the country wealth will change, so will the cargoship numbers.")
--
--   0326's self-assert reads the catalog only. This proof sets every realm's purse by hand and runs the REAL job, commission, load, voyage engine and retire, both ways. The sea is stubbed quiet. The economy is CLOSED here, as on prod.
--
-- @pass SIZE_CURVE     richest 50, poorest 20, a log between; a realm far under richest / span is at min and does not move the rest; all level is min
-- @pass SIZE_FLAT_GONE no knob and no body names the flat number; convoy_ships_of reads the rest
-- @pass SIZE_BAND      inside the band a number stays; past it, it moves to the curve; a number outside min..max always moves; the curve is read once an hour
-- @pass SIZE_RISE      the job makes a country's number, convoy_commission_per_run a run, one country a run, inside its ords; no purse moves
-- @pass SIZE_NO_SURPLUS_LOAD a surplus ship takes no load
-- @pass SIZE_FALL      surplus ships lay up highest ord first, convoy_retire_per_run a run; a ship at sea with funds is left alone until her lap is done, then she lays up with nothing aboard
-- @pass SIZE_LAID_UP   a laid-up ship is off the roster and figures, takes no step and is no home; her fleet, hull, house and book stand; no gold vanished
-- @pass SIZE_REUSE     a rise wakes the laid-up ship in that ord: the same fleet and house, no new row
-- @pass SIZE_IDLE_TURN an idle ship steps one run in convoy_idle_every; a ship with a load steps every run
-- ═════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_nat   uuid;
  v_nat2  uuid;
  v_nat3  uuid;
  v_cap   uuid;
  v_stop  uuid;
  v_fl    uuid;
  v_fl2   uuid;
  v_pl    uuid;
  v_n     int;
  v_m     int;
  v_r     jsonb;
  v_sum   bigint;
  v_load  bigint;
  v_now   timestamptz := now();
  v_guard int := 0;
  r       record;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'npc_traders_enabled', 'standing_routes_enabled');
  update public.world_config set value = 'false'::jsonb where key = 'npc_refits_enabled';
  update public.world_config set value = to_jsonb(1) where key = 'convoy_idle_every';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;

  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_35;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$
  select false, null::text, 0.5::numeric, 1::numeric
$b$
  $f$;
  execute $f$
create function pg_temp.purse(p_port uuid, p_d bigint)
returns void
language plpgsql
as $b$
declare
  v_by bigint := p_d - public.treasury_balance(p_port);
begin
  update public.port_treasury t set reserve = 0 where t.port_id = p_port;
  if v_by <> 0 then
    perform public.treasury_post(p_port, 'CROWN_CALL', v_by, null, null, true);
  end if;
end
$b$
  $f$;
  execute $f$
create function pg_temp.realm(p_code text, p_cash bigint)
returns void
language plpgsql
as $b$
-- a probe's hand: the realm's whole cash in its capital, its other harbours at nothing
declare
  q record;
  v_cap uuid := (select p.id from public.nations n join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code = p_code);
  v_nat uuid := (select n.id from public.nations n where n.code = p_code);
begin
  for q in select a.port_id from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR' where a.nation_id = v_nat loop
    perform pg_temp.purse(q.port_id, case when q.port_id = v_cap then p_cash else 0 end);
  end loop;
end
$b$
  $f$;
  execute $f$
create function pg_temp.want(p_code text)
returns int
language sql
as $b$
  select w.ships from public.convoy_ships_wanted() w join public.nations n on n.id = w.nation_id where n.code = p_code
$b$
  $f$;
  execute $f$
create function pg_temp.size(p_code text)
returns int
language sql
as $b$
  select public.convoy_ships_of(n.id) from public.nations n where n.code = p_code
$b$
  $f$;
  execute $f$
create function pg_temp.settle()
returns int
language plpgsql
as $b$
begin
  update public.cargo_fleet_sizes set read_at = '2000-01-01';
  return public.convoy_fleet_settle(now());
end
$b$
  $f$;
  execute $f$
create function pg_temp.ship(p_nat uuid, p_ord int)
returns uuid
language sql
as $b$
  select c.fleet_id from public.cargo_ships c where c.nation_id = p_nat and c.ord = p_ord
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
create function pg_temp.purses()
returns bigint
language sql
as $b$
  select (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)::bigint
       + (select sum(p.ducats) from public.players p)::bigint + public.funds_aboard()
$b$
  $f$;

  select id into v_nat from public.nations where code = 'PRT';
  select id into v_nat2 from public.nations where code = 'ENG';
  select id into v_nat3 from public.nations where code = 'JOS';
  v_cap := public.realm_capital(v_nat);

  -- ── THE CURVE ── the prod numbers of 2026-11-06
  perform pg_temp.realm('PRT', 4380000000);
  perform pg_temp.realm('FRA', 3360000000);
  perform pg_temp.realm('ESP', 2400000000);
  perform pg_temp.realm('NLD', 1600000000);
  perform pg_temp.realm('MNG', 640000000);
  perform pg_temp.realm('OTT', 350000000);
  perform pg_temp.realm('JPN', 290000000);
  perform pg_temp.realm('MUG', 100000000);
  perform pg_temp.realm('ENG', 72000000);
  perform pg_temp.realm('JOS', 13000000);
  if pg_temp.want('PRT') <> 50 or pg_temp.want('JOS') <> 20 or pg_temp.want('ENG') <> 23 or pg_temp.want('ESP') <> 46 or pg_temp.want('JPN') <> 32 then
    raise exception 'PROOF 35 FAIL: the curve: PRT % JOS % ENG % ESP % JPN %', pg_temp.want('PRT'), pg_temp.want('JOS'), pg_temp.want('ENG'), pg_temp.want('ESP'), pg_temp.want('JPN');
  end if;
  v_n := pg_temp.want('ENG');
  perform pg_temp.realm('JOS', 1);
  if pg_temp.want('ENG') <> v_n or pg_temp.want('JOS') <> 20 then
    raise exception 'PROOF 35 FAIL: a nearly broke realm moved another realm''s number';
  end if;
  perform pg_temp.realm('JOS', 13000000);
  for r in select n.code from public.great_powers g join public.nations n on n.id = g.nation_id loop
    perform pg_temp.realm(r.code, 5000000);
  end loop;
  if exists (select 1 from public.convoy_ships_wanted() w where w.ships <> 20) then
    raise exception 'PROOF 35 FAIL: all level is not min';
  end if;
  -- a spread narrower than the span: the poorest is the anchor, still 20 and 50
  perform pg_temp.realm('PRT', 50000000);
  perform pg_temp.realm('JOS', 1000000);
  if pg_temp.want('PRT') <> 50 or pg_temp.want('JOS') <> 20 or pg_temp.want('ENG') not between 21 and 49 then
    raise exception 'PROOF 35 FAIL: a narrow spread: PRT % JOS % ENG %', pg_temp.want('PRT'), pg_temp.want('JOS'), pg_temp.want('ENG');
  end if;
  raise notice 'PASS: SIZE_CURVE — 50 for the richest, 20 for the poorest, the log between; a realm near nothing moves nobody';

  -- ── THE FLAT NUMBER ──
  if exists (select 1 from public.world_config c where c.key = 'convoy_ships_per_nation')
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and strpos(pg_get_functiondef(p.oid), 'convoy_ships_' || 'per_nation') > 0) then
    raise exception 'PROOF 35 FAIL: the flat number stands';
  end if;
  update public.cargo_fleet_sizes s set ships = 33 where s.nation_id = v_nat;
  if public.convoy_ships_of(v_nat) <> 33 then
    raise exception 'PROOF 35 FAIL: convoy_ships_of does not read the rest';
  end if;
  raise notice 'PASS: SIZE_FLAT_GONE — no knob, no body, one reader';

  -- ── THE DEAD BAND ── wanted for ENG lies between; hold it within the band, then past it
  perform pg_temp.realm('ENG', 10000000);
  v_n := pg_temp.want('ENG');
  update public.cargo_fleet_sizes s set ships = v_n + public.wc_int('convoy_ships_band') where s.nation_id = v_nat2;
  perform pg_temp.settle();
  if pg_temp.size('ENG') <> v_n + public.wc_int('convoy_ships_band') then
    raise exception 'PROOF 35 FAIL: inside the band the number moved: % wanted %', pg_temp.size('ENG'), v_n;
  end if;
  update public.cargo_fleet_sizes s set ships = v_n + public.wc_int('convoy_ships_band') + 1 where s.nation_id = v_nat2;
  perform pg_temp.settle();
  if pg_temp.size('ENG') <> v_n then
    raise exception 'PROOF 35 FAIL: past the band the number did not move to the curve';
  end if;
  update public.cargo_fleet_sizes s set ships = 51 where s.nation_id = v_nat;   -- outside min..max, by a band of the curve
  perform pg_temp.settle();
  if pg_temp.size('PRT') <> 50 then
    raise exception 'PROOF 35 FAIL: a number outside min..max stayed';
  end if;
  update public.cargo_fleet_sizes s set ships = 40 where s.nation_id = v_nat;
  if public.convoy_fleet_settle(now() + interval '59 minutes') <> 0 or pg_temp.size('PRT') <> 40 then
    raise exception 'PROOF 35 FAIL: the curve was read inside the hour';
  end if;
  if public.convoy_fleet_settle(now() + interval '61 minutes') < 1 or pg_temp.size('PRT') <> 50 then
    raise exception 'PROOF 35 FAIL: the curve was not read after the hour';
  end if;
  raise notice 'PASS: SIZE_BAND — within the band it holds, past it it moves, outside min..max it moves, read once an hour';

  -- ── UP ── a world of 4 and 12 ships; the job makes them
  update public.cargo_fleet_sizes s set ships = 4, read_at = v_now + interval '2 hours';
  update public.cargo_fleet_sizes s set ships = 12 where s.nation_id = v_nat;
  update public.world_config set value = to_jsonb(3) where key = 'convoy_commission_per_run';
  v_sum := pg_temp.purses();
  -- the circuit first, for the realm the proof sails
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r ->> 'made')::int <> 3 or (select count(*) from public.cargo_ships c where c.nation_id = v_nat) <> 3 then
    raise exception 'PROOF 35 FAIL: a run is not capped: %', v_r;
  end if;
  v_guard := 0;
  while (select count(*) from public.cargo_ships c where c.nation_id = v_nat) < 12 loop
    perform public.tick_cargo_ships(v_now, v_nat);
    v_guard := v_guard + 1;
    if v_guard > 6 then
      raise exception 'PROOF 35 FAIL: the rise stalled';
    end if;
  end loop;
  v_r := public.tick_cargo_ships(v_now, null);
  if (select count(distinct c.nation_id) from public.cargo_ships c where c.nation_id <> v_nat) <> 1 or (v_r ->> 'made')::int <> 3 then
    raise exception 'PROOF 35 FAIL: a run is not one country: %', v_r;
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 35 FAIL: commissioning moved gold';
  end if;
  update public.world_config set value = to_jsonb(10) where key = 'convoy_commission_per_run';
  raise notice 'PASS: SIZE_RISE — 12 ships in four runs of 3, one country a run, no gold moved';

  -- ── DOWN ── a fall to 9; ord 12 sails first with funds; ord 11 and 10 lie idle
  perform pg_temp.purse(v_cap, 100000000);
  v_fl := pg_temp.ship(v_nat, 12);
  v_fl2 := pg_temp.ship(v_nat, 11);
  update public.cargo_fleet_sizes s set ships = 9 where s.nation_id = v_nat;
  v_stop := (select l.to_port from public.cargo_circuit_legs l join public.cargo_circuits k on k.id = l.circuit_id where k.nation_id = v_nat order by l.ord limit 1);
  -- every ship inside the number is out of reach: only the surplus 10, 11, 12 lie idle, and none may load
  update public.cargo_ships c set laid_up_at = v_now where c.nation_id = v_nat and c.ord <= 9;
  v_r := public.cargo_ships_load(jsonb_build_array(jsonb_build_object('port_id', v_stop, 'target', public.treasury_balance(v_stop) + 1000, 'cap', v_cap)));
  update public.cargo_ships c set laid_up_at = null where c.nation_id = v_nat and c.ord <= 9;
  if (v_r ->> 'ships')::int <> 0 or exists (select 1 from public.convoy_cargo b join public.cargo_ships c on c.fleet_id = b.fleet_id where c.nation_id = v_nat) then
    raise exception 'PROOF 35 FAIL: a surplus ship took a load: %', v_r;
  end if;
  raise notice 'PASS: SIZE_NO_SURPLUS_LOAD — with only surplus ships idle, nobody loads';

  -- she loaded while she was inside the number: raise it, load her, drop it
  update public.cargo_fleet_sizes s set ships = 12 where s.nation_id = v_nat;
  update public.cargo_ships c set laid_up_at = v_now where c.nation_id = v_nat and c.ord <= 11;   -- only ord 12 is free to load
  v_r := public.cargo_ships_load(jsonb_build_array(jsonb_build_object('port_id', v_stop, 'target', public.treasury_balance(v_stop) + 5000, 'cap', v_cap)));
  update public.cargo_ships c set laid_up_at = null where c.nation_id = v_nat and c.ord <= 11;
  update public.cargo_fleet_sizes s set ships = 9 where s.nation_id = v_nat;
  select b.ducats into v_load from public.convoy_cargo b where b.fleet_id = v_fl and b.stage = 'LOADED';
  if v_load is null then
    raise exception 'PROOF 35 FAIL: the probe did not load ord 12: %', v_r;
  end if;
  update public.world_config set value = to_jsonb(1) where key = 'convoy_retire_per_run';
  v_sum := pg_temp.purses();

  -- a run: ord 12 is loaded and leaves; the highest idle surplus, 11, lays up
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r ->> 'retired')::int <> 1 or (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_fl2) is null
     or (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_fl) is not null then
    raise exception 'PROOF 35 FAIL: the retire took the wrong ship: %', v_r;
  end if;
  if (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
    raise exception 'PROOF 35 FAIL: ord 12 did not sail with her load: %', v_r;
  end if;
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (select c.laid_up_at from public.cargo_ships c where c.nation_id = v_nat and c.ord = 10) is null or (v_r ->> 'retired')::int <> 1 then
    raise exception 'PROOF 35 FAIL: ord 10 did not lay up next: %', v_r;
  end if;
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r ->> 'retired')::int <> 0 or (select count(*) from public.cargo_ships_in_service c where c.nation_id = v_nat) <> 10 then
    raise exception 'PROOF 35 FAIL: a ship at sea or inside the number was laid up: %', v_r;
  end if;

  -- a rise while she is out: 1..9 and 12 are ten ships, but ord 10 is what the number means
  update public.cargo_fleet_sizes s set ships = 10 where s.nation_id = v_nat;
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r ->> 'made')::int <> 1 or (select c.laid_up_at from public.cargo_ships c where c.nation_id = v_nat and c.ord = 10) is not null then
    raise exception 'PROOF 35 FAIL: a ship out of her number hid a short country: %', v_r;
  end if;
  update public.cargo_fleet_sizes s set ships = 9 where s.nation_id = v_nat;
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r ->> 'retired')::int <> 1 then
    raise exception 'PROOF 35 FAIL: ord 10 did not lay up again: %', v_r;
  end if;

  -- her whole lap, the real engine, then she lays up
  v_guard := 0;
  while (select c.out_load is not null or f.status = 'SAILING' from public.cargo_ships c join public.fleets f on f.id = c.fleet_id where c.fleet_id = v_fl) loop
    v_guard := v_guard + 1;
    if v_guard > 200 then
      raise exception 'PROOF 35 FAIL: her lap never ended';
    end if;
    if (select f.status from public.fleets f where f.id = v_fl) = 'SAILING' then
      perform pg_temp.arrive(v_fl);
    end if;
    update public.fleets f set ready_at = null where f.id = v_fl;
    perform public.cargo_ship_step(v_fl, v_now);
  end loop;
  if exists (select 1 from public.cargo_ship_aboard(v_fl)) then
    raise exception 'PROOF 35 FAIL: she came home with funds still aboard';
  end if;
  -- empty but away from her home: not yet. She sails home on a real leg, and only there lays up
  update public.cargo_ships c set home_port_id = v_stop where c.fleet_id = v_fl;
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_fl) is not null or (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
    raise exception 'PROOF 35 FAIL: away from home she was laid up, or stayed: %', v_r;
  end if;
  perform public.tick_cargo_ships(v_now, v_nat);
  if (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_fl) is not null then
    raise exception 'PROOF 35 FAIL: a ship at sea was laid up';
  end if;
  perform pg_temp.arrive(v_fl);
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_fl) is null then
    raise exception 'PROOF 35 FAIL: home and empty, she did not lay up: %', v_r;
  end if;
  if pg_temp.purses() <> v_sum then
    raise exception 'PROOF 35 FAIL: gold vanished: % then %', v_sum, pg_temp.purses();
  end if;
  raise notice 'PASS: SIZE_FALL — 11 then 10 laid up, one a run; 12 sailed her lap with % d. first and laid up empty at home; purses summed the same', v_load;

  -- ── LAID UP ──
  v_pl := (select c.player_id from public.cargo_ships c where c.fleet_id = v_fl);
  if exists (select 1 from public.sea_houses() h where h.player_id = v_pl)
     or exists (select 1 from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e where e ->> 'id' = v_fl::text)
     or (public.cargo_figures() ->> 'cargo_ships')::int <> (select count(*) from public.cargo_ships) - (select count(*) from public.cargo_ships c where c.laid_up_at is not null) then
    raise exception 'PROOF 35 FAIL: a laid-up ship is still on the map or in the figures';
  end if;
  if not exists (select 1 from public.players p where p.id = v_pl and p.ducats = 0)
     or (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED'
     or not exists (select 1 from public.ships s where s.fleet_id = v_fl)
     or not exists (select 1 from public.convoy_cargo b where b.fleet_id = v_fl and b.stage = 'RETURNED' or b.fleet_id = v_fl and b.stage = 'DELIVERED')
     or not exists (select 1 from public.voyages o where o.fleet_id = v_fl)
     or public.fleet_kind(v_fl) <> 'CARGO_SHIP' then
    raise exception 'PROOF 35 FAIL: a laid-up ship lost a row';
  end if;
  update public.fleets f set status = 'UNABLE_TO_SAIL' where f.id = v_fl;
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (select f.status from public.fleets f where f.id = v_fl) <> 'UNABLE_TO_SAIL' then
    raise exception 'PROOF 35 FAIL: a laid-up ship took a step';
  end if;
  update public.fleets f set status = 'DOCKED' where f.id = v_fl;
  raise notice 'PASS: SIZE_LAID_UP — off the roster and figures, no step, and fleet, hull, house, voyages and book all stand';

  -- ── UP AGAIN ── the same ships
  v_n := (select count(*) from public.cargo_ships);
  v_m := (select count(*) from public.players);
  update public.cargo_fleet_sizes s set ships = 12 where s.nation_id = v_nat;
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r ->> 'made')::int <> 3 or (select count(*) from public.cargo_ships) <> v_n or (select count(*) from public.players) <> v_m
     or (select count(*) from public.cargo_ships_in_service c where c.nation_id = v_nat) <> 12
     or pg_temp.ship(v_nat, 12) <> v_fl or (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_fl) is not null then
    raise exception 'PROOF 35 FAIL: the rise did not wake the same ships: %', v_r;
  end if;
  if not exists (select 1 from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e where e ->> 'id' = v_fl::text) then
    raise exception 'PROOF 35 FAIL: a woken ship is not back on the map';
  end if;
  raise notice 'PASS: SIZE_REUSE — ords 10 to 12 woke: the same fleets and houses, no row added, back on the map';

  -- ── IDLE TURNS ──
  update public.world_config set value = to_jsonb(4) where key = 'convoy_idle_every';
  v_n := 0;
  for v_m in 0 .. 3 loop
    v_r := public.tick_cargo_ships(to_timestamp(240 * 1000000 + v_m * 60), v_nat);
    v_n := v_n + coalesce((v_r #>> '{steps,IDLE}')::int, 0);
    if coalesce((v_r #>> '{steps,IDLE}')::int, 0) not between 2 and 4 then
      raise exception 'PROOF 35 FAIL: one run in four did not take a quarter of the idle ships: %', v_r;
    end if;
  end loop;
  if v_n <> (select count(*) from public.cargo_ships_in_service c join public.fleets f on f.id = c.fleet_id where c.nation_id = v_nat and f.status = 'DOCKED') then
    raise exception 'PROOF 35 FAIL: four runs did not step each idle ship once: % steps', v_n;
  end if;
  -- a ship with a load is no idle ship: she steps in every one of four runs
  v_fl2 := pg_temp.ship(v_nat, 3);
  insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats)
    select 'LOADED', c.fleet_id, c.player_id, c.home_port_id, 100 from public.cargo_ships c where c.fleet_id = v_fl2;
  update public.fleets f set ready_at = v_now + interval '1 day' where f.id = v_fl2;
  v_m := 0;
  for v_n in 0 .. 3 loop
    v_r := public.tick_cargo_ships(to_timestamp(240 * 1000000 + v_n * 60), v_nat);
    v_m := v_m + coalesce((v_r #>> '{steps,IN_PORT}')::int, 0);
  end loop;
  if v_m <> 4 then
    raise exception 'PROOF 35 FAIL: a ship with a load did not step every run: % of 4', v_m;
  end if;
  raise notice 'PASS: SIZE_IDLE_TURN — each idle ship once in four runs, a ship with a load in all four';

  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_stub_35;
  alter function voyage.hazard_roll_real_35(uuid, integer) rename to hazard_roll;
end
$$;
