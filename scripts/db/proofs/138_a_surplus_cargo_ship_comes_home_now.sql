-- ═════════════════════════════════════════════════════════════════════════════
-- PROOF 138 - A SURPLUS CARGO SHIP COMES HOME NOW  (migration 0437; docs/dev-log/2026-11-15-cargo-home.md; the owner, 2026-11-15: "there are
--   still cargo ships that have 0 gold. if they are returning after they provided transport, instead of 0 gold, say it is returning." and "you
--   still haven't reduce the numbers right")
--
--   On the world's own flags and the REAL job (public.tick_cargo_ships: settle, retire, steps), load, voyage engine and retire; the sea stubbed
--   quiet; every scene rolled back. The economy is closed and the purses lit, as on prod. EVERY MARKER FAILS ON THE RULES BEFORE 0437: a surplus
--   ship with gold aboard sailed on to the next city of her circuit (SAILED), an idle surplus ship at a home that is no origin sailed off to a new
--   home, the card listed the circuit of a ship going home and had no `state`, and the Stats count counted the laid-up rows.
--
-- @pass CH_INSHARE  a ship inside her share with gold aboard, at a city that needs nothing, sails on to the next city of her circuit (as before)
-- @pass CH_RECALL   her share cut under her while she is at sea: at the next city (which needs nothing) the job's step answers RECALLED and she sails ONE leg straight home with all her gold; her card says LOADED, shows the gold and lists no circuit ahead
-- @pass CH_RETIRE   home, the job closes her lap (HOME: the gold RETURNED to her home, where it was loaded) and the next run lays her up (retired 1, LAID_UP); no gold moved from start to end
-- @pass CH_IDLE     an idle surplus ship at a home that is no origin waits (IDLE, docked) instead of sailing to a new home, and the job's next run lays her up
-- @pass CH_STATE    the one word: an empty ship docked away is RETURNING, docked at home HOME, laid up LAID_UP, with gold LOADED, the same on her card and her Stats page
-- @pass CH_COUNT    the Stats count and the Cargo list count and list only the cargo ships in service; a laid-up one is not in the list
-- ═════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_nat   uuid;
  v_cap   uuid;
  v_stop  uuid;
  v_stop2 uuid;
  v_fl    uuid;
  v_f13   uuid;
  v_f12   uuid;
  v_n     int;
  v_r     jsonb;
  v_s     text;
  v_w     bigint;
  v_load  bigint;
  v_card  jsonb;
  v_now   timestamptz := now();
  v_guard int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'npc_traders_enabled', 'standing_routes_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('npc_refits_enabled', 'convoy_rich_enabled', 'attack_enabled', 'pirates_bite');
  update public.world_config set value = to_jsonb(1) where key = 'convoy_idle_every';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;

  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_138;
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
create function pg_temp.dest(p_fleet uuid)
returns uuid
language sql
as $b$
  select o.dest_port_id from public.voyages o where o.fleet_id = p_fleet and o.status = 'SAILING'
$b$
  $f$;

  select id into v_nat from public.nations where code = 'PRT';
  v_cap := public.realm_capital(v_nat);

  -- Portugal at 14 ships (the settle held off for two hours, so the job keeps the numbers this proof writes)
  update public.cargo_fleet_sizes s set ships = 1, read_at = v_now + interval '2 hours';
  update public.cargo_fleet_sizes s set ships = 14 where s.nation_id = v_nat;
  update public.port_treasury t set ducats = 100000000, reserve = 0 where t.port_id = v_cap;
  v_guard := 0;
  while (select count(*) from public.cargo_ships c where c.nation_id = v_nat) < 14 loop
    perform public.tick_cargo_ships(v_now, v_nat);
    v_guard := v_guard + 1;
    if v_guard > 4 then
      raise exception 'PROOF 138 FAIL: Portugal''s 14 ships were not made';
    end if;
  end loop;
  v_stop := (select l.to_port from public.cargo_circuit_legs l join public.cargo_circuits k on k.id = l.circuit_id where k.nation_id = v_nat order by k.id desc, l.ord limit 1);
  v_stop2 := (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(v_nat, v_cap) and l.ord = 2);
  if v_stop2 is null or v_stop2 = v_cap then
    raise exception 'PROOF 138 FAIL: Portugal''s circuit has no second city';
  end if;
  v_fl := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 14);
  v_f13 := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 13);
  v_f12 := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 12);

  -- ord 14 loads (the others held aside so she is the one) and sails her circuit
  update public.cargo_ships c set laid_up_at = v_now where c.nation_id = v_nat and c.ord <= 13;
  v_r := public.cargo_ships_load(jsonb_build_array(jsonb_build_object('port_id', v_stop, 'target', public.treasury_balance(v_stop) + 5000, 'cap', v_cap)));
  update public.cargo_ships c set laid_up_at = null where c.nation_id = v_nat and c.ord <= 13;
  v_load := (select a.aboard from public.cargo_ship_aboard(v_fl) a);
  if v_load is null or public.cargo_ship_step(v_fl, v_now) <> 'SAILED' then
    raise exception 'PROOF 138 FAIL: ord 14 did not load and sail: %', v_r;
  end if;

  -- ── CH_INSHARE ── the first city needs nothing; inside her share she sails on
  update public.port_treasury t set ducats = 1000000000000 where t.port_id in (v_stop, v_stop2);
  v_w := pg_temp.w();
  perform pg_temp.arrive(v_fl);
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r #>> '{steps,SAILED}')::int is distinct from 1 or pg_temp.dest(v_fl) is distinct from v_stop2
     or (select a.aboard from public.cargo_ship_aboard(v_fl) a) is distinct from v_load then
    raise exception 'PROOF 138 FAIL: inside her share with gold she did not sail on to the next city: %', v_r;
  end if;
  raise notice 'PASS: CH_INSHARE — ord 14 (share 14) at % with %, the city needing nothing: on to % (%)', (select p.code from public.ports p where p.id = v_stop), v_load,
    (select p.code from public.ports p where p.id = v_stop2), v_r -> 'steps';

  -- ── CH_RECALL ── the share is cut under her while she is at sea
  update public.cargo_fleet_sizes s set ships = 13 where s.nation_id = v_nat;
  perform pg_temp.arrive(v_fl);
  v_r := public.tick_cargo_ships(v_now, v_nat);
  v_card := world.cargo_ship_card(v_fl);
  if (v_r #>> '{steps,RECALLED}')::int is distinct from 1 or pg_temp.dest(v_fl) is distinct from v_cap
     or (select a.aboard from public.cargo_ship_aboard(v_fl) a) is distinct from v_load
     or v_card ->> 'state' <> 'LOADED' or (v_card ->> 'funds')::bigint <> v_load or jsonb_array_length(v_card -> 'next') <> 0 or (v_card ->> 'stops_left')::int <> 0
     or world.stats_fleet(v_fl) #>> '{cargo,state}' <> 'LOADED' then
    raise exception 'PROOF 138 FAIL: over her share at % she did not sail straight home with her gold: %; card %', (select p.code from public.ports p where p.id = v_stop2), v_r, v_card - 'ships';
  end if;
  raise notice 'PASS: CH_RECALL — share cut to 13 at sea; at % the job answered %, she sails to % with all % aboard; her card: LOADED, % on it, no circuit ahead',
    (select p.code from public.ports p where p.id = v_stop2), v_r -> 'steps', (select p.code from public.ports p where p.id = v_cap), v_load, v_card ->> 'funds';

  -- ── CH_RETIRE ── home: HOME, the gold returned there; the next run lays her up
  perform pg_temp.arrive(v_fl);
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r #>> '{steps,HOME}')::int is distinct from 1 or exists (select 1 from public.cargo_ship_aboard(v_fl))
     or not exists (select 1 from public.convoy_cargo b where b.fleet_id = v_fl and b.stage = 'RETURNED' and b.port_id = v_cap and b.ducats = v_load)
     or public.cargo_ship_state(v_fl) <> 'HOME' then
    raise exception 'PROOF 138 FAIL: home, she did not close her lap and return her gold: %', v_r;
  end if;
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r ->> 'retired')::int <> 1 or (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_fl) is null then
    raise exception 'PROOF 138 FAIL: the next run did not lay her up: %', v_r;
  end if;
  if pg_temp.w() <> v_w then
    raise exception 'PROOF 138 FAIL: the recall moved gold: % -> %', v_w, pg_temp.w();
  end if;
  raise notice 'PASS: CH_RETIRE — home: HOME, % RETURNED at %; the next run retired 1; no gold moved', v_load, (select p.code from public.ports p where p.id = v_cap);

  -- ── CH_IDLE ── ord 13 over a share of 12, idle at a home that is no origin (the first city)
  update public.cargo_fleet_sizes s set ships = 12 where s.nation_id = v_nat;
  update public.cargo_ships c set home_port_id = v_stop, based_at = null where c.fleet_id = v_f13;
  update public.fleets f set port_id = v_stop, ready_at = null where f.id = v_f13;
  v_s := public.cargo_ship_step(v_f13, v_now);
  if v_s <> 'IDLE' or (select f.status from public.fleets f where f.id = v_f13) <> 'DOCKED' then
    raise exception 'PROOF 138 FAIL: an idle surplus ship at a home that is no origin answered % (she must wait for the retire)', v_s;
  end if;
  v_r := public.tick_cargo_ships(v_now, v_nat);
  if (v_r ->> 'retired')::int <> 1 or (select c.laid_up_at from public.cargo_ships c where c.fleet_id = v_f13) is null then
    raise exception 'PROOF 138 FAIL: the idle surplus ship was not laid up: %', v_r;
  end if;
  raise notice 'PASS: CH_IDLE — ord 13 idle at % (no origin): %, then laid up by the job (%)', (select p.code from public.ports p where p.id = v_stop), v_s, v_r ->> 'retired';

  -- ── CH_STATE ── the one word, on the card and the page
  update public.fleets f set port_id = v_stop where f.id = v_f12;   -- empty, docked away from her home
  if public.cargo_ship_state(v_f12) <> 'RETURNING' or world.cargo_ship_card(v_f12) ->> 'state' <> 'RETURNING' or world.stats_fleet(v_f12) #>> '{cargo,state}' <> 'RETURNING'
     or (world.cargo_ship_card(v_f12) ->> 'funds')::bigint <> 0 then
    raise exception 'PROOF 138 FAIL: an empty ship away is not RETURNING: %', world.cargo_ship_card(v_f12) - 'ships';
  end if;
  update public.fleets f set port_id = v_cap where f.id = v_f12;
  if public.cargo_ship_state(v_f12) <> 'HOME' or world.cargo_ship_card(v_f12) ->> 'state' <> 'HOME' or world.stats_fleet(v_f12) #>> '{cargo,state}' <> 'HOME'
     or public.cargo_ship_state(v_fl) <> 'LAID_UP' or world.cargo_ship_card(v_fl) ->> 'state' <> 'LAID_UP' or world.stats_fleet(v_fl) #>> '{cargo,state}' <> 'LAID_UP' then
    raise exception 'PROOF 138 FAIL: HOME or LAID_UP: % / %', public.cargo_ship_state(v_f12), public.cargo_ship_state(v_fl);
  end if;
  raise notice 'PASS: CH_STATE — empty away RETURNING, at home HOME, laid up LAID_UP, with gold LOADED (CH_RECALL); card and page agree';

  -- ── CH_COUNT ── the Stats count and the Cargo list: in service only
  v_r := public.stats_fleets_count(v_now - interval '1 hour', v_now);
  if (v_r #>> '{cargo,fleets}')::int <> (select count(*) from public.cargo_ships c where c.laid_up_at is null) or (v_r #>> '{cargo,laid_up}')::int <> 0
     or (select count(*) from public.cargo_ships c where c.laid_up_at is not null) < 2 then
    raise exception 'PROOF 138 FAIL: the Stats count: %', v_r -> 'cargo';
  end if;
  v_r := public.stats_fleet_list_rows('CARGO', v_now);
  if (v_r ->> 'fleets')::int <> (select count(*) from public.cargo_ships c where c.laid_up_at is null)
     or exists (select 1 from jsonb_array_elements(v_r -> 'list') e where (e ->> 'id')::uuid in (v_fl, v_f13)) then
    raise exception 'PROOF 138 FAIL: the Cargo list still lists a laid-up ship: %', v_r - 'list';
  end if;
  raise notice 'PASS: CH_COUNT — % cargo ships in service counted and listed, % laid up left out', v_r ->> 'fleets', (select count(*) from public.cargo_ships c where c.laid_up_at is not null);

  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_stub_138;
  alter function voyage.hazard_roll_real_138(uuid, integer) rename to hazard_roll;
end
$$;
