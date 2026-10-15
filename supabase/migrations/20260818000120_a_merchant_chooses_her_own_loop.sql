-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0120 — A MERCHANT CHOOSES HER OWN LOOP
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-15: *"the merchant npc should have freedom too. 15% is too big. change to 5%, and is
-- there a way for these ships, to change trading routes accordingly by itself finding the best
-- solution for money? change the buying items accordingly, selling them accordingly and so on by
-- itself?"* And: *"but some ships (bigger ships) must move outside the zone, meaning not nearby
-- 4~5 ports, but far away between continents too for bigger profit. you know that the prices
-- should go up as you move further away from the distance of original place where you've bought
-- right?"*
--
-- ── WHAT WAS FOUND ──────────────────────────────────────────────────────────────────────────────
-- Many merchants closed laps at net 0: nothing on their FIXED, authored loop cleared the 15 % bar
-- (npc_min_return_pct, 0114), so they sailed in ballast (0115). A merchant could change her LINES
-- every lap but never her PORTS. The server holds no pathfinder (the course is the client's
-- proposal; voyage.path_refusal judges it), so the only courses a merchant can sail are the ones
-- the roster already carries: measured on the applied chain, 995 authored legs, 1,804 both ways,
-- over 237 harbours, median 7 ways out of a harbour, 634 of them 2,000 nm or longer (194 harbours
-- have a long haul out).
-- ONE TRADING PATH COULD BOOK A LOSS: the cut-loss line (0097 §4.1, 0114 step 4) — a good refused
-- E_PRICE_LIMIT on a SELL at a stop in both of the last two closed laps is written `SELL <good>
-- ALL` with NO floor, so a parcel carried in at cost was let go at whatever the quay bid (prod,
-- 2026-10-14 23:07 UTC, lap 10 of one route: stock_in 105,894 sold for 92,688, net -13,206, every
-- cost 0). The at-profit floor (paid + npc_sell_margin) never applied to it: a named SELL line
-- carrying at_profit = false renders with no AT. Cargo lost to a STRIPPED raid (0027) is the other
-- way a lap closes below zero; that is not a trade and is left as it is.
-- PRICES ALREADY RISE WITH DISTANCE FROM THE SOURCE: world.affinity_at (0005/0048) prices a
-- (port, good) at 0.93 x base at a producer and home + span x (nearest source nm / reach)^curve
-- elsewhere — 1.00 + 0.76 x (nm / 9,500)^0.88, so ~1.10 at 1,000 nm, ~1.28 at 3,000, ~1.51 at
-- 6,000, 1.76 at 9,500 and beyond. Nothing in the market moves in this file.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE BAR IS 5 %. npc_min_return_pct 15 -> 5: the knob, read by the one keep test (now in
--     public.npc_leg_lines) and by the buy cap at the moment of buying (cmd.standing_route_lines).
-- (2) ONE LEG PLANNER. public.npc_leg_lines(route, from, to, hold, crew, speed) is 0114's
--     rank-filter-size-keep for one leg, moved out of npc_plan's loop whole: the cut-loss SELLs,
--     THE ranking (world.trade_routes from -> to), the wares filter, the npc_buyers_per_good cap
--     (counted ONCE per port as a map, not once per good), the sink-sized parcel, the wage and
--     min-return keep, the ceiling. It answers the lines AND what they pay AND the leg's sailed
--     distance (voyage.reach_from, the same figure the ranking rows carry), so a loop can be
--     priced without being written.
-- (3) THE KNOWN LEGS. public.npc_known_legs(port) — every course the merchant roster carries out
--     of that harbour, both ways (a course reversed is the same water; cmd.do_sail re-judges it at
--     departure), one per destination, with the reach table's distance.
-- (4) THE CHOICE, at her LAP START. When npc_plan plans ONE route whose fleet lies docked at her
--     stop 0 between laps, it prices her present loop and up to npc_route_candidates alternatives
--     from public.npc_loop_candidates: out-and-back to each of the npc_route_neighbours nearest
--     known harbours, three-stop loops among them where the roster knows the cross leg, and — for
--     a fleet whose hold is npc_route_far_hold_tuns or more — out-and-back on the
--     npc_route_far_candidates farthest known legs of npc_route_far_nm or more (or, when her
--     harbour has none, via a neighbour that has one). Every candidate destination must take her
--     draft, be open, and lie within the days of stores she can carry (her preset, raisable
--     through the preset core up to npc_preset_days_max while half her hold stays for cargo).
--     Each loop's lines come from the leg planner, each distinct leg priced once; the score is
--     ducats per REAL hour of the lap (sea time at the fleet's speed through time_compression,
--     plus her rest). She changes loop when the best beats her present one by
--     npc_route_switch_pct; her stop 0 (home) is where every loop starts and ends. Nothing pays
--     anywhere: she keeps her loop and sails it in ballast, as 0115 wrote.
-- (5) THE EXECUTOR READS THE NEW LOOP. cmd.run_standing_route re-reads the route, its stop count
--     and the stop she lies at after the lap-start plan (sliced), so the orders it writes — and
--     the course the SAIL carries — are the chosen loop's, never the stale record's.
-- (6) THE CUT-LOSS NEVER SELLS BELOW COST. The leg planner writes it as a NAMED at-profit SELL,
--     and cmd.standing_route_lines (sliced) adds npc_sell_margin only to the general SELL (no good
--     named): a named at-profit SELL floors at what she paid, so the parcel leaves the moment the
--     quay bids its cost and never for less. A merchant lap can no longer lose money by trading.
-- (7) A LOOP SHORTER THAN A GAME-DAY IS SCORED OVER THE GAME-DAY. The daily cap
--     (world.daily_cap_remaining, per company, port, good and game-day) lets a parcel be bought
--     once a game-day; a five-minute hop cannot sell its parcel eleven times an hour. So the hours
--     a lap is scored over are at least game_day_seconds, which is also why a nau out of Lisbon
--     is not sent to Porto for ever.
--
-- BOUNDED: no world scan. Per lap start: <= npc_route_candidates loops, each distinct leg priced
-- once (one world.trade_routes call plus <= 3 x 3 quotes), the known legs read once per harbour
-- touched. The choice is skipped past the upkeep budget (public.npc_upkeep_spent) and is never
-- made by the switch's pass (that pass plans all routes at once; a merchant chooses alone, at her
-- own lap start, inside the arrivals tick for that one fleet).
--
-- SUPERSEDES: public.npc_plan (0114, sliced by 0115), restated whole; by slices of their LIVE
-- bodies, cmd.run_standing_route (0117) and cmd.standing_route_lines (0114).
-- Self-asserts hold AS FOUND (0118): lit or dark, every probe rolls back and the switch is left
-- as found. The receipt prints the measured cost.

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
update public.world_config set value = to_jsonb(5),
       description = '0120: the least return, in percent of the outlay, a merchant BUY must promise at the next '
                     'stop''s current bid — at planning (public.npc_leg_lines) AND at the moment of buying '
                     '(cmd.standing_route_lines). The owner: "15% is too big. change to 5%".'
 where key = 'npc_min_return_pct';

