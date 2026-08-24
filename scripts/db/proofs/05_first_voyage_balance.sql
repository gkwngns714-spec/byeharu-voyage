-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 5 — WHAT A FIRST VOYAGE PAYS
--
-- Balance is a number, and a number that nothing measures will drift. The first version of this
-- world paid **32% of the stake** for one twenty-five-minute round trip: the purse doubled in two
-- voyages, before the player had learned the map. That was not found by playing — it was found by
-- measuring, and it is held here so it cannot come back.
--
-- ── 2026-08-22: THIS PROOF NO LONGER RUNS ITS OWN SEARCH ───────────────────────────────────────
-- It used to answer "what is the best one-leg trade out of this port?" with sixty lines of its own
-- — its own candidate ranking by affinity, its own halving walk down to something the purse could
-- afford, its own pairing of quotes. Migration 0019 made that question a READ,
-- `world.trade_routes()`, because a player could not answer it at all. Two implementations of one
-- question is the duplication docs/NO_SPAGHETTI.md §1 forbids, and this was the copy to delete:
-- keeping it would have meant this proof measuring an economy the game never shows anybody.
--
-- So the balance is now measured **on the number the player is actually offered**, which is a
-- strictly stronger claim than the old one: if the quay's figure and the economy ever part company,
-- this goes red.
--
-- ── THE PIN MOVED DELIBERATELY, AND HERE IS WHY ────────────────────────────────────────────────
-- The median first voyage reads **12.1 per cent** through the read where it read **9.7 per cent**
-- through the old private search (measured 2026-08-22, PGlite 0.5.5 / PostgreSQL 18.3, the same
-- eight ports, the same chain, no price changed by 0019). THE ECONOMY DID NOT MOVE — THE
-- MEASUREMENT GOT HONEST. The old walk halved from the free hold (55 → 27 → 13 …) and stopped at
-- whatever power of two the purse could cover; `world.trade_routes` prices at
-- `public.fleet_buy_capacity`, the same authority that resolves `ALL` when the order actually runs,
-- which stops at whichever of hold, stock, the daily cap and the purse binds first. The old figure
-- understated what a first voyage has always paid. The band is unchanged and 12.1 sits inside it.
--
-- WHAT THIS ASSERTS, AND WHY EACH ONE
--   * THE OPENING VOYAGE PAYS, EVERYWHERE. From a sample of starting ports, the best one-leg round
--     trip the quay offers returns something. A world where the best available trade loses money
--     has no game in it.
--   * IT DOES NOT PAY TOO MUCH. The median sits inside a band. Above it the economy is a printer;
--     below it, the voyage is not worth the twenty-five minutes.
--   * DISTANCE IS WHAT PAYS. The long legs must out-earn the short ones — otherwise there is no
--     reason to ever leave home waters, and the 214-port world collapses to whatever is nearest.
--     This is now POOLED OVER EVERY ROUTE THE QUAY OFFERS, at its own default reach, rather than
--     over the single best trade per port. The old form compared one number per port and had a
--     `skipped` branch for when a bucket came up empty — and on 2026-08-22 that branch started
--     firing, because at ONE leg from the eight largest ports nothing is over 800 nm at all. A
--     marker that passes by skipping is exactly the vacuous pass scripts/db/proof.mjs exists to
--     refuse, so the branch is gone: both buckets must be non-empty and the long one must win.
--   * AND THE SHORTLIST IS NOT COSTING THE PLAYER ANYTHING. `world.trade_routes` shortlists
--     candidates by authored affinity before it prices anything (0019's stage 1), which is a
--     heuristic. So one sampled port is ALSO scanned EXHAUSTIVELY — every good against every
--     one-leg destination, priced through the same quotes — and the read must find a trade at
--     least as good. Without this the cheap stage could quietly degrade and nothing would notice.
--
-- The knobs behind the first three live in world_config (`affinity_*`, migration 0005) and are
-- swept by scripts/db/tune-balance.mjs. If this proof goes red, run that sweep and read the table
-- it prints rather than nudging a constant until the red goes away.
--
-- @pass BALANCE_EVERY_PORT_HAS_A_TRADE   every sampled starting port offers a profitable first voyage
-- @pass BALANCE_MEDIAN_IN_BAND           the median return on the stake is inside the designed band
-- @pass BALANCE_DISTANCE_PAYS            long legs out-earn short ones, pooled over every route offered
-- @pass BALANCE_QUAY_FINDS_THE_BEST      the read's shortlist matches an exhaustive scan at one port
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  -- The band. Stated here, once, in the file that enforces it.
  c_median_lo constant numeric := 4.0;    -- below this a voyage is not worth the time it takes
  c_median_hi constant numeric := 16.0;   -- above this the purse doubles before the map is learned
  c_sample    constant int := 8;

  r_port    record;
  v_uid     uuid;
  v_player  uuid;
  v_fleet   uuid;
  v_stake   numeric;
  v_routes  jsonb;
  v_best    numeric;
  v_best_nm numeric;
  v_pct     numeric;
  v_n       int := 0;
  v_dry     int := 0;
  v_far     jsonb;          -- the same ports, scanned at the read's own default reach
  v_short   numeric := 0;   -- pooled return on the stake of every offered route under 400 nm
  v_short_n int := 0;
  v_long    numeric := 0;   -- ... and over 800 nm
  v_long_n  int := 0;
  v_s_sum   numeric; v_s_n int; v_l_sum numeric; v_l_n int;
  v_returns numeric[] := '{}';
  v_median  numeric;
  -- the exhaustive control, run at the FIRST sampled port only
  v_ctrl_port  text;
  v_ctrl_read  numeric;
  v_ctrl_full  numeric;
  v_ctrl_good  text;
  v_ctrl_dest  text;
  v_ctrl_pairs int;
begin
  for r_port in
    select id, code, name, culture from public.ports order by size_tier desc, code limit c_sample
  loop
    -- A house at THIS port, watered and fully crewed, exactly as a player would set out.
    v_uid := ('00000000-0000-4000-9500-' || lpad(md5(r_port.code), 12, '0'))::uuid;
    v_player := public.new_house(v_uid, 'Casa ' || r_port.code, 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    update public.fleets set port_id = r_port.id where id = v_fleet;
    perform cmd.assume_identity(v_uid);
    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
    perform cmd.do_hire(v_fleet, jsonb_build_object('count',
      (select c.crew_max - s.crew from public.ships s
         join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fleet)));

    select ducats into v_stake from public.players where id = v_player;

    -- THE QUAY'S OWN ANSWER, at one leg — every good it will price, not just the top row, because
    -- the read ranks by profit per sea-mile and this proof is asking a different question: what is
    -- the most a first voyage can RETURN ON THE STAKE? The rows are the read's; the metric is this
    -- file's, and it is applied to the read's own outlay and proceeds.
    -- 0039: "one leg" became a 600 nm sailed radius (measured: the closest match to the old
    -- one-leg horizon - see proof 04's note).
    v_routes := world.trade_routes(r_port.id, v_fleet, 600, null);
    select max((e->>'profit')::numeric),
           (array_agg((e->>'nm')::numeric order by (e->>'profit')::numeric desc))[1]
      into v_best, v_best_nm
      from jsonb_array_elements(v_routes->'routes') e;

    -- The read must have priced at the fleet's real capacity, or "what a first voyage pays" is
    -- being measured at some other house's quantity.
    if v_routes->'basis'->>'qty_from' <> 'fleet' then
      raise exception 'PROOF 5 FAILED: world.trade_routes priced % on the "%" basis, not the fleet''s — the balance would be measured at a quantity no player has',
        r_port.code, v_routes->'basis'->>'qty_from';
    end if;

    if r_port.code = (select code from public.ports order by size_tier desc, code limit 1) then
      v_ctrl_port := r_port.code;
      v_ctrl_read := v_best;
      -- EXHAUSTIVE: every good this port trades against EVERY destination inside the same 600 nm
      -- the shortlisted scan searched, priced through the same quotes at the same capacity.
      -- No shortlist, no cap, no ranking. (0039: "one leg" became the sailed radius.)
      select count(*), max(x.p),
             (array_agg(x.g order by x.p desc))[1], (array_agg(x.d order by x.p desc))[1]
        into v_ctrl_pairs, v_ctrl_full, v_ctrl_good, v_ctrl_dest
        from (
          select g.code as g, d.code as d, qs.total - qb.total as p
            from voyage.reach_from(r_port.id) rf
            join public.ports d on d.id = rf.port_id and d.kind = 'HARBOUR'
            join public.port_goods pg on pg.port_id = r_port.id
            join public.goods g on g.id = pg.good_id
           cross join lateral (select (public.fleet_buy_capacity(v_fleet, g.id)->>'max_qty')::numeric q) c
           cross join lateral world.quote(r_port.id, g.id, c.q, 'buy', null, v_fleet) qb
           cross join lateral world.quote(d.id, g.id, qb.units, 'sell', null, v_fleet) qs
           where rf.nm <= 600
             and c.q >= 1 and qb.units > 0
             and voyage.sail_refusal(v_fleet, d.id, null, rf.nm) is null
             and not (d.culture = any(g.culture_mask))
             and not (r_port.culture = any(g.culture_mask))
        ) x;
    end if;

    v_n := v_n + 1;
    if v_best is null or v_best <= 0 then
      v_dry := v_dry + 1;
    else
      v_pct := v_best / v_stake * 100;
      v_returns := v_returns || v_pct;
    end if;

    -- AND THE DISTANCE QUESTION, over every route the quay will offer at its own default reach.
    -- One trade per port is too few rows to say anything: it made the old form's answer depend on
    -- which single port happened to have a long winner.
    v_far := world.trade_routes(r_port.id, v_fleet, null, null);
    select coalesce(sum((e->>'profit')::numeric / v_stake * 100)
                      filter (where (e->>'nm')::numeric < 400), 0),
           count(*) filter (where (e->>'nm')::numeric < 400),
           coalesce(sum((e->>'profit')::numeric / v_stake * 100)
                      filter (where (e->>'nm')::numeric > 800), 0),
           count(*) filter (where (e->>'nm')::numeric > 800)
      into v_s_sum, v_s_n, v_l_sum, v_l_n
      from jsonb_array_elements(v_far->'routes') e;
    v_short := v_short + v_s_sum; v_short_n := v_short_n + v_s_n;
    v_long  := v_long  + v_l_sum; v_long_n  := v_long_n  + v_l_n;
  end loop;

  if v_dry <> 0 then
    raise exception 'PROOF 5 FAILED: % of % sampled ports offer no profitable first voyage at all',
      v_dry, v_n;
  end if;
  raise notice 'PASS: BALANCE_EVERY_PORT_HAS_A_TRADE — all % sampled ports offer a first voyage that pays, and the quay names it', v_n;

  select percentile_cont(0.5) within group (order by x)
    into v_median from unnest(v_returns) as t(x);
  if v_median < c_median_lo or v_median > c_median_hi then
    raise exception 'PROOF 5 FAILED: the median first voyage returns %%% of the stake, outside the designed band %%%-%%%. Run scripts/db/tune-balance.mjs and read the sweep.',
      round(v_median, 1), c_median_lo, c_median_hi;
  end if;
  raise notice 'PASS: BALANCE_MEDIAN_IN_BAND — the median first voyage returns % per cent of the stake (band %-%), worst %, best % — measured through world.trade_routes, which is what the player is shown',
    round(v_median, 1), c_median_lo, c_median_hi,
    (select round(min(x), 1) from unnest(v_returns) as t(x)),
    (select round(max(x), 1) from unnest(v_returns) as t(x));

  -- DISTANCE PAYS. Not a nicety: it is the reason the world is 214 ports wide rather than twelve.
  -- No skip branch. An empty bucket is a world in which the question cannot be asked, and a marker
  -- that reports PASS for that is reporting a safety it never examined.
  if v_short_n = 0 or v_long_n = 0 then
    raise exception 'PROOF 5 FAILED: the quay offered % route(s) under 400 nm and % over 800 nm across % ports, so "the long legs out-earn the short ones" was never actually compared',
      v_short_n, v_long_n, v_n;
  end if;
  if (v_long / v_long_n) <= (v_short / v_short_n) then
    raise exception 'PROOF 5 FAILED: long legs pay %%% and short legs pay %%% — there is no reason to sail far',
      round(v_long / v_long_n, 2), round(v_short / v_short_n, 2);
  end if;
  raise notice 'PASS: BALANCE_DISTANCE_PAYS — pooled over % offered route(s) over 800 nm they return % per cent of the stake against % per cent for the % under 400 nm',
    v_long_n, round(v_long / v_long_n, 2), round(v_short / v_short_n, 2), v_short_n;

  -- THE SHORTLIST IS NOT COSTING ANYTHING. The exhaustive scan must have found something (a zero
  -- pair count would agree with the read vacuously), and the read must match its best.
  if v_ctrl_pairs is null or v_ctrl_pairs = 0 then
    raise exception 'PROOF 5 FAILED: the exhaustive control at % priced 0 (good, destination) pairs, so it agrees with the read about nothing',
      v_ctrl_port;
  end if;
  if v_ctrl_read is null or v_ctrl_read < v_ctrl_full then
    raise exception 'PROOF 5 FAILED: at % the exhaustive scan found % d. (% to %) and world.trade_routes offered only % — the affinity shortlist is dropping the best trade',
      v_ctrl_port, v_ctrl_full, v_ctrl_good, v_ctrl_dest, v_ctrl_read;
  end if;
  raise notice 'PASS: BALANCE_QUAY_FINDS_THE_BEST — at % an exhaustive scan of % (good, destination) pairs found % d. at best (% to %), and world.trade_routes'' shortlist found % d. — the cheap stage costs the player nothing',
    v_ctrl_port, v_ctrl_pairs, v_ctrl_full, v_ctrl_good, v_ctrl_dest, v_ctrl_read;
end $$;
