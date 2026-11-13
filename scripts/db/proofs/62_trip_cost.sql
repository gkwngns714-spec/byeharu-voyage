-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 62 — A TRIP SAYS ITS TIME AND ITS PRICE  (migration 0360, world.trip_cost)
--
--   0360's own self-assert proves the read against the authorities it composes. This proof SAILS the trip and compares what the read said BEFORE
--   she left with what the game then did: a probe house's fleet, her casks empty, the economy closed, queues Lisbon -> a harbour a day away ->
--   Lisbon in one cmd.issue_lines, and every arrival is settled at its own instant (voyage.settle; her port time woken by public.port_time_wake).
--
--   The sea is not asked to behave: a storm that broaches her casks or lengthens a leg changes what the second leg must buy and when she arrives,
--   and the read cannot know it. The proof reads the voyage's own delay and the casks at arrival, and holds a figure only where the sea left it
--   alone; each marker says which it was.
--
-- @pass TRIP_SUPPLIES_FIRST   the purse fell at departure by exactly the first leg's supplies
-- @pass TRIP_DOCK_FEES        each arrival charged the dock fee the read named for that harbour
-- @pass TRIP_PORT_TIME        she lay in port the read's stop_seconds after the first arrival (docked a second before), then the second SAIL left
-- @pass TRIP_SUPPLIES_WALKED  the second leg's purchase is the walked figure (where the sea took nothing from her casks)
-- @pass TRIP_WAGES            the wages owed over the trip are the read's (where no leg was delayed)
-- @pass TRIP_TOTAL            supplies + wages + dock fees is the read's total, and the purse fell by supplies + dock fees
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth constant uuid := '00000000-0360-4000-8000-0000000000aa';
  v_pl     uuid;
  v_fl     uuid;
  v_sh     uuid;
  v_lis    uuid;
  v_near   record;
  v_trip   jsonb;
  v_r      jsonb;
  v_p0     bigint;
  v_p1     bigint;
  v_p2     bigint;
  v_p3     bigint;
  v_p4     bigint;
  v_voy    record;
  v_eta1   timestamptz;
  v_ready  timestamptz;
  v_owed0  numeric;
  v_owed1  numeric;
  v_w_exp  numeric;
  v_w_now  numeric;
  v_delay  numeric := 0;
  v_clean  boolean;
  v_n      int;
  v_out    jsonb;
  v_back   jsonb;
  v_nm1    numeric;
  v_speed  numeric;
