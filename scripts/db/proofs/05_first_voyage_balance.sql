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
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 2026-08-25 — THE LOTTERY, AND WHAT THE LOTTERY WAS HIDING
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- THIS FILE WAS A GATE THAT CRIED WOLF. On an UNCHANGED chain, `BALANCE_MEDIAN_IN_BAND` measured
-- 15.1 / 9.0 / 12.4 / 14.4 / 12.4 / 12.1 and once 16.2 (docs/RESUME.md), and on 2026-08-25 the same
-- bytes gave 18.3 and then 14.1 against a 4-16 band. A red that means "bad roll" as often as it
-- means "bad balance" is scrolled past, and then it gates nothing at all. That was the defect —
-- more than the number.
--
-- WHERE THE VARIANCE CAME FROM, MEASURED. `public.tick_market_drift` (0010:107) moves every price
-- by `random()` deliberately, and the chain's own self-asserts call it while applying, so EVERY
-- `db:apply` deals a different market. The median first voyage is a MAX over ~243 goods x the ports
-- in range of drift-noised price gaps, and a max over thousands of draws is dominated by the noise
-- amplitude — not by any affinity knob, which is why migration 0041 flattening the gradient by 30
-- per cent barely moved this number.
--
-- SO THE MARKET IS PINNED, AND THE PINNING IS NOT WRITTEN HERE: `proof.pin_market`
-- (scripts/db/market-fixture.mjs) is the one authority for it, shared with proof 04 and with
-- tests/rpc.firstSession.spec.ts. Every row is REDRAWN from the distribution the real process
-- settles into — the OU stationary law, clamped as 0010 clamps it — keyed on the AUTHORED port and
-- good codes, so the market is the same on every run and on every machine. The drift is replaced,
-- never removed: proof 04 records that a FLAT market is not "the economy without noise", it is an
-- economy with less trade in it than the game ever has (36 routes out of Lisboa drifted, 20 flat).
--
-- AND PINNING IT EXPOSED WHAT THE LOTTERY WAS HIDING. Driving the chain's OWN tick forward one
-- slot at a time from a freshly applied world (2026-08-25, PGlite 0.5.5 / PostgreSQL 18.3):
--
--     ticks (10 min each)     0       1       2       4       8      16      32
--     sd(drift)           0.0210  0.0442  0.0566  0.0706  0.0827  0.0890  0.0905
--     median voyage        13.2%   20.2%   21.1%   28.8%   32.5%   34.1%   35.2%
--
-- A FRESHLY APPLIED CHAIN IS NOT A LIVE WORLD. It has taken about one drift step on the 14,980
-- market rows migration 0003 seeded and NONE on the 39,468 that 0041 added, so 72 per cent of its
-- prices sit at exactly drift 0. The 12-18 per cent this proof used to report was therefore a
-- measurement of HOW MANY TICKS THE HARNESS HAPPENED TO RUN. A world whose clock has been running
-- for two hours — which is every deployed world, since `world.market()` itself winds the tick
-- (0029) — sits at sigma / sqrt(1 - theta^2) = 0.04 / sqrt(1 - 0.81) = 0.0918, and pays about 37.
--
-- THAT IS A REAL BALANCE DEFECT AND IT IS STATED, NOT ABSORBED.
--
-- AND IT SHOWED UP TWICE, WHICH IS WHAT DECIDED IT. BALANCE_DISTANCE_PAYS used to read 10.80 per
-- cent for the long legs against 3.26 for the short ones — geography worth three and a third times
-- as much as staying home. On the settled market the same pooled comparison read 18.87 against
-- 16.19: still the right way round, and worth 17 per cent. This is a game about carrying goods from
-- where they are made to where they are not, and the noise had all but erased the reason to leave
-- home waters. A knob that drowns the premise is not a balance preference.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 2026-08-25, THE SAME DAY — THE KNOB WAS PULLED: `drift_sigma` 0.04 -> 0.02 (MIGRATION 0056)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- Everything above is why. Migration 0056 carries the change, the alternatives it rejected and its
-- own self-assert; this file carries the band that judges it, and the two landed in ONE commit so
-- that the knob and its judge are never in two states at once.
--
-- MEASURED THROUGH THIS VERY FILE, on the chain as it stands at 0053 (2026-08-25, PGlite 0.5.5 /
-- PostgreSQL 18.3), with the band widened in memory so every marker still emitted:
--
--     drift_sigma            0.040    0.030    0.025   >0.020<   0.015
--     pooled median          37.4%    26.7%    21.5%    15.7%    12.5%
--     flat-market gradient    7.0%     7.0%     7.0%     7.0%     7.0%
--     long legs (>800 nm)    18.87%   14.21%   11.78%    9.66%    7.68%
--     short legs (<400 nm)   16.19%   11.10%    8.64%    5.88%    3.92%
--     long / short            1.17x    1.28x    1.36x    1.64x    1.96x
--     routes offered long/short 360/85  371/77   391/64   405/55   417/39
--
-- THREE THINGS THAT TABLE SETTLES, none of them assumed:
--   1. GEOGRAPHY MEASURABLY RECOVERS. The long-leg premium goes 1.17x -> 1.64x, a 40 per cent
--      relative gain, and the shape of what the quay offers moves with it: 85 near routes fall to
--      55 while 360 far ones rise to 405. Less noise does not merely pay less — it pays less for
--      staying home, which is the whole point.
--   2. THE AUTHORED GRADIENT IS UNTOUCHED. 7.0 per cent at every setting, to the digit, because
--      BALANCE_GRADIENT_IN_BAND measures the FLAT market — amplitude 0 — which no sigma can scale.
--      Confirmed by measurement rather than assumed.
--   3. THE 0051 / 0052 / 0053 MERGES MOVED NOTHING. At 0.040 this chain reports 37.4 / 7.0 /
--      18.87 / 16.19 — identical in every digit to the 45-migration chain the previous slice
--      measured. The band below is pinned to the chain it will be judged on.
--
-- WHAT WAS NOT DONE, AND THE NUMBERS THAT ARGUE FOR IT: 0.015 pays 12.5 (mid-band rather than at
-- its ceiling), recovers geography further to 1.96x, and keeps a fully bargained trader inside
-- 4-16 where 0.020 does not (15.7 + proof 06's 2.7 = 18.4). Against it: it thins the near market
-- hard, 39 short routes against 85 at the old setting. 0.020 was the authorised step and 0.020 is
-- what shipped; the rest is recorded so a second step needs no new measurement.
--
-- ── WHAT THIS ASSERTS, AND WHY EACH ONE ────────────────────────────────────────────────────────
--   * THE OPENING VOYAGE PAYS, EVERYWHERE. From a sample of starting ports, on every drawn market,
--     the best one-leg round trip the quay offers returns something. A world where the best
--     available trade loses money has no game in it.
--   * IT PAYS WHAT IT WAS MEASURED TO PAY. The pooled median sits inside a band. See the band's own
--     note below for what each bound means: it is a REGRESSION TRIPWIRE around a measured reality,
--     and it is deliberately not the same statement as the design's intent.
--   * THE AUTHORED GRADIENT IS STILL INSIDE THE DESIGNED BAND. The same measurement on a FLAT
--     market — the economy the affinity knobs author, with the clock's noise taken out — must sit
--     in 4-16 per cent, which is the band this file has always carried and the one
--     scripts/db/tune-balance.mjs sweeps against. This is where the design's intent still bites.
--   * DISTANCE IS WHAT PAYS. The long legs must out-earn the short ones — otherwise there is no
--     reason to ever leave home waters, and the 214-port world collapses to whatever is nearest.
--     POOLED OVER EVERY ROUTE THE QUAY OFFERS at its own default reach. Both buckets must be
--     non-empty: a marker that passes by skipping is exactly the vacuous pass scripts/db/proof.mjs
--     exists to refuse.
--   * AND THE SHORTLIST IS NOT COSTING THE PLAYER ANYTHING. `world.trade_routes` shortlists
--     candidates by authored affinity before it prices anything (0019's stage 1), which is a
--     heuristic. So one sampled port is ALSO scanned EXHAUSTIVELY — every good against every
--     one-leg destination, priced through the same quotes — and the read must find a trade at
--     least as good. Without this the cheap stage could quietly degrade and nothing would notice.
--
-- ── AND WHAT IT DELIBERATELY DOES NOT MEASURE: THE BARGAIN ─────────────────────────────────────
-- Every figure here is UNHAGGLED. A bargain struck at the cap is worth a further 2.7 per cent of
-- the stake over a round trip — measured across all 238 ports by proof 06's
-- HAGGLE_IS_WORTH_DOING, which is the one authority for that number and is not re-derived here.
-- The band's ceiling is set wide enough that a fully bargained trader is still inside it (15.7 +
-- 2.7 = 18.4, against a ceiling of 20.0); a second implementation of "what is a bargain worth"
-- would be the duplication §1 forbids. Note that the bargained trader is inside THIS band and just
-- outside the DESIGNED 4-16 — stated, not absorbed, exactly as docs/DEV_LOG.md:619 first stated it.
--
-- The knobs behind the gradient live in world_config (`affinity_*`, migration 0005) and are swept
-- by scripts/db/tune-balance.mjs. If BALANCE_GRADIENT_IN_BAND goes red, run that sweep and read the
-- table it prints rather than nudging a constant until the red goes away. If BALANCE_MEDIAN_IN_BAND
-- goes red ALONE, the gradient is fine and the drift amplitude has moved — look at 0001's knobs.
--
-- ── THE ONE KNOB, STILL SWEPT, FOR WHOEVER RETUNES NEXT ────────────────────────────────────────
-- `node scripts/db/breaktest-balance.mjs` ends by sweeping `drift_sigma` through this very file, so
-- the table above can be reproduced — and extended — without writing a line of new measurement.
--
-- BREAK-TESTED, because a gate nobody has watched fail is a gate nobody has tested: the same script
-- moves the economy on purpose and prints which marker each break reddens, and it proves the clean
-- run is IDENTICAL twice over. Run it and read what it prints; it commits nothing.
--
-- @pass BALANCE_EVERY_PORT_HAS_A_TRADE   every sampled starting port offers a profitable first voyage
-- @pass BALANCE_MEDIAN_IN_BAND           the pooled median return on the stake is inside the band
-- @pass BALANCE_GRADIENT_IN_BAND         the authored gradient, with the clock's noise out, is in 4-16
-- @pass BALANCE_DISTANCE_PAYS            long legs out-earn short ones, pooled over every route offered
-- @pass BALANCE_QUAY_FINDS_THE_BEST      the read's shortlist matches an exhaustive scan at one port
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  -- ── THE BAND, stated here, once, in the file that enforces it ────────────────────────────────
  --
  -- WHAT A BOUND MEANS. These two numbers do not say "what a first voyage ought to pay" — that
  -- claim belongs to c_grad_lo/c_grad_hi below, which is the band this file has always carried and
  -- which is asserted on the FLAT market, the only state the affinity knobs actually govern. What
  -- these two say is: THE SETTLED ECONOMY IS WHERE MIGRATION 0056 PUT IT. At drift_sigma = 0.02 the
  -- pooled median of 8 ports x 3 drawn markets reads 15.7 per cent (per-market medians 17.4 / 15.7 /
  -- 17.3, so a single drawn market is worth about +/- 1.5 on its own).
  --
  -- THE WIDTH IS CHOSEN FROM THE SWEEP IN THE HEADER, not from taste. The neighbouring settings
  -- this file measured pay 12.5 (sigma 0.015) and 21.5 (sigma 0.025), so a band of 13.0-20.0 is the
  -- widest one that still REFUSES a quarter-sized error in the knob in either direction, while
  -- leaving room for a drawn market's luck and for a fully bargained trader at 18.4.
  --
  --   * BELOW c_median_lo: the economy got poorer than 0056 set it. Either a price authority, the
  --     capacity fold or the trade scan has regressed, or the drift amplitude was cut again and
  --     this file was not re-measured with it.
  --   * ABOVE c_median_hi: the economy got richer than 0056 set it — the drift is climbing back
  --     toward the 37.4 per cent that made this a money printer, and geography is being drowned
  --     again. Read BALANCE_DISTANCE_PAYS in the same run: that is where it shows first.
  --
  -- A VALUE OUTSIDE THIS BAND IS A REAL DEFECT AND NEVER A BAD ROLL: the market is pinned by
  -- `proof.pin_market` and every input to the number below is a pure function of the chain. The
  -- same bytes give the same figure to the digit, on any machine, at any hour. If this reddens,
  -- something in the chain changed.
  c_median_lo constant numeric := 13.0;
  c_median_hi constant numeric := 20.0;

  -- ── AND THE DESIGNED BAND, on the state the design actually governs ──────────────────────────
  -- 4-16 per cent, unchanged since this file was written: below it a voyage is not worth the
  -- twenty-five minutes it takes, above it the purse doubles before the map is learned. Asserted
  -- on the flat market, where the number is the authored gradient and nothing else. Measured
  -- 2026-08-25: 7.0 per cent — against the 7.5 migration 0005:125 tuned the affinity knobs to, so
  -- THE AUTHORED ECONOMY IS DOING WHAT IT WAS DESIGNED TO DO. It read 7.0 at every drift_sigma in
  -- the header's sweep, to the digit, which is what makes it the right band for the design's claim:
  -- 0056 moved the settled market and could not move this one.
  --
  -- ONE CAVEAT, STATED. On a flat market `world.trade_routes`' shortlist (route_scan_keep = 3) is
  -- known to drop the best trade sometimes, so this figure is a LOWER BOUND on the gradient. It
  -- cannot therefore produce a false red on the ceiling; it could on the floor, which today stands
  -- at 1.75x below the measured figure.
  c_grad_lo   constant numeric := 4.0;
  c_grad_hi   constant numeric := 16.0;

  c_sample    constant int := 8;
  c_draws     constant int := 3;
  -- The fixture's own key and secret. `voyage.rng_raw` takes the secret as an ARGUMENT (0006:113),
  -- so nothing about the world's own secret is involved here or disclosed by this.
  c_key       constant uuid := '00000000-0f05-4000-8000-0000000000dd';
  c_secret    constant text := 'proof-5-fixture';

  d         int;
  r_port    record;
  v_fx      jsonb;
  v_uid     uuid;
  v_player  uuid;
  v_fleet   uuid;
  v_stake   numeric;
  v_routes  jsonb;
  v_best    numeric;
  v_pct     numeric;
  v_n       int := 0;
  v_dry     int := 0;
  v_far     jsonb;          -- the same ports, scanned at the read's own default reach
  v_short   numeric := 0;   -- pooled return on the stake of every offered route under 400 nm
  v_short_n int := 0;
  v_long    numeric := 0;   -- ... and over 800 nm
  v_long_n  int := 0;
  v_s_sum   numeric; v_s_n int; v_l_sum numeric; v_l_n int;
  v_returns numeric[] := '{}';   -- every sampled port on every drawn market, pooled
  v_draw    numeric[] := '{}';   -- ... and this draw's alone
  v_medians numeric[] := '{}';   -- one median per drawn market, for the notice
  v_median  numeric;
  v_flat    numeric[] := '{}';
  v_flat_md numeric;
  -- the exhaustive control, run at the FIRST sampled port of the FIRST drawn market only
  v_ctrl_port  text;
  v_ctrl_read  numeric;
  v_ctrl_full  numeric;
  v_ctrl_good  text;
  v_ctrl_dest  text;
  v_ctrl_pairs int;
begin
  -- ── THE PRECONDITION THIS PROOF OWNS ─────────────────────────────────────────────────────────
  -- Four markets are measured: three drawn from the settled law, and one flat. Each is pinned by
  -- the one authority, each with its own stream prefixes, and each raises on its own vacuity —
  -- so a fixture that silently stopped applying reddens here rather than quietly turning this
  -- file back into the lottery the header describes.
  for d in 1..(c_draws + 1) loop
    if d <= c_draws then
      v_fx := proof.pin_market(c_key, c_secret, 'p5v' || d || 'a:', 'p5v' || d || 'b:');
    else
      -- THE FLAT CONTROL — the same fixture at amplitude 0. Same stock, same slot, no noise.
      v_fx := proof.pin_market(c_key, c_secret, 'p5flat:', 'p5flat:', interval '1 day', 0);
    end if;
    if (v_fx->>'rows')::int < 14000 then
      raise exception 'PROOF 5 FAILED: the market fixture touched only % row(s) on draw %', v_fx->>'rows', d;
    end if;
    v_draw := '{}';

    for r_port in
      select id, code, name, culture from public.ports order by size_tier desc, code limit c_sample
    loop
      -- A house at THIS port, watered and fully crewed, exactly as a player would set out. The uid
      -- carries the draw index: the same port is founded once per market and `new_house` would
      -- refuse a second house on one auth uid.
      v_uid := ('00000000-0000-4000-950' || d || '-' || lpad(md5(r_port.code), 12, '0'))::uuid;
      v_player := public.new_house(v_uid, 'Casa ' || r_port.code || ' ' || d, 'PRT');
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
      select max((e->>'profit')::numeric)
        into v_best
        from jsonb_array_elements(v_routes->'routes') e;

      -- The read must have priced at the fleet's real capacity, or "what a first voyage pays" is
      -- being measured at some other house's quantity.
      if v_routes->'basis'->>'qty_from' <> 'fleet' then
        raise exception 'PROOF 5 FAILED: world.trade_routes priced % on the "%" basis, not the fleet''s — the balance would be measured at a quantity no player has',
          r_port.code, v_routes->'basis'->>'qty_from';
      end if;

      if d = 1 and r_port.code = (select code from public.ports order by size_tier desc, code limit 1) then
        v_ctrl_port := r_port.code;
        v_ctrl_read := v_best;
        -- EXHAUSTIVE: every good this port trades against EVERY destination inside the same 600 nm
        -- the shortlisted scan searched, priced through the same quotes at the same capacity.
        -- No shortlist, no cap, no ranking. (0039: "one leg" became the sailed radius.)
        --
        -- "every good this port TRADES" is now literal — moved deliberately 2026-08-26 with
        -- migration 0061, which made a city sell only the goods its roster names. Before it, every
        -- harbour carried a market row for all 243 goods and this control scanned all of them; it
        -- then found trades a player CANNOT MAKE (measured on the failing run: 1,070 d. on cloves
        -- at Alexandria, a good Alexandria does not trade and cmd.do_buy refuses) and reddened
        -- because world.trade_routes correctly refused to name them. The control is asked about the
        -- same universe the shortlist is: what she could actually load. The DESTINATION is still
        -- unfiltered, because selling is not gated by the roster.
        select count(*), max(x.p),
               (array_agg(x.g order by x.p desc))[1], (array_agg(x.d order by x.p desc))[1]
          into v_ctrl_pairs, v_ctrl_full, v_ctrl_good, v_ctrl_dest
          from (
            select g.code as g, d2.code as d, qs.total - qb.total as p
              from voyage.reach_from(r_port.id) rf
              join public.ports d2 on d2.id = rf.port_id and d2.kind = 'HARBOUR'
              join public.port_goods pg on pg.port_id = r_port.id
              join public.goods g on g.id = pg.good_id
             cross join lateral (select (public.fleet_buy_capacity(v_fleet, g.id)->>'max_qty')::numeric q) c
             cross join lateral world.quote(r_port.id, g.id, c.q, 'buy', null, v_fleet) qb
             cross join lateral world.quote(d2.id, g.id, qb.units, 'sell', null, v_fleet) qs
             where rf.nm <= 600
               and public.port_offers(r_port.id, pg.good_id)
               and c.q >= 1 and qb.units > 0
               and voyage.sail_refusal(v_fleet, d2.id, null, rf.nm) is null
               and not (d2.culture = any(g.culture_mask))
               and not (r_port.culture = any(g.culture_mask))
          ) x;
      end if;

      v_n := v_n + 1;
      if v_best is null or v_best <= 0 then
        v_dry := v_dry + 1;
      else
        v_pct := v_best / v_stake * 100;
        v_draw := v_draw || v_pct;
      end if;

      -- AND THE DISTANCE QUESTION, over every route the quay will offer at its own default reach.
      -- One trade per port is too few rows to say anything: it made the old form's answer depend on
      -- which single port happened to have a long winner. Asked on the first drawn market only —
      -- it is the expensive read in this file, and the claim is about geography, not about luck.
      if d = 1 then
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
      end if;
    end loop;

    if d <= c_draws then
      v_returns := v_returns || v_draw;
      v_medians := v_medians
        || (select percentile_cont(0.5) within group (order by x) from unnest(v_draw) as t(x));
    else
      v_flat := v_draw;
    end if;
  end loop;

  if v_dry <> 0 then
    raise exception 'PROOF 5 FAILED: % of % (port, market) pairs offer no profitable first voyage at all',
      v_dry, v_n;
  end if;
  raise notice 'PASS: BALANCE_EVERY_PORT_HAS_A_TRADE — all % (port, market) pair(s) — % sampled port(s) on % drawn market(s) plus the flat control — offer a first voyage that pays, and the quay names it',
    v_n, c_sample, c_draws;

  -- ── THE BAND, on the market a live world sits in ─────────────────────────────────────────────
  -- The statistic is the median of every sampled port on every drawn market, not the median of one
  -- market: a single drawn market's own median moved 34.5 -> 41.2 across three draws, so pooling
  -- is what makes the number a property of the economy rather than of one lucky draw.
  select percentile_cont(0.5) within group (order by x)
    into v_median from unnest(v_returns) as t(x);
  if v_median < c_median_lo or v_median > c_median_hi then
    raise exception 'PROOF 5 FAILED: the pooled median first voyage returns % per cent of the stake, outside the measured band %-%. The market is PINNED, so this is not a bad roll — something in the chain moved. Per-market medians: %. Run scripts/db/tune-balance.mjs and read the sweep.',
      round(v_median, 1), c_median_lo, c_median_hi,
      (select array_agg(round(x, 1)) from unnest(v_medians) as t(x));
  end if;
  raise notice 'PASS: BALANCE_MEDIAN_IN_BAND — the median first voyage returns % per cent of the stake (band %-%), worst %, best %, over % observation(s): % sampled port(s) on % market(s) drawn from the settled drift law, with per-market medians %. Measured through world.trade_routes, which is what the player is shown, and UNHAGGLED — a bargain at the cap adds a further 2.7 (proof 06)',
    round(v_median, 1), c_median_lo, c_median_hi,
    (select round(min(x), 1) from unnest(v_returns) as t(x)),
    (select round(max(x), 1) from unnest(v_returns) as t(x)),
    array_length(v_returns, 1), c_sample, c_draws,
    (select array_agg(round(x, 1)) from unnest(v_medians) as t(x));

  -- ── AND THE AUTHORED GRADIENT, with the clock's noise taken out ──────────────────────────────
  -- This is where the DESIGNED band still bites, and it is the number the affinity knobs move.
  -- It must also be strictly smaller than the drifted one: if it is not, the drift has stopped
  -- being where the arbitrage lives and every figure above means something else.
  select percentile_cont(0.5) within group (order by x)
    into v_flat_md from unnest(v_flat) as t(x);
  if v_flat_md is null or v_flat_md < c_grad_lo or v_flat_md > c_grad_hi then
    raise exception 'PROOF 5 FAILED: on a flat market the median first voyage returns % per cent of the stake, outside the DESIGNED band %-% — the authored gradient itself has moved, which is what scripts/db/tune-balance.mjs sweeps',
      round(v_flat_md, 1), c_grad_lo, c_grad_hi;
  end if;
  if v_flat_md >= v_median then
    raise exception 'PROOF 5 FAILED: the flat market pays % per cent and the drifted one % per cent — the clock''s noise is no longer where the arbitrage lives, so the band above is measuring something other than what it says',
      round(v_flat_md, 1), round(v_median, 1);
  end if;
  raise notice 'PASS: BALANCE_GRADIENT_IN_BAND — with the clock''s noise taken out the median first voyage returns % per cent of the stake, inside the designed band %-%; the settled drift the game runs on takes the same measurement to % per cent, a multiple of %. The noise is most of the number, and no affinity knob touches it — the lever is drift_sigma/drift_theta (0001)',
    round(v_flat_md, 1), c_grad_lo, c_grad_hi, round(v_median, 1),
    round(v_median / greatest(v_flat_md, 0.01), 2);

  -- DISTANCE PAYS. Not a nicety: it is the reason the world is 214 ports wide rather than twelve.
  -- No skip branch. An empty bucket is a world in which the question cannot be asked, and a marker
  -- that reports PASS for that is reporting a safety it never examined.
  if v_short_n = 0 or v_long_n = 0 then
    raise exception 'PROOF 5 FAILED: the quay offered % route(s) under 400 nm and % over 800 nm across % ports, so "the long legs out-earn the short ones" was never actually compared',
      v_short_n, v_long_n, c_sample;
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
