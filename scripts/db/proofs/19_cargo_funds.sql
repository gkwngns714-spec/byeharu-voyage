-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 19 — A CARGO SHIP CARRIES FUNDS  (migration 0309)
--
--   0309's own self-assert moves probe ships by hand over three probe courses (a migration never runs a real game step, docs/OPS_HEALTH.md section 4).
--   This proof lights the switch over the WHOLE world, runs the REAL public.city_day and sails one real lap of a realm through the REAL voyage engine, then the stats fold.
--
-- @pass FUNDS_DARK       dark: the job makes nothing, and the real city_day pays by CROWN_AID with no CONVOY flow
-- @pass FUNDS_CIRCUIT    lit: every great power gets a circuit of every city it reaches, ending at its capital, and its ships; the left-out are named
-- @pass FUNDS_ONE_PATH   lit: the real city_day writes no CROWN_AID, the capital loads exactly the need, and the sum of purses and funds aboard does not move
-- @pass FUNDS_LAP        one real lap: every stop in order through voyage.depart and voyage.settle; the short cities topped up exactly, the rest back home, the sum unmoved
-- @pass FUNDS_TOTAL      with funds aboard, the world total does not move, the fold has no drift, and a real tick_stats counts them in set_aside
-- @pass FUNDS_NO_DEBT    a whole lap leaves no dock fee owed, no wage, no ledger row, no forced home, and her hull whole
-- @pass FUNDS_RAID       a crewless hull takes the fight, the raid and the claim with no error; funds aboard are not in her hold, so nothing is taken
-- @pass FUNDS_WRECK      a real arrival with no hull docks UNABLE_TO_SAIL, and the job patches her and sends her on after the wait
-- @pass FUNDS_COMPACTED  her ended voyages and her reports go with the merchants', so her history does not grow
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_last  int := world.game_day() - 1;
  v_mark  bigint := coalesce((select max(id) from public.treasury_flows), 0);
  v_nat   uuid;
  v_cap   uuid;
  v_cir   bigint;
  v_n     int;
  v_legs  int;
  v_s1    uuid;
  v_s2    uuid;
  v_fl    uuid;
  v_fl2   uuid;
  v_pl    uuid;
  v_voy   uuid;
  v_r     jsonb;
  v_sum   bigint;
  v_tot0  bigint;
  v_now   timestamptz;
  v_end   timestamptz;
  v_step  text;
  v_seq   text[] := '{}';
  v_want  text[];
  v_kinds jsonb;
  v_guard int := 0;
  v_load  bigint;
  v_t0    timestamptz;
  v_ms    numeric;
  v_slot  bigint;
  v_rows  bigint;
  r       record;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled', 'combat_bite');
  update public.cargo_fleet_sizes set ships = 5, read_at = now();   -- 0326 re-cut: a country's number by hand; proof 35 proves the number
  update public.world_config set value = to_jsonb(1) where key = 'convoy_idle_every';
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set earned_day = v_last;   -- only the aid runs

  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code = 'PRT';

  -- every city of the realm at its target, the capital rich
  update public.port_treasury t set ducats = 50000, reserve = 0 where public.city_capital(t.port_id) = v_cap;
  update public.port_treasury t set ducats = 10000000 where t.port_id = v_cap;
  update public.port_treasury t set ducats = 1000 where t.port_id = (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap order by p.code limit 1);

  -- ── DARK ──
  begin
    v_r := public.tick_cargo_ships();
    v_r := jsonb_build_object('tick', v_r, 'day', public.city_day());
    raise exception using errcode = 'ZX319', message = (v_r || jsonb_build_object(
      'aid', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_AID' and f.ducats > 0),
      'convoy', (select count(*) from public.treasury_flows f where f.id > v_mark and f.kind like 'CONVOY%'),
      'ships', (select count(*) from public.cargo_ships), 'circuits', (select count(*) from public.cargo_circuits)))::text;
  exception when sqlstate 'ZX319' then
    v_r := sqlerrm::jsonb;
  end;
  if (v_r ->> 'aid')::bigint < 49000 or (v_r ->> 'convoy')::int <> 0 or (v_r ->> 'ships')::int <> 0 or (v_r ->> 'circuits')::int <> 0 or v_r #> '{tick,steps}' <> '{}'::jsonb then
    raise exception 'PROOF 19 FAIL: dark is not today: %', v_r;
  end if;
  raise notice 'PASS: FUNDS_DARK — instant aid paid % d., no CONVOY flow, no ship, no circuit', v_r ->> 'aid';

  -- ── LIT: the job, one realm a run ──
  update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
  v_t0 := clock_timestamp();
  for v_n in 1 .. 12 loop
    v_r := public.tick_cargo_ships();
  end loop;
  v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  if (select count(distinct k.nation_id) from public.cargo_circuits k) <> (select count(*) from public.great_powers)
     or (select count(*) from public.cargo_ships) <> (select sum(public.convoy_ships_of(g.nation_id)) from public.great_powers g) then
    raise exception 'PROOF 19 FAIL: not every realm got its circuit and ships: %', v_r;
  end if;
  for r in select k.id, k.nation_id, k.left_out, p.id as cap,
                  (select count(*) from public.cargo_circuit_legs l where l.circuit_id = k.id) as legs,
                  (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = k.id order by l.ord desc limit 1) as last_stop,
                  (select count(distinct l.to_port) from public.cargo_circuit_legs l where l.circuit_id = k.id) as stops,
                  (select count(*) from public.ports q where q.kind = 'HARBOUR' and public.city_capital(q.id) = p.id and q.id <> p.id) as cities
             from public.cargo_circuits k join public.nations n on n.id = k.nation_id join public.ports p on p.code = n.capital_port_code loop
    if r.legs > 0 and (r.last_stop <> r.cap or r.stops <> r.legs or r.legs <> r.cities - jsonb_array_length(r.left_out) + 1) then
      raise exception 'PROOF 19 FAIL: a circuit is not capital, every city, capital: % legs, % stops, % cities, left out %', r.legs, r.stops, r.cities, r.left_out;
    end if;
  end loop;
  raise notice 'PASS: FUNDS_CIRCUIT — % realms, % stops, left out %, 12 runs % ms', (select count(*) from public.cargo_circuits),
    (select count(*) from public.cargo_circuit_legs), (select jsonb_agg(x.c) from public.cargo_circuits k cross join lateral jsonb_array_elements_text(k.left_out) x(c)), v_ms;

  select k.id into v_cir from public.cargo_circuits k where k.nation_id = v_nat;
  v_legs := (select count(*) from public.cargo_circuit_legs l where l.circuit_id = v_cir);
  if v_legs < 3 then
    raise exception 'PROOF 19 FAIL: Portugal''s circuit has % legs', v_legs;
  end if;
  v_s1 := (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = v_cir and l.ord = 1);
  v_s2 := (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = v_cir and l.ord = v_legs - 1);
  v_fl := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 1);
  v_fl2 := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 2);
  v_pl := (select c.player_id from public.cargo_ships c where c.fleet_id = v_fl);

  -- two cities short: the first stop and the last
  update public.port_treasury t set ducats = 50000 where public.city_capital(t.port_id) = v_cap and t.port_id <> v_cap;
  update public.port_treasury t set ducats = 1000 where t.port_id in (v_s1, v_s2);
  perform public.stats_live_fold(now());    -- from here the journal starts from the aggregates
  v_tot0 := (world.stats_now() ->> 'total')::bigint;
  v_sum := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) + public.funds_aboard();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);

  -- ── THE REAL city_day, LIT ──
  v_r := public.city_day();
  v_load := (select a.aboard from public.cargo_ship_aboard(v_fl) a);
  if (v_r ->> 'aided')::int <> 0 or (v_r ->> 'aid')::bigint <> 0 or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_AID') then
    raise exception 'PROOF 19 FAIL: lit, the instant path also paid: %', v_r;
  end if;
  if v_load <> 98000 or exists (select 1 from public.cargo_ship_aboard(v_fl2)) then
    raise exception 'PROOF 19 FAIL: the capital did not load exactly the need onto one ship: % aboard', v_load;
  end if;
  if (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) + public.funds_aboard() <> v_sum then
    raise exception 'PROOF 19 FAIL: the sum of purses and funds aboard moved';
  end if;
  raise notice 'PASS: FUNDS_ONE_PATH — no CROWN_AID, % d. aboard the first ship, % d. aboard in all, purses and funds summed, moved 0', v_load, public.funds_aboard();

  -- ── THE TOTAL, WITH FUNDS AT SEA ──
  if (world.stats_now() ->> 'total')::bigint <> v_tot0 then
    raise exception 'PROOF 19 FAIL: the live world total moved by %', (world.stats_now() ->> 'total')::bigint - v_tot0;
  end if;
  v_r := public.stats_live_fold(now());
  if (v_r #>> '{drift,cities}')::bigint <> 0 or (v_r #>> '{drift,set_aside}')::bigint <> 0 then
    raise exception 'PROOF 19 FAIL: the fold found a drift with funds aboard: %', v_r;
  end if;
  if (world.stats_now() ->> 'total')::bigint <> v_tot0 then
    raise exception 'PROOF 19 FAIL: the fold moved the world total by %', (world.stats_now() ->> 'total')::bigint - v_tot0;
  end if;
  v_now := now() + interval '1 hour';
  v_slot := public.drift_slot_of(v_now);
  perform public.tick_stats(v_now);
  select w.set_aside into v_rows from public.stats_world w where w.slot = v_slot;
  if v_rows <> (select coalesce(sum(c.escrow), 0) from public.trade_contracts c where c.status = 'open') + (select coalesce(sum(s.accrued), 0) from public.city_shares s) + public.funds_aboard() then
    raise exception 'PROOF 19 FAIL: tick_stats did not count the funds aboard: %', v_rows;
  end if;
  raise notice 'PASS: FUNDS_TOTAL — % d. at sea; total unmoved, cities and set_aside drift 0, stats_world.set_aside % d.', public.funds_aboard(), v_rows;

  -- ── ONE REAL LAP ──
  v_want := array(select p.code from public.cargo_circuit_legs l join public.ports p on p.id = l.to_port where l.circuit_id = v_cir order by l.ord);
  v_now := now();
  v_kinds := '{}'::jsonb;
  loop
    v_guard := v_guard + 1;
    exit when v_guard > 400;
    v_step := public.cargo_ship_step(v_fl, v_now);
    exit when v_step = 'HOME';
    if v_step = 'SAILED' then
      select o.id, o.eta into v_voy, v_end from public.voyages o where o.fleet_id = v_fl and o.status = 'SAILING';
      v_seq := v_seq || (select p.code from public.voyages o join public.ports p on p.id = o.dest_port_id where o.id = v_voy);
      if cardinality(v_seq) = v_legs - 1 then
        update public.port_treasury t set ducats = t.ducats + 59000 where t.port_id = v_s2;    -- before her last stop a sale fills it: 49,000 d. must come home
        v_sum := v_sum + 59000;
      end if;
      loop      -- she arrives at her eta, her port time still to run; weather may push the eta on
        perform voyage.settle(v_fl, v_end);
        exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
        v_end := (select o.eta from public.voyages o where o.id = v_voy);
      end loop;
      select v_kinds || coalesce(jsonb_object_agg(x.kind, x.n), '{}'::jsonb) into v_kinds
        from (select e.kind, coalesce((v_kinds ->> e.kind)::int, 0) + count(*) as n from public.voyage_events e where e.voyage_id = v_voy group by 1) x;
      v_now := v_end;
    elsif v_step = 'IN_PORT' then
      v_now := v_now + interval '61 seconds';
    else
      raise exception 'PROOF 19 FAIL: step % on the lap, at %', v_step, v_seq;
    end if;
  end loop;
  if v_step <> 'HOME' or v_seq <> v_want then
    raise exception 'PROOF 19 FAIL: she did not sail the circuit: % % against %', v_step, v_seq, v_want;
  end if;
  if public.treasury_balance(v_s1) <> 50000 or public.treasury_balance(v_s2) <> 60000 then
    raise exception 'PROOF 19 FAIL: the stops were not served: % %', public.treasury_balance(v_s1), public.treasury_balance(v_s2);
  end if;
  if (select coalesce(sum(k.ducats), 0) from public.convoy_cargo k where k.fleet_id = v_fl and k.stage = 'DELIVERED') <> 49000
     or (select coalesce(sum(k.ducats), 0) from public.convoy_cargo k where k.fleet_id = v_fl and k.stage = 'RETURNED') <> 49000
     or exists (select 1 from public.cargo_ship_aboard(v_fl)) then
    raise exception 'PROOF 19 FAIL: the book does not close: %', (select jsonb_agg(to_jsonb(k) - 'fleet_id' - 'player_id') from public.convoy_cargo k where k.fleet_id = v_fl);
  end if;
  if (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) + public.funds_aboard() <> v_sum then
    raise exception 'PROOF 19 FAIL: the lap moved the sum of purses and funds aboard';
  end if;
  raise notice 'PASS: FUNDS_LAP — % stops of %, in order; 49,000 d. delivered, 49,000 d. home; purses and funds summed, moved 0; the sea gave %', cardinality(v_seq), cardinality(v_want), v_kinds;

  if exists (select 1 from public.port_fee_debts d where d.player_id = v_pl)
     or coalesce((select w.owed from public.fleet_wages w where w.fleet_id = v_fl), 0) <> 0
     or exists (select 1 from public.ledger l where l.player_id = v_pl)
     or (select p.ducats from public.players p where p.id = v_pl) <> 0
     or (v_kinds ? 'FORCED_HOME')
     or exists (select 1 from public.ships s where s.fleet_id = v_fl and (s.crew <> 0 or s.durability <> (select b.durability from public.ship_base(s.id) b))) then
    raise exception 'PROOF 19 FAIL: the lap left something owing or broken: %', jsonb_build_object('debts', (select count(*) from public.port_fee_debts d where d.player_id = v_pl), 'kinds', v_kinds);
  end if;
  raise notice 'PASS: FUNDS_NO_DEBT — no debt, wage, ledger row or forced home; hull whole at home';

  -- ── A RAID ON A CREWLESS HULL. Weather is by the voyage's own roll, so the fight is asked for by name, weak and strong ──
  perform public.cargo_ship_step(v_fl2, now());   -- she holds no load: idle at home
  select l.* into r from public.cargo_circuit_legs l where l.circuit_id = v_cir order by l.nm desc limit 1;
  v_voy := voyage.depart(v_fl2, r.segments, null, r.to_port, now());
  v_n := 0;
  for v_step in select x from unnest(array['10', '100', '1000', '100000']) x loop
    v_r := voyage.fight(v_voy, 1, v_fl2, v_step::numeric);
    if v_r is null or v_r ->> 'outcome' is null then
      raise exception 'PROOF 19 FAIL: no fight at raider %: %', v_step, v_r;
    end if;
    v_n := v_n + 1;
  end loop;
  v_r := voyage.raid_takes(v_voy, 1, v_fl2, 'STRIPPED');
  perform public.insurance_claim(v_voy, 1, v_r, 'STRIPPED');
  if v_r is distinct from '{}'::jsonb and exists (select 1 from jsonb_object_keys(v_r)) then
    raise exception 'PROOF 19 FAIL: raiders took something from an empty hold: %', v_r;
  end if;
  raise notice 'PASS: FUNDS_RAID — % fights and a stripping of a crewless hull, no error, nothing taken', v_n;

  -- ── A WRECK, THROUGH THE REAL ARRIVAL ──
  update public.ships s set durability = 0 where s.fleet_id = v_fl2;
  v_end := (select o.eta from public.voyages o where o.id = v_voy);
  loop
    perform voyage.settle(v_fl2, v_end);
    exit when (select f.status from public.fleets f where f.id = v_fl2) <> 'SAILING';
    v_end := (select o.eta from public.voyages o where o.id = v_voy);
  end loop;
  if (select f.status from public.fleets f where f.id = v_fl2) <> 'UNABLE_TO_SAIL' then
    raise exception 'PROOF 19 FAIL: a hull at 0 did not dock unable: %', (select f.status from public.fleets f where f.id = v_fl2);
  end if;
  update public.cargo_ships c set circuit_id = v_cir, leg = (select l.ord from public.cargo_circuit_legs l where l.circuit_id = v_cir and l.to_port = (select f.port_id from public.fleets f where f.id = v_fl2)),
         out_load = (select k.id from public.convoy_cargo k where k.fleet_id = v_fl and k.stage = 'LOADED' order by k.id desc limit 1)
   where c.fleet_id = v_fl2;
  v_step := public.cargo_ship_step(v_fl2, v_end);
  if (select f.status from public.fleets f where f.id = v_fl2) <> 'DOCKED'
     or exists (select 1 from public.ships s where s.fleet_id = v_fl2 and s.durability <> (select b.durability from public.ship_base(s.id) b)) then
    raise exception 'PROOF 19 FAIL: a wreck was not patched: %', v_step;
  end if;
  if (select f.port_id from public.fleets f where f.id = v_fl2) = v_cap then
    if v_step <> 'HOME' then
      raise exception 'PROOF 19 FAIL: a wreck at home: %', v_step;
    end if;
  else
    if v_step <> 'IN_PORT' then
      raise exception 'PROOF 19 FAIL: a wreck did not wait: %', v_step;
    end if;
    if public.cargo_ship_step(v_fl2, v_end + make_interval(secs => public.wc_num('convoy_wreck_seconds') + 1)) <> 'SAILED' then
      raise exception 'PROOF 19 FAIL: a wreck did not sail on after the wait';
    end if;
  end if;
  raise notice 'PASS: FUNDS_WRECK — docked UNABLE_TO_SAIL, % , patched', v_step;

  -- ── HER HISTORY ──
  if not exists (select 1 from public.voyages o where o.fleet_id = v_fl) or not exists (select 1 from public.events e where e.player_id = v_pl) then
    raise exception 'PROOF 19 FAIL: nothing to compact';
  end if;
  perform public.npc_compact_houses(array[v_pl], v_now + interval '7 hours');
  if exists (select 1 from public.voyages o where o.fleet_id = v_fl) or exists (select 1 from public.events e where e.player_id = v_pl) then
    raise exception 'PROOF 19 FAIL: her voyages or reports were kept: %, %', (select jsonb_agg(jsonb_build_object('s', o.status, 'eta', o.eta)) from public.voyages o where o.fleet_id = v_fl),
      (select jsonb_agg(jsonb_build_object('k', e.kind, 'at', e.created_at)) from (select * from public.events e where e.player_id = v_pl limit 4) e);
  end if;
  raise notice 'PASS: FUNDS_COMPACTED — her ended voyages and reports are gone after the merchants'' retention; the book stands';
end
$$;
