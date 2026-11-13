-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 63 — TRADE SAYS WHAT A TRIP REALLY COSTS  (migration 0361: world.good_board / world.board_sell / world.board_legs, world.trip_leg)
--
--   0361's own self-assert proves the board's row against world.trip_cost and the authorities it composes. This proof SAILS the trip Trade
--   offers and compares what the board's sell row said BEFORE she left with what the game then did: a probe house's fleet with cargo aboard,
--   her casks empty, the economy closed and the city purses lit, takes the nearest sale the board prices THROUGH A HARBOUR BETWEEN, queues its
--   SAILs in one cmd.issue_lines, and every arrival is settled at its own instant (voyage.settle; her port time woken by public.port_time_wake).
--
--   The sea is not asked to behave: a storm that broaches her casks or lengthens a leg changes what the next leg must buy, what is owed and when
--   she arrives, and no read can know it. Laden with her stores she also sails a shade slower than the board's speed in port, which can carry a
--   leg into one more day. The proof reads each voyage's own delay and settled days and her casks at each arrival, and holds a figure only where
--   the sea left it alone; each marker says which it was. The dock fees and the port time are held always.
--
-- @pass TRADE_ROW_IS_THE_MAPS_TRIP  the board's row is world.trip_cost's answer for the same harbours: days, port time, supplies, wages, dock fees
-- @pass TRADE_SUPPLIES              the purse fell at the departures by the row's supplies (where the sea took nothing from her casks)
-- @pass TRADE_DOCK_FEES             every arrival charged a dock fee, and together they are the row's dock_fee
-- @pass TRADE_WAGES                 the wages owed over the trip are the row's wages (where every leg settled the days the board counted)
-- @pass TRADE_TIME                  she lay in port the row's stop_seconds, and the sailing and the port time together are the row's time
-- @pass TRADE_AT_SEA                read again under way on the first leg, the same sale still pays the same dock fees and port time, and owes the same wages
-- @pass TRADE_PROFIT                the row's profit is its proceeds less the cost, the tax and exactly those three costs
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth constant uuid := '00000000-0361-4000-8000-0000000000aa';
  v_pl     uuid;
  v_fl     uuid;
  v_sh     uuid;
  v_lis    uuid;
  v_good   record;
  v_board  jsonb;
  v_row    jsonb;
  v_sea    jsonb;
  v_codes  text[];
  v_legs   jsonb := '[]'::jsonb;
  v_lines  jsonb := '[]'::jsonb;
  v_ask    jsonb := '[]'::jsonb;
  v_path   jsonb;
  v_trip   jsonb;
  v_r      jsonb;
  v_n      int;
  k        int;
  v_p      bigint;
  v_q      bigint;
  v_sup    bigint := 0;
  v_fees   bigint := 0;
  v_fee_n  int := 0;
  v_voy    record;
  v_dep    timestamptz;
  v_ready  timestamptz;
  v_sail_s numeric := 0;
  v_port_s numeric := 0;
  v_delay  numeric := 0;
  v_clean  boolean := true;
  v_days_ok boolean := true;   -- every leg settled the days the board counted for it
  v_sea1   numeric;
  v_days   numeric;
  v_owed0  numeric;
  v_owed1  numeric;
  v_hulls  jsonb;
  v_speed  numeric;
  v_nm     numeric;
  v_w_now  numeric;
  v_read_s numeric;
  v_t0     timestamptz;
  v_sup1   bigint;
