-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0019 — THE QUAY NAMES THE PORT THAT PAYS
--        world.trade_routes() — the read that answers the question this game could not answer:
--        WHERE is this good worth more than it is here, and what would that voyage be worth?
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, AS MEASURED ─────────────────────────────────────────────────────────────────────
-- A playability audit played the real game, followed MARKET's own printed rule — "Below 90, buy.
-- Above 110, sell." — bought 55 tuns of salt at Lisboa, sailed 248 nm to Cádiz and sold: net
-- MINUS 199 ducats, plus wages, for sixteen minutes of play.
--
-- The cause is structural and it is the metric the whole screen is built on. %NBR is "this port's
-- mid as a percentage of the ports within 600 nm" (0009:60). It is a LOCAL index, and it is
-- honest about that — but it cannot name a destination, and it cannot predict a profit, because a
-- profit is a pair of ports and a tax and a spread and a stepped book. Both facts were measured on
-- this chain, on 2026-08-22, on PostgreSQL 18.3 (PGlite 0.5.5):
--
--   1. THE BANDS ALMOST NEVER FIRE. Over a 30-port x 70-good sample (2,100 pairs): 145 read
--      "buy" (< 90), THIRTEEN read "sell" (> 110), 1,872 read "hold". A player at Lisboa is shown
--      seventy rows and no SELL at all. Every one-leg neighbour of Lisboa is inside 600 nm, so the
--      whole cluster shares a denominator and reads about the same by construction.
--   2. WORSE — WHERE THE BAND DOES FIRE, IT CAN BE WRONG ABOUT MONEY. Salt at Lisboa: mid 29.19,
--      %NBR 95.7. Salt at Porto, one 195 nm leg away: mid 32.69, %NBR 109.6 — a SELL, by the
--      screen's own rule. Buy 55 tuns at Lisboa (1,672 d.) and sell them at Porto and you receive
--      1,595 d. A LOSS OF 77 DUCATS on a row the game marks "sell". Seville, %NBR 108.9: -70.
--      The tax, the spread and the price impact of the order itself eat a 14-point mid gap whole.
--      The port that actually pays is Ponta Delgada, 781 nm out: +231 d. Nothing on the Lisboa
--      screen could ever have said so.
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
--   world.market(port)          0009:115 — one port per call, no comparison anywhere in it.
--   world.pct_of_neighbours     0009:39  — the local index, called FOUR times per good by
--                                          world.market (0009:130, 136, 137, 138). The whole read
--                                          measured 800 ms for one port's 70 rows.
--   MarketScreen's "How to read it" card — printed "Below 90, buy. Above 110, sell." as if it were
--                                          trade advice. It is a price index, and this file's
--                                          companion client change stops it posing as advice.
--
-- ── SO WHAT %NBR IS, AND WHAT IT IS NOT (the decision, stated) ──────────────────────────────────
-- %NBR IS KEPT, AND ITS DEFINITION IS UNCHANGED. It answers "is this good cheap in this
-- neighbourhood?" and that is a real question with one honest answer. It is NOT widened and it is
-- NOT joined by a second index:
--   * WIDENING THE RADIUS DOES NOT HELP. The failure above is not that the neighbourhood is too
--     small; it is that a ratio of MIDS can never predict a profit, at any radius, because it
--     contains neither the two ports' taxes nor their spreads nor the price impact of the order.
--     A 600 nm and a 6,000 nm index would both have called Porto a SELL.
--   * A SECOND INDEX WOULD BE A SECOND AUTHORITY for "is this dear or cheap", which is the one
--     thing docs/NO_SPAGHETTI.md §1 forbids.
-- What is added is not another index. It is the answer to a DIFFERENT question, priced in ducats
-- through world.quote — the same function the money moves through — so the number offered and the
-- number charged cannot disagree.
--
-- AND THE RADIUS AND THE TWO THRESHOLDS BECOME KNOBS, because they were duplicated. 600 lived at
-- 0009:61 AND at src/features/market/marketRows.ts:31; 90/110 lived at 0009:137-138 AND at
-- marketRows.ts:26-27. Four numbers, two authorities each, and the client's copies are captions
-- that must agree with the server or the block headings lie. They are knobs now, world.snapshot()
-- serves them, and the client prints what it is served.
--
-- ── ONE AUTHORITY PER CONCEPT — the three folds this file had to make first ─────────────────────
--
--   1. voyage.reach_from(from, max_ports, stop_at) — THE shortest path over the leg graph.
--      SUPERSEDES nothing by deletion: 0006:141 voyage.route_direct is re-cut to COMPOSE it.
--      Ranking destinations needs the distance to MANY ports; route_direct answered ONE. Writing a
--      second Dijkstra beside it would have been two authorities for "how far is it by sea", and
--      they could disagree — which is exactly how a quay quotes 195 nm for a voyage that sails
--      248. Dijkstra already computes every distance on the way to one; this exposes that, and
--      route_direct walks the predecessors back. Both bounds (max_ports, stop_at) are pure early
--      termination: Dijkstra settles nodes in distance order, so anything returned is FINAL.
--
--   2. voyage.sail_refusal(fleet, dest, nm) — THE answer to "may this fleet sail there?".
--      SUPERSEDES the four inline gates of cmd.do_sail (0007:368-403: crew, flagship, draft, ice,
--      endurance), which now composes it. Found the expensive way, in this file's own probe: the
--      ORDER MATTERS AND IT IS PRESERVED: the gate is asked twice, once before the router with a
--      distance of 0 (so an undocked fleet is still refused E_NOT_DOCKED rather than E_NO_ROUTE,
--      which is what she would get for having no port to route FROM) and once after, with the
--      distance, for the endurance clause. Two calls to one authority is composition; two copies
--      of the rule would not be.
--      Found the expensive way, in this file's own probe: the
--      first draft of trade_routes recommended 20 tuns of porcelain to Gorée for +2,163 d., and
--      cmd.issue refused the SAIL with E_ENDURANCE — a 14-day route against 15 days of stores and
--      a 1.15 margin. A quay that names a port the order will refuse is the same defect this file
--      exists to fix, one layer up. With the gate composed, the recommendation is SAILABLE by
--      construction, and the migration proves it by sailing it.
--
--   3. world.market computes %NBR ONCE per good, not four times.
--
-- ── HOW IT BOUNDS ITS OWN COST ──────────────────────────────────────────────────────────────────
-- 214 ports x 70 goods is not a query anybody runs per keystroke. The scan is bounded in four
-- named places, every one of them a knob, and the payload REPORTS the bounds it used:
--
--   route_scan_max_legs   2    destinations within N SAILED legs of here
--   route_scan_max_ports  120  and never more than the N nearest by sea (the Dijkstra stops there)
--   route_scan_goods      70   the cap on goods PRICED — see the two-stage note below
--   route_scan_keep       3    destinations per good that survive the shortlist and get priced
--                              (3 is not a guess: at 3, the shortlist matched an exhaustive scan
--                               at every port measured — see below)
--   route_probe_tuns      50   the quantity assumed when no fleet is named
--
-- TWO STAGES.
--   Stage 1 SHORTLISTS with world.mid_price — one call per (good, destination) in range, reading
--   the price authority rather than re-deriving it — and keeps the route_scan_keep dearest
--   destinations per good. A shortlist is not an answer and this file never reports one.
--   Stage 2 PRICES what survived, end to end, through world.quote — one BUY quote per good (the
--   buy side does not depend on the destination, so it is not paid per candidate) and one SELL
--   quote per surviving (good, destination) pair. EVERY NUMBER REPORTED COMES FROM THAT.
--
-- THE FIRST DRAFT SHORTLISTED ON AUTHORED AFFINITY INSTEAD, because that is free and because
-- 0009:313-315 uses exactly that trick for its own probe. It was measured against an EXHAUSTIVE
-- scan — every good against every one-leg destination, priced through the same quotes — and it
-- LOST TRADES: at Alexandria it offered 591 d. where the exhaustive best was 740 (indigo to
-- Tripoli, on another run 827 against 751). Affinity is one term of five in world.mid_price, and
-- a destination with a slightly lower affinity but a fuller warehouse or a lower commerce discount
-- can pay more. The mid-price shortlist matched the exhaustive best at every port tested, at
-- keep = 3, for about 160 ms. `05_first_voyage_balance.sql` now runs that exhaustive control on
-- every proof run, so the cheap stage can never quietly degrade again.
--
-- COMPLEXITY: O(V^2) for the bounded Dijkstra (V = min(ports, route_scan_max_ports)), plus
-- O(goods x ports) of column arithmetic with no function calls, plus AT MOST
-- goods + goods x route_scan_keep calls to world.quote — independent of how many ports are in
-- range. MEASURED on this machine (PGlite 0.5.5 / PostgreSQL 18.3, 214 ports, 782 legs, 70 goods),
-- from Lisboa at 2 legs (18 destinations in range):
--
--   voyage.reach_from(LIS), unbounded, all 213 ports          15-23 ms
--   world.trade_routes(LIS, no fleet, 2 legs, all goods)     ~290 ms   (70 buy + ~170 sell quotes)
--   world.trade_routes(LIS, WITH fleet, 2 legs, all goods)   ~380 ms   (+ fleet_buy_capacity/good)
--   world.market(LIS) BEFORE this file                       ~800 ms   (four %NBR walks per good)
--   world.market(LIS) after                                  ~245 ms   (one, behind a CTE fence)
--
-- So the prices now cost ~245 ms where they cost ~800, and the comparison the game never had costs
-- a further ~380: MARKET reads BOTH for about 630 ms where it read the prices alone for 800. On real
-- PostgreSQL rather than WebAssembly both figures are considerably smaller; PGlite is the shipping
-- runtime for local play, so it is the one measured here.
--
-- ── TWO QUESTIONS, ONE READ ─────────────────────────────────────────────────────────────────────
-- `p_to` pins the destination. Left null the read answers "where is any of this worth more than it
-- is here?"; given a port it answers "what should I carry THERE?" — the question a captain already
-- bound somewhere actually has, and the one `04_first_session.sql` asks to choose a return cargo.
-- It is the same shortlist, the same quotes and the same sail gate over a set of one, because a
-- second function for it would have been a second author of all three at once. With `p_to` the
-- port cap and the leg cap are both dropped: the caller has named the only destination there is.
--
-- ── THE QUANTITY IS STATED, NEVER GUESSED ───────────────────────────────────────────────────────
-- Profit depends on quantity, because the book is stepped (§G.2). So the payload carries
-- `basis.qty_from`:
--   'fleet'   — a fleet was named AND is lying at this port, so every row is priced at
--               public.fleet_buy_capacity(fleet, good).max_qty: the real number, bound by hold,
--               stock, the daily cap and THE PURSE, from the one authority that already answers
--               that question for the Command tab.
--   'default' — no fleet is lying here, so every row is priced at route_probe_tuns (50) capped by
--               the port's stock, and the payload says so.
--
-- ── WHAT THIS FILE DELIBERATELY DOES NOT DO ─────────────────────────────────────────────────────
--   * IT DOES NOT FORECAST WAGES. Wages are paid per settled voyage-day inside voyage.settle's day
--     loop (0007:944-946) and they are real — the probe below sails a 195 nm leg and the crew takes
--     16 d. of a 288 d. margin. But a forecast that recomputed that rule would be a SECOND author
--     of it, and folding it means re-cutting a 200-line function that also owns storms, calms and
--     pirates. So this read reports exactly what world.quote will charge and pay, calls it the
--     trade's MARGIN rather than the voyage's net, and prints `days` beside it so the exposure is
--     visible. Naming the limit is the honest half; inventing the number would not be.
--   * IT DOES NOT MODEL THE SPEED SHE WILL HAVE ONCE LOADED. voyage.sail_refusal is asked at her
--     CURRENT lading, and cargo slows a ship (voyage.ship_speed, 0006:352 — `1 - load_speed_penalty
--     x fill`). So `days` is her days as she lies now, and a route within a few per cent of her
--     endurance may still be refused after the cargo is aboard. That refusal arrives with
--     PROVISION as its fix (§F.5) and the trade is still there afterwards. The alternative was to
--     re-derive ship_speed at a hypothetical lading, which is a second author of the speed rule
--     for a three-per-cent correction; the honest half is naming it here.
--   * IT DOES NOT TOUCH world.pct_of_neighbours' DEFINITION, only where its radius is written.
--   * IT DOES NOT CHANGE A PRICE. No affinity, no stock, no drift, no spread, no tax moves here,
--     so proofs 04 and 05 measure the same economy they measured yesterday.
--   * IT DOES NOT RE-SEED STOCK. See the note on the STOCK column at the foot of this header.
--
-- ── THE THREE DEAD MARKET COLUMNS (D1), DECIDED ─────────────────────────────────────────────────
-- Measured here: ALL 14,980 port_goods rows read stock_band 6, because 0005:265 seeds
-- stock = stock_target and 0010's regeneration CLAMPS AT THE TARGET — `least(pg.stock_target, ...)`.
-- So `least(1.0, stock/stock_target)` can never exceed 1 by construction: a glut is not a state
-- this world has. The band is not broken; the world's resting state is full.
--   * NOT RE-SEEDED. stock is an input to world.mid_price, so scattering it would move all 14,980
--     prices and every balance proof with them — a real economy change bought for a meter, and a
--     second, unauthored source of price variation beside the one authored fact (0005's header
--     argues that case for the affinity matrix; it holds here). Rejected.
--   * NOT REBANDED. A two-sided meter would draw a range the data cannot occupy.
--   * THE COLUMN STAYS, and it starts meaning something the moment anybody buys — which is the
--     only thing that should move it. That is documented on the screen rather than faked, exactly
--     as TREND's emptiness under local play already is.
--   * WHAT DIES IS THE "NOTE" COLUMN'S WORD. `glut` was printed on every one of 70 rows at every
--     port (MarketScreen.tsx:530) — a false word for a full warehouse, AND a second rendering of
--     the meter beside it, which is the duplication docs/DEV_LOG.md:305 killed once already. The
--     column now carries what the screen could not say: the port that pays more, and by how much.
--
-- Depends ONLY on: 0001 (knobs, wc_*), 0002 (ports/legs), 0005 (mid_price/quote/daily cap),
--                  0006 (route_direct, fleet_speed, endurance_days), 0007 (do_sail, settle),
--                  0009 (the reads), 0015-0017 (officers, hold capacity, fleet_buy_capacity),
--                  0018 (client_rpc_entry_points, the EXECUTE lockdown).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('neighbour_radius_nm',   to_jsonb(600),
   'DESIGN E.4 %NBR: the great-circle radius, in nautical miles, that defines a port''s NEIGHBOURHOOD. Read by world.pct_of_neighbours and served to the client by world.snapshot, so the caption and the computation are one number. Measured 2026-08-22: widening it does not make %NBR predict a profit — see 0019''s header.'),
  ('advice_buy_below',      to_jsonb(90),
   'DESIGN E.4: below this %NBR a good is CHEAP against its neighbourhood. It is a price index band, not a recommendation to trade — world.trade_routes is what names a trade.'),
  ('advice_sell_above',     to_jsonb(110),
   'DESIGN E.4: above this %NBR a good is DEAR against its neighbourhood.'),
  ('route_scan_max_legs',   to_jsonb(2),
   '0019: how many SAILED legs out world.trade_routes looks by default. The distance is the sailed leg distance from voyage.reach_from, never a straight line.'),
  ('route_scan_max_ports',  to_jsonb(120),
   '0019: the bounded Dijkstra in world.trade_routes settles at most this many ports. A safety valve on O(V^2): today 2 legs from the busiest port reaches ~15, so it binds nothing, and it is what stops the scan growing with the map.'),
  ('route_scan_goods',      to_jsonb(70),
   '0019: the cap on goods PRICED through world.quote per call. At 70 goods in the world it binds nothing today; it is what stops this read multiplying if the goods table grows.'),
  ('route_scan_keep',       to_jsonb(3),
   '0019: how many destinations per good survive the mid-price shortlist and get priced end to end through world.quote. The shortlist is a heuristic; the number reported never is. At 3 it matched an exhaustive scan at every port measured — scripts/db/proofs/05_first_voyage_balance.sql re-checks that on every run.'),
  ('route_probe_tuns',      to_jsonb(50),
   '0019: the quantity world.trade_routes assumes when no fleet is lying at the port. Reported in the payload as basis.tuns, because a profit without a quantity is not a number.')
