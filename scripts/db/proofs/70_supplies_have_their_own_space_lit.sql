-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 70 — SUPPLIES HAVE THEIR OWN SPACE, LIT  (migration 0369 lights ship_stores_separate; 0345 built it, 0360 / 0361 price a trip through it)
--
--   Proofs 62 and 63 sail a trip with an almost empty hold, where the lit and the dark room for supplies are both large. This proof takes the case only the lit
--   world allows: A HOLD BRIMMED WITH CARGO and empty casks. The switch is NOT set here: it is read as the chain left it (0369). Trade's board prices the sale
--   through a harbour between (world.good_board, 0361), the map's read prices the same harbours (world.trip_cost, 0360), and then she SAILS it by the real
--   commands (cmd.issue_lines; every arrival settled at its own instant). What the two reads said is compared with what the game charged.
--
--   As in proofs 62 / 63 the sea is not asked to behave: the supplies figure is held where no leg was delayed and nothing was taken from her casks; the dock
--   fees are held always. Each marker says which it was.
--
-- @pass LIT_BY_0369             the chain left ship_stores_separate true, and 0369's news row is one row
-- @pass LIT_DARK_WOULD_REFUSE   the same brimmed hold with the switch set back for one statement: the SAIL is refused E_ENDURANCE and buys nothing
-- @pass LIT_ROW_IS_THE_TRIP     lit, the board's sell row and world.trip_cost name the same supplies, wages, dock fees and port time for the same harbours
-- @pass LIT_SUPPLIES_CHARGED    the purse fell at the departures by the row's supplies; they went into her supply room (never past it) and no cargo came off
-- @pass LIT_DOCK_FEES           every arrival charged a dock fee, and together they are the row's and the trip's dock_fee
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth constant uuid := '00000000-0369-4000-8000-0000000000aa';
  v_pl     uuid;
  v_fl     uuid;
  v_sh     uuid;
  v_lis    uuid;
  v_good   record;
  v_board  jsonb;
  v_row    jsonb;
  v_codes  text[];
  v_legs   jsonb := '[]'::jsonb;
  v_lines  jsonb := '[]'::jsonb;
  v_ask    jsonb := '[]'::jsonb;
  v_path   jsonb;
  v_trip   jsonb;
  v_r      jsonb;
  v_n      int;
  v_i      int;
  k        int;
  v_p      bigint;
  v_q      bigint;
  v_sup    bigint := 0;
  v_fees   bigint := 0;
  v_fee_n  int := 0;
  v_voy    record;
  v_ready  timestamptz;
  v_clean  boolean := true;
  v_hulls  jsonb;
  v_speed  numeric;
  v_nm     numeric;
  v_hold   numeric;
  v_cargo  numeric;
  v_space  numeric;
  v_st     numeric;
  v_st_max numeric := 0;
