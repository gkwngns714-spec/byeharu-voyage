-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0285 — THE WHOLE WORLD IS RE-BASED ×5, SO EVERY RATIO IS KEPT
--        (goods ×5 and every ABSOLUTE ducat quantity ×5; 0282 cashed the holds out first; 0208's
--         exact inverse at the whole scale; no persistent function is re-cut or created)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S INSTRUCTION ────────────────────────────────────────────────────────────────────
--   "the merchants and players holding the trade goods that are based before, convert them into
--    cash first then do the work." (2026-10-30)
--   The first half is LIVE: 0282 (20260818000282_the_old_hold_is_cashed_out_before_reprice.sql)
--   priced every held trade good at the old goods.base_value, credited each house once, and emptied
--   the holds. This file is the second half: the re-base itself — and the coordinator's correction of
--   2026-10-31 makes it WHOLE-SCALE: the owner's intent is real-world prices, not a harder game, so
--   goods ×5 alone would raise every price against an unchanged purse and break the game's own
--   balance proofs (PROOF 5's first-voyage return and PROOF 7's first-session BUY were red). Every
--   absolute ducat quantity moves ×5 with the goods, so every RATIO in the world is preserved.
--
-- ── THE MEASURED STATE (prod, read-only, 2026-10-31, head 20260818000284) ──────────────────────
--   goods: 629; base_value numeric(10,2); min 0.80, max 660.00; goods_price_level 0.2.
--   The design sheet docs/design/raw-materials-economy/GOODS_SAVED.csv carries a band per good; its
--   MIDPOINT equals the live goods.base_value × 5 for 584 of 584 sheet goods exactly (live × 5 /
--   midpoint = 1.000000 on every one). Three named goods: black-pepper 30.00 → 150 ([110,190]),
--   cinnamon 120.00 → 600 ([400,800]), saffron 390.00 → 1950 ([1300,2600]).
--   ONLY public.item_recipe_value(text) reads goods_price_level; it returns
--   Σ(qty × base_value / wc_num('goods_price_level')), so the ×5 column and the ÷5 knob cancel and
--   repair costs keep their design value. 222 item recipe products measured on prod: exact on all.
--   Money measured on prod before this file (see §PROD CHECKS for the SQL):
--     players 840 (821 merchants) — purses 1,704,092,571 d., min 0, max 56,898,626;
--     port_treasury 246 — rolled 51,625,039 d., reserve 2,779,323, invested 119,659,696;
--     treasury_flows 12,041 rows / -4,278,714 d. unrolled (live city money = 47,346,325 d.);
--     city_shares 3,630 — paid 137,085,286 d., accrued 273,323,914 d.;
--     open trade contracts 260 — premium 1,866,702 d., escrow 1,819,640 d. (7 expired rows stay);
--     fleet_wages 838 rows / 65,612.60 d.; port_fee_debts 191 rows / 159,208 d.;
--     insured_voyages 29,755 rows — value 1,427,040,231 d., price 952,436 d.;
--     hull_recipes 103 — 2,000 … 839,500 d. (barca 3,000); ship_classes 103 — 8,000 … 3,358,000 d.
--     (barca 12,000); officers 105 — wages 550 … 1,600 d.; npc_houses 821 — capital 5,000 … 729,000
--     (sum 26,061,000); route line limits 1,635; price_history 12,870 points (mid 1.0449 … 2,062.9058);
--     ships with a cargo basis 530; city treasury LIT and the economy CLOSED (economy_closed_total
--     1,986,693,521 d.); stats watch under_thin 187, under_reserve 131, broke 51.
--   The design sheet is at design ÷ 5 today; the whole world is at the same ÷ 5. ×5 on every
--   absolute ducat quantity restores it at every ratio — except the append-only flows (history,
--   below), which stay where they are.
--
-- ── THE RULE ──────────────────────────────────────────────────────────────────────────────────
--   EVERY ABSOLUTE DUCAT QUANTITY × 5. A quantity that is money — a purse, a stored price, a wage,
--   a fee, a premium, a cost basis, a price limit, a policy value, a city book — moves × 5.
--   DIMENSIONLESS things DO NOT MOVE: percentage rates, shares, spreads, multipliers, per-unit
--   ratios, counts and tonnes. The one knob/column pair from the first version stays exactly as it
--   was: goods.base_value × 5 and goods_price_level 0.2 → 1.0.
--
-- ── WHAT MOVES, TABLE BY TABLE (each line is also a self-assert) ──────────────────────────────
--   public.players.ducats                 every house's purse, NPC merchants included (they are
--                                         players rows). Written through public.credit — the ONE
--                                         purse writer — as one RESCALE credit of 4 × the old purse
--                                         per house, so each old purse becomes 5 × and the append-only
--                                         ledger reconciles (Σ ledger = purse, still exact).
--   public.port_treasury.ducats           the rolled half of every city purse × 5.
--   public.port_treasury.reserve          the city's ducat reserve × 5.
--   public.port_treasury.invested         the ducats invested in the city (E5's stake) × 5.
--   public.treasury_daybook.ducats        the city's rolled day-book × 5. NECESSARY: public.tick_city
--                                         asserts ducats = Σ daybook; scaling the purse alone would
--                                         break the hour's own reconciliation.
--   public.treasury_flows.ducats          NOT LISTED — append-only history, never updated (see WHAT
--                                         DOES NOT MOVE); the live balance is 5 × port_treasury.ducats
--                                         (the rolled half, ×5) + these flows as they stand.
--   public.city_shares.paid               what a company paid for its city shares × 5.
--   public.city_shares.accrued            coupons accrued but not yet paid × 5 (the stats set-aside
--                                         trigger follows it in the same update).
--   public.trade_contracts.mid_at_post    an open request's mid at posting × 5.
--   public.trade_contracts.premium_per_unit  its per-unit premium × 5.
--   public.trade_contracts.premium_ducats the whole premium × 5.
--   public.trade_contracts.escrow         the premium its city set aside × 5 (the stats set-aside
--                                         trigger follows it). Expired/fulfilled contracts are history
--                                         and stay at the scale they were paid at.
--   public.fleet_wages.owed               the crew's unpaid wages (a ducat liability) × 5.
--   public.fleet_wages.visit_net          the visit's net × 5.
--   public.fleet_wages.visit_paid         the visit's paid × 5.
--   public.port_fee_debts.ducats          a fleet's outstanding dock/stores debt × 5.
--   public.insured_voyages.value          the insured cargo's value × 5.
--   public.insured_voyages.price          the premium already paid × 5.
--   public.insured_voyages.lost_value     the loss measured × 5.
--   public.insured_voyages.paid           what the insurer paid × 5.
--   public.insured_voyages.short          the uncovered loss × 5.
--   public.insured_voyages.basis          the per-unit cargo cost basis (ducats a tun) × 5.
--   public.hull_recipes.ducats            every hull's yard price, set to its re-derived ×5 data
--                                         value (the generator re-rounds the labour to 500 and
--                                         re-fits the shed at the new scale; 98 of 103 land a few
--                                         thousand ducats from a blind old ×5, so the data value is
--                                         written exactly).
--   public.ship_classes.build_cost        every class's design build price, the same way (4 × the
--                                         re-derived hull labour).
--   public.officers.wage_ducats           every captain's wage × 5.
--   public.npc_houses.capital             every merchant company's capital × 5.
--   public.ships.cargo_basis              the per-unit cost of cargo aboard × 5.
--   public.player_storage.basis           the per-unit cost of goods ashore × 5.
--   public.standing_route_lines.price_limit  a route line's BUY ceiling / SELL floor × 5.
--   public.orders.args->'limit' + raw_text   an open/pending order's price limit × 5.
--   public.price_history.mid/ask/bid      the recorded price line × 5 (the chart meets the new level
--                                         instead of falling off a cliff; the 0208 precedent).
--   world_config (21 absolute ducat knobs) ×5:
--     starting_ducats (the founding purse), provision_food_price / provision_water_price (ducats a
--     tun), wage_per_crew_day (ducats a crew-day), repair_rate_per_point (ducats a point),
--     hire_crew_rate (ducats a hand), tow_fee_per_nm (ducats a mile), port_fee_base /
--     port_fee_per_ship (ducats a call / a ship), invest_min_ducats / donate_min_ducats (the smallest
--     stake / gift), skill_study_base_cost (ducats for a skill's first level), works_cost_base
--     (ducats for a city's first work level), restock_i_half (the investment at which restock is
--     half), stats_thin_purse (the thin-harbour threshold), city_purse_city / city_purse_capital
--     (the standing purse), city_seed_min (the least seed), city_earnings_per_dev (ducats a city
--     earns a dev a game-day), fame_ducats_per_point (ducats of turnover per fame point),
--     influence_day_cap (the ducat donation cap a day).
--   world_config.economy_closed_total     the closed economy's stamp (a ducat total) × 5 when it is
--                                         a number; null stays null.
--   public.stats_live (players/merchants/cities/set_aside)  the live Stats counters are brought to
--                                         the actual money after the re-base (players/merchants and set-aside ×5; cities = 5 × the rolled half + the flows, history) through
--                                         public.stats_live_add (the ONE live-figure helper), so the
--                                         world total the owner watches is exact from the first second.
--
-- ── WHAT DOES NOT MOVE ────────────────────────────────────────────────────────────────────────
--   No persistent function body is re-cut or created: public.new_house reads starting_ducats,
--   public.founding_credit and public.credit compose it, public.treasury_post and public.tick_city
--   read the city rows, and every fee/wage/premium is a knob or a stored row. The self-assert holds
--   the md5 of every function in public/cmd/world/voyage equal; the pg_temp helpers die with this
--   transaction. No ACL, volatility, definer or config. No column type. No port_goods row (the stock,
--   affinity, target and drift are asserted unchanged by md5). No goods recipe, no item recipe, no
--   cargo, hold, stock, count or tonne. No rate, percentage, share, spread, multiplier or per-unit
--   ratio.
--   HISTORY IS NOT REWRITTEN: public.ledger (append-only), public.events, public.capital_gifts,
--   public.city_month_book, public.route_month_laps, public.standing_route_laps,
--   public.voyages.wages_paid, the public.stats_* history, public.treasury_flows (append-only
--   aggregate history — 0122's trigger refuses any UPDATE), and every expired/fulfilled trade
--   contract stay at the scale their money actually moved at. The player
--   ledger reconciles through the RESCALE rows; the city's live purse is the ×5 rolled half plus
--   the flows as they stand, and the day-book is ×5 so tick_city's purse = daybook still holds; the
--   old books are books of real money and 0208 kept them for the
--   same reason. The public.price_history line IS scaled because it is the live chart the market
--   draws on, not a ledger of money moved (0208 scaled it for the same reason).
--   The two switches are OWNER-ONLY and are not touched: economy_closed and city_treasury_enabled
--   read back exactly as they were found (true on prod, false in a fresh local chain). The city
--   treasury's daily/hourly job and the closed economy's mint guard keep their rules — the RESCALE
--   kind is 'moved', so a closed economy's no-new-gold guard passes it by design.
--
-- ── THE CITY PURSE, SAID ONCE (because it is two rows and a book) ─────────────────────────────
--   public.treasury_balance(port) = port_treasury.ducats ×5 + Σ treasury_flows.ducats AS FOUND.
--   The flows are append-only history and are NOT re-scaled; port_treasury.ducats and
--   treasury_daybook.ducats ARE (tick_city's ASSERT requires ducats = Σ daybook). The next ROLL
--   folds the unscaled flows into the scaled purse and the scaled book — the one-time seam the
--   owner's rule accepts by calling the flows history. The stats_live cities counter is moved to
--   that actual live balance (5 × the rolled half + the flows) through stats_live_add, because a
--   direct row update does not fire the 0224 trigger (the trigger exists for treasury_post, which
--   this file does not need: the purse must be re-denominated, not paid in).
--
-- ── THE STATS LIVE, SAID ONCE ───────────────────────────────────────────────────────────────
--   The players/merchants counters move with every public.credit RESCALE row (credit calls
--   stats_live_add); the set-aside counter moves with the city_shares.accrued and trade_contracts
--   .escrow UPDATE triggers. The cities counter has no trigger on a bare port_treasury update, so a
--   final stats_live_add brings the four state figures to the actual after (players/merchants and
--   set-aside ×5; cities = 5 × the rolled half + the flows).
--   The sold/bought window counters are a period flow, not a state, and are left for the next count.
--
-- ── SUPERSEDE ─────────────────────────────────────────────────────────────────────────────────
--   0285 is 0208's exact inverse at the price level (0208 set goods_price_level 0.2 and applied it
--   once to the stored column; 0285 multiplies the stored column by 5 and sets the knob to 1.0), and
--   it re-cuts NO function and supersedes NO body: 0208's world.haul_at / world.haul_rows /
--   public.item_recipe_value hunks stay exactly as they are. The whole-scale money moves are DATA
--   and knobs, not function bodies.
--
-- ── SELF-ASSERT (all inside the applying transaction; the probe is rolled back) ───────────────
--   (a) goods ×5, the column still numeric(10,2), the knob 1.0; item_recipe_value unchanged on
--       every recipe product; port_goods and every function md5 unchanged;
--   (b) every house's purse exactly 5 × its as-found value, and the RESCALE rows = 4 × the old
--       purses (one per house with money);
--   (c) every row of every table above exactly 5 × its as-found money — the 103 hull/class prices
--       equal the re-derived data value (the same ×5 scale through the generator's 500-ducat
--       rounding and shed re-fit) — the row counts unchanged;
--   (d) the city: port_treasury ×5 and treasury_daybook ×5, treasury_balance = 5 × the as-found
--       rolled half + the as-found flows for every port, port_treasury.ducats = Σ treasury_daybook
--       (the tick_city invariant), and treasury_flows unchanged (history, append-only);
--   (e) every one of the 21 knobs ×5, every other knob unchanged except goods_price_level 0.1 →
--       1.0, and the two owner switches unchanged; economy_closed_total ×5 when numeric;
--   (f) the live Stats: players/merchants and set-aside ×5, cities = 5 × the rolled half + the flows,
--       and world.stats_now().total = 5 × the actual world total; stats_watch's under_thin,
--       under_reserve, broke and swing equal, thin ×5 (the gifts' ducat history is not rewritten and
--       is not asserted);
--   (g) a rolled-back probe on one harbour good: world.price/world.quote mid/ask/bid/avg_price/total
--       move ~5 × when that one good is scaled ×5, then the rollback restores it.
--
-- ── PROD CHECKS (read-only, one SELECT per file; run before the push) ─────────────────────────
--   Expected as found on 2026-10-31 (head 20260818000284; the exact numbers above in THE MEASURED
--   STATE), and after the push every money figure is ×5: players 1,704,092,571 → 8,520,462,855;
--   the city live balance 47,346,325 → 236,731,625; set-aside (open escrow + city_shares.accrued)
--   275,143,554 → 1,375,717,770; world total 2,026,582,450 → 10,132,912,250; economy_closed_total
--   1,986,693,521 → 9,933,467,605; starting_ducats 8,000 → 40,000; wage_per_crew_day 1 → 5;
--   barca hull 3,000 → 15,000 and barca build_cost 12,000 → 60,000 (the 103 hull/class prices are
--   the re-derived data values; 98 differ a few thousand from a blind old ×5 by the generator's
--   500-ducat rounding); NPC capital 5,000 … 729,000 →
--   25,000 … 3,645,000; city shares paid 137,085,286 → 685,426,430 and accrued 273,323,914 →
--   1,366,619,570; open premium 1,866,702 → 9,333,510 and escrow 1,819,640 → 9,098,200;
--   insured value 1,427,040,231 → 7,135,201,155; fleet owed 65,612.60 → 328,063.00; fee debts
--   159,208 → 796,040; route limits 1,635 rows ×5; price_history mid 1.0449 … 2,062.9058 → 5.2245 …
--   10,314.5290; stats watch thin 10,000 → 50,000, under_thin 187, under_reserve 131, broke 51
--   (the ratios are preserved), swing 0.0641/0.1669 unchanged; the goods md5, the 222 recipe
--   values, port_goods md5 and the 663 function md5 unchanged.
--   The exact SQL blocks are in docs/dev-log/2026-10-31-goods-price-level.md §PROD CHECKS and in
--   the PR body; the local proof gate runs PROOF 5 and PROOF 7, and every proof in the chain.
--
-- ── FORWARD ROLLBACK (a new migration, never an edit of this one) ─────────────────────────────
--   The exact inverse, in one forward file: goods.base_value / 5 and goods_price_level → 0.2; every
--   table above's money ÷ 5; every knob ÷ 5; the city's rolled purse/day-book ÷ 5 (the flows were
--   never scaled and stay); the stats_live
--   counters brought back through stats_live_add; economy_closed_total ÷ 5; the RESCALE kind stays
--   and the player purses are taken back with a RESCALE credit of −4/5 of the current purse per
--   house. The history books stay as recorded. Only the owner may call for it.
--
-- VERSION: 0285 (prod head 0284).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
declare
  v_col   text;
  v_bad_n int;
  v_bad   text;
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.goods') is null
     or to_regclass('public.port_goods') is null
     or to_regclass('public.world_config') is null
     or to_regclass('public.players') is null
     or to_regclass('public.port_treasury') is null
     or to_regclass('public.treasury_daybook') is null
     or to_regclass('public.treasury_flows') is null
     or to_regclass('public.city_shares') is null
     or to_regclass('public.trade_contracts') is null
     or to_regclass('public.fleet_wages') is null
     or to_regclass('public.port_fee_debts') is null
     or to_regclass('public.insured_voyages') is null
     or to_regclass('public.hull_recipes') is null
     or to_regclass('public.ship_classes') is null
     or to_regclass('public.officers') is null
     or to_regclass('public.npc_houses') is null
     or to_regclass('public.ships') is null
     or to_regclass('public.player_storage') is null
     or to_regclass('public.standing_route_lines') is null
     or to_regclass('public.orders') is null
     or to_regclass('public.price_history') is null
     or to_regclass('public.stats_live') is null
     or to_regclass('public.stats_live_deltas') is null
     or to_regclass('public.item_recipes') is null
     or to_regprocedure('public.wc_num(text)') is null
     or to_regprocedure('public.wc_int(text)') is null
     or to_regprocedure('public.credit(uuid,text,bigint,uuid)') is null
     or to_regprocedure('public.stats_live_add(jsonb)') is null
     or to_regprocedure('public.hold_the_quay()') is null
     or to_regprocedure('public.mint_gate(boolean)') is null
     or to_regprocedure('public.item_recipe_value(text)') is null
     or to_regprocedure('public.port_offers(uuid, uuid)') is null
     or to_regprocedure('world.price(uuid, uuid)') is null
     or to_regprocedure('world.quote(uuid, uuid, numeric, text, numeric, uuid)') is null then
    raise exception '0285 refuses: a table or function this file reads is not in this world';
  end if;
  select c.data_type || '|' || coalesce(c.numeric_precision::text, '') || '|' || coalesce(c.numeric_scale::text, '')
    into v_col
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'goods' and c.column_name = 'base_value';
  if v_col is distinct from 'numeric|10|2' then
    raise exception '0285 refuses: goods.base_value is %, not numeric(10,2)', v_col;
  end if;
  if not exists (select 1 from public.world_config where key = 'goods_price_level') then
    raise exception '0285 refuses: goods_price_level is missing — 0208 is not in this world';
  end if;
  if public.wc_num('goods_price_level') = 1.0 then
    raise exception '0285 refuses: goods_price_level already reads 1.0 — this has been applied once';
  end if;
  if public.wc_num('goods_price_level') is distinct from 0.2 then
    raise exception '0285 refuses: goods_price_level reads %, not 0.2 — this is not the state 0208 wrote and 0285 inverts',
      public.wc_num('goods_price_level');
  end if;
  if exists (select 1 from public.stats_flow_words where kind = 'RESCALE') then
    raise exception '0285 refuses: the RESCALE flow kind already exists — this has been applied once';
  end if;
  if (select count(*) from public.goods) = 0 or (select count(*) from public.players) = 0 then
    raise exception '0285 refuses: no goods or no houses to re-base';
  end if;
  select count(*), string_agg(g.code, ', ' order by g.code)
    into v_bad_n, v_bad
    from public.goods g
   where g.base_value is null
      or g.base_value <= 0
      or g.base_value = 'NaN'::numeric
      or g.base_value = 'Infinity'::numeric
      or g.base_value = '-Infinity'::numeric;
  if v_bad_n > 0 then
    raise exception '0285 refuses: % good(s) with a non-finite or <= 0 base_value: %', v_bad_n, v_bad;
  end if;
end $guard$;

-- ── THE WINDOW ────────────────────────────────────────────────────────────────────────────────
-- THE ORDER IS THE ECONOMY'S: the quay (no arrivals beat, trade, lap or company step is half done),
-- then the mint gate exclusive (every writer of new gold has committed; later ones wait and are
-- judged by the flags read here), then SHARE on every table this file touches (SHARE conflicts with
-- ROW EXCLUSIVE and allows reads, so no trade, city job, drift, snapshot or compactor can move a
-- figure between the snapshots and the asserts). All locks are held to the commit.
do $lock$
begin
  perform set_config('lock_timeout', '5s', true);
  perform public.hold_the_quay();
  perform public.mint_gate(true);
  lock table public.players, public.port_treasury, public.treasury_daybook, public.treasury_flows,
             public.city_shares, public.trade_contracts, public.fleet_wages, public.port_fee_debts,
             public.insured_voyages, public.hull_recipes, public.ship_classes, public.officers,
             public.npc_houses, public.ships, public.player_storage, public.standing_route_lines,
             public.orders, public.price_history, public.port_goods, public.world_config,
             public.stats_live, public.stats_live_deltas in share mode;
end $lock$;

-- ── DIGEST HELPERS (pg_temp; gone at commit, never a deployed function) ───────────────────────
create function pg_temp.goods_md5_0285()
returns text
language sql
stable
as $$
  select md5(string_agg(g.code || '|' || g.base_value, E'\n' order by g.code))
    from public.goods g
$$;

create function pg_temp.port_goods_md5_0285()
returns text
language sql
stable
as $$
  select md5(string_agg(pg.port_id::text || '|' || pg.good_id::text || '|' || pg.stock || '|' ||
                        pg.affinity || '|' || pg.stock_target || '|' || pg.drift,
                        E'\n' order by pg.port_id, pg.good_id))
    from public.port_goods pg
$$;

create function pg_temp.fns_n_0285()
returns int
language sql
stable
as $$
  select count(*)::int
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
$$;

create function pg_temp.fns_md5_0285()
returns text
language sql
stable
as $$
  select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')),
                        ',' order by p.oid::regprocedure::text))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