begin
  -- the closed economy with the city purses lit: dock fees and port time are in force for this transaction only
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (c_auth, 'Casa da Prova 62', (select n.id from public.nations n where n.code = 'PRT'), 100000, false)
  returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Prova', v_lis);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova', true, true);
  select s.id into v_sh from public.ships s where s.fleet_id = v_fl limit 1;
  update public.ships set crew = greatest(crew, 20), water_t = 0, food_t = 0 where id = v_sh;
  perform cmd.assume_identity(c_auth);

  select r.port_id, r.code, r.nm into v_near
    from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id
   where p.kind = 'HARBOUR' and r.nm / greatest(voyage.fleet_speed(v_fl), 0.1) / 24 >= 1
     and voyage.leg_refusal(v_fl, r.port_id, r.nm, null) is null
     and exists (select 1 from public.port_treasury t where t.port_id = r.port_id)
   order by r.nm limit 1;
  if v_near.port_id is null then
    raise exception 'PROOF 62 FAIL: no harbour a day from Lisbon is open to the probe';
  end if;

  v_speed := greatest(voyage.fleet_speed(v_fl), 0.1);   -- her speed in port, before the stores are aboard: what the read and the top-up read

  -- WHAT THE READ SAYS, before she leaves
  -- the courses a player's chart would propose (proof.course, the proofs' own pathfinder fixture): the read and the SAILs are given the same ones
  v_out := proof.course('LIS', v_near.code);
  v_back := proof.course(v_near.code, 'LIS');
  if v_out is null or v_back is null then
    raise exception 'PROOF 62 FAIL: the proofs hold no course between Lisbon and %', v_near.code;
  end if;
  select sum((s ->> 'nm')::numeric) into v_nm1 from jsonb_array_elements(voyage.segments_from_course(v_out)) s;
  v_trip := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code, 'course', v_out),
                                                    jsonb_build_object('from', v_near.code, 'to', 'LIS', 'course', v_back)));
  if v_trip -> 'total' = 'null'::jsonb or (v_trip -> 'legs' -> 0 ->> 'supplies')::bigint <= 0 or (v_trip ->> 'stop_seconds')::numeric <= 0
     or (v_trip -> 'legs' -> 0 ->> 'dock_fee')::bigint <= 0 or (v_trip -> 'legs' -> 1 ->> 'dock_fee')::bigint <= 0 then
    raise exception 'PROOF 62 FAIL: the read prices nothing to prove (empty casks buy nothing, or the closed economy asks no port time or no dock fee): %', v_trip;
  end if;
  select coalesce(sum(w.owed), 0) into v_owed0 from public.fleet_wages w where w.fleet_id = v_fl;
  select ducats into v_p0 from public.players where id = v_pl;

  -- THE TRIP, queued whole
  v_r := cmd.issue_lines(v_fl, jsonb_build_array(jsonb_build_object('text', 'SAIL ' || v_near.code, 'path', v_out),
                                                 jsonb_build_object('text', 'SAIL LIS', 'path', v_back)), null);
  if (v_r ->> 'ok')::boolean is not true or exists (select 1 from jsonb_array_elements(v_r -> 'orders') o where o ->> 'status' in ('failed', 'cancelled')) then
    raise exception 'PROOF 62 FAIL: the two SAILs were not queued: %', v_r;
  end if;
  select ducats into v_p1 from public.players where id = v_pl;
  if v_p0 - v_p1 <> (v_trip -> 'legs' -> 0 ->> 'supplies')::bigint then
    raise exception 'PROOF 62 FAIL: the first SAIL''s supplies cost % and the read said %', v_p0 - v_p1, v_trip -> 'legs' -> 0 ->> 'supplies';
  end if;
  raise notice 'PASS: TRIP_SUPPLIES_FIRST — % at departure, as read', v_p0 - v_p1;

  -- THE FIRST ARRIVAL, settled at its own instant (again while a delay moves it)
  for v_n in 1 .. 30 loop
    exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
    select v.id, v.eta, v.delay_hours into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
    perform voyage.settle(v_fl, v_voy.eta);
    select v.eta, v.delay_hours into v_voy.eta, v_voy.delay_hours from public.voyages v where v.id = v_voy.id;
  end loop;
  if (select f.status from public.fleets f where f.id = v_fl) = 'SAILING' or (select f.port_id from public.fleets f where f.id = v_fl) is distinct from v_near.port_id then
    raise exception 'PROOF 62 FAIL: she did not make %', v_near.code;
  end if;
  v_eta1 := v_voy.eta;
  v_delay := v_delay + coalesce(v_voy.delay_hours, 0);
  select ducats into v_p2 from public.players where id = v_pl;
  if v_p1 - v_p2 <> (v_trip -> 'legs' -> 0 ->> 'dock_fee')::bigint then
    raise exception 'PROOF 62 FAIL: % charged a dock fee of % and the read said %', v_near.code, v_p1 - v_p2, v_trip -> 'legs' -> 0 ->> 'dock_fee';
  end if;

  -- HER PORT TIME: she is still there, the next SAIL waiting, until the read's stop_seconds have passed
  select f.ready_at into v_ready from public.fleets f where f.id = v_fl;
  if v_ready is null or extract(epoch from v_ready - v_eta1) <> (v_trip -> 'legs' -> 0 ->> 'stop_seconds')::numeric
     or (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED' then
    raise exception 'PROOF 62 FAIL: her port time is % after the arrival and the read said % s', v_ready - v_eta1, v_trip -> 'legs' -> 0 ->> 'stop_seconds';
  end if;
  perform public.port_time_wake(v_ready - interval '1 second', clock_timestamp() + interval '20 seconds', v_fl);
  if (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED' then
    raise exception 'PROOF 62 FAIL: she left before her port time was up';
  end if;
  -- what the sea left in her casks: the first leg's settled days eaten from what she was topped up to, and nothing else gone
  select s.water_t into v_w_now from public.ships s where s.id = v_sh;
  select greatest(0, tu.water_t - x.crew * public.wc_num('water_per_crew_day') * greatest(1, ceil(v_nm1 / v_speed / 24)))
    into v_w_exp
    from public.ships x
   cross join lateral public.stores_topup(x.crew, 0, 0, public.ship_stores_room(x.id, public.ship_hold_capacity(x.id) - public.ship_cargo_tuns(x.id)),
                                          public.npc_leg_days(v_nm1, v_speed),
                                          public.ship_stores_room(x.id, public.ship_hold_capacity(x.id) * x.store_ratio)) tu
   where x.id = v_sh;
  v_clean := v_delay = 0 and abs(v_w_now - v_w_exp) < 0.002;

  perform public.port_time_wake(v_ready, clock_timestamp() + interval '20 seconds', v_fl);
  -- (the SAIL stamps its departure with the transaction's clock, not the job's instant, so the proof reads her state, not that stamp)
  if (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
    raise exception 'PROOF 62 FAIL: her port time was up at % and the second SAIL did not leave', v_ready;
  end if;
  raise notice 'PASS: TRIP_PORT_TIME — in port until % s after the first arrival (still docked a second before), then the second SAIL left: as read', extract(epoch from v_ready - v_eta1);

  -- THE SECOND LEG'S SUPPLIES: the walked figure
  select ducats into v_p3 from public.players where id = v_pl;
  if v_clean and v_p2 - v_p3 <> (v_trip -> 'legs' -> 1 ->> 'supplies')::bigint then
    raise exception 'PROOF 62 FAIL: the second SAIL''s supplies cost % and the read walked her casks to %', v_p2 - v_p3, v_trip -> 'legs' -> 1 ->> 'supplies';
  end if;
  raise notice 'PASS: TRIP_SUPPLIES_WALKED — % at the second departure, read % (%)', v_p2 - v_p3, v_trip -> 'legs' -> 1 ->> 'supplies',
    case when v_clean then 'held: the sea took nothing' else 'not held: the sea delayed her or took from her casks on the first leg' end;

  -- HOME
  for v_n in 1 .. 30 loop
    exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
    select v.id, v.eta, v.delay_hours into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
    perform voyage.settle(v_fl, v_voy.eta);
    select v.eta, v.delay_hours into v_voy.eta, v_voy.delay_hours from public.voyages v where v.id = v_voy.id;
  end loop;
  if (select f.status from public.fleets f where f.id = v_fl) = 'SAILING' or (select f.port_id from public.fleets f where f.id = v_fl) is distinct from v_lis then
    raise exception 'PROOF 62 FAIL: she did not make Lisbon again';
  end if;
  v_delay := v_delay + coalesce(v_voy.delay_hours, 0);
  select ducats into v_p4 from public.players where id = v_pl;
  if v_p3 - v_p4 <> (v_trip -> 'legs' -> 1 ->> 'dock_fee')::bigint then
    raise exception 'PROOF 62 FAIL: Lisbon charged a dock fee of % and the read said %', v_p3 - v_p4, v_trip -> 'legs' -> 1 ->> 'dock_fee';
  end if;
  raise notice 'PASS: TRIP_DOCK_FEES — % at % and % at Lisbon, as read', v_p1 - v_p2, v_near.code, v_p3 - v_p4;

  -- THE WAGES OWED over the two legs (public.owe_wages keeps them in public.fleet_wages; paid from her next sale's profit)
  select coalesce(sum(w.owed), 0) into v_owed1 from public.fleet_wages w where w.fleet_id = v_fl;
  if v_delay = 0 and round(v_owed1 - v_owed0) <> (v_trip ->> 'wages')::numeric then
    raise exception 'PROOF 62 FAIL: she owes her crew % for the trip and the read said %', v_owed1 - v_owed0, v_trip ->> 'wages';
  end if;
  raise notice 'PASS: TRIP_WAGES — % owed, read % (%)', round(v_owed1 - v_owed0), v_trip ->> 'wages',
    case when v_delay = 0 then 'held: no leg was delayed' else 'not held: the sea delayed a leg' end;

  if (v_trip ->> 'total')::bigint <> (v_trip ->> 'supplies')::bigint + (v_trip ->> 'wages')::bigint + (v_trip ->> 'dock_fee')::bigint
     or (v_clean and v_p0 - v_p4 <> (v_trip ->> 'supplies')::bigint + (v_trip ->> 'dock_fee')::bigint) then
    raise exception 'PROOF 62 FAIL: the purse fell by % and the read''s supplies + dock fees are %: %', v_p0 - v_p4,
      (v_trip ->> 'supplies')::bigint + (v_trip ->> 'dock_fee')::bigint, v_trip;
  end if;
  raise notice 'PASS: TRIP_TOTAL — the purse fell by %; read: supplies % + wages % + dock fees % = %', v_p0 - v_p4,
    v_trip ->> 'supplies', v_trip ->> 'wages', v_trip ->> 'dock_fee', v_trip ->> 'total';
end
$$;