begin
  -- AS THE CHAIN LEFT IT
  if (select c.value from public.world_config c where c.key = 'ship_stores_separate') is distinct from 'true'::jsonb or not public.ship_stores_separate()
     or (select count(*) from public.world_news w where w.key = 'update:0369') <> 1 then
    raise exception 'PROOF 70 FAIL: the chain did not leave ship_stores_separate true with one news row of 0369';
  end if;
  raise notice 'PASS: LIT_BY_0369 — ship_stores_separate reads true as the chain left it; one news row "update:0369"';

  -- the closed economy with the city purses lit: dock fees and port time are in force for this transaction only
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (c_auth, 'Casa da Prova 70', (select n.id from public.nations n where n.code = 'PRT'), 100000, false)
  returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Prova', v_lis);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova', true, true);
  select s.id into v_sh from public.ships s where s.fleet_id = v_fl limit 1;
  update public.ships set crew = greatest(crew, 20), water_t = 0, food_t = 0 where id = v_sh;
  perform cmd.assume_identity(c_auth);
  v_hold  := public.ship_hold_capacity(v_sh);
  v_space := public.ship_stores_space(v_sh);

  -- HER HOLD BRIMMED WITH ONE GOOD, AND THE SALE THE BOARD PRICES THROUGH A HARBOUR BETWEEN (the nearest such; the proofs must hold a course for every leg)
  for v_good in select g.id, g.code, g.bulk from public.goods g where g.bulk > 0 and floor(v_hold / g.bulk) >= 1 order by g.code loop
    update public.ships set cargo = jsonb_build_object(v_good.code, floor(v_hold / v_good.bulk)), cargo_basis = jsonb_build_object(v_good.code, 200) where id = v_sh;   -- written straight
    continue when public.fleet_free_hold(v_fl) >= 1;   -- a good whose bulk leaves a tun free is not a brimmed hold
    v_board := world.good_board(v_good.id, v_fl, null, null);
    select e into v_row
      from jsonb_array_elements(v_board->'sell') e
     where (e->>'sailable')::boolean and (e->>'quoted')::boolean and jsonb_array_length(e->'stops') >= 1 and jsonb_typeof(e->'profit') = 'number'
       and (e->'supplies'->>'cost')::numeric > 0
       and not exists (select 1
                         from (select lag(s.c, 1, 'LIS') over (order by s.i) as a, s.c as b
                                 from (select t.c, t.i from jsonb_array_elements_text(e->'stops') with ordinality t(c, i) union all select e->>'port', 1000) s) x
                        where proof.course(x.a, x.b) is null
                           or not exists (select 1 from public.port_treasury pt join public.ports p on p.id = pt.port_id where p.code = x.b))
     order by (e->>'miles')::numeric, e->>'port' limit 1;
    exit when v_row is not null;
  end loop;
  if v_row is null then
    raise exception 'PROOF 70 FAIL: lit, no good brimming her hold is priced at a harbour reached through a harbour between, with supplies to buy and a course for every leg';
  end if;
  v_cargo := public.ship_cargo_tuns(v_sh);
  if public.fleet_free_hold(v_fl) >= 1 or v_cargo < v_hold - 1 then
    raise exception 'PROOF 70 FAIL: the probe''s hold is not brimmed: hold %, cargo %, free %', v_hold, v_cargo, public.fleet_free_hold(v_fl);
  end if;
  v_codes := array(select jsonb_array_elements_text(v_row->'stops')) || (v_row->>'port');
  v_n := cardinality(v_codes);
  for k in 1 .. v_n loop
    v_path := proof.course(case when k = 1 then 'LIS' else v_codes[k - 1] end, v_codes[k]);
    v_legs := v_legs || jsonb_build_array(jsonb_build_object('from', case when k = 1 then 'LIS' else v_codes[k - 1] end, 'to', v_codes[k], 'course', v_path));
    v_ask := v_ask || jsonb_build_array(jsonb_build_object('from', case when k = 1 then 'LIS' else v_codes[k - 1] end, 'to', v_codes[k]));
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('text', 'SAIL ' || v_codes[k], 'path', v_path));
  end loop;

  -- DARK, FOR ONE STATEMENT: the same hold cannot leave (the world before the light), and nothing is bought
  update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate';
  select ducats into v_p from public.players where id = v_pl;
  v_r := proof.sail(v_fl, v_codes[1]);
  if coalesce((v_r->>'ok')::boolean, false) or v_r::text not like '%E_ENDURANCE%'
     or (select ducats from public.players where id = v_pl) <> v_p
     or exists (select 1 from public.ships s where s.id = v_sh and s.water_t + s.food_t > 0) then
    raise exception 'PROOF 70 FAIL: dark, the brimmed hold was not refused E_ENDURANCE with nothing bought: %', v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'ship_stores_separate';
  raise notice 'PASS: LIT_DARK_WOULD_REFUSE — with the switch set back, % t of cargo in a % t hold and empty casks: SAIL % is refused E_ENDURANCE and buys nothing', v_cargo, v_hold, v_codes[1];

  -- LIT: WHAT THE MAP'S READ SAYS OF THE SAME HARBOURS
  v_trip := world.trip_cost(v_fl, v_ask);
  if (v_row->>'wages')::numeric is distinct from (v_trip->>'wages')::numeric
     or (v_row->'supplies'->>'cost')::numeric is distinct from (v_trip->>'supplies')::numeric
     or (v_row->>'dock_fee')::numeric is distinct from (v_trip->>'dock_fee')::numeric
     or (v_row->>'stop_seconds')::numeric is distinct from (v_trip->>'stop_seconds')::numeric then
    raise exception 'PROOF 70 FAIL: lit, the board''s row is not world.trip_cost''s trip: % against %', v_row, v_trip;
  end if;
  if (v_row->'supplies'->>'cost')::bigint <= 0 or (v_row->>'dock_fee')::bigint <= 0 then
    raise exception 'PROOF 70 FAIL: the row prices nothing to prove: %', v_row;
  end if;
  raise notice 'PASS: LIT_ROW_IS_THE_TRIP — % (% t in a % t hold) to % via %: supplies %, wages %, dock fees %, port time % s: the board and world.trip_cost say the same',
    v_good.code, v_cargo, v_hold, v_row->>'port', v_row->'stops', v_row->'supplies'->>'cost', v_row->>'wages', v_row->>'dock_fee', v_row->>'stop_seconds';

  v_speed := greatest(voyage.fleet_speed(v_fl), 0.1);
  v_hulls := world.trip_hulls(v_fl);
  select ducats into v_p from public.players where id = v_pl;

  -- THE TRIP, queued whole
  v_r := cmd.issue_lines(v_fl, v_lines, null);
  if (v_r->>'ok')::boolean is not true or exists (select 1 from jsonb_array_elements(v_r->'orders') o where o->>'status' in ('failed', 'cancelled')) then
    raise exception 'PROOF 70 FAIL: lit, the % SAILs of a brimmed hold were not queued: %', v_n, v_r;
  end if;

  for k in 1 .. v_n loop
    if (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
      raise exception 'PROOF 70 FAIL: leg % did not leave', k;
    end if;
    -- THE DEPARTURE: the purse fell by this leg's supplies; they lie in her supply room, and her cargo is untouched
    select ducats into v_q from public.players where id = v_pl;
    v_sup := v_sup + (v_p - v_q);
    v_p := v_q;
    select s.water_t + s.food_t into v_st from public.ships s where s.id = v_sh;
    v_st_max := greatest(v_st_max, v_st);
    if v_st <= 0 or v_st > v_space + 0.01 or public.ship_cargo_tuns(v_sh) <> v_cargo then
      raise exception 'PROOF 70 FAIL: at departure % she carries % t of supplies against a supply room of % t, cargo % -> %', k, v_st, v_space, v_cargo, public.ship_cargo_tuns(v_sh);
    end if;
    select v.id, v.eta, v.delay_hours into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;

    -- THE ARRIVAL, settled at its own instant (again while a delay moves it)
    for v_i in 1 .. 30 loop
      exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
      select v.eta into v_voy.eta from public.voyages v where v.id = v_voy.id;
      perform voyage.settle(v_fl, v_voy.eta);
      select v.eta, v.delay_hours into v_voy.eta, v_voy.delay_hours from public.voyages v where v.id = v_voy.id;
    end loop;
    if (select f.status from public.fleets f where f.id = v_fl) = 'SAILING'
       or (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fl) is distinct from v_codes[k] then
      raise exception 'PROOF 70 FAIL: she did not make %', v_codes[k];
    end if;
    select ducats into v_q from public.players where id = v_pl;
    v_fees := v_fees + (v_p - v_q);
    v_fee_n := v_fee_n + case when v_p - v_q > 0 then 1 else 0 end;
    v_p := v_q;
    -- what the sea left in her casks: the walk's own figure for this leg, and nothing else gone
    select sum((s->>'nm')::numeric) into v_nm from jsonb_array_elements(voyage.segments_from_course(v_legs->(k - 1)->'course')) s;
    select tl.hulls into v_hulls from world.trip_leg(v_hulls, v_nm, v_speed) tl;
    v_clean := v_clean and coalesce(v_voy.delay_hours, 0) = 0
               and abs((select s.water_t from public.ships s where s.id = v_sh) - (v_hulls->0->>'water')::numeric) < 0.002;

    if k < v_n then
      select f.ready_at into v_ready from public.fleets f where f.id = v_fl;
      perform public.port_time_wake(v_ready, clock_timestamp() + interval '20 seconds', v_fl);
    end if;
  end loop;

  if v_clean and v_sup <> (v_row->'supplies'->>'cost')::bigint then
    raise exception 'PROOF 70 FAIL: lit, the supplies cost % over the trip and the row and the trip said %', v_sup, v_row->'supplies'->>'cost';
  end if;
  raise notice 'PASS: LIT_SUPPLIES_CHARGED — % over % departure(s), the row and the trip said % (%); at most % t aboard in a % t supply room, beside % t of cargo in a % t hold',
    v_sup, v_n, v_row->'supplies'->>'cost',
    case when v_clean then 'held: the sea took nothing' else 'not held: the sea delayed her or took from her casks' end, round(v_st_max, 2), v_space, v_cargo, v_hold;

  if v_fees <> (v_row->>'dock_fee')::bigint or v_fee_n <> v_n then
    raise exception 'PROOF 70 FAIL: % of % arrival(s) charged a dock fee, % together, and the row said %', v_fee_n, v_n, v_fees, v_row->>'dock_fee';
  end if;
  raise notice 'PASS: LIT_DOCK_FEES — % over % arrival(s), each charged: as the row and the trip said', v_fees, v_n;
end
$$;
