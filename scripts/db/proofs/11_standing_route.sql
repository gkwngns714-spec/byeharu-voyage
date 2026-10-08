-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 11 — A ROUTE RUNS BY ITSELF  (migration 0092)
--
-- WHAT THIS PROOF IS FOR, AND WHY IT IS NOT THE MIGRATION'S SELF-ASSERT AGAIN
--   0092 proves, in the transaction that applies it and as the OWNER, that its re-cuts are the
--   pre-images plus only their hunks, that cmd.issue answers byte-identically, and that one route
--   laps, paces, skips, stops and pauses. It cannot prove what a PLAYER meets:
--
--     1. THE DOOR. A player is `authenticated`: the read and the four verbs must answer through
--        the granted entry points, the refill / enqueue / renderer must be refused 42501, no
--        route table may be written directly, and RLS must show a company only its own routes,
--        stops, lines and laps. If a grant is wrong the feature is dead while every self-assert
--        stays green (proof 06's lesson).
--     2. AWAY FROM THE KEYBOARD, FOR REAL LENGTH. Four laps of a two-stop route driven by
--        public.tick_arrivals ALONE — no world.fleets, no world.standing_routes, no cmd.issue
--        between ticks: every arrival refills the queue (one DEPARTED per tick), ducats move, and
--        each closed lap reaches the player's own History read (world.ledger).
--     3. THE BOOKS BALANCE ACROSS LAPS. At the paced hold the purse has moved, to the ducat, by
--        the sum of the closed laps' net — the lap line is the money, not an estimate of it.
--     4. DARK MEANS DARK. With the switch off the verbs refuse through the door and the tick's
--        wake loop and the refill write nothing.
--
-- Every precondition is set here (hazards off, the switch on, pacing off then on) and all of it
-- rolls back with the proof.
--
-- @pass ROUTE_CLIENT_PATH    as authenticated: the read and the four verbs answer, the server-only route functions are refused 42501, a direct table write is refused, and RLS shows a company exactly its own route rows
-- @pass ROUTE_AFK_LAPS       tick_arrivals alone ran a two-stop route for at least three laps: every arrival refilled the queue and departed, ducats moved, and every closed lap is a ROUTE_LAP line in world.ledger
-- @pass ROUTE_BOOKS_BALANCE  at the paced hold the purse had moved exactly the sum of the closed laps' net, and the route waited for the next game-day with an empty queue
-- @pass ROUTE_DARK           with the switch off the four verbs refuse E_UNAVAILABLE through the door and a woken tick writes no order
-- @pass ROUTE_0096_DOOR      (0096) through the client door: a route calling at one harbour twice saves, a stop's crew_up is saved and served, and SELL <good> ALL over the day's allowance sells the allowance while an explicit quantity over it refuses whole
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth    constant uuid := '00000000-0f11-4000-8000-000000000001';
  c_auth2   constant uuid := '00000000-0f11-4000-8000-000000000002';
  v_player  uuid;
  v_player2 uuid;
  v_fleet   uuid;
  v_fleet2  uuid;
  v_lis     uuid;
  v_fnc     uuid;
  v_good    text;
  v_leg     jsonb;
  v_back    jsonb;
  v_res     jsonb;
  v_read    jsonb;
  v_route   uuid;
  v_p0      bigint;
  v_p1      bigint;
  v_net     bigint;
  v_laps    int;
  v_sold    bigint;
  v_dep0    int;
  v_dep1    int;
  v_seen    int;
  v_orders  int;
  v_hold    timestamptz;
  v_ticks   int := 8;
  k         int;
begin
  -- ── THE PRECONDITIONS THIS PROOF OWNS ────────────────────────────────────────────────────────
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
  update public.world_config set value = to_jsonb(0) where key = 'standing_route_laps_per_game_day';
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  v_player  := public.new_house(c_auth,  'Casa da Carreira', 'PRT');
  v_player2 := public.new_house(c_auth2, 'Casa do Lado',     'PRT');
  select id into v_fleet  from public.fleets where player_id = v_player;
  select id into v_fleet2 from public.fleets where player_id = v_player2;
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                           jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
    into v_leg from public.sea_reaches a, public.sea_reaches b where a.code = 'LIS' and b.code = 'FNC';
  v_back := jsonb_build_array(v_leg->1, v_leg->0);
  -- A good offered at Lisbon, not refused at Funchal (the migration probe's rule, read the same way).
  perform cmd.assume_identity(c_auth);
  select gl->>'code' into v_good
    from jsonb_array_elements(world.market(v_lis)->'goods') gl
    join public.goods g on g.code = gl->>'code'
    cross join lateral world.price(v_fnc, g.id) pf
   where (gl->>'offered')::boolean and (gl->>'available')::boolean and (gl->>'stock')::numeric >= 60
     and (gl->>'buy')::numeric between 5 and 60
     and not public.culture_refuses((select culture from public.ports where id = v_fnc), g.culture_mask)
   order by pf.bid - (gl->>'buy')::numeric desc, g.code
   limit 1;
  if v_good is null then
    raise exception 'PROOF 11 FAILED: no good to carry from Lisbon to Funchal';
  end if;

  -- The neighbour keeps a route of their own, so "sees exactly its own" has something to miss.
  perform cmd.assume_identity(c_auth2);
  set local role authenticated;
  v_res := cmd.standing_route_save(null, 'Not Yours', jsonb_build_array(
    jsonb_build_object('port', 'LIS', 'course', v_leg), jsonb_build_object('port', 'FNC', 'course', v_back)), 0, null);
  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception 'PROOF 11 FAILED: the neighbour''s route was refused: %', v_res;
  end if;
  reset role;

  -- ── 1. THE CLIENT PATH ───────────────────────────────────────────────────────────────────────
  perform cmd.assume_identity(c_auth);
  set local role authenticated;
  v_res := cmd.provision_preset_save(null, 'Keep for the route', 12);
  perform cmd.provision_preset_apply(v_fleet, (v_res->>'id')::uuid);
  v_res := cmd.standing_route_save(null, 'Wine run', jsonb_build_array(
    jsonb_build_object('port', 'LIS', 'course', v_leg, 'lines', jsonb_build_array(
      jsonb_build_object('kind', 'SELL'),
      jsonb_build_object('kind', 'BUY', 'good', v_good, 'qty', 20))),
    jsonb_build_object('port', 'FNC', 'course', v_back, 'lines', jsonb_build_array(
      jsonb_build_object('kind', 'SELL')))), 0, 20);
  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception 'PROOF 11 FAILED: save refused through the client door: %', v_res;
  end if;
  v_route := (v_res->>'id')::uuid;
  select ducats into v_p0 from public.players where id = v_player;
  v_res := cmd.standing_route_assign(v_route, v_fleet);
  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception 'PROOF 11 FAILED: assign refused through the client door: %', v_res;
  end if;
  v_read := world.standing_routes();
  if jsonb_array_length(v_read->'routes') <> 1 or v_read::text like '%Not Yours%'
     or v_read->'routes'->0->>'state' <> 'sailing' or not (v_read->>'enabled')::boolean then
    raise exception 'PROOF 11 FAILED: the read served %', v_read;
  end if;
  select count(*) into v_seen from public.standing_routes;
  if v_seen <> 1 or (select count(*) from public.standing_route_stops) <> 2
     or (select count(*) from public.standing_route_lines) <> 3
     or (select count(*) from public.standing_route_laps) <> 1 then
    raise exception 'PROOF 11 FAILED: RLS shows % route row(s) to this company — want exactly its own', v_seen;
  end if;
  begin
    perform cmd.run_standing_route(v_fleet, now());
    raise exception 'PROOF 11 FAILED: cmd.run_standing_route answered a client role';
  exception when insufficient_privilege then null;
  end;
  begin
    perform cmd.enqueue(v_player, '{}'::jsonb, 'SAIL TO FNC', null, null);
    raise exception 'PROOF 11 FAILED: cmd.enqueue answered a client role';
  exception when insufficient_privilege then null;
  end;
  begin
    perform cmd.standing_route_lines(v_route, 0, v_fleet);
    raise exception 'PROOF 11 FAILED: cmd.standing_route_lines answered a client role';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.standing_routes set reserve = 1;
    raise exception 'PROOF 11 FAILED: a client role wrote public.standing_routes directly';
  exception when insufficient_privilege then null;
  end;
  if cmd.standing_route_pause(v_route, true)->>'paused' <> 'true'
     or cmd.standing_route_pause(v_route, false)->>'paused' <> 'false' then
    raise exception 'PROOF 11 FAILED: pause / resume did not answer through the door';
  end if;
  reset role;
  raise notice 'PASS: ROUTE_CLIENT_PATH — as authenticated: save/assign/pause/resume answered, the read serves 1 route (sailing) and none of the neighbour''s, RLS shows 1 route / 2 stops / 3 lines / 1 lap, run_standing_route, enqueue and the renderer were refused 42501, and a direct update was refused';

  -- ── 2. AWAY FROM THE KEYBOARD: tick_arrivals and nothing else ───────────────────────────────
  select count(*) into v_dep0 from public.events where player_id = v_player and kind = 'DEPARTED';
  for k in 1 .. v_ticks loop
    -- The last arrival at Lisbon meets the pacing rule (step 3).
    if k = v_ticks then
      update public.world_config set value = to_jsonb(1) where key = 'standing_route_laps_per_game_day';
    end if;
    update public.voyages
       set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fleet and status = 'SAILING';
    perform public.tick_arrivals(now());
    if k < v_ticks and (select status from public.fleets where id = v_fleet) <> 'SAILING' then
      raise exception 'PROOF 11 FAILED: after tick % the route fleet is % — the queue was not refilled: %', k,
        (select status from public.fleets where id = v_fleet),
        (select jsonb_agg(jsonb_build_array(verb, status, error_code, raw_text) order by seq) from public.orders where fleet_id = v_fleet);
    end if;
  end loop;
  select count(*) into v_dep1 from public.events where player_id = v_player and kind = 'DEPARTED';
  select count(*), coalesce(sum(net), 0), coalesce(sum(sold), 0) into v_laps, v_net, v_sold
    from public.standing_route_laps where route_id = v_route and closed_at is not null;
  select ducats into v_p1 from public.players where id = v_player;
  select count(*) into v_orders from public.orders where fleet_id = v_fleet;
  perform cmd.assume_identity(c_auth);
  set local role authenticated;
  select count(*) into v_seen from jsonb_array_elements(world.ledger(null, 200)->'events') e where e->>'kind' = 'ROUTE_LAP';
  reset role;
  if v_laps < 3 or v_dep1 - v_dep0 <> v_ticks - 1 or v_sold <= 0 or v_p1 = v_p0 or v_seen <> v_laps then
    raise exception 'PROOF 11 FAILED: % tick(s): % closed lap(s), % departure(s) (want %), sold %, purse % -> %, % ROUTE_LAP line(s) in world.ledger',
      v_ticks, v_laps, v_dep1 - v_dep0, v_ticks - 1, v_sold, v_p0, v_p1, v_seen;
  end if;
  raise notice 'PASS: ROUTE_AFK_LAPS — % ticks of tick_arrivals alone: % laps closed, % refills departed, sold % 🪙, purse % -> %, % ROUTE_LAP lines in world.ledger, % order rows left on the fleet (pruned, bounded)',
    v_ticks, v_laps, v_dep1 - v_dep0, v_sold, v_p0, v_p1, v_seen, v_orders;

  -- ── 3. THE BOOKS BALANCE, AT THE PACED HOLD ──────────────────────────────────────────────────
  v_hold := to_timestamp(((world.game_day(now()) + 1) * public.wc_num('game_day_seconds'))::double precision);
  if v_p1 - v_p0 <> v_net
     or (select hold_until from public.standing_routes where id = v_route) is distinct from v_hold
     or (select status from public.fleets where id = v_fleet) <> 'DOCKED'
     or exists (select 1 from public.orders where fleet_id = v_fleet and status = 'pending') then
    raise exception 'PROOF 11 FAILED: the purse moved % against the laps'' net %, or the route did not wait for % (route %)',
      v_p1 - v_p0, v_net, v_hold, (select to_jsonb(sr) from public.standing_routes sr where id = v_route);
  end if;
  raise notice 'PASS: ROUTE_BOOKS_BALANCE — the purse moved % and the % closed laps'' net is %; the route waits at Lisbon, queue empty, until %',
    v_p1 - v_p0, v_laps, v_net, v_hold;

  -- ── 4. DARK ──────────────────────────────────────────────────────────────────────────────────
  update public.world_config set value = 'false'::jsonb where key = 'standing_routes_enabled';
  select count(*) into v_orders from public.orders where fleet_id = v_fleet;
  perform public.tick_arrivals(v_hold + interval '1 second');
  perform cmd.advance(v_fleet, v_hold + interval '1 second');
  perform cmd.assume_identity(c_auth);
  set local role authenticated;
  if cmd.standing_route_save(v_route, null, '[]'::jsonb, null, null)->>'error_code' <> 'E_UNAVAILABLE'
     or cmd.standing_route_assign(v_route, null)->>'error_code' <> 'E_UNAVAILABLE'
     or cmd.standing_route_pause(v_route, false)->>'error_code' <> 'E_UNAVAILABLE'
     or cmd.standing_route_delete(v_route)->>'error_code' <> 'E_UNAVAILABLE'
     or (world.standing_routes()->'routes'->0->>'state') <> 'off' then
    raise exception 'PROOF 11 FAILED: with the switch off a verb answered, or the read is not off';
  end if;
  reset role;
  if (select count(*) from public.orders where fleet_id = v_fleet) <> v_orders
     or (select status from public.fleets where id = v_fleet) <> 'DOCKED' then
    raise exception 'PROOF 11 FAILED: with the switch off the woken tick wrote an order or moved the fleet';
  end if;
  raise notice 'PASS: ROUTE_DARK — switch off: the four verbs answered E_UNAVAILABLE through the door, the read says off, and a tick past the hold plus an advance wrote no order';
end $$;

-- ── 5. WHAT 0096 GAVE A PLAYER'S ROUTE, THROUGH THE DOOR ─────────────────────────────────────────
do $$
declare
  c_auth  constant uuid := '00000000-0f11-4000-8000-000000000096';
  v_player uuid;
  v_fleet  uuid;
  v_lis    uuid;
  v_good   text;
  v_good_id uuid;
  v_lf jsonb; v_fl jsonb; v_fc jsonb; v_cf jsonb;
  v_res    jsonb;
  v_cap    numeric;
  v_fail   text;
  v_sold   numeric;
begin
  update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  select id into v_lis from public.ports where code = 'LIS';
  v_player := public.new_house(c_auth, 'Casa da Porta', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
    into v_lf from public.sea_reaches a, public.sea_reaches b where a.code = 'LIS' and b.code = 'FNC';
  v_fl := jsonb_build_array(v_lf->1, v_lf->0);
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
    into v_fc from public.sea_reaches a, public.sea_reaches b where a.code = 'FNC' and b.code = 'CAD';
  v_cf := jsonb_build_array(v_fc->1, v_fc->0);

  perform cmd.assume_identity(c_auth);
  set local role authenticated;
  -- a loop that calls at Funchal twice, crew_up on the second visit
  v_res := cmd.standing_route_save(null, 'Twice Funchal', jsonb_build_array(
    jsonb_build_object('port', 'LIS', 'course', v_lf),
    jsonb_build_object('port', 'FNC', 'course', v_fc),
    jsonb_build_object('port', 'CAD', 'course', v_cf),
    jsonb_build_object('port', 'FNC', 'course', v_fl, 'crew_up', true)), 0, 20);
  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception 'PROOF 11 FAILED: a loop calling twice at one harbour was refused through the door: %', v_res;
  end if;
  if (select (x->'stops'->3->>'crew_up')::boolean from jsonb_array_elements(world.standing_routes()->'routes') x
       where x->>'name' = 'Twice Funchal') is not true
     or (select (x->'stops'->1->>'crew_up')::boolean from jsonb_array_elements(world.standing_routes()->'routes') x
       where x->>'name' = 'Twice Funchal') is not false then
    raise exception 'PROOF 11 FAILED: crew_up was not saved and served per stop';
  end if;
  reset role;

  -- D3 through the door: a good she carries, the day's allowance cut to 10
  select gl->>'code' into v_good
    from jsonb_array_elements(world.market(v_lis)->'goods') gl
   where (gl->>'offered')::boolean and (gl->>'available')::boolean
   order by gl->>'code' limit 1;
  select id into v_good_id from public.goods where code = v_good;
  perform public.fleet_load(v_fleet, v_good, 20, 1);
  insert into public.trade_daily (player_id, port_id, good_id, game_day, qty)
  select v_player, v_lis, v_good_id, world.game_day(),
         greatest(0, public.wc_num('daily_cap_fraction') * pg.stock_target - 10)
    from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_good_id
  on conflict (player_id, port_id, good_id, game_day) do update set qty = excluded.qty;
  v_cap := floor(world.daily_cap_remaining(v_player, v_lis, v_good_id));
  perform cmd.assume_identity(c_auth);
  set local role authenticated;
  v_res := cmd.issue(v_fleet, format('SELL %s 15', v_good));
  v_fail := coalesce(v_res->>'error_code', (select o.error_code from public.orders o where o.fleet_id = v_fleet and o.verb = 'SELL' order by o.seq desc limit 1));
  perform cmd.clear(v_fleet, false);
  v_res := cmd.issue(v_fleet, format('SELL %s ALL', v_good));
  reset role;
  select coalesce((o.result->>'qty')::numeric, 0) into v_sold from public.orders o
   where o.fleet_id = v_fleet and o.verb = 'SELL' and o.status = 'done' order by o.seq desc limit 1;
  if v_cap <> 10 or v_fail is distinct from 'E_DAILY_CAP' or v_sold <> v_cap then
    raise exception 'PROOF 11 FAILED: D3 through the door — allowance %, an explicit 15 answered %, ALL sold %', v_cap, v_fail, v_sold;
  end if;
  raise notice 'PASS: ROUTE_0096_DOOR — through the door: a loop calling twice at Funchal saved, crew_up served on its 4th stop only, and with an allowance of % an explicit SELL 15 answered % while SELL ALL sold %',
    v_cap, v_fail, v_sold;
end $$;
