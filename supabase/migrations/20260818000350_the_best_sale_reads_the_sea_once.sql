-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0350 — THE BEST SALE READS THE SEA ONCE: world.best_sales answers the same, in about half the time. No table, no knob, no switch, no row, no job. It changes no trade and no figure.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY. world.best_sales (0348) is slow on prod: the health read shows a mean of ~2.6 s and a max of ~4.4 s over 68 calls, against the 2.5 s budget inside it (past it a card gets no line).
-- The queue named the fix "a precomputed dearest-buyers list". MEASURED FIRST (docs/dev-log/2026-11-11-dearest-buyers.md): ranking the buyers by price is about a fifth of a call, and no single
-- part is most of it. A call asks world.board_sell once per good, and every one of those asks again for things that do not depend on the good:
--   * world.mid_price once per harbour (249 calls a good, each two nested plpgsql calls, five statements): 30 % of a board_sell;
--   * her passage to every harbour (the passages parsed twice), public.supply_needs for every leg, and a 249 x 81 join to put them together: another 30 %;
--   * the 15 sell quotes and the buy quote (world.quote): 30 %. These are the figures themselves and are NOT touched.
-- A PRECOMPUTED LIST IS THE WRONG FIX, and this file does not build one: a stored list is stale the moment a stock moves (every trade, every merchant, every drift slot), and a stale ranking
-- prices a different set of cities than world.good_board does, so a card could name a city the trade tray does not price — unless every trade refreshes it (the price hot path) or the beat does.
-- The same cost goes, exactly, without storing anything:
--   world.good_mids(good)          NEW, server only. Every market row of a good with its price, in ONE statement: world.mid_from_terms (the one price expression) on the terms world.mid_terms
--                                  reads. It is world.mid_price(port, good, stock) for every row, to the digit (asserted below). This is the dearest-buyers list, read live.
--   world.board_legs(fleet, ctx)   NEW, server only. Her passage to every harbour and what its longest leg asks of her stores: world.board_sell's own reach / reach2 / needs and the leg columns
--                                  of its cand, MOVED there whole (not copied). It reads the fleet, where she sails from, the buy city and whether the good is her cargo; nothing of the good.
--   world.board_sell               RE-CUT (4 hunks): its cand reads the prices from world.good_mids and the legs from world.board_legs — handed over by the caller as `legs` when it has them,
--                                  else asked here. Everything after (the ranking, the quotes, the tax, the wages, the answer) is unmoved.
--   world.best_sales               RE-CUT (2 hunks): asks world.board_legs ONCE for the goods bought at p_port and once for her cargo, and hands them to every world.board_sell.
-- ONE AUTHORITY, STILL. world.good_board is not edited: it calls world.board_sell as before, which now asks world.board_legs itself. world.best_sales and world.good_board share the same
-- world.board_sell, world.board_legs and world.good_mids; the served profit on a card is still world.good_board's row for the same units (asserted below, as 0348 asserted it).
-- THE SAME ANSWER (asserted in one statement each, on a probe house that is rolled back): world.good_board = its answer before this file byte for byte (no city, her own city, an amount, another
-- city, her cargo); world.best_sales = its answer before this file (her own city, another city, with cargo aboard); world.good_mids = world.mid_price for every harbour of the probe's goods.
-- NOT TOUCHED: world.good_board, world.quote, world.mid_price, world.mid_terms, public.supply_needs, voyage.reach_passage, the 2.5 s budget, every table, knob, switch, job and client file.
-- COST OF KEEPING IT TRUE: none. Nothing is stored, so nothing is refreshed: the price hot path (cmd.do_buy / cmd.do_sell, the merchants) and the beat do not read or write anything new.
-- ROLLBACK (forward): a new migration reversing the 6 hunks (each OLD text is here verbatim) and dropping world.good_mids and world.board_legs; nothing else depends on them.
-- SELF-ASSERT: the catalog, then a probe house of its own rolled-back rows. BUDGET: ONE DO block, statement_timeout 90 s, lock_timeout 5 s; it fails above 45 s.
-- news: none
-- VERSION: 0350 - prod head 0349 (2026-11-11).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_def         text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_rel_before  text;
  v_job_before  text;
  h             record;
  rf            record;
  v_lived       boolean := false;
  v_pl          uuid;
  v_fl          uuid;
  v_home        uuid;
  v_hcode       text;
  v_near        uuid;
  v_g1          uuid;
  v_g1code      text;
  v_bad         text;
  v_cnt         int;
  v_rows        int;
  v_old         jsonb;
  v_new         jsonb;
  v_ms_old      numeric;
  v_ms_new      numeric;
  v_sum_old     numeric := 0;
  v_sum_new     numeric := 0;
  v_pairs       int := 0;
  v_k           int;
  r_m text; r_a text; r_b text; r_c text; r_d text; r_l text; r_e text;
  c_uid  constant uuid := '00000000-0350-4000-8000-000000000001';
  c_recut constant text[] := array['world.board_sell(uuid,uuid,jsonb)', 'world.best_sales(uuid,uuid)'];
  c_new_fns constant text[] := array['world.good_mids(uuid)', 'world.board_legs(uuid,jsonb)'];
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_new_fns) f where to_regprocedure(f) is not null) then
    raise exception '0350 refuses: something of it is already in this world';
  end if;
  if exists (select 1 from unnest(c_recut || array['world.good_board(uuid,uuid,uuid,numeric)', 'world.board_passages(uuid,uuid,uuid,numeric)', 'world.board_origin(uuid)',
                                                   'world.board_amount(uuid,uuid,numeric)', 'world.mid_price(uuid,uuid,numeric)', 'world.mid_terms(uuid,uuid)',
                                                   'public.supply_needs(uuid,numeric[])', 'cmd.assume_identity(uuid)']) f
              where to_regprocedure(f) is null)
     or to_regprocedure('world.mid_from_terms(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,numeric,numeric,numeric,numeric)') is null then
    raise exception '0350 refuses: 0348 (the board''s four pieces and the read) or the price expression is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0350 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0350
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_recut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select f::regprocedure::oid from unnest(c_recut) f));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_job_before;
  end if;

  -- ── 2. THE TWO NEW PIECES (server only) ──
  execute $f$
