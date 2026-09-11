-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 10 — THE MANIFEST  (migration 0083, and 0084's `native` beside it)
--
-- WHAT THIS PROOF IS FOR, AND WHY IT IS NOT THE MIGRATION'S SELF-ASSERT AGAIN
--   0083 proves, in the transaction that applies it, that a manifest lands atomically, that its
--   lines are the deployed verbs, and that the receipt equals the ledger. It cannot prove three
--   things, and those three are this file:
--
--     1. THE MANIFEST WORKS THROUGH THE DOOR THE BROWSER USES. A migration runs as the owner. A
--        player is `authenticated`, and may call exactly two of these functions; the one body
--        behind them must be refused with 42501, and so must every door for `anon`.
--     2. THE SALE PAYS FOR THE PURCHASE. The whole point of one order over two: a house that cannot
--        afford the buy on its own can afford it once the sale on the same manifest has landed
--        first. The self-assert never set the purse; this file does (proof 02's licence).
--     3. THE BARGAIN REACHES THE RECEIPT THROUGH THE REAL PATH. 0083 wrote a haggle_daily row by
--        hand to see haggle_saved move. Here cmd.haggle WINS one (certainty is set, as proof 06
--        sets it) and the preview's `haggle_saved` must be what the unbargained quote would have
--        charged over what the line did.
--
-- ── EVERY NUMBER HERE IS DERIVED OR MEASURED, NONE IS A SEED ────────────────────────────────────
-- The subjects are FOUND by query with an `order by`; the knobs are read from world_config; the
-- purse is SET only to make one refusal certain, and rolled back with everything else.
--
-- @pass MANIFEST_PREVIEW_MOVES_NOTHING   cmd.preview_basket answers a two-line manifest and leaves purse, cargo, events, stock and the day's volume untouched
-- @pass MANIFEST_LINES_ARE_THE_VERBS     each line's figures equal cmd.preview's SELL / BUY of the same order to the hundredth — one body, two doors
-- @pass MANIFEST_SELLS_FUND_BUYS         a buy the purse cannot cover alone is E_INSUFFICIENT_FUNDS in ducats; the same buy behind a sale on one manifest lands
-- @pass MANIFEST_IS_ATOMIC               a refused second line unwinds the first; the same two verbs without the savepoint show the non-atomic state (control)
-- @pass MANIFEST_RECEIPT_IS_THE_LEDGER   the landed manifest's lines are the ledger's SOLD / BOUGHT rows, the purse read back is the receipt's, Σ delta = net
-- @pass MANIFEST_XP_IS_HONEST            trading.delta is player_progress after less before, and world.player().levels.trading.points reads points_after
-- @pass MANIFEST_ONE_LINE_PER_GOOD       a good on two lines is E_MANIFEST_DUPLICATE; [], a side that is not buy/sell, an unknown code and half a tun are refused by shape; nothing moves
-- @pass MANIFEST_BREAKDOWN_ADDS_UP       mid ± tax ± spread is total within the unit rounding, and a bargain WON through cmd.haggle shows as haggle_saved
-- @pass MANIFEST_VERSION_GUARD           a stale version is E_STALE, a fresh one lands and bumps by one, a refused manifest bumps nothing
-- @pass MANIFEST_CLIENT_PATH             as authenticated both doors answer and another house's fleet is refused; cmd.run_manifest is 42501; as anon every door is 42501
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth    constant uuid := '00000000-0f10-4000-8000-000000000001';
  c_other   constant uuid := '00000000-0f10-4000-8000-000000000002';
  v_player  uuid;
  v_other   uuid;
  v_fleet   uuid;
  v_other_f uuid;
  v_port    uuid;
  v_port_c  text;
  v_a uuid; v_a_c text; v_a_n text; v_a_bulk numeric;
  v_b uuid; v_b_c text; v_b_n text; v_b_bulk numeric;
  v_c uuid; v_c_c text;
  k_per_point numeric := public.wc_num('fame_ducats_per_point');
  v_lines   jsonb;
  v_pv      jsonb;
  v_pa      jsonb;
  v_pb      jsonb;
  v_la      jsonb;
  v_lb      jsonb;
  v_res     jsonb;
  v_bad     jsonb;
  v_hag     jsonb;
  v_q       record;
  v_purse0  bigint;
  v_purse1  bigint;
  v_events0 bigint;
  v_cargo_a0 numeric;
  v_cargo_b0 numeric;
  v_stock_a0 numeric;
  v_stock_b0 numeric;
  v_td0     numeric;
  v_ver     int;
  v_buy_total bigint;
  v_over    numeric;
  v_ctrl_a  numeric;
  v_ctrl_seen boolean := false;
  v_n       bigint;
  v_sold_bal bigint;
  v_bought_bal bigint;
  v_err     text;
  v_state   text;
begin
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 0. TWO HOUSES, AND SUBJECTS FOUND BY QUERY. A, B, C are the goods this quay offers that this
  --    house can take most of, in that order (0061's own capacity authority, 0081's query).
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  v_player := public.new_house(c_auth,  'Casa do Manifesto P10', 'PRT');
  v_other  := public.new_house(c_other, 'Casa Alheia P10', 'PRT');
  select id, port_id into v_fleet, v_port from public.fleets where player_id = v_player;
  select id into v_other_f from public.fleets where player_id = v_other;
  select code into v_port_c from public.ports where id = v_port;
  perform cmd.assume_identity(c_auth);

  select g.id, g.code, g.name, g.bulk into v_a, v_a_c, v_a_n, v_a_bulk
    from public.goods g
   where public.port_offers(v_port, g.id)
     and not public.culture_refuses((select culture from public.ports where id = v_port), g.culture_mask)
     and world.daily_cap_remaining(v_player, v_port, g.id) >= 90
   order by (public.fleet_buy_capacity(v_fleet, g.id)->>'max_qty')::numeric desc, g.code limit 1;
  if v_a is null or (public.fleet_buy_capacity(v_fleet, v_a)->>'max_qty')::numeric < 20 then
    raise exception 'PROOF 10 FAILED: at % this house cannot take 20 t of any offered good; nothing below would be real', v_port_c;
  end if;
  perform cmd.do_buy(v_fleet, jsonb_build_object('good', v_a::text, 'qty', 12));
  select g.id, g.code, g.name, g.bulk into v_b, v_b_c, v_b_n, v_b_bulk
    from public.goods g
   where public.port_offers(v_port, g.id)
     and not public.culture_refuses((select culture from public.ports where id = v_port), g.culture_mask)
     and world.daily_cap_remaining(v_player, v_port, g.id) >= 90
     and g.id <> v_a
   order by (public.fleet_buy_capacity(v_fleet, g.id)->>'max_qty')::numeric desc, g.code limit 1;
  select g.id, g.code into v_c, v_c_c
    from public.goods g
   where public.port_offers(v_port, g.id)
     and not public.culture_refuses((select culture from public.ports where id = v_port), g.culture_mask)
     and world.daily_cap_remaining(v_player, v_port, g.id) >= 90
     and g.id not in (v_a, v_b)
   order by (public.fleet_buy_capacity(v_fleet, g.id)->>'max_qty')::numeric desc, g.code limit 1;
  if v_b is null or v_c is null
     or (public.fleet_buy_capacity(v_fleet, v_b)->>'max_qty')::numeric < 20
     or (public.fleet_buy_capacity(v_fleet, v_c)->>'max_qty')::numeric < 12 then
    raise exception 'PROOF 10 FAILED: at % with 12 t of % aboard there are not two more goods this house can take 20 / 12 t of (% / %)',
      v_port_c, v_a_c, coalesce(v_b_c, '-'), coalesce(v_c_c, '-');
  end if;
  v_lines := jsonb_build_array(jsonb_build_object('side', 'sell', 'good', v_a_c, 'qty', 5),
                               jsonb_build_object('side', 'buy',  'good', v_b_c, 'qty', 10));

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 1. A PREVIEW MOVES NOTHING.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select ducats into v_purse0 from public.players where id = v_player;
  select count(*) into v_events0 from public.events where player_id = v_player;
  v_cargo_a0 := public.fleet_cargo_qty(v_fleet, v_a_c);
  v_cargo_b0 := public.fleet_cargo_qty(v_fleet, v_b_c);
  select stock into v_stock_a0 from public.port_goods where port_id = v_port and good_id = v_a;
  select stock into v_stock_b0 from public.port_goods where port_id = v_port and good_id = v_b;
  select coalesce(sum(qty), 0) into v_td0 from public.trade_daily where player_id = v_player;
  v_pv := cmd.preview_basket(v_fleet, v_lines);
  if coalesce((v_pv->>'ok')::boolean, false) is not true or jsonb_array_length(v_pv->'estimate'->'lines') is distinct from 2 then
    raise exception 'PROOF 10 FAILED: preview_basket did not answer the two-line manifest: %', v_pv;
  end if;
  if (select ducats from public.players where id = v_player) <> v_purse0
     or public.fleet_cargo_qty(v_fleet, v_a_c) <> v_cargo_a0
     or public.fleet_cargo_qty(v_fleet, v_b_c) <> v_cargo_b0
     or (select count(*) from public.events where player_id = v_player) <> v_events0
     or (select stock from public.port_goods where port_id = v_port and good_id = v_a) <> v_stock_a0
     or (select stock from public.port_goods where port_id = v_port and good_id = v_b) <> v_stock_b0
     or (select coalesce(sum(qty), 0) from public.trade_daily where player_id = v_player) <> v_td0 then
    raise exception 'PROOF 10 FAILED: the preview moved something (purse % -> %, cargo % / %, events %)',
      v_purse0, (select ducats from public.players where id = v_player),
      public.fleet_cargo_qty(v_fleet, v_a_c), public.fleet_cargo_qty(v_fleet, v_b_c),
      (select count(*) from public.events where player_id = v_player);
  end if;
  raise notice 'PASS: MANIFEST_PREVIEW_MOVES_NOTHING — at % a preview of [SELL % 5, BUY % 10] answered 2 lines (net % d.) and left the purse at %, % / % t aboard, % events, the quay''s stock and the day''s volume exactly where they were',
    v_port_c, v_a_c, v_b_c, v_pv->'estimate'->'totals'->>'net', v_purse0, v_cargo_a0, v_cargo_b0, v_events0;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 2. THE LINES ARE THE VERBS.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  v_pa := cmd.preview(v_fleet, 'SELL ' || v_a_c || ' 5', null::jsonb);
  v_pb := cmd.preview(v_fleet, 'BUY ' || v_b_c || ' 10', null::jsonb);
  select l into v_la from jsonb_array_elements(v_pv->'estimate'->'lines') l where l->>'side' = 'sell';
  select l into v_lb from jsonb_array_elements(v_pv->'estimate'->'lines') l where l->>'side' = 'buy';
  if coalesce((v_pa->>'ok')::boolean, false) is not true or coalesce((v_pb->>'ok')::boolean, false) is not true
     or (v_la->>'total')::numeric        is distinct from (v_pa->'estimate'->>'total')::numeric
     or (v_la->>'avg_price')::numeric    is distinct from (v_pa->'estimate'->>'avg_price')::numeric
     or (v_la->>'profit')::numeric       is distinct from (v_pa->'estimate'->>'profit')::numeric
     or (v_la->>'mid_total')::numeric    is distinct from (v_pa->'estimate'->>'mid_total')::numeric
     or (v_la->>'tax_total')::numeric    is distinct from (v_pa->'estimate'->>'tax_total')::numeric
     or (v_la->>'spread_total')::numeric is distinct from (v_pa->'estimate'->>'spread_total')::numeric
     or (v_la->>'haggle_saved')::numeric is distinct from (v_pa->'estimate'->>'haggle_saved')::numeric
     or (v_lb->>'total')::numeric        is distinct from (v_pb->'estimate'->>'total')::numeric
     or (v_lb->>'avg_price')::numeric    is distinct from (v_pb->'estimate'->>'avg_price')::numeric
     or (v_lb->>'mid_total')::numeric    is distinct from (v_pb->'estimate'->>'mid_total')::numeric
     or (v_lb->>'tax_total')::numeric    is distinct from (v_pb->'estimate'->>'tax_total')::numeric
     or (v_lb->>'spread_total')::numeric is distinct from (v_pb->'estimate'->>'spread_total')::numeric
     or (v_lb->>'haggle_saved')::numeric is distinct from (v_pb->'estimate'->>'haggle_saved')::numeric then
    raise exception 'PROOF 10 FAILED: the manifest''s lines % / % are not cmd.preview''s % / %', v_la, v_lb, v_pa->'estimate', v_pb->'estimate';
  end if;
  raise notice 'PASS: MANIFEST_LINES_ARE_THE_VERBS — the SELL line (total %, avg %, profit %, mid %, tax %, spread %) and the BUY line (total %, avg %, mid %, tax %, spread %) equal cmd.preview''s SELL and BUY of the same orders to the hundredth',
    v_la->>'total', v_la->>'avg_price', v_la->>'profit', v_la->>'mid_total', v_la->>'tax_total', v_la->>'spread_total',
    v_lb->>'total', v_lb->>'avg_price', v_lb->>'mid_total', v_lb->>'tax_total', v_lb->>'spread_total';

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 3. THE SALE PAYS FOR THE PURCHASE. The purse is set one ducat short of the buy alone.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  v_buy_total := (v_lb->>'total')::bigint;
  -- Through the one money mover, with its own ledger row, so the purse invariant still holds and
  -- tick_reconcile can be asked afterwards (a bare UPDATE would leave the ledger a liar).
  perform public.credit(v_player, 'PROOF_DRAIN',
    (v_buy_total - 1) - (select ducats from public.players where id = v_player),
    public.emit_event(v_player, 'PROOF_DRAIN', jsonb_build_object('to', v_buy_total - 1)));
  select version into v_ver from public.fleets where id = v_fleet;
  v_bad := cmd.trade_basket(v_fleet, jsonb_build_array(jsonb_build_object('side', 'buy', 'good', v_b_c, 'qty', 10)), v_ver);
  if coalesce((v_bad->>'ok')::boolean, true)
     or v_bad->>'error_code' is distinct from 'E_INSUFFICIENT_FUNDS'
     or v_bad->'figures'->>'unit' is distinct from 'ducats'
     or (v_bad->'figures'->>'have')::numeric <> v_buy_total - 1
     or (v_bad->'figures'->>'need')::numeric <> v_buy_total
     or (v_bad->>'line')::int is distinct from 0 then
    raise exception 'PROOF 10 FAILED: with % d. against a % d. buy the lone BUY was not refused E_INSUFFICIENT_FUNDS in ducats at line 0: %', v_buy_total - 1, v_buy_total, v_bad;
  end if;
  select ducats into v_purse0 from public.players where id = v_player;
  select count(*) into v_events0 from public.events where player_id = v_player;
  v_res := cmd.trade_basket(v_fleet, v_lines, v_ver);
  if coalesce((v_res->>'ok')::boolean, false) is not true then
    raise exception 'PROOF 10 FAILED: the same BUY behind a SELL on one manifest was refused: %', v_res;
  end if;
  select ducats into v_purse1 from public.players where id = v_player;
  if v_purse1 is distinct from v_purse0 + (v_res->'totals'->>'net')::bigint or (v_res->'totals'->>'bought')::bigint is distinct from v_buy_total then
    raise exception 'PROOF 10 FAILED: the manifest landed but the purse went % -> % against a net of %', v_purse0, v_purse1, v_res->'totals'->>'net';
  end if;
  raise notice 'PASS: MANIFEST_SELLS_FUND_BUYS — with % d. in the purse, BUY % 10 (% d.) alone was E_INSUFFICIENT_FUNDS (have %, need %, ducats); [SELL % 5, BUY % 10] on one manifest landed, the sale''s % d. arriving first, and the purse closed at % d.',
    v_buy_total - 1, v_b_c, v_buy_total, v_bad->'figures'->>'have', v_bad->'figures'->>'need', v_a_c, v_b_c, v_res->'totals'->>'sold', v_purse1;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 5. THE RECEIPT IS THE LEDGER (the manifest that just landed).
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select l into v_la from jsonb_array_elements(v_res->'lines') l where l->>'side' = 'sell';
  select l into v_lb from jsonb_array_elements(v_res->'lines') l where l->>'side' = 'buy';
  if (select count(*) from public.events where player_id = v_player) <> v_events0 + 2 then
    raise exception 'PROOF 10 FAILED: a 2-line manifest wrote % event(s)', (select count(*) from public.events where player_id = v_player) - v_events0;
  end if;
  select count(*) into v_n from public.events e
   where e.player_id = v_player and e.kind = 'SOLD' and e.payload->>'good' = v_a_n
     and (e.payload->>'qty')::numeric = (v_la->>'qty')::numeric
     and (e.payload->>'total')::bigint = (v_la->>'total')::bigint
     and (e.payload->>'profit')::bigint = (v_la->>'profit')::bigint
     and (e.payload->>'mid_total')::numeric = (v_la->>'mid_total')::numeric
     and (e.payload->>'tax_total')::numeric = (v_la->>'tax_total')::numeric
     and (e.payload->>'spread_total')::numeric = (v_la->>'spread_total')::numeric;
  if v_n <> 1 then
    raise exception 'PROOF 10 FAILED: % SOLD event(s) carry the receipt''s SELL line %', v_n, v_la;
  end if;
  select count(*) into v_n from public.events e
   where e.player_id = v_player and e.kind = 'BOUGHT' and e.payload->>'good' = v_b_n
     and (e.payload->>'qty')::numeric = (v_lb->>'qty')::numeric
     and (e.payload->>'total')::bigint = (v_lb->>'total')::bigint
     and (e.payload->>'mid_total')::numeric = (v_lb->>'mid_total')::numeric
     and (e.payload->>'tax_total')::numeric = (v_lb->>'tax_total')::numeric
     and (e.payload->>'spread_total')::numeric = (v_lb->>'spread_total')::numeric;
  if v_n <> 1 then
    raise exception 'PROOF 10 FAILED: % BOUGHT event(s) carry the receipt''s BUY line %', v_n, v_lb;
  end if;
  select l.balance_after into v_sold_bal from public.ledger l join public.events e on e.id = l.ref_event_id
   where l.player_id = v_player and e.kind = 'SOLD' and e.payload->>'good' = v_a_n;
  select l.balance_after into v_bought_bal from public.ledger l join public.events e on e.id = l.ref_event_id
   where l.player_id = v_player and e.kind = 'BOUGHT' and e.payload->>'good' = v_b_n;
  if (v_res->'purse'->>'before')::bigint is distinct from v_purse0 or (v_res->'purse'->>'after')::bigint is distinct from v_purse1
     or v_sold_bal is distinct from v_purse0 + (v_la->>'total')::bigint
     or v_bought_bal is distinct from v_purse1
     or (select sum(l.ducats_delta) from public.ledger l join public.events e on e.id = l.ref_event_id
          where l.player_id = v_player
            and ((e.kind = 'SOLD' and e.payload->>'good' = v_a_n) or (e.kind = 'BOUGHT' and e.payload->>'good' = v_b_n)))
        is distinct from (v_res->'totals'->>'net')::bigint then
    raise exception 'PROOF 10 FAILED: the receipt (purse %, net %) is not the ledger (% -> % -> %)',
      v_res->'purse', v_res->'totals'->>'net', v_purse0, v_sold_bal, v_bought_bal;
  end if;
  perform public.tick_reconcile();
  raise notice 'PASS: MANIFEST_RECEIPT_IS_THE_LEDGER — the SOLD and BOUGHT events carry the two lines'' qty / total / profit / mid / tax / spread exactly, the ledger ran % -> % -> % (sale first, purchase last), Σ of the two rows is the receipt''s net % and the purse read back is purse.after %; tick_reconcile agrees',
    v_purse0, v_sold_bal, v_bought_bal, v_res->'totals'->>'net', v_res->'purse'->>'after';

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 6. XP IS HONEST — and the house screen reads the same number.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  if (v_res->'totals'->>'bought')::numeric + (v_res->'totals'->>'sold')::numeric < k_per_point then
    raise exception 'PROOF 10 FAILED: the manifest turned over less than one point''s worth (% d. against %/point); delta could be 0 and this marker would be vacuous',
      (v_res->'totals'->>'bought')::numeric + (v_res->'totals'->>'sold')::numeric, k_per_point;
  end if;
  if (v_res->'trading'->>'delta')::int < 1
     or (v_res->'trading'->>'delta')::int is distinct from (v_res->'trading'->>'points_after')::int - (v_res->'trading'->>'points_before')::int
     or (v_res->'trading'->>'points_after')::int is distinct from (public.player_progress(v_player)->'trading'->>'points')::int
     or (v_res->'trading'->>'points_after')::int is distinct from (world.player()->'player'->'levels'->'trading'->>'points')::int
     or (v_res->'trading'->>'level_after')::int is distinct from (world.player()->'player'->'levels'->'trading'->>'level')::int then
    raise exception 'PROOF 10 FAILED: trading % on the receipt is not what player_progress / world.player() read (% / %)',
      v_res->'trading', public.player_progress(v_player)->'trading', world.player()->'player'->'levels'->'trading';
  end if;
  raise notice 'PASS: MANIFEST_XP_IS_HONEST — trading % -> % (+%, level %) on the receipt is public.player_progress''s reading, and world.player().levels.trading.points reads the same %',
    v_res->'trading'->>'points_before', v_res->'trading'->>'points_after', v_res->'trading'->>'delta', v_res->'trading'->>'level_after',
    world.player()->'player'->'levels'->'trading'->>'points';

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 4. ATOMIC. The BUY asks one tun more than the hold takes once the sale has made room.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select ducats into v_purse0 from public.players where id = v_player;
  select count(*) into v_events0 from public.events where player_id = v_player;
  v_cargo_a0 := public.fleet_cargo_qty(v_fleet, v_a_c);
  v_cargo_b0 := public.fleet_cargo_qty(v_fleet, v_b_c);
  select stock into v_stock_a0 from public.port_goods where port_id = v_port and good_id = v_a;
  select stock into v_stock_b0 from public.port_goods where port_id = v_port and good_id = v_b;
  select coalesce(sum(qty), 0) into v_td0 from public.trade_daily where player_id = v_player;
  select version into v_ver from public.fleets where id = v_fleet;
  v_over := floor((public.fleet_free_hold(v_fleet) + 3 * v_a_bulk) / v_b_bulk) + 1;
  v_bad := cmd.trade_basket(v_fleet, jsonb_build_array(
             jsonb_build_object('side', 'sell', 'good', v_a_c, 'qty', 3),
             jsonb_build_object('side', 'buy',  'good', v_b_c, 'qty', v_over)), v_ver);
  if coalesce((v_bad->>'ok')::boolean, true) or v_bad->>'error_code' is distinct from 'E_HOLD_FULL'
     or (v_bad->>'line')::int is distinct from 1 or v_bad->'figures'->>'unit' is distinct from 't' then
    raise exception 'PROOF 10 FAILED: [SELL % 3, BUY % %] was not refused E_HOLD_FULL at line 1: %', v_a_c, v_b_c, v_over, v_bad;
  end if;
  if (select ducats from public.players where id = v_player) <> v_purse0
     or public.fleet_cargo_qty(v_fleet, v_a_c) <> v_cargo_a0
     or public.fleet_cargo_qty(v_fleet, v_b_c) <> v_cargo_b0
     or (select count(*) from public.events where player_id = v_player) <> v_events0
     or (select stock from public.port_goods where port_id = v_port and good_id = v_a) <> v_stock_a0
     or (select stock from public.port_goods where port_id = v_port and good_id = v_b) <> v_stock_b0
     or (select coalesce(sum(qty), 0) from public.trade_daily where player_id = v_player) <> v_td0
     or (select version from public.fleets where id = v_fleet) <> v_ver then
    raise exception 'PROOF 10 FAILED: the refused manifest moved something (purse % -> %, % t of % aboard (was %), events % (was %), version % (was %))',
      v_purse0, (select ducats from public.players where id = v_player),
      public.fleet_cargo_qty(v_fleet, v_a_c), v_a_c, v_cargo_a0,
      (select count(*) from public.events where player_id = v_player), v_events0,
      (select version from public.fleets where id = v_fleet), v_ver;
  end if;
  -- THE CONTROL: the same two verbs, no savepoint, the refusal swallowed per line.
  begin
    perform cmd.do_sell(v_fleet, jsonb_build_object('good', v_a::text, 'qty', 3));
    begin
      perform cmd.do_buy(v_fleet, jsonb_build_object('good', v_b::text, 'qty', v_over));
    exception when others then
      v_ctrl_seen := true;
    end;
    v_ctrl_a := public.fleet_cargo_qty(v_fleet, v_a_c);
    raise exception '__P10_CONTROL__';
  exception when others then
    if sqlerrm <> '__P10_CONTROL__' then raise; end if;
  end;
  if not v_ctrl_seen or v_ctrl_a is distinct from v_cargo_a0 - 3 or public.fleet_cargo_qty(v_fleet, v_a_c) <> v_cargo_a0 then
    raise exception 'PROOF 10 FAILED: the non-atomic control did not show the defect (refused %, % t after, expected %, now %)',
      v_ctrl_seen, v_ctrl_a, v_cargo_a0 - 3, public.fleet_cargo_qty(v_fleet, v_a_c);
  end if;
  raise notice 'PASS: MANIFEST_IS_ATOMIC — [SELL % 3, BUY % %] was refused E_HOLD_FULL on line 1 and the sale on line 0 was unwound with it: purse %, % t of % aboard, % events, stock, volume and version % all unchanged; the same two verbs run without the savepoint left % t aboard (the defect, thrown away)',
    v_a_c, v_b_c, v_over, v_purse0, v_cargo_a0, v_a_c, v_events0, v_ver, v_ctrl_a;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 7. ONE LINE PER GOOD, and the shape refusals — each leaving the world alone.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  v_bad := cmd.trade_basket(v_fleet, jsonb_build_array(
             jsonb_build_object('side', 'buy',  'good', v_b_c, 'qty', 2),
             jsonb_build_object('side', 'sell', 'good', v_b_c, 'qty', 1)), v_ver);
  if coalesce((v_bad->>'ok')::boolean, true) or v_bad->>'error_code' is distinct from 'E_MANIFEST_DUPLICATE' or (v_bad->>'line')::int is distinct from 1 then
    raise exception 'PROOF 10 FAILED: % on two lines was not E_MANIFEST_DUPLICATE at line 1: %', v_b_c, v_bad;
  end if;
  v_hag := cmd.trade_basket(v_fleet, '[]'::jsonb, v_ver);
  v_pa  := cmd.preview_basket(v_fleet, jsonb_build_array(
             jsonb_build_object('side', 'sell', 'good', v_a_c, 'qty', 1),
             jsonb_build_object('side', 'swap', 'good', v_b_c, 'qty', 1)));
  v_pb  := cmd.preview_basket(v_fleet, jsonb_build_array(jsonb_build_object('side', 'buy', 'good', 'no_such_good_p10', 'qty', 1)));
  v_pv  := cmd.preview_basket(v_fleet, jsonb_build_array(jsonb_build_object('side', 'sell', 'good', v_a_c, 'qty', 0.5)));
  if coalesce((v_hag->>'ok')::boolean, true) or v_hag->>'error_code' is distinct from 'E_MANIFEST_EMPTY' or v_hag->'line' is distinct from 'null'::jsonb
     or coalesce((v_pa->>'ok')::boolean, true) or v_pa->>'error_code' is distinct from 'E_MANIFEST_LINE' or (v_pa->>'line')::int is distinct from 1
     or coalesce((v_pb->>'ok')::boolean, true) or v_pb->>'error_code' is distinct from 'E_NO_SUCH_GOOD' or (v_pb->>'line')::int is distinct from 0
     or coalesce((v_pv->>'ok')::boolean, true) or v_pv->>'error_code' is distinct from 'E_MANIFEST_LINE' or (v_pv->>'line')::int is distinct from 0 then
    raise exception 'PROOF 10 FAILED: the shape refusals are not what 0083 declares: % / % / % / %', v_hag, v_pa, v_pb, v_pv;
  end if;
  if (select ducats from public.players where id = v_player) <> v_purse0
     or (select count(*) from public.events where player_id = v_player) <> v_events0
     or (select version from public.fleets where id = v_fleet) <> v_ver then
    raise exception 'PROOF 10 FAILED: a refused-by-shape manifest moved something';
  end if;
  raise notice 'PASS: MANIFEST_ONE_LINE_PER_GOOD — [BUY % 2, SELL % 1] is E_MANIFEST_DUPLICATE at line 1 ("%"); [] is E_MANIFEST_EMPTY with no line; a side of ''swap'' is E_MANIFEST_LINE at line 1; an unknown code is E_NO_SUCH_GOOD at line 0; half a tun is E_MANIFEST_LINE at line 0 (whole tuns only); purse, events and version untouched by all five',
    v_b_c, v_b_c, v_bad->>'error_message';

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 8. THE BREAKDOWN ADDS UP — and a bargain WON through cmd.haggle shows as haggle_saved.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  if abs((v_lb->>'mid_total')::numeric + (v_lb->>'tax_total')::numeric + (v_lb->>'spread_total')::numeric - (v_lb->>'total')::numeric)
       > 0.005 * (v_lb->>'qty')::numeric + 0.5
     or abs((v_la->>'mid_total')::numeric - (v_la->>'tax_total')::numeric - (v_la->>'spread_total')::numeric - (v_la->>'total')::numeric)
       > 0.005 * (v_la->>'qty')::numeric + 0.5
     or (v_lb->>'haggle_saved')::numeric is distinct from 0 or (v_la->>'haggle_saved')::numeric is distinct from 0 then
    raise exception 'PROOF 10 FAILED: the landed lines'' breakdowns do not add up: BUY % / SELL %', v_lb, v_la;
  end if;
  -- The purse drained for marker 3 is refilled through the same mover, so the bargained buy is
  -- refused by nothing but its own gates. Then certainty, as proof 06 sets it, so the bargain is
  -- about its SIZE and not about luck.
  perform public.credit(v_player, 'PROOF_REFILL', 8000, public.emit_event(v_player, 'PROOF_REFILL', '{}'::jsonb));
  update public.world_config set value = to_jsonb(1.0) where key = 'haggle_base_success';
  update public.world_config set value = to_jsonb(1.0) where key = 'haggle_success_max';
  select * into v_q from world.quote(v_port, v_c, 10, 'buy', null, v_fleet);
  v_hag := cmd.haggle(v_fleet, v_c, 'buy');
  if coalesce((v_hag->>'won')::boolean, false) is not true or (v_hag->>'concession')::numeric <= 0 then
    raise exception 'PROOF 10 FAILED: a certain bargain on % did not win: %', v_c_c, v_hag;
  end if;
  v_pv := cmd.preview_basket(v_fleet, jsonb_build_array(jsonb_build_object('side', 'buy', 'good', v_c_c, 'qty', 10)));
  if coalesce((v_pv->>'ok')::boolean, false) is not true then
    raise exception 'PROOF 10 FAILED: the bargained BUY of % was refused: %', v_c_c, v_pv;
  end if;
  select l into v_lb from jsonb_array_elements(v_pv->'estimate'->'lines') l;
  if (v_lb->>'haggle_saved')::numeric <= 0
     or (v_lb->>'concession_spent')::numeric is distinct from (v_hag->>'concession')::numeric
     or abs((v_lb->>'haggle_saved')::numeric - (v_q.total - (v_lb->>'total')::numeric)) > 1
     or (v_pv->'estimate'->'totals'->>'haggle_saved')::numeric is distinct from (v_lb->>'haggle_saved')::numeric then
    raise exception 'PROOF 10 FAILED: with a won concession of % the BUY of 10 t of % says haggle_saved % against an unbargained quote of % and a line total of %',
      v_hag->>'concession', v_c_c, v_lb->>'haggle_saved', v_q.total, v_lb->>'total';
  end if;
  raise notice 'PASS: MANIFEST_BREAKDOWN_ADDS_UP — BUY % + % + % ~ % and SELL % - % - % ~ % within the unit rounding, both with 0 saved; after cmd.haggle WON a concession of % on %, a previewed BUY 10 shows haggle_saved % d. against the unbargained % d. quote (line total %), and the receipt''s totals carry the same figure',
    (select l->>'mid_total' from jsonb_array_elements(v_res->'lines') l where l->>'side' = 'buy'),
    (select l->>'tax_total' from jsonb_array_elements(v_res->'lines') l where l->>'side' = 'buy'),
    (select l->>'spread_total' from jsonb_array_elements(v_res->'lines') l where l->>'side' = 'buy'),
    (select l->>'total' from jsonb_array_elements(v_res->'lines') l where l->>'side' = 'buy'),
    v_la->>'mid_total', v_la->>'tax_total', v_la->>'spread_total', v_la->>'total',
    v_hag->>'concession', v_c_c, v_lb->>'haggle_saved', v_q.total, v_lb->>'total';

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 9. THE VERSION GUARD.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select version into v_ver from public.fleets where id = v_fleet;
  v_bad := cmd.trade_basket(v_fleet, jsonb_build_array(jsonb_build_object('side', 'sell', 'good', v_a_c, 'qty', 1)), v_ver - 1);
  if coalesce((v_bad->>'ok')::boolean, true) or v_bad->>'error_code' is distinct from 'E_STALE' or (v_bad->>'version')::int is distinct from v_ver then
    raise exception 'PROOF 10 FAILED: version % against a fleet at % was not E_STALE: %', v_ver - 1, v_ver, v_bad;
  end if;
  v_res := cmd.trade_basket(v_fleet, jsonb_build_array(jsonb_build_object('side', 'sell', 'good', v_a_c, 'qty', 1)), v_ver);
  if coalesce((v_res->>'ok')::boolean, false) is not true or (v_res->>'version')::int is distinct from v_ver + 1
     or (select version from public.fleets where id = v_fleet) <> v_ver + 1 then
    raise exception 'PROOF 10 FAILED: a manifest at the right version % did not land at % : %', v_ver, v_ver + 1, v_res;
  end if;
  raise notice 'PASS: MANIFEST_VERSION_GUARD — version % against a fleet at % is E_STALE (envelope names version %); at % the manifest landed and the fleet is at %; the refused manifest of marker 4 left the version where it was',
    v_ver - 1, v_ver, v_bad->>'version', v_ver, v_res->>'version';

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- 10. THROUGH THE DOOR A BROWSER USES.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select version into v_ver from public.fleets where id = v_fleet;
  begin
    set local role authenticated;
    v_pv := cmd.preview_basket(v_fleet, jsonb_build_array(jsonb_build_object('side', 'sell', 'good', v_a_c, 'qty', 1)));
    if coalesce((v_pv->>'ok')::boolean, false) is not true then
      raise exception 'PROOF 10 FAILED: as authenticated, preview_basket refused: %', v_pv;
    end if;
    v_res := cmd.trade_basket(v_fleet, jsonb_build_array(jsonb_build_object('side', 'sell', 'good', v_a_c, 'qty', 1)), v_ver);
    if coalesce((v_res->>'ok')::boolean, false) is not true or (v_res->>'version')::int is distinct from v_ver + 1 then
      raise exception 'PROOF 10 FAILED: as authenticated, trade_basket refused: %', v_res;
    end if;
    -- Another house's fleet: refused by the skins, never reaching a verb.
    v_pa := cmd.preview_basket(v_other_f, jsonb_build_array(jsonb_build_object('side', 'buy', 'good', v_a_c, 'qty', 1)));
    v_pb := cmd.trade_basket(v_other_f, jsonb_build_array(jsonb_build_object('side', 'buy', 'good', v_a_c, 'qty', 1)), null);
    if coalesce((v_pa->>'ok')::boolean, true) or v_pa->>'error_code' is distinct from 'E_NO_SUCH_FLEET'
       or coalesce((v_pb->>'ok')::boolean, true) or v_pb->>'error_code' is distinct from 'E_NO_SUCH_FLEET' then
      raise exception 'PROOF 10 FAILED: another house''s fleet was not refused (% / %)', v_pa, v_pb;
    end if;
    -- The one body is not the client's.
    v_err := null;
    begin
      perform cmd.run_manifest(v_fleet, '[]'::jsonb);
    exception when insufficient_privilege then v_err := 'refused';
    end;
    if v_err is null then
      raise exception 'PROOF 10 FAILED: authenticated executed cmd.run_manifest, which is not a client entry point';
    end if;
    set local role none;
  exception when others then
    set local role none;
    raise;
  end;
  -- And anon may open neither door. The schema door is opened first, as proof 03 does, so the
  -- FUNCTION ACL is what is under test.
  grant usage on schema cmd to anon;
  v_n := 0;
  begin
    set local role anon;
    begin
      perform cmd.trade_basket(v_fleet, '[]'::jsonb, null);
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate;
      if v_state = '42501' then v_n := v_n + 1; end if;
    end;
    begin
      perform cmd.preview_basket(v_fleet, '[]'::jsonb);
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate;
      if v_state = '42501' then v_n := v_n + 1; end if;
    end;
    begin
      perform cmd.run_manifest(v_fleet, '[]'::jsonb);
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate;
      if v_state = '42501' then v_n := v_n + 1; end if;
    end;
    set local role none;
  exception when others then
    set local role none;
    raise;
  end;
  if v_n <> 3 then
    raise exception 'PROOF 10 FAILED: anon was refused 42501 on only % of the 3 manifest functions', v_n;
  end if;
  raise notice 'PASS: MANIFEST_CLIENT_PATH — as authenticated, preview_basket answered and trade_basket landed a SELL (version % -> %); another house''s fleet was E_NO_SUCH_FLEET at BOTH doors (one code for one screen); cmd.run_manifest was refused 42501; as anon (schema door opened first) trade_basket, preview_basket and run_manifest were all 42501',
    v_ver, v_res->>'version';
end $$;