on conflict (key) do nothing;

-- ── 2. THE ONE SHORTEST-PATH COMPUTATION OVER THE LEG GRAPH ────────────────────────────────────
-- The body is 0006:173-268's Dijkstra, unchanged in arithmetic. What is new: it reports EVERY
-- settled node rather than one path, it carries the hop count, and it takes two optional stopping
-- conditions. Nothing here changes which path is shortest.
create or replace function voyage.reach_from(
  p_from uuid, p_max_ports int default null, p_stop_at uuid default null
)
returns table (port_id uuid, nm numeric, hops int, prev_id uuid)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_ids     uuid[];
  v_start   int[];
  v_deg     int[];
  v_to      int[];
  v_nm      numeric[];
  v_dist    numeric[];
  v_prev    int[];
  v_hops    int[];
  v_done    boolean[];
  v_n       int;
  v_e       int;
  v_src     int;
  v_u       int;
  v_v       int;
  v_best    numeric;
  v_alt     numeric;
  v_i       int;
  v_settled int := 0;
  INF       constant numeric := 1e18;
begin
  select array_agg(p.id order by p.id) into v_ids from public.ports p;
  v_n := coalesce(array_length(v_ids, 1), 0);
  v_src := array_position(v_ids, p_from);
  if v_src is null then return; end if;

  -- Both directions from each stored row: the leg table is undirected and stored once (0002).
  select array_agg(e.b order by e.a, e.b), array_agg(e.nm order by e.a, e.b)
    into v_to, v_nm
    from (
      select array_position(v_ids, l.from_port_id) as a,
             array_position(v_ids, l.to_port_id)   as b,
             l.distance_nm                          as nm
        from public.legs l
      union all
      select array_position(v_ids, l.to_port_id),
             array_position(v_ids, l.from_port_id),
             l.distance_nm
        from public.legs l
    ) e;
  v_e := coalesce(array_length(v_to, 1), 0);
  if v_e = 0 then return; end if;

  -- Degrees, then a running start index — one pass each, no per-node query.
  v_deg := array_fill(0, array[v_n]);
  select array_agg(cnt order by a) into v_deg from (
    select a, count(*)::int as cnt from (
      select array_position(v_ids, l.from_port_id) as a from public.legs l
      union all
      select array_position(v_ids, l.to_port_id) from public.legs l
    ) x group by a
    union all
    select g.i, 0 from generate_series(1, v_n) g(i)
     where not exists (select 1 from public.legs l
                        where l.from_port_id = v_ids[g.i] or l.to_port_id = v_ids[g.i])
  ) d;
  v_start := array_fill(0, array[v_n]);
  v_i := 1;
  for v_u in 1 .. v_n loop
    v_start[v_u] := v_i;
    v_i := v_i + v_deg[v_u];
  end loop;

  v_dist := array_fill(INF, array[v_n]);
  v_prev := array_fill(0, array[v_n]);
  v_hops := array_fill(0, array[v_n]);
  v_done := array_fill(false, array[v_n]);
  v_dist[v_src] := 0;

  loop
    v_u := 0;
    v_best := INF;
    for v_i in 1 .. v_n loop
      if not v_done[v_i] and v_dist[v_i] < v_best then
        v_best := v_dist[v_i];
        v_u := v_i;
      end if;
    end loop;
    exit when v_u = 0;
    v_done[v_u] := true;
    if v_u <> v_src then v_settled := v_settled + 1; end if;
    -- EARLY TERMINATION. Dijkstra settles nodes in order of distance, so the moment the caller's
    -- own stopping condition is met, every node it can still see is already FINAL. Both bounds
    -- change how much of the answer is computed, never what the answer is — asserted below.
    exit when p_stop_at is not null and v_ids[v_u] = p_stop_at;
    exit when p_max_ports is not null and v_settled >= p_max_ports;
    for v_i in v_start[v_u] .. v_start[v_u] + v_deg[v_u] - 1 loop
      v_v := v_to[v_i];
      if not v_done[v_v] then
        v_alt := v_dist[v_u] + v_nm[v_i];
        if v_alt < v_dist[v_v] then
          v_dist[v_v] := v_alt;
          v_prev[v_v] := v_u;
          v_hops[v_v] := v_hops[v_u] + 1;
        end if;
      end if;
    end loop;
  end loop;

  -- ONLY SETTLED NODES. A node the search reached but never settled carries an upper bound, not
  -- an answer: returning it would be a distance that could still fall.
  for v_i in 1 .. v_n loop
    if v_i <> v_src and v_done[v_i] then
      port_id := v_ids[v_i];
      nm      := v_dist[v_i];
      hops    := v_hops[v_i];
      prev_id := case when v_prev[v_i] = 0 then null else v_ids[v_prev[v_i]] end;
      return next;
    end if;
  end loop;
