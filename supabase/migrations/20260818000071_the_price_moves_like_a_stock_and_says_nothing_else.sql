-- ===============================================================================================
-- 0071 - THE PRICE MOVES LIKE A STOCK, AND THE SCREEN SAYS NOTHING ELSE
-- ===============================================================================================
--
-- The owner, 2026-09-01:
--
--     "market - have only necessary info - buying price, selling price, price range when pressed
--      for more info, no nearby price info needed, the trading goods. The game will refresh every
--      15 minutes... The change prices will be like stock... For now -20% to +20%."
--
-- and, earlier and more than once:
--
--     "there is no need info - cheapest here, the game is to challenge players for finding the
--      best prices by themselves"
--
-- -- WHAT GOES, AND WHY IT IS ONE THING AND NOT THREE --------------------------------------------
-- `pct_nbr` is this quay's mid as a percentage of the ports within 600 nm. `advice` is that same
-- number cut into buy / hold / sell. They are ONE comparison wearing two hats, and it is the answer
-- the game exists to make the player find. Removing the number and keeping the badge would have
-- kept the answer and only hidden the arithmetic.
--
-- So both leave the payload, `world.pct_of_neighbours_at` is dropped, and the two knobs that cut
-- the band - advice_buy_below and advice_sell_above - are deleted rather than left behind to be
-- rediscovered by someone as "config nobody reads".
--
-- -- WHAT ARRIVES: THE RANGE, WHICH IS A FACT AND NOT AN ANSWER ---------------------------------
-- "price range when pressed for more info". A range says how far this price can travel; it does
-- NOT say where else to sell. It is computed through world.mid_from_terms - the ONE price
-- expression - with the drift term held at each end of its own band and every other term of this
-- row left exactly as it is. So the range is this good, at this quay, today: not a second price
-- model, and not a number this file invents.
--
-- -- WHAT THIS SUPERSEDES ------------------------------------------------------------------------
-- world.market, created at 0005 and re-cut since. This file replaces the body: it drops two fields
-- and the two CTEs that fed them, and adds two. Same name, same argument, same callers - the
-- MARKET face, the PORT face and the trade fold all read it and none of them gains a second read.
-- The change is NOT a no-op: a screen that sorted by `advice` has nothing to sort by afterwards,
-- which is the point, and the client half lands in the same commit.
--
-- -- FIFTEEN MINUTES, AND THE BAND ---------------------------------------------------------------
-- The chain ALREADY has a bounded random walk: port_goods.drift, an Ornstein-Uhlenbeck step pinned
-- on one authority by 0054 and tuned by 0056. The owner's "-20% to +20%" is that walk's BAND, so
-- it moves drift_clamp from 0.25 to 0.20. It must not become a second mover, and it does not: no
-- new column, no new function, no second walk. The cadence knob moves 600 -> 900 seconds and the
-- clock that 0029 already serves (`next_change_at`, "prices move in m:ss") keeps telling the truth
-- because it reads the knob rather than a constant.
--
-- Sigma is NOT touched, deliberately. 0056 measured that at sigma 0.04 the noise drowned the
-- geography and cut it to 0.02; raising it now to make the walk fill the wider band would undo a
-- ruling that was measured, in order to satisfy a sentence that was about the LIMIT. The band is
-- the rail, not the target.
-- ===============================================================================================

create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $fn$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0071 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

create temporary table defs_before_0071 as
  select 'world.market'::text as fn, pg_get_functiondef('world.market(uuid)'::regprocedure) as def;

-- -- 1. THE TWO KNOBS THE OWNER NAMED --------------------------------------------------------------
update public.world_config
   set value = to_jsonb(900::numeric),
       description = 'DESIGN D.2: tick_market_drift runs every FIFTEEN minutes (the owner, 2026-09-01: '
                     '"The game will refresh every 15 minutes"). The slot index floor(epoch/900) is what '
                     'makes the walk a pure function of the clock, so an offline world settles to the same '
                     'prices an online one does. 0029''s next_change_at reads this knob, so the countdown '
                     'the screen prints moved with it and no clock was touched.'
 where key = 'drift_slot_seconds';

update public.world_config
   set value = to_jsonb(0.20::numeric),
       description = 'The band the price walks in: -20% to +20% of the geography''s own mid (the owner, '
                     '2026-09-01). This is the RAIL, not the target - drift_sigma stays where 0056 '
                     'measured it, because raising the noise to fill a wider band would undo a ruling '
                     'that was measured in order to satisfy a sentence that was about the limit.'
 where key = 'drift_clamp';