$$;

-- ── AS FOUND ──────────────────────────────────────────────────────────────────────────────────
create temp table snap_0285 on commit drop as
select
  (select count(*) from public.goods)               as goods_n,
  pg_temp.goods_md5_0285()                          as goods_md5,
  public.wc_num('goods_price_level')                as knob,
  (select count(*) from public.port_goods)          as port_goods_n,
  pg_temp.port_goods_md5_0285()                     as port_goods_md5,
  pg_temp.fns_n_0285()                              as fns_n,
  pg_temp.fns_md5_0285()                            as fns_md5,
  (select min(base_value) from public.goods)        as base_min,
  (select max(base_value) from public.goods)        as base_max,
  (select count(*) from public.players)             as players_n,
  (select coalesce(sum(ducats), 0) from public.players where not is_npc) as players_np_sum,
  (select coalesce(sum(ducats), 0) from public.players where is_npc)     as players_npc_sum,
  (select coalesce(sum(ducats), 0) from public.players)                  as players_sum,
  (select count(*) from public.port_treasury)       as pt_n,
  (select coalesce(sum(ducats), 0) from public.port_treasury)   as pt_ducats_sum,
  (select coalesce(sum(reserve), 0) from public.port_treasury)  as pt_reserve_sum,
  (select coalesce(sum(coalesce(invested, 0)), 0) from public.port_treasury) as pt_invested_sum,
  (select count(*) from public.treasury_daybook)    as daybook_n,
  (select coalesce(sum(ducats), 0) from public.treasury_daybook) as daybook_sum,
  (select count(*) from public.treasury_flows)      as flows_n,
  (select coalesce(sum(ducats), 0) from public.treasury_flows)  as flows_sum,
  (select count(*) from public.city_shares)         as shares_n,
  (select coalesce(sum(paid), 0) from public.city_shares)    as shares_paid_sum,
  (select coalesce(sum(accrued), 0) from public.city_shares) as shares_accrued_sum,
  (select count(*) from public.trade_contracts where status = 'open') as open_n,
  (select coalesce(sum(premium_ducats), 0) from public.trade_contracts where status = 'open') as open_premium_sum,
  (select coalesce(sum(escrow), 0) from public.trade_contracts where status = 'open') as open_escrow_sum,
  (select count(*) from public.fleet_wages)         as wages_n,
  (select coalesce(sum(owed), 0) from public.fleet_wages) as wages_owed_sum,
  (select count(*) from public.port_fee_debts)      as debts_n,
  (select coalesce(sum(ducats), 0) from public.port_fee_debts) as debts_sum,
  (select count(*) from public.insured_voyages)     as insured_n,
  (select coalesce(sum(value), 0) from public.insured_voyages) as insured_value_sum,
  (select coalesce(sum(price), 0) from public.insured_voyages) as insured_price_sum,
  (select count(*) from public.hull_recipes)        as hull_n,
  (select count(*) from public.ship_classes)        as class_n,
  (select count(*) from public.officers)            as officer_n,
  (select count(*) from public.npc_houses)          as npc_house_n,
  (select coalesce(sum(capital), 0) from public.npc_houses) as npc_capital_sum,
  (select count(*) from public.price_history)       as ph_n,
  (select count(*) from public.ships where cargo_basis <> '{}'::jsonb) as basis_n,
  (select count(*) from public.standing_route_lines where price_limit is not null) as route_n,
  (select count(*) from public.orders
    where status in ('pending', 'active') and jsonb_typeof(args->'limit') = 'number') as order_n,
  world.stats_now()                                 as stats_now,
  public.stats_watch(now())                         as watch,
  (select value from public.world_config where key = 'economy_closed_total') as econ_total,
  (select value from public.world_config where key = 'economy_closed') as econ_closed,
  (select value from public.world_config where key = 'city_treasury_enabled') as city_lit;