end $$;

comment on function voyage.reach_from(uuid, int, uuid) is
  'THE shortest path over the leg graph, from one port to every port it can settle. Dijkstra, as '
  '0006:173 wrote it, exposed at the shape it always computed: voyage.route_direct now walks these '
  'predecessors rather than running its own. Both optional bounds are early termination and cannot '
  'change an answer that is returned.';

revoke all on function voyage.reach_from(uuid, int, uuid) from public, anon, authenticated;

-- ── SUPERSEDES 0006:141. Same answer; it no longer owns the search. ────────────────────────────
create or replace function voyage.route_direct(p_from uuid, p_to uuid)
returns uuid[]
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_ids   uuid[];
  v_prev  uuid[];
  v_nodes uuid[] := array[]::uuid[];
  v_u     uuid;
  v_i     int;
begin
  if p_from = p_to then
    return array[p_from];
  end if;
  -- p_stop_at: settle only as far as the target, which is what 0006's `exit when v_u = v_dst` did.
  select array_agg(r.port_id order by r.port_id), array_agg(r.prev_id order by r.port_id)
    into v_ids, v_prev
    from voyage.reach_from(p_from, null, p_to) r;
  if v_ids is null or array_position(v_ids, p_to) is null then
    return null;                   -- unreachable or off-graph: the caller raises E_NO_ROUTE
  end if;
  v_u := p_to;
  loop
    v_nodes := array[v_u] || v_nodes;
    exit when v_u = p_from;
    v_i := array_position(v_ids, v_u);
    if v_i is null or v_prev[v_i] is null then return null; end if;
    v_u := v_prev[v_i];
  end loop;
  return v_nodes;
end $$;

comment on function voyage.route_direct(uuid, uuid) is
  'THE shortest path between two ports. Supersedes 0006:141: the Dijkstra moved to '
  'voyage.reach_from so that ranking destinations and routing a voyage cannot disagree about how '
  'far it is by sea. Same graph, same arithmetic, same answer.';

revoke all on function voyage.route_direct(uuid, uuid) from public, anon, authenticated;

-- ── 3. THE ONE ANSWER TO "MAY THIS FLEET SAIL THERE?" ──────────────────────────────────────────
-- SUPERSEDES the inline gates of cmd.do_sail (0007:368-403). Everything that depends on the FLEET
-- and the DESTINATION lives here; route EXISTENCE stays with the router, which both callers ask.
-- Returns null when she may sail, else the exact 'E_CODE: sentence' cmd.do_sail raises.
create or replace function voyage.sail_refusal(p_fleet uuid, p_dest uuid, p_nm numeric)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  f       public.fleets%rowtype;
  v_short int;
  v_flag  numeric;
  v_draft int;
  v_maxd  int;
  v_speed numeric;
  v_days  numeric;
  v_end   numeric;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.id is null then
    return 'E_NO_SUCH_FLEET: there is no such fleet';
  end if;
  if f.status <> 'DOCKED' then
    return format('E_NOT_DOCKED: %s is %s and must be docked to sail', f.name, f.status);
  end if;

  -- Every ship must be able to leave and to arrive (DESIGN F.2 SAIL preconditions).
  select count(*) into v_short
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet and s.crew < c.crew_required;
  if v_short > 0 then
    return format('E_CREW_SHORT: %s ship(s) are below their required complement', v_short);
  end if;

  select coalesce(durability, 0) into v_flag from public.ships where fleet_id = p_fleet and is_flagship;
  if coalesce(v_flag, 0) <= 0 then
    return 'E_FLAGSHIP_DISABLED: the flagship cannot sail until it is repaired';
  end if;

  select max(c.draft) into v_draft from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet;
  select max_draft into v_maxd from public.ports where id = p_dest;
  if v_draft > v_maxd then
    return format('E_DRAFT: the deepest hull draws %s and that port takes %s', v_draft, v_maxd);
  end if;
  if (select is_ice_closed from public.ports where id = p_dest) then
    return 'E_PORT_CLOSED: that port is closed';
  end if;

  v_speed := voyage.fleet_speed(p_fleet);
  v_days  := (p_nm / v_speed) / 24;
  v_end   := voyage.endurance_days(p_fleet);
  -- DESIGN C.5: "SAIL refuses to queue if endurance_days < leg_days x 1.15, and says so."
  if v_end < v_days * public.wc_num('endurance_margin') then
    return format('E_ENDURANCE: %s carries %s days of stores and that route is %s voyage-days; you need %s — PROVISION first',
      f.name, round(v_end, 1), round(v_days, 1), round(v_days * public.wc_num('endurance_margin'), 1));
  end if;
  return null;