insert into public.world_config (key, value, description) values
  ('npc_route_candidates', to_jsonb(16),
   '0120: the most loops a merchant prices at a lap start, her present loop included. 0: she keeps '
   'her authored loop (the choice is off).'),
  ('npc_route_neighbours', to_jsonb(5),
   '0120: the nearest known harbours out of her home (public.npc_known_legs) that seed her '
   'out-and-back and three-stop candidate loops.'),
  ('npc_route_far_candidates', to_jsonb(3),
   '0120: the farthest known legs of npc_route_far_nm or more a BIG fleet (hold >= '
   'npc_route_far_hold_tuns) also prices as out-and-back loops — between continents.'),
  ('npc_route_far_nm', to_jsonb(2000),
   '0120: a leg at least this long is a long haul (a candidate only for a big fleet).'),
  ('npc_route_far_hold_tuns', to_jsonb(200),
   '0120: a fleet whose hold is at least this many tuns is offered the long hauls. The roster '
   'measures p50 86, p90 396, max 1,289 tuns.'),
  ('npc_route_switch_pct', to_jsonb(10),
   '0120: a merchant changes loop only when the best candidate pays at least this much more per '
   'real hour than her present loop (0 % present pays nothing: any paying loop wins).'),
  ('npc_preset_days_max', to_jsonb(90),
   '0120: the most days of stores the planner may set on a merchant fleet''s provision preset '
   '(through cmd.provision_preset_save_for) so that she can sail a chosen long haul; and never '
   'more than half her hold in stores.')
on conflict (key) do nothing;

-- ── 2. THE KNOWN LEGS ──────────────────────────────────────────────────────────────────────────
create or replace function public.npc_known_legs(p_from uuid)
returns table (to_port uuid, code text, course jsonb, nm numeric, reversed boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0120: THE COURSES THE WORLD HOLDS out of one harbour: every merchant route's leg from it, and
  -- every merchant route's leg INTO it sailed backwards (the same polyline, the same water; the
  -- roadsteads are its two ends either way, and cmd.do_sail judges it again at every departure).
  -- One per destination — an authored (forward) course before a reversed one, then the fewer
  -- points — with THE sailed distance (voyage.reach_from, the reach table).
  with ms as (
    select s.route_id, s.ord, s.port_id, s.course,
           lead(s.port_id)        over (partition by s.route_id order by s.ord) as nxt,
           first_value(s.port_id) over (partition by s.route_id order by s.ord) as first_port
      from public.standing_route_stops s
      join public.standing_routes sr on sr.id = s.route_id
      join public.players p on p.id = sr.player_id and p.is_npc),
  legs as (
    select m.port_id as a, coalesce(m.nxt, m.first_port) as b, m.course from ms m),
  both_ways as (
    select l.b as to_port, l.course, false as reversed from legs l where l.a = p_from
    union all
    select l.a, (select jsonb_agg(t.x order by t.i desc)
                   from jsonb_array_elements(l.course) with ordinality t(x, i)), true
      from legs l where l.b = p_from)
  select distinct on (w.to_port) w.to_port, p.code, w.course, r.nm, w.reversed
    from both_ways w
    join public.ports p on p.id = w.to_port
    join voyage.reach_from(p_from) r on r.port_id = w.to_port
   where w.to_port <> p_from
   order by w.to_port, w.reversed, jsonb_array_length(w.course)
$$;
revoke all on function public.npc_known_legs(uuid) from public, anon, authenticated;

-- ── 3. THE LEG PLANNER — 0114's rank, filter, size, keep, for ONE leg ─────────────────────────
create or replace function public.npc_leg_lines(p_route uuid, p_from uuid, p_to uuid,
                                                p_hold numeric, p_crew int, p_speed numeric)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- The lines a merchant route writes at p_from bound for p_to, and what they pay. 0114:246-293
