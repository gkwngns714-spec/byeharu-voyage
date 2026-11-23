-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0480 - THE HQ BOARD FROM THE SERVER: EVERY OPTION RANKED, ONE PRESS  (dark: the owner's switch hq_board_enabled, false; lit,
--        world.hq_board() serves every move open to her now, ranked by one rule, each naming the command that commits it)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/hq-command-2026-11-23.md section 2, v2 items 1-3 (the server ranks; risk on a sale; the rate). The standing
--   fleet jobs (v2 item 4 on) are 0481, not this file. docs/dev-log/2026-11-23-hq-board-server.md.
--
-- WHY: the owner, 2026-11-23: "i want this game to be strategical game, where all the work(acitivities) are done in HQ - words with
--   graphics. choosing best options available, finding best options." Then: "remove sea limits entirely, build the HQ board. go".
--   v1 (#830) ranked on the client from the reads it already made: three idle fleets at most, requests at the city in hand only, the
--   premium alone, today's net over the hours since midnight. The server sees every fleet, every port she lies in and her ledger.
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it; every figure is a knob):
--   THE READ world.hq_board() (the client's one door, registered; STABLE; writes nothing). Dark {"on": false}. Lit, signed out or a
--     merchant {"on": true, "company": false}. Lit, her company: public.hq_board_for(her id), which answers
--     {on, company, moves: [{id, kind, band, fleet, fleet_name, at, score, profit, seconds, risk, needs, act}], rate, next, threats,
--      unpriced, clock (the market's: the client asks again at its edge), ms}:
--     TRADE    each IDLE fleet's world.best_sales (the desk's own read: DOCKED, nothing queued, on no standing route), the oldest fleet
--              first, at most hq_board_fleets of them, and no new read started once hq_board_budget_ms have passed (the fleets left
--              are named in `unpriced`; each best_sales keeps its own 2.5 s budget, so a call is at most ~ budget + 2.5 s). Her best
--              hq_board_runs paying sales a fleet (pays, a harbour, a profit, `near` not false: v1's filter), by coin an hour.
--              risk {danger, bounty, pirate}: the highest danger level (1-5, world.sea_danger's own level) of the waters of every
--              harbour the passage calls at (her port, its stops, the sale's harbour), and the richest standing bounty whose pirate's
--              home is one of those harbours or whose ship lies in one of those waters (public.hq_course_risk). Computed HERE, not in
--              world.best_sales: the desk's time-budgeted read is not touched (no hunk, not a millisecond slower).
--              act {rpc: cmd.issue_lines, args: {fleet, version, plan: {good, buy_at, sell_at, units, stops}}}: the desk's own trip
--              (planLines over the plan, the course from the client's chart, as the desk sends it: a SAIL without a course is refused
--              E_NO_COURSE by cmd.do_sail, so the server cannot write the lines whole). stops: world.board_passages' passage from her
--              port (asked once a priced fleet, with her stores' reach, as best_sales' own board_origin asks it).
--     REQUEST  every open request at every harbour where a fleet of hers lies DOCKED, for each such fleet with the good aboard: the
--              units cmd.run_fulfil would land (her hold, the budget, today's allowance) and the NET cmd.preview_fulfil serves
--              (the sale's quote total plus the bonus, rounded up: the same math in a read; the self-assert compares the two).
--              The time is hq_board_request_floor_s (a quarter hour: v1's floor). act {rpc: cmd.fulfil, args: {fleet, contract, version}}.
--     YARD     while she holds fewer than hq_board_build_below ships and has no hull on order, and the yard takes orders: at each
--              harbour where a fleet of hers lies with a building yard, the cheapest hull it lays down for her (yard_labour, the
--              yard sheet's figure), priced by public.hull_order_price; the cheapest of those, when her purse covers it.
--              act {rpc: cmd.order_hull, args: {port, class}}.
--     LAND     the Land party (land lit) with goods come home or waiting: act {rpc: cmd.land_collect, args: {}}.
--     CREW     a DOCKED fleet with no captain in any cabin, at a harbour with an Inn where a captain she has not signed sits now and
--              her purse pays the wage: the cheapest of them. act {rpc: cmd.hire_officer, args: {code, fleet}} (hired into the fleet
--              is seated in it).
--     INVEST   idle coin (her purse less the dearest trade card's buy) of hq_board_idle_coin or more, and the city purses lit: at
--              each harbour where a fleet of hers lies DOCKED (cmd.invest's own gate), the work with shares offered whose stake of
--              that coin pays the most a day (public.coupon_day_of, the rule the coupons pay by; the price public.works_share_price,
--              world.holdings' own leaf); the best three. act {rpc: cmd.invest, args: {port, kind, shares}}.
--   THE RANKING (one rule, here, ORDER BY in public.hq_board_for; v1's src/domain/hq/moves.ts, served):
--     band 0 the yard (a second hull is a second earner); band 1 trade runs and requests together, by `score` = coin an hour (a trade
--     run: profit x 3600 / its seconds; a request: net x 3600 / the floor); band 2 Land goods to collect; band 3 hire a captain;
--     band 4 invest (score: a day's coupon / 24). Then the higher score, the bigger profit, the id (a stable order).
--   THE RATE rate {per_hour, net_24h, since}: her ledger's last 24 real hours (FOUNDING and probes left out, as world.report), by the
--     (player_id, created_at) index, over 24. Not today's net over the hours since midnight.
--   NEXT: the soonest of a voyage's arrival, a hull ready, a lesson done, a standing route's next lap. THREATS: her voyages under way
--     whose waters stand at hq_board_danger_warn or more, or hold a bounty pirate (her home their harbour, or her ship in them).
-- ONE AUTHORITY EACH: the board, public.hq_board_for; the course's risk, public.hq_course_risk; a sea's level, public.hq_sea_level
--   (world.sea_danger's own formula, read for one sea); the door, world.hq_board(). Every figure is a served authority's: best_sales,
--   board_passages, quote, daily_cap_remaining, hull_order_price, captain_wage, inn_present, coupon_day_of, land_progress.
-- NOT CHANGED: any command, world.best_sales, the desk, any other read; nothing for anyone while dark.
-- ROWS: none. No table, no index, no cron, no beat step: a read asked when HQ opens and when the market changes, never on a timer.
-- COST. Dark: one knob read. Lit, the local chain (proof 183 HB_COST, a new company at Lisbon): one call ~0.5 s with one idle fleet
--   priced, ~0.9 s with two (world.best_sales ~0.45 s a fleet there, world.board_passages ~0.08 s, the rest a few ms). PROD (the
--   before-0480 read, 2026-11-23): ONE world.best_sales for the newest company at Lisbon took 2,735 ms (cut by its own 2.5 s budget);
--   19 companies, 19 idle fleets, at most 1 a company. So a board on prod today is about one best_sales plus ~0.1 s, ~3 s; with more
--   idle fleets hq_board_budget_ms (2 s) starts no second read after a Lisbon-sized one: a call stays under ~2 s + 2.5 s + 0.2 s.
-- LOCKS: CREATE FUNCTION x4; CREATE OR REPLACE x1 by a hunk (public.client_rpc_entry_points); eight knobs. TIME: a second.
--   BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, hq_board_enabled false (the read answers {"on": false}; the client draws v1's board). Full: a new
--   migration reversing the one hunk (OLD text below verbatim), dropping the four functions, deleting the knobs.
-- SELF-ASSERT: the hunk once and reversing; no other function moved; the hunked body's grants, volatility, definer, search path, owner
--   unmoved; the knobs; the four functions STABLE; world.hq_board registered for authenticated alone; the three helpers server-only.
--   THE PROBE (rolled back; deterministic: no comparison of two time-budgeted reads, hq_board_fleets 0 wherever a figure is compared, so
--   world.best_sales is never asked there): dark {"on": false}; lit, a company at Lisbon with a request's good aboard: the request
--   card's net equals cmd.preview_fulfil's (asked in the same transaction), its act commits through cmd.fulfil; the rate is her probe
--   ledger row over 24; the yard card's price is hull_order_price's and its act commits through cmd.order_hull; the invest card's act
--   commits through cmd.invest; a crew card exactly when a captain she can pay sits at the Inn; the order is the rule's; a sea's level
--   is world.sea_danger's; a course through a bounty pirate's home carries her bounty. Proof 183 plays it with trade runs and the cost.
-- VERSION: 0480 = 0479 + 1 (0479, #828, hunks client_rpc_entry_points; this file's hunk is anchored on 0479's own line).
-- news: none (dark: nothing changes for a player until the owner lights hq_board_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.hq_sea_level(uuid)', 'public.hq_course_risk(text[])', 'public.hq_board_for(uuid)', 'world.hq_board()'];
  c_uid    constant uuid := '00000000-0480-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_note      text := '';
  v_lived     boolean := false;
  v_me        uuid;
  v_fl        uuid;
  v_ver       int;
  v_lis       uuid;
  v_good      uuid;
  v_gcode     text;
  v_ct        uuid;
  v_b         jsonb;
  v_m         jsonb;
  v_p         jsonb;
  v_r         jsonb;
  v_f         record;
  v_pirate    uuid;
  v_yard      text;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'hq_board_enabled') or to_regprocedure('world.hq_board()') is not null then
    raise exception '0480 refuses: it has been applied once';
  end if;
  if to_regprocedure('world.goods_mastery()') is null or to_regprocedure('world.best_sales(uuid,uuid)') is null
     or to_regprocedure('world.board_passages(uuid,uuid,uuid,numeric)') is null or to_regprocedure('public.hull_order_price(uuid,uuid,text)') is null
     or to_regprocedure('public.coupon_day_of(uuid,uuid,numeric)') is null or to_regprocedure('public.land_progress(uuid,timestamptz)') is null
     or to_regprocedure('public.bounty_value(timestamptz,integer,timestamptz)') is null or to_regprocedure('cmd.assume_identity(uuid)') is null then
    raise exception '0480 refuses: 0479, 0348, 0465, 0456, 0455, 0471 or 0213 is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('hq_board_enabled', 'false'::jsonb,
     '0480: THE SWITCH (the owner''s). true: world.hq_board() serves every move open to her now (trade runs, requests, the yard, Land, a captain, invest), ranked by one rule (public.hq_board_for), each naming the command that commits it; the HQ board draws it. false: the read is {"on": false} and the client ranks v1''s own.'),
    ('hq_board_fleets', to_jsonb(4), '0480: the idle fleets whose trade runs one world.hq_board() call prices (one world.best_sales each, the oldest fleet first).'),
    ('hq_board_budget_ms', to_jsonb(2000), '0480: the whole board''s budget: no new world.best_sales read starts once a call has run this many milliseconds (the fleets left are named in `unpriced`).'),
    ('hq_board_runs', to_jsonb(3), '0480: the trade runs a priced fleet offers the board, the best by coin an hour.'),
    ('hq_board_request_floor_s', to_jsonb(900), '0480: the time a request counts for in the ranking (a quarter hour: she lies there, the press is one).'),
    ('hq_board_idle_coin', to_jsonb(20000), '0480: coin beyond the dearest trade card''s buy at or above this is idle: the board offers invest cards.'),
    ('hq_board_build_below', to_jsonb(2), '0480: the yard card stands while she holds fewer ships than this (2: the second ship).'),
    ('hq_board_danger_warn', to_jsonb(4), '0480: a sea at this danger level (1-5) or more on a voyage under way counts as a threat on the board.');

  -- ── 3. THE RULES ──
  execute $f$
create function public.hq_sea_level(p_sea uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0480: ONE SEA'S DANGER LEVEL NOW (1-5), world.sea_danger's own formula read for one sea (the authored level, moved one step each
  -- time the live figure crosses a band the authored one is not over). Null for no sea.
  select least(5, greatest(1, s.danger_level + voyage.sea_band(voyage.sea_danger(s.id, now())) - voyage.sea_band(voyage.sea_danger(s.id, null))))
    from public.seas s where s.id = p_sea
$body$
  $f$;

  execute $f$
create function public.hq_course_risk(p_codes text[])
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0480: THE RISK OF A PASSAGE, from the harbours it calls at (codes, in any order): danger, the highest level (public.hq_sea_level) of
  -- their waters (1 with none known); bounty and pirate, the richest standing bounty (public.bounty_on lit) whose pirate's home is one of
  -- those harbours or whose ship lies (not laid up) in one of those waters; null with none.
  with h as materialized (
    select p.id, p.sea_id from public.ports p where p.code = any (p_codes) and p.kind = 'HARBOUR'
  ), w as materialized (
    select distinct h.sea_id from h where h.sea_id is not null
  ), b as (
    select public.bounty_value(x.named_at, x.taken, now()) as v, public.bounty_name(x.epithet, x.given, x.home_port) as nm
      from public.pirate_bounties x
      left join public.pirate_ships n on n.fleet_id = x.fleet_id
     where public.bounty_on() and x.closed_at is null and n.laid_up_at is null
       and (x.home_port in (select h.id from h) or n.sea_id in (select w.sea_id from w))
     order by 1 desc, 2 limit 1
  )
  select jsonb_build_object('danger', coalesce((select max(public.hq_sea_level(w.sea_id)) from w), 1),
                            'bounty', (select round(b.v) from b), 'pirate', (select b.nm from b))
$body$
  $f$;

  execute $f$
create function public.hq_board_for(p_player uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0480: THE HQ BOARD OF ONE COMPANY (world.hq_board's body; server only): every move open to her now, ranked by ONE rule (the ORDER BY at
-- the end), each naming the command that commits it. Trade runs are priced by world.best_sales, which reads the CALLER
-- (public.current_player_id): asked for anyone else, no fleet is priced (all `unpriced`). Writes nothing. The rules: 0480's header.
declare
  v_t0      timestamptz := clock_timestamp();
  v_caller  boolean := public.current_player_id() is not distinct from p_player;
  v_purse   bigint := (select p.ducats from public.players p where p.id = p_player);
  v_fleets  int := greatest(0, coalesce(public.wc_int('hq_board_fleets'), 4));
  v_budget  numeric := greatest(0, coalesce(public.wc_num('hq_board_budget_ms'), 2000));
  v_runs    int := greatest(0, coalesce(public.wc_int('hq_board_runs'), 3));
  v_floor   numeric := greatest(1, coalesce(public.wc_num('hq_board_request_floor_s'), 900));
  v_idle_at numeric := coalesce(public.wc_num('hq_board_idle_coin'), 20000);
  v_warn    int := coalesce(public.wc_int('hq_board_danger_warn'), 4);
  v_routes  boolean := coalesce(public.standing_routes_on(), false);
  v_moves   jsonb := '[]'::jsonb;
  v_unpriced jsonb := '[]'::jsonb;
  v_i       int := 0;
  f         record;
  v_bs      jsonb;
  v_pass    jsonb;
  v_stops   jsonb;
  s         record;
  v_dear    numeric := 0;
  v_idle    numeric;
  v_y       record;
  v_q       jsonb;
  v_best    jsonb;
  v_lp      public.land_parties%rowtype;
  v_prog    jsonb;
  v_next    jsonb;
begin
  if p_player is null or v_purse is null then
    return jsonb_build_object('moves', '[]'::jsonb, 'rate', null, 'next', null, 'threats', 0, 'unpriced', '[]'::jsonb,
                              'clock', jsonb_build_object('now', now(), 'next_change_at', public.next_drift_change_at(now())), 'ms', 0);
  end if;

  -- TRADE: each idle fleet's best sales (world.best_sales), the oldest first, within the fleet count and the board's budget
  for f in
    select fl.id, fl.name, fl.version, fl.port_id, p.code as at
      from public.fleets fl join public.ports p on p.id = fl.port_id
     where fl.player_id = p_player and fl.status = 'DOCKED' and p.kind = 'HARBOUR'
       and not exists (select 1 from public.orders o where o.fleet_id = fl.id and o.status in ('pending', 'active'))
       and not (v_routes and exists (select 1 from public.standing_routes r where r.fleet_id = fl.id))
     order by fl.created_at, fl.id
  loop
    if not v_caller or v_i >= v_fleets or (v_i > 0 and extract(epoch from clock_timestamp() - v_t0) * 1000 > v_budget) then
      v_unpriced := v_unpriced || to_jsonb(f.id);
      continue;
    end if;
    v_i := v_i + 1;
    begin
      v_bs := world.best_sales(f.id, f.port_id);
    exception when others then
      v_unpriced := v_unpriced || to_jsonb(f.id);
      continue;
    end;
    -- her passages from where she lies (the stops of each sale's passage), with her stores' reach, as best_sales' board_origin asks them
    v_pass := world.board_passages(p_player, f.id, f.port_id, (select sr.cap_nm from public.supply_reach(f.id) sr));
    select coalesce(jsonb_object_agg(p.code, coalesce(e->'stops', '[]'::jsonb)), '{}'::jsonb) into v_stops
      from jsonb_array_elements(v_pass) e join public.ports p on p.id = (e->>'port_id')::uuid;
    for s in
      select g.e, (g.e->>'profit')::numeric as profit, greatest(coalesce((g.e->>'seconds')::numeric, (g.e->>'days')::numeric * 86400), 1) as secs
        from jsonb_array_elements(coalesce(v_bs->'goods', '[]'::jsonb)) g(e)
       where (g.e->>'pays')::boolean and g.e->>'port' is not null and jsonb_typeof(g.e->'profit') = 'number' and (g.e->>'profit')::numeric > 0
         and g.e->'near' is distinct from 'false'::jsonb
         and (jsonb_typeof(g.e->'seconds') = 'number' or jsonb_typeof(g.e->'days') = 'number')
       order by (g.e->>'profit')::numeric / greatest(coalesce((g.e->>'seconds')::numeric, (g.e->>'days')::numeric * 86400), 1) desc, g.e->>'good'
       limit v_runs
    loop
      v_dear := greatest(v_dear, coalesce((s.e->>'cost')::numeric, 0));
      v_moves := v_moves || jsonb_build_array(jsonb_build_object(
        'id', format('trade:%s:%s:%s', f.id, s.e->>'good', s.e->>'port'), 'kind', 'trade', 'band', 1,
        'fleet', f.id, 'fleet_name', f.name, 'at', f.at,
        'score', round(s.profit * 3600 / s.secs), 'profit', round(s.profit), 'seconds', round(s.secs),
        'risk', public.hq_course_risk(array[f.at, s.e->>'port'] || array(select jsonb_array_elements_text(coalesce(v_stops->(s.e->>'port'), '[]'::jsonb)))),
        'needs', jsonb_build_object('good', s.e->>'good', 'units', (s.e->>'units')::numeric, 'cost', (s.e->>'cost')::numeric, 'to', s.e->>'port',
                                    'basis', s.e->>'basis'),
        'act', jsonb_build_object('rpc', 'cmd.issue_lines', 'args', jsonb_build_object('fleet', f.id, 'version', f.version, 'plan', jsonb_build_object(
                 'good', s.e->>'good', 'buy_at', case when s.e->>'basis' = 'on_board' then null else f.at end, 'sell_at', s.e->>'port',
                 'units', case when s.e->>'basis' = 'on_board' then null else (s.e->>'units')::numeric end,
                 'stops', coalesce(v_stops->(s.e->>'port'), '[]'::jsonb))))));
    end loop;
  end loop;

  -- REQUESTS: every open request where a fleet of hers lies DOCKED, the units cmd.run_fulfil would land, cmd.preview_fulfil's net
  v_moves := v_moves || coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', format('request:%s:%s', r.cid, r.fid), 'kind', 'request', 'band', 1,
             'fleet', r.fid, 'fleet_name', r.fname, 'at', r.at,
             'score', round(r.net * 3600 / v_floor), 'profit', r.net, 'seconds', null,
             'risk', null,
             'needs', jsonb_build_object('good', r.gcode, 'units', r.units, 'bonus', r.bonus),
             'act', jsonb_build_object('rpc', 'cmd.fulfil', 'args', jsonb_build_object('fleet', r.fid, 'contract', r.cid, 'version', r.ver))))
      from (select c.id as cid, fl.id as fid, fl.name as fname, fl.version as ver, p.code as at, g.code as gcode, u.units,
                   ceil(c.premium_per_unit * u.units)::bigint as bonus,
                   (q.total + ceil(c.premium_per_unit * u.units))::bigint as net
              from public.fleets fl
              join public.ports p on p.id = fl.port_id
              join public.trade_contracts c on c.port_id = fl.port_id and c.status = 'open' and c.expires_day > world.game_day()
              join public.goods g on g.id = c.good_id
             cross join lateral (select least(floor(public.fleet_cargo_qty(fl.id, g.code)), floor(c.premium_ducats / c.premium_per_unit),
                                              case when cap.v >= 1 then floor(cap.v) end) as units
                                   from (select world.daily_cap_remaining(p_player, c.port_id, c.good_id) as v) cap) u
             cross join lateral world.quote(c.port_id, c.good_id, u.units, 'sell', null, fl.id) q
             where fl.player_id = p_player and fl.status = 'DOCKED' and u.units >= 1 and q.units >= 1) r), '[]'::jsonb);

  -- THE YARD: the second ship (fewer than hq_board_build_below ships, none on order), the cheapest hull at a yard where she lies
  if public.wc('yard_order_enabled') = 'true'::jsonb
     and (select count(*) from public.ships sh where sh.player_id = p_player) < coalesce(public.wc_int('hq_board_build_below'), 2)
     and not exists (select 1 from public.hull_orders o where o.player_id = p_player and o.launched_at is null) then
    for v_y in
      select distinct on (y.port_id) y.port_id, y.code, y.class_code
        from (select b.port_id, p.code, h.class_code, public.yard_labour(p_player, h.class_code) as labour
                from (select distinct fl.port_id from public.fleets fl where fl.player_id = p_player and fl.status = 'DOCKED' and fl.port_id is not null) d
                join public.port_buildings b on b.port_id = d.port_id and b.kind = 'building_yard'
                join public.ports p on p.id = b.port_id
                join public.hull_recipes h on h.yard_tier <= b.tier
               where public.yard_wrong_country(b.port_id, h.class_code) is null and public.requirements_met(p_player, 'hull', h.class_code)
                 and public.hull_unmade(h.class_code) is null and public.famous_held(p_player, h.class_code) is null) y
       where y.labour is not null
       order by y.port_id, y.labour, y.class_code
    loop
      v_q := public.hull_order_price(p_player, v_y.port_id, v_y.class_code);
      continue when v_q is null or v_q->>'short' is not null or (v_q->>'price')::bigint > v_purse;
      if v_best is null or (v_q->>'price')::bigint < (v_best->'needs'->>'cost')::bigint then
        v_best := jsonb_build_object(
          'id', format('yard:%s:%s', v_y.code, v_y.class_code), 'kind', 'yard', 'band', 0, 'fleet', null, 'fleet_name', null, 'at', v_y.code,
          'score', null, 'profit', null, 'seconds', (v_q->>'minutes')::int * 60, 'risk', null,
          'needs', jsonb_build_object('hull', v_y.class_code, 'cost', (v_q->>'price')::bigint),
          'act', jsonb_build_object('rpc', 'cmd.order_hull', 'args', jsonb_build_object('port', v_y.port_id, 'class', v_y.class_code)));
      end if;
    end loop;
    if v_best is not null then
      v_moves := v_moves || jsonb_build_array(v_best);
    end if;
  end if;

  -- LAND: goods come home, or waiting, to collect
  if public.land_on() then
    select * into v_lp from public.land_parties lp where lp.player_id = p_player and lp.ord = 1;
    if v_lp.id is not null then
      v_prog := public.land_progress(v_lp.id, now());
      if coalesce((v_prog->>'new')::int, 0) > 0 or coalesce(v_lp.waiting, 0) > 0 then
        v_moves := v_moves || jsonb_build_array(jsonb_build_object(
          'id', 'land', 'kind', 'land', 'band', 2, 'fleet', null, 'fleet_name', null, 'at', (select p.code from public.ports p where p.id = v_lp.port_id),
          'score', null, 'profit', null, 'seconds', null, 'risk', null,
          'needs', jsonb_build_object('good', (select g.code from public.goods g where g.id = coalesce((v_lp.terms->>'good')::uuid, v_lp.waiting_good)),
                                      'units', coalesce((v_prog->>'new')::int, 0) + coalesce(v_lp.waiting, 0)),
          'act', jsonb_build_object('rpc', 'cmd.land_collect', 'args', '{}'::jsonb)));
      end if;
    end if;
  end if;

  -- CREW: a docked fleet with no captain in any cabin, at an Inn where a captain she has not signed sits now and her purse pays
  v_moves := v_moves || coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', format('crew:%s', c.fid), 'kind', 'crew', 'band', 3, 'fleet', c.fid, 'fleet_name', c.fname, 'at', c.at,
             'score', null, 'profit', null, 'seconds', null, 'risk', null,
             'needs', jsonb_build_object('officer', c.code, 'name', c.oname, 'wage', c.wage),
             'act', jsonb_build_object('rpc', 'cmd.hire_officer', 'args', jsonb_build_object('code', c.code, 'fleet', c.fid))))
      from (select fl.id as fid, fl.name as fname, p.code as at, o.code, o.name as oname, o.wage
              from public.fleets fl
              join public.ports p on p.id = fl.port_id
              cross join lateral (select oo.code, oo.name, public.captain_wage(p_player, oo.id) as wage
                                    from public.officers oo
                                   where world.inn_present(oo.id, fl.port_id, world.inn_shift())
                                     and not exists (select 1 from public.player_officers po where po.player_id = p_player and po.officer_id = oo.id)
                                   order by 3, oo.code limit 1) o
             where fl.player_id = p_player and fl.status = 'DOCKED'
               and exists (select 1 from public.port_buildings b where b.port_id = fl.port_id and b.kind = 'inn')
               and exists (select 1 from public.ships sh where sh.fleet_id = fl.id)
               and not exists (select 1 from public.captain_seats cs join public.ships sh on sh.id = cs.ship_id where sh.fleet_id = fl.id)
               and o.wage <= v_purse) c), '[]'::jsonb);

  -- INVEST: idle coin, at each harbour where a fleet of hers lies docked, the work whose stake of it pays the most a day; the best three
  v_idle := v_purse - v_dear;
  if v_idle >= v_idle_at and public.city_treasury_on() then
    v_moves := v_moves || coalesce((
      select jsonb_agg(z.o order by z.coupon desc, z.at, z.kind)
        from (select k.o, k.coupon, k.at, k.kind
                from (select distinct on (w.port_id) w.port_id, w.at, w.kind, w.coupon,
                             jsonb_build_object('id', format('invest:%s:%s', w.at, w.kind), 'kind', 'invest', 'band', 4, 'fleet', null, 'fleet_name', null,
                               'at', w.at, 'score', round(w.coupon / 24), 'profit', round(w.coupon), 'seconds', 86400, 'risk', null,
                               'needs', jsonb_build_object('work', w.kind, 'shares', w.shares, 'cost', w.cost, 'idle', round(v_idle)),
                               'act', jsonb_build_object('rpc', 'cmd.invest', 'args', jsonb_build_object('port', w.port_id, 'kind', w.kind, 'shares', w.shares))) as o
                        from (select v.port_id, v.at, v.kind, v.shares, v.shares * v.price as cost,
                                     public.coupon_day_of(v.port_id, p_player, v.shares * v.price) as coupon
                                from (select d.port_id, p.code as at, kk.kind, pr.price,
                                             least(public.city_offered(d.port_id, kk.kind), floor(v_idle / pr.price))::int as shares
                                        from (select distinct fl.port_id from public.fleets fl where fl.player_id = p_player and fl.status = 'DOCKED' and fl.port_id is not null) d
                                        join public.ports p on p.id = d.port_id and p.kind = 'HARBOUR'
                                       cross join (values ('docks'), ('market'), ('production'), ('inn')) kk(kind)
                                       cross join lateral (select public.works_share_price(coalesce((select cw.level from public.city_works cw
                                                                                                    where cw.port_id = d.port_id and cw.kind = kk.kind), 0)) as price) pr
                                       where pr.price > 0) v
                               where v.shares >= 1 and v.shares * v.price >= coalesce(public.wc_int('invest_min_ducats'), 0)) w
                       order by w.port_id, w.coupon desc, w.kind) k
               order by k.coupon desc, k.at, k.kind
               limit 3) z), '[]'::jsonb);
  end if;

  -- NEXT: the soonest of an arrival, a hull ready, a lesson done, a standing route's next lap
  select jsonb_build_object('what', n.what, 'at', n.at, 'name', n.name) into v_next
    from (select 'arrives' as what, v.eta as at, fl.name
            from public.voyages v join public.fleets fl on fl.id = v.fleet_id
           where fl.player_id = p_player and v.status = 'SAILING' and v.eta > now()
          union all
          select 'ship', o.ready_at, o.class_code from public.hull_orders o where o.player_id = p_player and o.launched_at is null and o.ready_at > now()
          union all
          select 'training', q.finishes_at, null from public.skill_queue q where q.player_id = p_player and q.finishes_at > now()
          union all
          select 'lap', r.hold_until, r.name from public.standing_routes r where r.player_id = p_player and r.hold_until > now()) n
   order by n.at, n.what limit 1;

  return jsonb_build_object(
    -- THE RANKING: the one rule (0480's header): the band, then coin an hour, then the profit, then the id
    'moves', coalesce((select jsonb_agg(m.e order by (m.e->>'band')::int, (m.e->>'score')::numeric desc nulls last,
                                                     (m.e->>'profit')::numeric desc nulls last, m.e->>'id')
                         from jsonb_array_elements(v_moves) m(e)), '[]'::jsonb),
    -- THE RATE: her ledger's last 24 real hours (FOUNDING and probes left out, as world.report), by the (player_id, created_at) index
    'rate', (select jsonb_build_object('per_hour', round(coalesce(sum(l.ducats_delta), 0) / 24.0), 'net_24h', coalesce(sum(l.ducats_delta), 0),
                                       'since', now() - interval '24 hours')
               from public.ledger l
              where l.player_id = p_player and l.created_at > now() - interval '24 hours'
                and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_'),
    'next', v_next,
    -- THREATS: her voyages under way whose waters stand at hq_board_danger_warn or more, or hold a bounty pirate
    'threats', (select count(*)
                  from public.voyages v join public.fleets fl on fl.id = v.fleet_id
                 cross join lateral (select array(select distinct (e->>'sea_id')::uuid
                                                    from jsonb_array_elements(case when jsonb_typeof(v.path) = 'array' then v.path else '[]'::jsonb end) e
                                                   where e ? 'sea_id') as seas) w
                 where fl.player_id = p_player and v.status = 'SAILING'
                   and (exists (select 1 from unnest(w.seas) sid where public.hq_sea_level(sid) >= v_warn)
                        or public.hq_course_risk(array(select p.code from public.ports p where p.id in (v.origin_port_id, v.dest_port_id)))->>'bounty' is not null
                        or (public.bounty_on() and exists (select 1 from public.pirate_bounties x join public.pirate_ships n on n.fleet_id = x.fleet_id
                                                            where x.closed_at is null and n.laid_up_at is null and n.sea_id = any (w.seas))))),
    'unpriced', v_unpriced,
    -- the market's clock (best_sales' own): the client asks again at its edge, never on the beat
    'clock', jsonb_build_object('now', now(), 'next_change_at', public.next_drift_change_at(now())),
    'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end
$body$
  $f$;

  execute $f$
create function world.hq_board()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0480: THE HQ BOARD, the client's one door. Dark (hq_board_enabled false): {"on": false}. Lit, signed out or a merchant:
-- {"on": true, "company": false}. Lit, her company: public.hq_board_for(her) with on and company true. Writes nothing.
declare
  v_me uuid := public.current_player_id();
begin
  if public.wc('hq_board_enabled') is distinct from 'true'::jsonb then
    return jsonb_build_object('on', false);
  end if;
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('on', true, 'company', false);
  end if;
  return jsonb_build_object('on', true, 'company', true) || public.hq_board_for(v_me);
end
$body$
  $f$;
  revoke all on function public.hq_sea_level(uuid) from public, anon, authenticated;
  revoke all on function public.hq_course_risk(text[]) from public, anon, authenticated;
  revoke all on function public.hq_board_for(uuid) from public, anon, authenticated;
  revoke all on function world.hq_board() from public, anon;
  grant execute on function world.hq_board() to authenticated;
  comment on function world.hq_board() is
    '0480: the HQ board (dark {"on": false}): every move open to her now, ranked by one rule, each with the command that commits it; her rate, the next clock, threats. A read. Client door.';

  -- ── 4. THE HUNK (it occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0480 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0480 values
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'goods_mastery',         ''),$h$,
$h$      ('world',       'goods_mastery',         ''),
      -- 0480: the HQ board (dark: {"on": false})
      ('world',       'hq_board',              ''),$h$);

  for v_h in select h.fn from hunks_0480 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0480 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0480 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0480 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0480 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0480 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog, the knobs, the door ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0480 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0480 self-assert FAIL: the grants, volatility, definer, search path or owner of the hunked body moved';
  end if;
  if (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.provolatile = 's') <> 4 then
    raise exception '0480 self-assert FAIL: a new function is not STABLE (the board is a read)';
  end if;
  if public.wc('hq_board_enabled') <> 'false'::jsonb or public.wc_int('hq_board_fleets') <> 4 or public.wc_int('hq_board_budget_ms') <> 2000
     or public.wc_int('hq_board_runs') <> 3 or public.wc_int('hq_board_request_floor_s') <> 900 or public.wc_int('hq_board_idle_coin') <> 20000
     or public.wc_int('hq_board_build_below') <> 2 or public.wc_int('hq_board_danger_warn') <> 4 then
    raise exception '0480 self-assert FAIL: the knobs are not as written';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) = ('world', 'hq_board', '')
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 1
     or has_function_privilege('authenticated', 'public.hq_board_for(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.hq_course_risk(text[])', 'execute')
     or has_function_privilege('authenticated', 'public.hq_sea_level(uuid)', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0480 self-assert FAIL: world.hq_board is not registered for authenticated alone, or a client reaches a server-only function';
  end if;

  -- ── 6. THE PROBE, rolled back by a raised sentinel (world.best_sales is never asked: hq_board_fleets 0) ──
  begin
    update public.world_config set value = to_jsonb(0) where key = 'hq_board_fleets';
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_me := public.new_house(c_uid, 'Casa do Quadro 0480', 'PRT');
    perform cmd.assume_identity(c_uid);
    select f.id into v_fl from public.fleets f where f.player_id = v_me;
    update public.players p set ducats = 2000000 where p.id = v_me;

    -- (a) DARK: {"on": false}
    if world.hq_board() is distinct from '{"on": false}'::jsonb then
      raise exception '0480 self-assert FAIL: dark, the read is not {"on": false}: %', left(world.hq_board()::text, 300);
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'hq_board_enabled';

    -- (b) A REQUEST: a good Lisbon trades, aboard; a request for it at Lisbon. The card's net is cmd.preview_fulfil's.
    select g.id, g.code into v_good, v_gcode
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_lis and not public.culture_refuses((select p.culture from public.ports p where p.id = v_lis), g.culture_mask)
     order by pg.stock_target desc, g.code limit 1;
    update public.ships s set cargo = jsonb_build_object(v_gcode, 20), cargo_basis = jsonb_build_object(v_gcode, 1) where s.fleet_id = v_fl;
    insert into public.trade_contracts (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day, status, escrow, size)
    values (v_lis, v_good, world.game_day(), 99, 50, 20, 100, 7.5, 375, world.game_day() + 3, 'open', 375, 'city')
    returning id into v_ct;
    -- (c) THE RATE: one probe ledger row an hour ago, one 30 hours ago (outside the window)
    insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at)
    values (v_me, 'SELL', 4800, 2000000, now() - interval '1 hour'), (v_me, 'SELL', 99999, 2000000, now() - interval '30 hours');
    v_b := world.hq_board();
    v_p := cmd.preview_fulfil(v_fl, v_ct);
    select m.e into v_m from jsonb_array_elements(v_b->'moves') m(e) where m.e->>'kind' = 'request';
    if (v_b->>'company')::boolean is not true or v_m is null or (v_p->>'ok')::boolean is not true or jsonb_typeof(v_b #> '{clock,next_change_at}') <> 'string'
       or (v_m->>'profit')::numeric is distinct from (v_p #>> '{estimate,totals,net}')::numeric
       or (v_m->'needs'->>'units')::numeric is distinct from (v_p #>> '{estimate,contract,qty}')::numeric
       or v_m #>> '{act,rpc}' <> 'cmd.fulfil' or (v_m #>> '{act,args,contract}')::uuid <> v_ct or (v_m #>> '{act,args,fleet}')::uuid <> v_fl
       or (v_m->>'score')::numeric <> round((v_m->>'profit')::numeric * 3600 / 900)
       or (v_b #>> '{rate,per_hour}')::numeric <> 200 or (v_b #>> '{rate,net_24h}')::numeric <> 4800
       or jsonb_array_length(v_b->'unpriced') <> 1 or v_b #>> '{unpriced,0}' <> v_fl::text then
      raise exception '0480 self-assert FAIL: lit, the request card is not cmd.preview_fulfil''s, the rate is not her 24 hours, or her idle fleet was priced: % / % / %',
        left(coalesce(v_m::text, 'null'), 400), left(coalesce(v_p::text, 'null'), 400), left((v_b - 'moves')::text, 300);
    end if;
    -- a crew card exactly when a captain she has not signed sits at Lisbon's Inn now (her new fleet has no captain)
    if exists (select 1 from jsonb_array_elements(v_b->'moves') m(e) where m.e->>'kind' = 'crew')
       is distinct from exists (select 1 from public.officers o where world.inn_present(o.id, v_lis, world.inn_shift())) then
      raise exception '0480 self-assert FAIL: lit, a crew card stands without a captain at the Inn, or none with one';
    end if;
    -- THE ORDER is the rule's: bands rising; within a band, coin an hour falling (nulls last)
    if exists (select 1 from (select (m.e->>'band')::int as b, (m.e->>'score')::numeric as s, k,
                                     lag((m.e->>'band')::int) over (order by k) as pb, lag((m.e->>'score')::numeric) over (order by k) as ps
                                from jsonb_array_elements(v_b->'moves') with ordinality m(e, k)) z
                where z.b < z.pb or (z.b = z.pb and z.ps is null and z.s is not null) or (z.b = z.pb and z.s > z.ps)) then
      raise exception '0480 self-assert FAIL: lit, the moves are not in the rule''s order: %', left((v_b->'moves')::text, 600);
    end if;
    -- the request's act commits through cmd.fulfil
    v_r := cmd.fulfil((v_m #>> '{act,args,fleet}')::uuid, (v_m #>> '{act,args,contract}')::uuid, (v_m #>> '{act,args,version}')::int);
    if (v_r->>'ok')::boolean is not true then
      raise exception '0480 self-assert FAIL: the request card''s act did not commit: %', left(v_r::text, 400);
    end if;

    -- (d) THE YARD: the yard takes orders; her one ship at Lisbon's building yard: the card is hull_order_price's, its act commits
    update public.world_config set value = 'true'::jsonb where key = 'yard_order_enabled';
    v_b := world.hq_board();
    select m.e into v_m from jsonb_array_elements(v_b->'moves') m(e) where m.e->>'kind' = 'yard';
    if v_m is null or v_m->>'at' <> 'LIS' or v_b #>> '{moves,0,kind}' <> 'yard'
       or (v_m #>> '{needs,cost}')::bigint <> (public.hull_order_price(v_me, v_lis, v_m #>> '{needs,hull}')->>'price')::bigint then
      raise exception '0480 self-assert FAIL: lit, the yard card is missing, not first, or not hull_order_price''s: %', left(coalesce(v_m::text, (v_b->'moves')::text), 400);
    end if;
    v_yard := format('%s %s', v_m #>> '{needs,hull}', v_m #>> '{needs,cost}');
    v_r := cmd.order_hull((v_m #>> '{act,args,port}')::uuid, v_m #>> '{act,args,class}');
    if (v_r->>'ok')::boolean is not true
       or exists (select 1 from jsonb_array_elements(world.hq_board()->'moves') m(e) where m.e->>'kind' = 'yard') then
      raise exception '0480 self-assert FAIL: the yard card''s act did not commit, or the card stands with a hull on order: %', left(v_r::text, 400);
    end if;

    -- (e) INVEST: the city purses lit; her idle coin buys a stake at Lisbon: the card's act commits through cmd.invest
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    v_b := world.hq_board();
    select m.e into v_m from jsonb_array_elements(v_b->'moves') m(e) where m.e->>'kind' = 'invest';
    if v_m is null or v_m->>'at' <> 'LIS' or (v_m #>> '{needs,cost}')::numeric > (select p.ducats from public.players p where p.id = v_me) then
      raise exception '0480 self-assert FAIL: lit, no invest card for idle coin at Lisbon: %', left((v_b->'moves')::text, 400);
    end if;
    v_r := cmd.invest((v_m #>> '{act,args,port}')::uuid, v_m #>> '{act,args,kind}', (v_m #>> '{act,args,shares}')::int);
    if (v_r->>'ok')::boolean is not true then
      raise exception '0480 self-assert FAIL: the invest card''s act did not commit: %', left(v_r::text, 400);
    end if;

    -- (f) RISK: a sea's level is world.sea_danger's; a course through a bounty pirate's home carries her bounty (the bounties lit)
    if exists (select 1 from jsonb_array_elements(world.sea_danger()) d join public.seas s on s.code = d->>'sea_code'
                where public.hq_sea_level(s.id) <> (d->>'level')::int) then
      raise exception '0480 self-assert FAIL: a sea''s level is not world.sea_danger''s';
    end if;
    update public.world_config set value = 'true'::jsonb where key in ('pirate_bounties_enabled', 'pirates_bite', 'economy_closed');
    select f.id into v_pirate from public.fleets f where f.id <> v_fl order by f.id limit 1;
    insert into public.pirate_bounties (slot, fleet_id, epithet, given, home_port, named_at, taken, took)
    values (50, v_pirate, 'Probe', 'Quadro', (select p.id from public.ports p where p.code = 'SET'), now() - interval '2 hours', 1, '[]'::jsonb);
    v_r := public.hq_course_risk(array['LIS', 'SET']);
    if not public.bounty_on() or v_r->>'bounty' is null or v_r->>'pirate' is null then
      raise exception '0480 self-assert FAIL: a course through a bounty pirate''s home carries no bounty: %', v_r;
    end if;
    if (v_r->>'danger')::int <> greatest(public.hq_sea_level((select p.sea_id from public.ports p where p.code = 'LIS')),
                                         public.hq_sea_level((select p.sea_id from public.ports p where p.code = 'SET'))) then
      raise exception '0480 self-assert FAIL: a course''s danger is not the highest of its waters: %', v_r;
    end if;

    -- (g) SIGNED OUT, and a merchant: no company
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{}', true);
    if world.hq_board() is distinct from '{"on": true, "company": false}'::jsonb then
      raise exception '0480 self-assert FAIL: lit and signed out, the read is not {"on": true, "company": false}';
    end if;
    v_note := format('request net %s = preview''s, rate 200/h, yard %s, invest %s %s, risk LIS-SET %s',
                     (v_p #>> '{estimate,totals,net}'), v_yard, v_m #>> '{needs,work}', v_m #>> '{needs,cost}', v_r);
    raise exception using errcode = 'ZX480', message = 'PROBE_ROLLBACK_0480';
  exception when sqlstate 'ZX480' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0480 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0480' or p.auth_uid = c_uid)
     or public.wc('hq_board_enabled') is distinct from 'false'::jsonb or public.wc_int('hq_board_fleets') <> 4
     or public.current_player_id() is not null then
    raise exception '0480 self-assert FAIL: the probe left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0480 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0480 self-assert ok: THE HQ BOARD (dark). % hunk once and reversing; grants and volatility unmoved; no other function moved; four STABLE functions, eight knobs (hq_board_enabled false). Probe (rolled back): dark {"on": false}; lit %; each act committed through its own command. % ms.',
    (select count(*) from hunks_0480), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