end $$;

comment on function voyage.sail_refusal(uuid, uuid, numeric) is
  'THE one answer to "may this fleet sail there, right now?" — crew, flagship, draft, ice and '
  'endurance. cmd.do_sail RAISES what this returns and world.trade_routes REFUSES TO RECOMMEND '
  'what this refuses, so the quay can never name a port the order would turn down. Supersedes the '
  'four inline gates at 0007:368-403.';

revoke all on function voyage.sail_refusal(uuid, uuid, numeric) from public, anon, authenticated;

-- ── SUPERSEDES 0007:332. The gates moved out; nothing else about SAIL changed. ─────────────────
create or replace function cmd.do_sail(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  f        public.fleets%rowtype;
  v_nodes  uuid[];
  v_via    uuid[];
  v_dest   uuid;
  v_nm     numeric;
  v_speed  numeric;
  v_days   numeric;
  v_refuse text;
  v_voyage uuid;
begin
  select * into f from public.fleets where id = p_fleet;

  v_dest := (p_args->>'dest')::uuid;
  select coalesce(array_agg(x::uuid), '{}'::uuid[]) into v_via
    from jsonb_array_elements_text(coalesce(p_args->'via', '[]'::jsonb)) x;

  -- 0019: not-docked, crew, flagship, draft and ice are ONE authority now, and the quay consults
  -- the same one before it recommends a destination. E_NOT_DOCKED is inside it, which is why the
  -- status check that stood at 0007:353 is gone rather than duplicated — AND WHY THIS CALL COMES
  -- BEFORE THE ROUTER. A fleet at sea has no `port_id`, so routing her first turns "she is at sea"
  -- into "there is no route", which is a true sentence about the wrong thing; 0007 refused her
  -- status first and so does this. A distance of 0 cannot trip the endurance clause, which is
  -- asked again below once there is a real one to ask about.
  v_refuse := voyage.sail_refusal(p_fleet, v_dest, 0);
  if v_refuse is not null then
    raise exception '%', v_refuse using errcode = 'P0001';
  end if;

  v_nodes := voyage.route(f.port_id, v_dest, v_via);
  if v_nodes is null then
    raise exception 'E_NO_ROUTE: there is no authored sea route from here to that port'
      using errcode = 'P0001';
  end if;

  select sum((e->>'nm')::numeric) into v_nm
    from jsonb_array_elements(voyage.path_from_nodes(v_nodes)) e;

  -- ...and now the one clause that needed a distance to have an opinion. Same authority, asked
  -- again with the answer it was missing; never a second copy of the rule.
  v_refuse := voyage.sail_refusal(p_fleet, v_dest, v_nm);
  if v_refuse is not null then
    raise exception '%', v_refuse using errcode = 'P0001';
  end if;

  v_speed := voyage.fleet_speed(p_fleet);
  v_days  := (v_nm / v_speed) / 24;

  v_voyage := voyage.depart(p_fleet, v_nodes);
  perform public.emit_event(f.player_id, 'DEPARTED', jsonb_build_object(
    'fleet', f.name, 'voyage_id', v_voyage, 'total_nm', v_nm,
    'legs', jsonb_array_length(voyage.path_from_nodes(v_nodes)),
    'eta', (select eta from public.voyages where id = v_voyage)));
  return jsonb_build_object('voyage_id', v_voyage, 'total_nm', v_nm, 'voyage_days', round(v_days, 2));
end $$;

revoke all on function cmd.do_sail(uuid, jsonb) from public, anon, authenticated;

-- ── 4. %NBR: SAME DEFINITION, ONE PLACE FOR THE RADIUS ─────────────────────────────────────────
create or replace function world.pct_of_neighbours(p_port uuid, p_good uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_here   numeric;
  v_them   numeric;
  v_radius numeric := public.wc_num('neighbour_radius_nm');
begin
  -- "prices vs ports within N nm" (DESIGN E.4). Great-circle, not leg distance: this is a
  -- NEIGHBOURHOOD, not a route, and a port two short legs away is still a neighbour.
  select world.mid_price(p_port, p_good, pg.stock) into v_here
    from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good;
  if v_here is null then return null; end if;

  select avg(world.mid_price(o.id, p_good, pg.stock)) into v_them
    from public.ports here
    join public.ports o on o.id <> here.id
    join public.port_goods pg on pg.port_id = o.id and pg.good_id = p_good
   where here.id = p_port
     and voyage.gc_distance_nm(here.lat::float8, here.lon::float8, o.lat::float8, o.lon::float8) <= v_radius;

  if v_them is null or v_them = 0 then return null; end if;
  return round(v_here / v_them * 100, 1);
end $$;

comment on function world.pct_of_neighbours(uuid, uuid) is
  'DESIGN E.4 %NBR, defined once. Supersedes 0009:39 in one respect only: the radius is the '
  'neighbour_radius_nm knob rather than a literal, because the client printed the same 600 as a '
  'caption and two places held one number. It is a LOCAL PRICE INDEX and it is honest about that; '
  'it is not, and was never able to be, a prediction of profit — world.trade_routes is.';

revoke all on function world.pct_of_neighbours(uuid, uuid) from public, anon;
grant execute on function world.pct_of_neighbours(uuid, uuid) to authenticated;

-- ── SUPERSEDES 0009:115. Four %NBR walks per good become one; the bands come from the knobs. ───
create or replace function world.market(p_port uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- MATERIALIZED, and that word is load-bearing. `cross join lateral (select
  -- world.pct_of_neighbours(...))` reads as one call per good and is NOT: the planner pulls the
  -- sublink up and substitutes the expression at every reference, so four references cost four
  -- neighbourhood walks — which is precisely what 0009 was doing by hand. Measured on this chain:
  -- 1,303 ms with the lateral, 245 ms with this CTE. A fence is the only thing that makes "once"
  -- mean once.
  with nbr as materialized (
    select pg.good_id, world.pct_of_neighbours(p_port, pg.good_id) as pct
      from public.port_goods pg
     where pg.port_id = p_port
  ),
  band as materialized (
    select public.wc_num('advice_buy_below') as lo, public.wc_num('advice_sell_above') as hi
  )
  select jsonb_build_object(
    'port', (select jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name,
                                       'tax_rate', p.tax_rate, 'spread', world.spread(p.id),
                                       'culture', p.culture, 'dev_commerce', p.dev_commerce)
               from public.ports p where p.id = p_port),
    'goods', (select coalesce(jsonb_agg(jsonb_build_object(
        'good_id', g.id, 'code', g.code, 'name', g.name, 'category', g.category,
        'buy',  q.ask, 'sell', q.bid, 'mid', q.mid,
        'pct_nbr', n.pct,
        'stock', pg.stock, 'stock_target', pg.stock_target,
        'stock_band', round(least(1.0, pg.stock / pg.stock_target) * 6),
        -- DESIGN B.4: culture gates what a port will trade at all. UNAVAILABLE is a fact about the
        -- port, not a price, so it is a flag beside the price rather than a price of zero.
        'available', not (pr.culture = any(g.culture_mask)),
        -- The BAND of the price index, not a recommendation to trade.
        'advice', case when n.pct is null then 'hold'
                       when n.pct < b.lo then 'buy'
                       when n.pct > b.hi then 'sell'
                       else 'hold' end)
        order by g.code), '[]'::jsonb)
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
      join public.ports pr on pr.id = pg.port_id
      join nbr n on n.good_id = pg.good_id
     cross join band b
     cross join lateral world.price(pg.port_id, pg.good_id) q
     where pg.port_id = p_port))
$$;

revoke all on function world.market(uuid) from public, anon;
grant execute on function world.market(uuid) to authenticated;

-- ── SUPERSEDES 0009:68 — the client stops holding its own copy of three server numbers. ────────
create or replace function world.snapshot()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'ports', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'name', p.name, 'country', p.country,
        'nation', n.code, 'lat', p.lat, 'lon', p.lon, 'sea', s.name, 'region', r.code,
        'culture', p.culture, 'size_tier', p.size_tier, 'max_draft', p.max_draft,
        'has_yard', p.has_yard, 'yard_tier', p.yard_tier, 'has_academy', p.has_academy,
        'is_ice_closed', p.is_ice_closed, 'tax_rate', p.tax_rate, 'crew_pool', p.crew_pool,
        'dev_industry', p.dev_industry, 'dev_commerce', p.dev_commerce, 'dev_military', p.dev_military)
        order by p.code), '[]'::jsonb)
      from public.ports p
      left join public.nations n on n.id = p.nation_id
      join public.seas s on s.id = p.sea_id
      join public.regions r on r.id = p.region_id),
    'legs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', l.id, 'from', a.code, 'to', b.code, 'nm', l.distance_nm,
        'hazard_mult', l.hazard_mult, 'notes', l.notes) order by a.code, b.code), '[]'::jsonb)
      from public.legs l join public.ports a on a.id = l.from_port_id
                         join public.ports b on b.id = l.to_port_id),
    'goods', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', g.id, 'code', g.code, 'name', g.name, 'base_value', g.base_value,
        'bulk', g.bulk, 'category', g.category, 'perishable_pct_day', g.perishable_pct_day,
        'culture_mask', g.culture_mask) order by g.code), '[]'::jsonb) from public.goods g),
    'ship_classes', (select coalesce(jsonb_agg(to_jsonb(c) order by c.tier), '[]'::jsonb)
      from public.ship_classes c),
    -- The knobs the CLIENT legitimately needs, named one by one. Serving world_config wholesale
    -- would ship the hazard seed to every browser; an allow-list is the only safe shape.
    'config', jsonb_build_object(
        'time_compression',  public.wc_int('time_compression'),
        'order_queue_max',   public.wc_int('order_queue_max'),
        'fleet_max',         public.wc_int('fleet_max'),
        'ship_max',          public.wc_int('ship_max'),
        'endurance_margin',  public.wc_num('endurance_margin'),
        'trade_step_tuns',   public.wc_int('trade_step_tuns'),
        'water_per_crew_day', public.wc_num('water_per_crew_day'),
        'food_per_crew_day',  public.wc_num('food_per_crew_day'),
        'wage_per_crew_day',  public.wc_num('wage_per_crew_day'),
        -- 0019: the three numbers MARKET used to declare for itself.
        'neighbour_radius_nm', public.wc_num('neighbour_radius_nm'),
        'advice_buy_below',    public.wc_num('advice_buy_below'),
        'advice_sell_above',   public.wc_num('advice_sell_above')),
    'verbs', cmd.verb_schema())