create temp table players_0285 on commit drop as
select id, ducats from public.players;

create temp table pt_0285 on commit drop as
select port_id, ducats, reserve, invested from public.port_treasury;

create temp table daybook_0285 on commit drop as
select port_id, game_day, kind, ducats from public.treasury_daybook;

create temp table flows_0285 on commit drop as
select id, port_id, kind, ducats from public.treasury_flows;

create temp table shares_0285 on commit drop as
select port_id, kind, player_id, paid, accrued from public.city_shares;

create temp table contracts_0285 on commit drop as
select id, status, mid_at_post, premium_per_unit, premium_ducats, escrow from public.trade_contracts;

create temp table wages_0285 on commit drop as
select fleet_id, owed, visit_net, visit_paid from public.fleet_wages;

create temp table debts_0285 on commit drop as
select player_id, port_id, kind, ducats from public.port_fee_debts;

create temp table insured_0285 on commit drop as
select voyage_id, value, price, lost_value, paid, short, basis from public.insured_voyages;

create temp table want_hull_0285 on commit drop as
select * from (values
  ('barca', 15000::bigint), ('carlat', 35000), ('nau', 150000),
  ('carred', 40000), ('galeao', 275000), ('patache', 16500), ('carabela', 38500), ('zabra', 44000),
  ('urca', 165000), ('galeon', 302500), ('jacht', 10000), ('buss', 30000), ('fluyt', 127500),
  ('pinas', 144500), ('retour', 204000), ('pinnace', 12500), ('crayer', 16000), ('bark', 47000),
  ('levanter', 157500), ('racegal', 289000), ('barque', 16000), ('carnorm', 37000), ('navire', 157500),
  ('galere', 178500), ('galion', 289000), ('fusta', 19000), ('marcil', 38500), ('galsott', 44000),
  ('galgros', 165000), ('caracca', 264000), ('kayik', 15000), ('xebec', 40000), ('karamur', 150000),
  ('kadirga', 170000), ('bastarda', 275000), ('dhow', 13000), ('sambuk', 10000), ('ghurab', 34000),
  ('baghlah', 127500), ('jahaz', 204000), ('niao', 11000), ('shachuan', 31500), ('cangshan', 36000),
  ('junk', 135000), ('fuchuan', 247500), ('kobaya', 17500), ('kobune', 15000), ('sekibune', 40000),
  ('shuinsen', 150000), ('ataka', 275000), ('hyeop', 12000), ('sangseon', 35000), ('byeong', 40000),
  ('joun', 150000), ('panok', 275000), ('naucarr', 400000), ('carraca', 768000), ('galmanila', 440000),
  ('galreal', 953000), ('spiegel', 340000), ('indiaman', 420000), ('greatship', 911000), ('grandnav', 499000),
  ('galeazza', 522500), ('kalyon', 475000), ('bashum', 864000), ('hajji', 340000), ('dachuan', 360000),
  ('oataka', 475000), ('daepanok', 475000), ('carvarm', 100000), ('nauguerra', 375000), ('galplata', 664000),
  ('dunkirk', 110000), ('armfluit', 319000), ('kaper', 85000), ('qpinnace', 31500), ('armmerch', 394000),
  ('fregcourse', 105000), ('fluteroy', 394000), ('galbast', 467500), ('carcarm', 664500), ('korsan', 100000),
  ('mavna', 653000), ('batil', 25500), ('ghurabj', 85000), ('zhanchuan', 382500), ('haicang', 542500),
  ('murakami', 44000), ('oshuin', 375000), ('tamang', 30000), ('bangpae', 425000), ('madre', 3091500),
  ('sanmartin', 3831500), ('batavia', 828000), ('goldenhind', 147000), ('couronne', 2045500), ('duodo', 2140500),
  ('turgut', 684000), ('rahimi', 2652500), ('baochuan', 2758000), ('sjb', 934000), ('geobuk', 682000)
) v(class_code, ducats);

