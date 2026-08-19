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
  v_good_code text;
  v_back_code text;
  v_dest_code text;
  v_dest_name text;
  v_dest_culture text;
  v_start  bigint;
  v_after_buy bigint;
  v_final  bigint;
  v_nbr_home numeric;
  v_nbr_away numeric;
  v_r      jsonb;
  v_mkt    jsonb;
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
  k        int;
begin
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

  -- ── 0:20 the MARKET tab. The player does not know the world; they read the %NBR column and the
  --    BUY block at the top of it. So does this proof: it takes the best buy-here-sell-there pair
  --    that ONE leg out of Lisboa offers, judged the way the tab judges it.
  select p_dest.id, p_dest.code, p_dest.name, pg_home.good_id, g.code, l.distance_nm
    into v_dest, v_dest_code, v_dest_name, v_good, v_good_code, v_leg_nm
    from public.legs l
    join public.ports p_dest
      on p_dest.id = case when l.from_port_id = v_lis then l.to_port_id else l.from_port_id end
    join public.port_goods pg_home on pg_home.port_id = v_lis
    join public.port_goods pg_away
      on pg_away.port_id = p_dest.id and pg_away.good_id = pg_home.good_id
    join public.goods g on g.id = pg_home.good_id
   where (l.from_port_id = v_lis or l.to_port_id = v_lis)
     and not (p_dest.culture = any(g.culture_mask))
     and g.bulk <= 1.0                                  -- a Barca's hold is 60 tuns, stores included
     and g.base_value * 40 < v_start                    -- and a starter has to be able to pay for it
   order by pg_away.affinity - pg_home.affinity desc, l.distance_nm asc, g.code asc
   limit 1;
  if v_good is null then
    raise exception 'PROOF 4 FAILED at 0:20 — no one-leg trade out of Lisboa is open to a starter at all';
  end if;

  select culture into v_dest_culture from public.ports where id = v_dest;
  v_mkt      := world.market(v_lis);
  v_nbr_home := world.pct_of_neighbours(v_lis, v_good);
  v_nbr_away := world.pct_of_neighbours(v_dest, v_good);
  if v_nbr_home is null or v_nbr_away is null or v_nbr_home >= 90 or v_nbr_away <= v_nbr_home then
    raise exception 'PROOF 4 FAILED at 0:20 — % reads %%NBR % at Lisboa and % at %; the session needs a clear buy here and a dearer market there',
      v_good_code, v_nbr_home, v_nbr_away, v_dest_name;
  end if;
  if (select e->>'advice' from jsonb_array_elements(v_mkt->'goods') e where e->>'code' = v_good_code) <> 'buy' then
    raise exception 'PROOF 4 FAILED at 0:20 — the market does not mark % as a BUY at Lisboa, so the BUY block would not have shown it', v_good_code;
  end if;
  raise notice 'PASS: FIRST_SESSION_READS_MARKET — % is % per cent of its neighbours at Lisboa (marked BUY) and % per cent at % — % nm away',
    v_good_code, round(v_nbr_home, 1), round(v_nbr_away, 1), v_dest_name, v_leg_nm;

  -- Water the casks first. §F.2 refuses a voyage the stores cannot cover, and refusing is the game
  -- working; a captain fills them at the quay before a 500-mile round trip.
  perform cmd.issue(v_fleet, 'PROVISION FULL');
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
  v_r := cmd.issue(v_fleet, 'BUY ' || v_good_code || ' ' || v_room::int);
  select ducats into v_after_buy from public.players where id = v_player;
  v_cargo := public.fleet_cargo_qty(v_fleet, v_good_code);
  if not (v_r->>'ok')::boolean or v_cargo <> v_room
     or v_after_buy <> v_start - (v_r->'order'->'result'->>'total')::bigint then
    raise exception 'PROOF 4 FAILED at 0:40 — the cargo did not go aboard (% tuns of %, purse % -> %): %',
      v_cargo, v_good_code, v_start, v_after_buy, v_r;
  end if;
  raise notice 'PASS: FIRST_SESSION_BUYS_CARGO — % tuns of % aboard at % d./tun, % d. total, purse % → %',
    v_room, v_good_code, v_r->'order'->'result'->>'avg_price', v_r->'order'->'result'->>'total', v_start, v_after_buy;

  -- ── 1:20 SAIL, typed the way a player types it
  select speed_kn into v_rated from public.ship_classes c
    join public.ships s on s.class_id = c.id where s.fleet_id = v_fleet;
  v_r := cmd.issue(v_fleet, 'SAIL Gaivota TO ' || v_dest_code);
  if not (v_r->>'ok')::boolean then
    raise exception 'PROOF 4 FAILED at 1:20 — SAIL was refused: %', v_r;
  end if;
  select extract(epoch from (eta - departed_at)) / 60 into v_eta_min
    from public.voyages where fleet_id = v_fleet and status = 'SAILING';
  v_speed := voyage.fleet_speed(v_fleet);
  -- The crossing is the LEG's own sailed distance — the one the chart draws and the router summed
  -- — not a figure quoted in a document.
  if abs((v_r->'order'->'result'->>'total_nm')::numeric - v_leg_nm) > 0.05 then
    raise exception 'PROOF 4 FAILED at 1:20 — the crossing is % nm but the leg is % nm',
      v_r->'order'->'result'->>'total_nm', v_leg_nm;
  end if;
  -- Laden, and therefore slower than the rating. Both directions matter: no penalty at all would
  -- mean M_load was never applied, and hold space would stop being a decision (§C.3).
  if v_speed >= v_rated or v_eta_min <= 0 then
    raise exception 'PROOF 4 FAILED at 1:20 — a Barca carrying % of her 60 tuns makes % kn against a % kn rating over % real minutes',
      v_room, v_speed, v_rated, v_eta_min;
  end if;
  raise notice 'PASS: FIRST_SESSION_SAILS — % nm to % at % kn (rated %, laden), % voyage-days, ETA % real minutes',
    v_leg_nm, v_dest_name, round(v_speed, 3), v_rated, v_r->'order'->'result'->>'voyage_days', round(v_eta_min, 2);

  -- ── 1:35 "you queue the rest while it sails". The return cargo is chosen the same way the
  --    outbound one was: what that port sells cheap which Lisboa pays more for.
  -- Chosen on the GRADIENT, and affordable against the stake rather than against what is left after
  -- loading — because by the time this order runs the outbound cargo has been sold. She sails with
  -- 586 ducats in hand and comes into Ponta Delgada with the pepper money; judging the return cargo
  -- on the purse she has right now would rule out every good she will actually be able to buy.
  select pg_away.good_id, g.code
    into v_back, v_back_code
    from public.port_goods pg_away
    join public.port_goods pg_home on pg_home.port_id = v_lis and pg_home.good_id = pg_away.good_id
    join public.goods g on g.id = pg_away.good_id
   where pg_away.port_id = v_dest
     and g.bulk <= 1.0
     and g.base_value * 10 < v_start
     and not (v_dest_culture = any(g.culture_mask))
   order by pg_home.affinity - pg_away.affinity desc, g.code asc
   limit 1;
  if v_back is null then
    raise exception 'PROOF 4 FAILED at 1:35 — nothing at % is worth carrying home', v_dest_name;
  end if;

  perform cmd.issue(v_fleet, 'SELL ' || v_good_code || ' ALL');
  perform cmd.issue(v_fleet, 'BUY ' || v_back_code || ' 20');
  perform cmd.issue(v_fleet, 'SAIL Gaivota TO LIS');
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