-- ANY DRIFT ALREADY OUTSIDE THE NEW BAND IS BROUGHT INSIDE IT. Without this a live world would
-- carry rows above the rail until each happened to step again - a band that is not yet a band.
update public.port_goods
   set drift = greatest(-0.20, least(0.20, drift))
 where abs(drift) > 0.20;

-- The two knobs that cut the neighbour comparison into a recommendation. Deleted rather than left
-- to be rediscovered as "config nobody reads".
delete from public.world_config where key in ('advice_buy_below', 'advice_sell_above');

-- -- 2. THE QUAY STOPS ANSWERING THE QUESTION -------------------------------------------------------
select pg_temp.recut('world.market(uuid)'::regprocedure, false,
  $n0$  -- MATERIALIZED, and that word is still load-bearing: without the fence the planner
  -- substitutes the expression at every reference and "once" stops meaning once (0019). What
  -- changed in 0053 is WHAT is fenced. The scalar world.pct_of_neighbours walked the
  -- neighbourhood and priced it per GOOD — 243 walks and 9,720 world.mid_price calls to draw one
  -- screen, measured at 1,026 ms of a 1,185 ms body at Bordeaux. world.pct_of_neighbours_at is
  -- the same §E.4 rule asked ONCE for the whole quay: 57 ms, same numbers to the digit.
  with nbr as materialized (
    select a.good_id, a.pct from world.pct_of_neighbours_at(p_port) a
  ),
  band as materialized (
    select public.wc_num('advice_buy_below') as lo, public.wc_num('advice_sell_above') as hi
  )
$n0$,
  $n1$  -- MATERIALIZED, and that word is still load-bearing: without the fence the planner
  -- substitutes the expression at every reference and "once" stops meaning once (0019).
  --
  -- 0071: the neighbour walk and the advice band are GONE. What they answered - "is this dear
  -- or cheap compared with everywhere else" - is the question the game exists to make the player
  -- answer for themselves. `knobs` replaces them, and it is read once for the whole quay for the
  -- same reason 0053 made the neighbour walk a single call: a per-row wc_num is 523 reads.
  with knobs as materialized (
    select public.wc_num('price_elasticity') as e, public.wc_num('mid_dev_discount') as dd,
           public.wc_num('price_band_lo')    as blo, public.wc_num('price_band_hi')  as bhi,
           public.wc_num('drift_clamp')      as clamp
  )
$n1$,
  $p0$        'pct_nbr', n.pct,
$p0$,
  $p1$        -- 0071 RANGE: how far this price can travel, priced through the ONE expression with
        -- the drift term held at each end of its own band and every other term of this row left
        -- exactly as it is. A fact about this good at this quay - never a hint about another one.
        'range_lo', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.stock_target,
                      pg.stock, -k.clamp, pg.season_mod, pr.dev_commerce, k.e, k.dd, k.blo, k.bhi),
        'range_hi', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.stock_target,
                      pg.stock,  k.clamp, pg.season_mod, pr.dev_commerce, k.e, k.dd, k.blo, k.bhi),
$p1$,
  $a0$,
        -- The BAND of the price index, not a recommendation to trade.
        'advice', case when n.pct is null then 'hold'
                       when n.pct < b.lo then 'buy'
                       when n.pct > b.hi then 'sell'
                       else 'hold' end)$a0$,
  $a1$)$a1$,
  $j0$      join nbr n on n.good_id = pg.good_id
     cross join band b$j0$,
  $j1$     cross join knobs k$j1$);

-- AND THE SNAPSHOT STOPS ADVERTISING THE CUT. 0019 served the two band knobs so a caption could
-- not disagree with the computation behind it; there is no computation left to agree with, and a
-- config key whose row this file just deleted would serve null to a client that types it as a
-- number. `neighbour_radius_nm` stays: it is the radius world.reach and the trade scan still use.
select pg_temp.recut('world.snapshot()'::regprocedure, false,
  $c0$        'neighbour_radius_nm', public.wc_num('neighbour_radius_nm'),
        'advice_buy_below',    public.wc_num('advice_buy_below'),
        'advice_sell_above',   public.wc_num('advice_sell_above')),$c0$,
  $c1$        'neighbour_radius_nm', public.wc_num('neighbour_radius_nm')),$c1$);