-- moved here whole so a loop can be priced without being written (npc_plan prices every candidate
-- loop through this and writes only the winner):
--   1. RANK with THE ranking (world.trade_routes, p_from to p_to, twelve rows), priced end to end
--      through world.quote.
--   2. FILTER: the house's authored wares first (all rows only when no listed good passes), and at
--      most npc_buyers_per_good OTHER merchant routes buying that good here (a laid-up or failed
--      route holds no place) — the count taken ONCE per port, as a good -> buyers map.
--   3. SIZE each kept good with the quote authority's own answer: the units the SINK takes above
--      the probe's cost x (1 + npc_sell_margin), capped by the daily cap at both ends and the hold
--      left. KEEP only if the two quotes at that size beat the leg's wages (running_cost_mult) and
--      return >= npc_min_return_pct on the outlay. The first npc_lines_per_stop.
--   4. LINES: SELL everything above cost (paid + npc_sell_margin); for a good refused E_PRICE_LIMIT
--      on a SELL here in BOTH of the last two closed laps, the cut-loss: SELL <good> ALL at what she
--      paid and not a ducat less (0120 — it had no floor); BUY <good> <q> AT <ceiling>.
-- Answers {lines, profit, nm, any}: `profit` is the sum of (sink quote - source quote) over the
-- kept goods, `nm` the sailed distance from the reach table (the figure the ranking's rows carry),
-- `any` whether anything was kept.
declare
  v_k       int     := public.wc_int('npc_lines_per_stop');
  v_margin  numeric := public.wc_num('npc_sell_margin');
  v_minret  numeric := public.wc_num('npc_min_return_pct');
  v_kmax    int     := public.wc_int('npc_buyers_per_good');
  sr        public.standing_routes%rowtype;
  h         public.npc_houses%rowtype;
  v_code    text;
  v_nm      numeric;
  v_lines   jsonb := jsonb_build_array(jsonb_build_object('kind', 'SELL', 'at_profit', true));
  v_cut     text;
  v_rows    jsonb;
  v_buyers  jsonb;
  e         jsonb;
  v_good    uuid;
  v_bulk    numeric;
  v_cap     numeric;
  v_q       numeric;
  v_ceiling numeric;
  v_left    numeric;
  v_wages   numeric;
  v_kept    int := 0;
  v_pass    int;
  v_profit  numeric := 0;
  v_any     boolean := false;
  q_size    record;
  q_sell    record;
  q_buy     record;
begin
  select * into sr from public.standing_routes where id = p_route;
  select * into h from public.npc_houses where player_id = sr.player_id;
  select p.code into v_code from public.ports p where p.id = p_from;
  select r.nm into v_nm from voyage.reach_from(p_from) r where r.port_id = p_to;

  -- THE CUT-LOSS: refused E_PRICE_LIMIT on a SELL here in BOTH of the last two closed laps.
  for v_cut in
    select z.g from (
      select split_part(x.e->>'line', ' ', 2) as g, count(distinct x.lap_no) as laps
        from (select l.lap_no, jsonb_array_elements(l.skipped) as e
                from (select lp.lap_no, lp.skipped from public.standing_route_laps lp
                       where lp.route_id = sr.id and lp.closed_at is not null
                       order by lp.lap_no desc limit 2) l) x
       where x.e->>'port' = v_code and x.e->>'verb' = 'SELL' and x.e->>'code' = 'E_PRICE_LIMIT'
       group by 1) z
     where z.laps = 2 and exists (select 1 from public.goods g where g.code = z.g)
     order by z.g limit 2 loop
    v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut, 'at_profit', true);   -- 0120: at cost
  end loop;

  -- THE OTHER MERCHANT BUYERS HERE, per good, once (0114 counted them once per candidate good).
  select coalesce(jsonb_object_agg(z.g, z.n), '{}'::jsonb) into v_buyers from (
    select l.good_id::text as g, count(distinct l.route_id) as n
      from public.standing_route_lines l
      join public.standing_route_stops s3 on s3.route_id = l.route_id and s3.ord = l.stop_ord
      join public.standing_routes sr3 on sr3.id = l.route_id
                                     and coalesce(sr3.paused_reason, '') not in ('laid_up', 'error')
      join public.players p3 on p3.id = sr3.player_id and p3.is_npc
     where l.route_id <> sr.id and l.kind = 'BUY' and s3.port_id = p_from
     group by 1) z;

  -- RANK, FILTER, SIZE, KEEP.
  v_rows  := coalesce(world.trade_routes(p_from, null, null, 12, p_to)->'routes', '[]'::jsonb);
  v_left  := p_hold;
  v_wages := public.crew_wages(p_crew, false) * public.running_cost_mult(sr.player_id)
             * coalesce(v_nm, 0) / (greatest(p_speed, 0.1) * 24);
  for v_pass in 1 .. 2 loop
    exit when v_pass = 2 and v_kept > 0;
    for e in select x from jsonb_array_elements(v_rows) x loop
      exit when v_kept >= v_k;
      v_good := (e->>'good_id')::uuid;
      continue when v_pass = 1 and not ((e->>'code') = any(h.wares));
      continue when v_lines @> jsonb_build_array(jsonb_build_object('kind', 'BUY', 'good', e->>'code'));
      continue when coalesce((v_buyers->>(v_good::text))::int, 0) >= v_kmax;
      select g.bulk into v_bulk from public.goods g where g.id = v_good;
      v_cap := floor(least(world.daily_cap_remaining(sr.player_id, p_from, v_good),
                           world.daily_cap_remaining(sr.player_id, p_to, v_good),
                           v_left / greatest(v_bulk, 0.001)));
      continue when v_cap is null or v_cap < 1;
      -- THE SIZE is the sink's own answer: units it takes above the probe's cost plus the margin.
      select * into q_size from world.quote(p_to, v_good, v_cap, 'sell',
                                            round((e->>'buy_price')::numeric * (1 + v_margin), 2), null);
      v_q := floor(coalesce(q_size.units, 0));
      continue when v_q < 1;
      select * into q_buy from world.quote(p_from, v_good, v_q, 'buy', null, null);
      continue when q_buy.units is null or q_buy.units < v_q or q_buy.total <= 0;
      select * into q_sell from world.quote(p_to, v_good, v_q, 'sell', null, null);
      continue when q_sell.total - q_buy.total - v_wages <= 0
                 or (q_sell.total - q_buy.total) * 100 < v_minret * q_buy.total;
      v_ceiling := public.npc_buy_ceiling(p_from, v_good, h.patience);
      continue when v_ceiling is null;
      v_lines  := v_lines || jsonb_build_object('kind', 'BUY', 'good', e->>'code', 'qty', v_q,
                                                'price_limit', v_ceiling);
      v_left   := v_left - v_q * v_bulk;
      v_kept   := v_kept + 1;
      v_profit := v_profit + (q_sell.total - q_buy.total);
      v_any    := true;
    end loop;
  end loop;

  return jsonb_build_object('lines', v_lines, 'profit', v_profit, 'nm', v_nm, 'any', v_any);
end $$;
revoke all on function public.npc_leg_lines(uuid, uuid, uuid, numeric, int, numeric) from public, anon, authenticated;

-- ── 4. THE LEGS A FLEET MAY SAIL out of a harbour ──────────────────────────────────────────────
create or replace function public.npc_feasible_legs(p_port uuid, p_draft int, p_speed numeric, p_days int)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0120: the known legs out of p_port (public.npc_known_legs) a fleet of draft p_draft and speed
  -- p_speed may sail with p_days of stores: a harbour that takes her draft, open (the two berth
  -- facts voyage.sail_refusal reads), and a passage her stores cover at endurance_margin, one day
  -- spare — the stores gate as the sail gate judges it. Nearest first, then the port id.
  select coalesce(jsonb_agg(jsonb_build_object('port_id', l.to_port, 'code', l.code, 'course', l.course, 'nm', l.nm)
                            order by l.nm, l.to_port), '[]'::jsonb)
    from public.npc_known_legs(p_port) l
    join public.ports p on p.id = l.to_port
   where p.kind = 'HARBOUR' and p.max_draft >= p_draft and not p.is_ice_closed
     and ceil(l.nm / (greatest(p_speed, 0.1) * 24) * public.wc_num('endurance_margin'))::int + 1 <= p_days
$$;
revoke all on function public.npc_feasible_legs(uuid, int, numeric, int) from public, anon, authenticated;

-- ── 4b. THE CANDIDATE LOOPS out of her home ────────────────────────────────────────────────────
create or replace function public.npc_loop_candidates(p_route uuid, p_fleet uuid, p_home uuid,
                                                      p_hold numeric, p_speed numeric)
returns table (stops jsonb, kind text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- The loops a merchant may price at a lap start, each a jsonb array of stops
-- [{port_id, code, course, nm}, …] whose stop i's course is the leg to stop i + 1 (the last leg
-- returns home). Bounded by the knobs; every destination must be a harbour that takes her draft,
-- open, and within the days of stores she can carry. Deterministic (ties fall to the port id).
--   near  : out-and-back to each of the npc_route_neighbours nearest known harbours;
--   near3 : home -> B -> C -> home where B and C are neighbours and the roster knows B -> C,
--           the shortest first, filling what npc_route_candidates leaves;
--   far   : (hold >= npc_route_far_hold_tuns) out-and-back on the npc_route_far_candidates
--           farthest known legs of npc_route_far_nm or more; her harbour having none, via each
--           neighbour's farthest such leg (home -> X -> F -> X -> home).
declare
  v_near    int     := public.wc_int('npc_route_neighbours');
  v_farn    int     := public.wc_int('npc_route_far_candidates');
  v_far_nm  numeric := public.wc_num('npc_route_far_nm');
  v_far_hld numeric := public.wc_num('npc_route_far_hold_tuns');
  v_max     int     := public.wc_int('npc_route_candidates');
  v_days_cap int;
  v_draft   int;
  v_capacity numeric;
  v_crew    int;
  v_preset  int;
  v_stores  numeric;
  v_home    jsonb;
  v_legs    jsonb;
  v_nearset jsonb;
  v_farset  jsonb;
  v_cache   jsonb := '{}'::jsonb;
  v_out     int := 0;
  v_room    int;
  b         jsonb;
  c         jsonb;
  v_ret     jsonb;
  v_bc      jsonb;
  v_three   jsonb := '[]'::jsonb;
  t         jsonb;
  v_xf      jsonb;
  v_fx      jsonb;
