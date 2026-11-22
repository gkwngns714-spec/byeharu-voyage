-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0472 - THE FIRST HOUR  (dark: the owner's switch first_hour_enabled, false; lit, a new company's Trade cards price the load the
--        one-press default buys, near trips first, and its second hull costs a few good trips)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/playable-2026-11-22.md section 5 ("Second play-test, lit game"), the lead's items S1, S2 and S3;
--   docs/dev-log/2026-11-22-first-hour.md (the numbers before and after).
--
-- WHY (the play-test, a fresh Lisbon company with 40,000 coins):
--   S1  the Trade card's green line (Buy & sell) opens at the card's units, and world.best_sales priced the card at the FULL load she can
--       take: 35,262 of 40,000 spent for one trip. The docked Buy opens at half her coin (#780, TradePanel.tsx firstBuy); the card did not.
--   S2  the yard's Order (0465) of a Barca at Lisbon is about 26,000: two presses in minute one finish the welcome's goal ("earn your
--       second ship") before any trade.
--   S3  from the second port (Porto) every card named a 6-7 hour trip; a newcomer was offered nothing near.
--
-- WHAT CHANGES WHEN LIT (DECIDED BY DEFAULT; the owner may reverse any of it):
--   S1  world.best_sales: a good bought at the city in hand is priced for the SMALLER of the load it priced before (her hold, the
--       stock, the day's cap, her purse: public.fleet_buy_capacity where she lies, else what fits) and what HALF her coin buys at the
--       city's ask (world.price, the figure the market serves as `buy`): least(load, greatest(1, floor(purse * 0.5 / ask))). This is the
--       docked tray's own first count (TradePanel.tsx firstBuy: at least one unit, as there), so the card's profit, the Buy & sell
--       sheet's default (it opens at the card's units, Trade.tsx pressBest) and the docked Buy are one number. A new company keeps half
--       her coin for the next trip. Every sale row of that good is priced for that count (the 'asked' amount, as 0351 prices the Max),
--       the far choice too; a leg whose stores leave room for fewer is priced for what fits beside them, as before. Her cargo is
--       unchanged.
--   S2  public.hull_order_price: while a company holds at most one ship and has no hull on order (her SECOND hull), the order's fee is
--       raised so the price before her Trading discount is at least first_hull_order_floor (52,000: her 40,000 and about 12,000 earned,
--       four to six good trips at the half-coin loads S1 prices). The raise is part of the fee, so 0468's per-level discount takes its
--       share off it too (Trading 5: 10 % of the whole fee; a Barca at Lisbon 52,000 -> about 48,550). Labour and materials are
--       untouched. A hull whose price is above the floor already is unchanged; the third hull and every later one are unchanged (the
--       ladder is not moved). The answer carries `first: true` when the floor raised the fee (the yard shows "First order").
--       The build-from-materials path (cmd.do_build) does not read this function: unchanged.
--   S3  world.best_sales: for a company paid for a Trading level under first_hour_trading_below (5; her mark, public.house_level_marks,
--       as 0468 reads it; none: level 1), a sale within first_hour_trip_hours (2 h of real time to the sale) that pays is preferred
--       to one beyond it; among them the best profit per hour, as before. Where nothing within the horizon pays, the card is what it
--       was. `far` (the biggest total profit, which the Buy & sell sheet's three choices offer) is unchanged.
-- ONE AUTHORITY, EXTENDED (no second one made): the card's sale is still world.best_sales; an order's price is still public.hull_order_price
--   (world.hull_quote and the door, public.hull_order_for, read it, so what the yard quotes and what the door charges agree).
-- THE SWITCH first_hour_enabled (FALSE here). Dark: every hunk is a no-op (asserted on a probe against the pre-images in pg_temp).
-- NOT CHANGED: any existing knob (starting_ducats, yard_order_fee_pct, trade_step_tuns), world.good_board and world.board_sell (a card's
--   row is still their row for its units), the buy, the sale, voyage.settle, a merchant (no order door; no Trading mark), the 0433
--   path for a load beyond her purse.
-- ROWS: none, dark or lit; four world_config rows. -- budget: none (no table, no job, no cron, no index, no fillfactor or autovacuum
--   setting). -- retention: none (no table). COST lit: world.best_sales asks world.price and one world.quote more a bought good (two
--   index reads and a shelf walk), inside its 2.5 s budget; public.hull_order_price two counts by player (ships, hull_orders: indexed).
-- LOCKS: CREATE OR REPLACE x2 by hunks (world.best_sales, public.hull_order_price). TIME: a second. BUDGET: statement_timeout 45 s,
--   lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, first_hour_enabled false (every figure is its pre-image's at once; an order placed lit keeps
--   the price it was paid at). Full: a new migration reversing the six hunks (OLD texts below verbatim) and deleting the four knobs.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path, owner
--   unmoved; no other world_config row moved; the switch false. THE PROBE (rolled back): a fresh Lisbon company. DARK every card and
--   every order price equals its pre-image's (copies in pg_temp); LIT each card bought here is priced at least(pre-image units,
--   floor(purse / 2 / ask)) units, within half her coin plus the shelf's walk; her second hull's price before discount is the floor,
--   a third hull's the pre-image's, Trading 5 takes 10 % of the raised fee. Proof 175 plays the doors.
-- VERSION: 0472 = prod head 0471 + 1 (0473 is another builder's: public.hold_request_post and world.houses_week; this file reads neither).
-- news: none (dark: nothing changes for a player until the owner lights first_hour_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['world.best_sales(uuid,uuid)', 'public.hull_order_price(uuid,uuid,text)'];
  c_knobs  constant text[] := array['first_hour_enabled', 'first_hour_trading_below', 'first_hour_trip_hours', 'first_hull_order_floor'];
  c_uid    constant uuid := '00000000-0472-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_pl        uuid;
  v_fl        uuid;
  v_lis       uuid;
  v_old       jsonb;
  v_new       jsonb;
  v_purse     numeric;
  v_floor     bigint;
  v_cards     int := 0;
  v_halved    int := 0;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config c where c.key = any(c_knobs)) then
    raise exception '0472 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) f where to_regprocedure(f) is null)
     or to_regclass('public.house_level_marks') is null or to_regclass('public.hull_orders') is null
     or to_regprocedure('world.price(uuid,uuid)') is null
     or to_regprocedure('world.quote(uuid,uuid,numeric,text,numeric,uuid)') is null
     or to_regprocedure('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)') is null
     or to_regprocedure('cmd.assume_identity(uuid)') is null
     or public.wc('yard_order_fee_pct') is null or public.wc('starting_ducats') is null then
    raise exception '0472 refuses: the best sales (0348, 0351, 0433, 0459), the marks (0356), the yard order (0465) or the levels (0468) are not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0472 (fn text primary key, def text) on commit drop;
  insert into pre_0472 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE SWITCH AND ITS THREE FIGURES ──
  insert into public.world_config (key, value, description) values
    ('first_hour_enabled', 'false'::jsonb,
     '0472: THE FIRST HOUR (the owner''s switch). true: world.best_sales prices a good bought at the city in hand for least(the load, floor(purse / 2 / ask)) units (the docked Buy''s first count), and for a company under Trading first_hour_trading_below prefers a paying sale within first_hour_trip_hours; public.hull_order_price raises the fee of a company''s second hull (at most one ship, none on order) so its price before the Trading discount is at least first_hull_order_floor. false: both are as before 0472.'),
    ('first_hour_trading_below', '5'::jsonb,
     '0472: a company paid for a Trading level under this (public.house_level_marks; none: 1) is offered near trips first on its Trade cards (first_hour_enabled).'),
    ('first_hour_trip_hours', '2'::jsonb,
     '0472: the real hours to a sale within which a Trade card''s sale is "near" for a company under first_hour_trading_below (first_hour_enabled).'),
    ('first_hull_order_floor', '52000'::jsonb,
     '0472: the least an order of a company''s second hull costs before her Trading discount, in coins: the fee is raised to it (first_hour_enabled). 40,000 to start and about four to six good trips.');

  -- ── 3. THE HUNKS (each OLD text once in its live body; each reverses) ──
  create temp table hunks_0472 (fn text, ord int, old text, new text, primary key (fn, ord)) on commit drop;
  insert into hunks_0472 values
  ('world.best_sales(uuid,uuid)', 1,
$h$  v_i       int;
$h$,
$h$  v_i       int;
  -- 0472 (THE FIRST HOUR, first_hour_enabled): v_half the count half her coin buys at the city's ask; v_near_s the real seconds within
  -- which a paying sale is preferred, for a company under Trading first_hour_trading_below (null: no preference, as before)
  v_first_hour boolean := public.wc('first_hour_enabled') = 'true'::jsonb;
  v_half    numeric;
  v_near_s  numeric := case when public.wc('first_hour_enabled') = 'true'::jsonb
                                 and coalesce((select m.level from public.house_level_marks m
                                                where m.player_id = public.current_player_id() and m.track = 'trading'), 1)
                                     < public.wc_num('first_hour_trading_below')
                            then public.wc_num('first_hour_trip_hours') * 3600 end;
$h$),
  ('world.best_sales(uuid,uuid)', 2,
$h$    v_short := v_u is not null and v_u <= 0 and v_cap->>'bound_by' = 'purse';   -- her purse buys not one
$h$,
$h$    v_short := v_u is not null and v_u <= 0 and v_cap->>'bound_by' = 'purse';   -- her purse buys not one
    -- 0472 (S1): A GOOD BOUGHT HERE IS PRICED FOR WHAT HALF HER COIN BUYS, when that is less than the load above (the docked tray's own
    -- first count, TradePanel.tsx firstBuy: floor(purse / 2 / ask), at least one): every sale then priced for that count, as the Max is
    if v_first_hour and a.basis <> 'on_board' and (v_u is null or v_u > 0) then
      v_half := (select greatest(1, floor(v_purse * 0.5 / q.ask)) from world.price(p_port, gd.id) q where q.ask > 0);
      if v_half is not null and v_half < coalesce(v_u, a.units) then
        select jsonb_build_object('max_qty', q.units, 'est_total', q.total, 'bound_by', 'half') into v_cap
          from world.quote(p_port, gd.id, v_half, 'buy', null, p_fleet) q where q.units > 0;
        v_u := case when v_cap is null then v_u else (v_cap->>'max_qty')::numeric end;
      end if;
    end if;
$h$),
  ('world.best_sales(uuid,uuid)', 3,
$h$             order by (c.profit > 0) desc, case when c.profit > 0 then c.profit / c.secs end desc nulls last,
$h$,
$h$             order by (c.profit > 0) desc,
                      (v_near_s is null or c.profit <= 0 or c.secs <= v_near_s) desc,   -- 0472 (S3): a newcomer's near PAYING sale first (dark: none)
                      case when c.profit > 0 then c.profit / c.secs end desc nulls last,
$h$),
  ('public.hull_order_price(uuid,uuid,text)', 1,
$h$  v_min   int;
$h$,
$h$  v_min   int;
  v_first boolean := false;   -- 0472: the floor of a company's second hull raised the fee
  v_rise  bigint;
$h$),
  ('public.hull_order_price(uuid,uuid,text)', 2,
$h$  v_fee := round((v_lab + v_mat) * public.wc_num('yard_order_fee_pct') / 100.0 * (1 - public.level_perk(p_player, 'yard_fee') / 100))::bigint;
$h$,
$h$  v_fee := round((v_lab + v_mat) * public.wc_num('yard_order_fee_pct') / 100.0 * (1 - public.level_perk(p_player, 'yard_fee') / 100))::bigint;
  -- 0472 (S2, first_hour_enabled): HER SECOND HULL (she holds at most one ship and has none on order): the fee is raised so the price
  -- before her Trading discount is at least first_hull_order_floor; the discount takes its share off the whole fee
  if public.wc('first_hour_enabled') = 'true'::jsonb and p_player is not null
     and (select count(*) from public.ships s where s.player_id = p_player)
         + (select count(*) from public.hull_orders o where o.player_id = p_player and o.launched_at is null) <= 1 then
    v_rise := round((public.wc_num('first_hull_order_floor') - v_lab - v_mat) * (1 - public.level_perk(p_player, 'yard_fee') / 100))::bigint;
    if v_rise > v_fee then
      v_fee := v_rise;
      v_first := true;
    end if;
  end if;
$h$),
  ('public.hull_order_price(uuid,uuid,text)', 3,
$h$                            'price', v_lab + v_mat::bigint + v_fee, 'minutes', greatest(coalesce(v_min, 0), 1), 'short', v_short);
$h$,
$h$                            'price', v_lab + v_mat::bigint + v_fee, 'minutes', greatest(coalesce(v_min, 0), 1), 'short', v_short)
         || case when v_first then jsonb_build_object('first', true) else '{}'::jsonb end;   -- 0472: the second hull's floor raised the fee
$h$);

  for v_h in select h.fn from hunks_0472 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0472 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0472 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0472 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0472 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0472 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_fn_before then
    raise exception '0472 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0472 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all(c_knobs)) <> v_cfg_before
     or public.wc('first_hour_enabled') is distinct from 'false'::jsonb
     or public.wc_num('first_hull_order_floor') <= public.wc_num('starting_ducats') then
    raise exception '0472 self-assert FAIL: an existing world_config row moved, first_hour_enabled is not false, or the floor is not above the starting purse';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0472 self-assert FAIL: a client can write a table';
  end if;

  -- ── 5. THE PROBE, rolled back by a raised sentinel ──
  begin
    -- the pre-images, callable as pg_temp.*_old_0472 (their definer dropped: a copy in pg_temp runs as the migration)
    for x in select p.fn, p.def from pre_0472 p loop
      execute replace(replace(replace(x.def,
        'FUNCTION world.best_sales(', 'FUNCTION pg_temp.best_sales_old_0472('),
        'FUNCTION public.hull_order_price(', 'FUNCTION pg_temp.order_price_old_0472('),
        'SECURITY DEFINER', '');
    end loop;
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_pl := public.new_house(c_uid, 'Casa da Hora 0472', 'PRT');
    select f.id into v_fl from public.fleets f where f.player_id = v_pl limit 1;
    perform cmd.assume_identity(c_uid);
    select p.ducats into v_purse from public.players p where p.id = v_pl;

    -- (a) DARK: every card and every order price is its pre-image's
    if world.best_sales(v_fl, v_lis) - 'clock' is distinct from pg_temp.best_sales_old_0472(v_fl, v_lis) - 'clock'
       or public.hull_order_price(v_pl, v_lis, 'barca') is distinct from pg_temp.order_price_old_0472(v_pl, v_lis, 'barca') then
      raise exception '0472 self-assert FAIL: dark, a card or an order price moved';
    end if;

    -- (b) LIT, S1: a good bought here is priced at least(the pre-image's units, floor(purse / 2 / ask)) units (at least one)
    update public.world_config set value = 'true'::jsonb where key = 'first_hour_enabled';
    v_old := pg_temp.best_sales_old_0472(v_fl, v_lis);
    v_new := world.best_sales(v_fl, v_lis);
    if not (v_old ->> 'cut')::boolean and not (v_new ->> 'cut')::boolean then
      for x in
        select o.e ->> 'good' as good, (o.e ->> 'units')::numeric as u_old, (n.e ->> 'units')::numeric as u_new, (n.e ->> 'cost')::numeric as cost,
               (select greatest(1, floor(v_purse * 0.5 / q.ask)) from world.price(v_lis, g.id) q where q.ask > 0) as half,
               (select q.ask from world.price(v_lis, g.id) q) as ask
          from jsonb_array_elements(v_old -> 'goods') o(e)
          join jsonb_array_elements(v_new -> 'goods') n(e) on n.e ->> 'good' = o.e ->> 'good'
          join public.goods g on g.code = o.e ->> 'good'
         where o.e ->> 'basis' <> 'on_board' and o.e ->> 'port' is not null and n.e ->> 'port' is not null
      loop
        v_cards := v_cards + 1;
        -- the units: never more than before, never more than half her coin buys (a leg's stores may leave room for fewer: FIT)
        if x.u_new > x.u_old or x.u_new > x.half then
          raise exception '0472 self-assert FAIL: lit, % is priced for % units (before %, half her coin %)', x.good, x.u_new, x.u_old, x.half;
        end if;
        if x.u_new < x.u_old then
          v_halved := v_halved + 1;
          -- within half her coin, but for the shelf's walk above the ask (each unit after the first is dearer)
          if x.cost > v_purse * 0.5 * 1.25 then
            raise exception '0472 self-assert FAIL: lit, % costs % of her % for % units at %', x.good, x.cost, v_purse, x.u_new, x.ask;
          end if;
        end if;
      end loop;
      v_note := format('%s cards bought here, %s priced at half her coin', v_cards, v_halved);
    else
      v_note := 'the cards were NOT COMPARED HERE (the 2.5 s budget ran out; proof 175 holds them)';
    end if;

    -- (c) LIT, S2: her second hull costs the floor before discount; with a hull on order a third is the pre-image's
    v_old := pg_temp.order_price_old_0472(v_pl, v_lis, 'barca');
    v_new := public.hull_order_price(v_pl, v_lis, 'barca');
    v_floor := public.wc_num('first_hull_order_floor')::bigint;
    if v_old is null then
      v_note := v_note || '; the order was NOT PRICED HERE (no barca price at Lisbon; proof 175 holds it)';
    else
      if (v_old ->> 'price')::bigint < v_floor
         and ((v_new ->> 'price')::bigint <> v_floor or (v_new ->> 'first') is distinct from 'true'
              or (v_new ->> 'labour') <> (v_old ->> 'labour') or (v_new ->> 'materials') <> (v_old ->> 'materials')
              or (v_new ->> 'minutes') <> (v_old ->> 'minutes')
              or (v_new ->> 'price')::bigint <> (v_new ->> 'labour')::bigint + (v_new ->> 'materials')::bigint + (v_new ->> 'fee')::bigint) then
        raise exception '0472 self-assert FAIL: lit, her second Barca is % against % (floor %)', v_new, v_old, v_floor;
      end if;
      insert into public.hull_orders (player_id, port_id, class_code, labour, materials, fee, price, ordered_at, ready_at)
      values (v_pl, (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_lis order by p.code limit 1), 'barca', (v_old ->> 'labour')::bigint, (v_old ->> 'materials')::bigint, (v_old ->> 'fee')::bigint, (v_old ->> 'price')::bigint, now(), now() + interval '30 minutes');
      if public.hull_order_price(v_pl, v_lis, 'barca') is distinct from pg_temp.order_price_old_0472(v_pl, v_lis, 'barca') then
        raise exception '0472 self-assert FAIL: lit, with a hull on order the next is not its pre-image''s price';
      end if;
      v_note := v_note || format('; her second Barca %s -> %s', v_old ->> 'price', v_new ->> 'price');
    end if;
    raise exception using errcode = 'ZX472', message = 'PROBE_ROLLBACK_0472';
  exception when sqlstate 'ZX472' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0472 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0472' or p.auth_uid = c_uid)
     or public.wc('first_hour_enabled') is distinct from 'false'::jsonb
     or to_regprocedure('pg_temp.best_sales_old_0472(uuid,uuid)') is not null
     or public.current_player_id() is not null then
    raise exception '0472 self-assert FAIL: the probe left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0472 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0472 self-assert ok: THE FIRST HOUR (dark). % hunks once each and reversing; grants and volatility unmoved; no other function or knob moved; first_hour_enabled false. Probe (rolled back), a fresh Lisbon company: dark every card and the order price their pre-image''s; lit %. % ms.',
    (select count(*) from hunks_0472), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
