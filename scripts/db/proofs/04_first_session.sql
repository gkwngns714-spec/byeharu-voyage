-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 4 — THE FIRST SESSION  (DESIGN §K.1, beat by beat, in the world that actually exists)
--
--   "0:00  You are the Casa de Aveiro. One Barca, 'Gaivota', docked at Lisboa. 8,000 ducats.
--    0:20  MARKET tab. A good reads far below its neighbours. The BUY block is at the top.
--    0:40  Tap the row. CMD fills in the order. You submit — and it is refused, because it does
--          not fit. You buy what fits.
--    1:20  CMD: SAIL to the port that pays more.
--    1:35  You queue the rest while it sails: SELL ALL · BUY the return cargo · SAIL home.
--    6:20  LEDGER pings ... 11:00 Gaivota is home. You have understood the machine."
--
-- WHAT THIS PROOF IS FOR
--   Every other proof tests a mechanism. This one tests THE PRODUCT: that the sequence a new
--   player is promised actually runs, in the words the player would type, through the one public
--   entry point, and leaves them richer. If this is red, the game does not work, however green the
--   rest of the chain is.
--
-- WHY IT NAMES NO CARGO AND NO DESTINATION
--   §K.1 was written against a twelve-port world and reads "buy sal at Lisboa, sell it at Cádiz,
--   188 nm". All three are now wrong, and none of them was ever the point:
--
--     * the goods table is the real one (70 traded goods, English names), so "sal" is three
--       different commodities;
--     * the world is 214 real ports, so which cargo pays out of Lisboa is a fact about geography
--       and 14,980 derived prices, not something a proof may assume;
--     * and Lisboa to Cádiz is not 188 nm, because 188 nm is the straight line and Cape St Vincent
--       is in the way. The sailed leg is ~248 nm.
--
--   A proof that hard-codes those is asserting a SEED, and it goes red the day the world grows.
--   So this one asks the market the same question a player asks — "what is cheap here and dear one
--   leg away?" — and then plays whatever the answer is. The BEATS are asserted; the itinerary is
--   discovered. Every command is still a typed string through cmd.issue(): the grammar carries the
--   session, not the executors.
--
-- @pass FIRST_SESSION_OPENS          one Barca named Gaivota, docked at Lisboa, 8,000 ducats
-- @pass FIRST_SESSION_READS_MARKET   a good reads below 90% of its neighbours here and dearer there
-- @pass FIRST_SESSION_OVERSIZED_REFUSED  an order bigger than the hold is refused E_HOLD_FULL with a sentence and a fix
-- @pass FIRST_SESSION_BUYS_CARGO     the cargo is aboard and the purse fell by the quoted amount
-- @pass FIRST_SESSION_SAILS          the crossing is the leg's own sailed distance, and laden is slower than rated
-- @pass FIRST_SESSION_QUEUES_AHEAD   three more orders are queued while the fleet is at sea
-- @pass FIRST_SESSION_RUNS_UNATTENDED  the queue completes with no tick and no player present
-- @pass FIRST_SESSION_REPORT_IS_PROSE  the after-action report is sentences, not codes
-- @pass FIRST_SESSION_HOME_RICHER    the return cargo sold at Lisboa; the purse is above where it started
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth  constant uuid := '00000000-0f04-4000-8000-000000000001';
  v_player uuid;
  v_fleet  uuid;
  v_lis    uuid;
  v_dest   uuid;
  v_good   uuid;
  v_back   uuid;
  v_back_qty numeric;
  v_good_code text;
  v_back_code text;
  v_dest_code text;
  v_dest_name text;
  v_dest_culture text;
  v_start  bigint;
  v_after_buy bigint;
  v_final  bigint;
  v_mid_home numeric;
  v_mid_away numeric;
  v_roster_n int;      -- 0061: how many goods Lisboa TRADES — derived, never pinned
  v_r      jsonb;
  v_mkt    jsonb;
  v_routes jsonb;
  v_home   jsonb;
  v_edge   numeric;
  v_qty    numeric;
  v_fl     jsonb;
  v_led    jsonb;
  v_eta_min numeric;
  v_leg_nm numeric;
  v_queued int;
  v_prose  text;
  v_cargo  numeric;
  v_room   numeric;
  v_speed  numeric;
  v_rated  numeric;
  v_refused_seq int;
  v_fixture jsonb;
  k        int;
  r_out    record;