begin
  select max(cl.draft), coalesce(sum(public.ship_hold_capacity(s.id)), 0), coalesce(sum(s.crew), 0)
    into v_draft, v_capacity, v_crew
    from public.ships s join public.ship_classes cl on cl.id = s.class_id where s.fleet_id = p_fleet;
  select pr.days into v_preset
    from public.fleets f join public.provision_presets pr on pr.id = f.provision_preset_id where f.id = p_fleet;
  v_stores   := v_crew * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day'));
  -- THE DAYS SHE CAN CARRY: her preset as it stands, or what the planner may raise it to — the knob,
  -- and never more than half her hold in stores.
  v_days_cap := greatest(coalesce(v_preset, 0),
                         least(public.wc_int('npc_preset_days_max'),
                               coalesce(floor(0.5 * v_capacity / nullif(v_stores, 0))::int, 0)));
  select jsonb_build_object('port_id', p.id, 'code', p.code) into v_home from public.ports p where p.id = p_home;

  -- the feasible known legs out of a harbour, read once per harbour this call touches
  v_legs := public.npc_feasible_legs(p_home, v_draft, p_speed, v_days_cap);
  v_cache := jsonb_build_object(p_home::text, v_legs);

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_nearset
    from (select x from jsonb_array_elements(v_legs) x where (x->>'nm')::numeric < v_far_nm
           order by (x->>'nm')::numeric, x->>'port_id' limit v_near) z;
  if p_hold >= v_far_hld then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_farset
      from (select x from jsonb_array_elements(v_legs) x where (x->>'nm')::numeric >= v_far_nm
             order by (x->>'nm')::numeric desc, x->>'port_id' limit v_farn) z;
  else
    v_farset := '[]'::jsonb;
  end if;

  -- OUT AND BACK, near then far. The way back is a known leg of the destination's.
  for b in select x from jsonb_array_elements(v_nearset || v_farset) x loop
    exit when v_out >= v_max - 1;
    if not v_cache ? (b->>'port_id') then
      v_cache := v_cache || jsonb_build_object(b->>'port_id',
                   public.npc_feasible_legs((b->>'port_id')::uuid, v_draft, p_speed, v_days_cap));
    end if;
    select x into v_ret from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = p_home::text;
    continue when v_ret is null;
    stops := jsonb_build_array(v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
                              jsonb_build_object('port_id', b->'port_id', 'code', b->'code',
                                                 'course', v_ret->'course', 'nm', v_ret->'nm'));
    kind := case when (b->>'nm')::numeric >= v_far_nm then 'far' else 'near' end;
    v_out := v_out + 1;
    return next;
  end loop;

  -- FAR VIA A NEIGHBOUR, when her own harbour has no long haul: home -> X -> F -> X -> home.
  if p_hold >= v_far_hld and jsonb_array_length(v_farset) = 0 then
    for b in select x from jsonb_array_elements(v_nearset) x loop
      exit when v_out >= v_max - 1 or v_farn <= 0;
      select x into v_xf from jsonb_array_elements(v_cache->(b->>'port_id')) x
       where (x->>'nm')::numeric >= v_far_nm order by (x->>'nm')::numeric desc, x->>'port_id' limit 1;
      continue when v_xf is null;
      if not v_cache ? (v_xf->>'port_id') then
        v_cache := v_cache || jsonb_build_object(v_xf->>'port_id',
                     public.npc_feasible_legs((v_xf->>'port_id')::uuid, v_draft, p_speed, v_days_cap));
      end if;
      select x into v_fx from jsonb_array_elements(v_cache->(v_xf->>'port_id')) x where x->>'port_id' = b->>'port_id';
      select x into v_ret from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = p_home::text;
      continue when v_fx is null or v_ret is null;
      stops := jsonb_build_array(
        v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
        jsonb_build_object('port_id', b->'port_id', 'code', b->'code', 'course', v_xf->'course', 'nm', v_xf->'nm'),
        jsonb_build_object('port_id', v_xf->'port_id', 'code', v_xf->'code', 'course', v_fx->'course', 'nm', v_fx->'nm'),
        jsonb_build_object('port_id', b->'port_id', 'code', b->'code', 'course', v_ret->'course', 'nm', v_ret->'nm'));
      kind := 'far';
      v_out := v_out + 1;
      v_farn := v_farn - 1;
      return next;
    end loop;
  end if;

  -- THREE STOPS among the neighbours, the shortest first, into the room that is left.
  v_room := v_max - 1 - v_out;
  if v_room > 0 then
    for b in select x from jsonb_array_elements(v_nearset) x loop
      for c in select x from jsonb_array_elements(v_nearset) x loop
        continue when c->>'port_id' = b->>'port_id';
        select x into v_bc from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = c->>'port_id';
        continue when v_bc is null;
        select x into v_ret from jsonb_array_elements(v_cache->(c->>'port_id')) x where x->>'port_id' = p_home::text;
        continue when v_ret is null;
        v_three := v_three || jsonb_build_object(
          'nm', (b->>'nm')::numeric + (v_bc->>'nm')::numeric + (v_ret->>'nm')::numeric,
          'loop', jsonb_build_array(
            v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
            jsonb_build_object('port_id', b->'port_id', 'code', b->'code', 'course', v_bc->'course', 'nm', v_bc->'nm'),
            jsonb_build_object('port_id', c->'port_id', 'code', c->'code', 'course', v_ret->'course', 'nm', v_ret->'nm')));
      end loop;
    end loop;
    for t in select x from jsonb_array_elements(v_three) x
              order by (x->>'nm')::numeric, x->'loop'->1->>'port_id', x->'loop'->2->>'port_id' limit v_room loop
      stops := t->'loop';
      kind := 'near3';
      return next;
    end loop;
  end if;
  return;
end $$;
revoke all on function public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric) from public, anon, authenticated;

