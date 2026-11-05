-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 20 — CARGO SHIPS YOU CAN SEE  (migration 0310)
--
--   0310's own self-assert moves one probe ship on three probe harbours. This proof lights the switch over the WHOLE world and reads the map, the hall and Stats while a real ship of a real
--   realm sails a real leg through voyage.depart and voyage.settle, then folds the real count.
--
-- @pass SEEN_MERCHANTS  every merchant row of world.sea_roster is the row it was before any ship existed: no key, no order, no value moved
-- @pass SEEN_ROSTER     every cargo ship is a row of world.sea_roster with her kind, one hull and the ink of her nation's merchants
-- @pass SEEN_TOTAL      world.sea_traffic counts her and serves her, and its total less its rows is its omitted, world view and window alike
-- @pass SEEN_CARD       her card says where she is bound, the funds aboard and the next stops, and answers for no other fleet
-- @pass SEEN_HALL       the hall of her next stop serves what she will pay, the stop after waits its turn, a city not short and a capital are told nothing, and the switch off stops it
-- @pass SEEN_FIGURES    world.stats_now serves the funds at sea, a part of set_aside and not a new sum
-- @pass SEEN_COUNT      she is at sea and no merchant: the journal and the real fold agree, drift 0
-- @pass SEEN_DELTA      when she docks a roster delta carries it, with no route to re-date
-- ══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_nat   uuid;
  v_cap   uuid;
  v_cir   bigint;
  v_s1    uuid;
  v_s2    uuid;
  v_s3    uuid;
  v_fl    uuid;
  v_voy   uuid;
  v_end   timestamptz;
  v_r0    jsonb;
  v_r     jsonb;
  v_c     jsonb;
  v_n     int;
  v_ink   text;
  v_load  bigint;
  v_aside bigint;
  v_sea   bigint;
  v_merch bigint;
  v_view  jsonb := '{"south": 30, "north": 45, "west": -20, "east": 0}'::jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled');
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;

  select g.nation_id, p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code = 'PRT';

  v_r0 := world.sea_roster(null) -> 'fleets';
  if jsonb_array_length(v_r0) = 0 then
    raise exception 'PROOF 20 FAIL: this world has no merchants to compare';
  end if;

  update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
  for v_n in 1 .. 12 loop
    perform public.tick_cargo_ships();
  end loop;
  select k.id into v_cir from public.cargo_circuits k where k.nation_id = v_nat;
  v_s1 := (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = v_cir and l.ord = 1);
  v_s2 := (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = v_cir and l.ord = 2);
  v_s3 := (select l.to_port from public.cargo_circuit_legs l where l.circuit_id = v_cir and l.ord = 3);
  v_fl := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 1);
  update public.port_treasury t set ducats = 50000, reserve = 0 where public.city_capital(t.port_id) = v_cap;
  update public.port_treasury t set ducats = 10000000 where t.port_id = v_cap;
  update public.port_treasury t set ducats = 1000 where t.port_id in (v_s1, v_s2);
  perform public.stats_live_fold(now());

  -- ── THE MERCHANTS DID NOT MOVE ──
  v_r := world.sea_roster(null) -> 'fleets';
  if (select jsonb_agg(e order by i) from jsonb_array_elements(v_r) with ordinality t(e, i) where not e ? 'kind') is distinct from v_r0 then
    raise exception 'PROOF 20 FAIL: a merchant row moved once ships existed';
  end if;
  raise notice 'PASS: SEEN_MERCHANTS — % merchant rows, the array they were', jsonb_array_length(v_r0);

  -- ── THE ROSTER ──
  v_n := (select count(*) from jsonb_array_elements(v_r) e where e ->> 'kind' = 'CARGO_SHIP');
  if v_n <> (select count(*) from public.cargo_ships) or v_n <> jsonb_array_length(v_r) - jsonb_array_length(v_r0) or v_n < 50 then
    raise exception 'PROOF 20 FAIL: % cargo rows of % ships', v_n, (select count(*) from public.cargo_ships);
  end if;
  if exists (select 1 from jsonb_array_elements(v_r) e join public.cargo_ships c on c.fleet_id = (e ->> 'id')::uuid
              where jsonb_array_length(e -> 'hulls') <> 1 or e ->> 'ink' is distinct from
                    (select h.ink from public.npc_houses h join public.players o on o.id = h.player_id where o.nation_id = c.nation_id group by 1 order by count(*) desc limit 1)) then
    raise exception 'PROOF 20 FAIL: a cargo row has the wrong hull count or ink';
  end if;
  v_ink := (select e ->> 'ink' from jsonb_array_elements(v_r) e where e ->> 'id' = v_fl::text);
  raise notice 'PASS: SEEN_ROSTER — % ships with kind, one hull each, nation ink (Portugal: %)', v_n, v_ink;

  -- ── THE LOAD, AND SHE SAILS ──
  v_r := public.crown_aid(v_cap);
  v_load := (select a.aboard from public.cargo_ship_aboard(v_fl) a);
  if v_load <> 98000 then
    raise exception 'PROOF 20 FAIL: % aboard: %', v_load, v_r;
  end if;
  if public.cargo_ship_step(v_fl, now()) <> 'SAILED' then
    raise exception 'PROOF 20 FAIL: she did not sail';
  end if;
  select o.id, o.eta into v_voy, v_end from public.voyages o where o.fleet_id = v_fl and o.status = 'SAILING';

  -- ── THE TOTAL ──
  v_r := world.sea_traffic(null);
  if (v_r ->> 'total')::int <> (select count(*) from public.fleets f join public.players p on p.id = f.player_id and p.is_npc)
     or (v_r ->> 'total')::int - jsonb_array_length(v_r -> 'fleets') <> (v_r ->> 'omitted')::int then
    raise exception 'PROOF 20 FAIL: the world view is not honest: total %, rows %, omitted %', v_r ->> 'total', jsonb_array_length(v_r -> 'fleets'), v_r ->> 'omitted';
  end if;
  v_r := world.sea_traffic(jsonb_build_object('south', (world.sea_roster(now()) #>> '{fleets,0,voyage,course,0,0}')::float8 - 3, 'north', (world.sea_roster(now()) #>> '{fleets,0,voyage,course,0,0}')::float8 + 3,
                                              'west', (world.sea_roster(now()) #>> '{fleets,0,voyage,course,0,1}')::float8 - 3, 'east', (world.sea_roster(now()) #>> '{fleets,0,voyage,course,0,1}')::float8 + 3));
  if not exists (select 1 from jsonb_array_elements(v_r -> 'fleets') e where e ->> 'id' = v_fl::text and e ->> 'kind' = 'CARGO_SHIP')
     or (v_r ->> 'total')::int - jsonb_array_length(v_r -> 'fleets') <> (v_r ->> 'omitted')::int then
    raise exception 'PROOF 20 FAIL: a window round her does not serve her, or is not honest';
  end if;
  raise notice 'PASS: SEEN_TOTAL — total %, a window round her serves her with her kind, total less rows is omitted', v_r ->> 'total';

  -- ── THE CARD ──
  v_c := world.cargo_ship_card(v_fl);
  if (v_c ->> 'funds')::bigint <> v_load or v_c ->> 'to' is distinct from (select p.code from public.ports p where p.id = v_s1)
     or v_c #>> '{next,0}' is distinct from (select p.code from public.ports p where p.id = v_s2)
     or (v_c ->> 'stops_left')::int <> (select count(*) from public.cargo_circuit_legs l where l.circuit_id = v_cir) - 1
     or jsonb_array_length(v_c -> 'next') > 5 or v_c #>> '{fleet,status}' <> 'SAILING' or v_c ->> 'eta' is null then
    raise exception 'PROOF 20 FAIL: the card: %', v_c - 'ships';
  end if;
  begin
    perform world.cargo_ship_card((v_r0 -> 0 ->> 'id')::uuid);
    raise exception 'PROOF 20 FAIL: the card answered for a merchant';
  exception when others then
    if position('E_NOT_FOUND' in sqlerrm) = 0 then
      raise;
    end if;
  end;
  raise notice 'PASS: SEEN_CARD — % d. to %, then %, % stops left; a merchant is refused', v_c ->> 'funds', v_c ->> 'to', v_c -> 'next', v_c ->> 'stops_left';

  -- ── THE HALL ──
  v_r := world.town_hall(v_s1) -> 'funds_on_way';
  if (v_r ->> 'ducats')::bigint <> 49000 or (v_r ->> 'stops')::int <> 0 or v_r ->> 'eta' is null then
    raise exception 'PROOF 20 FAIL: her next stop: %', v_r;
  end if;
  v_r := world.town_hall(v_s2) -> 'funds_on_way';
  if (v_r ->> 'ducats')::bigint <> 49000 or (v_r ->> 'stops')::int <> 1 or v_r ->> 'eta' is not null then
    raise exception 'PROOF 20 FAIL: the stop after: %', v_r;
  end if;
  if world.town_hall(v_s3) ? 'funds_on_way' or world.town_hall(v_cap) ? 'funds_on_way' then
    raise exception 'PROOF 20 FAIL: a city not short, or the capital, was told of funds';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'convoys_enabled';
  if world.town_hall(v_s1) ? 'funds_on_way' then
    raise exception 'PROOF 20 FAIL: the switch is off and she pays nobody, yet the hall says funds are coming';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
  raise notice 'PASS: SEEN_HALL — next stop 49,000 d., the stop after waits; a city not short, the capital and the switch off say nothing';

  -- ── STATS ──
  v_r := world.stats_now();
  if (v_r ->> 'funds_at_sea')::bigint <> public.funds_aboard() or (v_r ->> 'funds_at_sea')::bigint < v_load or (v_r ->> 'cargo_ships')::int <> (select count(*) from public.cargo_ships)
     or (v_r ->> 'set_aside')::bigint < (v_r ->> 'funds_at_sea')::bigint then
    raise exception 'PROOF 20 FAIL: the figures: %', v_r;
  end if;
  raise notice 'PASS: SEEN_FIGURES — % d. at sea, of % d. set aside, % ships', v_r ->> 'funds_at_sea', v_r ->> 'set_aside', v_r ->> 'cargo_ships';

  -- ── THE COUNT ──
  v_sea := (v_r ->> 'at_sea')::bigint;
  v_merch := (v_r ->> 'at_sea_merchants')::bigint;
  if v_sea <> (select count(*) from public.fleets f where f.status = 'SAILING')
     or v_merch <> (select count(*) from public.fleets f join public.players p on p.id = f.player_id where f.status = 'SAILING' and p.is_npc) - 1 then
    raise exception 'PROOF 20 FAIL: the live count: at sea %, merchants %', v_sea, v_merch;
  end if;
  v_r := public.stats_live_fold(now());
  if (v_r #>> '{drift,at_sea}')::bigint <> 0 or (v_r #>> '{drift,at_sea_merchants}')::bigint <> 0 or (v_r #>> '{drift,set_aside}')::bigint <> 0 then
    raise exception 'PROOF 20 FAIL: the fold found a drift: %', v_r;
  end if;
  raise notice 'PASS: SEEN_COUNT — % at sea, % of them merchants, she is the difference; the fold has no drift', v_sea, v_merch;

  -- ── SHE DOCKS ──
  loop
    perform voyage.settle(v_fl, v_end);
    exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
    v_end := (select o.eta from public.voyages o where o.id = v_voy);
  end loop;
  update public.voyages set departed_at = now() - interval '2 hours', eta = now() - interval '5 seconds' where id = v_voy;   -- the proof's clock stands at now(): her arrival is put just behind it
  v_r := world.sea_roster(now() - interval '30 seconds');
  if not exists (select 1 from jsonb_array_elements(v_r -> 'fleets') e where e ->> 'id' = v_fl::text and e ->> 'status' = 'DOCKED' and e -> 'voyage' = 'null'::jsonb) then
    raise exception 'PROOF 20 FAIL: a delta did not carry her docked';
  end if;
  update public.voyages set eta = now() - interval '1 hour' where id = v_voy;
  v_r := world.sea_roster(now() - interval '30 seconds');
  if exists (select 1 from jsonb_array_elements(v_r -> 'fleets') e where e ->> 'id' = v_fl::text) then
    raise exception 'PROOF 20 FAIL: a delta keeps carrying her long after she docked';
  end if;
  raise notice 'PASS: SEEN_DELTA — her arrival is in the next delta, and not in the one after';
end
$$;