$$;

revoke all on function world.snapshot() from public, anon;
grant execute on function world.snapshot() to authenticated;

-- ── 5. THE COMPARISON ──────────────────────────────────────────────────────────────────────────
create or replace function world.trade_routes(
  p_from     uuid,
  p_fleet    uuid    default null,
  p_max_legs int     default null,
  p_limit    int     default null,
  p_to       uuid    default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_legs    int     := greatest(1, coalesce(p_max_legs, public.wc_int('route_scan_max_legs')));
  v_ports   int     := public.wc_int('route_scan_max_ports');
  v_keep    int     := public.wc_int('route_scan_keep');
  v_goods   int     := public.wc_int('route_scan_goods');
  v_tuns    numeric := public.wc_num('route_probe_tuns');
  v_player  uuid    := public.current_player_id();
  f         public.fleets%rowtype;
  v_speed   numeric;
  v_basis   text    := 'default';
  v_nports  int;
  v_ncand   int;
  v_rows    jsonb;
begin
  if p_from is null or not exists (select 1 from public.ports where id = p_from) then
    raise exception 'E_NO_SUCH_PORT: there is no such port' using errcode = 'P0001';
  end if;

  if p_fleet is not null then
    select * into f from public.fleets where id = p_fleet;
    -- A fleet id is not a public handle: naming somebody else's fleet would disclose her hold,
    -- her purse and her speed through the numbers this read returns.
    if f.id is null or f.player_id is distinct from v_player then
      raise exception 'E_NOT_YOURS: that is not your fleet' using errcode = 'P0001';
    end if;
    v_speed := voyage.fleet_speed(p_fleet);
    -- Only a fleet LYING HERE can set the quantity: fleet_buy_capacity reads the port she is in.
    if f.port_id = p_from then v_basis := 'fleet'; end if;
  end if;

  with reach as materialized (
    -- TWO QUESTIONS, ONE READ. Without p_to: "where is any of this worth more?" — every port
    -- within v_legs sailed legs, nearest first, capped. With p_to: "what should I carry THERE?" —
    -- that one port, however far it is, which is why the port cap is dropped for it. A separate
    -- function for the second question would have been a second author of the shortlist, the
    -- pricing and the sail gate all at once.
    select r.port_id, r.nm, r.hops
      from voyage.reach_from(p_from, case when p_to is null then v_ports else null end) r
     where (case when p_to is null then (r.hops between 1 and v_legs)
                 else (r.port_id = p_to) end)
       -- A DESTINATION THIS FLEET COULD NOT SAIL TO IS NOT A RECOMMENDATION. The gate is
       -- voyage.sail_refusal — the SAME authority cmd.do_sail raises from — so the quay cannot
       -- name a port the order would refuse. Applied only when she is lying here: a fleet at sea
       -- has no current sailing to judge, so the scan falls back to the stated default basis.
       -- The gate is her CURRENT lading: taking cargo aboard slows her, so a route within a few
       -- per cent of her endurance can still be refused once loaded (see the header).
       and (v_basis <> 'fleet' or voyage.sail_refusal(p_fleet, r.port_id, r.nm) is null)
  ),
  here as materialized (
    select pg.good_id, pg.stock, g.culture_mask,
           world.mid_price(p_from, pg.good_id, pg.stock) as mid
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
      join public.ports  p on p.id = pg.port_id
     where pg.port_id = p_from
       and not (p.culture = any(g.culture_mask))
  ),
  -- STAGE 1 — the shortlist, through world.mid_price: one call per (good, destination) in range.
  -- It READS the price authority rather than re-deriving anything, and what it produces is a
  -- candidate list, never a number this read reports.
  mids as materialized (
    select h.good_id, rc.port_id, rc.nm, rc.hops, h.mid as mid_here,
           world.mid_price(rc.port_id, h.good_id, pg.stock) as mid_there
      from here h
      cross join reach rc
      join public.port_goods pg on pg.port_id = rc.port_id and pg.good_id = h.good_id
      join public.ports d on d.id = rc.port_id
     where not (d.culture = any(h.culture_mask))
  ),
  pairs as materialized (
    select m.good_id, m.port_id, m.nm, m.hops, m.mid_there - m.mid_here as gap,
           row_number() over (partition by m.good_id
                                  order by m.mid_there desc, m.nm asc) as rn
      from mids m
     where m.mid_there > m.mid_here
  ),
  short_goods as materialized (
    select good_id from pairs where rn = 1 order by gap desc, good_id limit v_goods
  ),
  kept as materialized (
    select p.good_id, p.port_id, p.nm, p.hops
      from pairs p
      join short_goods sg on sg.good_id = p.good_id
     where p.rn <= v_keep
  ),
  -- STAGE 2 — the price, through world.quote, which is where the money moves.
  -- The BUY side does not depend on the destination, so it is quoted ONCE per good.
  sized as materialized (
    select h.good_id,
           case when v_basis = 'fleet'
                then (public.fleet_buy_capacity(p_fleet, h.good_id)->>'max_qty')::numeric
                else floor(least(v_tuns, h.stock)) end as qty
      from here h
      join short_goods sg on sg.good_id = h.good_id
  ),
  bought as materialized (
    select z.good_id, qb.units, qb.total as outlay, qb.avg_price as buy_price
      from sized z
      cross join lateral world.quote(p_from, z.good_id, z.qty, 'buy', null, p_fleet) qb
     where z.qty >= 1
  ),
  priced as materialized (
    select k.good_id, k.port_id, k.nm, k.hops,
           b.units, b.outlay, b.buy_price,
           qs.total as proceeds, qs.avg_price as sell_price
      from kept k
      join bought b on b.good_id = k.good_id and b.units > 0
      cross join lateral world.quote(k.port_id, k.good_id, b.units, 'sell', null, p_fleet) qs
  ),
  best as (
    select distinct on (p.good_id) p.*
      from priced p
     order by p.good_id, (p.proceeds - p.outlay) desc, p.nm asc
  ),
  shaped as (
    select jsonb_build_object(
             'good_id', b.good_id, 'code', g.code, 'name', g.name,
             'to', jsonb_build_object('id', d.id, 'code', d.code, 'name', d.name),
             'qty', b.units, 'outlay', b.outlay, 'proceeds', b.proceeds,
             'profit', b.proceeds - b.outlay,
             'return_pct', case when b.outlay > 0
                                then round((b.proceeds - b.outlay)::numeric / b.outlay * 100, 1) end,
             'buy_price', b.buy_price, 'sell_price', b.sell_price,
             'nm', b.nm, 'legs', b.hops,
             'days', case when v_speed > 0 then round(b.nm / v_speed / 24, 2) end,
             'profit_per_day', case when v_speed > 0 and b.nm > 0
                                    then round((b.proceeds - b.outlay)::numeric / (b.nm / v_speed / 24), 1) end,
             'profit_per_nm', round((b.proceeds - b.outlay)::numeric / greatest(b.nm, 1), 4)
           ) as x,
           -- RANKED BY PROFIT, AND THAT WAS MEASURED RATHER THAN ASSUMED. The first cut ranked by
           -- profit per sea-mile, which is the better RATE and the worse ANSWER: out of Lisboa it
           -- put "27 tuns of wax to Setúbal, 16 nm, +49 d." above "20 tuns of porcelain to
           -- Saint-Louis, +1,847 d.", because 49/16 beats 1847/1534. A player who taps the top row
           -- and makes forty-nine ducats has been told the same unhelpful thing the %NBR bands
           -- told the auditor, in a new column. What a captain is choosing between here is
           -- VOYAGES, and the question is how much this one pays; the rate is on the row for
           -- anyone comparing tempos (`profit_per_day`, and `profit_per_nm` when no fleet is named
           -- and there is no speed to divide by).
           row_number() over (order by (b.proceeds - b.outlay) desc, b.nm asc, b.good_id) as rk
      from best b
      join public.goods g on g.id = b.good_id
      join public.ports d on d.id = b.port_id
     where b.proceeds > b.outlay
  )
  select (select count(*) from reach),
         (select count(*) from shaped),
         (select coalesce(jsonb_agg(x order by rk)
                            filter (where p_limit is null or rk <= p_limit), '[]'::jsonb)
            from shaped)
    into v_nports, v_ncand, v_rows;

  return jsonb_build_object(
    'from', (select jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name)
               from public.ports p where p.id = p_from),
    'fleet', case when f.id is null then null else
               jsonb_build_object('id', f.id, 'name', f.name, 'speed_kn', v_speed,
                                  'here', f.port_id = p_from) end,
    -- THE BOUNDS THIS ANSWER WAS COMPUTED UNDER, reported rather than assumed. A profit with no
    -- quantity is not a number, and a search with no stated reach is not a search.
    'basis', jsonb_build_object(
       'qty_from', v_basis, 'tuns', v_tuns,
       'max_legs', case when p_to is null then v_legs else null end,
       'to', (select p.code from public.ports p where p.id = p_to),
       'ports_considered', v_nports, 'goods_cap', v_goods, 'keep_per_good', v_keep,
       'routes_found', v_ncand),
    'routes', v_rows);