-- ── 5. THE PLANNER, SUPERSEDED (0114 as sliced by 0115) ────────────────────────────────────────
create or replace function public.npc_plan(p_now timestamptz default now(), p_route uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- Writes each merchant route's STOPS and LINES from the market through cmd.standing_route_save_for.
-- Every leg's lines come from THE leg planner (public.npc_leg_lines: 0114's rank, filter, size,
-- keep); this function decides WHICH LOOP and writes it.
--   * A PASS (p_route null — the switch) or a route not at a lap start: her present loop, re-lined.
--   * A LAP START (p_route named, her fleet docked at her stop 0 with no open lap): her present
--     loop and up to npc_route_candidates others (public.npc_loop_candidates), each priced through
--     the leg planner with every distinct leg priced once, scored in ducats per REAL hour of the
--     lap — sea time at her speed through time_compression, plus her rest (route_rest_voyage_days).
--     The best wins when it beats her present loop by npc_route_switch_pct; a longer leg than her
--     stores cover raises her preset through cmd.provision_preset_save_for first (the candidates
--     already stop at npc_preset_days_max and half her hold), and a refused raise keeps her loop.
--     Counted `chosen`; the loops priced, `candidates`.
--   * Nothing pays on any leg of the loop written: it is written as it stands — SELL at a profit at
--     every stop and no BUY — and she sails it in ballast (0115). Counted `ballast`.
-- The pass takes the route planned LONGEST AGO first (updated_at) and defers past the upkeep
-- budget (public.npc_upkeep_spent); a route not reached is counted `deferred`, never half-planned.
-- Routes paused 'error' or 'laid_up' are skipped by the pass; npc_tend re-plans one alone.
-- Locks fleet then route, NOWAIT: a busy route is skipped, never waited for.
declare
  v_pace    int     := public.wc_int('npc_laps_per_game_day');
  v_cand    int     := public.wc_int('npc_route_candidates');
  v_switch  numeric := public.wc_num('npc_route_switch_pct');
  v_emargin numeric := public.wc_num('endurance_margin');
  v_comp    numeric := public.wc_num('time_compression');
  v_rest_h  numeric := public.wc_num('route_rest_voyage_days') * 86400 / public.wc_num('time_compression') / 3600;
  v_day_h   numeric := public.wc_num('game_day_seconds') / 3600;   -- the daily cap's period, in real hours
  r         record;
  lp        record;
  sr        public.standing_routes%rowtype;
  f         public.fleets%rowtype;
  v_n       int;
  v_hold    numeric;
  v_crew    int;
  v_speed   numeric;
  v_choose  boolean;
  v_loops   jsonb;
  v_loop    jsonb;
  v_len     int;
  v_memo    jsonb;
  v_key     text;
  v_leg     jsonb;
  v_from    uuid;
  v_to      uuid;
  v_stops   jsonb;
  v_profit  numeric;
  v_nm      numeric;
  v_maxnm   numeric;
  v_any     boolean;
  v_score   numeric;
  v_cur_stops jsonb;
  v_cur_score numeric;
  v_cur_any boolean;
  v_best_i  int;
  v_best_stops jsonb;
  v_best_score numeric;
  v_best_any boolean;
  v_best_maxnm numeric;
  v_days    int;
  v_preset  int;
  v_res     jsonb;
  i         int;
  j         int;
  v_planned int := 0;
  v_laid    int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_chosen  int := 0;
  v_cands   int := 0;
  v_notes   jsonb := '[]'::jsonb;