begin
  -- the closed economy with the city purses lit: dock fees and port time are in force for this transaction only
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (c_auth, 'Casa da Prova 63', (select n.id from public.nations n where n.code = 'PRT'), 100000, false)
  returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Prova', v_lis);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova', true, true);
  select s.id into v_sh from public.ships s where s.fleet_id = v_fl limit 1;
  update public.ships set crew = greatest(crew, 20), water_t = 0, food_t = 0 where id = v_sh;
  perform cmd.assume_identity(c_auth);

  -- HER CARGO, AND THE SALE THE BOARD PRICES THROUGH A HARBOUR BETWEEN (the nearest such; the proofs must hold a course for every leg)
  for v_good in select g.id, g.code from public.goods g order by g.code loop
    update public.ships set cargo = jsonb_build_object(v_good.code, 5), cargo_basis = jsonb_build_object(v_good.code, 200) where id = v_sh;   -- written straight
    v_board := world.good_board(v_good.id, v_fl, null, null);
    select e into v_row
      from jsonb_array_elements(v_board->'sell') e
     where (e->>'sailable')::boolean and (e->>'quoted')::boolean and jsonb_array_length(e->'stops') >= 1 and jsonb_typeof(e->'profit') = 'number'
       and not exists (select 1
                         from (select lag(s.c, 1, 'LIS') over (order by s.i) as a, s.c as b
                                 from (select t.c, t.i from jsonb_array_elements_text(e->'stops') with ordinality t(c, i) union all select e->>'port', 1000) s) x
                        where proof.course(x.a, x.b) is null
                           or not exists (select 1 from public.port_treasury pt join public.ports p on p.id = pt.port_id where p.code = x.b))
     order by (e->>'miles')::numeric, e->>'port' limit 1;
    exit when v_row is not null;
  end loop;
  if v_row is null then
    raise exception 'PROOF 63 FAIL: no good aboard is priced at a harbour reached through a harbour between, with a course for every leg';
  end if;
  if v_board->'qty'->>'basis' <> 'on_board' then
    raise exception 'PROOF 63 FAIL: the probe''s cargo is not read as on board: %', v_board->'qty';
  end if;
  v_codes := array(select jsonb_array_elements_text(v_row->'stops')) || (v_row->>'port');
  v_n := cardinality(v_codes);
  for k in 1 .. v_n loop
    v_path := proof.course(case when k = 1 then 'LIS' else v_codes[k - 1] end, v_codes[k]);
    v_legs := v_legs || jsonb_build_array(jsonb_build_object('from', case when k = 1 then 'LIS' else v_codes[k - 1] end, 'to', v_codes[k], 'course', v_path));
    v_ask := v_ask || jsonb_build_array(jsonb_build_object('from', case when k = 1 then 'LIS' else v_codes[k - 1] end, 'to', v_codes[k]));
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('text', 'SAIL ' || v_codes[k], 'path', v_path));
  end loop;

  -- WHAT THE MAP'S READ SAYS OF THE SAME HARBOURS (world.trip_cost, the legs measured as the board measures them: the sailed-distance table)
  v_trip := world.trip_cost(v_fl, v_ask);
  if (v_row->>'wages')::numeric is distinct from (v_trip->>'wages')::numeric
     or (v_row->'supplies'->>'cost')::numeric is distinct from (v_trip->>'supplies')::numeric
     or (v_row->>'dock_fee')::numeric is distinct from (v_trip->>'dock_fee')::numeric
     or (v_row->>'stop_seconds')::numeric is distinct from (v_trip->>'stop_seconds')::numeric
     or abs((v_row->>'days')::numeric - (v_trip->>'days')::numeric) > 0.011
     or abs((v_row->>'sail_days')::numeric - (v_trip->>'sail_days')::numeric) > 0.011 then
    raise exception 'PROOF 63 FAIL: the board''s row is not world.trip_cost''s trip: % against %', v_row, v_trip;
  end if;
  if (v_row->'supplies'->>'cost')::bigint <= 0 or (v_row->>'wages')::bigint <= 0 or (v_row->>'dock_fee')::bigint <= 0 or (v_row->>'stop_seconds')::numeric <= 0 then
    raise exception 'PROOF 63 FAIL: the row prices nothing to prove (no supplies, no wages, no dock fee or no port time): %', v_row;
  end if;
  raise notice 'PASS: TRADE_ROW_IS_THE_MAPS_TRIP — % to % via %: days %, port time % s, supplies %, wages %, dock fees %: the board and world.trip_cost say the same',
    v_good.code, v_row->>'port', v_row->'stops', v_row->>'days', v_row->>'stop_seconds', v_row->'supplies'->>'cost', v_row->>'wages', v_row->>'dock_fee';

  v_t0 := now();
  v_read_s := extract(epoch from ((v_row->>'arrive_at')::timestamptz - v_t0));
  v_speed := greatest(voyage.fleet_speed(v_fl), 0.1);   -- her speed in port, before the stores are aboard: what the board and the top-up read
  v_hulls := world.trip_hulls(v_fl);
  select coalesce(sum(w.owed), 0) into v_owed0 from public.fleet_wages w where w.fleet_id = v_fl;
  select ducats into v_p from public.players where id = v_pl;

  -- THE TRIP, queued whole
  v_r := cmd.issue_lines(v_fl, v_lines, null);
  if (v_r->>'ok')::boolean is not true or exists (select 1 from jsonb_array_elements(v_r->'orders') o where o->>'status' in ('failed', 'cancelled')) then
    raise exception 'PROOF 63 FAIL: the % SAILs were not queued: %', v_n, v_r;
  end if;

  for k in 1 .. v_n loop
    -- THE DEPARTURE: the purse fell by this leg's supplies
    if (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
      raise exception 'PROOF 63 FAIL: leg % did not leave', k;
    end if;
    select ducats into v_q from public.players where id = v_pl;
    v_sup := v_sup + (v_p - v_q);
    if k = 1 then
      v_sup1 := v_p - v_q;
    end if;
    v_p := v_q;
    select v.id, v.eta, v.departed_at, v.delay_hours into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
    v_dep := v_voy.departed_at;

    if k = 1 then
      -- READ AGAIN UNDER WAY: the same sale from the sea. What is left of this voyage to settle is owed, her next harbour is a call on the way
      select e into v_sea from jsonb_array_elements(world.good_board(v_good.id, v_fl, null, null)->'sell') e where e->>'port' = v_row->>'port';
      -- the days the board counted for this leg in port, and the days this voyage will settle (laden, it can run into one more)
      select sum((s->>'nm')::numeric) into v_nm from jsonb_array_elements(voyage.segments_from_course(v_legs->0->'course')) s;
      select tl.sea_days into v_sea1 from world.trip_leg(v_hulls, v_nm, v_speed) tl;
      if v_sea is null or (v_sea->'stops') is distinct from to_jsonb(v_codes[2:v_n - 1])
         or (v_sea->>'dock_fee')::numeric is distinct from (v_row->>'dock_fee')::numeric
         or (v_sea->>'stop_seconds')::numeric is distinct from (v_row->>'stop_seconds')::numeric
         or (voyage.total_days(v_voy.id) = v_sea1 and (v_sea->>'wages')::numeric is distinct from (v_row->>'wages')::numeric) then
        raise exception 'PROOF 63 FAIL: under way on the first leg the same sale reads % and read % in port', v_sea, v_row;
      end if;
      raise notice 'PASS: TRADE_AT_SEA — under way to %: dock fees %, port time % s, as in port; wages %, in port % (%); supplies still to buy %', v_codes[1],
        v_sea->>'dock_fee', v_sea->>'stop_seconds', v_sea->>'wages', v_row->>'wages',
        case when voyage.total_days(v_voy.id) = v_sea1 then 'held' else 'not held: laden, this leg runs into another day' end, v_sea->'supplies'->>'cost';
    end if;

    -- THE ARRIVAL, settled at its own instant (again while a delay moves it)
    for v_n in 1 .. 30 loop
      exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
      select v.eta into v_voy.eta from public.voyages v where v.id = v_voy.id;
      perform voyage.settle(v_fl, v_voy.eta);
      select v.eta, v.delay_hours into v_voy.eta, v_voy.delay_hours from public.voyages v where v.id = v_voy.id;
    end loop;
    v_n := cardinality(v_codes);
    if (select f.status from public.fleets f where f.id = v_fl) = 'SAILING'
       or (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fl) is distinct from v_codes[k] then
      raise exception 'PROOF 63 FAIL: she did not make %', v_codes[k];
    end if;
    v_delay := v_delay + coalesce(v_voy.delay_hours, 0);
    v_sail_s := v_sail_s + extract(epoch from v_voy.eta - v_dep);
    select ducats into v_q from public.players where id = v_pl;
    v_fees := v_fees + (v_p - v_q);
    v_fee_n := v_fee_n + case when v_p - v_q > 0 then 1 else 0 end;
    v_p := v_q;
    -- what the sea left in her casks: the walk's own figure for this leg, and nothing else gone
    select sum((s->>'nm')::numeric) into v_nm from jsonb_array_elements(voyage.segments_from_course(v_legs->(k - 1)->'course')) s;
    select tl.hulls, tl.sea_days into v_hulls, v_days from world.trip_leg(v_hulls, v_nm, v_speed) tl;
    select s.water_t into v_w_now from public.ships s where s.id = v_sh;
    v_clean := v_clean and coalesce(v_voy.delay_hours, 0) = 0 and abs(v_w_now - (v_hulls->0->>'water')::numeric) < 0.002;
    v_days_ok := v_days_ok and voyage.total_days(v_voy.id) = v_days;

    if k < v_n then
      -- HER PORT TIME: still there a second before it is up, then the next SAIL leaves
      select f.ready_at into v_ready from public.fleets f where f.id = v_fl;
      if v_ready is null or extract(epoch from v_ready - v_voy.eta) * (v_n - 1) <> (v_row->>'stop_seconds')::numeric then
        raise exception 'PROOF 63 FAIL: her port time at % is % and the row said % s over % call(s)', v_codes[k], v_ready - v_voy.eta, v_row->>'stop_seconds', v_n - 1;
      end if;
      perform public.port_time_wake(v_ready - interval '1 second', clock_timestamp() + interval '20 seconds', v_fl);
      if (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED' then
        raise exception 'PROOF 63 FAIL: she left % before her port time was up', v_codes[k];
      end if;
      perform public.port_time_wake(v_ready, clock_timestamp() + interval '20 seconds', v_fl);
      v_port_s := v_port_s + extract(epoch from v_ready - v_voy.eta);
    end if;
  end loop;

  if v_clean and v_sup <> (v_row->'supplies'->>'cost')::bigint then
    raise exception 'PROOF 63 FAIL: the supplies cost % over the trip and the row said %', v_sup, v_row->'supplies'->>'cost';
  end if;
  raise notice 'PASS: TRADE_SUPPLIES — % over % departure(s), the row said % (%)', v_sup, v_n, v_row->'supplies'->>'cost',
    case when v_clean then 'held: the sea took nothing' else 'not held: the sea delayed her or took from her casks' end;

  if v_fees <> (v_row->>'dock_fee')::bigint or v_fee_n <> v_n then
    raise exception 'PROOF 63 FAIL: % of % arrival(s) charged a dock fee, % together, and the row said %', v_fee_n, v_n, v_fees, v_row->>'dock_fee';
  end if;
  raise notice 'PASS: TRADE_DOCK_FEES — % over % arrival(s), each charged: as the row said', v_fees, v_n;

  select coalesce(sum(w.owed), 0) into v_owed1 from public.fleet_wages w where w.fleet_id = v_fl;
  if v_days_ok and round(v_owed1 - v_owed0) <> (v_row->>'wages')::numeric then
    raise exception 'PROOF 63 FAIL: she owes her crew % for the trip and the row said %', v_owed1 - v_owed0, v_row->>'wages';
  end if;
  raise notice 'PASS: TRADE_WAGES — % owed, the row said % (%)', round(v_owed1 - v_owed0), v_row->>'wages',
    case when v_days_ok then 'held: every leg settled the days the board counted' else 'not held: a leg ran into another day' end;

  -- THE TIME: the port time is the row's to the second; the whole (the sailing as her voyages ran it, laden with her stores, and the port time)
  -- is the row's within the larger of 30 s and 3 % (the board sails her at her speed in port, before the stores are aboard)
  if v_port_s <> (v_row->>'stop_seconds')::numeric
     or (v_delay = 0 and abs(v_sail_s + v_port_s - v_read_s) > greatest(30, v_read_s * 0.03)) then
    raise exception 'PROOF 63 FAIL: she sailed % s and lay in port % s; the row said % s in port and % s in all', round(v_sail_s), v_port_s, v_row->>'stop_seconds', round(v_read_s);
  end if;
  raise notice 'PASS: TRADE_TIME — in port % s as the row said; sailing % s + port = % s, the row said % s (%)', v_port_s, round(v_sail_s), round(v_sail_s + v_port_s), round(v_read_s),
    case when v_delay = 0 then 'held' else 'the whole not held: the sea delayed a leg' end;

  if (v_row->>'profit')::numeric <> (v_row->>'proceeds')::numeric - (v_row->>'cost')::numeric - (v_row->>'profit_tax')::numeric
                                    - (v_row->'supplies'->>'cost')::numeric - (v_row->>'wages')::numeric - (v_row->>'dock_fee')::numeric
     or (v_clean and v_days_ok and (v_row->'supplies'->>'cost')::numeric + (v_row->>'wages')::numeric + (v_row->>'dock_fee')::numeric <> v_sup + round(v_owed1 - v_owed0) + v_fees) then
    raise exception 'PROOF 63 FAIL: the row''s profit does not take off what the trip cost (supplies %, wages %, dock fees %): %', v_sup, round(v_owed1 - v_owed0), v_fees, v_row;
  end if;
  raise notice 'PASS: TRADE_PROFIT — profit % = proceeds % - cost % - tax % - supplies % - wages % - dock fees %; charged: supplies %, wages %, dock fees %',
    v_row->>'profit', v_row->>'proceeds', v_row->>'cost', v_row->>'profit_tax', v_row->'supplies'->>'cost', v_row->>'wages', v_row->>'dock_fee',
    v_sup, round(v_owed1 - v_owed0), v_fees;
end
$$;