create function world.good_mids(p_good uuid)
returns table(port_id uuid, stock numeric, stock_target numeric, mid numeric)
language sql
stable
as $body$
  -- 0350: EVERY MARKET ROW OF A GOOD AND ITS PRICE, IN ONE STATEMENT — the dearest-buyers list, read live. The price is world.mid_from_terms (the one price expression) on the row's terms and
  -- the four price knobs, exactly as world.mid_terms reads them one row at a time: mid = world.mid_price(port_id, p_good, stock) for every row, to the digit (asserted where it was made, 0350).
  -- world.board_sell reads it instead of one world.mid_price a harbour. Plain SQL on purpose (no definer, no setting), so the planner folds it into the caller's statement; server only.
  select pg.port_id, pg.stock, pg.stock_target,
         world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.glut, pg.stock_target, pg.stock, pg.drift,   -- 0173: + haul; 0194: + glut
                              pg.season_mod, p.dev_commerce,
                              (select public.wc_num('price_elasticity')), (select public.wc_num('mid_dev_discount')),   -- the four knobs, each read once a statement
                              (select public.wc_num('price_band_lo')), (select public.wc_num('price_band_hi'))) as mid
    from public.port_goods pg
    join public.goods g on g.id = pg.good_id
    join public.ports p on p.id = pg.port_id
   where pg.good_id = p_good
$body$
  $f$;

  execute $f$
create function world.board_legs(p_fleet uuid, p_ctx jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0350: HER PASSAGE TO EVERY HARBOUR, AND WHAT ITS LONGEST LEG ASKS OF HER STORES — world.board_sell's own reach / reach2 / needs and the leg columns of its cand, moved here whole (0188,
-- 0205, 0225, 0231; world.board_sell reads it for one board, world.best_sales once for every good). One row a harbour: {id, nm, stops, direct_nm, max_leg, shut_leg, sn_days, sn_tons, sn_cost,
-- sn_fits, sn_hold}. It reads of p_ctx only: world.board_origin's answer (origin, lead_nm, lead_stops, cap, passages), whether the good is her cargo (basis = on_board: sailed from where she is; else
-- bought first at src.code), and src_passages (the passages from the buy city, when the caller has them; else asked here). Nothing of the good, the amount or the prices.
declare
  v_player  uuid := public.current_player_id();
  v_origin  uuid := (p_ctx->>'origin')::uuid;
  v_lead_nm numeric := (p_ctx->>'lead_nm')::numeric;
  v_lead_stops text[] := array(select jsonb_array_elements_text(p_ctx->'lead_stops'));
  v_cap     numeric := (p_ctx->>'cap')::numeric;
  v_passages jsonb := p_ctx->'passages';
  v_basis   text := p_ctx->>'basis';
  v_src_passages jsonb := nullif(p_ctx->'src_passages', 'null'::jsonb);
  v_src_id  uuid;
  v_src     record;
  v_legs    jsonb;
begin
  select p_ctx->'src'->>'code' as code into v_src;
  v_src_id := (select p.id from public.ports p where v_basis <> 'on_board' and p.code = v_src.code);
  if v_src_id is not null and v_src_id is distinct from v_origin and v_src_passages is null then
    v_src_passages := world.board_passages(v_player, p_fleet, v_src_id, v_cap);
  end if;

  with src as (
    select p.id from public.ports p where v_basis <> 'on_board' and p.code = v_src.code
  ), reach as materialized (
    -- 0188: the passage she can sail (voyage.reach_passage), as BUY AT reads it — 0205: the rows asked once, above
    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg,
           r.shut_leg_nm as shut_leg   -- 0231
      from jsonb_to_recordset(v_passages) r(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric, shut_leg_nm numeric)
    union all select v_origin, 0, 0, '{}'::text[], case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end, null
     where v_origin is not null
  ), reach2 as materialized (   -- from the buy city, when it must be bought first
    select r.port_id, r.nm, r.direct_nm, r.stops, r.max_leg_nm as max_leg, r.shut_leg_nm as shut_leg   -- 0231
      from (select id from src where id is distinct from v_origin) s
     cross join jsonb_to_recordset(v_src_passages) r(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric, shut_leg_nm numeric)   -- 0348: world.board_passages, asked once
    union all   -- 0205: bought where she sails from — those are the passages asked once, above
    select x.port_id, x.nm, x.direct_nm, x.stops, x.max_leg_nm, x.shut_leg_nm
      from src cross join jsonb_to_recordset(v_passages) x(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric, shut_leg_nm numeric)
     where src.id = v_origin
    union all select id, 0, 0, '{}'::text[], 0, null from src
  ), legs as materialized (
    -- every harbour (world.board_sell keeps the ones that buy the good): the leg figures, as its `cand` read them
    select p.id,
           case when v_basis = 'on_board' then rc.nm
                else (select rc1.nm from reach rc1 where rc1.port_id = (select id from src)) + r2.nm end as nm,
           -- 0188: the stops between where she sails this leg from and the sell city, its direct miles, and the
           -- longest leg of the whole passage (to the buy city first, when it must be bought first)
           case when v_basis = 'on_board' then rc.stops else r2.stops end as stops,
           case when v_basis = 'on_board' then rc.direct_nm else r2.direct_nm end as direct_nm,
           case when v_basis = 'on_board' then rc.max_leg
                else greatest((select rc1.max_leg from reach rc1 where rc1.port_id = (select id from src)), r2.max_leg) end as max_leg,
           -- 0231: no passage within her stores, one within her navigation would: the least longest leg it asks (bought
           -- first elsewhere: each part's longest leg, or the leg that shuts it; null when her navigation shuts a part)
           case when v_basis = 'on_board' then case when rc.nm is null then rc.shut_leg end
                when r2.nm is not null and (select rc1.nm from reach rc1 where rc1.port_id = (select id from src)) is not null then null
                else (select greatest(a.v, b.v)
                        from (select case when rc1.nm is null then rc1.shut_leg else rc1.max_leg end as v
                                from reach rc1 where rc1.port_id = (select id from src)) a
                       cross join (select case when r2.nm is null then r2.shut_leg else r2.max_leg end as v) b
                       where a.v is not null and b.v is not null) end as shut_leg
      from public.ports p
      left join reach rc on rc.port_id = p.id
      left join reach2 r2 on r2.port_id = p.id
     where p.kind = 'HARBOUR'
  ), needs as materialized (
    -- 0225: what every candidate's longest leg asks of her stores — public.supply_needs, ONE call for every distinct
    -- length (her hulls read once), joined back by length; a row with no leg joins the null answer (fits false)
    select * from public.supply_needs(p_fleet, (select array_agg(c.max_leg) from legs c))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'nm', c.nm, 'stops', to_jsonb(c.stops), 'direct_nm', c.direct_nm, 'max_leg', c.max_leg, 'shut_leg', c.shut_leg,
           'sn_days', n.days, 'sn_tons', n.tons, 'sn_cost', n.cost, 'sn_fits', n.fits,   -- 0225
           'sn_hold', public.stores_in_hold(n.tons))), '[]'::jsonb)   -- the room those stores take in her hold: what a row's units_fit subtracts
    into v_legs
    from legs c left join needs n on n.nm is not distinct from c.max_leg;
  return v_legs;