begin
  -- ── THE PRECONDITION THIS PROOF OWNS, ADDED 2026-08-23 ───────────────────────────────────────
  -- This file was a LOTTERY, and it lost roughly one run in three.
  --
  -- `public.tick_market_drift` (0010:107) moves every price by `random()`, DELIBERATELY — its own
  -- comment says "the market is deliberately NOT deterministic, unlike the hazard rolls; a market
  -- a player could replay would be a market a player could front-run." The chain's own self-asserts
  -- call it while applying, so EVERY `db:apply` builds a different market. (Proof 5 was believed to
  -- survive that by pooling eight ports and asserting a band. It did not — it lost about one run in
  -- six on an unchanged chain, and since 2026-08-25 it pins the market through the same fixture
  -- this file does.) This one never had a chance: it needs ONE specific thing to exist — a cargo out of Lisboa that a port one leg away pays more for, AND a return cargo
  -- Lisboa pays more for — and on an unlucky draw there is no such round trip, and it failed at
  -- 0:20 with "not one destination sells anything Lisboa pays more for". That is the world being
  -- unlucky, not the game being broken, and a proof that reddens on a correct system stops gating
  -- anything the third time somebody scrolls past it.
  --
  -- THE FIRST FIX WAS WRONG AND IS RECORDED SO NOBODY REPEATS IT: pinning drift to ZERO made the
  -- file deterministic and deterministically RED. Measured — the quay names 36 routes out of
  -- Lisboa on a drifted market and only 20 on a flat one. The noise is where much of the arbitrage
  -- lives, so deleting it does not give you "the economy without noise", it gives you an economy
  -- with less trade in it than the game ever has.
  --
  -- SO THE DRIFT IS REPLACED, NOT REMOVED, and the replacement is not written here.
  --
  -- 2026-08-25: the forty lines of Box-Muller that used to stand in this spot are now
  -- `proof.pin_market` (scripts/db/market-fixture.mjs), because proof 05 and
  -- tests/rpc.firstSession.spec.ts needed exactly the same thing and three copies of one rule is
  -- the duplication docs/NO_SPAGHETTI.md §1 forbids — the copy that drifts is always the one
  -- nobody is looking at. The law it applies is unchanged and is written out there: every row
  -- redrawn from the OU stationary law the real process settles into, clamped as 0010 clamps it,
  -- keyed on the AUTHORED codes (`ports.code`, `goods.code`) rather than the `gen_random_uuid()`
  -- ids, with the drift slot parked ahead of 0029's wind and the stock pinned to `stock_target`.
  --
  -- THE DRAW IS STILL THIS FILE'S OWN. The key, the secret and both stream prefixes below are the
  -- ones this proof has used since 2026-08-23, so the market it plays is byte-identical to the one
  -- it has been playing; proof 05 passes its own and cannot move these numbers.
  v_fixture := proof.pin_market('00000000-0f04-4000-8000-0000000000dd'::uuid, 'proof-4-fixture',
                                'p4u1:', 'p4u2:');

  -- AND THE OTHER AMBIENT INPUT THIS FILE DOES NOT OWN — the one `proof.pin_market` deliberately
  -- does not touch, because it is the weather and not the market:
  --
  --   HAZARDS. voyage.rng is keyed on the voyage id, which is a gen_random_uuid(), so the weather
  --   is different every run. At hazard_p_max = 0.06 a day, a seven-day crossing meets something
  --   about a third of the time, and a hazard that strands the fleet halts the queue — which is
  --   the halt rule WORKING, and incompatible with a proof whose claim is "the queue completes".
  --   Set to zero here. This file is about the SCRIPT of §K.1, not about the weather; the danger
  --   table has its own coverage and this proof never asserted anything about it.
  --
  -- All of it is set inside the transaction scripts/db/proof.mjs rolls back, and every one of them
  -- is read back, because a fixture that silently stops applying is worse than none: pin_market
  -- raises on its own vacuity and returns the receipt asserted here, and the hazard knob is
  -- re-read below.
  update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max';
  if (v_fixture->>'nonzero')::int < 14000 or (v_fixture->>'distinct')::int < 1000
     or public.wc_num('hazard_p_max') <> 0 then
    raise exception 'PROOF 4 FAILED: the market/hazard preconditions did not take (% non-zero drift row(s), % distinct value(s), hazard_p_max %), so this file is back to playing whatever the clock dealt it',
      v_fixture->>'nonzero', v_fixture->>'distinct', public.wc_num('hazard_p_max');
  end if;

  select id into v_lis from public.ports where code = 'LIS';

  -- ── 0:00
  v_player := public.new_house(c_auth, 'Casa de Aveiro', 'PRT');
  perform cmd.assume_identity(c_auth);
  select id into v_fleet from public.fleets where player_id = v_player;
  select ducats into v_start from public.players where id = v_player;

  if v_start <> 8000
     or (select name from public.fleets where id = v_fleet) <> 'Gaivota'
     or (select status from public.fleets where id = v_fleet) <> 'DOCKED'
     or (select port_id from public.fleets where id = v_fleet) <> v_lis
     or (select count(*) from public.ships where fleet_id = v_fleet) <> 1
     or (select c.name from public.ships s join public.ship_classes c on c.id = s.class_id
          where s.fleet_id = v_fleet) <> 'Barca' then
    raise exception 'PROOF 4 FAILED at 0:00 — the house does not open as K.1 describes (% d., fleet %, status %)',
      v_start, (select name from public.fleets where id = v_fleet),
      (select status from public.fleets where id = v_fleet);
  end if;
  raise notice 'PASS: FIRST_SESSION_OPENS — Casa de Aveiro, one Barca "Gaivota" docked at Lisboa, % ducats', v_start;

  -- Water the casks first. §F.2 refuses a voyage the stores cannot cover, and refusing is the game
  -- working; a captain fills them at the quay before a 500-mile round trip. It happens BEFORE the
  -- market is read now, because the quay only offers destinations she can actually reach today and
  -- a dry ship can reach almost none of them (voyage.sail_refusal, 0019).
  perform cmd.issue(v_fleet, 'PROVISION FULL');

  -- ── 0:20 the MARKET tab. The player does not know the world; they read the WHERE IT PAYS column
  --    and take the row that pays most. So does this proof.
  --
  --    IT USED TO PICK THE WIDEST AFFINITY GAP, and that is the defect migration 0019 exists to
  --    fix, reproduced inside the proof: an affinity gap is not a profit, and the round trip
  --    therefore lost money on roughly one run in twenty — measured, not guessed, and it is why
  --    this file was intermittently red before anybody had changed the economy. A proof that fails
  --    by luck gates nothing. The trade is now the one `world.trade_routes` names, priced end to
  --    end through the same `world.quote` these orders will execute at.
  --    AND IT IS A ROUND TRIP, so the destination has to be worth coming back FROM. The first cut
  --    took the single best outbound row and then asked what Ponta Delgada sells that Lisboa pays
  --    more for — nothing, as it happens, because a small Atlantic island buys from the capital
  --    rather than selling to it. That is not a defect in either read; it is the difference
  --    between one trade and a voyage. So the outbound rows are walked in profit order and the
  --    first destination that ALSO offers a cargo home is the one she sails to. Both legs are the
  --    quay's, through the same authority, and the second call PINS the destination because she is
  --    coming home whatever else is on offer.
  -- 0039: "one leg out" became a sailed radius. 600 nm is measured, not chosen: the old one-leg
  -- scan reached a median of 7 harbours per port, and 600 nm of sailed water reaches a median 8 -
  -- the closest radius to the horizon the proof was written against.
  v_routes := world.trade_routes(v_lis, v_fleet, 600, null);
  for r_out in
    select (e->'to'->>'id')::uuid            as dest_id,
           e->'to'->>'code'                  as dest_code,
           e->'to'->>'name'                  as dest_name,
           (e->>'good_id')::uuid             as good_id,
           e->>'code'                        as good_code,
           (e->>'nm')::numeric               as nm,
           (e->>'profit')::numeric           as profit,
           (e->>'qty')::numeric              as qty
      from jsonb_array_elements(v_routes->'routes') e
      join public.goods g on g.code = e->>'code'
     where g.bulk <= 1.0                                -- a Barca's hold is 60 tuns, stores included
     order by (e->>'profit')::numeric desc, e->>'code'
  loop
    v_home := world.trade_routes(r_out.dest_id, null, null, null, v_lis);
    -- AFFORDABILITY IS THE QUAY'S OWN ARITHMETIC, NOT A PROXY. This used to filter on
    -- `base_value * 10 < stake` and then buy a flat 20 tuns — and the day the catalogue grew to
    -- 243 goods the top-profit return row out of Setubal became sword-blades, whose 20 tuns cost
    -- roughly twice the stake the proxy had approved. The order failed E_INSUFFICIENT_FUNDS, the
    -- queue halted, and the proof reddened on a correct system. So the filter now prices the very
    -- purchase it will make from the row's own outlay/qty (the same authority that charges it),
    -- with 15%% headroom for drift between this read and the arrival that executes it. Buying
    -- fewer tuns than the row priced can only cost less per tun (price impact rises with
    -- quantity), so the estimate is conservative by construction.
    select (e->>'good_id')::uuid, e->>'code', least(20, floor((e->>'qty')::numeric))
      into v_back, v_back_code, v_back_qty
      from jsonb_array_elements(v_home->'routes') e
      join public.goods g on g.code = e->>'code'
     where g.bulk <= 1.0
       and (e->>'qty')::numeric >= 1
       and ((e->>'outlay')::numeric / (e->>'qty')::numeric)
             * least(20, floor((e->>'qty')::numeric)) * 1.15 < v_start
     order by (e->>'profit')::numeric desc, e->>'code'
     limit 1;
    if v_back is not null then
      v_dest      := r_out.dest_id;
      v_dest_code := r_out.dest_code;
      v_dest_name := r_out.dest_name;
      v_good      := r_out.good_id;
      v_good_code := r_out.good_code;
      v_leg_nm    := r_out.nm;
      v_edge      := r_out.profit;
      v_qty       := r_out.qty;
      exit;
    end if;
  end loop;
  if v_good is null then
    raise exception 'PROOF 4 FAILED at 0:20 — of the % route(s) the quay names out of Lisboa, not one destination sells anything Lisboa pays more for, so there is no round trip to play (basis %)',
      jsonb_array_length(v_routes->'routes'), v_routes->'basis';
  end if;

  select culture into v_dest_culture from public.ports where id = v_dest;
  v_mkt      := world.market(v_lis);
  -- 0071: THE INDEX IS GONE, AND WITH IT THE ONLY THING THIS EVER PRINTED. world.pct_of_neighbours
  -- compared this quay's mid with its neighbours' - the answer the owner asked the game to make
  -- the player find - and it is dropped. What stands in its place is the same fact, read the way a
  -- player now has to read it: the mid HERE and the mid THERE, for the good the quay named. Two
  -- prices the player can actually see, rather than an index that pre-chewed them.
  v_mid_home := world.mid_price(v_lis,  v_good, (select stock from public.port_goods where port_id = v_lis  and good_id = v_good));
  v_mid_away := world.mid_price(v_dest, v_good, (select stock from public.port_goods where port_id = v_dest and good_id = v_good));
  -- MOVED DELIBERATELY 2026-08-26 with migration 0061. This used to read "the prices screen still
  -- has to price EVERYTHING (that is what a reading room is)" and asserted
  -- `length(market.goods) = count(*) from public.goods`. Since 0061 a CITY SELLS ONLY WHAT ITS
  -- ROSTER NAMES — the owner, docs/OWNER_REQUESTS.md row 48, "min 4, max 10 trades goods per
  -- city" — so a quay prices its own roster, not the catalogue, and the old line asserted a world
  -- the game no longer has. The expectation is DERIVED from public.port_specialties rather than
  -- pinned, so it survives the re-authoring of the roster's contents, and the owner's own 4..10
  -- band is checked beside it. Nobody's fleet lies at Lisboa in this read, so public.quay_shows's
  -- cargo half cannot widen the payload here.
  --
  -- The rest of the claim is UNCHANGED and is the half that caught 0061's own defect: the good the
  -- quay named has to be ON that market — a shortlist that names a cargo cmd.do_buy would refuse is
  -- a quay promising what the verb will not do — and the margin it quoted has to be a real one at
  -- the fleet's own quantity. %NBR is printed beside them as what it is — an index — and
  -- deliberately NOT required to be in any band: a good can read below the buy threshold here and
  -- still lose money over there, which is the whole reason the WHERE column exists.
  select count(*)::int into v_roster_n from public.port_specialties where port_id = v_lis;
  if jsonb_array_length(v_mkt->'goods') <> v_roster_n
     or v_roster_n < 4 or v_roster_n > 10
     or (select count(*) from jsonb_array_elements(v_mkt->'goods') e where e->>'code' = v_good_code) <> 1
     or v_edge is null or v_edge <= 0
     or v_routes->'basis'->>'qty_from' <> 'fleet' then
    raise exception 'PROOF 4 FAILED at 0:20 — the Lisboa market served % good(s) for a roster of % (the owner''s band is 4..10, the catalogue holds %), % is on it % time(s), and the quay quoted a margin of % on the % basis',
      jsonb_array_length(v_mkt->'goods'), v_roster_n, (select count(*) from public.goods), v_good_code,
      (select count(*) from jsonb_array_elements(v_mkt->'goods') e where e->>'code' = v_good_code),
      v_edge, v_routes->'basis'->>'qty_from';
  end if;
  raise notice 'PASS: FIRST_SESSION_READS_MARKET — Lisboa prices the % good(s) it TRADES (of % in the catalogue), and the quay names % for % — % nm out, a quoted margin of % d.; it mids at % here and % there, which is the gradient itself rather than an index of it',
    jsonb_array_length(v_mkt->'goods'), (select count(*) from public.goods), v_good_code, v_dest_name, v_leg_nm, v_edge,
    round(v_mid_home, 1), round(v_mid_away, 1);
  select greatest(1, floor((c.hold - s.water_t - s.food_t) / g.bulk))
    into v_room
    from public.ships s
    join public.ship_classes c on c.id = s.class_id
    join public.goods g on g.id = v_good
   where s.fleet_id = v_fleet;
  select ducats into v_start from public.players where id = v_player;   -- the stake, after watering

  -- ── 0:40 the order the tapped row would compose, at a quantity that does NOT fit. K.1's own
  --    script hits this: the hold is 60 tuns and the stores are already in it.
  v_r := cmd.issue(v_fleet, 'BUY ' || v_good_code || ' ' || (v_room + 20)::int);
  if (v_r->>'ok')::boolean or v_r->>'error_code' <> 'E_HOLD_FULL'
     or length(coalesce(v_r->>'error_message', '')) < 10
     or jsonb_array_length(v_r->'fixes') < 1 then
    raise exception 'PROOF 4 FAILED at 0:40 — "BUY % %" should be refused E_HOLD_FULL with a sentence and a fix; got %',
      v_good_code, (v_room + 20)::int, v_r;
  end if;
  v_refused_seq := (v_r->'order'->>'seq')::int;
  raise notice 'PASS: FIRST_SESSION_OVERSIZED_REFUSED — "BUY % %" → E_HOLD_FULL: "%" with % fix(es)',
    v_good_code, (v_room + 20)::int, v_r->>'error_message', jsonb_array_length(v_r->'fixes');

  perform cmd.clear(v_fleet, false);
  -- AND THE QUANTITY IS THE QUAY'S, NOT THE HOLD'S. `v_room` is what FITS; it ignores the purse,
  -- which is how this beat used to arrive at "110 tuns of Porcelain cost 40534 d. and you hold
  -- 7925" the moment the trade stopped being hand-picked for cheapness. `world.trade_routes`
  -- priced the row through `public.fleet_buy_capacity`, which stops at whichever of hold, stock,
  -- the daily cap and the purse binds first — the same authority `ALL` resolves through when the
  -- order runs. The number offered and the number charged are the same number.
  v_r := cmd.issue(v_fleet, 'BUY ' || v_good_code || ' ' || v_qty::int);
  select ducats into v_after_buy from public.players where id = v_player;
  v_cargo := public.fleet_cargo_qty(v_fleet, v_good_code);
  if not (v_r->>'ok')::boolean or v_cargo <> v_qty
     or v_after_buy <> v_start - (v_r->'order'->'result'->>'total')::bigint then
    raise exception 'PROOF 4 FAILED at 0:40 — the cargo did not go aboard (% of % tuns of %, purse % -> %): %',
      v_cargo, v_qty, v_good_code, v_start, v_after_buy, v_r;
  end if;
  raise notice 'PASS: FIRST_SESSION_BUYS_CARGO — % tuns of % aboard at % d./tun, % d. total, purse % → % (the quay offered % tuns and % is what she took)',
    v_cargo, v_good_code, v_r->'order'->'result'->>'avg_price', v_r->'order'->'result'->>'total',
    v_start, v_after_buy, v_qty, v_cargo;

  -- ── 1:20 SAIL, typed the way a player types it
  select speed_kn into v_rated from public.ship_classes c
    join public.ships s on s.class_id = c.id where s.fleet_id = v_fleet;
  v_r := proof.sail(v_fleet, v_dest_code);
  if not (v_r->>'ok')::boolean then
    raise exception 'PROOF 4 FAILED at 1:20 — SAIL was refused: %', v_r;
  end if;
  select extract(epoch from (eta - departed_at)) / 60 into v_eta_min
    from public.voyages where fleet_id = v_fleet and status = 'SAILING';
  v_speed := voyage.fleet_speed(v_fleet);
  -- The crossing is the LEG's own sailed distance — the one the chart draws and the router summed
  -- — not a figure quoted in a document.
  -- 0039: the quay quotes the reach table (rounded to 0.1 nm) and the mover measures the
  -- proposed course segment by segment (rounded to 0.01 each, long segments split) — one
  -- generator, two roundings, so the tolerance is half a per cent, not a twentieth of a mile.
  if abs((v_r->'order'->'result'->>'total_nm')::numeric - v_leg_nm) > greatest(0.5, v_leg_nm * 0.005) then
    raise exception 'PROOF 4 FAILED at 1:20 — the crossing is % nm but the quay quoted % nm',
      v_r->'order'->'result'->>'total_nm', v_leg_nm;
  end if;
  -- Laden, and therefore slower than the rating. Both directions matter: no penalty at all would
  -- mean M_load was never applied, and hold space would stop being a decision (§C.3).
  if v_speed >= v_rated or v_eta_min <= 0 then
    raise exception 'PROOF 4 FAILED at 1:20 — a Barca carrying % of her 60 tuns makes % kn against a % kn rating over % real minutes',
      v_qty, v_speed, v_rated, v_eta_min;
  end if;
  raise notice 'PASS: FIRST_SESSION_SAILS — % nm to % at % kn (rated %, laden), % voyage-days, ETA % real minutes',
    v_leg_nm, v_dest_name, round(v_speed, 3), v_rated, v_r->'order'->'result'->>'voyage_days', round(v_eta_min, 2);

  -- ── 1:35 "you queue the rest while it sails". The homeward cargo was settled at 0:20, when the
  --    destination was: a port is only worth sailing to if there is something to bring back, and
  --    choosing the two legs apart is how a round trip ends up with an empty one. No fleet was
  --    named for that read — she is at sea by now, and fleet_buy_capacity reads the port a fleet is
  --    LYING in — so the quay priced it at its own stated quantity and this order takes that
  --    quantity (capped at twenty tuns for a Barca's hold). Affordability was judged against the
  --    stake, from the row's own outlay, because by the time this order runs the outbound cargo
  --    has been sold.

  perform cmd.issue(v_fleet, 'SELL ' || v_good_code || ' ALL');
  perform cmd.issue(v_fleet, 'BUY ' || v_back_code || ' ' || v_back_qty::int);
  perform proof.sail(v_fleet, 'LIS');
  select count(*) into v_queued from public.orders where fleet_id = v_fleet and status = 'pending';
  if v_queued <> 3 or (select status from public.fleets where id = v_fleet) <> 'SAILING' then
    raise exception 'PROOF 4 FAILED at 1:35 — % order(s) queued behind a fleet that is %',
      v_queued, (select status from public.fleets where id = v_fleet);
  end if;
  raise notice 'PASS: FIRST_SESSION_QUEUES_AHEAD — 3 orders queued while Gaivota is at sea (SELL % ALL · BUY % 20 · SAIL TO Lisboa)',
    v_good_code, v_back_code;

  -- ── 6:20 → 11:00. The player closes the app. Nothing ticks. Time simply passes, and the ONLY
  --    thing that happens is that they come back and LOOK. The loop follows the fleet home rather
  --    than assuming how long a voyage in this world takes.
  for k in 1 .. 24 loop
    exit when (select status from public.fleets where id = v_fleet) <> 'SAILING';
    update public.voyages
       set departed_at = departed_at - (eta - now()) - interval '1 minute',
           eta         = now() - interval '1 minute'
     where fleet_id = v_fleet and status = 'SAILING';
    v_fl := world.fleets();     -- the READ is the catch-up (DESIGN D.2)
  end loop;

  if (select status from public.fleets where id = v_fleet) <> 'DOCKED'
     or (select port_id from public.fleets where id = v_fleet) <> v_lis
     or (select count(*) from public.orders where fleet_id = v_fleet and status = 'pending') <> 0
     or (select count(*) from public.orders
          where fleet_id = v_fleet and status = 'failed') <> 0 then
    raise exception 'PROOF 4 FAILED at 11:00 — the fleet is % at % with % pending and % failed order(s)',
      (select status from public.fleets where id = v_fleet),
      coalesce((select code from public.ports p join public.fleets f on f.port_id = p.id where f.id = v_fleet), 'sea'),
      (select count(*) from public.orders where fleet_id = v_fleet and status = 'pending'),
      (select count(*) from public.orders where fleet_id = v_fleet and status = 'failed');
  end if;
  raise notice 'PASS: FIRST_SESSION_RUNS_UNATTENDED — every order completed with no tick and nobody watching; Gaivota is docked at Lisboa carrying % tuns of %',
    public.fleet_cargo_qty(v_fleet, v_back_code), v_back_code;

  -- ── the LEDGER: §E.6 says the report is prose, and prose is what must come out
  v_led := world.ledger();
  select e->'payload'->'lines'->>0 into v_prose
    from jsonb_array_elements(v_led->'events') e where e->>'kind' = 'VOYAGE_REPORT' limit 1;
  if v_prose is null or v_prose !~ '^Day [0-9]+\.' or length(v_prose) < 25 then
    raise exception 'PROOF 4 FAILED — the after-action report is not prose: %', coalesce(v_prose, '(none)');
  end if;
  if (v_led->>'ducats')::bigint <> (v_led->>'ledger_sum')::bigint then
    raise exception 'PROOF 4 FAILED — the ledger does not reconcile: purse % vs sum %',
      v_led->>'ducats', v_led->>'ledger_sum';
  end if;
  raise notice 'PASS: FIRST_SESSION_REPORT_IS_PROSE — "%" (% ledger entries, purse reconciles)',
    v_prose, jsonb_array_length(v_led->'events');

  -- ── the beat K.1 leaves implied: turn the return cargo back into ducats at the port that wants it
  v_r := cmd.issue(v_fleet, 'SELL ' || v_back_code || ' ALL');
  if not (v_r->>'ok')::boolean then
    raise exception 'PROOF 4 FAILED — the % would not sell at Lisboa: %', v_back_code, v_r;
  end if;
  select ducats into v_final from public.players where id = v_player;

  -- ── and the whole point of the ten minutes
  if v_final <= v_start then
    raise exception 'PROOF 4 FAILED — the session did not make money: started % d., ended % d.', v_start, v_final;
  end if;
  raise notice 'PASS: FIRST_SESSION_HOME_RICHER — started % d.; bought % at Lisboa, sold it at %, brought % home and sold it for % d.; the round trip cost % d. in wages and stores and still returned +% d. on a % d. stake, a return of % per cent',
    v_start, v_good_code, v_dest_name, v_back_code, v_r->'order'->'result'->>'total',
    (select coalesce(-sum(ducats_delta), 0) from public.ledger
      where player_id = v_player and kind in ('WAGES', 'PROVISION')),
    v_final - v_start, v_start,
    round((v_final - v_start)::numeric / v_start * 100, 2);
end $$;
