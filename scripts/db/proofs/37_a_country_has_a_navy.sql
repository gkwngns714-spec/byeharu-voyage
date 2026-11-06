-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 37 — A COUNTRY HAS A NAVY  (migration 0331, owner row 285, W12 of docs/WORLD_POWERS.md)
--
--   0331's self-assert reads the catalog only (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof lights navy_enabled and runs the REAL job, the REAL voyage engine, the
--   REAL refit and the REAL purses. The sea is stubbed on one setting, as proof 36's: empty, every day is quiet. The economy is CLOSED here, as on prod (CI's own world is open), and NAVY_OPEN runs the
--   money once more with it open. No count of ships or cities of the probe world is assumed beyond two stations for Portugal, which the proof checks.
--
-- @pass NAVY_DARK       off: the job writes nothing, no row in any navy table, no flow, the card refuses, the kind and origin of a merchant and a company are what they were
-- @pass NAVY_NEEDS_PURSES the knob with the purses dark lights nothing
-- @pass NAVY_SIZE       the size matches the formula at probe purses, cap and floor, read once in its window, the purse one reader
-- @pass NAVY_STATIONS   the capital is first, every city the plan names as covered is within reach of a station, each station a city the power holds, ord n serves rank n and wraps
-- @pass NAVY_BROKE      a capital that cannot pay waits: no hull, no flow, no event, no error, its reserve respected, and a busy capital is passed over
-- @pass NAVY_BUILD      it pays the moment it can: the build cost, capital to the yard, two moved rows, nothing minted, purse 0, no ledger row; one a day
-- @pass NAVY_KIND       she is NAVY, her origin her station, in no merchant table or tend roster, no wage, no dock fee; merchants' and cargo ships' answers stand
-- @pass NAVY_PATROL     a whole patrol through the real voyage engine: every leg in order, hands and stores at each departure, mended home, off again; no gold, no wage, no ledger, no debt
-- @pass NAVY_QUAY       a quay at its floor gives no hands and holds nobody
-- @pass NAVY_PAY        an hour of upkeep: capital to the harbour she last called at, two rows, moved; once an hour; a missed hour is one slice; at the capital nothing moves
-- @pass NAVY_UNPAID     a capital that can pay one ship pays the lowest ord; the other is laid up at her station, with no error and no debt; money back, she wakes, the same fleet
-- @pass NAVY_SHRINK     a falling number lays up the ship above it, never deletes her; a rising one wakes her
-- @pass NAVY_OFF        switch off with a ship at sea: she finishes the leg, sails to her station, is laid up; nothing is built or paid
-- @pass NAVY_WRECK      a wreck goes to her station, which pays the refit, moved; a station that cannot pay keeps her waiting; she forgets the patrol and sails again; dark she is patched free
-- @pass NAVY_FIGHT      a real PIRATES day settles with her guns, no wage, no raise
-- @pass NAVY_FLAG       a flag change re-plans one country a run, retires a station, and the ship sails to her new one
-- @pass NAVY_BOUND      at most navy_steps_per_run steps a run, none starved; one plan step a run; one ship added a run
-- @pass NAVY_SEA        lit, she is a row of world.sea_roster with kind NAVY; laid up she is not; her card serves what she is and refuses anything else
-- @pass NAVY_STORES     navy_store_days covers the longest patrol leg and the longest move between two stations of a realm, at the slowest she can sail
-- @pass NAVY_OPEN       with the economy open the build and the pay move exactly the same
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_t     timestamptz := now();
  v_nat   uuid;
  v_cap   uuid;
  v_yard  uuid;
  v_st2   uuid;
  v_other uuid;
  v_pl1   uuid;
  v_pl2   uuid;
  v_fl1   uuid;
  v_fl2   uuid;
  v_hum   uuid;
  v_hfl   uuid;
  v_mer   uuid;
  v_id    uuid;
  v_voy   uuid;
  v_cost  bigint := (select c.build_cost from public.ship_classes c where c.code = public.wc_text('navy_ship_class'));
  v_slice bigint := round(public.wc_num('navy_upkeep_day') / 24);
  v_need  int := (select c.crew_required from public.ship_classes c where c.code = public.wc_text('navy_ship_class'));
  v_floor int := public.wc_int('npc_crew_pool_floor');
  v_mark  bigint;
  v_led   bigint;
  v_ev    bigint;
  v_sum   bigint;
  v_n     int;
  v_k     int;
  v_a     numeric;
  v_b     numeric;
  v_step  text;
  v_seq   text[] := '{}';
  v_want  text[];
  v_end   timestamptz;
  v_r     jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled', 'combat_bite');
  update public.world_config set value = 'false'::jsonb where key in ('npc_refits_enabled', 'navy_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 0, reserve = 0;

  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_37;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql stable
as $b$
declare
  v_s text := coalesce(current_setting('byeharu.proof_sea', true), '');
begin
  return query select v_s <> '', nullif(v_s, ''), 0.5::numeric, 1::numeric;
end
$b$
  $f$;
  execute $f$
create function pg_temp.purses()
returns bigint
language sql
as $b$
  select (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t)::bigint + (select sum(p.ducats) from public.players p)::bigint + public.funds_aboard()
$b$
  $f$;
  execute $f$
create function pg_temp.purse(p_port uuid, p_d bigint, p_reserve bigint default 0)
returns void
language plpgsql
as $b$
declare
  v_by bigint := p_d - public.treasury_balance(p_port);
begin
  update public.port_treasury t set reserve = p_reserve where t.port_id = p_port;
  if v_by <> 0 then
    perform public.treasury_post(p_port, 'CROWN_CALL', v_by, null, null, true);   -- a probe's hand on a purse: every reader below takes its mark after this
  end if;
end
$b$
  $f$;
  execute $f$
create function pg_temp.reach_port(p_fleet uuid)
returns timestamptz
language plpgsql
as $b$
declare
  v_v uuid;
  v_e timestamptz;
begin
  select o.id, o.eta into v_v, v_e from public.voyages o where o.fleet_id = p_fleet and o.status = 'SAILING';
  loop
    perform voyage.settle(p_fleet, v_e);
    exit when (select f.status from public.fleets f where f.id = p_fleet) <> 'SAILING';
    v_e := (select o.eta from public.voyages o where o.id = v_v);
  end loop;
  update public.fleets f set ready_at = null where f.id = p_fleet;   -- port time is a minute of her life and not what this proof reads
  return v_e;
end
$b$
  $f$;
  execute $f$
create function pg_temp.flows(p_mark bigint, p_kind text)
returns jsonb
language sql
as $b$
  select coalesce(jsonb_agg(jsonb_build_array(p.code, f.ducats, f.player_id) order by f.ducats, p.code), '[]'::jsonb)
    from public.treasury_flows f join public.ports p on p.id = f.port_id where f.id > p_mark and f.kind = p_kind
$b$
  $f$;

  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code = 'PRT';
  v_other := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP');
  v_mer := (select nf.fleet_id from public.npc_fleets nf order by nf.roster_ord limit 1);
  insert into public.players (company_name, nation_id, ducats) values ('Proof 37 house', v_nat, 0) returning id into v_hum;
  v_hfl := public.form_fleet(v_hum, 'Proof 37 fleet', v_cap);
  perform public.commission_ship(v_hum, v_hfl, 'navire', 'Proof 37 hull', true, true);
  update public.ports p set crew_pool = 500;

  -- ── OFF ──
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.tick_navy(v_t);
  if v_r <> jsonb_build_object('plan', null, 'steps', '{}'::jsonb, 'added', null, 'paid', 0)
     or public.navy_on()
     or exists (select 1 from public.navy_ships) or exists (select 1 from public.navy_realms) or exists (select 1 from public.navy_stations) or exists (select 1 from public.navy_patrol_legs)
     or exists (select 1 from public.treasury_flows f where f.id > v_mark) then
    raise exception 'PROOF 37 FAIL: off, the job wrote something: %', v_r;
  end if;
  if public.fleet_kind(v_hfl) <> 'COMPANY' or public.fleet_kind(v_mer) <> 'MERCHANT' or public.fleet_origin(v_hfl) is not null or public.fleet_origin(v_mer) is null then
    raise exception 'PROOF 37 FAIL: off, a kind or an origin moved';
  end if;
  begin
    perform world.navy_ship_card(v_hfl);
    raise exception 'PROOF 37 FAIL: the card served a company';
  exception when others then
    if sqlerrm not like 'E_NOT_FOUND%' then raise; end if;
  end;
  raise notice 'PASS: NAVY_DARK — nothing written, % answers', v_r;

  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';
  update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
  v_r := public.tick_navy(v_t);
  if public.navy_on() or v_r -> 'plan' <> 'null'::jsonb or exists (select 1 from public.navy_realms) then
    raise exception 'PROOF 37 FAIL: with no purses the knob lit something: %', v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  raise notice 'PASS: NAVY_NEEDS_PURSES — purses dark, nothing';

  -- ── SIZE ──
  foreach v_mark in array array[0, 24999999, 25000000, 74000000, 100000000, 2288000000, 4400000000, 90000000000]::bigint[] loop
    perform pg_temp.purse(v_cap, v_mark);
    if public.realm_purse(v_nat) <> v_mark or public.navy_size_for(public.realm_purse(v_nat)) <> least(24, 2 + floor(sqrt(v_mark / 25000000.0))::int) then
      raise exception 'PROOF 37 FAIL: size at purse %: % from a purse of %', v_mark, public.navy_size_for(public.realm_purse(v_nat)), public.realm_purse(v_nat);
    end if;
  end loop;
  if (select w.cash from public.convoy_ships_wanted() w where w.nation_id = v_nat) <> public.realm_purse(v_nat) then
    raise exception 'PROOF 37 FAIL: two readings of a purse';
  end if;
  perform pg_temp.purse(v_cap, 1000000);
  v_n := public.navy_read(v_t);
  if v_n <> (select count(*) from public.great_powers) or public.navy_size_of(v_nat) <> 2 then
    raise exception 'PROOF 37 FAIL: the first read: % rows, size %', v_n, public.navy_size_of(v_nat);
  end if;
  perform pg_temp.purse(v_cap, 4400000000);
  v_n := public.navy_read(v_t + interval '23 hours');
  if v_n <> 0 or public.navy_size_of(v_nat) <> 2 then
    raise exception 'PROOF 37 FAIL: a read inside its window moved the number';
  end if;
  v_n := public.navy_read(v_t + interval '24 hours');
  if v_n = 0 or public.navy_size_of(v_nat) <> 15 then
    raise exception 'PROOF 37 FAIL: the day''s read did not move the number: %', public.navy_size_of(v_nat);
  end if;
  raise notice 'PASS: NAVY_SIZE — 0 d. to 90 B d. match the formula; a purse of 4.4 B d. is 15 ships';
  perform pg_temp.purse(v_cap, 1000000);
  update public.navy_realms r set read_at = null, ships = 0;
  perform public.navy_read(v_t);
  if public.navy_size_of(v_nat) <> 2 then
    raise exception 'PROOF 37 FAIL: the proof wants 2 ships';
  end if;

  -- ── STATIONS ──
  perform public.navy_stations_build(v_nat, v_t);
  v_st2 := public.navy_station_of(v_nat, 2);
  if (select s.port_id from public.navy_stations s where s.nation_id = v_nat and s.rank = 1) <> v_cap or public.navy_station_of(v_nat, 1) <> v_cap then
    raise exception 'PROOF 37 FAIL: the capital is not the first station';
  end if;
  if v_st2 = v_cap then
    raise exception 'PROOF 37 FAIL: this proof needs two Portuguese stations';
  end if;
  v_n := (select count(*) from public.navy_stations s where s.nation_id = v_nat and s.retired_at is null);
  if public.navy_station_of(v_nat, v_n + 1) is distinct from v_cap or public.navy_station_of(v_nat, v_n + 2) is distinct from v_st2 then
    raise exception 'PROOF 37 FAIL: ord does not wrap over % stations', v_n;
  end if;
  if exists (select 1 from public.navy_stations s where s.nation_id = v_nat and public.port_nation(s.port_id) is distinct from v_nat)
     or exists (select 1 from public.ports p where p.kind = 'HARBOUR' and not p.is_ice_closed and public.port_nation(p.id) = v_nat
                 and not exists (select 1 from public.navy_stations s join public.sea_reaches r on r.port_id = s.port_id
                                  where s.nation_id = v_nat and (s.port_id = p.id or (r.reaches ->> p.code)::numeric <= public.wc_num('navy_reach_nm'))))
     or (select sum(x.covers) from public.navy_station_plan(v_nat) x) <> (select count(*) from public.ports p where p.kind = 'HARBOUR' and not p.is_ice_closed and public.port_nation(p.id) = v_nat) then
    raise exception 'PROOF 37 FAIL: a station is not hers, or a city is left uncovered';
  end if;
  raise notice 'PASS: NAVY_STATIONS — Portugal keeps % stations, capital first', v_n;
  perform public.navy_stations_build(v_nat, v_t);
  if (select count(*) from public.navy_stations s where s.nation_id = v_nat) <> v_n then
    raise exception 'PROOF 37 FAIL: a second build of the same plan wrote rows';
  end if;

  -- ── A CAPITAL THAT CANNOT PAY WAITS ──
  update public.navy_realms r set stations_at = v_t + interval '1 day' where r.nation_id <> v_nat;
  v_led := (select count(*) from public.ledger);
  v_ev := (select count(*) from public.events);
  perform pg_temp.purse(v_cap, v_cost - 1);
  v_r := public.tick_navy(v_t, v_nat);
  if v_r -> 'added' <> 'null'::jsonb or exists (select 1 from public.navy_ships) then
    raise exception 'PROOF 37 FAIL: a capital 1 d. short built: %', v_r;
  end if;
  perform pg_temp.purse(v_cap, v_cost + 100, 101);   -- the balance would do; the surplus does not
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.tick_navy(v_t, v_nat);
  if v_r -> 'added' <> 'null'::jsonb or exists (select 1 from public.navy_ships) or pg_temp.flows(v_mark, 'BUILD_NAVY') <> '[]'::jsonb
     or (select count(*) from public.events) <> v_ev or (select count(*) from public.ledger) <> v_led then
    raise exception 'PROOF 37 FAIL: a capital that cannot pay built something: %', v_r;
  end if;
  perform pg_temp.purse(v_cap, v_cost * 2);
  begin
    alter function public.treasury_try_lock(uuid) rename to treasury_try_lock_real_37;
    execute $f$
create function public.treasury_try_lock(p_port uuid)
returns boolean
language sql
as $b$ select false $b$
    $f$;
    v_r := public.tick_navy(v_t, v_nat);
    raise exception using errcode = 'ZX337', message = v_r::text;
  exception when sqlstate 'ZX337' then
    v_r := sqlerrm::jsonb;
  end;
  if v_r -> 'added' <> 'null'::jsonb or v_r -> 'steps' ? 'ERROR' then
    raise exception 'PROOF 37 FAIL: a busy capital was taken: %', v_r;
  end if;
  raise notice 'PASS: NAVY_BROKE — short by 1 d., or by its reserve, or busy: no hull, no flow, no event, no error';

  -- ── THE RUN IT CAN PAY ──
  perform pg_temp.purse(v_cap, v_cost + v_slice);   -- the hull and her first hour
  v_yard := public.refit_yard(v_cap);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_led := (select count(*) from public.ledger);
  v_sum := pg_temp.purses();
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'added' <> 'BUILT' or (select count(*) from public.navy_ships) <> 1 then
    raise exception 'PROOF 37 FAIL: a capital that can pay built nothing: %', v_r;
  end if;
  if pg_temp.flows(v_mark, 'BUILD_NAVY') <> jsonb_build_array(jsonb_build_array((select p.code from public.ports p where p.id = v_cap), -v_cost, null), jsonb_build_array((select p.code from public.ports p where p.id = v_yard), v_cost, null))
     or pg_temp.purses() <> v_sum or public.treasury_balance(v_cap) <> v_slice then
    raise exception 'PROOF 37 FAIL: the build is not one class, capital to yard, moved: %', pg_temp.flows(v_mark, 'BUILD_NAVY');
  end if;
  select n.fleet_id, n.player_id into v_fl1, v_pl1 from public.navy_ships n where n.nation_id = v_nat and n.ord = 1;
  if (select p.ducats from public.players p where p.id = v_pl1) <> 0 or (select count(*) from public.ledger) <> v_led
     or (select string_agg(k.code || ':' || s.crew, ',') from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = v_fl1) <> public.wc_text('navy_ship_class') || ':0'
     or (select f.port_id from public.fleets f where f.id = v_fl1) <> v_cap then
    raise exception 'PROOF 37 FAIL: she is not one crewless hull at her station with an empty purse';
  end if;
  perform pg_temp.purse(v_cap, v_cost * 3);
  v_r := public.tick_navy(v_t + interval '23 hours', v_nat);
  if v_r -> 'added' <> 'null'::jsonb then
    raise exception 'PROOF 37 FAIL: two ships in a day: %', v_r;
  end if;
  v_r := public.tick_navy(v_t + interval '24 hours', v_nat);
  if v_r ->> 'added' <> 'BUILT' then
    raise exception 'PROOF 37 FAIL: no second ship after a day: %', v_r;
  end if;
  select n.fleet_id, n.player_id into v_fl2, v_pl2 from public.navy_ships n where n.nation_id = v_nat and n.ord = 2;
  if (select f.port_id from public.fleets f where f.id = v_fl2) <> v_st2 then
    raise exception 'PROOF 37 FAIL: ship 2 is not at the second station';
  end if;
  raise notice 'PASS: NAVY_BUILD — % d. from the capital to its yard, moved, the run it could pay; one a day', v_cost;
  v_t := v_t + interval '25 hours';

  -- ── THE KIND ──
  if public.fleet_kind(v_fl1) <> 'NAVY' or public.fleet_origin(v_fl1) is distinct from v_cap or public.fleet_origin(v_fl2) is distinct from v_st2
     or public.fleet_kind(v_mer) <> 'MERCHANT' or public.fleet_kind(v_hfl) <> 'COMPANY' or public.fleet_origin(v_hfl) is not null then
    raise exception 'PROOF 37 FAIL: the kind or the origin';
  end if;
  if exists (select 1 from public.npc_houses h where h.player_id in (v_pl1, v_pl2)) or exists (select 1 from public.npc_fleets h where h.fleet_id in (v_fl1, v_fl2))
     or exists (select 1 from public.npc_tend_roster() r where r.fleet_id in (v_fl1, v_fl2)) then
    raise exception 'PROOF 37 FAIL: a merchant table or the tend roster names her';
  end if;
  if not public.crown_house(v_pl1) or public.crown_house(v_hum) or public.crown_house((select f.player_id from public.fleets f where f.id = v_mer)) then
    raise exception 'PROOF 37 FAIL: crown_house';
  end if;
  if public.port_fee(v_st2, v_pl1, 1000) <> 0 or public.port_fee(v_st2, v_hum, 1000) <= 0 then
    raise exception 'PROOF 37 FAIL: the dock fee: navy %, company %', public.port_fee(v_st2, v_pl1, 1000), public.port_fee(v_st2, v_hum, 1000);
  end if;
  update public.ships s set crew = 50 where s.fleet_id = v_fl1;
  if public.fleet_wage(v_fl1, false) <> 0 or public.fleet_wage(v_hfl, false) <= 0 then
    raise exception 'PROOF 37 FAIL: the wage: navy %, company %', public.fleet_wage(v_fl1, false), public.fleet_wage(v_hfl, false);
  end if;
  update public.ships s set crew = 0 where s.fleet_id = v_fl1;
  raise notice 'PASS: NAVY_KIND — NAVY, origin her station, no merchant table, no wage, no dock fee';

  -- ── A WHOLE PATROL ──
  for v_n in 1 .. 12 loop
    v_k := (select count(*) from public.navy_stations s where s.legs_at is not null);
    v_r := public.tick_navy(v_t, v_nat);
    exit when v_r -> 'plan' = 'null'::jsonb;
    if (select count(*) from public.navy_stations s where s.legs_at is not null) <> v_k + 1 then
      raise exception 'PROOF 37 FAIL: not one patrol a run: %', v_r;
    end if;
  end loop;
  v_k := (select count(*) from public.navy_patrol_legs l join public.navy_stations s on s.id = l.station_id where s.port_id = v_cap);
  v_want := array(select (select p.code from public.ports p where p.id = l.to_port) from public.navy_patrol_legs l join public.navy_stations s on s.id = l.station_id where s.port_id = v_cap order by l.ord);
  if v_k < 2 or v_want[v_k] <> (select p.code from public.ports p where p.id = v_cap) then
    raise exception 'PROOF 37 FAIL: the patrol does not end at her station: %', v_want;
  end if;
  v_sum := pg_temp.purses();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_led := (select count(*) from public.ledger);
  for v_id in select f.id from public.fleets f join public.navy_ships n on n.fleet_id = f.id where f.status = 'SAILING' loop   -- the job's runs above sent them out: bring them in, and start from her station
    perform pg_temp.reach_port(v_id);
  end loop;
  update public.navy_ships n set patrol = null, leg = 0 where n.nation_id = v_nat;
  update public.fleets f set port_id = n.station_port, ready_at = null from public.navy_ships n where n.fleet_id = f.id;
  update public.ships s set durability = s.durability - 100 where s.fleet_id = v_fl1;
  for v_n in 1 .. v_k loop
    v_step := public.navy_ship_step(v_fl1, v_t);
    if v_step <> 'SAILED' or (select s.crew from public.ships s where s.fleet_id = v_fl1) <> v_need
       or (select s.water_t > 0 and s.food_t > 0 from public.ships s where s.fleet_id = v_fl1) is not true then
      raise exception 'PROOF 37 FAIL: leg %: %, crew %', v_n, v_step, (select s.crew from public.ships s where s.fleet_id = v_fl1);
    end if;
    v_end := pg_temp.reach_port(v_fl1);
    v_t := greatest(v_t, v_end) + interval '1 second';
    v_seq := v_seq || (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fl1);
  end loop;
  if v_seq <> v_want then
    raise exception 'PROOF 37 FAIL: she called at %, the patrol is %', v_seq, v_want;
  end if;
  v_step := public.navy_ship_step(v_fl1, v_t);
  if v_step <> 'SAILED' or (select n.leg from public.navy_ships n where n.fleet_id = v_fl1) <> 1 then
    raise exception 'PROOF 37 FAIL: she did not start the next patrol: %', v_step;
  end if;
  if (select s.durability from public.ships s where s.fleet_id = v_fl1) <> (select b.durability from public.ships s cross join lateral public.ship_base(s.id) b where s.fleet_id = v_fl1) then
    raise exception 'PROOF 37 FAIL: she was not mended at home';
  end if;
  if (select p.ducats from public.players p where p.id = v_pl1) <> 0 or (select count(*) from public.ledger) <> v_led or pg_temp.purses() <> v_sum
     or exists (select 1 from public.treasury_flows f where f.id > v_mark) then
    raise exception 'PROOF 37 FAIL: a patrol moved gold or left a debt';
  end if;
  raise notice 'PASS: NAVY_PATROL — % legs (%), hands and stores each time, mended home, no gold', v_k, array_to_string(v_seq, ' ');

  -- ── A QUAY AT ITS FLOOR ──
  v_end := pg_temp.reach_port(v_fl1);
  v_t := greatest(v_t, v_end) + interval '1 second';
  update public.ships s set crew = 0 where s.fleet_id = v_fl1;
  update public.ports p set crew_pool = v_floor where p.id = (select f.port_id from public.fleets f where f.id = v_fl1);
  v_step := public.navy_ship_step(v_fl1, v_t);
  if v_step <> 'SAILED' or (select s.crew from public.ships s where s.fleet_id = v_fl1) <> 0
     or (select p.crew_pool from public.ports p where p.id = (select n.last_port from public.navy_ships n where n.fleet_id = v_fl1)) <> v_floor then
    raise exception 'PROOF 37 FAIL: a quay at its floor: %, crew %', v_step, (select s.crew from public.ships s where s.fleet_id = v_fl1);
  end if;
  raise notice 'PASS: NAVY_QUAY — no hands at the floor, and she sails';
  update public.ports p set crew_pool = 500;

  -- ── AN HOUR OF UPKEEP ──
  v_end := pg_temp.reach_port(v_fl1);
  v_t := greatest(v_t, v_end) + interval '1 second';
  update public.fleets f set port_id = v_cap, lat = null, lon = null where f.id = v_fl1;
  update public.navy_ships n set patrol = null, leg = 0 where n.fleet_id = v_fl1;
  update public.navy_realms r set paid_at = null where r.nation_id = v_nat;
  perform pg_temp.purse(v_cap, 10000000);
  update public.navy_ships n set unpaid_since = v_t where n.fleet_id = v_fl1;   -- paid again, she is back on duty
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_sum := pg_temp.purses();
  begin
    alter function public.treasury_try_lock(uuid) rename to treasury_try_lock_real_37;
    execute $f$
create function public.treasury_try_lock(p_port uuid)
returns boolean
language sql
as $b$ select false $b$
    $f$;
    v_a := public.navy_pay(v_t, v_nat);
    raise exception using errcode = 'ZX337', message = v_a::text;
  exception when sqlstate 'ZX337' then
    v_a := sqlerrm::numeric;
  end;
  if v_a <> 0 or pg_temp.flows(v_mark, 'NAVY_PAY') <> '[]'::jsonb or (select r.paid_at from public.navy_realms r where r.nation_id = v_nat) is not null then
    raise exception 'PROOF 37 FAIL: a busy capital paid: %', v_a;
  end if;
  v_a := public.navy_pay(v_t, v_nat);
  if (select n.unpaid_since from public.navy_ships n where n.fleet_id = v_fl1) is not null then
    raise exception 'PROOF 37 FAIL: paid, she stayed unpaid';
  end if;
  if v_a <> v_slice or pg_temp.purses() <> v_sum
     or pg_temp.flows(v_mark, 'NAVY_PAY') <> jsonb_build_array(jsonb_build_array((select p.code from public.ports p where p.id = v_cap), -v_slice, null), jsonb_build_array((select p.code from public.ports p where p.id = v_st2), v_slice, null)) then
    raise exception 'PROOF 37 FAIL: the hour: % %', v_a, pg_temp.flows(v_mark, 'NAVY_PAY');
  end if;
  v_a := public.navy_pay(v_t + interval '59 minutes', v_nat);
  if v_a <> 0 then
    raise exception 'PROOF 37 FAIL: paid twice in an hour';
  end if;
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_a := public.navy_pay(v_t + interval '7 hours', v_nat);
  if v_a <> v_slice then
    raise exception 'PROOF 37 FAIL: a missed hour was carried';
  end if;
  v_t := v_t + interval '7 hours';
  raise notice 'PASS: NAVY_PAY — % d. to the harbour she lies at, moved; the ship at the capital moved nothing; a missed hour is not carried', v_slice;

  -- ── A CAPITAL THAT CAN PAY ONE ──
  perform pg_temp.purse(v_cap, v_slice * 2, v_slice);   -- two on the balance, one of them its reserve
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_t := v_t + interval '1 hour';
  v_a := public.navy_pay(v_t, v_nat);
  if v_a <> 0 or (select n.unpaid_since from public.navy_ships n where n.fleet_id = v_fl1) is not null or (select n.unpaid_since from public.navy_ships n where n.fleet_id = v_fl2) is distinct from v_t then
    raise exception 'PROOF 37 FAIL: one slice did not pay the first ord: %', v_a;
  end if;
  v_step := public.navy_ship_step(v_fl2, v_t);
  if v_step <> 'LAID_UP' or exists (select 1 from public.navy_ships_in_service n where n.fleet_id = v_fl2) or not exists (select 1 from public.fleets f join public.ships s on s.fleet_id = f.id where f.id = v_fl2 and f.status = 'DOCKED' and f.port_id = v_st2) then
    raise exception 'PROOF 37 FAIL: unpaid, she was not laid up at her station: %', v_step;
  end if;
  perform pg_temp.purse(v_cap, 0, 0);
  v_t := v_t + interval '1 hour';
  v_a := public.navy_pay(v_t, v_nat);
  if v_a <> 0 or (select n.unpaid_since from public.navy_ships n where n.fleet_id = v_fl1) is null then
    raise exception 'PROOF 37 FAIL: a broke capital: % d.', v_a;
  end if;
  update public.navy_realms r set added_at = v_t - interval '1 day' where r.nation_id = v_nat;
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'added' is not null or v_r -> 'steps' ? 'ERROR' then
    raise exception 'PROOF 37 FAIL: a broke capital woke a ship: %', v_r;
  end if;
  perform pg_temp.purse(v_cap, 10000000);
  v_t := v_t + interval '1 hour';
  update public.navy_realms r set added_at = v_t - interval '1 day' where r.nation_id = v_nat;
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'added' <> 'WOKEN' then
    raise exception 'PROOF 37 FAIL: paid again, nobody woke: %', v_r;
  end if;
  if (select count(*) from public.navy_ships n where n.nation_id = v_nat) <> 2 then
    raise exception 'PROOF 37 FAIL: a new ship instead of a woken one';
  end if;
  raise notice 'PASS: NAVY_UNPAID — the lowest ord is paid, the other laid up, a broke capital raises nothing, money back she wakes';
  v_t := v_t + interval '1 day';
  update public.navy_realms r set added_at = v_t where r.nation_id = v_nat;
  for v_id in select n.fleet_id from public.navy_ships n where n.nation_id = v_nat and n.laid_up_at is not null loop
    update public.navy_ships n set laid_up_at = null, unpaid_since = null where n.fleet_id = v_id;
  end loop;
  update public.navy_ships n set unpaid_since = null where n.nation_id = v_nat;
  for v_id in select f.id from public.fleets f join public.navy_ships n on n.fleet_id = f.id where n.nation_id = v_nat and f.status = 'SAILING' loop
    v_end := pg_temp.reach_port(v_id);
  end loop;
  v_t := greatest(v_t, v_end) + interval '1 second';

  -- ── A FALLING NUMBER ──
  update public.world_config set value = to_jsonb(1) where key = 'navy_min';
  perform pg_temp.purse(v_cap, 0);
  update public.navy_realms r set read_at = null, added_at = v_t;
  perform public.navy_read(v_t);
  perform pg_temp.purse(v_cap, 10000000);
  if public.navy_size_of(v_nat) <> 1 then
    raise exception 'PROOF 37 FAIL: the proof wants 1 ship, the world says %', public.navy_size_of(v_nat);
  end if;
  for v_n in 1 .. 4 loop
    v_step := public.navy_ship_step(v_fl2, v_t);
    exit when v_step = 'LAID_UP';
    if (select f.status from public.fleets f where f.id = v_fl2) = 'SAILING' then
      v_end := pg_temp.reach_port(v_fl2);
      v_t := greatest(v_t, v_end) + interval '1 second';
    end if;
  end loop;
  if v_step <> 'LAID_UP' or not exists (select 1 from public.fleets f where f.id = v_fl2) or not exists (select 1 from public.navy_ships n where n.fleet_id = v_fl2 and n.laid_up_at is not null) then
    raise exception 'PROOF 37 FAIL: above the number she was not laid up: %', v_step;
  end if;
  update public.world_config set value = to_jsonb(2) where key = 'navy_min';
  update public.navy_realms r set read_at = null, added_at = v_t - interval '1 day';
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'added' <> 'WOKEN' or exists (select 1 from public.navy_ships n where n.fleet_id = v_fl2 and n.laid_up_at is not null) then
    raise exception 'PROOF 37 FAIL: a rising number did not wake her: %', v_r;
  end if;
  raise notice 'PASS: NAVY_SHRINK — laid up at her station, never deleted, the same fleet woken';

  -- ── THE SWITCH OFF, A SHIP AT SEA ──
  for v_id in select f.id from public.fleets f join public.navy_ships n on n.fleet_id = f.id where f.status = 'SAILING' loop
    v_end := pg_temp.reach_port(v_id);
    v_t := greatest(v_t, v_end) + interval '1 second';
  end loop;
  update public.navy_ships n set patrol = null, leg = 0 where n.nation_id = v_nat;
  update public.fleets f set port_id = n.station_port, ready_at = null from public.navy_ships n where n.fleet_id = f.id;
  v_step := public.navy_ship_step(v_fl1, v_t);
  if v_step <> 'SAILED' then
    raise exception 'PROOF 37 FAIL: she would not sail: %', v_step;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'navy_enabled';
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  update public.navy_realms r set paid_at = null, added_at = null;
  update public.navy_ships n set patrol = null, leg = 0 where n.fleet_id = v_fl2;
  v_end := pg_temp.reach_port(v_fl1);
  v_t := greatest(v_t, v_end) + interval '1 second';
  v_step := public.navy_ship_step(v_fl1, v_t);
  if (select f.status from public.fleets f where f.id = v_fl1) = 'SAILING' then
    if v_step <> 'SAILED' or (select n.patrol from public.navy_ships n where n.fleet_id = v_fl1) is not null then
      raise exception 'PROOF 37 FAIL: off, she did not make for her station: %', v_step;
    end if;
    v_end := pg_temp.reach_port(v_fl1);
    v_t := greatest(v_t, v_end) + interval '1 second';
    v_step := public.navy_ship_step(v_fl1, v_t);
  end if;
  if v_step <> 'LAID_UP' or (select f.port_id from public.fleets f where f.id = v_fl1) <> v_cap then
    raise exception 'PROOF 37 FAIL: off, she was not laid up at her station: %', v_step;
  end if;
  v_r := public.tick_navy(v_t, v_nat);
  if v_r -> 'plan' <> 'null'::jsonb or (v_r ->> 'paid')::bigint <> 0 or v_r -> 'added' <> 'null'::jsonb or exists (select 1 from public.treasury_flows f where f.id > v_mark) then
    raise exception 'PROOF 37 FAIL: off, the job built or paid: %', v_r;
  end if;
  raise notice 'PASS: NAVY_OFF — she made for her station and lay up; nothing built, nothing paid';

  -- ── A WRECK ──
  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';
  update public.navy_ships n set laid_up_at = null, unpaid_since = null where n.nation_id = v_nat;
  update public.navy_realms r set added_at = v_t;
  v_step := public.navy_ship_step(v_fl2, v_t);
  if v_step <> 'SAILED' then
    raise exception 'PROOF 37 FAIL: ship 2 would not sail: %', v_step;
  end if;
  -- dark: she limps in and is patched free
  update public.ships s set durability = 0 where s.fleet_id = v_fl1;
  update public.fleets f set status = 'UNABLE_TO_SAIL', ready_at = null where f.id = v_fl1;
  v_step := public.navy_ship_step(v_fl1, v_t);
  if v_step <> 'IN_PORT' or (select s.durability from public.ships s where s.fleet_id = v_fl1) <= 0 or (select f.status from public.fleets f where f.id = v_fl1) <> 'DOCKED' then
    raise exception 'PROOF 37 FAIL: refits dark, she was not patched: %', v_step;
  end if;
  update public.fleets f set ready_at = null where f.id = v_fl1;
  -- lit: every hull at 0 on a stormy day: she is at her station, her station pays
  update public.world_config set value = 'true'::jsonb where key = 'npc_refits_enabled';
  update public.ships s set durability = 0 where s.fleet_id = v_fl2;
  perform set_config('byeharu.proof_sea', 'STORM', true);
  perform voyage.settle(v_fl2, voyage.day_ends_at((select o.id from public.voyages o where o.fleet_id = v_fl2 and o.status = 'SAILING'), 1));
  perform set_config('byeharu.proof_sea', '', true);
  if (select f.status from public.fleets f where f.id = v_fl2) <> 'UNABLE_TO_SAIL' or (select f.port_id from public.fleets f where f.id = v_fl2) <> v_st2 then
    raise exception 'PROOF 37 FAIL: a wreck is not at her station: %', (select f.status from public.fleets f where f.id = v_fl2);
  end if;
  v_step := public.navy_ship_step(v_fl2, v_t);
  if v_step <> 'WRECK' then
    raise exception 'PROOF 37 FAIL: a wreck stepped';
  end if;
  perform pg_temp.purse(v_st2, 0);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_step := public.npc_refit_step(v_fl2, v_t);
  if v_step <> 'WAITING' or pg_temp.flows(v_mark, 'REFIT') <> '[]'::jsonb then
    raise exception 'PROOF 37 FAIL: a station with no money refitted';
  end if;
  v_a := public.npc_refit_cost(v_fl2);
  perform pg_temp.purse(v_st2, 5000000);
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_sum := pg_temp.purses();
  v_step := public.npc_refit_step(v_fl2, v_t);
  if v_step <> 'PAID' or pg_temp.purses() <> v_sum or public.treasury_balance(v_st2) <> 5000000 - v_a::bigint then
    raise exception 'PROOF 37 FAIL: the refit: %', pg_temp.flows(v_mark, 'REFIT');
  end if;
  update public.fleets f set ready_at = null where f.id = v_fl2;
  v_step := public.navy_ship_step(v_fl2, v_t);
  if v_step <> 'SAILED' or (select n.leg from public.navy_ships n where n.fleet_id = v_fl2) <> 1 then
    raise exception 'PROOF 37 FAIL: after her refit she did not start her patrol again: %', v_step;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'npc_refits_enabled';
  raise notice 'PASS: NAVY_WRECK — her station paid % d., moved; a broke one left her waiting; patched free while the rule is dark', v_a;

  -- ── A REAL PIRATES DAY ──
  v_voy := (select o.id from public.voyages o where o.fleet_id = v_fl2 and o.status = 'SAILING');
  perform set_config('byeharu.proof_sea', 'PIRATES', true);
  perform voyage.settle(v_fl2, voyage.day_ends_at(v_voy, 1));
  perform set_config('byeharu.proof_sea', '', true);
  v_r := (select e.payload from public.voyage_events e where e.voyage_id = v_voy and e.day_index = 1 and e.kind = 'PIRATES');
  if v_r is null or v_r ->> 'outcome' is null or (v_r ->> 'wages')::numeric <> 0 or (select p.ducats from public.players p where p.id = v_pl2) <> 0 then
    raise exception 'PROOF 37 FAIL: no PIRATES day through voyage.settle: %', v_r;
  end if;
  raise notice 'PASS: NAVY_FIGHT — %', v_r ->> 'outcome';

  -- ── A FLAG CHANGES ──
  v_end := pg_temp.reach_port(v_fl2);
  v_t := greatest(v_t, v_end) + interval '1 second';
  update public.navy_ships n set patrol = null, leg = 0 where n.fleet_id = v_fl2;
  update public.fleets f set port_id = v_st2, ready_at = null where f.id = v_fl2;
  update public.port_allegiance a set nation_id = v_other, since = v_t where a.port_id = v_st2;
  update public.navy_realms r set stations_at = v_t + interval '1 day' where r.nation_id not in (v_nat, v_other);
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'plan' <> 'STATIONS' then
    raise exception 'PROOF 37 FAIL: a flag change was not planned: %', v_r;
  end if;
  if exists (select 1 from public.navy_stations s where s.nation_id = v_nat and s.port_id = v_st2 and s.retired_at is null) then
    raise exception 'PROOF 37 FAIL: a harbour it lost is still its station';
  end if;
  if (select f.status from public.fleets f where f.id = v_fl2) <> 'SAILING' or (select n.station_port from public.navy_ships n where n.fleet_id = v_fl2) = v_st2
     or public.fleet_origin(v_fl2) <> public.navy_station_of(v_nat, 2) then
    raise exception 'PROOF 37 FAIL: she did not make for her new station: %', v_r;
  end if;
  raise notice 'PASS: NAVY_FLAG — one realm a run, she sails for her new station, and her origin went with her';
  update public.navy_realms r set stations_at = v_t + interval '1 day';

  -- ── THE JOB IS BOUND ──
  update public.world_config set value = to_jsonb(1) where key = 'navy_steps_per_run';
  update public.world_config set value = to_jsonb(0) where key = 'navy_build_hours';
  for v_id in select f.id from public.fleets f join public.navy_ships n on n.fleet_id = f.id where f.status = 'SAILING' loop
    v_end := pg_temp.reach_port(v_id);
    v_t := greatest(v_t, v_end) + interval '1 second';
  end loop;
  update public.navy_ships n set laid_up_at = null, unpaid_since = null;
  update public.fleets f set ready_at = null from public.navy_ships n where n.fleet_id = f.id;
  perform pg_temp.purse(v_cap, 100000000);
  v_r := public.tick_navy(v_t, v_nat);
  v_n := (select coalesce(sum(e.value::int), 0) from jsonb_each_text(v_r -> 'steps') e);
  if v_n <> 1 then
    raise exception 'PROOF 37 FAIL: % steps in a run bound to 1: %', v_n, v_r;
  end if;
  v_id := (select f.id from public.fleets f join public.navy_ships n on n.fleet_id = f.id where f.status = 'SAILING' limit 1);
  v_k := 0;
  for v_n in 1 .. 4 loop
    exit when not exists (select 1 from public.fleets f join public.navy_ships n on n.fleet_id = f.id where n.nation_id = v_nat and f.status <> 'SAILING');
    v_t := v_t + interval '1 minute';
    perform public.tick_navy(v_t, v_nat);
    v_k := v_k + 1;
  end loop;
  if exists (select 1 from public.fleets f join public.navy_ships n on n.fleet_id = f.id where n.nation_id = v_nat and f.status <> 'SAILING') then
    raise exception 'PROOF 37 FAIL: a ship starved under the bound';
  end if;
  update public.world_config set value = to_jsonb(40) where key = 'navy_steps_per_run';
  update public.navy_realms r set ships = 5, read_at = v_t where r.nation_id = v_nat;
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'added' <> 'BUILT' or (select count(*) from public.navy_ships n where n.nation_id = v_nat) <> 3 then
    raise exception 'PROOF 37 FAIL: more than one ship a run: %', v_r;
  end if;
  perform public.navy_stations_build(v_other, v_t);
  perform pg_temp.purse(public.realm_capital(v_other), 100000000);
  update public.navy_realms r set ships = 3, read_at = v_t, added_at = null where r.nation_id = v_other;
  v_k := (select count(*) from public.navy_ships);
  v_r := public.tick_navy(v_t + interval '1 minute');
  if (select count(*) from public.navy_ships) <> v_k + 1 then
    raise exception 'PROOF 37 FAIL: more than one ship a run, world-wide: %', v_r;
  end if;
  update public.world_config set value = to_jsonb(24) where key = 'navy_build_hours';
  raise notice 'PASS: NAVY_BOUND — one step in a run bound to one, every ship served, one ship added a run, world-wide';

  -- ── ON THE SEA, ON THE CARD ──
  v_r := (select e from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e where e ->> 'id' = v_fl1::text);
  if v_r ->> 'kind' is distinct from 'NAVY' or v_r -> 'hulls' is distinct from jsonb_build_array(public.wc_text('navy_ship_class')) then
    raise exception 'PROOF 37 FAIL: her roster row: %', v_r;
  end if;
  if exists (select 1 from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e where e ->> 'id' = v_mer::text and e ? 'kind') then
    raise exception 'PROOF 37 FAIL: a merchant row has a kind';
  end if;
  v_r := world.navy_ship_card(v_fl1);
  if v_r ->> 'station' is null or v_r ->> 'mission' <> 'PATROL' or v_r ->> 'nation_code' <> 'PRT' or jsonb_array_length(v_r -> 'ships') <> 1
     or (v_r -> 'ships' -> 0) ?| array['id', 'water_t', 'food_t'] or v_r ? 'funds' or (v_r -> 'laid_up')::boolean then
    raise exception 'PROOF 37 FAIL: her card: %', v_r;
  end if;
  update public.navy_ships n set laid_up_at = v_t where n.fleet_id = v_fl1;
  if exists (select 1 from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e where e ->> 'id' = v_fl1::text) then
    raise exception 'PROOF 37 FAIL: a laid-up ship is on the sea';
  end if;
  update public.navy_ships n set laid_up_at = null where n.fleet_id = v_fl1;
  perform public.stats_live_fold(v_t, true);
  if (select l.at_sea - l.at_sea_merchants from public.stats_live l)
     <> (select count(*) from public.fleets f join public.navy_ships n on n.fleet_id = f.id where f.status = 'SAILING') then
    raise exception 'PROOF 37 FAIL: a navy ship was counted a merchant: %', (select jsonb_build_array(l.at_sea, l.at_sea_merchants) from public.stats_live l);
  end if;
  if (public.cargo_figures() ->> 'navy_ships')::int <> (select count(*) from public.navy_ships_in_service) then
    raise exception 'PROOF 37 FAIL: the figure: %', public.cargo_figures();
  end if;
  raise notice 'PASS: NAVY_SEA — kind NAVY on the roster, nothing on a merchant, a card, off the sea laid up';

  -- ── EVERY LEG OF THE WORLD ──
  update public.navy_realms r set stations_at = null;
  update public.port_allegiance a set nation_id = v_nat where a.port_id = v_st2;
  for v_n in 1 .. 120 loop
    v_k := (select count(*) from public.navy_stations s where s.legs_at is not null);
    v_step := public.navy_plan_step(v_t);
    exit when v_step is null;
    if (select count(*) from public.navy_stations s where s.legs_at is not null) > v_k + 1 then
      raise exception 'PROOF 37 FAIL: not one patrol a run: %', v_step;
    end if;
    v_t := v_t + interval '1 minute';
  end loop;
  select max(l.nm) into v_a from public.navy_patrol_legs l;
  v_a := greatest(v_a, (select max((r.reaches ->> p2.code)::numeric)
                          from public.navy_stations a join public.sea_reaches r on r.port_id = a.port_id
                          join public.navy_stations b on b.nation_id = a.nation_id and b.id <> a.id join public.ports p2 on p2.id = b.port_id));   -- a move between two stations of a realm, by the shortest water
  v_b := voyage.stores_need_days(v_a, (select k.speed_kn from public.ship_classes k where k.code = public.wc_text('navy_ship_class')) * public.wc_num('hull_speed_floor'));
  if (select count(distinct s.nation_id) from public.navy_stations s) <> (select count(*) from public.great_powers) or v_b > public.wc_num('navy_store_days') then
    raise exception 'PROOF 37 FAIL: the longest patrol leg, % nm, asks % days of stores at her floor, and she carries %', v_a, v_b, public.wc_num('navy_store_days');
  end if;
  raise notice 'PASS: NAVY_STORES — the longest leg or move of % stations, % nm, asks % days; she carries %', (select count(*) from public.navy_stations), v_a, round(v_b, 1), public.wc_num('navy_store_days');

  -- ── THE ECONOMY OPEN, AS CI'S OWN WORLD ──
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  perform pg_temp.purse(v_cap, v_cost + v_slice * 10);
  update public.navy_realms r set paid_at = null, added_at = null where r.nation_id = v_nat;
  update public.world_config set value = to_jsonb(0) where key = 'navy_steps_per_run';
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_sum := pg_temp.purses();
  v_r := public.tick_navy(v_t, v_nat);
  if v_r ->> 'added' <> 'BUILT' or pg_temp.purses() <> v_sum or jsonb_array_length(pg_temp.flows(v_mark, 'BUILD_NAVY')) <> 2 then
    raise exception 'PROOF 37 FAIL: open, the money moved differently: % %', v_r, pg_temp.flows(v_mark, 'BUILD_NAVY');
  end if;
  raise notice 'PASS: NAVY_OPEN — open, the same two rows and the same sum';
end
$$;