end $$;

comment on function world.trade_routes(uuid, uuid, int, int, uuid) is
  'THE comparison. For each good this port will trade, the reachable port that pays most for it, '
  'priced end to end through world.quote — the same function a committed BUY and SELL execute at — '
  'over the SAILED leg distance from voyage.reach_from, and only to destinations '
  'voyage.sail_refusal says this fleet may actually reach. Ranked by what the voyage PAYS. The '
  'quantity it assumed is in basis.qty_from; the bounds it searched under are in basis.';

revoke all on function world.trade_routes(uuid, uuid, int, int, uuid) from public, anon;
grant execute on function world.trade_routes(uuid, uuid, int, int, uuid) to authenticated;

-- ── 6. THE CLIENT ENTRY POINTS — SUPERSEDES 0018:183 ───────────────────────────────────────────
-- One row added. 0018's rule stands: this list and src/lib/rpc/catalog.ts are one statement of
-- what a browser may call, and client_executable_writers() subtracts it, so granted and sanctioned
-- cannot drift.
create or replace function public.client_rpc_entry_points()
returns table (schema_name text, function_name text, arg_types text, fn regprocedure)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.s, t.f, t.a,
         to_regprocedure(format('%I.%I(%s)', t.s, t.f, t.a))
    from (values
      -- the reads (world)
      ('world'::text, 'snapshot'::text,      ''::text),
      ('world',       'market',              'uuid'),
      ('world',       'fleets',              ''),
      ('world',       'ledger',              'timestamptz, int'),
      ('world',       'buy_capacity',        'uuid, uuid'),
      ('world',       'price_history',       'uuid, int'),
      ('world',       'player',              ''),
      ('world',       'officers',            ''),
      ('world',       'skills',              ''),
      -- 0019: the comparison. src/lib/rpc/catalog.ts names it `worldTradeRoutes`.
      ('world',       'trade_routes',        'uuid, uuid, int, int, uuid'),
      -- the orders (cmd)
      ('cmd',         'issue',               'uuid, text, int'),
      ('cmd',         'preview',             'uuid, text'),
      ('cmd',         'cancel_at',           'uuid, int'),
      ('cmd',         'clear',               'uuid, boolean'),
      ('cmd',         'verb_schema',         ''),
      ('cmd',         'hire_officer',        'text, uuid'),
      ('cmd',         'post_officer',        'text, uuid'),
      ('cmd',         'study_skill',         'text, uuid'),
      ('cmd',         'found_house',         'text, text')
    ) as t(s, f, a)
$$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe   constant uuid := '00000000-0019-4000-8000-000000000001';
  v_lis     uuid;
  v_player  uuid;
  v_fleet   uuid;
  rp        record;
  v_n       int;
  v_m       int;
  v_bad     int;
  v_stop_bad int;
  v_allports int;
  v_nm_a    numeric;
  v_nm_b    numeric;
  v_path    uuid[];
  v_routes  jsonb;
  v_played  jsonb;
  v_top     jsonb;
  v_gate    text;
  v_far     uuid;
  v_far_nm  numeric;
  v_res     jsonb;
  v_gate_res jsonb;
  v_buy_res jsonb; v_sail_res jsonb; v_sell_res jsonb;
  v_pinned  jsonb; v_pin_port uuid; v_pin_bad int; v_pin_n int;
  v_pred_out bigint; v_pred_in bigint;
  v_real_out bigint; v_real_in bigint;
  v_trap_g  text; v_trap_p text; v_trap_loss bigint; v_trap_pct numeric;
  v_mkt     jsonb; v_mkt_bad int;
  v_ms_before int; v_ms_after int;
  f_reach boolean := false; f_bounds boolean := false; f_router boolean := false;
  f_gate  boolean := false; f_sail  boolean := false; f_exec  boolean := false;
  f_trap  boolean := false; f_market boolean := false; f_grant boolean := false;
  f_pin   boolean := false;
