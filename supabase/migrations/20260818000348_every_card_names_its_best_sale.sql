-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0348 — EVERY CARD NAMES ITS BEST SALE: world.best_sales(fleet, port), one read per city in hand. A READ: no table, no knob, no switch, no row. It changes no trade.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-11 (docs/OWNER_REQUESTS.md row 307, the remaster: "make it playable, make it fun"). The playtest: to learn which good pays where, a player pressed 8 city chips and read 10 cards each; nothing said
-- where a good sells higher, and "Max" on a good locked in a loss with no warning. On prod 12 of 19 players never made a first buy. docs/DESIGN.md K.1 promised "you did not have to know anything to see it".
-- The Command board's goods cards (src/features/command/buysell/TradeBoard.tsx) now each name the good's best reachable sale — the city and the PROFIT the Sail & sell tray shows — before any buy.
--
-- ONE AUTHORITY, MOVED, NOT COPIED. world.good_board (0171 … 0345) is the one place a sale's profit is worked out. Its pieces move into four server-only functions that it now calls, and world.best_sales calls
-- the same four:
--   world.board_passages(player, fleet, from, cap)  the passages from a harbour, as jsonb (good_board's 0205 read of voyage.reach_passage, verbatim).
--   world.board_origin(fleet)                       where her passages run from and what she sails with: origin, lead, speed, wage, stores, reach, cap and the passages (good_board's opening, verbatim).
--   world.board_amount(fleet, good, qty)            THE AMOUNT: on board, else asked, else her free hold (at least a step) (good_board's, verbatim).
--   world.board_sell(good, fleet, ctx)              THE SELL ROWS: every harbour that buys it, the dearest 10 and the nearest 5 she can sail to priced in full, the profit (good_board's SELL AT, verbatim but for
--                                                   two reader's options, below).
-- world.good_board's body keeps its checks, its BUY AT, the city it would buy at, its seas and its answer; three hunks hand the rest to the four (each asserted once and reversing; ACL, volatility, definer,
-- config and owner unmoved). ITS ANSWER IS ITS PRE-IMAGE BYTE FOR BYTE: asserted below in one statement against a pg_temp copy of the pre-image, for a good not aboard (no city, her own city, an amount, another
-- city) and for her cargo.
--
-- world.best_sales(p_fleet, p_port) — granted to authenticated, STABLE, reads only. For EVERY good the city sells (public.port_offers), by code: the best sale she can sail to, from that city —
--   {good, basis, port, units, profit, days, pays}. port null: no city she can sail to is priced. pays: profit > 0.
--   A good NOT aboard is bought at p_port (good_board's p_from) for THE UNITS THAT FIT BESIDE THE STORES OF THAT SALE'S LEG (the sell row's own `units_fit`): board_sell's FIT option buys each priced row
--   at its own count — world.quote at p_port, once per distinct count — so the row's profit is EXACTLY world.good_board(good, fleet, p_port, units)'s row for that city: the figure the trip tray opens with,
--   because the press opens the trip at those units. Asserted below, in one statement, for every good with a sale.
--   A good aboard is her cargo: good_board's on_board basis (the Sail & sell tray's own reading), exactly world.good_board(good, fleet, null, null)'s row. Asserted below.
--   p_port itself is never the answer (a sale where it is bought is no trip). The rows are the same rows good_board prices: no top-N cut of its own, nothing ranked here but by the served profit.
--   board_sell's LEAN option leaves out what only a full board shows (the day's cap, the estimate at arrival, an open request, passage_needs, the dock dues, the unpriced rows); no figure of a priced row moves.
-- COST. world.best_sales asks board_origin ONCE (voyage.reach_passage from where she sails), and the passages from p_port ONCE when she is not there; then per good one board_sell: market prices at every
--   harbour that buys it (world.mid_price), up to 15 sell quotes and the buy quotes at p_port per distinct count, the tax, the supplies. Measured: the PR's PROD CHECKS and docs/dev-log/2026-11-11-best-sales.md.
--   A TIME BUDGET: the goods are read in code order until 2.5 s have passed; the goods left are not answered and `cut` is true (the client draws no line for them). A slow call fails soft, never raises.
--   The ranking a precomputed dearest-buyers list could replace sits inside world.board_sell (cand / ranked), so that swap stays internal to it.
-- NOT TOUCHED: world.quote, world.mid_price, public.profit_tax, public.supply_needs, voyage.reach_passage, every table, every knob and switch, every other function. The seas (0219) are read by good_board as before;
--   best_sales reads none (sea_conditions_bite is false on prod; the trip's Go gates on `sailable`, which the seas do not move).
-- ROLLBACK (forward): a new migration reversing the hunks (each OLD text is here verbatim) and dropping the five new functions; nothing else depends on them.
-- SELF-ASSERT: the catalog, then a probe house of its own rolled-back rows. BUDGET: ONE DO block, statement_timeout 120 s, lock_timeout 5 s.
-- VERSION: 0348 - prod head 0345 (read 2026-11-11). 0346 (route builder) and 0347 (news markers) deploy first and touch neither world.good_board nor the registry line this file anchors on.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_def         text;
  v_pre         text;
  v_reg_pre     text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_rel_before  text;
  v_gb_meta     text;
  h             record;
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
  v_pays        int;
  v_bs          jsonb;
  v_ms          numeric[] := '{}';
  v_t           timestamptz;
  r_a text; r_b text; r_c text; r_d text; r_e text;
  c_uid  constant uuid := '00000000-0348-4000-8000-000000000001';
  c_reg_old constant text := $h$      ('world',       'captain_stats',         'text'),
$h$;
  c_reg_new constant text := $h$      ('world',       'captain_stats',         'text'),
      -- 0348: the best sale of every good a city sells, read once per city in hand (the Command board's cards).
      ('world',       'best_sales',            'uuid, uuid'),
$h$;
  c_new_fns constant text[] := array['world.board_passages(uuid,uuid,uuid,numeric)', 'world.board_origin(uuid)', 'world.board_amount(uuid,uuid,numeric)',
                                     'world.board_sell(uuid,uuid,jsonb)', 'world.best_sales(uuid,uuid)'];
begin
  perform set_config('statement_timeout', '120s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_new_fns) f where to_regprocedure(f) is not null) then
    raise exception '0348 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('world.good_board(uuid,uuid,uuid,numeric)') is null or to_regprocedure('public.stores_in_hold(numeric)') is null
     or to_regprocedure('voyage.reach_passage(uuid,uuid,uuid,numeric)') is null or to_regprocedure('public.client_rpc_entry_points()') is null then
    raise exception '0348 refuses: 0171 / 0231 / 0345 (the board it cuts, the stores) are not all in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  v_pre := replace(pg_get_functiondef('world.good_board(uuid,uuid,uuid,numeric)'::regprocedure), E'\r', '');
  v_reg_pre := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
    into v_gb_meta from pg_proc p where p.oid = 'world.good_board(uuid,uuid,uuid,numeric)'::regprocedure;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid not in ('world.good_board(uuid,uuid,uuid,numeric)'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  -- the pre-image kept as a pg_temp copy (0251's way), for the parity proof in one statement
  if (length(v_pre) - length(replace(v_pre, 'FUNCTION world.good_board(', ''))) / length('FUNCTION world.good_board(') <> 1 then
    raise exception '0348 refuses: good_board''s definition does not name itself once';
  end if;
  execute replace(v_pre, 'FUNCTION world.good_board(', 'FUNCTION pg_temp.good_board_old_0348(');

  -- ── 2. THE FOUR PIECES OF THE BOARD, AND THE READ ──
  execute $f$
create function world.board_passages(p_player uuid, p_fleet uuid, p_from uuid, p_cap numeric)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0348: THE PASSAGES FROM A HARBOUR, as jsonb — world.good_board's 0205 read of voyage.reach_passage, moved here whole (good_board, board_origin, board_sell and best_sales ask it).
  select coalesce(jsonb_agg(jsonb_build_object('port_id', r.port_id, 'nm', r.nm, 'direct_nm', r.direct_nm,
                                               'stops', r.stops, 'max_leg_nm', r.max_leg_nm,
                                               'shut_leg_nm', r.shut_leg_nm)), '[]'::jsonb)   -- 0231
    from voyage.reach_passage(p_player, p_fleet, p_from, p_cap) r   -- 0216: + her fleet; 0231: + the legs her stores cover
$body$
  $f$;

  execute $f$
create function world.board_origin(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0348: WHERE HER PASSAGES RUN FROM, AND WHAT SHE SAILS WITH — world.good_board's opening, moved here whole (good_board and best_sales read it). The caller has checked the fleet is the caller's.
declare
  v_player  uuid := public.current_player_id();
  f         public.fleets%rowtype;
  v         public.voyages%rowtype;
  v_now     timestamptz := now();
  v_tc      numeric := public.wc_num('time_compression');
  v_reach_nm numeric;
  v_origin  uuid;
  v_lead_nm numeric := 0;
  v_lead_at timestamptz := now();
  v_speed   numeric;
  v_wage    numeric;
  v_where   jsonb;
  v_lead_stops  text[] := '{}';
  v_end     numeric;
  v_margin  numeric;
  v_carry   numeric;
  v_cap     numeric;
begin
  select * into f from public.fleets where id = p_fleet;
  v_speed := voyage.fleet_speed(p_fleet);
  v_wage  := public.fleet_wage(p_fleet, false);
  v_end    := voyage.endurance_days(p_fleet);       -- 0188: a leg is sailable when her casks cover it (sail_refusal's rule)
  v_margin := public.wc_num('endurance_margin');
  v_reach_nm := public.passage_reach_nm(v_player);   -- 0251
  -- 0231 (owner row 208): HER LEGS FIT HER SUPPLIES. Every SAIL tops her stores up to the room beside her cargo (0225),
  -- so the longest leg she can sail is the one those stores cover (public.supply_reach — the rules `fits` reads). The
  -- passages are searched with every leg within it: a far city is reached by stopping to resupply, or is shut and
  -- says why (`shut`, voyage.leg_refusal).
  select sr.carry_days, sr.cap_nm into v_carry, v_cap from public.supply_reach(p_fleet) sr;
  if f.port_id is not null then
    v_origin := f.port_id;
    v_where  := jsonb_build_object('kind', 'docked', 'port', (select code from public.ports where id = f.port_id));
  else
    select * into v from public.voyages where fleet_id = p_fleet and status = 'SAILING' order by departed_at desc limit 1;
    if v.id is not null then
      v_origin  := v.dest_port_id;
      v_lead_nm := greatest(0, v.total_nm - voyage.progress_nm(v.id, v_now));
      v_lead_at := greatest(v.eta, v_now);
      v_where   := jsonb_build_object('kind', 'sailing', 'port', (select code from public.ports where id = v.dest_port_id),
                                      'miles_left', round(v_lead_nm), 'eta', v.eta);
    else
      -- 0183: AT ANCHOR (no berth, no voyage under way): from THE NEAREST HARBOUR to where she lies —
      -- the great-circle miles to it are the lead, as a voyage's miles left are, and the lead's time is
      -- those miles at her speed. The sailed-distance table holds harbours only. Never a board of bare rows.
      select p.id, voyage.gc_distance_nm(f.lat, f.lon, p.lat, p.lon)
        into v_origin, v_lead_nm
        from public.ports p
       where p.kind = 'HARBOUR' and f.lat is not null and f.lon is not null
       order by voyage.gc_distance_nm(f.lat, f.lon, p.lat, p.lon), p.code
       limit 1;
      v_lead_nm := coalesce(v_lead_nm, 0);
      if v_origin is not null and v_speed > 0 then
        v_lead_at := v_now + make_interval(secs => (v_lead_nm / v_speed * 3600 / v_tc)::double precision);
      end if;
      -- 0188: she sails to that harbour first: it is every passage's first stop, and the lead is a leg her casks must cover
      v_lead_stops := case when v_origin is not null then array[(select code from public.ports where id = v_origin)] else '{}' end;
      v_where := jsonb_build_object('kind', 'at_sea', 'port', null,
                                    'via', (select code from public.ports where id = v_origin),
                                    'miles_left', round(v_lead_nm));
    end if;
  end if;
  return jsonb_build_object('origin', v_origin, 'lead_nm', v_lead_nm, 'lead_at', v_lead_at, 'lead_stops', to_jsonb(v_lead_stops), 'where', v_where,
                            'speed', v_speed, 'wage', v_wage, 'end', v_end, 'margin', v_margin, 'reach_nm', v_reach_nm, 'carry', v_carry, 'cap', v_cap,
                            'passages', world.board_passages(v_player, p_fleet, v_origin, v_cap));   -- 0205: asked once
end
$body$
  $f$;

  execute $f$
create function world.board_amount(p_fleet uuid, p_good uuid, p_qty numeric, out units numeric, out basis text, out cost_each numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0348: THE AMOUNT A BOARD PRICES — world.good_board's, moved here whole (good_board and best_sales read it).
declare
  g         public.goods%rowtype;
  v_aboard  numeric;
  v_units   numeric;
  v_basis   text;
  v_cost_each numeric;
begin
  select * into g from public.goods where id = p_good;
  -- THE AMOUNT: what is on board, else what was asked, else what her free cargo space takes (at least a step)
  v_aboard := coalesce(public.fleet_cargo_qty(p_fleet, g.code), 0);
  if v_aboard > 0 then
    v_units := v_aboard; v_basis := 'on_board';
    v_cost_each := public.fleet_cargo_basis(p_fleet, g.code);
  elsif p_qty is not null and p_qty > 0 then
    v_units := floor(p_qty); v_basis := 'asked';
  else
    v_units := floor(public.fleet_free_hold(p_fleet) / g.bulk); v_basis := 'capacity';
    if v_units < 1 then
      v_units := public.wc_num('trade_step_tuns'); v_basis := 'step';
    end if;
  end if;
  units := v_units; basis := v_basis; cost_each := v_cost_each;
end
$body$
  $f$;

  execute $f$
create function world.board_sell(p_good uuid, p_fleet uuid, p_ctx jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0348: THE SELL ROWS OF A GOOD — world.good_board's SELL AT, moved here whole: the one place a sale's profit is worked out (good_board and best_sales read it). p_ctx is world.board_origin's answer plus
-- the amount (world.board_amount), the city it is bought at (src {code, units, cost}, src_cut, src_name) and two reader's options, both false for good_board:
--   fit   each priced row is bought at the buy city for the units that fit beside ITS stores (its `units_fit`), world.quote once per distinct count — the figure good_board serves when asked for that count;
--   lean  leave out what only a full board shows (the cap, the estimate, a request, passage_needs, the dues, the unpriced rows); no priced row's figure moves.
-- src_passages: the passages from the buy city (world.board_passages), when the caller has them; else asked here. THE RANKING (cand, ranked) is the part a precomputed list could replace.
declare
  v_player  uuid := public.current_player_id();
  g         public.goods%rowtype;
  v_now     timestamptz := now();
  v_tc      numeric := public.wc_num('time_compression');
  v_slot_s  numeric := public.wc_num('drift_slot_seconds');
  v_slots   int := public.wc_int('outlook_slots');
  v_max     int := public.wc_int('outlook_slots_max');
  v_quoted  int := public.wc_int('good_board_quoted');
  v_near    int := public.wc_int('good_board_quoted_near');
  v_reach_nm numeric := (p_ctx->>'reach_nm')::numeric;
  v_origin  uuid := (p_ctx->>'origin')::uuid;
  v_lead_nm numeric := (p_ctx->>'lead_nm')::numeric;
  v_lead_at timestamptz := (p_ctx->>'lead_at')::timestamptz;
  v_lead_stops text[] := array(select jsonb_array_elements_text(p_ctx->'lead_stops'));
  v_speed   numeric := (p_ctx->>'speed')::numeric;
  v_wage    numeric := (p_ctx->>'wage')::numeric;
  v_cap     numeric := (p_ctx->>'cap')::numeric;
  v_passages jsonb := p_ctx->'passages';
  v_units   numeric := (p_ctx->>'units')::numeric;
  v_basis   text := p_ctx->>'basis';
  v_cost_each numeric := (p_ctx->>'cost_each')::numeric;
  v_src_cut boolean := coalesce((p_ctx->>'src_cut')::boolean, false);
  v_src_name text := p_ctx->>'src_name';
  v_fit     boolean := coalesce((p_ctx->>'fit')::boolean, false);
  v_lean    boolean := coalesce((p_ctx->>'lean')::boolean, false);
  v_src_passages jsonb := p_ctx->'src_passages';
  v_src_id  uuid;
  v_src     record;
  v_sell    jsonb;
begin
  select * into g from public.goods where id = p_good;
  select p_ctx->'src'->>'code' as code, (p_ctx->'src'->>'units')::numeric as units, (p_ctx->'src'->>'cost')::numeric as cost into v_src;
  v_src_id := (select p.id from public.ports p where v_basis <> 'on_board' and p.code = v_src.code);
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
  ), units as (
    select case when v_basis = 'on_board' then v_units else coalesce(v_src.units, 0) end as n,
           case when v_basis = 'on_board' then case when v_cost_each is null then null else round(v_cost_each * v_units) end
                else v_src.cost end as cost
  ), buys as materialized (
    -- 0348 FIT (world.best_sales): each priced row is bought at the buy city for the units that fit beside ITS stores —
    -- world.quote, once per distinct count — so the row's figure is the board's own figure for that count
    select f.n, qb.units, qb.total::numeric as total
      from (select distinct r.fit as n from ranked r
             where v_fit and (r.rk <= v_quoted or r.nk <= v_near) and r.fit > 0) f
     cross join lateral world.quote((select id from src), p_good, f.n, 'buy', null, p_fleet) qb
  ), lots as materialized (
    -- 0348: the units each priced row sells and what they cost — the board's one amount, or (FIT) the row's own
    select r.id,
           case when v_fit then coalesce(b.units, 0) else u.n end as n,
           case when v_fit then b.total else u.cost end as cost
      from ranked r cross join units u
      left join buys b on b.n = r.fit
     where r.rk <= v_quoted or r.nk <= v_near   -- 0251: the dearest, and the nearest she can sail to
  ), quoted as materialized (
    select r.id, l.n, l.cost, qs.total as proceeds, qs.avg_price, qs.spread_total,
           case when r.nm is not null and v_speed > 0 then (v_lead_nm + r.nm) / v_speed / 24 end as days,
           case when r.nm is not null and v_speed > 0
                then v_lead_at + make_interval(secs => (r.nm / v_speed * 3600 / v_tc)::double precision) end as arrive_at
      from ranked r join lots l on l.id = r.id
     cross join lateral world.quote(r.id, p_good, l.n, 'sell', null, p_fleet) qs
     where l.n > 0
  ), priced as materialized (
    select q.*,
           public.profit_tax(q.id, case when q.cost is null then null else q.proceeds - q.cost end, v_player) as tax,
           case when q.days is null then null else round(v_wage * q.days) end as wages,
           -- 0348 LEAN (world.best_sales): the day's cap and the estimate are read only when shown
           case when not v_lean then world.daily_cap_remaining(v_player, q.id, p_good) end as cap_left,
           case when not v_lean then world.price_outlook(q.id, p_good,
             least(v_max, greatest(v_slots, ceil(extract(epoch from (coalesce(q.arrive_at, v_now) - v_now)) / v_slot_s)::int + 1)),
             'bid') end as j
      from quoted q
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'port', r.code, 'name', r.name, 'mid', r.mid, 'quoted', p.id is not null,
           'stops', to_jsonb(r.stops),   -- 0188
           'needs', case when not v_lean and r.direct_nm > v_reach_nm then public.passage_needs(v_player, r.direct_nm) end,   -- 0251: null within her reach
           'sailable', coalesce(r.nm is not null and r.max_leg is not null and v_speed > 0 and r.sn_fits, false),   -- 0225: they fit
           'longest_leg', case when r.max_leg is not null and v_speed > 0
                               then jsonb_build_object('miles', round(r.max_leg), 'days', round(r.max_leg / v_speed / 24, 2)) end,
           'supplies', case when r.max_leg is not null and v_speed > 0
                            then jsonb_build_object('days', round(r.sn_days, 1), 'cost', r.sn_cost, 'fits', r.sn_fits,
                                   'units_fit', r.fit) end,   -- 0225 (0348: read once, in `ranked`)
           'profit', case when p.id is not null and p.cost is not null and p.wages is not null and r.max_leg is not null and v_speed > 0
                          then p.proceeds - p.cost - p.tax - p.wages - r.sn_cost end,   -- 0225: the net less the supplies
           'shut', (select case when v_src_cut   -- 0238: the crossing is on the way to the buy city: say which
                                then jsonb_set(sh.refusal, '{figures}', coalesce(sh.refusal->'figures', '{}'::jsonb)
                                               || jsonb_build_object('buy_at', v_src.code, 'buy_at_name', v_src_name))
                                else sh.refusal end
                      from shuts sh where sh.nm = r.shut_leg and r.nm is null),   -- 0231
           'stock', r.stock, 'stock_target', r.stock_target,   -- 0183
           'miles', case when r.nm is not null then round(v_lead_nm + r.nm) end,
           'days', case when r.nm is not null and v_speed > 0 then round((v_lead_nm + r.nm) / v_speed / 24, 2) end,
           'arrive_at', p.arrive_at,
           'units', case when p.id is not null then p.n end,   -- 0348: the row's own units (the board's one amount, unless FIT)
           'price_each', p.avg_price, 'proceeds', p.proceeds, 'cost', p.cost, 'profit_tax', p.tax,
           'port_fee', p.spread_total, 'wages', p.wages,
           'net', case when p.id is not null and p.cost is not null and p.wages is not null
                       then p.proceeds - p.cost - p.tax - p.wages end,
           'net_per_ton', case when p.id is not null and p.cost is not null and p.wages is not null and p.n > 0
                               then round((p.proceeds - p.cost - p.tax - p.wages) / (p.n * g.bulk), 2) end,
           'cap_left', p.cap_left,
           'at_arrival', case when p.id is not null then
              (select jsonb_build_object('value', (e->>'value')::numeric, 'lo', (e->>'lo')::numeric, 'hi', (e->>'hi')::numeric)
                 from jsonb_array_elements(p.j->'points') with ordinality x(e, i)
                where (e->>'at')::timestamptz >= coalesce(p.arrive_at, v_now) order by i limit 1) end,
           'best', case when p.id is not null and not v_lean then public.outlook_best(p.j->'points', coalesce(p.arrive_at, v_now), 'bid') end,
           'request', case when not v_lean then
                        (select jsonb_build_object('premium_pct', c.premium_pct, 'days_left', c.expires_day - world.game_day())
                           from public.trade_contracts c
                          where c.port_id = r.id and c.good_id = p_good and c.status = 'open' and c.expires_day >= world.game_day()
                          order by c.premium_pct desc limit 1) end)
           -- 0237 (E4b, §4c): the dock fee for this parcel there and the country factor on its tax — closed only
           || case when v_lean then '{}'::jsonb else public.port_dues(r.id, v_player, p.cost) end
           order by (p.id is null),
                    case when p.id is not null and p.cost is not null and p.wages is not null
                         then p.proceeds - p.cost - p.tax - p.wages end desc nulls last,
                    r.mid desc, r.code), '[]'::jsonb)
    into v_sell
    from ranked r left join priced p on p.id = r.id
   where not v_lean or p.id is not null;   -- 0348 LEAN: only the priced rows
  return v_sell;
end
$body$
  $f$;

  execute $f$
create function world.best_sales(p_fleet uuid, p_port uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0348: THE BEST SALE OF EVERY GOOD A CITY SELLS, for your fleet (docs/OWNER_REQUESTS.md row 307). {port, goods: [{good, basis, port, units, profit, days, pays}], cut, clock}, the goods by code.
-- A good not aboard: bought at p_port for the units that fit beside the stores of that sale's leg (world.board_sell FIT) — world.good_board(good, fleet, p_port, units)'s row to the coin.
-- A good aboard: her cargo (on_board) — world.good_board(good, fleet, null, null)'s row to the coin. The best is the highest served profit of the rows she can sail to; p_port itself never.
-- port null: no city she can sail to is priced. pays: the profit is above nought. cut: the 2.5 s budget ran out; the goods after it are not answered.
declare
  v_player  uuid := public.current_player_id();
  v_t0      timestamptz := clock_timestamp();
  f         public.fleets%rowtype;
  v_port    public.ports%rowtype;
  v_o       jsonb;
  v_origin  uuid;
  v_src_passages jsonb;
  v_src_cut boolean;
  gd        record;
  a         record;
  v_rows    jsonb;
  v_best    jsonb;
  v_out     jsonb := '[]'::jsonb;
  v_cut     boolean := false;
  c_budget  constant interval := interval '2.5 seconds';
begin
  if v_player is null then
    raise exception 'E_NO_PLAYER: there is no company signed in' using errcode = 'P0001';
  end if;
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or f.player_id is distinct from v_player then
    raise exception 'E_NOT_YOURS: that is not your fleet' using errcode = 'P0001';
  end if;
  select * into v_port from public.ports where id = p_port and kind = 'HARBOUR';
  if v_port.id is null then
    raise exception 'E_NO_SUCH_PORT: there is no such harbour' using errcode = 'P0001';
  end if;

  v_o := world.board_origin(p_fleet);
  v_origin := (v_o->>'origin')::uuid;
  -- bought at p_port: the passages from it, asked once for every good (none when she sails from it)
  if p_port is distinct from v_origin then
    v_src_passages := world.board_passages(v_player, p_fleet, p_port, (v_o->>'cap')::numeric);
  end if;
  -- the way to p_port is past her stores (good_board's 0238 `shut` words name it)
  v_src_cut := not (p_port is not distinct from v_origin
                    or exists (select 1 from jsonb_array_elements(v_o->'passages') e
                                where (e->>'port_id')::uuid = p_port and jsonb_typeof(e->'nm') = 'number'));

  for gd in
    select g.id, g.code
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = p_port and public.port_offers(p_port, g.id)
     order by g.code
  loop
    if clock_timestamp() - v_t0 > c_budget then
      v_cut := true;
      exit;
    end if;
    select * into a from world.board_amount(p_fleet, gd.id, null);
    v_rows := world.board_sell(gd.id, p_fleet, v_o || jsonb_build_object(
                'units', a.units, 'basis', a.basis, 'cost_each', a.cost_each,
                'src', jsonb_build_object('code', case when a.basis <> 'on_board' then v_port.code end),
                'src_cut', a.basis <> 'on_board' and v_src_cut,
                'src_name', case when a.basis <> 'on_board' then v_port.name end,
                'fit', a.basis <> 'on_board', 'lean', true, 'src_passages', v_src_passages));
    v_best := (select e from jsonb_array_elements(v_rows) e
                where (e->>'sailable')::boolean and jsonb_typeof(e->'profit') = 'number' and e->>'port' is distinct from v_port.code
                order by (e->>'profit')::numeric desc, (e->>'days')::numeric nulls last, e->>'port'
                limit 1);
    v_out := v_out || jsonb_build_array(jsonb_build_object(
               'good', gd.code, 'basis', a.basis,
               'port', v_best->>'port', 'units', (v_best->>'units')::numeric, 'profit', (v_best->>'profit')::numeric,
               'days', (v_best->>'days')::numeric, 'pays', coalesce((v_best->>'profit')::numeric > 0, false)));
  end loop;

  return jsonb_build_object('port', v_port.code, 'goods', v_out, 'cut', v_cut,
                            'clock', jsonb_build_object('now', now(), 'next_change_at', public.next_drift_change_at(now())));
end
$body$
  $f$;

  revoke all on function world.board_passages(uuid,uuid,uuid,numeric) from public, anon, authenticated;
  revoke all on function world.board_origin(uuid) from public, anon, authenticated;
  revoke all on function world.board_amount(uuid,uuid,numeric) from public, anon, authenticated;
  revoke all on function world.board_sell(uuid,uuid,jsonb) from public, anon, authenticated;
  revoke all on function world.best_sales(uuid,uuid) from public, anon;
  grant execute on function world.best_sales(uuid,uuid) to authenticated;

  -- ── 3. THE HUNKS: world.good_board hands its pieces to the four (each once, and reversing) ──
  create temp table hunks_0348 (n int, old text, new text) on commit drop;
  insert into hunks_0348 values
(1,
$h$-- cargo list's near cities); passage_needs is asked only of a leg past her reach (its own null otherwise).
$h$,
$h$-- cargo list's near cities); passage_needs is asked only of a leg past her reach (its own null otherwise).
-- 0348: its opening, its amount and its sell rows are world.board_origin, world.board_amount and world.board_sell (the one authority world.best_sales reads too).
$h$),
(2,
$h$  v_src_name text;                  -- 0238: its name, for the shut row's words
$h$,
$h$  v_src_name text;                  -- 0238: its name, for the shut row's words
  v_o       jsonb;                  -- 0348: world.board_origin's answer
$h$),
(3,
$h$  v_speed := voyage.fleet_speed(p_fleet);
  v_wage  := public.fleet_wage(p_fleet, false);
  v_end    := voyage.endurance_days(p_fleet);       -- 0188: a leg is sailable when her casks cover it (sail_refusal's rule)
  v_margin := public.wc_num('endurance_margin');
  v_reach_nm := public.passage_reach_nm(v_player);   -- 0251
  -- 0231 (owner row 208): HER LEGS FIT HER SUPPLIES. Every SAIL tops her stores up to the room beside her cargo (0225),
  -- so the longest leg she can sail is the one those stores cover (public.supply_reach — the rules `fits` reads). The
  -- passages are searched with every leg within it: a far city is reached by stopping to resupply, or is shut and
  -- says why (`shut`, voyage.leg_refusal).
  select sr.carry_days, sr.cap_nm into v_carry, v_cap from public.supply_reach(p_fleet) sr;
  if f.port_id is not null then
    v_origin := f.port_id;
    v_where  := jsonb_build_object('kind', 'docked', 'port', (select code from public.ports where id = f.port_id));
  else
    select * into v from public.voyages where fleet_id = p_fleet and status = 'SAILING' order by departed_at desc limit 1;
    if v.id is not null then
      v_origin  := v.dest_port_id;
      v_lead_nm := greatest(0, v.total_nm - voyage.progress_nm(v.id, v_now));
      v_lead_at := greatest(v.eta, v_now);
      v_where   := jsonb_build_object('kind', 'sailing', 'port', (select code from public.ports where id = v.dest_port_id),
                                      'miles_left', round(v_lead_nm), 'eta', v.eta);
    else
      -- 0183: AT ANCHOR (no berth, no voyage under way): from THE NEAREST HARBOUR to where she lies —
      -- the great-circle miles to it are the lead, as a voyage's miles left are, and the lead's time is
      -- those miles at her speed. The sailed-distance table holds harbours only. Never a board of bare rows.
      select p.id, voyage.gc_distance_nm(f.lat, f.lon, p.lat, p.lon)
        into v_origin, v_lead_nm
        from public.ports p
       where p.kind = 'HARBOUR' and f.lat is not null and f.lon is not null
       order by voyage.gc_distance_nm(f.lat, f.lon, p.lat, p.lon), p.code
       limit 1;
      v_lead_nm := coalesce(v_lead_nm, 0);
      if v_origin is not null and v_speed > 0 then
        v_lead_at := v_now + make_interval(secs => (v_lead_nm / v_speed * 3600 / v_tc)::double precision);
      end if;
      -- 0188: she sails to that harbour first: it is every passage's first stop, and the lead is a leg her casks must cover
      v_lead_stops := case when v_origin is not null then array[(select code from public.ports where id = v_origin)] else '{}' end;
      v_where := jsonb_build_object('kind', 'at_sea', 'port', null,
                                    'via', (select code from public.ports where id = v_origin),
                                    'miles_left', round(v_lead_nm));
    end if;
  end if;

  -- THE AMOUNT: what is on board, else what was asked, else what her free cargo space takes (at least a step)
  v_aboard := coalesce(public.fleet_cargo_qty(p_fleet, g.code), 0);
  if v_aboard > 0 then
    v_units := v_aboard; v_basis := 'on_board';
    v_cost_each := public.fleet_cargo_basis(p_fleet, g.code);
  elsif p_qty is not null and p_qty > 0 then
    v_units := floor(p_qty); v_basis := 'asked';
  else
    v_units := floor(public.fleet_free_hold(p_fleet) / g.bulk); v_basis := 'capacity';
    if v_units < 1 then
      v_units := public.wc_num('trade_step_tuns'); v_basis := 'step';
    end if;
  end if;

  -- 0205: THE PASSAGES FROM WHERE SHE SAILS, ASKED ONCE. voyage.reach_passage was asked three times a board —
  -- BUY AT, SELL AT, and from the buy city when that is where she is — at ~1.2 s each on prod.
  select coalesce(jsonb_agg(jsonb_build_object('port_id', r.port_id, 'nm', r.nm, 'direct_nm', r.direct_nm,
                                               'stops', r.stops, 'max_leg_nm', r.max_leg_nm,
                                               'shut_leg_nm', r.shut_leg_nm)), '[]'::jsonb)   -- 0231
    into v_passages
    from voyage.reach_passage(v_player, p_fleet, v_origin, v_cap) r;   -- 0216: + her fleet; 0231: + the legs her stores cover
$h$,
$h$  -- 0348: WHERE SHE SAILS FROM, WHAT SHE SAILS WITH, AND THE AMOUNT — world.board_origin and world.board_amount (good_board's own opening and amount, moved there whole)
  v_o := world.board_origin(p_fleet);
  v_speed    := (v_o->>'speed')::numeric;
  v_wage     := (v_o->>'wage')::numeric;
  v_end      := (v_o->>'end')::numeric;
  v_margin   := (v_o->>'margin')::numeric;
  v_reach_nm := (v_o->>'reach_nm')::numeric;
  v_carry    := (v_o->>'carry')::numeric;
  v_cap      := (v_o->>'cap')::numeric;
  v_origin   := (v_o->>'origin')::uuid;
  v_lead_nm  := (v_o->>'lead_nm')::numeric;
  v_lead_at  := (v_o->>'lead_at')::timestamptz;
  v_where    := v_o->'where';
  v_lead_stops := array(select jsonb_array_elements_text(v_o->'lead_stops'));
  select a.units, a.basis, a.cost_each into v_units, v_basis, v_cost_each from world.board_amount(p_fleet, p_good, p_qty) a;
  v_passages := v_o->'passages';   -- 0205: the passages from where she sails, asked once (world.board_passages)
$h$),
(4,
$h$  -- SELL AT: every harbour whose culture buys it; the dearest good_board_quoted priced in full
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
     cross join lateral voyage.reach_passage(v_player, p_fleet, s.id, v_cap) r   -- 0216; 0231: + the legs her stores cover
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
           row_number() over (order by (c.nm is null), c.mid desc, c.nm nulls last, c.code) as rk,
           -- 0251: THE NEAREST SHE CAN SAIL TO (the row's own `sailable`), by the passage's miles; where she lies last
           row_number() over (order by coalesce(c.nm is not null and c.max_leg is not null and v_speed > 0 and n.fits, false) desc,
                                       c.id is not distinct from v_origin, c.nm nulls last, c.code) as nk
      from cand c left join needs n on n.nm is not distinct from c.max_leg
  ), units as (
    select case when v_basis = 'on_board' then v_units else coalesce(v_src.units, 0) end as n,
           case when v_basis = 'on_board' then case when v_cost_each is null then null else round(v_cost_each * v_units) end
                else v_src.cost end as cost
  ), quoted as materialized (
    select r.id, qs.total as proceeds, qs.avg_price, qs.spread_total,
           case when r.nm is not null and v_speed > 0 then (v_lead_nm + r.nm) / v_speed / 24 end as days,
           case when r.nm is not null and v_speed > 0
                then v_lead_at + make_interval(secs => (r.nm / v_speed * 3600 / v_tc)::double precision) end as arrive_at
      from ranked r cross join units u
     cross join lateral world.quote(r.id, p_good, u.n, 'sell', null, p_fleet) qs
     where (r.rk <= v_quoted or r.nk <= v_near) and u.n > 0   -- 0251: the dearest, and the nearest she can sail to
  ), priced as materialized (
    select q.*, u.cost,
           public.profit_tax(q.id, case when u.cost is null then null else q.proceeds - u.cost end, v_player) as tax,
           case when q.days is null then null else round(v_wage * q.days) end as wages,
           world.daily_cap_remaining(v_player, q.id, p_good) as cap_left,
           world.price_outlook(q.id, p_good,
             least(v_max, greatest(v_slots, ceil(extract(epoch from (coalesce(q.arrive_at, v_now) - v_now)) / v_slot_s)::int + 1)),
             'bid') as j
      from quoted q cross join units u
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'port', r.code, 'name', r.name, 'mid', r.mid, 'quoted', p.id is not null,
           'stops', to_jsonb(r.stops),   -- 0188
           'needs', case when r.direct_nm > v_reach_nm then public.passage_needs(v_player, r.direct_nm) end,   -- 0251: null within her reach
           'sailable', coalesce(r.nm is not null and r.max_leg is not null and v_speed > 0 and r.sn_fits, false),   -- 0225: they fit
           'longest_leg', case when r.max_leg is not null and v_speed > 0
                               then jsonb_build_object('miles', round(r.max_leg), 'days', round(r.max_leg / v_speed / 24, 2)) end,
           'supplies', case when r.max_leg is not null and v_speed > 0
                            then jsonb_build_object('days', round(r.sn_days, 1), 'cost', r.sn_cost, 'fits', r.sn_fits,
                                   -- the units of the good that fit beside those stores (the capacity basis's own measure,
                                   -- public.fleet_free_hold, less their tuns): what a BUY may load and still sail this leg
                                   'units_fit', case when v_basis <> 'on_board' then greatest(0, floor(((select t from free) - public.stores_in_hold(r.sn_tons)) / g.bulk)) end) end,   -- 0225
           'profit', case when p.id is not null and p.cost is not null and p.wages is not null and r.max_leg is not null and v_speed > 0
                          then p.proceeds - p.cost - p.tax - p.wages - r.sn_cost end,   -- 0225: the net less the supplies
           'shut', (select case when v_src_cut   -- 0238: the crossing is on the way to the buy city: say which
                                then jsonb_set(sh.refusal, '{figures}', coalesce(sh.refusal->'figures', '{}'::jsonb)
                                               || jsonb_build_object('buy_at', v_src.code, 'buy_at_name', v_src_name))
                                else sh.refusal end
                      from shuts sh where sh.nm = r.shut_leg and r.nm is null),   -- 0231
           'stock', r.stock, 'stock_target', r.stock_target,   -- 0183
           'miles', case when r.nm is not null then round(v_lead_nm + r.nm) end,
           'days', case when r.nm is not null and v_speed > 0 then round((v_lead_nm + r.nm) / v_speed / 24, 2) end,
           'arrive_at', p.arrive_at,
           'units', case when p.id is not null then (select n from units) end,
           'price_each', p.avg_price, 'proceeds', p.proceeds, 'cost', p.cost, 'profit_tax', p.tax,
           'port_fee', p.spread_total, 'wages', p.wages,
           'net', case when p.id is not null and p.cost is not null and p.wages is not null
                       then p.proceeds - p.cost - p.tax - p.wages end,
           'net_per_ton', case when p.id is not null and p.cost is not null and p.wages is not null and (select n from units) > 0
                               then round((p.proceeds - p.cost - p.tax - p.wages) / ((select n from units) * g.bulk), 2) end,
           'cap_left', p.cap_left,
           'at_arrival', case when p.id is not null then
              (select jsonb_build_object('value', (e->>'value')::numeric, 'lo', (e->>'lo')::numeric, 'hi', (e->>'hi')::numeric)
                 from jsonb_array_elements(p.j->'points') with ordinality x(e, i)
                where (e->>'at')::timestamptz >= coalesce(p.arrive_at, v_now) order by i limit 1) end,
           'best', case when p.id is not null then public.outlook_best(p.j->'points', coalesce(p.arrive_at, v_now), 'bid') end,
           'request', (select jsonb_build_object('premium_pct', c.premium_pct, 'days_left', c.expires_day - world.game_day())
                         from public.trade_contracts c
                        where c.port_id = r.id and c.good_id = p_good and c.status = 'open' and c.expires_day >= world.game_day()
                        order by c.premium_pct desc limit 1))
           -- 0237 (E4b, §4c): the dock fee for this parcel there and the country factor on its tax — closed only
           || public.port_dues(r.id, v_player, p.cost)
           order by (p.id is null),
                    case when p.id is not null and p.cost is not null and p.wages is not null
                         then p.proceeds - p.cost - p.tax - p.wages end desc nulls last,
                    r.mid desc, r.code), '[]'::jsonb)
    into v_sell
    from ranked r left join priced p on p.id = r.id;
$h$,
$h$  -- SELL AT: world.board_sell (0348: moved there whole — the one authority world.best_sales reads too)
  v_sell := world.board_sell(p_good, p_fleet, v_o || jsonb_build_object(
              'units', v_units, 'basis', v_basis, 'cost_each', v_cost_each,
              'src', jsonb_build_object('code', v_src.code, 'units', v_src.units, 'cost', v_src.cost),
              'src_cut', v_src_cut, 'src_name', v_src_name, 'fit', false, 'lean', false));
$h$);

  v_def := v_pre;
  for h in select * from hunks_0348 order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0348 self-assert FAIL: good_board hunk % occurs % time(s), not once: the deployed body is not what this file was written against', h.n, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
  v_def := replace(pg_get_functiondef('world.good_board(uuid,uuid,uuid,numeric)'::regprocedure), E'\r', '');
  for h in select * from hunks_0348 order by n desc loop
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0348 self-assert FAIL: new hunk % is not in the live body once', h.n;
    end if;
    v_def := replace(v_def, h.new, h.old);
  end loop;
  if v_def <> v_pre then
    raise exception '0348 self-assert FAIL: good_board does not reverse to its pre-image';
  end if;

  -- the registry row (once, and reversing)
  v_n := (length(v_reg_pre) - length(replace(v_reg_pre, c_reg_old, ''))) / length(c_reg_old);
  if v_n <> 1 then
    raise exception '0348 self-assert FAIL: the registry hunk occurs % time(s), not once', v_n;
  end if;
  execute replace(v_reg_pre, c_reg_old, c_reg_new);
  v_def := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_reg_new, ''))) / length(c_reg_new) <> 1 or replace(v_def, c_reg_new, c_reg_old) <> v_reg_pre then
    raise exception '0348 self-assert FAIL: public.client_rpc_entry_points is not its pre-image plus the one row';
  end if;

  -- ── 4. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in ('world.good_board(uuid,uuid,uuid,numeric)'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure)
         and p.oid <> all (array(select f::regprocedure::oid from unnest(c_new_fns) f))) <> v_fn_before then
    raise exception '0348 self-assert FAIL: another function moved';
  end if;
  if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
        from pg_proc p where p.oid = 'world.good_board(uuid,uuid,uuid,numeric)'::regprocedure) <> v_gb_meta then
    raise exception '0348 self-assert FAIL: good_board changed its ACL, volatility, definer, config or owner';
  end if;
  if exists (select 1 from unnest(c_new_fns) f join pg_proc p on p.oid = f::regprocedure where p.provolatile <> 's' or not p.prosecdef) then
    raise exception '0348 self-assert FAIL: a new function is not STABLE and definer';
  end if;
  if has_function_privilege('anon', 'world.best_sales(uuid,uuid)', 'execute') or not has_function_privilege('authenticated', 'world.best_sales(uuid,uuid)', 'execute')
     or exists (select 1 from unnest(c_new_fns[1:4]) f
                 where has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute')) then
    raise exception '0348 self-assert FAIL: the grants are not the read to authenticated and the four pieces to nobody';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'best_sales' and e.arg_types = 'uuid, uuid' and e.fn is not null) then
    raise exception '0348 self-assert FAIL: the read is not in the client registry';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0348 self-assert FAIL: a world_config row moved: this file sets no knob';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0348 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  begin
    perform world.best_sales(gen_random_uuid(), gen_random_uuid());
    raise exception '0348 self-assert FAIL: a caller with no company read best_sales';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'E_NO_PLAYER%' then
      raise;
    end if;
  end;

  -- ── 5. THE SELF-ASSERT: a probe house of its own rows, every one rolled back. Only the probe's own keys are asserted. ──
  begin
    v_pl := public.new_house(c_uid, 'Probe 0348', 'PRT');
    select id, port_id into v_fl, v_home from public.fleets where player_id = v_pl;
    v_hcode := (select code from public.ports where id = v_home);
    if v_home is null then
      raise exception '0348 self-assert FAIL: the probe company lies at no harbour';
    end if;
    perform cmd.assume_identity(c_uid);
    -- a good her harbour sells with stock (bought below), and the nearest other harbour that sells goods
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
      raise exception '0348 self-assert FAIL: the probe found no good at % or no harbour near it', v_hcode;
    end if;

    -- (a) PARITY, NOTHING ABOARD: the new good_board is its pre-image byte for byte — no city, her own city, an amount, another city that sells it (ONE statement, one snapshot)
    select count(*), string_agg(format('%s from %s qty %s', v_g1code, coalesce(x.f::text, '-'), coalesce(x.q::text, '-')), '; ')
             filter (where pg_temp.good_board_old_0348(v_g1, v_fl, x.f, x.q) is distinct from world.good_board(v_g1, v_fl, x.f, x.q))
      into v_cnt, v_bad
      from (values (null::uuid, null::numeric), (v_home, null), (v_home, 7),
                   ((select pg.port_id from public.port_goods pg join public.ports p on p.id = pg.port_id
                      where pg.good_id = v_g1 and pg.port_id <> v_home and p.kind = 'HARBOUR' and pg.stock > 0 and public.port_offers(pg.port_id, v_g1)
                      order by p.code limit 1), null)) x(f, q);
    if v_bad is not null then
      raise exception '0348 self-assert FAIL: good_board is not its pre-image: %', v_bad;
    end if;
    r_a := format('good_board = its pre-image for %s, %s ways (not aboard)', v_g1code, v_cnt);

    -- (b) AGREEMENT, NOTHING ABOARD: every good with a sale at her harbour is good_board(good, fleet, here, units)'s row for that city, to the coin (ONE statement)
    with bs as materialized (select world.best_sales(v_fl, v_home) as b),
         cards as (select e from bs, jsonb_array_elements(bs.b->'goods') e where e->>'port' is not null)
    select (select b from bs), count(*), count(*) filter (where (e->>'pays')::boolean),
           string_agg(format('%s at %s: card %s x %s, board %s x %s', e->>'good', e->>'port', e->>'profit', e->>'units', y.s->>'profit', y.s->>'units'), '; ')
             filter (where y.s is null or (y.s->>'profit')::numeric is distinct from (e->>'profit')::numeric or (y.s->>'units')::numeric is distinct from (e->>'units')::numeric
                     or (y.s->>'sailable')::boolean is not true)
      into v_bs, v_rows, v_pays, v_bad
      from cards
      cross join lateral (select world.good_board((select g.id from public.goods g where g.code = e->>'good'), v_fl,
                                                  case when e->>'basis' <> 'on_board' then v_home end,
                                                  case when e->>'basis' <> 'on_board' then (e->>'units')::numeric end) as gb) x
      left join lateral (select s from jsonb_array_elements(x.gb->'sell') s where s->>'port' = e->>'port') y on true;
    if v_bad is not null then
      raise exception '0348 self-assert FAIL: a card is not the board''s figure: %', v_bad;
    end if;
    if v_rows = 0 or (v_bs->>'cut')::boolean or jsonb_array_length(v_bs->'goods') <> (select count(*) from public.port_goods pg where pg.port_id = v_home and public.port_offers(v_home, pg.good_id)) then
      raise exception '0348 self-assert FAIL: positive control — best_sales at % answered % good(s), % with a sale, cut %', v_hcode, jsonb_array_length(v_bs->'goods'), v_rows, v_bs->>'cut';
    end if;
    if exists (select 1 from jsonb_array_elements(v_bs->'goods') e where e->>'port' = v_hcode) then
      raise exception '0348 self-assert FAIL: a card names the city it is bought at';
    end if;
    r_b := format('best_sales at %s: %s goods, %s with a sale (%s pay), every one good_board''s row to the coin', v_hcode, jsonb_array_length(v_bs->'goods'), v_rows, v_pays);

    -- (c) ANOTHER CITY IN HAND (bought there, not where she lies): the same agreement
    with bs as materialized (select world.best_sales(v_fl, v_near) as b),
         cards as (select e from bs, jsonb_array_elements(bs.b->'goods') e where e->>'port' is not null)
    select (select b from bs), count(*),
           string_agg(format('%s at %s: card %s x %s, board %s x %s', e->>'good', e->>'port', e->>'profit', e->>'units', y.s->>'profit', y.s->>'units'), '; ')
             filter (where y.s is null or (y.s->>'profit')::numeric is distinct from (e->>'profit')::numeric or (y.s->>'units')::numeric is distinct from (e->>'units')::numeric)
      into v_bs, v_rows, v_bad
      from cards
      cross join lateral (select world.good_board((select g.id from public.goods g where g.code = e->>'good'), v_fl,
                                                  case when e->>'basis' <> 'on_board' then v_near end,
                                                  case when e->>'basis' <> 'on_board' then (e->>'units')::numeric end) as gb) x
      left join lateral (select s from jsonb_array_elements(x.gb->'sell') s where s->>'port' = e->>'port') y on true;
    if v_bad is not null then
      raise exception '0348 self-assert FAIL: from another city, a card is not the board''s figure: %', v_bad;
    end if;
    r_c := format('best_sales at %s (not where she lies): %s goods, %s with a sale, every one good_board''s row', v_bs->>'port', jsonb_array_length(v_bs->'goods'), v_rows);

    -- (d) HER CARGO: 10 of the good bought; good_board is its pre-image, and the card is the Sail & sell tray's row (on_board)
    perform cmd.do_buy(v_fl, jsonb_build_object('good', v_g1, 'qty', 10));
    if coalesce(public.fleet_cargo_qty(v_fl, v_g1code), 0) <> 10 then
      raise exception '0348 self-assert FAIL: the probe did not load 10 %', v_g1code;
    end if;
    with bs as materialized (select world.best_sales(v_fl, v_home) as b),
         mine as (select e from bs, jsonb_array_elements(bs.b->'goods') e where e->>'good' = v_g1code)
    select (select b from bs),
           case when pg_temp.good_board_old_0348(v_g1, v_fl, null, null) is distinct from world.good_board(v_g1, v_fl, null, null) then 'good_board is not its pre-image aboard'
                when (select e->>'basis' from mine) is distinct from 'on_board' then 'the card does not read her cargo'
                when (select e->>'port' from mine) is not null
                     and (select (s->>'profit')::numeric from jsonb_array_elements(world.good_board(v_g1, v_fl, null, null)->'sell') s where s->>'port' = (select e->>'port' from mine))
                         is distinct from (select (e->>'profit')::numeric from mine) then 'the card is not the Sail & sell row' end
      into v_bs, v_bad;
    if v_bad is not null then
      raise exception '0348 self-assert FAIL: her cargo: %', v_bad;
    end if;
    r_d := format('%s aboard: good_board = its pre-image; the card %s', v_g1code,
                  (select e from jsonb_array_elements(v_bs->'goods') e where e->>'good' = v_g1code));

    -- (e) TIMING (a notice; prod is measured in the PR's PROD CHECKS)
    for v_n in 1 .. 3 loop
      v_t := clock_timestamp();
      perform world.best_sales(v_fl, v_home);
      v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000);
    end loop;
    r_e := format('best_sales at %s: %s ms', v_hcode, array_to_string(v_ms, ', '));

    raise exception using errcode = 'ZX348', message = 'PROBE_ROLLBACK_0348';
  exception when sqlstate 'ZX348' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0348 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid = c_uid) then
    raise exception '0348 self-assert FAIL: the probe left rows behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0348 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  raise notice '0348 probe (a): %', r_a;
  raise notice '0348 probe (b): %', r_b;
  raise notice '0348 probe (c): %', r_c;
  raise notice '0348 probe (d): %', r_d;
  raise notice '0348 probe (e): %', r_e;
  raise notice '0348 self-assert ok: EVERY CARD NAMES ITS BEST SALE. world.good_board = its pre-image byte for byte, its pieces moved to board_passages / board_origin / board_amount / board_sell (server only); world.best_sales (STABLE, to authenticated) is good_board''s own row to the coin for every good; one registry row; no other function, knob, table or row moved. % ms.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
