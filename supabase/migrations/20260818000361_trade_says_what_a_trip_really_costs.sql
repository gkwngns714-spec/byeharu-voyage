-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0361 — TRADE SAYS WHAT A TRIP REALLY COSTS: wages, dock fees, supplies and time, one authority. NO TABLE, NO KNOB, NO SWITCH.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-13. 0360 gave the Map's Send fleet a trip's real time and price (world.trip_cost). Its builder reported that Trade disagreed with it,
-- and the owner said "do all": Trade must agree with what is really charged, and with the Map.
--
-- WHAT WAS WRONG ON TRADE'S BOARD (world.good_board and world.best_sales, both through world.board_sell):
--   wages      the day's wage times the days at sea WITH THEIR FRACTION. voyage.settle owes a whole day for every day begun on every leg.
--   dock fee   the destination's alone, for the parcel alone, and never taken off the profit. public.port_call charges every harbour she calls at,
--              on all the cargo aboard at cost.
--   supplies   what her LONGEST leg would buy as her hold stands now. cmd.do_sail buys before every leg, her casks emptier each time.
--   time       the sailing only. A call on the way takes port_prep_seconds while the economy is closed (fleets.ready_at).
--
-- WHAT THIS FILE DOES. One walk of a trip's stores, and every reader of a trip's price asks it:
--   NEW world.trip_stop_seconds()                 the time a call on the way takes (0360's own line, moved here whole)
--   NEW world.trip_hulls(fleet)                   her hulls as a walk reads them (0360's own read, moved here whole; public.supply_needs' reading)
--   NEW world.trip_leg(hulls, nm, speed, ...)     ONE LEG: topped up as cmd.do_sail tops her, its settled days eaten as voyage.settle eats them
--                                                 (0360's own loop, moved here whole). Server only, STABLE, like world.board_legs.
--   RE-CUT world.trip_cost     (3 hunks)          asks those three. ITS ANSWER DOES NOT CHANGE (asserted against its pre-image below).
--   RE-CUT world.board_legs    (3 hunks)          every harbour's row gains the trip there: t_sea (the days settle will owe), t_sup (supplies, her
--                                                 casks walked), t_stop (seconds in port on the way), t_pre (the harbours she calls at with the cargo
--                                                 aboard now) and t_post (those called at after a buy: their dock fee is on the cargo aboard then).
--   RE-CUT world.board_sell    (9 hunks)          wages = the wage for t_sea; supplies.cost = t_sup; dock_fee = every call's public.port_fee;
--                                                 days and arrive_at carry t_stop; profit = proceeds - cost - tax - wages - supplies - dock_fee.
--                                                 New keys: sail_days, stop_seconds, dock_fee.
--   RE-CUT world.good_board    (7 hunks)          its BUY AT rows read the same legs: days and arrive_at carry the calls on the way, supplies.cost
--                                                 is the walked figure. New keys: sail_days, stop_seconds. Her cargo's board hands the legs it asked to
--                                                 world.board_sell (asked once, not twice).
--   world.best_sales is NOT re-cut: it reads world.board_sell's rows, so every card's profit, days and seconds move with them.
--
-- THE SAME FIGURES AS THE MAP. For a trip sailed from where she lies with her own cargo, or a good bought where she lies while the economy is open,
-- a sell row's sail_days, stop_seconds, days, supplies.cost, wages and dock_fee are world.trip_cost's for the same harbours (asserted below, and in
-- scripts/db/proofs/63_trade_true_cost.sql against what the game then charges).
-- WHERE TRADE KNOWS MORE THAN A PLAIN TRIP: a good bought first raises the cargo aboard, so the harbours after the buy charge their dock fee on the
-- cargo aboard now PLUS that buy (public.port_call's own base). world.trip_cost prices a plain trip, on the cargo aboard now.
-- A FLEET AT SEA: the days still to be settled on the voyage under way (voyage.total_days less voyages.last_settled_day) are owed too, and her
-- destination is a call on the way.
--
-- WHAT A PLAYER SEES CHANGE. Wages go up (a day begun is a whole day; never under one a leg). Supplies go up on a trip of several legs. While the
-- economy is closed: the dock fee is every call's, it comes off the profit, and the days and the real time carry a minute a call. Profit therefore
-- goes down by exactly those amounts; nothing is charged that was not charged before.
--
-- WHAT IT DOES NOT KNOW (as 0360): a storm or a calm that lengthens a leg; short rations (the wage is then 1.5 times); the room a buy takes from her
-- stores on the legs after it (the board already buys only what fits beside the longest leg's stores).
--
-- DECIDED BY DEFAULT (the owner may reverse any of these afterwards):
--   * The dock fee comes OFF the profit. Before, it was printed beside the profit and not taken off.
--   * A best sale "within her purse" (0351) now asks the whole trip's supplies of her purse, not the longest leg's: it reads the same row.
--   * `dues` (0237) is untouched: its `fee` is still the destination's for the parcel. The trip's fee is the new `dock_fee`; Trade prints that.
--   * The harbour where she lies costs nothing to "sail" to: no leg, so no supplies (before, a one-day top-up was taken off that row's profit).
--
-- COST: world.board_legs walks every harbour she can reach once a call (the legs are remembered by their way, so a harbour beyond another walks one
-- leg more). world.best_sales asks it twice a call; world.good_board once for her cargo, else twice (the second walked to the sellers alone). The dock fee is
-- asked for the priced rows only, once a harbour and cargo value, and never while the economy is open. Measured in the self-assert (old against new, the
-- same minute) and by scripts/ops/harness/trade-true-cost/paired.mjs.
-- ROLLBACK (forward, owner only): scripts/ops/harness/trade-true-cost/rollback-0361.sql is the draft: the 22 hunks reversed, the three helpers dropped.
-- NEWS: this file posts its own UPDATE row, public.news_update('0361', 'Trade: true trip cost', '교역: 실제 항해 비용') (0347's law).
-- SELF-ASSERT: the catalog, then a probe house of its own rolled-back rows (the economy flags are turned INSIDE the rolled-back probe only).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 90 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- VERSION: 0361, after 0360 (it re-cuts 0360's read). 0355 to 0358 are other branches'; none re-cuts a body this file re-cuts.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t1          timestamptz;
  v_def         text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_rel_before  text;
  v_job_before  text;
  rf            record;
  h             record;
  v_pl          uuid;
  v_fl          uuid;
  v_home        uuid;
  v_hcode       text;
  v_near        record;
  v_legs        jsonb;
  v_old         jsonb;
  v_new         jsonb;
  v_trip        jsonb;
  v_bad         text;
  v_lived       boolean := false;
  gd            record;
  r             record;
  v_rows        int := 0;
  v_chained     int := 0;
  v_cards       int := 0;
  v_fee_rows    int := 0;
  v_fee_max     bigint := 0;
  v_up_wages    bigint := 0;
  v_up_sup      bigint := 0;
  v_stock       numeric;
  v_prep        numeric;
  v_exp         bigint;
  v_ms_old      numeric := 0;
  v_ms_new      numeric := 0;
  v_gb_old      numeric := 0;
  v_gb_new      numeric := 0;
  v_g1          uuid;
  v_g1code      text;
  r_a text; r_b text; r_c text; r_d text; r_e text;
  c_uid   constant uuid := '00000000-0361-4000-8000-000000000001';
  c_recut constant text[] := array['world.trip_cost(uuid,jsonb)', 'world.board_legs(uuid,jsonb)', 'world.board_sell(uuid,uuid,jsonb)',
                                   'world.good_board(uuid,uuid,uuid,numeric)'];
  c_new   constant text[] := array['world.trip_stop_seconds()', 'world.trip_hulls(uuid)', 'world.trip_leg(jsonb,numeric,numeric,boolean,numeric)'];
  -- the keys of a sell row this file moves or adds (every other key of every row is asserted unmoved)
  c_sell_keys constant text[] := array['sail_days', 'stop_seconds', 'wages', 'dock_fee', 'profit', 'net', 'net_per_ton', 'supplies'];
  c_buy_keys  constant text[] := array['sail_days', 'stop_seconds', 'supplies'];
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_recut || array['world.best_sales(uuid,uuid)', 'world.board_origin(uuid)', 'public.supply_needs(uuid,numeric[])',
                                                   'public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)', 'public.stores_cost(uuid,numeric,numeric)',
                                                   'public.npc_leg_days(numeric,numeric)', 'public.port_fee(uuid,uuid,numeric)', 'public.fleet_stock_at_cost(uuid)',
                                                   'public.economy_closed()', 'voyage.total_days(uuid)', 'public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)',
                                                   'cmd.assume_identity(uuid)', 'public.news_update(text,text,text)']) f
              where to_regprocedure(f) is null) then
    raise exception '0361 refuses: 0360 (world.trip_cost), the board''s pieces (0348, 0350) or an authority they compose is not in this world';
  end if;
  if exists (select 1 from unnest(c_new) f where to_regprocedure(f) is not null)
     or (select p.prosrc from pg_proc p where p.oid = 'world.board_sell(uuid,uuid,jsonb)'::regprocedure) like '%t_sea%' then
    raise exception '0361 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0361 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0361
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_recut || array['world.best_sales(uuid,uuid)']) f;
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

  -- ── 2. THE THREE HELPERS: 0360's own lines, moved here whole, so the Map's read and Trade's board walk a trip with one pair of hands ──
  execute $f$
create function world.trip_stop_seconds()
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0361: THE TIME A CALL ON THE WAY TAKES, in real seconds (0360's own line, moved here whole): port_prep_seconds while the economy is closed
  -- (0237: fleets.ready_at = the arrival + that knob), else 0. Read by world.trip_cost and world.board_legs. Server only.
  select case when public.economy_closed() then greatest(coalesce(public.wc_num('port_prep_seconds'), 0), 0) else 0 end
$body$
  $f$;
  execute $f$
create function world.trip_hulls(p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0361: HER HULLS AS A WALK OF HER STORES READS THEM (0360's own read, moved here whole), exactly as public.supply_needs reads them (0225, 0250,
  -- 0345): [{crew, water, food, room, full}], the room her stores may fill and her full mark. Read by world.trip_cost and world.board_legs. Server only.
  select coalesce(jsonb_agg(jsonb_build_object(
           'crew', s.crew, 'water', s.water_t, 'food', s.food_t,
           'room', public.ship_stores_room(s.id, hc.cap - public.ship_cargo_tuns(s.id)),
           'full', public.ship_stores_room(s.id, hc.cap * s.store_ratio))), '[]'::jsonb)
    from public.ships s
   cross join lateral (select public.ship_hold_capacity(s.id) as cap offset 0) hc
   where s.fleet_id = p_fleet
$body$
  $f$;
  execute $f$
create function world.trip_leg(p_hulls jsonb, p_nm numeric, p_speed numeric, p_top boolean default true, p_sea numeric default null)
returns table(hulls jsonb, water_t numeric, food_t numeric, sea_days numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0361: ONE LEG OF A TRIP, WALKED (0360's own loop, moved here whole; world.trip_cost and world.board_legs ask it). Every hull of p_hulls
-- (world.trip_hulls) is topped up for a leg of p_nm at p_speed as cmd.do_sail tops her (public.stores_topup to public.npc_leg_days), then the leg's
-- settled days are eaten at water_per_crew_day and food_per_crew_day a crew, as voyage.settle eats them: every day begun is a day settled
-- (voyage.total_days: the hours over 24, rounded up, never under one). Answers her hulls as she arrives, the tuns of water and food the top-up took
-- on (public.stores_cost prices them), and the days settled (public.fleet_wage is owed for each).
--   p_top false  nothing is bought (a voyage already under way: she provisioned when she left)
--   p_sea        the days to settle, when the caller knows them (a voyage under way: what is left of it)
declare
  v_wpd  numeric := public.wc_num('water_per_crew_day');
  v_fpd  numeric := public.wc_num('food_per_crew_day');
  v_top  numeric := public.npc_leg_days(p_nm, p_speed);
  v_w    numeric;
  v_f    numeric;
  h      record;
begin
  sea_days := coalesce(p_sea, greatest(1, ceil(p_nm / p_speed / 24)));   -- voyage.total_days: every day begun is settled, never under one
  water_t := 0;
  food_t := 0;
  hulls := '[]'::jsonb;
  for h in select * from jsonb_to_recordset(p_hulls) x(crew numeric, water numeric, food numeric, room numeric, "full" numeric) loop
    v_w := 0;
    v_f := 0;
    if p_top then
      select tu.water_t, tu.food_t into v_w, v_f from public.stores_topup(h.crew, h.water, h.food, h.room, v_top, h."full") tu;
    end if;
    water_t := water_t + coalesce(v_w, 0);
    food_t := food_t + coalesce(v_f, 0);
    hulls := hulls || jsonb_build_array(jsonb_build_object(
      'crew', h.crew,
      'water', greatest(0, coalesce(h.water, 0) + coalesce(v_w, 0) - coalesce(h.crew, 0) * v_wpd * sea_days),
      'food',  greatest(0, coalesce(h.food, 0) + coalesce(v_f, 0) - coalesce(h.crew, 0) * v_fpd * sea_days),
      'room', h.room, 'full', h."full"));
  end loop;
  return next;
end
$body$
  $f$;
  revoke all on function world.trip_stop_seconds() from public, anon, authenticated;
  revoke all on function world.trip_hulls(uuid) from public, anon, authenticated;
  revoke all on function world.trip_leg(jsonb, numeric, numeric, boolean, numeric) from public, anon, authenticated;
  comment on function world.trip_stop_seconds() is '0361: the real seconds a call on the way takes (port_prep_seconds while the economy is closed, else 0). Server only.';
  comment on function world.trip_hulls(uuid) is '0361: a fleet''s hulls as a walk of her stores reads them. Server only.';
  comment on function world.trip_leg(jsonb, numeric, numeric, boolean, numeric) is
    '0361: one leg of a trip walked: topped up as cmd.do_sail tops her, its settled days eaten as voyage.settle eats them. Server only.';

  -- ── 3. THE HUNKS (each once on the live body, and reversing) ──
  create temp table hunks_0361 (fn text, n int, old text, new text) on commit drop;
  insert into hunks_0361 values
('world.trip_cost(uuid,jsonb)', 1,
$h$  v_prep   numeric := case when public.economy_closed() then greatest(coalesce(public.wc_num('port_prep_seconds'), 0), 0) else 0 end;
$h$,
$h$  v_prep   numeric := world.trip_stop_seconds();   -- 0361: the one reading of a call's time (Trade's board reads it too)
$h$),
('world.trip_cost(uuid,jsonb)', 2,
$h$  select coalesce(jsonb_agg(jsonb_build_object(
           'crew', s.crew, 'water', s.water_t, 'food', s.food_t,
           'room', public.ship_stores_room(s.id, hc.cap - public.ship_cargo_tuns(s.id)),
           'full', public.ship_stores_room(s.id, hc.cap * s.store_ratio))), '[]'::jsonb)
    into v_hulls
    from public.ships s
   cross join lateral (select public.ship_hold_capacity(s.id) as cap offset 0) hc
   where s.fleet_id = p_fleet;
$h$,
$h$  v_hulls := world.trip_hulls(p_fleet);   -- 0361: moved there whole (Trade's board reads it too)
$h$),
('world.trip_cost(uuid,jsonb)', 3,
$h$    v_top := public.npc_leg_days(v_nm, v_speed);
    v_sea := greatest(1, ceil(v_nm / v_speed / 24));   -- voyage.total_days: every day begun is settled, never under one
    v_w := 0;
    v_f := 0;
    v_next := '[]'::jsonb;
    for h in select * from jsonb_to_recordset(v_hulls) x(crew numeric, water numeric, food numeric, room numeric, "full" numeric) loop
      select tu.water_t, tu.food_t into t from public.stores_topup(h.crew, h.water, h.food, h.room, v_top, h."full") tu;
      v_w := v_w + coalesce(t.water_t, 0);
      v_f := v_f + coalesce(t.food_t, 0);
      v_next := v_next || jsonb_build_array(jsonb_build_object(
        'crew', h.crew,
        'water', greatest(0, coalesce(h.water, 0) + coalesce(t.water_t, 0) - coalesce(h.crew, 0) * v_wpd * v_sea),
        'food',  greatest(0, coalesce(h.food, 0) + coalesce(t.food_t, 0) - coalesce(h.crew, 0) * v_fpd * v_sea),
        'room', h.room, 'full', h."full"));
    end loop;
    v_hulls := v_next;
$h$,
$h$    -- 0361: world.trip_leg, this loop moved there whole (Trade's board walks a trip with it too)
    select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_hulls, v_w, v_f, v_sea from world.trip_leg(v_hulls, v_nm, v_speed) tl;
$h$),
('world.board_legs(uuid,jsonb)', 1,
$h$-- bought first at src.code), and src_passages (the passages from the buy city, when the caller has them; else asked here). Nothing of the good, the amount or the prices.
$h$,
$h$-- bought first at src.code), and src_passages (the passages from the buy city, when the caller has them; else asked here). Nothing of the good, the amount or the prices.
-- 0361: AND THE TRIP THERE, AS THE GAME WILL CHARGE IT (owner 2026-11-13; world.trip_cost's own walk, world.trip_leg). A row she has a passage to gains
--   t_stop  the real seconds she lies in port on the way (world.trip_stop_seconds a call: every harbour before the last, the buy city among them)
--   t_sea   the days voyage.settle will owe wages for: every day begun on every leg, and what is left of a voyage under way
--   t_sup   her supplies, her casks walked along the trip (topped up before each leg, the leg's settled days eaten)
--   t_pre   the harbours she calls at carrying the cargo aboard now, in order (codes): all of them when she sells her cargo; up to and with the buy
--           city when the good is bought first. t_post: the harbours called at after that buy. world.board_sell asks public.port_fee of each, for the
--           rows it prices (the fee after a buy is on the cargo aboard then)
-- It also reads of p_ctx: speed and where.kind (world.board_origin's), and `only` (harbour ids: the trip is walked to those alone, for a reader of a few rows; the
-- rest keep the columns they had). A leg the sailed-distance table cannot measure leaves t_sea .. t_post out.
$h$),
('world.board_legs(uuid,jsonb)', 2,
$h$  v_legs    jsonb;
$h$,
$h$  v_legs    jsonb;
  -- 0361: the trip to every harbour
  v_onb     boolean := coalesce((p_ctx->>'basis') = 'on_board', false);
  v_kind    text := p_ctx->'where'->>'kind';
  v_speed   numeric := greatest(coalesce((p_ctx->>'speed')::numeric, 0), 0.1);
  v_prep    numeric := world.trip_stop_seconds();
  v_ocode   text;
  v_hulls   jsonb;
  v_lead    boolean := false;       -- she is not in a berth: her way to the harbour her passages run from comes first
  v_h0      jsonb;
  v_sup0    bigint := 0;
  v_sea0    numeric := 0;
  v_skip    int := coalesce(cardinality(v_lead_stops), 0);
  v_pre     text[] := '{}';         -- bought first elsewhere: the harbours to the buy city, and it
  v_seq     text[];
  v_key     text;
  -- a way already walked, by its harbours in order: her hulls there, the supplies and the days settled so far
  m_key     text[] := '{}';
  m_h       jsonb[] := '{}';
  m_s       bigint[] := '{}';
  m_d       numeric[] := '{}';
  v_pos     int;
  v_k       int;
  v_xid     uuid[] := '{}';
  v_only    uuid[] := case when jsonb_typeof(p_ctx->'only') = 'array' then array(select jsonb_array_elements_text(p_ctx->'only')::uuid) end;
  v_xj      jsonb[] := '{}';
  v_from    text;
  v_to      text;
  v_nm      numeric;
  v_w       numeric;
  v_f       numeric;
  v_sea     numeric;
  v_h       jsonb;
  v_sup     bigint;
  v_seas    numeric;
  v_ok      boolean;
  v_npre    int;
  v_m       jsonb;
  v_n       int;
  ti        int;
  tr        record;
$h$),
('world.board_legs(uuid,jsonb)', 3,
$h$    from legs c left join needs n on n.nm is not distinct from c.max_leg;
  return v_legs;
$h$,
$h$    from legs c left join needs n on n.nm is not distinct from c.max_leg;

  -- 0361: THE TRIP TO EVERY HARBOUR SHE HAS A PASSAGE TO, walked as world.trip_cost walks it (world.trip_leg), each way walked once
  v_ocode := (select p.code from public.ports p where p.id = v_origin);
  v_hulls := world.trip_hulls(p_fleet);
  v_h0 := v_hulls;
  if v_origin is not null and v_kind = 'sailing' then
    -- a voyage under way: what is left of it to settle is owed too; nothing more is bought for it
    select greatest(0, voyage.total_days(v.id) - v.last_settled_day) into v_n
      from public.voyages v where v.fleet_id = p_fleet and v.status = 'SAILING' order by v.departed_at desc limit 1;
    select tl.hulls, tl.sea_days into v_h0, v_sea0 from world.trip_leg(v_hulls, 0, v_speed, false, coalesce(v_n, 0)) tl;
    v_lead := true;
  elsif v_origin is not null and v_kind = 'at_sea' and v_lead_nm > 0 then
    -- at anchor: the miles to the nearest harbour are her first leg (0183)
    select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_h0, v_w, v_f, v_sea0 from world.trip_leg(v_hulls, v_lead_nm, v_speed) tl;
    v_sup0 := public.stores_cost(v_player, v_w, v_f);
    v_lead := true;
  end if;
  if not v_onb and v_src_id is not null and v_src_id is distinct from v_origin then
    select array(select jsonb_array_elements_text(e->'stops')) || v_src.code into v_pre
      from jsonb_array_elements(v_passages) e
     where (e->>'port_id')::uuid = v_src_id and jsonb_typeof(e->'nm') = 'number' and jsonb_typeof(e->'stops') = 'array';
    v_pre := coalesce(v_pre, '{}');   -- no passage to the buy city: no row below has miles
  end if;
  for tr in
    select l.id, p.code, l.stops, l.max_leg
      from jsonb_to_recordset(v_legs) l(id uuid, nm numeric, stops text[], max_leg numeric)
      join public.ports p on p.id = l.id
     where l.nm is not null and (v_only is null or l.id = any (v_only))
     order by coalesce(cardinality(l.stops), 0), p.code
  loop
    -- the harbours she arrives at, in order: her cargo sailed from where she is; or to the buy city first, then on
    v_seq := case when v_onb then case when tr.id = v_origin then '{}'::text[] else coalesce(tr.stops[v_skip + 1:], '{}') || tr.code end
                  else v_pre || case when tr.id = v_src_id then '{}'::text[] else coalesce(tr.stops, '{}') || tr.code end end;
    v_m := jsonb_build_object('t_stop', v_prep * greatest(case when v_lead then 1 else 0 end + coalesce(cardinality(v_seq), 0) - 1, 0));
    if tr.max_leg is not null then
      v_key := case when v_lead then 'L' else '' end;
      v_h := v_h0; v_sup := v_sup0; v_seas := v_sea0; v_ok := true;
      v_n := coalesce(cardinality(v_seq), 0);
      v_k := 0;
      -- the way to the harbour before this one is, nearly always, walked already (the rows come nearest in calls first): take it up from the longest way walked
      for ti in reverse v_n - 1 .. 1 loop
        v_pos := array_position(m_key, v_key || '>' || array_to_string(v_seq[1:ti], '>'));
        if v_pos is not null then
          v_key := m_key[v_pos]; v_h := m_h[v_pos]; v_sup := m_s[v_pos]; v_seas := m_d[v_pos];
          v_k := ti;
          exit;
        end if;
      end loop;
      for ti in v_k + 1 .. v_n loop
        v_from := case when ti = 1 then v_ocode else v_seq[ti - 1] end;
        v_to := v_seq[ti];
        v_key := v_key || '>' || v_to;
        -- the leg's sailed miles: public.sea_reaches, the table voyage.reach_from and voyage.reach_passage read
        select (sr.reaches->>v_to)::numeric into v_nm from public.sea_reaches sr where sr.code = v_from;
        if v_nm is null or v_nm <= 0 then
          v_ok := false;
          exit;
        end if;
        select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_h, v_w, v_f, v_sea from world.trip_leg(v_h, v_nm, v_speed) tl;
        v_sup := v_sup + public.stores_cost(v_player, v_w, v_f);
        v_seas := v_seas + v_sea;
        m_key := m_key || v_key; m_h := m_h || v_h; m_s := m_s || v_sup; m_d := m_d || v_seas;
      end loop;
      if v_ok then
        -- the harbours she arrives at with the cargo aboard now, and those after the buy
        v_npre := case when v_onb then v_n else coalesce(cardinality(v_pre), 0) end;
        v_m := v_m || jsonb_build_object('t_sea', v_seas, 't_sup', v_sup,
                 't_pre', to_jsonb(case when v_lead then array[v_ocode] else '{}'::text[] end || v_seq[1:v_npre]),
                 't_post', to_jsonb(v_seq[v_npre + 1:]));
      end if;
    end if;
    v_xid := v_xid || tr.id;
    v_xj := v_xj || v_m;
  end loop;
  select coalesce(jsonb_agg(e || coalesce(x.j, '{}'::jsonb)), '[]'::jsonb) into v_legs
    from jsonb_array_elements(v_legs) e
    left join unnest(v_xid, v_xj) x(id, j) on x.id = (e->>'id')::uuid;
  return v_legs;
$h$),
('world.board_sell(uuid,uuid,jsonb)', 1,
$h$-- has them (world.best_sales: once for every good) hands them over as `legs`, else they are asked here. THE PRICES are world.good_mids': every buyer's mid in one pass, not one call a harbour.
$h$,
$h$-- has them (world.best_sales: once for every good) hands them over as `legs`, else they are asked here. THE PRICES are world.good_mids': every buyer's mid in one pass, not one call a harbour.
-- 0361: A ROW SAYS WHAT THE TRIP REALLY COSTS (owner 2026-11-13: Trade agrees with what is charged, and with the Map's world.trip_cost). From world.board_legs' trip (world.trip_leg's walk):
-- wages = the day's wage for every day voyage.settle will owe (t_sea), not the days with their fraction; supplies.cost = her casks walked along the trip (t_sup), not the longest leg's top-up;
-- dock_fee = public.port_fee of every harbour called at (t_pre on the cargo aboard now, t_post on the cargo aboard after the buy; each asked once); days and arrive_at carry the calls on the way (t_stop); profit takes all of them off.
-- New keys: sail_days (the sailing alone), stop_seconds, dock_fee. `dues` (0237) is unmoved: its fee is the destination's for the parcel alone.
$h$),
('world.board_sell(uuid,uuid,jsonb)', 2,
$h$  v_legs    jsonb := p_ctx->'legs';   -- 0350: world.board_legs' answer, when the caller has it
$h$,
$h$  v_legs    jsonb := p_ctx->'legs';   -- 0350: world.board_legs' answer, when the caller has it
  v_closed  boolean := public.economy_closed();   -- 0361: open, public.port_fee is 0 everywhere, so it is not asked
  v_stock   numeric := case when v_closed then public.fleet_stock_at_cost(p_fleet) end;   -- 0361: the cargo aboard now at cost (public.port_call's base)
$h$),
('world.board_sell(uuid,uuid,jsonb)', 3,
$h$           l.sn_days, l.sn_tons, l.sn_cost, l.sn_fits, l.sn_hold   -- 0225; sn_hold: the room those stores take in her hold (public.stores_in_hold), read once a leg
$h$,
$h$           l.sn_days, l.sn_tons, l.sn_cost, l.sn_fits, l.sn_hold,   -- 0225; sn_hold: the room those stores take in her hold (public.stores_in_hold), read once a leg
           l.t_sea, l.t_sup, l.t_stop, l.t_pre, l.t_post   -- 0361: the trip there, as the game will charge it (world.board_legs)
$h$),
('world.board_sell(uuid,uuid,jsonb)', 4,
$h$                                        sn_days numeric, sn_tons numeric, sn_cost bigint, sn_fits boolean, sn_hold numeric) on l.id = p.id
$h$,
$h$                                        sn_days numeric, sn_tons numeric, sn_cost bigint, sn_fits boolean, sn_hold numeric,
                                        t_sea numeric, t_sup bigint, t_stop numeric, t_pre text[], t_post text[]) on l.id = p.id   -- 0361
$h$),
('world.board_sell(uuid,uuid,jsonb)', 5,
$h$           case when r.nm is not null and v_speed > 0 then (v_lead_nm + r.nm) / v_speed / 24 end as days,
           case when r.nm is not null and v_speed > 0
                then v_lead_at + make_interval(secs => (r.nm / v_speed * 3600 / v_tc)::double precision) end as arrive_at
$h$,
$h$           case when r.nm is not null and v_speed > 0 then (v_lead_nm + r.nm) / v_speed / 24 end as days,
           r.t_sea, r.t_pre, r.t_post,   -- 0361
           case when r.nm is not null and v_speed > 0   -- 0361: + the real seconds in port on the way
                then v_lead_at + make_interval(secs => (r.nm / v_speed * 3600 / v_tc + coalesce(r.t_stop, 0))::double precision) end as arrive_at
$h$),
('world.board_sell(uuid,uuid,jsonb)', 6,
$h$  ), priced as materialized (
    select q.*,
           public.profit_tax(q.id, case when q.cost is null then null else q.proceeds - q.cost end, v_player) as tax,
           case when q.days is null then null else round(v_wage * q.days) end as wages,
$h$,
$h$  ), fees as materialized (
    -- 0361: THE DOCK FEE of every harbour a priced row calls at, public.port_fee asked ONCE for each harbour and cargo value: the cargo aboard now up to the
    -- buy (t_pre), that and the row's own buy after it (t_post): public.port_call's base. Open: nothing is asked (the fee is 0 everywhere)
    select d.code, d.v, public.port_fee(p.id, v_player, d.v) as fee
      from (select distinct u.code, case when u.post then v_stock + coalesce(q.cost, 0) else v_stock end as v
              from quoted q
             cross join lateral (select x, false from unnest(q.t_pre) x union all select x, true from unnest(q.t_post) x) u(code, post)
             where v_closed and q.t_sea is not null) d
      join public.ports p on p.code = d.code and p.kind = 'HARBOUR'
  ), priced as materialized (
    select q.*,
           public.profit_tax(q.id, case when q.cost is null then null else q.proceeds - q.cost end, v_player) as tax,
           -- 0361: the day's wage for every day voyage.settle will owe (a day begun is a day owed), as world.trip_cost says it
           case when q.days is null or q.t_sea is null then null else round(v_wage * q.t_sea) end as wages,
           case when q.t_sea is null then null
                when not v_closed then 0
                else (select coalesce(sum(f.fee), 0)::bigint
                        from (select x, v_stock from unnest(q.t_pre) x union all select x, v_stock + coalesce(q.cost, 0) from unnest(q.t_post) x) u(code, v)
                        join fees f on f.code = u.code and f.v = u.v) end as dock_fee,
$h$),
('world.board_sell(uuid,uuid,jsonb)', 7,
$h$                            then jsonb_build_object('days', round(r.sn_days, 1), 'cost', r.sn_cost, 'fits', r.sn_fits,
$h$,
$h$                            then jsonb_build_object('days', round(r.sn_days, 1), 'cost', coalesce(r.t_sup, r.sn_cost), 'fits', r.sn_fits,   -- 0361: walked along the trip
$h$),
('world.board_sell(uuid,uuid,jsonb)', 8,
$h$                          then p.proceeds - p.cost - p.tax - p.wages - r.sn_cost end,   -- 0225: the net less the supplies
$h$,
$h$                          then p.proceeds - p.cost - p.tax - p.wages - r.t_sup - p.dock_fee end,   -- 0225: the net less the supplies; 0361: the trip's supplies, and its dock fees
$h$),
('world.board_sell(uuid,uuid,jsonb)', 9,
$h$           'days', case when r.nm is not null and v_speed > 0 then round((v_lead_nm + r.nm) / v_speed / 24, 2) end,
           'arrive_at', p.arrive_at,
           'units', case when p.id is not null then p.n end,   -- 0348: the row's own units (the board's one amount, unless FIT)
           'price_each', p.avg_price, 'proceeds', p.proceeds, 'cost', p.cost, 'profit_tax', p.tax,
           'port_fee', p.spread_total, 'wages', p.wages,
$h$,
$h$           -- 0361: the whole trip in voyage-days: the sailing, and the calls on the way at time_compression (world.trip_cost's `days`)
           'days', case when r.nm is not null and v_speed > 0 then round((v_lead_nm + r.nm) / v_speed / 24 + coalesce(r.t_stop, 0) * v_tc / 86400, 2) end,
           'sail_days', case when r.nm is not null and v_speed > 0 then round((v_lead_nm + r.nm) / v_speed / 24, 2) end,
           'stop_seconds', case when r.nm is not null then coalesce(r.t_stop, 0) end,
           'arrive_at', p.arrive_at,
           'units', case when p.id is not null then p.n end,   -- 0348: the row's own units (the board's one amount, unless FIT)
           'price_each', p.avg_price, 'proceeds', p.proceeds, 'cost', p.cost, 'profit_tax', p.tax,
           'port_fee', p.spread_total, 'wages', p.wages, 'dock_fee', p.dock_fee,
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$-- 0348: its opening, its amount and its sell rows are world.board_origin, world.board_amount and world.board_sell (the one authority world.best_sales reads too).
$h$,
$h$-- 0348: its opening, its amount and its sell rows are world.board_origin, world.board_amount and world.board_sell (the one authority world.best_sales reads too).
-- 0361: a row says what the trip really costs. The sell rows are world.board_sell's (wages, supplies, dock_fee, days: see there). A BUY AT row's days and arrive_at
-- carry the calls on the way and its supplies.cost is her casks walked along the trip, from the same world.board_legs; new keys sail_days and stop_seconds.
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 2,
$h$  v_o       jsonb;                  -- 0348: world.board_origin's answer
$h$,
$h$  v_o       jsonb;                  -- 0348: world.board_origin's answer
  v_trips   jsonb;                  -- 0361: her cargo's board: world.board_legs for a trip from where she is (the BUY AT rows' trip, and the sell rows')
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 3,
$h$  v_passages := v_o->'passages';   -- 0205: the passages from where she sails, asked once (world.board_passages)
$h$,
$h$  v_passages := v_o->'passages';   -- 0205: the passages from where she sails, asked once (world.board_passages)
  if v_basis = 'on_board' then   -- 0361: her cargo is sailed from where she is: the trip to every harbour, asked once for the buy rows and the sell rows
    v_trips := world.board_legs(p_fleet, v_o || jsonb_build_object('basis', 'on_board'));
  end if;
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 4,
$h$  ), timed as materialized (
    select s.*,
           case when s.nm is not null and v_speed > 0
                then v_lead_at + make_interval(secs => (s.nm / v_speed * 3600 / v_tc)::double precision) end as arrive_at
      from sellers s
$h$,
$h$  ), trips as materialized (
    -- 0361: THE TRIP TO EACH SELLER from where she is (world.board_legs, world.trip_leg's walk): asked above for her cargo's board; else walked to the sellers alone
    select x.id, x.t_stop, x.t_sup
      from jsonb_to_recordset(coalesce(v_trips, world.board_legs(p_fleet, v_o || jsonb_build_object('basis', 'on_board',
             'only', (select coalesce(jsonb_agg(s0.id), '[]'::jsonb) from sellers s0))))) x(id uuid, t_stop numeric, t_sup bigint)
  ), timed as materialized (
    select s.*, tl.t_stop, tl.t_sup,   -- 0361
           case when s.nm is not null and v_speed > 0   -- 0361: + the real seconds in port on the way
                then v_lead_at + make_interval(secs => (s.nm / v_speed * 3600 / v_tc + coalesce(tl.t_stop, 0))::double precision) end as arrive_at
      from sellers s
      left join trips tl on tl.id = s.id
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 5,
$h$           'supplies', (select jsonb_build_object('days', round(sn.days, 1), 'cost', sn.cost, 'fits', sn.fits)
$h$,
$h$           'supplies', (select jsonb_build_object('days', round(sn.days, 1), 'cost', coalesce(s.t_sup, sn.cost), 'fits', sn.fits)   -- 0361: walked along the trip
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 6,
$h$           'days', case when s.nm is not null and v_speed > 0 then round((v_lead_nm + s.nm) / v_speed / 24, 2) end,
$h$,
$h$           -- 0361: the whole trip in voyage-days: the sailing, and the calls on the way at time_compression
           'days', case when s.nm is not null and v_speed > 0 then round((v_lead_nm + s.nm) / v_speed / 24 + coalesce(s.t_stop, 0) * v_tc / 86400, 2) end,
           'sail_days', case when s.nm is not null and v_speed > 0 then round((v_lead_nm + s.nm) / v_speed / 24, 2) end,
           'stop_seconds', case when s.nm is not null then coalesce(s.t_stop, 0) end,
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 7,
$h$              'src_cut', v_src_cut, 'src_name', v_src_name, 'fit', false, 'lean', false));
$h$,
$h$              'src_cut', v_src_cut, 'src_name', v_src_name, 'fit', false, 'lean', false)
              -- 0361: her cargo is sailed from where she is: those are the legs asked above, handed over (asked once)
              || case when v_basis = 'on_board' then jsonb_build_object('legs', v_trips) else '{}'::jsonb end);
$h$);

  for rf in select * from pre_0361 p where p.fn = any (c_recut) order by 1 loop
    v_def := rf.def;
    for h in select * from hunks_0361 x where x.fn = rf.fn order by n loop
      v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
      if v_n <> 1 then
        raise exception '0361 self-assert FAIL: % hunk % occurs % time(s), not once: the deployed body is not what this file was written against', rf.fn, h.n, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(rf.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0361 x where x.fn = rf.fn order by n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception '0361 self-assert FAIL: % new hunk % is not in the live body once', rf.fn, h.n;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> rf.def then
      raise exception '0361 self-assert FAIL: % does not reverse to its pre-image', rf.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = rf.fn::regprocedure) <> rf.meta then
      raise exception '0361 self-assert FAIL: % changed its ACL, volatility, definer, config or owner', rf.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0361) <> 22 or (select count(distinct x.fn) from hunks_0361 x join pre_0361 p on p.fn = x.fn) <> 4 then
    raise exception '0361 self-assert FAIL: the hunks are not the 22 of the four re-cut bodies';
  end if;

  -- ── 4. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select f::regprocedure::oid from unnest(c_recut || c_new) f))) <> v_fn_before then
    raise exception '0361 self-assert FAIL: a function other than the four re-cut bodies and the three helpers moved (world.best_sales among them must not)';
  end if;
  if exists (select 1 from unnest(c_new) f join pg_proc p on p.oid = f::regprocedure
              where p.provolatile <> 's' or not p.prosecdef or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                 or coalesce(p.proconfig::text, '') is distinct from (select coalesce(q.proconfig::text, '') from pg_proc q where q.oid = 'world.board_legs(uuid,jsonb)'::regprocedure)) then
    raise exception '0361 self-assert FAIL: a helper is not STABLE, definer, server only, with world.board_legs'' search path';
  end if;
  -- ONE WALK: the top-up and the eating are in world.trip_leg and nowhere else among the readers of a trip
  if (select p.prosrc from pg_proc p where p.oid = 'world.trip_cost(uuid,jsonb)'::regprocedure) like '%stores_topup(%'
     or (select p.prosrc from pg_proc p where p.oid = 'world.board_legs(uuid,jsonb)'::regprocedure) like '%stores_topup(%'
     or (select p.prosrc from pg_proc p where p.oid = 'world.board_sell(uuid,uuid,jsonb)'::regprocedure) like '%v_wage * q.days%'
     or (select p.prosrc from pg_proc p where p.oid = 'world.trip_cost(uuid,jsonb)'::regprocedure) not like '%world.trip_leg(%'
     or (select p.prosrc from pg_proc p where p.oid = 'world.board_legs(uuid,jsonb)'::regprocedure) not like '%world.trip_leg(%' then
    raise exception '0361 self-assert FAIL: a reader of a trip still walks her stores itself, or the board still pays wages by the fraction';
  end if;
  if not has_function_privilege('authenticated', 'world.good_board(uuid,uuid,uuid,numeric)', 'execute') or not has_function_privilege('authenticated', 'world.trip_cost(uuid,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'world.board_sell(uuid,uuid,jsonb)', 'execute') or has_function_privilege('authenticated', 'world.board_legs(uuid,jsonb)', 'execute') then
    raise exception '0361 self-assert FAIL: a grant moved: the two reads to authenticated, the pieces server only';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0361 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_def;
    if v_def is distinct from v_job_before then
      raise exception '0361 self-assert FAIL: a cron job moved: this file schedules nothing';
    end if;
  end if;

  -- ── 5. THE SELF-ASSERT: a probe house of its own rows, every one rolled back. Only the probe's own answers are asserted. ──
  begin
    -- the bodies BEFORE this file, kept as pg_temp copies of the pre-images (rolled back with the probe); each old body asks the old pieces
    execute replace((select def from pre_0361 where fn = 'world.trip_cost(uuid,jsonb)'), 'FUNCTION world.trip_cost(', 'FUNCTION pg_temp.trip_cost_old_0361(');
    execute replace((select def from pre_0361 where fn = 'world.board_legs(uuid,jsonb)'), 'FUNCTION world.board_legs(', 'FUNCTION pg_temp.board_legs_old_0361(');
    execute replace(replace((select def from pre_0361 where fn = 'world.board_sell(uuid,uuid,jsonb)'), 'FUNCTION world.board_sell(', 'FUNCTION pg_temp.board_sell_old_0361('),
                    'world.board_legs(', 'pg_temp.board_legs_old_0361(');
    execute replace(replace((select def from pre_0361 where fn = 'world.good_board(uuid,uuid,uuid,numeric)'), 'FUNCTION world.good_board(', 'FUNCTION pg_temp.good_board_old_0361('),
                    'world.board_sell(', 'pg_temp.board_sell_old_0361(');
    execute replace(replace(replace((select def from pre_0361 where fn = 'world.best_sales(uuid,uuid)'), 'FUNCTION world.best_sales(', 'FUNCTION pg_temp.best_sales_old_0361('),
                    'world.board_sell(', 'pg_temp.board_sell_old_0361('), 'world.board_legs(', 'pg_temp.board_legs_old_0361(');

    update public.world_config set value = 'false'::jsonb where key = 'economy_closed';   -- a founding is refused on a closed economy (as 0311's probe); rolled back with the probe
    v_pl := public.new_house(c_uid, 'Casa do Custo 0361', 'PRT');
    select f.id, f.port_id into v_fl, v_home from public.fleets f where f.player_id = v_pl;
    v_hcode := (select p.code from public.ports p where p.id = v_home);
    if v_home is null then
      raise exception '0361 self-assert FAIL: the probe company lies at no harbour';
    end if;
    update public.ships s set water_t = 0, food_t = 0 where s.fleet_id = v_fl;   -- empty casks: every leg must buy
    perform cmd.assume_identity(c_uid);

    -- (a) world.trip_cost IS WHAT IT WAS: its pre-image and the re-cut body answer the same, to the byte, open and closed, one leg and out and home
    select r2.port_id, r2.code, r2.nm into v_near
      from voyage.reach_from(v_home) r2 join public.ports p on p.id = r2.port_id
     where p.kind = 'HARBOUR' and r2.nm / greatest(voyage.fleet_speed(v_fl), 0.1) / 24 >= 1 and (select n.fits from public.supply_need(v_fl, r2.nm) n)
     order by r2.nm limit 1;
    if v_near.port_id is null then
      raise exception '0361 self-assert FAIL: the probe has no harbour a day away that her stores fit';
    end if;
    for v_n in 1 .. 2 loop
      update public.world_config set value = to_jsonb(v_n = 2) where key in ('economy_closed', 'city_treasury_enabled');
      for v_legs in
        select x.l from (values (jsonb_build_array(jsonb_build_object('from', v_hcode, 'to', v_near.code))),
                                (jsonb_build_array(jsonb_build_object('from', v_hcode, 'to', v_near.code), jsonb_build_object('from', v_near.code, 'to', v_hcode))),
                                (jsonb_build_array(jsonb_build_object('from', v_hcode, 'to', v_near.code), jsonb_build_object('from', v_near.code, 'to', 'NO SUCH 0361')))) x(l)
      loop
        v_old := pg_temp.trip_cost_old_0361(v_fl, v_legs);
        v_new := world.trip_cost(v_fl, v_legs);
        if v_old is null or v_new is distinct from v_old then
          raise exception '0361 self-assert FAIL: world.trip_cost moved (closed %): before % after %', v_n = 2, v_old, v_new;
        end if;
      end loop;
    end loop;
    r_a := format('world.trip_cost is its pre-image on 6 trips (open and closed; one leg, out and home, an unknown harbour)');
    update public.world_config set value = 'false'::jsonb where key in ('economy_closed', 'city_treasury_enabled');

    -- (b) OPEN, A GOOD BOUGHT WHERE SHE LIES. Every key this file does not name is what it was on every row (the row set, the prices, the proceeds, the tax,
    -- the estimate, the days and arrive_at with no port time). A row she can sail to and that is priced is world.trip_cost's trip through the same harbours.
    for gd in
      select g.id, g.code from public.port_goods pg join public.goods g on g.id = pg.good_id
       where pg.port_id = v_home and public.port_offers(v_home, g.id) order by g.code limit 2
    loop
      v_t1 := clock_timestamp(); v_old := pg_temp.good_board_old_0361(gd.id, v_fl, v_home, null); v_gb_old := v_gb_old + extract(epoch from clock_timestamp() - v_t1) * 1000;
      v_t1 := clock_timestamp(); v_new := world.good_board(gd.id, v_fl, v_home, null); v_gb_new := v_gb_new + extract(epoch from clock_timestamp() - v_t1) * 1000;
      if (v_new - 'buy' - 'sell') is distinct from (v_old - 'buy' - 'sell')
         or jsonb_array_length(v_new->'sell') <> jsonb_array_length(v_old->'sell') or jsonb_array_length(v_new->'buy') <> jsonb_array_length(v_old->'buy') then
        raise exception '0361 self-assert FAIL: % board: something outside its rows moved, or a row came or went', gd.code;
      end if;
      select string_agg(n.e->>'port', ', ') into v_bad
        from jsonb_array_elements(v_new->'sell') n(e)
        left join jsonb_array_elements(v_old->'sell') o(e) on o.e->>'port' = n.e->>'port'
       where o.e is null or (n.e - c_sell_keys) is distinct from (o.e - c_sell_keys)
          or ((n.e->'supplies') - 'cost') is distinct from ((o.e->'supplies') - 'cost')
          or (n.e->>'stop_seconds')::numeric is distinct from case when jsonb_typeof(n.e->'miles') = 'number' then 0 end
          or (n.e->'sail_days') is distinct from (n.e->'days')
          or (jsonb_typeof(n.e->'wages') = 'number' and (n.e->>'wages')::numeric < (o.e->>'wages')::numeric)                     -- a day begun is a whole day: never less
          or (jsonb_typeof(n.e->'net') = 'number' and (n.e->>'net')::numeric <> (n.e->>'proceeds')::numeric - (n.e->>'cost')::numeric - (n.e->>'profit_tax')::numeric - (n.e->>'wages')::numeric)
          or (jsonb_typeof(n.e->'profit') = 'number' and (n.e->>'profit')::numeric <> (n.e->>'net')::numeric - (n.e->'supplies'->>'cost')::numeric - (n.e->>'dock_fee')::numeric)
          or jsonb_typeof(n.e->'profit') is distinct from jsonb_typeof(o.e->'profit') or jsonb_typeof(n.e->'wages') is distinct from jsonb_typeof(o.e->'wages')
          or (jsonb_typeof(n.e->'wages') = 'number' and (n.e->>'dock_fee')::numeric <> 0)
          -- one leg, nothing walked further: the supplies are the leg's own top-up, as before
          or (jsonb_array_length(coalesce(nullif(n.e->'stops', 'null'::jsonb), '[]'::jsonb)) = 0 and n.e->>'port' <> v_hcode and jsonb_typeof(n.e->'miles') = 'number'
              and (n.e->'supplies'->>'cost') is distinct from (o.e->'supplies'->>'cost'));
      if v_bad is not null then
        raise exception '0361 self-assert FAIL: % board, open: a sell row moved where it must not, or does not add up, at %', gd.code, v_bad;
      end if;
      select string_agg(n.e->>'port', ', ') into v_bad
        from jsonb_array_elements(v_new->'buy') n(e)
        left join jsonb_array_elements(v_old->'buy') o(e) on o.e->>'port' = n.e->>'port'
       where o.e is null or (n.e - c_buy_keys) is distinct from (o.e - c_buy_keys)
          or ((n.e->'supplies') - 'cost') is distinct from ((o.e->'supplies') - 'cost')
          or (n.e->'sail_days') is distinct from (n.e->'days');
      if v_bad is not null then
        raise exception '0361 self-assert FAIL: % board, open: a buy row moved where it must not, at %', gd.code, v_bad;
      end if;
      for r in
        select n.e, o.e as oe from jsonb_array_elements(v_new->'sell') n(e) join jsonb_array_elements(v_old->'sell') o(e) on o.e->>'port' = n.e->>'port'
         where (n.e->>'sailable')::boolean and (n.e->>'quoted')::boolean and n.e->>'port' <> v_hcode
      loop
        select coalesce(jsonb_agg(jsonb_build_object('from', x.a, 'to', x.b) order by x.i), '[]'::jsonb) into v_legs
          from (select s.i, lag(s.c, 1, v_hcode) over (order by s.i) as a, s.c as b
                  from (select t.c, t.i from jsonb_array_elements_text(r.e->'stops') with ordinality t(c, i)
                        union all select r.e->>'port', 1000) s) x;
        v_trip := world.trip_cost(v_fl, v_legs);
        if (r.e->>'wages')::numeric is distinct from (v_trip->>'wages')::numeric
           or (r.e->'supplies'->>'cost')::numeric is distinct from (v_trip->>'supplies')::numeric
           or (r.e->>'dock_fee')::numeric is distinct from (v_trip->>'dock_fee')::numeric
           or (r.e->>'stop_seconds')::numeric is distinct from (v_trip->>'stop_seconds')::numeric
           or abs((r.e->>'sail_days')::numeric - (v_trip->>'sail_days')::numeric) > 0.011 or abs((r.e->>'days')::numeric - (v_trip->>'days')::numeric) > 0.011
           or (r.e->>'profit')::numeric is distinct from (r.e->>'proceeds')::numeric - (r.e->>'cost')::numeric - (r.e->>'profit_tax')::numeric - (v_trip->>'total')::numeric then
          raise exception '0361 self-assert FAIL: % sold at %, open: the board''s row is not world.trip_cost''s trip: % against %', gd.code, r.e->>'port', r.e, v_trip;
        end if;
        v_rows := v_rows + 1;
        v_chained := v_chained + case when jsonb_array_length(v_legs) > 1 then 1 else 0 end;
        v_up_wages := v_up_wages + (r.e->>'wages')::bigint - (r.oe->>'wages')::bigint;
        v_up_sup := v_up_sup + (r.e->'supplies'->>'cost')::bigint - (r.oe->'supplies'->>'cost')::bigint;
      end loop;
      v_g1 := gd.id; v_g1code := gd.code;
    end loop;
    if v_rows = 0 then
      raise exception '0361 self-assert FAIL: the probe''s boards priced no row she can sail to: nothing was compared';
    end if;
    r_b := format('open, 2 boards: every other key of every row unmoved; %s priced row(s) are world.trip_cost''s trip (%s through a harbour between); over them wages +%s, supplies +%s',
                  v_rows, v_chained, v_up_wages, v_up_sup);

    -- (c) THE CARDS ARE THE BOARD'S ROWS STILL (0348's law), and the read is not far slower: old and new in turn
    for v_n in 1 .. 3 loop
      v_t1 := clock_timestamp(); v_old := pg_temp.best_sales_old_0361(v_fl, v_home); v_ms_old := v_ms_old + extract(epoch from clock_timestamp() - v_t1) * 1000;
      v_t1 := clock_timestamp(); v_new := world.best_sales(v_fl, v_home); v_ms_new := v_ms_new + extract(epoch from clock_timestamp() - v_t1) * 1000;
    end loop;
    if jsonb_array_length(v_new->'goods') <> jsonb_array_length(v_old->'goods') and not ((v_new->>'cut')::boolean or (v_old->>'cut')::boolean) then
      raise exception '0361 self-assert FAIL: world.best_sales answers % goods and answered %', jsonb_array_length(v_new->'goods'), jsonb_array_length(v_old->'goods');
    end if;
    for r in select e from jsonb_array_elements(v_new->'goods') e where e->>'port' is not null order by e->>'good' limit 3 loop
      continue when clock_timestamp() - v_t0 > interval '25 seconds';
      select s into v_trip
        from jsonb_array_elements(world.good_board((select g.id from public.goods g where g.code = r.e->>'good'), v_fl, v_home, (r.e->>'units')::numeric)->'sell') s
       where s->>'port' = r.e->>'port';
      if v_trip is null or (v_trip->>'profit')::numeric is distinct from (r.e->>'profit')::numeric or (v_trip->>'days')::numeric is distinct from (r.e->>'days')::numeric
         or round(extract(epoch from ((v_trip->>'arrive_at')::timestamptz - now()))) is distinct from (r.e->>'seconds')::numeric then
        raise exception '0361 self-assert FAIL: the % card is not the board''s row: % against %', r.e->>'good', r.e, v_trip;
      end if;
      v_cards := v_cards + 1;
    end loop;
    if not ((v_new->>'cut')::boolean or (v_old->>'cut')::boolean) and v_ms_new > v_ms_old * 2 + 300 then
      raise exception '0361 self-assert FAIL: world.best_sales is far slower than before: new % ms against old % ms over 3 calls', round(v_ms_new), round(v_ms_old);
    end if;
    r_c := format('%s card(s) are the board''s rows; world.best_sales a call: old %s ms, new %s ms; world.good_board a call: old %s ms, new %s ms',
                  v_cards, round(v_ms_old / 3), round(v_ms_new / 3), round(v_gb_old / 2), round(v_gb_new / 2));

    -- (d) CLOSED, HER OWN CARGO ABOARD: every priced row she can sail to is world.trip_cost's trip to the coin, dock fees and port time with it
    update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
    update public.ships s set cargo = jsonb_build_object(v_g1code, 5), cargo_basis = jsonb_build_object(v_g1code, 200)
     where s.id = (select x.id from public.ships x where x.fleet_id = v_fl order by x.id limit 1);
    v_prep := world.trip_stop_seconds();
    v_new := world.good_board(v_g1, v_fl, null, null);
    if v_new->'qty'->>'basis' <> 'on_board' then
      raise exception '0361 self-assert FAIL: the probe''s cargo is not read as on board: %', v_new->'qty';
    end if;
    v_rows := 0;
    for r in
      select n.e from jsonb_array_elements(v_new->'sell') n(e) where (n.e->>'sailable')::boolean and (n.e->>'quoted')::boolean and n.e->>'port' <> v_hcode
    loop
      select coalesce(jsonb_agg(jsonb_build_object('from', x.a, 'to', x.b) order by x.i), '[]'::jsonb) into v_legs
        from (select s.i, lag(s.c, 1, v_hcode) over (order by s.i) as a, s.c as b
                from (select t.c, t.i from jsonb_array_elements_text(r.e->'stops') with ordinality t(c, i)
                      union all select r.e->>'port', 1000) s) x;
      v_trip := world.trip_cost(v_fl, v_legs);
      if (r.e->>'wages')::numeric is distinct from (v_trip->>'wages')::numeric
         or (r.e->'supplies'->>'cost')::numeric is distinct from (v_trip->>'supplies')::numeric
         or (r.e->>'dock_fee')::numeric is distinct from (v_trip->>'dock_fee')::numeric
         or (r.e->>'stop_seconds')::numeric is distinct from (v_trip->>'stop_seconds')::numeric
         or (r.e->>'stop_seconds')::numeric is distinct from v_prep * (jsonb_array_length(v_legs) - 1)
         or abs((r.e->>'sail_days')::numeric - (v_trip->>'sail_days')::numeric) > 0.011 or abs((r.e->>'days')::numeric - (v_trip->>'days')::numeric) > 0.011
         or abs(extract(epoch from ((r.e->>'arrive_at')::timestamptz - now())) - (v_trip->>'days')::numeric * 86400 / public.wc_num('time_compression')) > 20
         or (r.e->>'profit')::numeric is distinct from (r.e->>'proceeds')::numeric - (r.e->>'cost')::numeric - (r.e->>'profit_tax')::numeric - (v_trip->>'total')::numeric then
        raise exception '0361 self-assert FAIL: her cargo sold at %, closed: the board''s row is not world.trip_cost''s trip: % against %', r.e->>'port', r.e, v_trip;
      end if;
      v_rows := v_rows + 1;
      v_fee_rows := v_fee_rows + case when (r.e->>'dock_fee')::bigint > 0 then 1 else 0 end;
      v_fee_max := greatest(v_fee_max, (r.e->>'dock_fee')::bigint);
    end loop;
    if v_rows = 0 then
      raise exception '0361 self-assert FAIL: closed, her cargo''s board priced no row she can sail to';
    end if;
    r_d := format('closed, her cargo: %s priced row(s) are world.trip_cost''s trip to the coin (%s with a dock fee, the dearest %s; %s s a call on the way)', v_rows, v_fee_rows, v_fee_max, v_prep);

    -- (e) CLOSED, A GOOD BOUGHT WHERE SHE LIES: every harbour after the buy charges on the cargo aboard now plus that buy (public.port_call's base)
    v_stock := public.fleet_stock_at_cost(v_fl);
    v_rows := 0;
    for gd in
      select g.id, g.code from public.port_goods pg join public.goods g on g.id = pg.good_id
       where pg.port_id = v_home and public.port_offers(v_home, g.id) and g.id <> v_g1 order by g.code limit 1
    loop
      v_new := world.good_board(gd.id, v_fl, v_home, null);
      for r in
        select n.e from jsonb_array_elements(v_new->'sell') n(e) where (n.e->>'sailable')::boolean and (n.e->>'quoted')::boolean and n.e->>'port' <> v_hcode
      loop
        select coalesce(sum(public.port_fee(p.id, v_pl, v_stock + (r.e->>'cost')::numeric)), 0) into v_exp
          from (select t.c from jsonb_array_elements_text(r.e->'stops') t(c) union all select r.e->>'port') x(c)
          join public.ports p on p.code = x.c and p.kind = 'HARBOUR';
        if (r.e->>'dock_fee')::numeric is distinct from v_exp::numeric
           or (r.e->>'profit')::numeric is distinct from (r.e->>'net')::numeric - (r.e->'supplies'->>'cost')::numeric - v_exp then
          raise exception '0361 self-assert FAIL: % bought at % and sold at %, closed: the dock fee is not every call''s on the cargo aboard then (%): %', gd.code, v_hcode, r.e->>'port', v_exp, r.e;
        end if;
        v_rows := v_rows + 1;
      end loop;
    end loop;
    r_e := format('closed, bought where she lies: %s priced row(s) pay every call''s fee on the cargo aboard after the buy', v_rows);

    raise exception using errcode = 'ZX361', message = 'PROBE_ROLLBACK_0361';
  exception when sqlstate 'ZX361' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0361 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid = c_uid) then
    raise exception '0361 self-assert FAIL: the probe left rows behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0361 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  if to_regprocedure('pg_temp.trip_cost_old_0361(uuid,jsonb)') is not null or to_regprocedure('pg_temp.board_legs_old_0361(uuid,jsonb)') is not null
     or to_regprocedure('pg_temp.board_sell_old_0361(uuid,uuid,jsonb)') is not null or to_regprocedure('pg_temp.good_board_old_0361(uuid,uuid,uuid,numeric)') is not null
     or to_regprocedure('pg_temp.best_sales_old_0361(uuid,uuid)') is not null then
    raise exception '0361 self-assert FAIL: a copy of a pre-image outlived the probe';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0361 self-assert FAIL: a world_config row moved: this file sets no knob, and the probe''s flags did not roll back';
  end if;

  -- ── 6. THE NEWS (0347's law): Trade's wages, dock fees, supplies and time are the trip's real ones from the deploy on ──
  perform public.news_update('0361', 'Trade: true trip cost', '교역: 실제 항해 비용');

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0361 self-assert FAIL: the file ran % s, over its 45 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0361 probe (a): %', r_a;
  raise notice '0361 probe (b): %', r_b;
  raise notice '0361 probe (c): %', r_c;
  raise notice '0361 probe (d): %', r_d;
  raise notice '0361 probe (e): %', r_e;
  raise notice '0361 self-assert ok: TRADE SAYS WHAT A TRIP REALLY COSTS. One walk (world.trip_leg) under world.trip_cost and the board; world.trip_cost answers what it answered; a board row''s wages, supplies, dock fee and days are the trip''s as the game charges them; 22 hunks, each once and reversing; no other function, knob, table, row or job moved. % ms.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