-- -- 2b. AND "WHERE TO SAIL" GOES WITH IT ----------------------------------------------------------
-- DESIGN_V1 §13, decision 3, put to the owner and answered: does NEARBY's removal take `pays at`
-- and `Where to sail`? "Yes". Both were renderings of world.trade_routes, which ranks every
-- harbour in reach by what it would pay for what is on this quay - the same comparison as the
-- neighbour index, arriving at the same answer by a longer road.
--
-- The FUNCTION stays, because scripts/db/proofs/04 uses it to find a route worth testing and runs
-- as postgres. What goes is the client's door to it: the grant is revoked, the catalogue entry is
-- removed, and no screen reads it. Leaving the grant would have left exactly what 0022 shipped
-- once and this chain has a test about - a complete server mechanic with a door nobody opens.
revoke execute on function world.trade_routes(uuid, uuid, numeric, int, uuid) from authenticated;

-- The neighbour walk itself. Nothing calls it once the quay stops; a scalar that answers a question
-- the game has decided not to answer is the kind of thing a later session wires back in "because
-- it was already there". Postgres refuses the drop if anything still depends on it, which is the
-- proof that nothing does.
drop function if exists world.pct_of_neighbours_at(uuid, uuid);
drop function if exists world.pct_of_neighbours_at(uuid);
-- AND THE SCALAR IT REPLACED. 0053 made the set-returning form the fast path and left the
-- per-good scalar standing; the only caller left was a proof, which now reads the two MIDS at the
-- two ends instead - two prices a player can see, rather than an index that pre-chewed them.
drop function if exists world.pct_of_neighbours(uuid, uuid);

-- -- SELF-ASSERT ------------------------------------------------------------------------------------
do $$
declare
  v_port    uuid;
  v_mkt     jsonb;
  v_row     jsonb;
  v_before  text;
  v_after   text;
  v_bad     int;
  v_slot    numeric;
  v_clamp   numeric;
  v_grants  int;