create temp table want_class_0285 on commit drop as
select * from (values
  ('barca', 60000::numeric), ('carlat', 140000), ('nau', 600000),
  ('carred', 160000), ('galeao', 1100000), ('patache', 66000), ('carabela', 154000), ('zabra', 176000),
  ('urca', 660000), ('galeon', 1210000), ('jacht', 40000), ('buss', 120000), ('fluyt', 510000),
  ('pinas', 578000), ('retour', 816000), ('pinnace', 50000), ('crayer', 64000), ('bark', 188000),
  ('levanter', 630000), ('racegal', 1156000), ('barque', 64000), ('carnorm', 148000), ('navire', 630000),
  ('galere', 714000), ('galion', 1156000), ('fusta', 76000), ('marcil', 154000), ('galsott', 176000),
  ('galgros', 660000), ('caracca', 1056000), ('kayik', 60000), ('xebec', 160000), ('karamur', 600000),
  ('kadirga', 680000), ('bastarda', 1100000), ('dhow', 52000), ('sambuk', 40000), ('ghurab', 136000),
  ('baghlah', 510000), ('jahaz', 816000), ('niao', 44000), ('shachuan', 126000), ('cangshan', 144000),
  ('junk', 540000), ('fuchuan', 990000), ('kobaya', 70000), ('kobune', 60000), ('sekibune', 160000),
  ('shuinsen', 600000), ('ataka', 1100000), ('hyeop', 48000), ('sangseon', 140000), ('byeong', 160000),
  ('joun', 600000), ('panok', 1100000), ('naucarr', 1600000), ('carraca', 3072000), ('galmanila', 1760000),
  ('galreal', 3812000), ('spiegel', 1360000), ('indiaman', 1680000), ('greatship', 3644000), ('grandnav', 1996000),
  ('galeazza', 2090000), ('kalyon', 1900000), ('bashum', 3456000), ('hajji', 1360000), ('dachuan', 1440000),
  ('oataka', 1900000), ('daepanok', 1900000), ('carvarm', 400000), ('nauguerra', 1500000), ('galplata', 2656000),
  ('dunkirk', 440000), ('armfluit', 1276000), ('kaper', 340000), ('qpinnace', 126000), ('armmerch', 1576000),
  ('fregcourse', 420000), ('fluteroy', 1576000), ('galbast', 1870000), ('carcarm', 2658000), ('korsan', 400000),
  ('mavna', 2612000), ('batil', 102000), ('ghurabj', 340000), ('zhanchuan', 1530000), ('haicang', 2170000),
  ('murakami', 176000), ('oshuin', 1500000), ('tamang', 120000), ('bangpae', 1700000), ('madre', 12366000),
  ('sanmartin', 15326000), ('batavia', 3312000), ('goldenhind', 588000), ('couronne', 8182000), ('duodo', 8562000),
  ('turgut', 2736000), ('rahimi', 10610000), ('baochuan', 11032000), ('sjb', 3736000), ('geobuk', 2728000)
) v(code, build_cost);

create temp table officer_0285 on commit drop as
select id, wage_ducats from public.officers;

create temp table npc_house_0285 on commit drop as
select player_id, capital from public.npc_houses;

create temp table basis_0285 on commit drop as
select id, cargo_basis from public.ships where cargo_basis <> '{}'::jsonb;

create temp table storage_0285 on commit drop as
select player_id, port_id, good_id, basis from public.player_storage where basis is not null;

create temp table route_0285 on commit drop as
select route_id, stop_ord, ord, price_limit from public.standing_route_lines where price_limit is not null;

create temp table orders_0285 on commit drop as
select id, raw_text, args from public.orders
 where status in ('pending', 'active') and jsonb_typeof(args->'limit') = 'number';

create temp table ph_0285 on commit drop as
select port_id, good_id, slot, mid, ask, bid from public.price_history;

create temp table knobs_0285 on commit drop as
select key, value from public.world_config;

create temp table goods_0285 on commit drop as
select id, code, base_value from public.goods;

create temp table recipe_0285 on commit drop as
select distinct ir.item_code as code, public.item_recipe_value(ir.item_code) as v
  from public.item_recipes ir;

-- THE ACTUAL BEFORE (the four money state buckets; the world total the owner watches)
create temp table actual_0285 on commit drop as
select
  (select coalesce(sum(ducats), 0) from public.players)::bigint as players,
  (select coalesce(sum(ducats), 0) from public.port_treasury)
    + (select coalesce(sum(ducats), 0) from public.treasury_flows) as cities,
  (select coalesce(sum(escrow), 0) from public.trade_contracts where status = 'open')
    + (select coalesce(sum(accrued), 0) from public.city_shares) as set_aside;

-- ── THE CHANGE ───────────────────────────────────────────────────────────────────────────────
-- 1. The first version's pair: the stored goods ×5 and the knob 0.2 → 1.0.
update public.goods set base_value = round(base_value * 5, 2);

update public.world_config
   set value = to_jsonb(1.0),
       updated_at = now(),
       description = description || ' 0285: re-based to 1.0; the stored goods.base_value was x5 onto the design level.'
 where key = 'goods_price_level';