begin
  select id into v_lis from public.ports where code = 'LIS';

  -- (a) THE ROUTER STILL ROUTES, AND reach_from IS THE WHOLE GRAPH.
  --     0003 asserts the leg graph is connected from Lisboa; the new reader must see all of it.
  select count(*) into v_n from voyage.reach_from(v_lis);
  select count(*) into v_allports from public.ports where id <> v_lis;
  -- Every returned row must be a real shortest path: its predecessor is a port, and the hop count
  -- is at least one. A 0-hop row other than the source would mean the walk-back could not close.
  select count(*) into v_bad from voyage.reach_from(v_lis) rf
   where rf.hops < 1 or rf.prev_id is null
      or not exists (select 1 from public.legs l
                      where (l.from_port_id = rf.prev_id and l.to_port_id = rf.port_id)
                         or (l.to_port_id = rf.prev_id and l.from_port_id = rf.port_id));
  if v_n = v_allports and v_bad = 0 then f_reach := true; end if;

  -- (b) THE TWO BOUNDS ARE EARLY TERMINATION, NOT A DIFFERENT ANSWER. Both are checked against
  --     the unbounded run on every port they return, and the counts are asserted first so the
  --     comparison cannot pass over an empty set.
  select count(*) into v_n from voyage.reach_from(v_lis, 25);
  select count(*) into v_bad
    from voyage.reach_from(v_lis, 25) b
    join voyage.reach_from(v_lis)     u on u.port_id = b.port_id
   where b.nm is distinct from u.nm or b.hops is distinct from u.hops
      or b.prev_id is distinct from u.prev_id;
  select count(*), count(*) filter (where s.nm is distinct from u.nm
                                       or s.hops is distinct from u.hops
                                       or s.prev_id is distinct from u.prev_id)
    into v_m, v_stop_bad
    from voyage.reach_from(v_lis, null, (select id from public.ports where code = 'TUN')) s
    join voyage.reach_from(v_lis) u on u.port_id = s.port_id;
  -- The counts are asserted BEFORE the comparisons: a join that matched nothing would agree
  -- vacuously, which is the shape README §3 calls worse than no assert at all.
  if v_n = 25 and v_bad = 0 and v_m > 0 and v_stop_bad = 0 then f_bounds := true; end if;

  -- (c) route_direct COMPOSES IT AND IS STILL OPTIMAL. For a deterministic sample of destinations:
  --     the path is a real chain of legs, its summed nm equals reach_from's distance, and NO
  --     two-leg path is shorter. The positive control is the last clause — a router that returned
  --     any old path would fail it, and a router that returned the great circle would fail the
  --     first, since 0003 asserts no leg is shorter than the great circle between its ports.
  v_bad := 0;
  for rp in select p.id, p.code from public.ports p where p.id <> v_lis order by p.code limit 12 loop
    v_path := voyage.route_direct(v_lis, rp.id);
    if v_path is null or v_path[1] <> v_lis or v_path[array_length(v_path,1)] <> rp.id then
      v_bad := v_bad + 1;
      continue;
    end if;
    select sum(l.distance_nm) into v_nm_a
      from generate_subscripts(v_path, 1) s(i)
      join public.legs l on (l.from_port_id = v_path[s.i] and l.to_port_id = v_path[s.i+1])
                         or (l.to_port_id  = v_path[s.i] and l.from_port_id = v_path[s.i+1])
     where s.i < array_length(v_path, 1);
    select rf.nm into v_nm_b from voyage.reach_from(v_lis) rf where rf.port_id = rp.id;
    if v_nm_a is distinct from v_nm_b then v_bad := v_bad + 1; continue; end if;
    -- no single leg and no two-leg chain beats it
    select min(x.nm) into v_nm_a from (
      select l.distance_nm as nm from public.legs l
       where (l.from_port_id = v_lis and l.to_port_id = rp.id)
          or (l.to_port_id = v_lis and l.from_port_id = rp.id)
      union all
      select l1.distance_nm + l2.distance_nm
        from public.legs l1
        join public.legs l2 on true
       where (l1.from_port_id = v_lis or l1.to_port_id = v_lis)
         and (l2.from_port_id = rp.id  or l2.to_port_id = rp.id)
         and (case when l1.from_port_id = v_lis then l1.to_port_id else l1.from_port_id end)
           = (case when l2.from_port_id = rp.id  then l2.to_port_id else l2.from_port_id end)
    ) x;
    if v_nm_a is not null and v_nm_a < v_nm_b - 0.0001 then v_bad := v_bad + 1; end if;
  end loop;
  if v_bad = 0 then f_router := true; end if;

  -- (d) world.market SERVES THE SAME NUMBERS IT SERVED YESTERDAY. The supersede folded four %NBR
  --     walks into one and moved 90/110/600 into knobs; nothing about the VALUES may move. Every
  --     good is recomputed inline from 0009's own definitions and required to match.
  v_mkt := world.market(v_lis);
  select count(*) into v_mkt_bad
    from jsonb_array_elements(v_mkt->'goods') e
    join public.goods g on g.code = e->>'code'
    join public.port_goods pg on pg.port_id = v_lis and pg.good_id = g.id
   cross join lateral world.price(v_lis, g.id) q
   cross join lateral (select world.pct_of_neighbours(v_lis, g.id) as pct) n
   where (e->>'buy')::numeric  is distinct from q.ask
      or (e->>'sell')::numeric is distinct from q.bid
      or (e->'pct_nbr' = 'null'::jsonb) is distinct from (n.pct is null)
      or (n.pct is not null and (e->>'pct_nbr')::numeric is distinct from n.pct)
      or e->>'advice' is distinct from (case when n.pct is null then 'hold'
                                             when n.pct < 90  then 'buy'
                                             when n.pct > 110 then 'sell'
                                             else 'hold' end);
  if v_mkt_bad = 0
     and jsonb_array_length(v_mkt->'goods') = (select count(*) from public.goods)
     and (world.snapshot()->'config'->>'neighbour_radius_nm')::numeric = 600
     and (world.snapshot()->'config'->>'advice_buy_below')::numeric = 90
     and (world.snapshot()->'config'->>'advice_sell_above')::numeric = 110 then
    f_market := true;
  end if;

  begin
    v_player := public.new_house(v_probe, 'Casa da Doca', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    perform cmd.assume_identity(v_probe);
    -- THE PROBE SETS ITS OWN PRECONDITION (README §3): watered, fed and fully crewed, exactly as
    -- a player sets out. A Barca sails with precisely the hands she needs, and a half-stored one
    -- has an endurance that depends on what new_house happened to give her — neither is a world
    -- this file owns.
    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
    perform cmd.do_hire(v_fleet, jsonb_build_object('count',
      (select c.crew_max - sh.crew from public.ships sh
         join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = v_fleet)));

    -- (e) THE SAIL GATE IS ONE AUTHORITY, AND IT BITES. Find the farthest port in range at 3 legs
    --     that this fleet CANNOT reach, and require that voyage.sail_refusal and a real
    --     cmd.issue('SAIL TO ...') agree — the same code, from the same sentence. A probe that
    --     found no such port would prove nothing, so its existence is asserted first.
    select rf.port_id, rf.nm into v_far, v_far_nm
      from voyage.reach_from(v_lis, 120) rf
     where voyage.sail_refusal(v_fleet, rf.port_id, rf.nm) like 'E_ENDURANCE%'
     order by rf.nm desc, rf.port_id
     limit 1;
    if v_far is not null then
      v_gate := voyage.sail_refusal(v_fleet, v_far, v_far_nm);
      v_gate_res := cmd.issue(v_fleet, format('SAIL TO %s', (select code from public.ports where id = v_far)));
      -- cmd.issue splits the raised 'E_CODE: sentence' into code and sentence, so the two halves
      -- are put back together and required to be the SAME STRING, not merely the same code. A
      -- matching code with a drifted sentence is exactly how two authorities look on the way out.
      if v_gate_res->>'error_code' = 'E_ENDURANCE'
         and (v_gate_res->>'error_code') || ': ' || (v_gate_res->>'error_message') = v_gate then
        f_gate := true;
      end if;
      perform cmd.clear(v_fleet, false);
    end if;

    -- (f) EVERY DESTINATION THE QUAY NAMES IS ONE SHE MAY SAIL TO, and the scan really was
    --     filtered — the port found in (e) is inside the scan's reach and is NOT in the answer.
    v_routes := world.trade_routes(v_lis, v_fleet, 2, null);
    select count(*) into v_bad
      from jsonb_array_elements(v_routes->'routes') e
     where voyage.sail_refusal(v_fleet, (e->'to'->>'id')::uuid, (e->>'nm')::numeric) is not null;
    if v_bad = 0
       and jsonb_array_length(v_routes->'routes') > 0
       and v_routes->'basis'->>'qty_from' = 'fleet'
       and not exists (select 1 from jsonb_array_elements(v_routes->'routes') e
                        where (e->'to'->>'id')::uuid = v_far) then
      f_sail := true;
    end if;

    -- (f2) PINNED TO ONE PORT, the read answers the other question — and it must answer it with
    --      the SAME rows: every route the open scan found to that port has to come back, priced
    --      identically, when the scan is pinned to it. The subject is the destination the open
    --      scan actually used, so the comparison can never be over an empty set.
    v_pin_port := (v_routes->'routes'->0->'to'->>'id')::uuid;
    if v_pin_port is not null then
      v_pinned := world.trade_routes(v_lis, v_fleet, null, null, v_pin_port);
      select count(*) into v_pin_bad
        from jsonb_array_elements(v_routes->'routes') a
       where (a->'to'->>'id')::uuid = v_pin_port
         and not exists (select 1 from jsonb_array_elements(v_pinned->'routes') b
                          where b->>'good_id' = a->>'good_id'
                            and b->>'profit'  = a->>'profit'
                            and b->>'nm'      = a->>'nm');
      select count(*) into v_pin_n from jsonb_array_elements(v_pinned->'routes') b
       where b->'to'->>'id' <> v_pin_port::text;
      if v_pin_bad = 0 and v_pin_n = 0
         and jsonb_array_length(v_pinned->'routes') > 0 then
        f_pin := true;
      end if;
    end if;

    -- (g) THE HEADLINE: THE NUMBER OFFERED IS THE NUMBER CHARGED. Take the quay's own top row and
    --     PLAY IT — BUY here, SAIL there, SELL — through cmd.issue, the only mutating entry point.
    --     The realised totals must equal the predicted ones TO THE DUCAT. A prediction that was
    --     merely "close" would be a second price authority, which is the defect this file exists
    --     to end one level up.
    -- THE ONE-LEG SET, deliberately. The gate above is evaluated at her CURRENT lading and cargo
    -- slows a ship (voyage.ship_speed, 0006:352) — see the header's note — so a TWO-leg route
    -- inside a few per cent of her endurance can still be refused once she is loaded. A one-leg
    -- route out of Lisboa is nowhere near that edge, and a probe picks a subject the world will
    -- actually let it use rather than one that fails on some runs and not others.
    v_played   := world.trade_routes(v_lis, v_fleet, 1, null);
    v_top      := v_played->'routes'->0;
    v_pred_out := (v_top->>'outlay')::bigint;
    v_pred_in  := (v_top->>'proceeds')::bigint;
    v_buy_res := cmd.issue(v_fleet, format('BUY %s %s', v_top->>'code', (v_top->>'qty')::numeric));
    v_real_out := (v_buy_res->'order'->'result'->>'total')::bigint;
    v_sail_res := cmd.issue(v_fleet, format('SAIL TO %s', v_top->'to'->>'code'));
    f_sail := f_sail and (v_sail_res->>'ok')::boolean;
    update public.voyages set departed_at = departed_at - interval '600 hours',
                              eta = eta - interval '600 hours'
     where fleet_id = v_fleet and status = 'SAILING';
    perform world.fleets();                       -- the read is the catch-up (D.2)
    v_sell_res := cmd.issue(v_fleet, format('SELL %s %s', v_top->>'code', (v_top->>'qty')::numeric));
    v_real_in := (v_sell_res->'order'->'result'->>'total')::bigint;
    if v_real_out = v_pred_out and v_real_in = v_pred_in and v_pred_in > v_pred_out then
      f_exec := true;
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  -- (h) THE DEFECT ITSELF, STILL MEASURABLE — the positive control for why this file exists.
  --     Somewhere within one leg of Lisboa there is a good whose %NBR at the destination is ABOVE
  --     advice_sell_above (the screen marks it "sell") while carrying it there from Lisboa at the
  --     probe quantity LOSES money. If that pair ever stops existing, %NBR became a profit
  --     predictor and this assert should be revisited rather than deleted.
  select g.code, d.code, (qs.total - qb.total), world.pct_of_neighbours(d.id, g.id)
    into v_trap_g, v_trap_p, v_trap_loss, v_trap_pct
    from voyage.reach_from(v_lis, 120) rf
    join public.ports d on d.id = rf.port_id
    join public.port_goods pg on pg.port_id = v_lis
    join public.goods g on g.id = pg.good_id
   cross join lateral world.quote(v_lis, g.id, 50, 'buy') qb
   cross join lateral world.quote(d.id,  g.id, qb.units, 'sell') qs
   where rf.hops = 1
     and not (d.culture = any(g.culture_mask))
     and not ((select culture from public.ports where id = v_lis) = any(g.culture_mask))
     and qb.units > 0
     and qs.total < qb.total
     and world.pct_of_neighbours(d.id, g.id) > public.wc_num('advice_sell_above')
   order by (qs.total - qb.total) asc, g.code, d.code
   limit 1;
  if v_trap_g is not null then f_trap := true; end if;

  -- (i) The lockdown, both halves, and the new read reachable by exactly one role.
  if (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and has_function_privilege('authenticated', 'world.trade_routes(uuid, uuid, int, int, uuid)', 'execute')
     and not has_function_privilege('anon', 'world.trade_routes(uuid, uuid, int, int, uuid)', 'execute')
     and not has_function_privilege('anon', 'voyage.reach_from(uuid, int, uuid)', 'execute')
     and not has_function_privilege('anon', 'voyage.sail_refusal(uuid, uuid, numeric)', 'execute')
     and (select count(*) from public.client_rpc_entry_points() where fn is null) = 0
     and exists (select 1 from public.client_rpc_entry_points()
                  where schema_name = 'world' and function_name = 'trade_routes') then
    f_grant := true;
  end if;

  if not f_reach  then raise exception '0019 self-assert FAIL: voyage.reach_from(LIS) settled % of % ports with % row(s) whose predecessor is not a real leg', v_n, v_allports, v_bad; end if;
  if not f_bounds then raise exception '0019 self-assert FAIL: nearest-25 returned % row(s) (want 25) and disagreed on %; stop-at-TUN returned % row(s) and disagreed on %', v_n, v_bad, v_m, v_stop_bad; end if;
  if not f_router then raise exception '0019 self-assert FAIL: % of 12 sampled routes are not a real chain of legs, do not match reach_from''s distance, or are beaten by a shorter two-leg path', v_bad; end if;
  if not f_market then raise exception '0019 self-assert FAIL: the superseded world.market changed % of % good(s), or the three knobs are not served', v_mkt_bad, jsonb_array_length(v_mkt->'goods'); end if;
  if not f_gate   then raise exception '0019 self-assert FAIL: the gate and cmd.do_sail did not produce the SAME sentence for a port beyond endurance — or the probe found no such port at all within the nearest 120, in which case it is asserting nothing (far=%, gate said [%], order said [%])', v_far, v_gate, v_gate_res; end if;
  if not f_sail   then raise exception '0019 self-assert FAIL: world.trade_routes named % destination(s) this fleet may not sail to, or named none at all, or the SAIL of its own top route was refused. top=% buy=% sail=%', v_bad, v_top, v_buy_res, v_sail_res; end if;
  if not f_pin    then raise exception '0019 self-assert FAIL: pinning the scan to one port did not reproduce the open scan''s rows for it (% mismatched, % foreign row(s) came back, % row(s) total)', v_pin_bad, v_pin_n, jsonb_array_length(v_pinned->'routes'); end if;
  if not f_exec   then raise exception '0019 self-assert FAIL: the quay predicted % out / % in and the orders moved % / % — the number offered is not the number charged. top=% buy=% sell=%', v_pred_out, v_pred_in, v_real_out, v_real_in, v_top, v_buy_res, v_sell_res; end if;
  if not f_trap   then raise exception '0019 self-assert FAIL: no good within one leg of Lisboa both reads above the SELL threshold at the destination and loses money on the voyage — %%NBR may have become a profit predictor, in which case this assert wants rewriting, not deleting'; end if;
  if not f_grant  then raise exception '0019 self-assert FAIL: the grant posture is wrong — world.trade_routes is not reachable by exactly `authenticated`, or an entry point does not resolve, or a client write/execute grant appeared'; end if;

  select count(*) into v_n from public.players;
  if v_n <> 0 then raise exception '0019 self-assert FAIL: % player row(s) survived the probe subtransaction', v_n; end if;

  raise notice '0019 self-assert ok: voyage.reach_from settled all % ports from Lisboa with every predecessor a real leg, and BOTH bounds (nearest-25, stop-at-TUN) agreed with the unbounded run on every port they returned; voyage.route_direct composes it and 12 sampled routes are each a real chain of legs matching reach_from to the digit, none beaten by a shorter two-leg path; world.market serves all % goods with buy/sell/%%NBR/advice UNCHANGED after folding four neighbourhood walks into one, and snapshot now serves the 600/90/110 the client used to declare for itself; voyage.sail_refusal and cmd.do_sail returned the IDENTICAL sentence for a port beyond endurance (% at % nm), and world.trade_routes named 0 destinations she may not reach and excluded that very port, and pinning the scan to one port reproduced the open scan''s rows for it exactly; the quay''s own top row — % tun(s) of % to % — predicted % d. out and % d. in and the orders moved EXACTLY that, a margin of % d.; and the defect is still there to be measured: % at % reads %%NBR % (above the SELL threshold) and LOSES % d. on the voyage, which is why a price index is not a trade; 0 client write grants, 0 client-executable writers',
    v_allports,
    (select count(*) from public.goods),
    (select code from public.ports where id = v_far), v_far_nm,
    (v_top->>'qty')::numeric, v_top->>'code', v_top->'to'->>'code',
    v_pred_out, v_pred_in, v_pred_in - v_pred_out,
    v_trap_g, v_trap_p, v_trap_pct, -v_trap_loss;
end $$;