begin
  -- (a) THE OWNER'S TWO NUMBERS ARE THE WORLD'S TWO NUMBERS.
  select public.wc_num('drift_slot_seconds'), public.wc_num('drift_clamp') into v_slot, v_clamp;
  if v_slot <> 900 then
    raise exception '0071 self-assert FAIL: the market refreshes every % second(s), not 900', v_slot;
  end if;
  if v_clamp <> 0.20 then
    raise exception '0071 self-assert FAIL: the band is +/-%, not +/-0.20', v_clamp;
  end if;
  -- AND NO ROW IS OUTSIDE IT. A knob that names a band no row obeys is a knob, not a band.
  select count(*) into v_bad from public.port_goods where abs(drift) > 0.20 + 1e-9;
  if v_bad <> 0 then
    raise exception '0071 self-assert FAIL: % market row(s) sit outside the new band', v_bad;
  end if;
  if exists (select 1 from public.world_config where key in ('advice_buy_below', 'advice_sell_above')) then
    raise exception '0071 self-assert FAIL: the advice knobs are still in the config';
  end if;
  if world.snapshot()->'config' ? 'advice_buy_below' then
    raise exception '0071 self-assert FAIL: the snapshot still advertises a band it cannot compute';
  end if;
  if not (world.snapshot()->'config' ? 'neighbour_radius_nm') then
    raise exception '0071 self-assert FAIL: the reach radius left with the advice band - it is still used';
  end if;

  -- (b) THE COMPARISON IS GONE, ROOT AND BRANCH. Not "the field is absent from one payload": the
  --     function that computed it must not exist, or a later session finds it and wires it back.
  if has_function_privilege('authenticated', 'world.trade_routes(uuid, uuid, numeric, int, uuid)', 'execute') then
    raise exception '0071 self-assert FAIL: a client can still ask where to sail';
  end if;
  if to_regprocedure('world.pct_of_neighbours_at(uuid)') is not null
     or to_regprocedure('world.pct_of_neighbours(uuid, uuid)') is not null then
    raise exception '0071 self-assert FAIL: a neighbour comparison still exists';
  end if;

  select p.id into v_port from public.ports p
   where p.kind = 'HARBOUR' order by p.size_tier desc, p.code limit 1;
  v_mkt := world.market(v_port);
  select value into v_row from jsonb_array_elements(v_mkt->'goods') limit 1;
  if v_row is null then
    raise exception '0071 self-assert FAIL: the busiest harbour serves an empty market';
  end if;
  if v_row ? 'pct_nbr' or v_row ? 'advice' then
    raise exception '0071 self-assert FAIL: the quay still tells the player where to trade: %', v_row;
  end if;

  -- (c) WHAT STAYED, STAYED. The owner named what they wanted kept, and a slice that quietly took
  --     a price with it would be worse than one that kept the advice.
  if not (v_row ? 'buy' and v_row ? 'sell' and v_row ? 'stock' and v_row ? 'name') then
    raise exception '0071 self-assert FAIL: the market lost something the owner asked to keep: %', v_row;
  end if;

  -- (d) THE RANGE IS A RANGE, and it is this row's own. Measured on every good of a real quay
  --     rather than spot-checked: low below the mid, high above it, and the mid inside.
  select count(*) into v_bad from jsonb_array_elements(v_mkt->'goods') e
   where (e->>'range_lo')::numeric > (e->>'mid')::numeric
      or (e->>'range_hi')::numeric < (e->>'mid')::numeric;
  if v_bad <> 0 then
    raise exception '0071 self-assert FAIL: % row(s) price outside their own range', v_bad;
  end if;
  select count(*) into v_bad from jsonb_array_elements(v_mkt->'goods') e
   where (e->>'range_hi')::numeric <= (e->>'range_lo')::numeric;
  if v_bad <> 0 then
    raise exception '0071 self-assert FAIL: % range(s) are empty or inverted', v_bad;
  end if;
  -- AND IT IS THE BAND, not some other spread: at the extremes the walk can reach, the ratio of
  -- high to low is (1+clamp)/(1-clamp) = 1.5 wherever the world band is not itself binding.
  select count(*) into v_bad from jsonb_array_elements(v_mkt->'goods') e
   where abs((e->>'range_hi')::numeric / nullif((e->>'range_lo')::numeric, 0) - 1.5) > 0.01;
  if v_bad >= jsonb_array_length(v_mkt->'goods') then
    raise exception '0071 self-assert FAIL: not one range spans the drift band - the range is not the band';
  end if;

  -- (e) NOTHING ELSE MOVED, and the pre-image really did carry what was removed.
  select def into v_before from defs_before_0071 where fn = 'world.market';
  if position('pct_nbr' in v_before) = 0 then
    raise exception '0071 self-assert FAIL: the pre-image never served pct_nbr - this file removed nothing';
  end if;
  v_after := pg_get_functiondef('world.market(uuid)'::regprocedure);
  -- Precise on purpose: what must be gone is the CALL and the FIELD, not every mention of the
  -- words. A body is allowed to remember what it used to do — an earlier draft of this assert
  -- read `position('advice' in ...)` and failed on 0053's own comment about performance, which is
  -- history worth keeping rather than a comparison worth removing.
  if position('world.pct_of_neighbours_at(' in v_after) <> 0 then
    raise exception '0071 self-assert FAIL: the re-cut body still CALLS the neighbour walk';
  end if;
  if position('''advice'',' in v_after) <> 0 or position('''pct_nbr'',' in v_after) <> 0 then
    raise exception '0071 self-assert FAIL: the re-cut body still BUILDS the removed fields';
  end if;

  -- (f) POSTURE.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0071 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0071 self-assert ok: THE PRICE MOVES LIKE A STOCK AND SAYS NOTHING ELSE. The market refreshes every 900 seconds and walks in a band of +/-0.20, both the owner''s own numbers, and NO row sits outside the new band - a live world''s drifts were brought inside it rather than left to step in on their own. The neighbour comparison is gone root and branch: pct_nbr and advice have left the payload, world.pct_of_neighbours_at is DROPPED (which Postgres would have refused if anything still depended on it), and the two knobs that cut it into buy/hold/sell are deleted rather than left to be rediscovered. What the owner asked to keep is kept - the goods, the buy price, the sell price and the stock - and what arrives is a RANGE: how far this price can travel, priced through the ONE expression with the drift term held at each end of its own band, verified on every good of the busiest quay to contain its own mid and to span the band itself. Sigma was not touched: the band is the rail, not the target; 0 client write grants.';
end $$;