-- 2. Every absolute ducat knob ×5 (the 21 listed in the header; rates and percentages are not here).
update public.world_config c
   set value = to_jsonb((c.value #>> '{}')::numeric * 5),
       updated_at = now(),
       description = c.description || ' 0285: x5 whole-scale re-base.'
 where c.key = any (array[
   'starting_ducats', 'provision_food_price', 'provision_water_price', 'wage_per_crew_day',
   'repair_rate_per_point', 'hire_crew_rate', 'tow_fee_per_nm', 'port_fee_base', 'port_fee_per_ship',
   'invest_min_ducats', 'donate_min_ducats', 'skill_study_base_cost', 'works_cost_base',
   'restock_i_half', 'stats_thin_purse', 'city_purse_city', 'city_purse_capital', 'city_seed_min',
   'city_earnings_per_dev', 'fame_ducats_per_point', 'influence_day_cap'
 ]);

-- The closed economy's stamp is a ducat total; scale it only when it is a number (null while open).
update public.world_config
   set value = to_jsonb((value #>> '{}')::bigint * 5),
       updated_at = now(),
       description = description || ' 0285: x5 whole-scale re-base.'
 where key = 'economy_closed_total' and jsonb_typeof(value) = 'number';

-- 3. The word the ledger and the money feed print for the re-denomination.
insert into public.stats_flow_words (kind, side, word, ord)
values ('RESCALE', 'moved', 'Money re-based', 43);

-- 4. Every house's purse ×5 through THE ONE PURSE WRITER: a RESCALE credit of 4 × the old purse.
--    (kind RESCALE is 'moved', so the closed economy's mint guard passes it; credit also journals the
--    players/merchants live Stats figure in the same statement.)
do $run$
declare
  r     record;
  v_n   int := 0;
  v_sum bigint := 0;
begin
  for r in select id, ducats from public.players where ducats <> 0 order by id loop
    perform public.credit(r.id, 'RESCALE', r.ducats * 4, null);
    v_n := v_n + 1;
    v_sum := v_sum + r.ducats * 4;
  end loop;
  raise notice '0285 rescale: % house(s), % ducat(s) credited through public.credit', v_n, v_sum;
end $run$;

-- 5. The city's rolled purse and the book that reconciles it. public.treasury_flows is NOT touched:
--    it is append-only aggregate history (0122's tg_treasury_append_only refuses any UPDATE — the
--    first prod push stopped on its 12,041 rows), and this slice's rule keeps history at the scale
--    its money moved at. The live balance is the ×5 rolled half plus those flows.
update public.port_treasury
   set ducats = ducats * 5,
       reserve = reserve * 5,
       invested = case when invested is null then null else invested * 5 end,
       updated_at = now();

update public.treasury_daybook set ducats = ducats * 5;

-- 6. The city's shares, and the open requests' money (expired/fulfilled contracts are history).
update public.city_shares set paid = paid * 5, accrued = accrued * 5;

update public.trade_contracts
   set mid_at_post = mid_at_post * 5,
       premium_per_unit = premium_per_unit * 5,
       premium_ducats = premium_ducats * 5,
       escrow = escrow * 5
 where status = 'open';

-- 7. The live liabilities and policies.
update public.fleet_wages set owed = owed * 5, visit_net = visit_net * 5, visit_paid = visit_paid * 5;
update public.port_fee_debts set ducats = ducats * 5, updated_at = now();

update public.insured_voyages
   set value = value * 5,
       price = price * 5,
       lost_value = lost_value * 5,
       paid = paid * 5,
       short = short * 5,
       basis = case when basis is null or basis = '{}'::jsonb then basis
                    else (select jsonb_object_agg(e.key,
                            case when jsonb_typeof(e.value) = 'number'
                                 then to_jsonb((e.value #>> '{}')::numeric * 5) else e.value end)
                            from jsonb_each(basis) e) end;

-- 8. The catalogue prices: every hull, every class, every captain, every merchant's capital.
--    The hulls and classes take their data values, NOT a blind old ×5: build-ships.mjs re-rounds
--    every archetype's labour to 500 ducats and re-fits the shed at the new scale, so 98 of the 103
--    prices land a few thousand ducats from 5 × the old column. The 103 values below are exactly
--    data/hulls.json (3 live) + data/ships.generated.json (100 generated), and 4 × the labour for
--    each class; the world-guard holds the database to the same files.
update public.hull_recipes h set ducats = v.ducats
  from (values
    ('barca', 15000::bigint), ('carlat', 35000), ('nau', 150000),
    ('carred', 40000), ('galeao', 275000), ('patache', 16500), ('carabela', 38500), ('zabra', 44000),
    ('urca', 165000), ('galeon', 302500), ('jacht', 10000), ('buss', 30000), ('fluyt', 127500),
    ('pinas', 144500), ('retour', 204000), ('pinnace', 12500), ('crayer', 16000), ('bark', 47000),
    ('levanter', 157500), ('racegal', 289000), ('barque', 16000), ('carnorm', 37000), ('navire', 157500),
    ('galere', 178500), ('galion', 289000), ('fusta', 19000), ('marcil', 38500), ('galsott', 44000),
    ('galgros', 165000), ('caracca', 264000), ('kayik', 15000), ('xebec', 40000), ('karamur', 150000),
    ('kadirga', 170000), ('bastarda', 275000), ('dhow', 13000), ('sambuk', 10000), ('ghurab', 34000),
    ('baghlah', 127500), ('jahaz', 204000), ('niao', 11000), ('shachuan', 31500), ('cangshan', 36000),
    ('junk', 135000), ('fuchuan', 247500), ('kobaya', 17500), ('kobune', 15000), ('sekibune', 40000),
    ('shuinsen', 150000), ('ataka', 275000), ('hyeop', 12000), ('sangseon', 35000), ('byeong', 40000),
    ('joun', 150000), ('panok', 275000), ('naucarr', 400000), ('carraca', 768000), ('galmanila', 440000),
    ('galreal', 953000), ('spiegel', 340000), ('indiaman', 420000), ('greatship', 911000), ('grandnav', 499000),
    ('galeazza', 522500), ('kalyon', 475000), ('bashum', 864000), ('hajji', 340000), ('dachuan', 360000),
    ('oataka', 475000), ('daepanok', 475000), ('carvarm', 100000), ('nauguerra', 375000), ('galplata', 664000),
    ('dunkirk', 110000), ('armfluit', 319000), ('kaper', 85000), ('qpinnace', 31500), ('armmerch', 394000),
    ('fregcourse', 105000), ('fluteroy', 394000), ('galbast', 467500), ('carcarm', 664500), ('korsan', 100000),
    ('mavna', 653000), ('batil', 25500), ('ghurabj', 85000), ('zhanchuan', 382500), ('haicang', 542500),
    ('murakami', 44000), ('oshuin', 375000), ('tamang', 30000), ('bangpae', 425000), ('madre', 3091500),
    ('sanmartin', 3831500), ('batavia', 828000), ('goldenhind', 147000), ('couronne', 2045500), ('duodo', 2140500),
    ('turgut', 684000), ('rahimi', 2652500), ('baochuan', 2758000), ('sjb', 934000), ('geobuk', 682000)
  ) v(class_code, ducats)
 where h.class_code = v.class_code;

update public.ship_classes c set build_cost = v.build_cost
  from (values
    ('barca', 60000::numeric), ('carlat', 140000), ('nau', 600000),
    ('carred', 160000), ('galeao', 1100000), ('patache', 66000), ('carabela', 154000), ('zabra', 176000),
    ('urca', 660000), ('galeon', 1210000), ('jacht', 40000), ('buss', 120000), ('fluyt', 510000),
    ('pinas', 578000), ('retour', 816000), ('pinnace', 50000), ('crayer', 64000), ('bark', 188000),
    ('levanter', 630000), ('racegal', 1156000), ('barque', 64000), ('carnorm', 148000), ('navire', 630000),
    ('galere', 714000), ('galion', 1156000), ('fusta', 76000), ('marcil', 154000), ('galsott', 176000),
    ('galgros', 660000), ('caracca', 1056000), ('kayik', 60000), ('xebec', 160000), ('karamur', 600000),
    ('kadirga', 680000), ('bastarda', 1100000), ('dhow', 52000), ('sambuk', 40000), ('ghurab', 136000),
    ('baghlah', 510000), ('jahaz', 816000), ('niao', 44000), ('shachuan', 126000), ('cangshan', 144000),
    ('junk', 540000), ('fuchuan', 990000), ('kobaya', 70000), ('kobune', 60000), ('sekibune', 160000),
    ('shuinsen', 600000), ('ataka', 1100000), ('hyeop', 48000), ('sangseon', 140000), ('byeong', 160000),
    ('joun', 600000), ('panok', 1100000), ('naucarr', 1600000), ('carraca', 3072000), ('galmanila', 1760000),
    ('galreal', 3812000), ('spiegel', 1360000), ('indiaman', 1680000), ('greatship', 3644000), ('grandnav', 1996000),
    ('galeazza', 2090000), ('kalyon', 1900000), ('bashum', 3456000), ('hajji', 1360000), ('dachuan', 1440000),
    ('oataka', 1900000), ('daepanok', 1900000), ('carvarm', 400000), ('nauguerra', 1500000), ('galplata', 2656000),
    ('dunkirk', 440000), ('armfluit', 1276000), ('kaper', 340000), ('qpinnace', 126000), ('armmerch', 1576000),
    ('fregcourse', 420000), ('fluteroy', 1576000), ('galbast', 1870000), ('carcarm', 2658000), ('korsan', 400000),
    ('mavna', 2612000), ('batil', 102000), ('ghurabj', 340000), ('zhanchuan', 1530000), ('haicang', 2170000),
    ('murakami', 176000), ('oshuin', 1500000), ('tamang', 120000), ('bangpae', 1700000), ('madre', 12366000),
    ('sanmartin', 15326000), ('batavia', 3312000), ('goldenhind', 588000), ('couronne', 8182000), ('duodo', 8562000),
    ('turgut', 2736000), ('rahimi', 10610000), ('baochuan', 11032000), ('sjb', 3736000), ('geobuk', 2728000)
  ) v(code, build_cost)
 where c.code = v.code;

update public.officers set wage_ducats = wage_ducats * 5;
update public.npc_houses set capital = capital * 5;

-- 9. The per-unit cost bases and the forward price commitments.
update public.ships s
   set cargo_basis = (select jsonb_object_agg(e.key,
                        case when jsonb_typeof(e.value) = 'number'
                             then to_jsonb((e.value #>> '{}')::numeric * 5) else e.value end)
                        from jsonb_each(s.cargo_basis) e)
 where s.cargo_basis <> '{}'::jsonb and s.cargo_basis is not null;

update public.player_storage set basis = basis * 5 where basis is not null;
update public.standing_route_lines set price_limit = price_limit * 5 where price_limit is not null;

update public.orders o
   set args = jsonb_set(o.args, '{limit}', to_jsonb((o.args->>'limit')::numeric * 5)),
       raw_text = case when o.raw_text ~* ' AT [0-9]+(\.[0-9]+)?$'
                       then regexp_replace(o.raw_text, ' AT [0-9]+(\.[0-9]+)?$',
                              ' AT ' || trim_scale((o.args->>'limit')::numeric * 5)::text, 'i')
                       else o.raw_text end
 where o.status in ('pending', 'active') and jsonb_typeof(o.args->'limit') = 'number';

-- 10. The price line the chart draws (mid 4 dp; ask/bid 2 dp), so it meets the new level.
update public.price_history
   set mid = round(mid * 5, 4),
       ask = case when ask is null then null else round(ask * 5, 2) end,
       bid = case when bid is null then null else round(bid * 5, 2) end;

-- 11. Bring the four live Stats state figures to the actual money after the re-base: players and
--     merchants ×5, cities = 5 × the rolled half + the flows (history, unscaled), set-aside ×5.
--     The credit rows moved players/merchants; the city_shares.accrued and trade_contracts.escrow
--     UPDATE triggers moved set_aside; the cities counter has no trigger on a bare purse update, so
--     one stats_live_add settles all four (the helper writes one journal row per changed figure, as
--     0224 requires).
do $stats$
declare
  v_act  record;
  v_now  jsonb;
  v_np   bigint;
  v_npc  bigint;
  v_city bigint;
  v_set  bigint;
begin
  select * into v_act from actual_0285;
  select world.stats_now() into v_now;
  v_np   := 5 * (select players_np_sum from snap_0285);
  v_npc  := 5 * (select players_npc_sum from snap_0285);
  -- the flows are history and stay: 5 × (rolled + flows) - 4 × flows = 5 × rolled + flows
  v_city := 5 * v_act.cities - 4 * (select flows_sum from snap_0285);
  v_set  := 5 * v_act.set_aside;
  perform public.stats_live_add(jsonb_build_object(
    'players',   v_np   - (v_now->>'players')::bigint,
    'merchants', v_npc  - (v_now->>'merchants')::bigint,
    'cities',    v_city - (v_now->>'cities')::bigint,
    'set_aside', v_set  - (v_now->>'set_aside')::bigint));
end $stats$;

-- ── SELF-ASSERT ───────────────────────────────────────────────────────────────────────────────
do $$
declare
  v       record;
  v_n     int;
  v_bad   int;
  v_min   numeric;
  v_max   numeric;
  v_gmd5  text;
  v_rc_n  int;
  v_rc_bad int;
  v_big   bigint;
  v_now   jsonb;
  v_watch jsonb;
  v_port  uuid;
  v_good  uuid;
  v_pcode text;
  v_gcode text;
  v_base  numeric;
  v_nowbase numeric;
  v_b     record;
  v_s     record;
  v_qb    record;
  v_qs    record;
  v_mid_x numeric;
  v_ask_x numeric;
  v_bid_x numeric;
  v_avg_x numeric;
  v_tot_x numeric;
  v_act   record;
  v_np    bigint;
  v_npc   bigint;
  v_city  bigint;
  v_set   bigint;
  v_rc_rows int;
  v_scaled constant text[] := array[
    'starting_ducats', 'provision_food_price', 'provision_water_price', 'wage_per_crew_day',
    'repair_rate_per_point', 'hire_crew_rate', 'tow_fee_per_nm', 'port_fee_base', 'port_fee_per_ship',
    'invest_min_ducats', 'donate_min_ducats', 'skill_study_base_cost', 'works_cost_base',
    'restock_i_half', 'stats_thin_purse', 'city_purse_city', 'city_purse_capital', 'city_seed_min',
    'city_earnings_per_dev', 'fame_ducats_per_point', 'influence_day_cap'];
begin
  select * into v from snap_0285;
  select * into v_act from actual_0285;

  -- (a) GOODS ×5, THE SAME PAIR, NOTHING ELSE IN THE CATALOGUE
  if (select count(*) from public.goods) <> v.goods_n or v.goods_n = 0 then
    raise exception '0285 self-assert FAIL: goods count % -> %', v.goods_n, (select count(*) from public.goods);
  end if;
  if (select count(*) from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'goods' and c.column_name = 'base_value'
         and c.data_type = 'numeric' and c.numeric_precision = 10 and c.numeric_scale = 2) <> 1 then
    raise exception '0285 self-assert FAIL: goods.base_value is no longer numeric(10,2)';
  end if;
  select count(*) into v_n
    from goods_0285 b join public.goods g on g.id = b.id
   where g.base_value is distinct from b.base_value * 5;
  if v_n <> 0 then
    raise exception '0285 self-assert FAIL: % good(s) whose new base_value is not exactly 5 x its as-found value', v_n;
  end if;
  if v.knob is distinct from 0.2 or public.wc_num('goods_price_level') is distinct from 1.0 then
    raise exception '0285 self-assert FAIL: goods_price_level % -> %, expected 0.2 -> 1.0',
      v.knob, public.wc_num('goods_price_level');
  end if;
  if (select count(*) from public.world_config where key = 'goods_price_level' and value = to_jsonb(1.0::numeric)) <> 1 then
    raise exception '0285 self-assert FAIL: world_config''s goods_price_level row is not the jsonb 1.0';
  end if;
  select count(*) into v_bad from public.goods
   where base_value <= 0 or base_value = 'NaN'::numeric
      or base_value = 'Infinity'::numeric or base_value = '-Infinity'::numeric;
  if v_bad <> 0 then
    raise exception '0285 self-assert FAIL: % good(s) with a non-finite or <= 0 base_value after the re-base', v_bad;
  end if;
  select min(base_value), max(base_value) into v_min, v_max from public.goods;
  if v_min is null or v_min <= 0 or v_min <> v.base_min * 5 or v_max <> v.base_max * 5 then
    raise exception '0285 self-assert FAIL: the goods extremes are wrong: min % -> % (expected %), max % -> % (expected %)',
      v.base_min, v_min, v.base_min * 5, v.base_max, v_max, v.base_max * 5;
  end if;

  -- (a) THE RECIPE INVARIANT: the knob's one reader is unchanged on every item recipe product
  select count(*), count(*) filter (where public.item_recipe_value(r.code) is distinct from r.v)
    into v_rc_n, v_rc_bad from recipe_0285 r;
  if v_rc_n < 10 or v_rc_bad <> 0
     or v_rc_n <> (select count(distinct item_code) from public.item_recipes)
     or not exists (select 1 from recipe_0285 r where r.v > 0) then
    raise exception '0285 self-assert FAIL: item recipe values: % measured, % moved of % recipe product(s)',
      v_rc_n, v_rc_bad, (select count(distinct item_code) from public.item_recipes);
  end if;

  -- (a) THE MARKET ROWS AND EVERY FUNCTION UNMOVED
  if (select count(*) from public.port_goods) <> v.port_goods_n
     or pg_temp.port_goods_md5_0285() is distinct from v.port_goods_md5 then
    raise exception '0285 self-assert FAIL: port_goods moved (% rows, md5 % -> %)',
      v.port_goods_n, v.port_goods_md5, pg_temp.port_goods_md5_0285();
  end if;
  if pg_temp.fns_n_0285() <> v.fns_n or pg_temp.fns_md5_0285() is distinct from v.fns_md5 then
    raise exception '0285 self-assert FAIL: a function in public/cmd/world/voyage moved (% -> %, md5 % -> %)',
      v.fns_n, pg_temp.fns_n_0285(), v.fns_md5, pg_temp.fns_md5_0285();
  end if;

  -- (b) EVERY HOUSE ×5, THE RESCALE ROWS ARE 4 × THE OLD PURSES
  if (select count(*) from public.players) <> v.players_n then
    raise exception '0285 self-assert FAIL: players count % -> %', v.players_n, (select count(*) from public.players);
  end if;
  select count(*) into v_n from public.players p join players_0285 b on b.id = p.id
   where p.ducats is distinct from b.ducats * 5;
  if v_n <> 0 then
    raise exception '0285 self-assert FAIL: % house(s) whose purse is not exactly 5 x its as-found value', v_n;
  end if;
  select count(*), coalesce(sum(ducats_delta), 0) into v_rc_rows, v_big
    from public.ledger where kind = 'RESCALE';
  if v_rc_rows <> (select count(*) from players_0285 where ducats <> 0) or v_big <> 4 * v.players_sum then
    raise exception '0285 self-assert FAIL: % RESCALE row(s) for % nonzero house(s), % d. credited (expected % d.)',
      v_rc_rows, (select count(*) from players_0285 where ducats <> 0), v_big, 4 * v.players_sum;
  end if;

  -- (c) EVERY RESCALED MONEY ROW ×5 (the append-only flows stay), EVERY COUNT UNCHANGED
  select count(*) into v_n from public.port_treasury p join pt_0285 b on b.port_id = p.port_id
   where p.ducats is distinct from b.ducats * 5
      or p.reserve is distinct from b.reserve * 5
      or p.invested is distinct from (case when b.invested is null then null else b.invested * 5 end);
  if v_n <> 0 or (select count(*) from public.port_treasury) <> (select count(*) from pt_0285) then
    raise exception '0285 self-assert FAIL: % city purse row(s) not exactly 5 x (ducats/reserve/invested)', v_n;
  end if;
  if (select count(*) from public.port_treasury) <> v.pt_n
     or (select coalesce(sum(ducats), 0) from public.port_treasury) <> v.pt_ducats_sum * 5
     or (select coalesce(sum(reserve), 0) from public.port_treasury) <> v.pt_reserve_sum * 5
     or (select coalesce(sum(coalesce(invested, 0)), 0) from public.port_treasury) <> v.pt_invested_sum * 5 then
    raise exception '0285 self-assert FAIL: the city purse totals are not 5 x';
  end if;

  select count(*) into v_n from public.treasury_daybook d join daybook_0285 b
    on b.port_id = d.port_id and b.game_day = d.game_day and b.kind = d.kind
   where d.ducats is distinct from b.ducats * 5;
  if v_n <> 0 or (select count(*) from public.treasury_daybook) <> (select count(*) from daybook_0285)
     or (select coalesce(sum(ducats), 0) from public.treasury_daybook) <> v.daybook_sum * 5 then
    raise exception '0285 self-assert FAIL: % treasury_daybook row(s) not exactly 5 x', v_n;
  end if;
  -- THE FLOWS ARE HISTORY AND UNTOUCHED (0122's append-only trigger refuses an UPDATE; the first
  -- prod push died here, so this file no longer writes the table at all).
  select count(*) into v_n from public.treasury_flows f join flows_0285 b on b.id = f.id
   where f.ducats is distinct from b.ducats;
  if v_n <> 0 or (select count(*) from public.treasury_flows) <> (select count(*) from flows_0285)
     or (select coalesce(sum(ducats), 0) from public.treasury_flows) <> v.flows_sum then
    raise exception '0285 self-assert FAIL: % treasury_flows row(s) moved; the flows are history', v_n;
  end if;

  -- THE TICK_CITY INVARIANT: the purse equals its day-book, after the scale as before it
  if exists (select 1 from public.port_treasury t
              where t.ducats <> coalesce((select sum(d.ducats) from public.treasury_daybook d
                                           where d.port_id = t.port_id), 0)) then
    raise exception '0285 self-assert FAIL: the tick_city purse = daybook invariant is broken after the scale';
  end if;
  -- THE LIVE CITY BALANCE: 5 × the rolled half + the flows AS FOUND (they are history and unscaled)
  select count(*) into v_n
    from public.port_treasury t join pt_0285 b on b.port_id = t.port_id
   where public.treasury_balance(t.port_id)
         <> 5 * b.ducats + coalesce((select sum(f.ducats) from flows_0285 f where f.port_id = b.port_id), 0);
  if v_n <> 0 then
    raise exception '0285 self-assert FAIL: % city live balance(s) are not exactly (5 x the rolled half + the flows)', v_n;
  end if;

  select count(*) into v_n from public.city_shares s
    join shares_0285 b on b.port_id = s.port_id and b.kind = s.kind and b.player_id = s.player_id
   where s.paid is distinct from b.paid * 5 or s.accrued is distinct from b.accrued * 5;
  if v_n <> 0 or (select count(*) from public.city_shares) <> (select count(*) from shares_0285) then
    raise exception '0285 self-assert FAIL: % city share row(s) not exactly 5 x (paid/accrued)', v_n;
  end if;

  select count(*) into v_n from public.trade_contracts t join contracts_0285 b on b.id = t.id
   where case when t.status = 'open'
              then t.mid_at_post is distinct from b.mid_at_post * 5
                or t.premium_per_unit is distinct from b.premium_per_unit * 5
                or t.premium_ducats is distinct from b.premium_ducats * 5
                or t.escrow is distinct from b.escrow * 5
              else t.mid_at_post is distinct from b.mid_at_post
                or t.premium_per_unit is distinct from b.premium_per_unit
                or t.premium_ducats is distinct from b.premium_ducats
                or t.escrow is distinct from b.escrow end;
  if v_n <> 0 or (select count(*) from public.trade_contracts) <> (select count(*) from contracts_0285) then
    raise exception '0285 self-assert FAIL: % contract row(s) wrong (open x5, history unchanged)', v_n;
  end if;
  if (select count(*) from public.trade_contracts where status = 'open') <> v.open_n
     or (select coalesce(sum(premium_ducats), 0) from public.trade_contracts where status = 'open') <> v.open_premium_sum * 5
     or (select coalesce(sum(escrow), 0) from public.trade_contracts where status = 'open') <> v.open_escrow_sum * 5 then
    raise exception '0285 self-assert FAIL: the open contracts'' premium/escrow totals are not 5 x';
  end if;

  select count(*) into v_n from public.fleet_wages w join wages_0285 b on b.fleet_id = w.fleet_id
   where w.owed is distinct from b.owed * 5 or w.visit_net is distinct from b.visit_net * 5
      or w.visit_paid is distinct from b.visit_paid * 5;
  if v_n <> 0 or (select count(*) from public.fleet_wages) <> (select count(*) from wages_0285) then
    raise exception '0285 self-assert FAIL: % fleet wage row(s) not exactly 5 x', v_n;
  end if;
  select count(*) into v_n from public.port_fee_debts d
    join debts_0285 b on b.player_id = d.player_id and b.port_id = d.port_id and b.kind = d.kind
   where d.ducats is distinct from b.ducats * 5;
  if v_n <> 0 or (select count(*) from public.port_fee_debts) <> (select count(*) from debts_0285) then
    raise exception '0285 self-assert FAIL: % port fee debt row(s) not exactly 5 x', v_n;
  end if;
  select count(*) into v_n from public.insured_voyages i join insured_0285 b on b.voyage_id = i.voyage_id
   where i.value is distinct from b.value * 5 or i.price is distinct from b.price * 5
      or i.lost_value is distinct from b.lost_value * 5 or i.paid is distinct from b.paid * 5
      or i.short is distinct from b.short * 5;
  if v_n <> 0 or (select count(*) from public.insured_voyages) <> (select count(*) from insured_0285) then
    raise exception '0285 self-assert FAIL: % insured policy row(s) not exactly 5 x', v_n;
  end if;

  select count(*) into v_n from public.hull_recipes h join want_hull_0285 w on w.class_code = h.class_code
   where h.ducats is distinct from w.ducats;
  if v_n <> 0 or (select count(*) from public.hull_recipes) <> (select count(*) from want_hull_0285) then
    raise exception '0285 self-assert FAIL: % hull recipe row(s) not equal to the re-derived data value', v_n;
  end if;
  select count(*) into v_n from public.ship_classes c join want_class_0285 w on w.code = c.code
   where c.build_cost is distinct from w.build_cost;
  if v_n <> 0 or (select count(*) from public.ship_classes) <> (select count(*) from want_class_0285) then
    raise exception '0285 self-assert FAIL: % ship class row(s) not equal to the re-derived data value', v_n;
  end if;
  select count(*) into v_n from public.officers o join officer_0285 b on b.id = o.id
   where o.wage_ducats is distinct from b.wage_ducats * 5;
  if v_n <> 0 or (select count(*) from public.officers) <> (select count(*) from officer_0285) then
    raise exception '0285 self-assert FAIL: % officer row(s) not exactly 5 x', v_n;
  end if;
  select count(*) into v_n from public.npc_houses h join npc_house_0285 b on b.player_id = h.player_id
   where h.capital is distinct from b.capital * 5;
  if v_n <> 0 or (select count(*) from public.npc_houses) <> (select count(*) from npc_house_0285) then
    raise exception '0285 self-assert FAIL: % merchant capital row(s) not exactly 5 x', v_n;
  end if;

  select count(*) into v_n from public.ships s join basis_0285 b on b.id = s.id
   where s.cargo_basis is distinct from (select jsonb_object_agg(e.key,
           case when jsonb_typeof(e.value) = 'number'
                then to_jsonb((e.value #>> '{}')::numeric * 5) else e.value end)
           from jsonb_each(b.cargo_basis) e);
  if v_n <> 0 or (select count(*) from public.ships where cargo_basis <> '{}'::jsonb and cargo_basis is not null) <> (select count(*) from basis_0285) then
    raise exception '0285 self-assert FAIL: % cargo basis row(s) not exactly 5 x', v_n;
  end if;
  select count(*) into v_n from public.player_storage s
    join storage_0285 b on b.player_id = s.player_id and b.port_id = s.port_id and b.good_id = s.good_id
   where s.basis is distinct from b.basis * 5;
  if v_n <> 0 or (select count(*) from public.player_storage where basis is not null) <> (select count(*) from storage_0285) then
    raise exception '0285 self-assert FAIL: % storage basis row(s) not exactly 5 x', v_n;
  end if;
  select count(*) into v_n from public.standing_route_lines l
    join route_0285 b on b.route_id = l.route_id and b.stop_ord = l.stop_ord and b.ord = l.ord
   where l.price_limit is distinct from b.price_limit * 5;
  if v_n <> 0 or (select count(*) from public.standing_route_lines where price_limit is not null) <> (select count(*) from route_0285) then
    raise exception '0285 self-assert FAIL: % route line limit(s) not exactly 5 x', v_n;
  end if;
  select count(*) into v_n from public.orders o join orders_0285 b on b.id = o.id
   where (o.args->>'limit')::numeric is distinct from (b.args->>'limit')::numeric * 5;
  if v_n <> 0 or (select count(*) from public.orders where status in ('pending','active') and jsonb_typeof(args->'limit') = 'number') <> (select count(*) from orders_0285) then
    raise exception '0285 self-assert FAIL: % open order limit(s) not exactly 5 x', v_n;
  end if;

  select count(*) into v_n from public.price_history h
    join ph_0285 b on b.port_id = h.port_id and b.good_id = h.good_id and b.slot = h.slot
   where h.mid is distinct from round(b.mid * 5, 4)
      or h.ask is distinct from (case when b.ask is null then null else round(b.ask * 5, 2) end)
      or h.bid is distinct from (case when b.bid is null then null else round(b.bid * 5, 2) end);
  if v_n <> 0 or (select count(*) from public.price_history) <> (select count(*) from ph_0285) then
    raise exception '0285 self-assert FAIL: % price_history row(s) not exactly 5 x (mid/ask/bid)', v_n;
  end if;

  -- (d) THE 21 KNOBS ×5, EVERY OTHER KNOB UNCHANGED, THE SWITCHES UNTOUCHED
  select count(*) into v_n from public.world_config c join knobs_0285 b using (key)
   where (c.key = any (v_scaled) and c.value is distinct from to_jsonb((b.value #>> '{}')::numeric * 5))
      or (c.key = 'goods_price_level' and c.value is distinct from to_jsonb(1.0::numeric))
      or (c.key <> 'goods_price_level' and c.key <> 'economy_closed_total'
          and not (c.key = any (v_scaled)) and c.value is distinct from b.value)
      or (c.key = 'economy_closed_total'
          and jsonb_typeof(b.value) = 'number'
          and c.value is distinct from to_jsonb((b.value #>> '{}')::bigint * 5))
      or (c.key = 'economy_closed_total' and jsonb_typeof(b.value) <> 'number' and c.value is distinct from b.value);
  if v_n <> 0 then
    raise exception '0285 self-assert FAIL: % world_config row(s) are not the intended x5 (or unchanged rate)', v_n;
  end if;
  if (select value from public.world_config where key = 'economy_closed') is distinct from v.econ_closed
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from v.city_lit then
    raise exception '0285 self-assert FAIL: an owner switch moved';
  end if;

  -- (e) THE LIVE STATS: THE ACTUAL MONEY AFTER THE RE-BASE (the flows stay unscaled)
  select world.stats_now() into v_now;
  v_np   := 5 * (select players_np_sum from snap_0285);
  v_npc  := 5 * (select players_npc_sum from snap_0285);
  v_city := 5 * v_act.cities - 4 * (select flows_sum from snap_0285);
  v_set  := 5 * v_act.set_aside;
  if (v_now->>'players')::bigint is distinct from v_np
     or (v_now->>'merchants')::bigint is distinct from v_npc
     or (v_now->>'cities')::bigint is distinct from v_city
     or (v_now->>'set_aside')::bigint is distinct from v_set
     or (v_now->>'total')::bigint is distinct from v_np + v_npc + v_city + v_set then
    raise exception '0285 self-assert FAIL: the live Stats are not the actual money after the re-base: % vs %/%/%/%',
      v_now, v_np, v_npc, v_city, v_set;
  end if;

  -- (f) THE WATCH: THE COUNTS AND THE SWING ARE KEPT; THE THIN THRESHOLD MOVES ×5
  v_watch := public.stats_watch(now());
  if (v_watch->>'under_thin') is distinct from (v.watch->>'under_thin')
     or (v_watch->>'under_reserve') is distinct from (v.watch->>'under_reserve')
     or (v_watch->>'broke') is distinct from (v.watch->>'broke')
     or (v_watch->>'swing_p50') is distinct from (v.watch->>'swing_p50')
     or (v_watch->>'swing_p90') is distinct from (v.watch->>'swing_p90')
     or (v_watch->>'swing_steps') is distinct from (v.watch->>'swing_steps')
     or (v_watch->>'thin')::numeric is distinct from (v.watch->>'thin')::numeric * 5 then
    raise exception '0285 self-assert FAIL: the economy watch moved: before %, after %', v.watch, v_watch;
  end if;

  -- (g) THE MARKET PRICES FROM THE STORED COLUMN — a rolled-back probe on one harbour good
  select pg.port_id, pg.good_id, p.code, g.code, g.base_value
    into v_port, v_good, v_pcode, v_gcode, v_base
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
    join public.goods g on g.id = pg.good_id
   where pg.stock >= 100
   order by g.base_value desc, p.code, g.code
   limit 1;
  if v_port is null then
    raise exception '0285 self-assert FAIL: no harbour good with stock >= 100 to probe';
  end if;
  select * into v_b from world.price(v_port, v_good);
  select * into v_qb from world.quote(v_port, v_good, 10, 'buy', null, null);
  if v_b.mid is null or v_b.ask is null or v_b.bid is null
     or v_b.mid <= 0 or v_b.ask <= 0 or v_b.bid <= 0
     or v_qb.avg_price is null or v_qb.avg_price <= 0 or v_qb.total is null or v_qb.total <= 0 then
    raise exception '0285 self-assert FAIL: the probe pair %/% has no live quote', v_pcode, v_gcode;
  end if;
  begin
    update public.goods set base_value = round(base_value * 5, 2) where id = v_good;
    select * into v_s from world.price(v_port, v_good);
    select * into v_qs from world.quote(v_port, v_good, 10, 'buy', null, null);
    raise exception using errcode = 'ZX285', message = 'probe ok';
  exception when sqlstate 'ZX285' then
    null;
  end;
  select base_value into v_nowbase from public.goods where id = v_good;
  if v_nowbase is distinct from v_base then
    raise exception '0285 self-assert FAIL: the rolled-back probe did not restore %/% base_value: % -> %',
      v_pcode, v_gcode, v_base, v_nowbase;
  end if;
  v_mid_x := v_s.mid / v_b.mid;
  v_ask_x := v_s.ask / v_b.ask;
  v_bid_x := v_s.bid / v_b.bid;
  v_avg_x := v_qs.avg_price / v_qb.avg_price;
  v_tot_x := v_qs.total::numeric / v_qb.total::numeric;
  if v_mid_x not between 4.9 and 5.1 or v_ask_x not between 4.9 and 5.1
     or v_bid_x not between 4.9 and 5.1 or v_avg_x not between 4.9 and 5.1
     or v_tot_x not between 4.9 and 5.1 then
    raise exception '0285 self-assert FAIL: %/% scaled x5 moved mid/ask/bid/avg_price/total by %/%/%/%/%, not ~5',
      v_pcode, v_gcode, v_mid_x, v_ask_x, v_bid_x, v_avg_x, v_tot_x;
  end if;

  -- (h) THE RECEIPT
  v_gmd5 := pg_temp.goods_md5_0285();
  raise notice '0285 self-assert ok: THE WHOLE WORLD IS RE-BASED x5, SO EVERY RATIO IS KEPT. goods % (md5 % -> %), every base_value exactly x5; goods_price_level % -> %; % item recipe products unchanged; % house(s) / % d. -> % d. (players % d. + merchants % d.), every purse x5, % RESCALE row(s) = % d.; city live % d. -> % d. (port_treasury % d. as found x5 + flows % d. as found; daybook % d. as found x5), reserve % d., invested % d., % city share(s) paid % d. / accrued % d., % open contract(s) premium % d. / escrow % d.; % wage row(s) % d., % fee debt(s) % d., % policy(ies) value % d.; % hull(s) / % class(es) (their re-derived data values) / % officer(s) / % merchant capital(s) x5; % cargo basis, % storage basis, % route limit, % order limit; % price point(s) x5; 21 money knobs x5 and every rate unchanged; stats watch under_thin % / under_reserve % / broke % / swing %/% kept, thin % -> %; live Stats = the actual money after the re-base (total % d.); history books not re-scaled; port_goods % rows md5 % unchanged; % functions md5 % unchanged; rolled-back probe %/% base % -> % moved mid/ask/bid/avg_price/total by %/%/%/%/%, rollback restored %.',
    v.goods_n, v.goods_md5, v_gmd5,
    v.knob, public.wc_num('goods_price_level'),
    v_rc_n,
    v.players_n, v.players_sum, (select coalesce(sum(ducats), 0) from public.players),
    v.players_np_sum, v.players_npc_sum,
    v_rc_rows, v_big,
    v_act.cities, (v_now->>'cities')::bigint, v.pt_ducats_sum, v.flows_sum, v.daybook_sum,
    v.pt_reserve_sum, v.pt_invested_sum,
    v.shares_n, v.shares_paid_sum, v.shares_accrued_sum,
    v.open_n, v.open_premium_sum, v.open_escrow_sum,
    v.wages_n, v.wages_owed_sum, v.debts_n, v.debts_sum, v.insured_n, v.insured_value_sum,
    v.hull_n, v.class_n, v.officer_n, v.npc_house_n,
    v.basis_n, (select count(*) from storage_0285), v.route_n, v.order_n,
    v.ph_n,
    (v_watch->>'under_thin'), (v_watch->>'under_reserve'), (v_watch->>'broke'),
    (v_watch->>'swing_p50'), (v_watch->>'swing_p90'), (v_watch->>'thin'), v.watch->>'thin',
    (v_now->>'total')::bigint,
    v.port_goods_n, v.port_goods_md5,
    v.fns_n, v.fns_md5,
    v_pcode, v_gcode, v_base, round(v_base * 5, 2),
    round(v_mid_x, 6), round(v_ask_x, 6), round(v_bid_x, 6), round(v_avg_x, 6), round(v_tot_x, 6),
    v_nowbase;
end $$;