end
$body$
  $f$;

  revoke all on function world.good_mids(uuid) from public, anon, authenticated;
  revoke all on function world.board_legs(uuid,jsonb) from public, anon, authenticated;

  -- ── 3. THE HUNKS: world.board_sell reads the prices and the legs from the two; world.best_sales asks the legs once (each hunk once, and reversing) ──
  create temp table hunks_0350 (fn text, n int, old text, new text) on commit drop;
  insert into hunks_0350 values
('world.board_sell(uuid,uuid,jsonb)', 1,
$h$-- src_passages: the passages from the buy city (world.board_passages), when the caller has them; else asked here. THE RANKING (cand, ranked) is the part a precomputed list could replace.
$h$,
$h$-- src_passages: the passages from the buy city (world.board_passages), when the caller has them; else asked there.
-- 0350: THE LEGS (her passage to every harbour and what its longest leg asks of her stores) are world.board_legs' — this body's own reach / reach2 / needs, moved there whole; a caller that
-- has them (world.best_sales: once for every good) hands them over as `legs`, else they are asked here. THE PRICES are world.good_mids': every buyer's mid in one pass, not one call a harbour.
$h$),
('world.board_sell(uuid,uuid,jsonb)', 2,
$h$  v_lead_stops text[] := array(select jsonb_array_elements_text(p_ctx->'lead_stops'));
  v_speed   numeric := (p_ctx->>'speed')::numeric;
  v_wage    numeric := (p_ctx->>'wage')::numeric;
  v_cap     numeric := (p_ctx->>'cap')::numeric;
  v_passages jsonb := p_ctx->'passages';
$h$,
$h$  v_speed   numeric := (p_ctx->>'speed')::numeric;
  v_wage    numeric := (p_ctx->>'wage')::numeric;
$h$),
('world.board_sell(uuid,uuid,jsonb)', 3,
$h$  v_src_passages jsonb := p_ctx->'src_passages';
  v_src_id  uuid;
$h$,
$h$  v_legs    jsonb := p_ctx->'legs';   -- 0350: world.board_legs' answer, when the caller has it
$h$),
('world.board_sell(uuid,uuid,jsonb)', 4,
$h$  v_src_id := (select p.id from public.ports p where v_basis <> 'on_board' and p.code = v_src.code);
  if v_src_id is not null and v_src_id is distinct from v_origin and v_src_passages is null then
    v_src_passages := world.board_passages(v_player, p_fleet, v_src_id, v_cap);
  end if;

  -- SELL AT: every harbour whose culture buys it; the dearest good_board_quoted priced in full
  with src as (
    select p.id from public.ports p where v_basis <> 'on_board' and p.code = v_src.code
  ), reach as materialized (
    -- 0188: the passage she can sail (voyage.reach_passage), as BUY AT reads it — 0205: the rows asked once, above
    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg,
           r.shut_leg_nm as shut_leg   -- 0231
      from jsonb_to_recordset(v_passages) r(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric, shut_leg_nm numeric)
    union all select v_origin, 0, 0, '{}'::text[], case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end, null
     where v_origin is not null
  ), reach2 as materialized (   -- from the buy city, when it must be bought first
    select r.port_id, r.nm, r.direct_nm, r.stops, r.max_leg_nm as max_leg, r.shut_leg_nm as shut_leg   -- 0231
      from (select id from src where id is distinct from v_origin) s
     cross join jsonb_to_recordset(v_src_passages) r(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric, shut_leg_nm numeric)   -- 0348: world.board_passages, asked once
    union all   -- 0205: bought where she sails from — those are the passages asked once, above
    select x.port_id, x.nm, x.direct_nm, x.stops, x.max_leg_nm, x.shut_leg_nm
      from src cross join jsonb_to_recordset(v_passages) x(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric, shut_leg_nm numeric)
     where src.id = v_origin
    union all select id, 0, 0, '{}'::text[], 0, null from src
  ), cand as materialized (
    select p.id, p.code, p.name, pg.stock, pg.stock_target,   -- 0183: + the city's stock and its normal level
           world.mid_price(p.id, p_good, pg.stock) as mid,
           case when v_basis = 'on_board' then rc.nm
                else (select rc1.nm from reach rc1 where rc1.port_id = (select id from src)) + r2.nm end as nm,
           -- 0188: the stops between where she sails this leg from and the sell city, its direct miles, and the
           -- longest leg of the whole passage (to the buy city first, when it must be bought first)
           case when v_basis = 'on_board' then rc.stops else r2.stops end as stops,
           case when v_basis = 'on_board' then rc.direct_nm else r2.direct_nm end as direct_nm,
           case when v_basis = 'on_board' then rc.max_leg
                else greatest((select rc1.max_leg from reach rc1 where rc1.port_id = (select id from src)), r2.max_leg) end as max_leg,
           -- 0231: no passage within her stores, one within her navigation would: the least longest leg it asks (bought
           -- first elsewhere: each part's longest leg, or the leg that shuts it; null when her navigation shuts a part)
           case when v_basis = 'on_board' then case when rc.nm is null then rc.shut_leg end
                when r2.nm is not null and (select rc1.nm from reach rc1 where rc1.port_id = (select id from src)) is not null then null
                else (select greatest(a.v, b.v)
                        from (select case when rc1.nm is null then rc1.shut_leg else rc1.max_leg end as v
                                from reach rc1 where rc1.port_id = (select id from src)) a
                       cross join (select case when r2.nm is null then r2.shut_leg else r2.max_leg end as v) b
                       where a.v is not null and b.v is not null) end as shut_leg
      from public.ports p
      join public.port_goods pg on pg.port_id = p.id and pg.good_id = p_good
      left join reach rc on rc.port_id = p.id
      left join reach2 r2 on r2.port_id = p.id
     where p.kind = 'HARBOUR' and not public.culture_refuses(p.culture, g.culture_mask)
  ), needs as materialized (
    -- 0225: what every candidate's longest leg asks of her stores — public.supply_needs, ONE call for every distinct
    -- length (her hulls read once), joined back by length; a row with no leg joins the null answer (fits false)
    select * from public.supply_needs(p_fleet, (select array_agg(c.max_leg) from cand c))
  ), shuts as materialized (
    -- 0231: why a city no passage within her stores reaches is shut — voyage.leg_refusal, once per distinct length
    select u.nm, voyage.leg_refusal(p_fleet, null, u.nm, null) as refusal
      from (select distinct c.shut_leg from cand c where c.nm is null and c.shut_leg is not null) u(nm)
  ), free as materialized (
    -- 0225: the capacity basis's own measure of her room, read ONCE (every sell row's `units_fit` subtracts its stores from it)
    select public.fleet_free_hold(p_fleet) as t
  ), ranked as materialized (
    -- 0188: the dearest cities she can REACH are priced first; one no passage within her reach gets to ranks last
    select c.*, n.days as sn_days, n.tons as sn_tons, n.cost as sn_cost, n.fits as sn_fits,   -- 0225
           -- the units of the good that fit beside those stores (the capacity basis's own measure,
           -- public.fleet_free_hold, less their tuns): what a BUY may load and still sail this leg (0225; 0348: read here,
           -- once, for the row's `units_fit` and for the FIT amount below)
           case when v_basis <> 'on_board' then greatest(0, floor(((select t from free) - public.stores_in_hold(n.tons)) / g.bulk)) end as fit,
           row_number() over (order by (c.nm is null), c.mid desc, c.nm nulls last, c.code) as rk,
           -- 0251: THE NEAREST SHE CAN SAIL TO (the row's own `sailable`), by the passage's miles; where she lies last
           row_number() over (order by coalesce(c.nm is not null and c.max_leg is not null and v_speed > 0 and n.fits, false) desc,
                                       c.id is not distinct from v_origin, c.nm nulls last, c.code) as nk
      from cand c left join needs n on n.nm is not distinct from c.max_leg
$h$,
$h$  -- 0350: THE LEGS — handed over, else asked here (world.good_board asks one board; world.best_sales asks once for every good)
  if v_legs is null or jsonb_typeof(v_legs) <> 'array' then
    v_legs := world.board_legs(p_fleet, p_ctx);
  end if;

  -- SELL AT: every harbour whose culture buys it; the dearest good_board_quoted priced in full
  with src as (
    select p.id from public.ports p where v_basis <> 'on_board' and p.code = v_src.code
  ), cand as materialized (
    -- 0350: the city's stock, its normal level and its price from world.good_mids (world.mid_price's figure, every buyer in one pass);
    -- her passage there and what its longest leg asks of her stores from world.board_legs (0188, 0225, 0231: moved there whole)
    select p.id, p.code, p.name, m.stock, m.stock_target,   -- 0183: + the city's stock and its normal level
           m.mid,
           l.nm, l.stops, l.direct_nm, l.max_leg, l.shut_leg,
           l.sn_days, l.sn_tons, l.sn_cost, l.sn_fits, l.sn_hold   -- 0225; sn_hold: the room those stores take in her hold (public.stores_in_hold), read once a leg
      from public.ports p
      join world.good_mids(p_good) m on m.port_id = p.id
      join jsonb_to_recordset(v_legs) l(id uuid, nm numeric, stops text[], direct_nm numeric, max_leg numeric, shut_leg numeric,
                                        sn_days numeric, sn_tons numeric, sn_cost bigint, sn_fits boolean, sn_hold numeric) on l.id = p.id
     where p.kind = 'HARBOUR' and not public.culture_refuses(p.culture, g.culture_mask)
  ), shuts as materialized (
    -- 0231: why a city no passage within her stores reaches is shut — voyage.leg_refusal, once per distinct length
    select u.nm, voyage.leg_refusal(p_fleet, null, u.nm, null) as refusal
      from (select distinct c.shut_leg from cand c where c.nm is null and c.shut_leg is not null) u(nm)
  ), free as materialized (
    -- 0225: the capacity basis's own measure of her room, read ONCE (every sell row's `units_fit` subtracts its stores from it)
    select public.fleet_free_hold(p_fleet) as t
  ), ranked as materialized (
    -- 0188: the dearest cities she can REACH are priced first; one no passage within her reach gets to ranks last
    select c.*,
           -- the units of the good that fit beside those stores (the capacity basis's own measure,
           -- public.fleet_free_hold, less their tuns): what a BUY may load and still sail this leg (0225; 0348: read here,
           -- once, for the row's `units_fit` and for the FIT amount below)
           case when v_basis <> 'on_board' then greatest(0, floor(((select t from free) - c.sn_hold) / g.bulk)) end as fit,
           row_number() over (order by (c.nm is null), c.mid desc, c.nm nulls last, c.code) as rk,
           -- 0251: THE NEAREST SHE CAN SAIL TO (the row's own `sailable`), by the passage's miles; where she lies last
           row_number() over (order by coalesce(c.nm is not null and c.max_leg is not null and v_speed > 0 and c.sn_fits, false) desc,
                                       c.id is not distinct from v_origin, c.nm nulls last, c.code) as nk
      from cand c
$h$),
('world.best_sales(uuid,uuid)', 5,
$h$  v_cut     boolean := false;
$h$,
$h$  v_cut     boolean := false;
  v_ctx     jsonb;                  -- 0350: what world.board_sell is asked with
  v_legs_buy jsonb;                 -- 0350: world.board_legs for a good bought at p_port, asked once
  v_legs_own jsonb;                 -- 0350: world.board_legs for her cargo, asked once
$h$),
('world.best_sales(uuid,uuid)', 6,
$h$    select * into a from world.board_amount(p_fleet, gd.id, null);
    v_rows := world.board_sell(gd.id, p_fleet, v_o || jsonb_build_object(
                'units', a.units, 'basis', a.basis, 'cost_each', a.cost_each,
                'src', jsonb_build_object('code', case when a.basis <> 'on_board' then v_port.code end),
                'src_cut', a.basis <> 'on_board' and v_src_cut,
                'src_name', case when a.basis <> 'on_board' then v_port.name end,
                'fit', a.basis <> 'on_board', 'lean', true, 'src_passages', v_src_passages));
$h$,
$h$    select * into a from world.board_amount(p_fleet, gd.id, null);
    v_ctx := v_o || jsonb_build_object(
                'units', a.units, 'basis', a.basis, 'cost_each', a.cost_each,
                'src', jsonb_build_object('code', case when a.basis <> 'on_board' then v_port.code end),
                'src_cut', a.basis <> 'on_board' and v_src_cut,
                'src_name', case when a.basis <> 'on_board' then v_port.name end,
                'fit', a.basis <> 'on_board', 'lean', true, 'src_passages', v_src_passages);
    -- 0350: THE LEGS, ASKED ONCE A CALL, NOT ONCE A GOOD. Her passage to every harbour and its stores do not depend on the good:
    -- only on whether it is her cargo (sailed from where she is) or bought at p_port (sailed there first). world.board_legs reads
    -- nothing else of the amount, so one answer serves every good of the same kind.
    if a.basis = 'on_board' then
      if v_legs_own is null then
        v_legs_own := world.board_legs(p_fleet, v_ctx);
      end if;
      v_ctx := v_ctx || jsonb_build_object('legs', v_legs_own);
    else
      if v_legs_buy is null then
        v_legs_buy := world.board_legs(p_fleet, v_ctx);
      end if;
      v_ctx := v_ctx || jsonb_build_object('legs', v_legs_buy);
    end if;
    v_rows := world.board_sell(gd.id, p_fleet, v_ctx);
$h$);

  for rf in select * from pre_0350 order by 1 loop
    v_def := rf.def;
    for h in select * from hunks_0350 x where x.fn = rf.fn order by n loop
      v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
      if v_n <> 1 then
        raise exception '0350 self-assert FAIL: % hunk % occurs % time(s), not once: the deployed body is not what this file was written against', rf.fn, h.n, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(rf.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0350 x where x.fn = rf.fn order by n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception '0350 self-assert FAIL: % new hunk % is not in the live body once', rf.fn, h.n;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> rf.def then
      raise exception '0350 self-assert FAIL: % does not reverse to its pre-image', rf.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = rf.fn::regprocedure) <> rf.meta then
      raise exception '0350 self-assert FAIL: % changed its ACL, volatility, definer, config or owner', rf.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0350) <> 6 or (select count(distinct x.fn) from hunks_0350 x join pre_0350 p on p.fn = x.fn) <> 2 then
    raise exception '0350 self-assert FAIL: the hunks are not the 6 of the two re-cut bodies';
  end if;

  -- ── 4. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select f::regprocedure::oid from unnest(c_recut || c_new_fns) f))) <> v_fn_before then
    raise exception '0350 self-assert FAIL: another function moved (world.good_board, world.quote and world.mid_price among them must not)';
  end if;
  if exists (select 1 from unnest(c_new_fns) f join pg_proc p on p.oid = f::regprocedure where p.provolatile <> 's')
     or exists (select 1 from unnest(c_new_fns || c_recut[1:1]) f
                 where has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute'))
     or has_function_privilege('anon', 'world.best_sales(uuid,uuid)', 'execute') or not has_function_privilege('authenticated', 'world.best_sales(uuid,uuid)', 'execute') then
    raise exception '0350 self-assert FAIL: the new pieces are not STABLE and server only, or the read lost its grant';
  end if;
  -- the costs that went are gone from the body: no price asked a harbour at a time, no stores asked a good at a time, the passages parsed nowhere in it
  v_def := (select p.prosrc from pg_proc p where p.oid = 'world.board_sell(uuid,uuid,jsonb)'::regprocedure);
  if v_def like '%mid_price(%' or v_def like '%supply_needs(%' or v_def like '%stores_in_hold(%' or v_def like '%board_passages(%' or v_def like '%jsonb_to_recordset(v_passages)%'
     or v_def not like '%world.good_mids(p_good)%' or v_def not like '%world.board_legs(p_fleet, p_ctx)%' then
    raise exception '0350 self-assert FAIL: world.board_sell still asks a price a harbour or the stores a good, or does not read the two new pieces';
  end if;
  v_def := (select p.prosrc from pg_proc p where p.oid = 'world.best_sales(uuid,uuid)'::regprocedure);
  if (length(v_def) - length(replace(v_def, 'world.board_legs(p_fleet, v_ctx)', ''))) / length('world.board_legs(p_fleet, v_ctx)') <> 2
     or v_def not like '%interval ''2.5 seconds''%' then
    raise exception '0350 self-assert FAIL: world.best_sales does not ask the legs once a kind, or its budget moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0350 self-assert FAIL: a world_config row moved: this file sets no knob';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0350 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_def;
    if v_def is distinct from v_job_before then
      raise exception '0350 self-assert FAIL: a cron job moved: this file schedules nothing';
    end if;
  end if;

  -- ── 5. THE SELF-ASSERT: a probe house of its own rows, every one rolled back. Only the probe's own answers are asserted. ──
  begin
    -- the answers BEFORE this file, kept as pg_temp copies of the three pre-images (0251's way; rolled back with the probe)
    execute replace((select def from pre_0350 where fn = 'world.board_sell(uuid,uuid,jsonb)'), 'FUNCTION world.board_sell(', 'FUNCTION pg_temp.board_sell_old_0350(');
    execute replace(replace((select def from pre_0350 where fn = 'world.best_sales(uuid,uuid)'), 'FUNCTION world.best_sales(', 'FUNCTION pg_temp.best_sales_old_0350('),
                    'world.board_sell(', 'pg_temp.board_sell_old_0350(');
    v_def := replace(pg_get_functiondef('world.good_board(uuid,uuid,uuid,numeric)'::regprocedure), E'\r', '');
    if v_def not like '%v_sell := world.board_sell(%' then
      raise exception '0350 self-assert FAIL: world.good_board does not ask world.board_sell';
    end if;
    execute replace(replace(v_def, 'FUNCTION world.good_board(', 'FUNCTION pg_temp.good_board_old_0350('), 'world.board_sell(', 'pg_temp.board_sell_old_0350(');

    v_pl := public.new_house(c_uid, 'Probe 0350', 'PRT');
    select id, port_id into v_fl, v_home from public.fleets where player_id = v_pl;
    v_hcode := (select code from public.ports where id = v_home);
    if v_home is null then
      raise exception '0350 self-assert FAIL: the probe company lies at no harbour';
    end if;
    perform cmd.assume_identity(c_uid);
    select g.id, g.code into v_g1, v_g1code
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_home and pg.stock >= 50 and public.port_offers(v_home, g.id)
     order by g.code limit 1;
    select p.id into v_near
      from public.ports p, public.ports hb
     where hb.id = v_home and p.kind = 'HARBOUR' and p.id <> v_home
       and exists (select 1 from public.port_goods pg where pg.port_id = p.id and public.port_offers(p.id, pg.good_id))
     order by voyage.gc_distance_nm(hb.lat, hb.lon, p.lat, p.lon), p.code limit 1;
    if v_g1 is null or v_near is null then
      raise exception '0350 self-assert FAIL: the probe found no good at % or no harbour near it', v_hcode;
    end if;

    -- (m) THE PRICES: world.good_mids is world.mid_price, to the digit, at every harbour, for every good her harbour sells (ONE statement, one snapshot)
    select count(*), count(*) filter (where m.mid is distinct from world.mid_price(m.port_id, s.good_id, m.stock)
                                         or m.stock is distinct from pg.stock or m.stock_target is distinct from pg.stock_target)
      into v_cnt, v_n
      from (select pg0.good_id from public.port_goods pg0 where pg0.port_id = v_home and public.port_offers(v_home, pg0.good_id)) s
     cross join lateral world.good_mids(s.good_id) m
      join public.port_goods pg on pg.port_id = m.port_id and pg.good_id = s.good_id;
    if v_n <> 0 or v_cnt = 0
       or v_cnt <> (select count(*) from public.port_goods pg where pg.good_id in (select pg0.good_id from public.port_goods pg0 where pg0.port_id = v_home and public.port_offers(v_home, pg0.good_id))) then
      raise exception '0350 self-assert FAIL: world.good_mids is not world.mid_price: % of % market rows differ', v_n, v_cnt;
    end if;
    r_m := format('good_mids = mid_price on %s market rows', v_cnt);

    -- (a) THE BOARD, NOTHING ABOARD: world.good_board is its answer before this file, byte for byte — no city, her own city, an amount, another city that sells it (ONE statement)
    select count(*), string_agg(format('%s from %s qty %s', v_g1code, coalesce(x.f::text, '-'), coalesce(x.q::text, '-')), '; ')
             filter (where pg_temp.good_board_old_0350(v_g1, v_fl, x.f, x.q) is distinct from world.good_board(v_g1, v_fl, x.f, x.q))
      into v_cnt, v_bad
      from (values (null::uuid, null::numeric), (v_home, null), (v_home, 7),
                   ((select pg.port_id from public.port_goods pg join public.ports p on p.id = pg.port_id
                      where pg.good_id = v_g1 and pg.port_id <> v_home and p.kind = 'HARBOUR' and pg.stock > 0 and public.port_offers(pg.port_id, v_g1)
                      order by p.code limit 1), null)) x(f, q);
    if v_bad is not null then
      raise exception '0350 self-assert FAIL: good_board is not its answer before this file: %', v_bad;
    end if;
    r_a := format('good_board = before for %s, %s ways (not aboard)', v_g1code, v_cnt);

    -- (b) THE READ AT HER OWN CITY: old then new in ONE statement (one snapshot), each timed. A cut answer (the 2.5 s budget, on a busy world) is compared over the goods both answered.
    with t0 as materialized (select clock_timestamp() as c),
         o  as materialized (select pg_temp.best_sales_old_0350(v_fl, v_home) as b from t0),
         t1 as materialized (select clock_timestamp() as c, o.b from o),
         n  as materialized (select world.best_sales(v_fl, v_home) as b, t1.c, t1.b as ob from t1),
         t2 as materialized (select clock_timestamp() as c2, n.c as c1, n.b, n.ob from n)
    select t2.ob, t2.b, extract(epoch from t2.c1 - t0.c) * 1000, extract(epoch from t2.c2 - t2.c1) * 1000
      into v_old, v_new, v_ms_old, v_ms_new from t2 cross join t0;
    v_k := least(jsonb_array_length(v_old->'goods'), jsonb_array_length(v_new->'goods'));
    if v_k = 0 or v_old->'port' is distinct from v_new->'port' or v_old->'clock' is distinct from v_new->'clock'
       or exists (select 1 from generate_series(0, v_k - 1) i where v_old->'goods'->i is distinct from v_new->'goods'->i)
       or (not (v_old->>'cut')::boolean and not (v_new->>'cut')::boolean and v_old is distinct from v_new) then
      raise exception '0350 self-assert FAIL: best_sales at % is not its answer before this file: old % new %', v_hcode, v_old, v_new;
    end if;
    if not (v_old->>'cut')::boolean and not (v_new->>'cut')::boolean then
      v_sum_old := v_sum_old + v_ms_old; v_sum_new := v_sum_new + v_ms_new; v_pairs := v_pairs + 1;
    end if;
    if not (v_new->>'cut')::boolean and jsonb_array_length(v_new->'goods') <> (select count(*) from public.port_goods pg where pg.port_id = v_home and public.port_offers(v_home, pg.good_id)) then
      raise exception '0350 self-assert FAIL: positive control — best_sales at % answered % good(s)', v_hcode, jsonb_array_length(v_new->'goods');
    end if;
    if not exists (select 1 from jsonb_array_elements(v_new->'goods') e where e->>'port' is not null) then
      raise exception '0350 self-assert FAIL: positive control — no good at % has a sale', v_hcode;
    end if;
    r_b := format('best_sales at %s = before: %s goods compared (old %s, new %s answered); old %s ms, new %s ms', v_hcode, v_k,
                  jsonb_array_length(v_old->'goods'), jsonb_array_length(v_new->'goods'), round(v_ms_old), round(v_ms_new));

    -- (l) THE LAW 0348 ASSERTED, KEPT: a card's profit and units are world.good_board(good, fleet, here, units)'s row for that city, to the coin (the first 3 cards with a sale; ONE statement)
    with bs as materialized (select world.best_sales(v_fl, v_home) as b),
         cards as (select e from bs, jsonb_array_elements(bs.b->'goods') with ordinality x(e, i) where e->>'port' is not null order by i limit 3)
    select count(*),
           string_agg(format('%s at %s: card %s x %s, board %s x %s', e->>'good', e->>'port', e->>'profit', e->>'units', y.s->>'profit', y.s->>'units'), '; ')
             filter (where y.s is null or (y.s->>'profit')::numeric is distinct from (e->>'profit')::numeric or (y.s->>'units')::numeric is distinct from (e->>'units')::numeric
                     or (y.s->>'sailable')::boolean is not true)
      into v_rows, v_bad
      from cards
      cross join lateral (select world.good_board((select g.id from public.goods g where g.code = e->>'good'), v_fl,
                                                  case when e->>'basis' <> 'on_board' then v_home end,
                                                  case when e->>'basis' <> 'on_board' then (e->>'units')::numeric end) as gb) x
      left join lateral (select s from jsonb_array_elements(x.gb->'sell') s where s->>'port' = e->>'port') y on true;
    if v_bad is not null or v_rows = 0 then
      raise exception '0350 self-assert FAIL: a card is not the board''s figure (% cards): %', v_rows, v_bad;
    end if;
    r_l := format('%s cards at %s: each is good_board''s row to the coin', v_rows, v_hcode);

    -- (c) ANOTHER CITY IN HAND (bought there, not where she lies): NEW FIRST, then old, in one statement
    with t0 as materialized (select clock_timestamp() as c),
         n  as materialized (select world.best_sales(v_fl, v_near) as b from t0),
         t1 as materialized (select clock_timestamp() as c, n.b from n),
         o  as materialized (select pg_temp.best_sales_old_0350(v_fl, v_near) as b, t1.c, t1.b as nb from t1),
         t2 as materialized (select clock_timestamp() as c2, o.c as c1, o.b, o.nb from o)
    select t2.b, t2.nb, extract(epoch from t2.c2 - t2.c1) * 1000, extract(epoch from t2.c1 - t0.c) * 1000
      into v_old, v_new, v_ms_old, v_ms_new from t2 cross join t0;
    v_k := least(jsonb_array_length(v_old->'goods'), jsonb_array_length(v_new->'goods'));
    if v_k = 0 or v_old->'port' is distinct from v_new->'port'
       or exists (select 1 from generate_series(0, v_k - 1) i where v_old->'goods'->i is distinct from v_new->'goods'->i)
       or (not (v_old->>'cut')::boolean and not (v_new->>'cut')::boolean and v_old is distinct from v_new) then
      raise exception '0350 self-assert FAIL: from another city, best_sales is not its answer before this file: old % new %', v_old, v_new;
    end if;
    if not (v_old->>'cut')::boolean and not (v_new->>'cut')::boolean then
      v_sum_old := v_sum_old + v_ms_old; v_sum_new := v_sum_new + v_ms_new; v_pairs := v_pairs + 1;
    end if;
    r_c := format('best_sales at %s (not where she lies) = before: %s goods compared; old %s ms, new %s ms', v_new->>'port', v_k, round(v_ms_old), round(v_ms_new));

    -- (d) HER CARGO: 10 of the good bought. The board is its answer before this file, and the read is too (both kinds of legs in one call: her cargo, and the goods bought here)
    perform cmd.do_buy(v_fl, jsonb_build_object('good', v_g1, 'qty', 10));
    if coalesce(public.fleet_cargo_qty(v_fl, v_g1code), 0) <> 10 then
      raise exception '0350 self-assert FAIL: the probe did not load 10 %', v_g1code;
    end if;
    with t0 as materialized (select clock_timestamp() as c),
         o  as materialized (select pg_temp.best_sales_old_0350(v_fl, v_home) as b from t0),
         t1 as materialized (select clock_timestamp() as c, o.b from o),
         n  as materialized (select world.best_sales(v_fl, v_home) as b, t1.c, t1.b as ob from t1),
         t2 as materialized (select clock_timestamp() as c2, n.c as c1, n.b, n.ob from n)
    select t2.ob, t2.b, extract(epoch from t2.c1 - t0.c) * 1000, extract(epoch from t2.c2 - t2.c1) * 1000,
           case when pg_temp.good_board_old_0350(v_g1, v_fl, null, null) is distinct from world.good_board(v_g1, v_fl, null, null) then 'good_board is not its answer before this file, aboard' end
      into v_old, v_new, v_ms_old, v_ms_new, v_bad from t2 cross join t0;
    v_k := least(jsonb_array_length(v_old->'goods'), jsonb_array_length(v_new->'goods'));
    if v_bad is null and (v_k = 0 or exists (select 1 from generate_series(0, v_k - 1) i where v_old->'goods'->i is distinct from v_new->'goods'->i)
                          or (not (v_old->>'cut')::boolean and not (v_new->>'cut')::boolean and v_old is distinct from v_new)) then
      v_bad := format('best_sales is not its answer before this file: old %s new %s', v_old, v_new);
    end if;
    if v_bad is null and not exists (select 1 from jsonb_array_elements(v_new->'goods') e where e->>'good' = v_g1code and e->>'basis' = 'on_board')
       and not (v_new->>'cut')::boolean then
      v_bad := 'the card does not read her cargo';
    end if;
    if v_bad is not null then
      raise exception '0350 self-assert FAIL: her cargo: %', v_bad;
    end if;
    if not (v_old->>'cut')::boolean and not (v_new->>'cut')::boolean then
      v_sum_old := v_sum_old + v_ms_old; v_sum_new := v_sum_new + v_ms_new; v_pairs := v_pairs + 1;
    end if;
    r_d := format('%s aboard: good_board = before; best_sales = before, %s goods compared; old %s ms, new %s ms', v_g1code, v_k, round(v_ms_old), round(v_ms_new));

    -- (e) THE TIME: over the pairs neither of which was cut, the new read may not be slower than the old by more than a quarter (it measures about half; the bound is for a busy world)
    if v_pairs > 0 and v_sum_new > v_sum_old * 1.25 then
      raise exception '0350 self-assert FAIL: best_sales is slower than before: new % ms against old % ms over % pair(s)', round(v_sum_new), round(v_sum_old), v_pairs;
    end if;
    r_e := format('%s pair(s) uncut: old %s ms, new %s ms (%s %%)', v_pairs, round(v_sum_old), round(v_sum_new),
                  case when v_sum_old > 0 then round(100 * v_sum_new / v_sum_old) end);

    raise exception using errcode = 'ZX350', message = 'PROBE_ROLLBACK_0350';
  exception when sqlstate 'ZX350' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0350 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid = c_uid) then
    raise exception '0350 self-assert FAIL: the probe left rows behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0350 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  if to_regprocedure('pg_temp.board_sell_old_0350(uuid,uuid,jsonb)') is not null then
    raise exception '0350 self-assert FAIL: a copy of a pre-image outlived the probe';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0350 self-assert FAIL: the file ran % s, over its 45 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0350 probe (m): %', r_m;
  raise notice '0350 probe (a): %', r_a;
  raise notice '0350 probe (b): %', r_b;
  raise notice '0350 probe (l): %', r_l;
  raise notice '0350 probe (c): %', r_c;
  raise notice '0350 probe (d): %', r_d;
  raise notice '0350 probe (e): %', r_e;
  raise notice '0350 self-assert ok: THE BEST SALE READS THE SEA ONCE. world.board_sell reads every buyer''s price in one pass (world.good_mids = world.mid_price) and her legs from world.board_legs (its own reach / needs, moved); world.best_sales asks the legs once a call. good_board and best_sales answer as before, byte for byte; no other function, knob, table, row or job moved. % ms.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
