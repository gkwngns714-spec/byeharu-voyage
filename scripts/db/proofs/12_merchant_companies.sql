-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 12 — THE MERCHANT COMPANIES SAIL THE SAME SEA  (migrations 0096-0099, docs/NPC_TRADERS.md)
--
-- WHAT THIS PROOF IS FOR, AND WHY IT IS NOT THE MIGRATIONS' SELF-ASSERTS AGAIN
--   0096-0099 prove, as the OWNER and on thrown-away probes, that the cores are their doors' moved
--   regions, that one probe merchant laps, that the reads keep their key sets. They cannot prove
--   what the founded ROSTER does, all of it at once, through the shared clock — nor what a PLAYER
--   meets at the door:
--
--     1. THE WALL. As `authenticated`, every server-only merchant function and core is refused 42501,
--        a merchant's rows cannot be written, every door handed a merchant's fleet answers "not
--        yours", RLS shows a player none of a merchant's fleets — and the two reads answer.
--     2. AWAY FROM THE KEYBOARD, THE WHOLE ROSTER. The switch on, then tick_arrivals and
--        tick_reconcile ALONE (passages rewound as the cron would see them): a probe merchant on a
--        hand-set market closes a lap with net > 0, every merchant trade is a route-born order, and
--        every roster fleet closes at least one lap through the one executor.
--     3. THE BOOKS. npc_compact rolls each merchant's old books into ONE carried row that still
--        reconciles, touches no player row, and leaves the merchants under npc_row_budget. The rows
--        written per lap are PRINTED (the figure slice 6 records).
--     4. RANK. After settle_standings no merchant is on the board; the probe player is.
--     5. EARNINGS. The card's day is the hand sum of the laps closed in the last day, and its seven
--        recent nets are the last seven laps' in order.
--     6. DARK. The switch off: every merchant route is paused dark, both reads are empty, fleets
--        end docked, and a woken tick writes no merchant order.
--
-- NOT HERE, AND SAID SO: MERCHANT_NOWAIT (upkeep skips a fleet another session holds, within
-- lock_timeout) needs a second connection, which PGlite cannot open; it belongs to CI's disposable
-- Supabase (docs/NPC_TRADERS.md §4.5, §13). The refound cap is asserted by 0097 on its probe.
--
-- Every precondition is set here (hazards off, routes on, merchant pace 0 so a rewound clock is not
-- held, the market pinned by proof.pin_market, the switch, and the probe merchant's lap built and
-- asserted before the soak) and all of it rolls back with the proof. Nothing here reads the wall
-- clock's state of the world: see the two blocks above the soak (2026-10-18).
--
-- @pass MERCHANT_CLIENT_WALL  as authenticated: every merchant core and npc function is refused 42501, a merchant fleet cannot be written, every door handed a merchant fleet refuses it, RLS shows no merchant fleet, and sea_traffic and the card answer (the card refusing the player's own fleet)
-- @pass MERCHANT_AFK_LAP      tick_arrivals and tick_reconcile alone: the probe merchant closed a lap with net > 0, every merchant BOUGHT/SOLD came from a route-born order, and every roster fleet closed at least one lap
-- @pass MERCHANT_BOOKS        after npc_compact every merchant reconciles with exactly one carried row, no player row was touched, retained merchant rows are under npc_row_budget; rows per lap printed
-- @pass MERCHANT_RANK         settle_standings ranked the probe player and no merchant
-- @pass MERCHANT_EARNINGS     the card's day equals the hand sum of the laps closed in the last day, and laps_recent is the last seven nets in order
-- @pass MERCHANT_DARK         the switch off: every merchant route paused dark, both reads empty, merchant fleets docked, and a woken tick wrote no merchant order
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth    constant uuid := '00000000-0f12-4000-8000-000000000001';
  v_player  uuid;
  v_pfleet  uuid;
  v_lis     uuid;
  v_fnc     uuid;
  v_good    uuid;
  v_code    text;
  v_leg     jsonb;
  v_back    jsonb;
  v_spec    jsonb;
  v_m       uuid;
  v_mfleet  uuid;
  v_mroute  uuid;
  v_rfleet  uuid;
  v_res     jsonb;
  v_card    jsonb;
  v_tr      jsonb;
  v_fn      text;
  v_n       int;
  v_soak    int;
  v_k       int;
  v_bad     text[];
  v_rows0   bigint;
  v_rows1   bigint;
  v_laps    int;
  v_player_ledger int;
  v_held    bigint;
  v_sum     numeric;
  v_recent  jsonb;
  v_orders  int;
begin
  -- ── THE PRECONDITIONS THIS PROOF OWNS ────────────────────────────────────────────────────────
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
  update public.world_config set value = to_jsonb(0) where key = 'npc_laps_per_game_day';
  if (select count(*) from public.players where is_npc) < 20 then
    raise exception 'PROOF 12 FAILED: the founded roster is missing (% merchant companies)', (select count(*) from public.players where is_npc);
  end if;
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
    into v_leg from public.sea_reaches a, public.sea_reaches b where a.code = 'LIS' and b.code = 'FNC';
  v_back := jsonb_build_array(v_leg->1, v_leg->0);

  -- THE MARKET IS PINNED (proof.pin_market, scripts/db/market-fixture.mjs, the one authority for
  -- it), with this file's own key. Without it every input below was the wall clock's: the drift is
  -- re-drawn by random() whenever a read lands in a later 10-minute slot than the image was built
  -- in, and stock regenerates by world.game_day(now()) against whatever last_regen_day the image
  -- carries. So which goods the roster fleets planned at Lisbon, and therefore what was left for
  -- the probe, changed with the hour the proof ran (2026-10-18: green at 00:33 UTC on 0172, red
  -- from then on, with or without 0173). The fixture parks the drift slot a day ahead of now() and
  -- pins stock to stock_target at the current game-day, so inside this one transaction, where
  -- now() never moves, the market is a pure function of the chain.
  v_res := proof.pin_market('00000000-0f12-4000-8000-0000000000dd'::uuid, 'proof-12-fixture', 'p12u1:', 'p12u2:');
  if (v_res->>'nonzero')::int < 14000 or (v_res->>'distinct')::int < 1000
     or exists (select 1 from public.port_goods
                 where drift_slot <= public.drift_slot_of(now()) or last_regen_day <> world.game_day(now())) then
    raise exception 'PROOF 12 FAILED: the market fixture did not take (%), so this file is back to playing whatever the clock dealt it', v_res;
  end if;

  -- ── A SOAK WHOSE COST DOES NOT GROW WITH THE WORLD ───────────────────────────────────────────
  -- The roster went from 32 fleets to 76 on 2026-10-11 and this gate's budget did not: the job
  -- passed at 22m48s and was CANCELLED at 30m16s on the next commit, which touched no SQL. The
  -- workflow's ruling is that the answer to that is a lighter fixture, not a bigger number.
  --
  -- Nothing here ever claimed that every fleet IN THE WORLD laps — that is the deploy's soak, on
  -- production's market. What this proof claims is that MERCHANTS lap, AFK, through the one
  -- executor, and that their books reconcile. Twenty-one of them prove that exactly as well as
  -- seventy-six, and the cost now stays flat the next time the world grows.
  --
  -- Done with npc_fleet_max — THE WORLD'S OWN LEVER for exactly this ("population is lowered live
  -- without a migration") — and never by pausing routes by hand, which the upkeep would lift at the
  -- next reconcile. The probe merchant is founded at roster_ord 0, so she is always inside the cap.
  --
  -- READ THE FILTER BELOW BEFORE CHANGING IT. A route beyond the cap is NOT paused 'dark': npc_tend
  -- only writes that reason for a route that HAS a fleet assigned, and a route the switch never
  -- started has no fleet and no reason at all. A first cut of this soak filtered on `paused_reason
  -- is distinct from 'dark'` and so counted 46 never-started routes as part of the soak; they of
  -- course closed no lap, and they looked exactly like a game defect — they were written up as one
  -- before the evidence was taken (OWNER_REQUESTS row 114, withdrawn). THE SOAK IS THE ROUTES THAT
  -- WERE ACTUALLY STARTED: a fleet assigned, and not dark.
  update public.world_config set value = to_jsonb(21) where key = 'npc_fleet_max';
  perform public.npc_traders_switch(true);
  if (select count(*) from public.standing_routes sr join public.players p on p.id = sr.player_id and p.is_npc
       where sr.fleet_id is not null) < 15 then
    raise exception 'PROOF 12 FAILED: the switch started too few merchants to soak';
  end if;

  -- A PROBE MERCHANT, AND HER LAP STATE BUILT HERE, NEVER LEFT TO PLANNING ORDER.
  --
  -- THE DEFECT THIS BLOCK REPLACED (2026-10-18). She used to be founded BEFORE the switch on a
  -- hand-set Lisbon -> Funchal market for the first Lisbon good by code, and her lines were left to
  -- the planner. The switch plans every merchant route (838 on the failing run, sailing or not:
  -- the soak's npc_fleet_max decides which START, not which are planned), longest-planned first,
  -- so the probe, founded a moment before, LAST; and the leg planner keeps at most
  -- npc_buyers_per_good OTHER merchant buyers of a good at a port. Measured on the failing run:
  -- her ware (anise) already had its three merchant buyers at Lisbon, so it was struck off,
  -- nothing else on the leg passed, and she was written in ballast, SELL lines only. On this
  -- file's pinned market every one of the ten Lisbon goods Funchal trades is so held (most of
  -- those routes never sail in this proof). Her one lap bought nothing and closed at minus her
  -- stores (net -9). Her second lap can never start inside this proof: the fortnight at home
  -- (0101) is measured from closed_at = now(), and now() does not move in one transaction. So the
  -- proof passed only on the hours when the drift had left one Lisbon place free.
  --
  -- NOW the roster is switched on FIRST, so every merchant line that will exist is already written,
  -- and her lap is BUILT, not planned: her good is one no SAILING merchant buys anywhere (so no one
  -- fills the Funchal sink before her); her market is hand-set on top of the pinned one (Lisbon a
  -- maker at target stock, Funchal starved of it); her lines are written through the planner's own
  -- save door (cmd.standing_route_save_for) as the planner writes them: SELL at a profit at both
  -- stops, and at Lisbon BUY <good> <qty> AT the merchant ceiling (public.npc_buy_ceiling), sized
  -- inside the daily cap at both ends and half her hold; and she is started through the upkeep's
  -- own assign door (cmd.standing_route_assign_for). Everything after that is the real path: the
  -- executor's route-born orders, tick_arrivals, the SELL at Funchal and the lap close. Her lap
  -- state is ASSERTED before anything runs, and the claim at the end ("she closes a profitable
  -- lap") is unchanged.
  select pg.good_id, g.code into v_good, v_code
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and public.port_offers(v_lis, pg.good_id) and pg.stock_target >= 100
     and exists (select 1 from public.port_goods q where q.port_id = v_fnc and q.good_id = pg.good_id)
     and not public.culture_refuses((select culture from public.ports where id = v_fnc), g.culture_mask)
     and not exists (select 1 from public.standing_route_lines l
                       join public.standing_routes sr on sr.id = l.route_id and sr.fleet_id is not null
                       join public.players p on p.id = sr.player_id and p.is_npc
                      where l.good_id = pg.good_id and l.kind = 'BUY')
   order by g.code limit 1;
  if v_good is null then
    raise exception 'PROOF 12 FAILED: every Lisbon good that Funchal trades is bought by a sailing merchant, so there is no free ware to probe with';
  end if;
  update public.port_goods set stock = stock_target where port_id = v_lis and good_id = v_good;
  update public.port_goods set stock = greatest(1, round(stock_target * 0.15)) where port_id = v_fnc and good_id = v_good;
  v_spec := jsonb_build_object(
    'company', 'Casa da Prova Doze', 'alt_company', 'Casa da Prova XII', 'nation', 'PRT', 'ink', 'prt',
    'master', 'Capitão Probo', 'blurb', 'A probe company that lives for one proof.',
    'capital', 80000, 'patience', 0.30, 'wares', jsonb_build_array(v_code), 'roster_ord', 0,
    'skills', jsonb_build_object('SEAMANSHIP', 1),
    'fleets', jsonb_build_array(jsonb_build_object(
       'name', 'Prova Doze', 'roster_ord', 0, 'days', 12,
       'ships', jsonb_build_array(jsonb_build_object('class', 'carlat', 'name', 'Prova Doze')),
       'officers', '[]'::jsonb,
       'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                  jsonb_build_object('port', 'FNC', 'course', v_back)))));
  v_m := public.npc_found(v_spec);
  select fleet_id, route_id into v_mfleet, v_mroute from public.npc_fleets where player_id = v_m;
  select floor(least(world.daily_cap_remaining(v_m, v_lis, v_good), world.daily_cap_remaining(v_m, v_fnc, v_good),
                     ((select coalesce(sum(public.ship_cargo_tuns(s.id)), 0) from public.ships s where s.fleet_id = v_mfleet)
                      + public.fleet_free_hold(v_mfleet)) / 2 / greatest(g.bulk, 0.001)))::int
    into v_k from public.goods g where g.id = v_good;
  if coalesce(v_k, 0) < 1 or public.npc_buy_ceiling(v_lis, v_good, 0.30) is null then
    raise exception 'PROOF 12 FAILED: the probe''s parcel of % is % unit(s), ceiling % — nothing to build her lap on',
      v_code, v_k, public.npc_buy_ceiling(v_lis, v_good, 0.30);
  end if;
  v_res := cmd.standing_route_save_for(v_m, v_mroute, null, jsonb_build_array(
    jsonb_build_object('port', 'LIS', 'course', v_leg, 'repair', true, 'crew_up', true, 'lines', jsonb_build_array(
      jsonb_build_object('kind', 'SELL', 'at_profit', true),
      jsonb_build_object('kind', 'BUY', 'good', v_code, 'qty', v_k, 'price_limit', public.npc_buy_ceiling(v_lis, v_good, 0.30)))),
    jsonb_build_object('port', 'FNC', 'course', v_back, 'repair', false, 'crew_up', true, 'lines', jsonb_build_array(
      jsonb_build_object('kind', 'SELL', 'at_profit', true)))), null, null, 0);
  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception 'PROOF 12 FAILED: the save door refused the probe''s lap: %', v_res;
  end if;
  v_res := cmd.standing_route_assign_for(v_m, v_mroute, v_mfleet);
  if not coalesce((v_res->>'ok')::boolean, false)
     or (select fleet_id from public.standing_routes where id = v_mroute) is distinct from v_mfleet
     or (select lap_no from public.standing_routes where id = v_mroute) <> 1 then
    raise exception 'PROOF 12 FAILED: the assign door did not start the probe merchant: %', v_res;
  end if;
  if not exists (select 1 from public.orders o where o.fleet_id = v_mfleet and o.verb = 'BUY' and o.status = 'done'
                    and o.route_lap_id is not null)
     or (select status from public.fleets where id = v_mfleet) <> 'SAILING' then
    raise exception 'PROOF 12 FAILED: the probe merchant''s lap 1 did not BUY % at Lisbon through a route-born order and sail: orders %',
      v_code,
      (select jsonb_agg(jsonb_build_array(o.verb, o.status, o.error_code, o.raw_text) order by o.seq) from public.orders o where o.fleet_id = v_mfleet);
  end if;

  -- A PLAYER, with a fleet of her own.
  v_player := public.new_house(c_auth, 'Casa da Testemunha', 'PRT');
  select id into v_pfleet from public.fleets where player_id = v_player;
  -- ── 1. THE WALL ──────────────────────────────────────────────────────────────────────────────
  select nf.fleet_id into v_rfleet from public.npc_fleets nf where nf.player_id <> v_m order by nf.roster_ord limit 1;
  perform cmd.assume_identity(c_auth);
  set local role authenticated;
  v_n := 0;
  foreach v_fn in array array[
      'select public.npc_found(''{}''::jsonb)', 'select public.npc_plan(now(), null)', 'select public.npc_tend(now(), null)',
      'select public.npc_compact(now())', 'select public.npc_traders_switch(true)', 'select public.route_earnings(null)',
      'select public.npc_buy_ceiling(null, null, 0.1)', 'select public.commission_ship(null, null, ''barca'', ''X'', false, false)',
      'select public.form_fleet(null, ''X'', null)', 'select public.sign_officer(null, ''X'', null)',
      'select public.raise_skill(null, ''X'', null)', 'select cmd.standing_route_save_for(null, null, null, ''[]''::jsonb, null, null, null)',
      'select cmd.standing_route_assign_for(null, null, null)', 'select cmd.clear_for(null, null, false)',
      'select world.voyage_view(null, false)', 'select public.tick_arrivals(now())'] loop
    begin
      execute v_fn;
      raise exception 'PROOF 12 FAILED: a client role ran %', v_fn;
    exception when insufficient_privilege then
      v_n := v_n + 1;
    end;
  end loop;
  begin
    update public.fleets set name = 'Taken' where id = v_rfleet;
    get diagnostics v_k = row_count;
    if v_k <> 0 then
      raise exception 'PROOF 12 FAILED: a client wrote a merchant fleet';
    end if;
  exception when insufficient_privilege then null;
  end;
  if coalesce(cmd.issue(v_rfleet, 'SAIL TO LIS')->>'error_code', 'OK') not in ('E_NO_SUCH_FLEET', 'E_NOT_YOUR_FLEET')
     or coalesce(cmd.clear(v_rfleet, false)->>'error_code', 'OK') <> 'E_NOT_YOUR_FLEET'
     or coalesce(cmd.cancel_at(v_rfleet, null)->>'error_code', 'OK') <> 'E_NOT_YOUR_FLEET' then   -- (0225: the preset door is revoked, 42501 for everyone)
    raise exception 'PROOF 12 FAILED: a door accepted a merchant''s fleet';
  end if;
  begin
    if exists (select 1 from public.fleets f where f.id <> v_pfleet) then
      raise exception 'PROOF 12 FAILED: RLS shows a player fleets that are not hers';
    end if;
  exception when insufficient_privilege then
    null;   -- no read grant at all is a wall too
  end;
  v_tr := world.sea_traffic();
  if not (v_tr->>'enabled')::boolean or jsonb_array_length(v_tr->'fleets') < 20 then
    raise exception 'PROOF 12 FAILED: sea_traffic did not answer the player: %', left(v_tr::text, 200);
  end if;
  v_card := world.npc_fleet_card(v_rfleet);
  if v_card->'fleet'->>'id' <> v_rfleet::text then
    raise exception 'PROOF 12 FAILED: the card did not answer the player';
  end if;
  begin
    perform world.npc_fleet_card(v_pfleet);
    raise exception 'PROOF 12 FAILED: the card answered for the player''s own fleet';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'E_NOT_FOUND%' then raise; end if;
  end;
  reset role;
  raise notice 'PASS: MERCHANT_CLIENT_WALL — as authenticated: % server-only merchant function(s) refused 42501, a merchant fleet could not be written, issue/clear/cancel/preset refused a merchant fleet, RLS showed only her own fleet, sea_traffic served % merchant fleet(s), the card answered for a merchant and refused her own fleet E_NOT_FOUND',
    v_n, jsonb_array_length(v_tr->'fleets');

  -- ── 2. AWAY FROM THE KEYBOARD: the whole roster, the arrivals tick and the hourly reconcile ───
  select (select count(*) from public.ledger l join public.players p on p.id = l.player_id and p.is_npc)
       + (select count(*) from public.events e join public.players p on p.id = e.player_id and p.is_npc)
       + (select count(*) from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
            join public.fleets f on f.id = v.fleet_id join public.players p on p.id = f.player_id and p.is_npc)
       + (select count(*) from public.voyages v join public.fleets f on f.id = v.fleet_id join public.players p on p.id = f.player_id and p.is_npc)
       + (select count(*) from public.orders o join public.players p on p.id = o.player_id and p.is_npc)
    into v_rows0;
  for v_k in 1 .. 14 loop
    update public.voyages v set departed_at = v.departed_at - (v.eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
      from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
     where v.fleet_id = f.id and v.status = 'SAILING';
    update public.standing_routes sr set hold_until = now() - interval '1 second'
      from public.players p where p.id = sr.player_id and p.is_npc and sr.hold_until is not null;
    perform public.tick_arrivals(now());
    call public.tick_lap_starts(false);   -- 0266: a rested merchant's lap starts in its own job, not in the beat
    if v_k % 5 = 0 then
      call public.tick_reconcile(false);   -- 0137: a procedure; false = inside this proof's transaction
    end if;
  end loop;
  select (select count(*) from public.ledger l join public.players p on p.id = l.player_id and p.is_npc)
       + (select count(*) from public.events e join public.players p on p.id = e.player_id and p.is_npc)
       + (select count(*) from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
            join public.fleets f on f.id = v.fleet_id join public.players p on p.id = f.player_id and p.is_npc)
       + (select count(*) from public.voyages v join public.fleets f on f.id = v.fleet_id join public.players p on p.id = f.player_id and p.is_npc)
       + (select count(*) from public.orders o join public.players p on p.id = o.player_id and p.is_npc)
    into v_rows1;
  select count(*) into v_laps from public.standing_route_laps x join public.npc_fleets nf on nf.route_id = x.route_id
   where x.closed_at is not null;
  if not exists (select 1 from public.standing_route_laps where route_id = v_mroute and closed_at is not null and net > 0) then
    raise exception 'PROOF 12 FAILED: the probe merchant closed no profitable lap: %',
      (select jsonb_agg(jsonb_build_object('lap', lap_no, 'net', net, 'closed', closed_at)) from public.standing_route_laps where route_id = v_mroute);
  end if;
  if exists (select 1 from public.orders o join public.players p on p.id = o.player_id and p.is_npc
              where o.verb in ('BUY', 'SELL') and o.status = 'done' and o.route_lap_id is null) then
    raise exception 'PROOF 12 FAILED: a merchant traded through an order no route wrote';
  end if;
  -- Every roster fleet either closed a lap through the executor, or is LAID UP because the planner
  -- found nothing that pays on any leg of its loop (a truthful state of this market, re-asked every
  -- hour, never a fault) — and at least four in five closed one. A fleet stopped for any other reason
  -- is a failure.
  select array_agg(format('%s (%s, route %s, failed %s, lap %s)', f.name, f.status,
                          coalesce(sr.paused_reason, 'running'),
                          (select o.error_code || ' ' || o.raw_text from public.orders o where o.fleet_id = f.id and o.status = 'failed' order by o.seq limit 1),
                          sr.lap_no))
    into v_bad from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
    join public.standing_routes sr on sr.id = nf.route_id
   where sr.fleet_id is not null and sr.paused_reason is distinct from 'dark'
     and not exists (select 1 from public.standing_route_laps x where x.route_id = nf.route_id and x.closed_at is not null)
     and not (sr.paused_reason = 'laid_up'
              and exists (select 1 from public.events e where e.player_id = sr.player_id and e.kind = 'ROUTE_PAUSED'
                            and e.payload::text like '%No cargo pays%'));
  if v_bad is not null then
    raise exception 'PROOF 12 FAILED: merchant fleet(s) neither lapped nor were laid up for want of cargo: %', v_bad;
  end if;
  select count(*) into v_n from public.npc_fleets nf
    join public.standing_routes sr on sr.id = nf.route_id
   where sr.fleet_id is not null and sr.paused_reason is distinct from 'dark'
     and exists (select 1 from public.standing_route_laps x where x.route_id = nf.route_id and x.closed_at is not null);
  select count(*) into v_soak from public.npc_fleets nf
    join public.standing_routes sr on sr.id = nf.route_id
   where sr.fleet_id is not null and sr.paused_reason is distinct from 'dark';
  if v_n * 5 < v_soak * 4 then
    raise exception 'PROOF 12 FAILED: only % of % soaked merchant fleets closed a lap', v_n, v_soak;
  end if;
  -- NON-VACUITY: the soak must have had fleets in it, or the two claims above are about nothing.
  if v_soak < 15 then
    raise exception 'PROOF 12 FAILED: the soak drove only % fleet(s) — it is proving nothing', v_soak;
  end if;
  raise notice 'PASS: MERCHANT_AFK_LAP — 14 rewound ticks of tick_arrivals (+ 2 reconciles) over the % started fleets: % merchant laps closed by % of them (the rest laid up for want of a paying cargo), the probe merchant''s best lap netted %, every merchant BUY/SELL came from a route-born order',
    v_soak, v_laps, v_n,
    (select max(net) from public.standing_route_laps where route_id = v_mroute);

  -- ── 3. THE BOOKS ─────────────────────────────────────────────────────────────────────────────
  select count(*) into v_player_ledger from public.ledger where player_id = v_player;
  v_res := public.npc_compact(now() + interval '7 hours');
  select array_agg(p.company_name) into v_bad from public.players p
   where p.is_npc and (public.ledger_sum(p.id) <> p.ducats
                       or (select count(*) from public.ledger l where l.player_id = p.id and l.kind = 'NPC_CARRIED') > 1);
  if v_bad is not null then
    raise exception 'PROOF 12 FAILED: the roll-up broke the books of %: %', v_bad, v_res;
  end if;
  if (select count(*) from public.ledger where player_id = v_player) <> v_player_ledger
     or exists (select 1 from public.ledger l where l.kind = 'NPC_CARRIED' and l.player_id = v_player) then
    raise exception 'PROOF 12 FAILED: the compactor touched a player''s book';
  end if;
  select (select count(*) from public.ledger l join public.players p on p.id = l.player_id and p.is_npc)
       + (select count(*) from public.events e join public.players p on p.id = e.player_id and p.is_npc)
       + (select count(*) from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
            join public.fleets f on f.id = v.fleet_id join public.players p on p.id = f.player_id and p.is_npc)
       + (select count(*) from public.voyages v join public.fleets f on f.id = v.fleet_id join public.players p on p.id = f.player_id and p.is_npc)
       + (select count(*) from public.orders o join public.players p on p.id = o.player_id and p.is_npc)
       + (select count(*) from public.trade_daily td join public.players p on p.id = td.player_id and p.is_npc)
    into v_held;
  if v_held > public.wc_int('npc_row_budget') then
    raise exception 'PROOF 12 FAILED: % merchant rows retained, over the budget %', v_held, public.wc_int('npc_row_budget');
  end if;
  raise notice 'PASS: MERCHANT_BOOKS — the soak wrote % merchant rows for % closed laps (% rows per lap); npc_compact %; every merchant reconciles with at most one carried row, the player''s % ledger row(s) untouched, % merchant rows retained (budget %)',
    v_rows1 - v_rows0, v_laps, round((v_rows1 - v_rows0)::numeric / greatest(v_laps, 1), 1), v_res,
    v_player_ledger, v_held, public.wc_int('npc_row_budget');

  -- ── 4. RANK ──────────────────────────────────────────────────────────────────────────────────
  delete from public.standings;
  perform public.settle_standings(now());
  if exists (select 1 from public.standings s join public.players p on p.id = s.player_id where p.is_npc)
     or not exists (select 1 from public.standings where player_id = v_player) then
    raise exception 'PROOF 12 FAILED: Rank holds a merchant or lost the player';
  end if;
  raise notice 'PASS: MERCHANT_RANK — settle_standings wrote % row(s): the probe player''s, and none of % merchant companies',
    (select count(*) from public.standings), (select count(*) from public.players where is_npc);

  -- ── 5. EARNINGS ──────────────────────────────────────────────────────────────────────────────
  v_card := world.npc_fleet_card(v_mfleet);
  select coalesce(sum(net), 0) into v_sum from public.standing_route_laps
   where route_id = v_mroute and closed_at > now() - interval '24 hours';
  select coalesce(jsonb_agg(y.net order by y.lap_no desc), '[]'::jsonb) into v_recent
    from (select net, lap_no from public.standing_route_laps where route_id = v_mroute and closed_at is not null
           order by lap_no desc limit 7) y;
  if (v_card->'earnings'->>'day')::numeric <> v_sum or v_card->'earnings'->'laps_recent' <> v_recent
     or (v_card->'earnings'->>'laps_done')::int < 1 then
    raise exception 'PROOF 12 FAILED: the card''s earnings % are not the laps'' own (day %, recent %)', v_card->'earnings', v_sum, v_recent;
  end if;
  raise notice 'PASS: MERCHANT_EARNINGS — the probe merchant''s card says % a day over % lap(s), the hand sum of its laps is %, and its recent nets % are the laps'' own',
    v_card->'earnings'->>'day', v_card->'earnings'->>'day_laps', v_sum, v_recent;

  -- ── 6. DARK ──────────────────────────────────────────────────────────────────────────────────
  perform public.npc_traders_switch(false);
  if exists (select 1 from public.standing_routes sr join public.players p on p.id = sr.player_id and p.is_npc
              where sr.fleet_id is not null and sr.paused_reason is distinct from 'dark') then
    raise exception 'PROOF 12 FAILED: switching off left a merchant route running';
  end if;
  if jsonb_array_length(world.sea_traffic()->'fleets') <> 0 then
    raise exception 'PROOF 12 FAILED: sea_traffic served merchants while dark';
  end if;
  begin
    perform world.npc_fleet_card(v_rfleet);
    raise exception 'PROOF 12 FAILED: the card answered while dark';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'E_NOT_FOUND%' then raise; end if;
  end;
  -- the fleets at sea finish their leg and lie in port
  update public.voyages v set departed_at = v.departed_at - (v.eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
    from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
   where v.fleet_id = f.id and v.status = 'SAILING';
  perform public.tick_arrivals(now());
  if exists (select 1 from public.fleets f join public.players p on p.id = f.player_id and p.is_npc where f.status = 'SAILING') then
    raise exception 'PROOF 12 FAILED: a merchant put to sea again while dark';
  end if;
  select count(*) into v_orders from public.orders o join public.players p on p.id = o.player_id and p.is_npc;
  update public.standing_routes sr set hold_until = now() - interval '1 second'
    from public.players p where p.id = sr.player_id and p.is_npc;
  perform public.tick_arrivals(now() + interval '1 hour');
  call public.tick_lap_starts(false);   -- 0266: the woken holds go to the lap-start job, which must write nothing while dark
  perform public.npc_tend(now());
  if (select count(*) from public.orders o join public.players p on p.id = o.player_id and p.is_npc) <> v_orders
     or exists (select 1 from public.fleets f join public.players p on p.id = f.player_id and p.is_npc where f.status = 'SAILING') then
    raise exception 'PROOF 12 FAILED: a woken tick wrote a merchant order or sailed a merchant while dark';
  end if;
  raise notice 'PASS: MERCHANT_DARK — switch off: every merchant route paused dark, sea_traffic empty, the card refused, % merchant fleet(s) docked, and a woken tick plus an upkeep pass wrote no merchant order',
    (select count(*) from public.fleets f join public.players p on p.id = f.player_id and p.is_npc where f.status = 'DOCKED');
end $$;
