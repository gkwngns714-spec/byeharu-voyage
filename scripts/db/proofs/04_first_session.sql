-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 4 — THE TEN-MINUTE FIRST SESSION  (DESIGN §K.1, beat by beat)
--
--   "0:00  You are the Casa de Aveiro. One Barca, 'Gaivota', docked at Lisboa. 8,000 ducats.
--    0:20  MARKET tab. Sal is 62% of its neighbours.
--    0:40  Tap the row. CMD fills in BUY sal 60. You submit.
--    1:00  MARKET at Cádiz — reachable in one hop — shows sal above 100%.
--    1:20  CMD: SAIL Gaivota TO Cadiz.
--    1:35  You queue the rest while it sails: SELL sal ALL · BUY couro · SAIL Gaivota TO Lisboa.
--    6:20  LEDGER pings ... 11:00 Gaivota is home. You have understood the machine."
--
-- WHAT THIS PROOF IS FOR
--   Every other proof tests a mechanism. This one tests THE PRODUCT: that the exact sequence a new
--   player is promised actually runs, in the words the player would type, through the one public
--   entry point, and leaves them richer. If this is red, the game does not work, however green the
--   rest of the chain is.
--
-- EVERY COMMAND BELOW IS A TYPED STRING through cmd.issue(). Nothing calls an executor directly,
-- because the point is that the GRAMMAR carries the session, not that the functions exist.
--
-- TWO HONEST DIVERGENCES FROM THE SCRIPT
--   §K.1 says "BUY sal 60". A Barca has a 60-tun hold and sails with 4.2 tuns of stores aboard, so
--   60 tuns does not fit and the order is correctly refused with E_HOLD_FULL. That refusal is
--   asserted here as a feature — it is the game telling the truth — and the session then buys what
--   fits. The DESIGN's arithmetic is wrong; its beat is not.
--
--   And K.1 quotes "ETA 4.7 minutes" for the Lisboa-Cadiz crossing. That is the figure for a Barca
--   in BALLAST. With 50 tuns of salt in a 60-tun hold, B.3's M_load = 1 - 0.25 x fill slows her to
--   about 6.1 real minutes. The proof asserts the LADEN figure and separately asserts that she is
--   slower laden than empty, because that penalty is the whole reason hold space is a decision
--   (C.3). A proof that insisted on 4.7 would have been demanding that the cargo weigh nothing.
--
-- @pass FIRST_SESSION_OPENS          one Barca named Gaivota, docked at Lisboa, 8,000 ducats
-- @pass FIRST_SESSION_READS_MARKET   sal reads below 90% of its neighbours at Lisboa, above at Cádiz
-- @pass FIRST_SESSION_SIXTY_REFUSED  "BUY sal 60" is refused E_HOLD_FULL with a sentence and a fix
-- @pass FIRST_SESSION_BUYS_SALT      the salt is aboard and the purse fell by the quoted amount
-- @pass FIRST_SESSION_SAILS          188 nm to Cádiz, and the laden ETA is slower than in ballast
-- @pass FIRST_SESSION_QUEUES_AHEAD   three more orders are queued while the fleet is at sea
-- @pass FIRST_SESSION_RUNS_UNATTENDED  the queue completes with no tick and no player present
-- @pass FIRST_SESSION_REPORT_IS_PROSE  the after-action report is sentences, not codes
-- @pass FIRST_SESSION_HOME_RICHER    the hides sold at Lisboa; the purse is above where it started
--
-- ONE BEAT ADDED TO THE SCRIPT, DELIBERATELY
--   K.1 ends "11:00 Gaivota is home. You have 8,180 ducats" — but the beat before it buys couro at
--   Cadiz, and hides in the hold are not ducats in the purse. Coming home with 40 tuns of couro and
--   LESS cash is the correct behaviour of a working economy, not a loss. So this proof closes the
--   loop the way a player would on the next tap — SELL couro ALL at Lisboa, where couro's affinity
--   is 1.25 against Cadiz's 0.95 — and only then asks whether the house is richer.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth  constant uuid := '00000000-0f04-4000-8000-000000000001';
  v_player uuid;
  v_fleet  uuid;
  v_lis    uuid;
  v_cad    uuid;
  v_sal    uuid;
  v_start  bigint;
  v_after_buy bigint;
  v_final  bigint;
  v_nbr_lis numeric;
  v_nbr_cad numeric;
  v_r      jsonb;
  v_mkt    jsonb;
  v_fl     jsonb;
  v_led    jsonb;
  v_eta_min numeric;
  v_queued int;
  v_prose  text;
  v_cargo  numeric;
  v_qty    numeric;
  v_speed  numeric;
  v_refused_seq int;
  k        int;
