-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 18 — CARGO SHIPS EXIST  (migration 0308)
--
--   0308's own self-assert commissions probe ships on a probe nation and never sails them (a migration never runs a real game step, docs/OPS_HEALTH.md section 4).
--   This proof lights the switch over the WHOLE world, sails a real cargo ship through the REAL voyage engine, and reads the map. It is why V1 can say how she will live.
--
-- @pass CARGO_DARK_NOTHING  dark, the commission makes nothing for a real great power
-- @pass CARGO_ALL_POWERS    lit, every great power with a harbour capital gets the knob's count, and no purse in the world moves
-- @pass CARGO_NOT_MERCHANT  no merchant roster and no map read names her
-- @pass CARGO_SAILS         she departs with voyage.depart and docks with voyage.settle: no wage, no stores, no forced home, no purse moved but the dock fee she owes
-- @pass CARGO_COMPACTED     her ended voyage is compacted with the merchants', so her history does not grow
-- @pass CARGO_KNOWN_LEAK    world.sea_traffic's `total` counts her, the one read V4 must close before she is lit on prod
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_nat    uuid;
  v_cap    uuid;
  v_capc   text;
  v_city   uuid;
  v_cityc  text;
  v_course jsonb;
  v_fl     uuid;
  v_pl     uuid;
  v_voy    uuid;
  v_sum    bigint;
  v_n      int;
  v_want   int;
  v_made   int := 0;
  v_tot0   int;
  v_tot1   int;
  v_map    jsonb;
  v_speed  numeric;
  v_eta    timestamptz;
  r        record;
  f        public.fleets%rowtype;
  v_fee    bigint;
  v_wages  bigint;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;

  select g.nation_id, p.id, p.code into v_nat, v_cap, v_capc
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code = 'PRT';
  if v_nat is null then
    raise exception 'PROOF 18 FAIL: Portugal has no harbour capital in this world';
  end if;

  -- dark
  if public.cargo_ships_commission(v_nat) <> 0 or exists (select 1 from public.cargo_ships) then
    raise exception 'PROOF 18 FAIL: dark, a cargo ship was made';
  end if;
  raise notice 'PASS: CARGO_DARK_NOTHING — Portugal, dark: 0 made';

  v_tot0 := (world.sea_traffic(null) ->> 'total')::int;
  v_sum := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t);

  -- lit: every great power with a harbour capital
  update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
  v_want := public.wc_int('convoy_ships_per_nation');
  for r in select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id
             join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' order by n.code loop
    v_n := public.cargo_ships_commission(r.nation_id);
    if v_n <> v_want then
      raise exception 'PROOF 18 FAIL: nation % got % ships, not %', r.nation_id, v_n, v_want;
    end if;
    v_made := v_made + v_n;
  end loop;
  if v_made < 10 * v_want or (select count(*) from public.cargo_ships) <> v_made
     or (select count(*) from public.cargo_ships c where public.fleet_kind(c.fleet_id) = 'CARGO_SHIP') <> v_made then
    raise exception 'PROOF 18 FAIL: % made', v_made;
  end if;
  if (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) <> v_sum then
    raise exception 'PROOF 18 FAIL: a commission moved a purse';
  end if;
  raise notice 'PASS: CARGO_ALL_POWERS — % cargo ships at % a realm, every purse summed, moved 0', v_made, v_want;

  -- no merchant read names her
  select c.fleet_id, c.player_id into v_fl, v_pl from public.cargo_ships c where c.nation_id = v_nat and c.ord = 1;
  if exists (select 1 from public.npc_tend_roster() x join public.cargo_ships c on c.fleet_id = x.fleet_id)
     or exists (select 1 from public.npc_invest_roster(null) x join public.cargo_ships c on c.player_id = x.player_id)
     or exists (select 1 from public.capital_gift_roster(now(), null) x join public.cargo_ships c on c.player_id = x.player_id)
     or exists (select 1 from public.capital_gift_roster(now(), v_pl))
     or exists (select 1 from public.lap_starts_due() x join public.cargo_ships c on c.fleet_id = x.fleet_id) then
    raise exception 'PROOF 18 FAIL: a merchant roster names a cargo ship';
  end if;
  v_map := jsonb_build_object('traffic', world.sea_traffic(null), 'roster', world.sea_roster(null), 'quay', world.port_merchants(v_cap));
  if exists (select 1 from public.cargo_ships c where position(c.fleet_id::text in v_map::text) > 0) then
    raise exception 'PROOF 18 FAIL: a map read names a cargo ship';
  end if;
  if exists (select 1 from public.cargo_ships c where position(c.player_id::text in world.stats_merchants('1w')::text) > 0) then
    raise exception 'PROOF 18 FAIL: the merchants'' stats name a cargo ship';
  end if;
  raise notice 'PASS: CARGO_NOT_MERCHANT — tend, invest, gifts, laps, sea traffic, sea roster, quay and merchant stats read none of % ships', v_made;

  -- she sails: the nearest harbour of her realm the fixture holds a course to
  select p.id, p.code, proof.course(v_capc, p.code) into v_city, v_cityc, v_course
    from public.ports p
   where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap and proof.course(v_capc, p.code) is not null
   order by voyage.gc_distance_nm((select lat from public.ports where id = v_cap)::double precision, (select lon from public.ports where id = v_cap)::double precision,
                                  p.lat::double precision, p.lon::double precision), p.code
   limit 1;
  if v_city is null then
    raise exception 'PROOF 18 FAIL: no course from % to a harbour of its realm', v_capc;
  end if;
  v_speed := voyage.fleet_speed(v_fl);
  v_voy := voyage.depart(v_fl, voyage.segments_from_course(v_course), v_cap, v_city, now() - interval '30 days');
  if (select status from public.fleets where id = v_fl) <> 'SAILING' then
    raise exception 'PROOF 18 FAIL: she did not depart';
  end if;
  v_n := voyage.settle(v_fl, now());
  select * into f from public.fleets where id = v_fl;
  v_eta := (select eta from public.voyages where id = v_voy);
  if f.status <> 'DOCKED' or f.port_id <> v_city or (select status from public.voyages where id = v_voy) <> 'ARRIVED' then
    raise exception 'PROOF 18 FAIL: she did not dock at %: % %', v_cityc, f.status, f.port_id;
  end if;
  if exists (select 1 from public.voyage_events e where e.voyage_id = v_voy and e.kind = 'FORCED_HOME')
     or exists (select 1 from public.voyage_events e where e.voyage_id = v_voy and coalesce((e.payload ->> 'wages')::numeric, 0) <> 0) then
    raise exception 'PROOF 18 FAIL: she was forced home or charged a wage: %',
      (select jsonb_agg(e.kind) from public.voyage_events e where e.voyage_id = v_voy);
  end if;
  if (select s.crew from public.ships s where s.fleet_id = v_fl) <> 0 or (select p.ducats from public.players p where p.id = v_pl) <> 0
     or exists (select 1 from public.ledger l where l.player_id = v_pl) then
    raise exception 'PROOF 18 FAIL: she gained a crew, a purse or a ledger row';
  end if;
  v_fee := coalesce((select sum(d.ducats) from public.port_fee_debts d where d.player_id = v_pl), 0);
  v_wages := coalesce((select w.owed from public.fleet_wages w where w.fleet_id = v_fl), 0);
  if v_wages <> 0 then
    raise exception 'PROOF 18 FAIL: she owes wages: %', v_wages;
  end if;
  if v_fee <= 0 then
    raise exception 'PROOF 18 FAIL: the known dock fee was not owed: the dev-log says V2 must meet it';
  end if;
  raise notice 'PASS: CARGO_SAILS — % to %, % nm, at speed % (% nm a real minute), % days settled, docked; no wage, no stores, no forced home; she owes the harbour % d. dock fee and V2 must meet it',
    v_capc, v_cityc, round((select total_nm from public.voyages where id = v_voy)), v_speed, round(v_speed * public.wc_num('time_compression') / 60), v_n, v_fee;

  -- her history goes with the merchants'
  if not exists (select 1 from public.voyage_events e where e.voyage_id = v_voy) then
    raise exception 'PROOF 18 FAIL: no voyage events to compact';
  end if;
  perform public.npc_compact_houses(array[v_pl], v_eta + interval '7 hours');
  if exists (select 1 from public.voyages v where v.id = v_voy) or exists (select 1 from public.voyage_events e where e.voyage_id = v_voy) then
    raise exception 'PROOF 18 FAIL: her ended voyage was not compacted';
  end if;
  raise notice 'PASS: CARGO_COMPACTED — her ended voyage and its events are gone after the merchants'' retention';

  -- the known leak, named so V4 cannot miss it
  v_tot1 := (world.sea_traffic(null) ->> 'total')::int;
  if v_tot1 - v_tot0 <> v_made then
    raise exception 'PROOF 18 FAIL: sea_traffic total moved by %, not by the % ships: the dev-log is out of date', v_tot1 - v_tot0, v_made;
  end if;
  raise notice 'PASS: CARGO_KNOWN_LEAK — sea_traffic total is % over its rows: V4 serves her kind and closes this before any ship is lit', v_made;
end
$$;