begin
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false);
  end if;
  for r in
    select nf.fleet_id, nf.route_id
      from public.npc_fleets nf
      join public.players p on p.id = nf.player_id and p.is_npc
      join public.standing_routes sr0 on sr0.id = nf.route_id
     where (p_route is null and coalesce(sr0.paused_reason, '') not in ('error', 'laid_up'))
        or nf.route_id = p_route
     order by sr0.updated_at, nf.roster_ord
  loop
    -- THE BUDGET (0114). Past the upkeep's deadline a route is not begun.
    if public.npc_upkeep_spent() then
      v_deferred := v_deferred + 1;
      continue;
    end if;
    begin
      -- FLEET BEFORE ROUTE, and never wait (§4.5).
      perform 1 from public.fleets where id = r.fleet_id for update nowait;
      select * into sr from public.standing_routes where id = r.route_id for update nowait;
      select * into f from public.fleets where id = r.fleet_id;
      select count(*) into v_n from public.standing_route_stops where route_id = sr.id;
      select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0)
        into v_crew, v_hold
        from public.ships s join public.ship_classes c on c.id = s.class_id
       where s.fleet_id = r.fleet_id;
      v_hold  := v_hold + public.fleet_free_hold(r.fleet_id);
      v_speed := greatest(coalesce(voyage.fleet_speed(r.fleet_id), 0), 0.1);

      -- LOOP 0 IS HER PRESENT LOOP.
      select jsonb_agg(jsonb_build_object('port_id', s.port_id, 'code', p.code, 'course', s.course) order by s.ord)
        into v_loop
        from public.standing_route_stops s join public.ports p on p.id = s.port_id
       where s.route_id = sr.id;
      v_loops := jsonb_build_array(v_loop);

      -- THE CHOICE, at her lap start only: planned alone, her fleet lying at her stop 0 between
      -- laps. The switch's pass (p_route null) and a route mid-lap keep their loop.
      v_choose := p_route is not null and v_cand > 0 and sr.fleet_id = r.fleet_id and sr.lap_id is null
                  and f.status = 'DOCKED' and f.port_id = (v_loop->0->>'port_id')::uuid;
      if v_choose then
        for lp in select * from public.npc_loop_candidates(sr.id, r.fleet_id, f.port_id, v_hold, v_speed) loop
          exit when jsonb_array_length(v_loops) >= v_cand;
          v_loops := v_loops || jsonb_build_array(lp.stops);
        end loop;
      end if;

      -- PRICE EVERY LOOP through the leg planner, each distinct leg once.
      v_memo := '{}'::jsonb;
      v_best_i := 0;
      for i in 0 .. jsonb_array_length(v_loops) - 1 loop
        v_loop   := v_loops->i;
        v_len    := jsonb_array_length(v_loop);
        v_stops  := '[]'::jsonb;
        v_profit := 0;
        v_nm     := 0;
        v_maxnm  := 0;
        v_any    := false;
        for j in 0 .. v_len - 1 loop
          v_from := (v_loop->j->>'port_id')::uuid;
          v_to   := (v_loop->((j + 1) % v_len)->>'port_id')::uuid;
          v_key  := v_from::text || '>' || v_to::text;
          if v_memo ? v_key then
            v_leg := v_memo->v_key;
          else
            v_leg  := public.npc_leg_lines(sr.id, v_from, v_to, v_hold, v_crew, v_speed);
            v_memo := v_memo || jsonb_build_object(v_key, v_leg);
          end if;
          v_stops  := v_stops || jsonb_build_object('port', v_loop->j->>'code', 'course', v_loop->j->'course',
                                                   'repair', j = 0, 'crew_up', true, 'lines', v_leg->'lines');
          v_profit := v_profit + coalesce((v_leg->>'profit')::numeric, 0);
          v_nm     := v_nm + coalesce((v_leg->>'nm')::numeric, 0);
          v_maxnm  := greatest(v_maxnm, coalesce((v_leg->>'nm')::numeric, 0));
          v_any    := v_any or coalesce((v_leg->>'any')::boolean, false);
        end loop;
        -- DUCATS PER REAL HOUR of the lap: nm / kn is voyage-hours; through the compression, real;
        -- plus her rest; and never less than a game-day, because the daily cap lets her buy a
        -- parcel once a game-day — a five-minute hop does not sell its parcel eleven times an hour.
        v_score := v_profit / greatest(v_nm / v_speed / v_comp + v_rest_h, v_day_h);
        if i = 0 then
          v_cur_stops := v_stops; v_cur_score := v_score; v_cur_any := v_any;
          v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm;
        elsif v_score > v_best_score then
          v_best_i := i; v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm;
        end if;
      end loop;
      v_cands := v_cands + jsonb_array_length(v_loops);

      -- SHE CHANGES LOOP only when the best pays npc_route_switch_pct more per hour than her own.
      if v_best_i <> 0 and not (v_best_score > 0 and v_best_score >= v_cur_score * (1 + v_switch / 100)) then
        v_best_i := 0;
      end if;
      if v_best_i <> 0 then
        -- A LONGER LEG THAN HER STORES COVER raises her preset through the preset core (the
        -- candidates already stop at npc_preset_days_max and half her hold).
        v_days := ceil(v_best_maxnm / (v_speed * 24) * v_emargin)::int + 1;
        select pr.days into v_preset from public.provision_presets pr where pr.id = f.provision_preset_id;
        if v_preset is not null and v_days > v_preset then
          v_res := cmd.provision_preset_save_for(sr.player_id, f.provision_preset_id, null, v_days);
          if not coalesce((v_res->>'ok')::boolean, false) then
            v_notes := v_notes || jsonb_build_object('route', sr.name, 'preset_refused', v_res->>'error_code');
            v_best_i := 0;
          end if;
        end if;
      end if;
      if v_best_i <> 0 then
        v_stops := v_best_stops; v_any := v_best_any;
        v_chosen := v_chosen + 1;
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'chosen',
                     (select string_agg(x->>'port', '-' order by k) from jsonb_array_elements(v_best_stops) with ordinality t(x, k)),
                     'per_hour', round(v_best_score), 'was', round(v_cur_score));
      else
        v_stops := v_cur_stops; v_any := v_cur_any;
      end if;

      -- 0115: A MERCHANT IS NEVER PARKED. Nothing pays: the loop is written as it stands — SELL
      -- at a profit at every stop and no BUY — and she sails it in ballast. Counted `ballast`.
      if not v_any then
        v_laid := v_laid + 1;
      end if;
      v_res := cmd.standing_route_save_for(sr.player_id, sr.id, null, v_stops, null, null, v_pace);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_plan: the save door refused % — %', sr.name, v_res->>'error_message';
      end if;
      v_planned := v_planned + 1;
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('route', r.route_id, 'error', sqlerrm);
    end;
  end loop;

  return jsonb_build_object('enabled', true, 'planned', v_planned, 'ballast', v_laid,
                            'chosen', v_chosen, 'candidates', v_cands,
                            'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred, 'notes', v_notes);
end $$;

-- ── 6. THE SLICES — each hunk asserted to occur EXACTLY ONCE in the LIVE body (LF-normalised) ───
create or replace function pg_temp.slice_0120(p_fn text, p_old text, p_new text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  v_n   int  := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
begin
  if v_n <> 1 then
    raise exception '0120 self-assert FAIL: a hunk of % occurs % time(s), not once — the live body is not what this file was cut against: %',
      p_fn, v_n, left(p_old, 120);
  end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- (1) THE EXECUTOR reads the loop the plan may have changed.
select pg_temp.slice_0120('cmd.run_standing_route(uuid, timestamptz)',
$h$      v_plan := public.npc_plan(p_now, sr.id);
      if (select paused_reason from public.standing_routes where id = sr.id) is not null then
        return 0;
      end if;
    end if;
$h$,
$h$      v_plan := public.npc_plan(p_now, sr.id);
      if (select paused_reason from public.standing_routes where id = sr.id) is not null then
        return 0;
      end if;
      -- 0120: THE PLAN MAY HAVE CHANGED HER LOOP. Re-read the route, its stop count and the stop
      -- she lies at, so the orders written below — and the course the SAIL carries — are the
      -- chosen loop's, never the record read before the plan.
      select * into sr from public.standing_routes where id = sr.id;
      select count(*) into v_n from public.standing_route_stops where route_id = sr.id;
      select s.*, p.code, p.kind into cur
        from public.standing_route_stops s join public.ports p on p.id = s.port_id
       where s.route_id = sr.id and s.ord = sr.stop_cursor % v_n;
      if cur.port_id is distinct from f.port_id then
        raise exception 'E_ROUTE_BROKEN: the loop planned for % does not start where she lies', f.name using errcode = 'P0001';
      end if;
    end if;
$h$);

-- (2) THE RENDERER: the margin is the general SELL's; a named at-profit SELL — the cut-loss — floors
--     at what she paid.
select pg_temp.slice_0120('cmd.standing_route_lines(uuid, integer, uuid)',
$h$      if v_npc and ln.at_profit and v_floor is not null then
        v_floor := v_floor * (1 + public.wc_num('npc_sell_margin'));
      end if;
$h$,
$h$      -- 0120: the margin is the GENERAL at-profit SELL's (no good named). A NAMED at-profit SELL
      -- is the cut-loss: she lets that parcel go at what she paid, and never below.
      if v_npc and ln.at_profit and ln.good_id is null and v_floor is not null then
        v_floor := v_floor * (1 + public.wc_num('npc_sell_margin'));
      end if;
$h$);

-- ── 7. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_was_on  boolean := public.npc_traders_on();
  v_routes_on boolean := public.standing_routes_on();
  v_n       int;
  v_route   uuid;
  v_fleet   uuid;
  v_player  uuid;
  v_home    uuid;
  v_before  text[];
  v_after   text[];
  v_res     jsonb;
  v_note    jsonb;
  v_stops   jsonb;
  v_t0      timestamptz;
  v_ms      numeric;
  v_sum_ms  numeric := 0;
  v_max_ms  numeric := 0;
  v_k       int := 0;
  v_goods   text[];
  v_lines   text[];
  v_big     uuid;
  v_big_home uuid;
  v_big_hold numeric;
  v_cands   int;
  v_far     int;
  v_sail    record;
  v_r       record;
  v_s       record;
begin
  -- (a) THE KNOBS, as this file argues them (a pre-existing key is kept as found by `on conflict do
  --     nothing`, so a different value is a FAIL, not a silent drift).
  if public.wc_num('npc_min_return_pct') <> 5 or public.wc_int('npc_route_candidates') <> 16
     or public.wc_int('npc_route_neighbours') <> 5 or public.wc_int('npc_route_far_candidates') <> 3
     or public.wc_num('npc_route_far_nm') <> 2000 or public.wc_num('npc_route_far_hold_tuns') <> 200
     or public.wc_num('npc_route_switch_pct') <> 10 or public.wc_int('npc_preset_days_max') <> 90 then
    raise exception '0120 self-assert FAIL: the knobs do not read as written (min return % %%)', public.wc_num('npc_min_return_pct');
  end if;

  -- (b) ONE AUTHORITY EACH. The keep test (min return, buyer cap, wages) lives in npc_leg_lines
  --     and nowhere in npc_plan; npc_plan composes the leg planner and the candidates; the
  --     executor re-reads the loop; the save door loops over no point.
  if position('npc_leg_lines(' in pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure)) = 0
     or position('npc_loop_candidates(' in pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure)) = 0
     or position('npc_min_return_pct' in pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure)) > 0
     or position('npc_buyers_per_good' in pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure)) > 0
     or position('world.trade_routes(' in pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure)) > 0
     or position($q$wc_num('npc_min_return_pct')$q$ in pg_get_functiondef('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'::regprocedure)) = 0
     or position('running_cost_mult(sr.player_id)' in pg_get_functiondef('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'::regprocedure)) = 0
     or position('npc_upkeep_spent()' in pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure)) = 0
     or position($q$true, 'laid_up'$q$ in pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure)) > 0
     or position('0120: THE PLAN MAY HAVE CHANGED HER LOOP' in pg_get_functiondef('cmd.run_standing_route(uuid, timestamptz)'::regprocedure)) = 0
     or position($q$'good', v_cut, 'at_profit', true$q$ in pg_get_functiondef('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'::regprocedure)) = 0
     or position('ln.at_profit and ln.good_id is null and v_floor is not null' in pg_get_functiondef('cmd.standing_route_lines(uuid, integer, uuid)'::regprocedure)) = 0 then
    raise exception '0120 self-assert FAIL: a slice did not land, or a rule has two authors';
  end if;
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not like 'pg_temp%' and p.prosrc like '%wc_num(''npc_min_return_pct'')%';
  if v_n <> 2 then   -- the leg planner, and the buy cap at the moment of buying (0114)
    raise exception '0120 self-assert FAIL: % functions read npc_min_return_pct, not two', v_n;
  end if;

  -- (c) BEHAVIOUR, lit, rolled back.
  begin
    update public.world_config set value = 'true'::jsonb where key = 'npc_traders_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    perform set_config('byeharu.npc_upkeep_deadline', '', true);
    if not public.npc_traders_on() then
      raise exception '0120 self-assert FAIL: the probe could not light the merchants';
    end if;

    -- THE KNOWN LEGS are loops' worth of courses: from every merchant home there is a way out, and
    -- a leg out of A to B is a leg out of B to A.
    select nf.route_id, nf.fleet_id, sr.player_id into v_route, v_fleet, v_player
      from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
      join public.fleets f on f.id = nf.fleet_id
     where f.status not in ('ADRIFT', 'UNABLE_TO_SAIL') order by nf.roster_ord, nf.fleet_id limit 1;
    if v_route is null then
      raise exception '0120 self-assert FAIL: no merchant route to probe';
    end if;
    select s.port_id into v_home from public.standing_route_stops s where s.route_id = v_route and s.ord = 0;
    select count(*) into v_n from public.npc_known_legs(v_home);
    if v_n = 0 then
      raise exception '0120 self-assert FAIL: no known leg out of the first merchant home';
    end if;
    for v_r in select l.to_port, l.course from public.npc_known_legs(v_home) l limit 3 loop
      if not exists (select 1 from public.npc_known_legs(v_r.to_port) x where x.to_port = v_home) then
        raise exception '0120 self-assert FAIL: a known leg has no way back';
      end if;
    end loop;

    -- THE CUT-LOSS FLOORS AT COST: a parcel aboard at 50 under a named at-profit SELL renders
    -- `AT >= 50`; one at 40 under the general SELL renders at 40 x (1 + npc_sell_margin).
    select array_agg(g.code order by g.code) into v_goods from (select code from public.goods order by code limit 2) g;
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_fleet;
    update public.ships set cargo = jsonb_build_object(v_goods[1], 10, v_goods[2], 10),
                            cargo_basis = jsonb_build_object(v_goods[1], 50, v_goods[2], 40)
     where id = (select s.id from public.ships s where s.fleet_id = v_fleet order by s.id limit 1);
    delete from public.standing_route_lines where route_id = v_route and stop_ord = 0;
    insert into public.standing_route_lines (route_id, stop_ord, ord, kind, good_id, qty, price_limit, at_profit) values
      (v_route, 0, 0, 'SELL', null, null, null, true),
      (v_route, 0, 1, 'SELL', (select id from public.goods where code = v_goods[1]), null, null, true);
    v_lines := cmd.standing_route_lines(v_route, 0, v_fleet);
    if not (v_lines @> array[format('SELL %s ALL AT >= 50', v_goods[1])])
       or not (v_lines @> array[format('SELL %s ALL AT >= %s', v_goods[2],
                                       trim_scale(round(ceil(40 * (1 + public.wc_num('npc_sell_margin')) * 100) / 100, 2))::text)]) then
      raise exception '0120 self-assert FAIL: the cut-loss or the general SELL floors wrong: %', v_lines;
    end if;

    -- THE CHOICE. The subject: the first merchant route (roster order) whose fleet can sail and
    -- that the planner, at a lap start, moves to a better loop. The loop found must be a loop of
    -- known legs starting where she lies, better per hour than the one she had. No route in the
    -- first forty changing loop would be a finding, not a pass.
    v_route := null;
    for v_r in select nf.route_id, nf.fleet_id, sr.player_id, sr.name
               from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
               join public.fleets f on f.id = nf.fleet_id
              where f.status not in ('ADRIFT', 'UNABLE_TO_SAIL') order by nf.roster_ord, nf.fleet_id limit 40 loop
      begin
        -- AS AT A LAP START: assigned, docked at her stop 0, no open lap.
        update public.standing_routes set fleet_id = v_r.fleet_id, lap_id = null, stop_cursor = 0, paused_reason = null, hold_until = null
         where id = v_r.route_id;
        update public.fleets set status = 'DOCKED', port_id = (select port_id from public.standing_route_stops where route_id = v_r.route_id and ord = 0)
         where id = v_r.fleet_id;
        select array_agg(p.code order by s.ord) into v_before from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = v_r.route_id;
        v_t0 := clock_timestamp();
        v_res := public.npc_plan(now(), v_r.route_id);
        v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
        v_k := v_k + 1; v_sum_ms := v_sum_ms + v_ms; v_max_ms := greatest(v_max_ms, v_ms);
        if (v_res->>'planned')::int is distinct from 1 or (v_res->>'failed')::int is distinct from 0
           or (v_res->>'candidates')::int is null or (v_res->>'candidates')::int < 1 then
          raise exception '0120 self-assert FAIL: the lap-start plan of % answered %', v_r.name, v_res;
        end if;
        select array_agg(p.code order by s.ord) into v_after from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = v_r.route_id;
        if (v_res->>'chosen')::int = 1 then
          if v_before = v_after then
            raise exception '0120 self-assert FAIL: % chose a loop and kept her stops', v_r.name;
          end if;
          v_route := v_r.route_id; v_fleet := v_r.fleet_id; v_player := v_r.player_id;
          v_note := (select x from jsonb_array_elements(v_res->'notes') x where x ? 'chosen' limit 1);
          raise exception 'KEEP_0120';
        elsif v_before <> v_after then
          raise exception '0120 self-assert FAIL: % chose nothing and her stops changed', v_r.name;
        end if;
        raise exception 'ROLLBACK_0120_ONE';
      exception when others then
        if sqlerrm = 'KEEP_0120' then exit; end if;
        if sqlerrm <> 'ROLLBACK_0120_ONE' then raise; end if;
      end;
    end loop;
    if v_route is null then
      raise exception '0120 self-assert FAIL: none of the first % merchant routes changed loop at a lap start', v_k;
    end if;
    -- (KEEP_0120 unwound the subject's trial like the others; she is set up again for the probes below.)
    update public.standing_routes set fleet_id = v_fleet, lap_id = null, stop_cursor = 0, paused_reason = null, hold_until = null
     where id = v_route;
    update public.fleets set status = 'DOCKED', port_id = (select port_id from public.standing_route_stops where route_id = v_route and ord = 0)
     where id = v_fleet;
    select array_agg(p.code order by s.ord) into v_before from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = v_route;
    select f.port_id into v_home from public.fleets f where f.id = v_fleet;

    -- THE POSITIVE CONTROL: with the choice off, the same lap-start plan keeps her stops exactly.
    update public.world_config set value = to_jsonb(0) where key = 'npc_route_candidates';
    v_res := public.npc_plan(now(), v_route);
    select array_agg(p.code order by s.ord) into v_after from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = v_route;
    if (v_res->>'planned')::int is distinct from 1 or (v_res->>'chosen')::int is distinct from 0
       or (v_res->>'candidates')::int is distinct from 1 or v_before is distinct from v_after then
      raise exception '0120 self-assert FAIL: with the choice off the plan answered % and left stops %', v_res - 'notes', v_after;
    end if;
    update public.world_config set value = to_jsonb(16) where key = 'npc_route_candidates';

    -- THE EXECUTOR, end to end: at her lap start it plans (the choice), and the orders it writes
    -- are the chosen loop's — the SAIL names the new stop 1 and carries the new stop 0's course.
    update public.standing_routes set updated_at = now() - interval '2 minutes' where id = v_route;
    perform cmd.clear_for(v_player, v_fleet, false);
    v_n := cmd.run_standing_route(v_fleet, now());
    select array_agg(p.code order by s.ord) into v_after from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = v_route;
    if v_n < 1 or v_after is not distinct from v_before or v_after[1] <> (select code from public.ports where id = v_home) then
      raise exception '0120 self-assert FAIL: the executor wrote % order(s) and the loop reads % (was %)', v_n, v_after, v_before;
    end if;
    if (select paused_reason from public.standing_routes where id = v_route) is not null then
      raise exception '0120 self-assert FAIL: the executor paused the probe: %', (select paused_reason from public.standing_routes where id = v_route);
    end if;
    select o.raw_text, o.args into v_sail from public.orders o where o.fleet_id = v_fleet and o.verb = 'SAIL' and o.status = 'pending' order by o.seq desc limit 1;
    if v_sail.raw_text is distinct from 'SAIL TO ' || v_after[2]
       or v_sail.args->'path' is distinct from (select s.course from public.standing_route_stops s where s.route_id = v_route and s.ord = 0) then
      raise exception '0120 self-assert FAIL: the SAIL written reads "%" with a course that is not the new stop 0''s (loop %)', v_sail.raw_text, v_after;
    end if;
    -- every leg of the loop she now sails is a known leg out of its stop, course and all
    for v_s in select st.ord, st.port_id, st.course,
                    (select s2.port_id from public.standing_route_stops s2 where s2.route_id = st.route_id
                      and s2.ord = (st.ord + 1) % (select count(*) from public.standing_route_stops s3 where s3.route_id = st.route_id)) as nxt
               from public.standing_route_stops st where st.route_id = v_route loop
      if not exists (select 1 from public.npc_known_legs(v_s.port_id) l where l.to_port = v_s.nxt and l.course = v_s.course) then
        raise exception '0120 self-assert FAIL: stop % of the chosen loop sails a course the world does not hold', v_s.ord;
      end if;
    end loop;

    -- THE FAR GATE: the biggest hold in the roster is offered the long hauls when a feasible one
    -- is known out of her home; a small hold is offered none.
    select nf.fleet_id, nf.route_id, s.port_id, sum(public.ship_cargo_tuns(sh.id)) + public.fleet_free_hold(nf.fleet_id)
      into v_big, v_route, v_big_home, v_big_hold
      from public.npc_fleets nf join public.ships sh on sh.fleet_id = nf.fleet_id
      join public.standing_route_stops s on s.route_id = nf.route_id and s.ord = 0
     group by nf.fleet_id, nf.route_id, s.port_id order by 4 desc limit 1;
    select count(*), count(*) filter (where kind = 'far') into v_cands, v_far
      from public.npc_loop_candidates(v_route, v_big, v_big_home, v_big_hold, greatest(voyage.fleet_speed(v_big), 0.1));
    if v_cands > public.wc_int('npc_route_candidates') - 1 then
      raise exception '0120 self-assert FAIL: % candidate loops, over the knob', v_cands;
    end if;
    if v_far = 0 and exists (select 1 from public.npc_known_legs(v_big_home) l where l.nm >= public.wc_num('npc_route_far_nm')) then
      -- a far leg is known out of her home: it was refused only by draft, closure or stores
      v_note := coalesce(v_note, '{}'::jsonb) || jsonb_build_object('far_refused_for_the_biggest_hold', true);
    end if;
    if v_big_hold >= public.wc_num('npc_route_far_hold_tuns')
       and exists (select 1 from public.npc_loop_candidates(v_route, v_big, v_big_home,
                                 public.wc_num('npc_route_far_hold_tuns') - 1, greatest(voyage.fleet_speed(v_big), 0.1)) where kind = 'far') then
      raise exception '0120 self-assert FAIL: a hold under the far threshold was offered a long haul';
    end if;
    for v_r in select c.stops, c.kind from public.npc_loop_candidates(v_route, v_big, v_big_home, v_big_hold, greatest(voyage.fleet_speed(v_big), 0.1)) c loop
      if v_r.stops->0->>'port_id' <> v_big_home::text or jsonb_array_length(v_r.stops) < 2
         or exists (select 1 from jsonb_array_elements(v_r.stops) with ordinality t(x, k)
                     where x->>'port_id' = (v_r.stops->(k::int % jsonb_array_length(v_r.stops))->>'port_id')) then
        raise exception '0120 self-assert FAIL: a candidate is not a loop out of her home: %', v_r.kind;
      end if;
    end loop;

    raise exception 'ROLLBACK_0120';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0120' then raise; end if;
  end;

  -- EVERYTHING ABOVE WAS UNDONE.
  if public.npc_traders_on() is distinct from v_was_on or public.standing_routes_on() is distinct from v_routes_on
     or public.wc_int('npc_route_candidates') <> 16 or public.npc_upkeep_spent() then
    raise exception '0120 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0120 self-assert ok: A MERCHANT CHOOSES HER OWN LOOP. Min return 5 %%; the keep test has one author '
    '(npc_leg_lines) and the plan composes it and the candidates; the cut-loss floors at cost (a 50 parcel rendered '
    'AT >= 50, the general SELL at 40 plus the margin); with the choice off a lap-start plan kept the stops; the '
    'executor at a lap start wrote the chosen loop''s orders (the SAIL carries the new course) and every leg she sails '
    'is a known leg; the biggest hold was offered % candidate loop(s), % far, a small hold none; the first route to '
    'change loop: %. Lap-start plan over % route(s): mean % ms, max % ms. Rolled back; switch as found (%).',
    v_cands, v_far, v_note, v_k, round(v_sum_ms / greatest(v_k, 1)), round(v_max_ms),
    case when v_was_on then 'lit' else 'dark' end;
end $$;