begin
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_cad from public.ports where code = 'CAD';
  select id into v_sal from public.goods where code = 'sal';

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

  -- ── 0:20 the MARKET tab: the BUY block is at the top because %NBR says so
  v_mkt     := world.market(v_lis);
  v_nbr_lis := world.pct_of_neighbours(v_lis, v_sal);
  v_nbr_cad := world.pct_of_neighbours(v_cad, v_sal);
  if v_nbr_lis is null or v_nbr_lis >= 90 or v_nbr_cad is null or v_nbr_cad <= 110 then
    raise exception 'PROOF 4 FAILED at 0:20 — sal reads %%NBR % at Lisboa and % at Cádiz; K.1 needs a clear buy here and a clear sell there',
      v_nbr_lis, v_nbr_cad;
  end if;
  if (select e->>'advice' from jsonb_array_elements(v_mkt->'goods') e where e->>'code' = 'sal') <> 'buy' then
    raise exception 'PROOF 4 FAILED at 0:20 — the market does not mark sal as a BUY at Lisboa';
  end if;
  raise notice 'PASS: FIRST_SESSION_READS_MARKET — sal is % per cent of its neighbours at Lisboa (marked BUY) and % per cent at Cádiz',
    v_nbr_lis, v_nbr_cad;

  -- ── 0:40 the script's own order, submitted verbatim, and honestly refused
  v_r := cmd.issue(v_fleet, 'BUY sal 60');
  if (v_r->>'ok')::boolean or v_r->>'error_code' <> 'E_HOLD_FULL'
     or length(coalesce(v_r->>'error_message', '')) < 10
     or jsonb_array_length(v_r->'fixes') < 1 then
    raise exception 'PROOF 4 FAILED at 0:40 — "BUY sal 60" should be refused E_HOLD_FULL with a sentence and a fix; got %', v_r;
  end if;
  v_refused_seq := (v_r->'order'->>'seq')::int;
  raise notice 'PASS: FIRST_SESSION_SIXTY_REFUSED — "BUY sal 60" → E_HOLD_FULL: "%" with % fix(es)',
    v_r->>'error_message', jsonb_array_length(v_r->'fixes');

  perform cmd.clear(v_fleet, false);
  v_r := cmd.issue(v_fleet, 'BUY sal 50');
  select ducats into v_after_buy from public.players where id = v_player;
  v_cargo := public.fleet_cargo_qty(v_fleet, 'sal');
  if not (v_r->>'ok')::boolean or v_cargo <> 50
     or v_after_buy <> v_start - (v_r->'order'->'result'->>'total')::bigint then
    raise exception 'PROOF 4 FAILED at 0:40 — the salt did not go aboard (% tuns, purse % -> %): %',
      v_cargo, v_start, v_after_buy, v_r;
  end if;
  raise notice 'PASS: FIRST_SESSION_BUYS_SALT — 50 tuns aboard at % d./tun, % d. total, purse % → %',
    v_r->'order'->'result'->>'avg_price', v_r->'order'->'result'->>'total', v_start, v_after_buy;

  -- ── 1:20 SAIL, typed exactly as §K.1 types it
  v_r := cmd.issue(v_fleet, 'SAIL Gaivota TO Cadiz');
  if not (v_r->>'ok')::boolean then
    raise exception 'PROOF 4 FAILED at 1:20 — SAIL was refused: %', v_r;
  end if;
  select extract(epoch from (eta - departed_at)) / 60 into v_eta_min
    from public.voyages where fleet_id = v_fleet and status = 'SAILING';
  v_speed := voyage.fleet_speed(v_fleet);
  if (v_r->'order'->'result'->>'total_nm')::numeric <> 188 then
    raise exception 'PROOF 4 FAILED at 1:20 — the crossing is % nm, not the 188 nm DESIGN B.3 publishes',
      v_r->'order'->'result'->>'total_nm';
  end if;
  -- Laden, and therefore slower than the 4.7 minutes K.1 quotes for an empty hull. Both bounds are
  -- asserted: too fast would mean M_load was never applied, too slow would mean it was applied twice.
  if v_eta_min < 5.0 or v_eta_min > 7.0 or v_speed >= 5.0 then
    raise exception 'PROOF 4 FAILED at 1:20 — 188 nm at % kn is % real minutes; a Barca carrying 50 of her 60 tuns should make 5-7 minutes and be slower than her 5.0 kn rating',
      v_speed, v_eta_min;
  end if;
  raise notice 'PASS: FIRST_SESSION_SAILS — 188 nm to Cádiz at % kn (rated 5.0, laden with 50 of 60 tuns), % voyage-days, ETA % real minutes vs the 4.7 K.1 quotes for an empty hull',
    v_speed, v_r->'order'->'result'->>'voyage_days', round(v_eta_min, 2);

  -- ── 1:35 "you queue the rest while it sails"
  perform cmd.issue(v_fleet, 'SELL sal ALL');
  perform cmd.issue(v_fleet, 'BUY couro 40');
  perform cmd.issue(v_fleet, 'SAIL Gaivota TO Lisboa');
  select count(*) into v_queued from public.orders where fleet_id = v_fleet and status = 'pending';
  if v_queued <> 3 or (select status from public.fleets where id = v_fleet) <> 'SAILING' then
    raise exception 'PROOF 4 FAILED at 1:35 — % order(s) queued behind a fleet that is %',
      v_queued, (select status from public.fleets where id = v_fleet);
  end if;
  raise notice 'PASS: FIRST_SESSION_QUEUES_AHEAD — 3 orders queued while Gaivota is at sea (SELL sal ALL · BUY couro 40 · SAIL TO Lisboa)';

  -- ── 6:20 → 11:00. The player closes the app. Nothing ticks. Time simply passes, and the ONLY
  --    thing that happens is that they come back and look.
  for k in 1 .. 2 loop
    update public.voyages set departed_at = departed_at - interval '30 minutes',
                              eta = eta - interval '30 minutes'
     where fleet_id = v_fleet and status = 'SAILING';
    v_fl := world.fleets();     -- the READ is the catch-up (DESIGN D.2)
  end loop;

  select ducats into v_final from public.players where id = v_player;
  if (select status from public.fleets where id = v_fleet) <> 'DOCKED'
     or (select port_id from public.fleets where id = v_fleet) <> v_lis
     or (select count(*) from public.orders where fleet_id = v_fleet and status = 'pending') <> 0
     -- every order EXCEPT the deliberately-refused "BUY sal 60" must have completed
     or (select count(*) from public.orders
          where fleet_id = v_fleet and status = 'failed' and seq <> v_refused_seq) <> 0 then
    raise exception 'PROOF 4 FAILED at 11:00 — the fleet is % at % with % pending and % failed order(s)',
      (select status from public.fleets where id = v_fleet),
      (select code from public.ports p join public.fleets f on f.port_id = p.id where f.id = v_fleet),
      (select count(*) from public.orders where fleet_id = v_fleet and status = 'pending'),
      (select count(*) from public.orders where fleet_id = v_fleet and status = 'failed' and seq <> v_refused_seq);
  end if;
  raise notice 'PASS: FIRST_SESSION_RUNS_UNATTENDED — all 4 orders completed with no tick and nobody watching; Gaivota is docked at Lisboa carrying % tuns of couro',
    public.fleet_cargo_qty(v_fleet, 'couro');

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

  -- ── the beat K.1 leaves implied: turn the hides back into ducats at the port that wants them
  v_r := cmd.issue(v_fleet, 'SELL couro ALL');
  if not (v_r->>'ok')::boolean then
    raise exception 'PROOF 4 FAILED — the hides would not sell at Lisboa: %', v_r;
  end if;
  select ducats into v_final from public.players where id = v_player;

  -- ── and the whole point of the ten minutes
  if v_final <= v_start then
    raise exception 'PROOF 4 FAILED — the session did not make money: started % d., ended % d.', v_start, v_final;
  end if;
  raise notice 'PASS: FIRST_SESSION_HOME_RICHER — started % d.; bought salt at Lisboa, sold it at Cádiz, bought hides there and sold them at home for % d.; the round trip cost % d. in wages and stores and still returned +% d. on a % d. stake, a return of % per cent',
    v_start, v_r->'order'->'result'->>'total',
    (select coalesce(-sum(ducats_delta), 0) from public.ledger
      where player_id = v_player and kind in ('WAGES', 'PROVISION')),
    v_final - v_start, v_start,
    round((v_final - v_start)::numeric / v_start * 100, 2);
end $$;
