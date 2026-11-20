-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0459 - A TRIP IS QUOTED AS IT IS SAILED  (its time, the weight of a good bought on the way, no stores from an anchorage: the three faults 0454
--        left, docs/dev-log/2026-11-18-stores-quote.md "Not changed")
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE FAULTS (reproduced on the local chain at 0458 by proof 162, before this file; docs/dev-log/2026-11-19-quote-faults.md):
--   1. THE TIME. world.trip_cost (the Map's Send fleet) and Trade's rows (world.board_sell, world.good_board) said a trip's days and arrive_at at
--      her speed in port (voyage.fleet_speed once, or world.board_origin's `speed`). The SAIL freezes her speed after the leg's top-up
--      (voyage.depart), and since 0454 the walk already reads that speed for the days it settles (world.trip_leg); only the time was left on the
--      speed in port. Proof 162: Lisbon to Reykjavik 1,634.5 nm, quoted 4.54 d, sailed 4.5713 d (15.0000 kn in port, 14.8979 laden).
--   2. A GOOD BOUGHT ON THE WAY. Trade's board walked the legs after the buy city with the cargo aboard NOW (world.board_legs knew nothing of the
--      amount), so a full hold bought there was not in her speed (fill = cargo + stores over her hold, load_speed_penalty): the days, the wages and
--      the stores after the buy were a lighter ship's. Proof 162: 378 horses (567 t) bought at Setubal, sold at Nantes: stores 13 quoted, 15
--      charged; 2.15 d quoted, 2.82 d sailed (11.25 kn laden, not 15).
--   3. AN ANCHORAGE. From her own anchor the walk topped her up for the way in to the nearest harbour (world.trip_leg with a top-up); cmd.do_sail
--      buys stores only when she is docked. Proof 162: the row said 1 of stores, the SAIL bought 0.
-- THE FIX (decided by default; one home for each rule):
--   DROP+CREATE world.trip_leg   + `sail_days`: the leg's sailing days at her speed laden with its stores (voyage.depart's speed, voyage-days with
--                                their fraction); `sea_days` = that rounded up, never under one, as before. A hull's other keys (cap, cargo) ride
--                                through the walk. Without a top-up and without p_sea, the leg is walked on the casks she has (the anchorage).
--   RE-CUT world.trip_cost       each leg's days and the trip's sail_days are world.trip_leg's sail_days; its speed in port goes.
--   RE-CUT world.trip_hulls      + cap and cargo (tuns) a hull, so a buy can be stowed and weighed.
--   RE-CUT voyage.fleet_speed_of p_stores may carry `cargo` too (as water and food): the speed of a hull with the cargo walked aboard.
--   NEW public.stow_takes        THE STOWING RULE, public.fleet_load's loop moved out whole (largest hull first, equal hulls by id, whole units in the
--                                room beside her cargo and stores). RE-CUT public.fleet_load: it loads what stow_takes says. Nothing a buy loads moves.
--   NEW world.trip_stow          a buy on the way, put into walked hulls by public.stow_takes: cargo up, and the stores' room (public.ship_stores_room)
--                                as public.supply_needs would read it then.
--   NEW world.board_trips        world.board_legs' walk (0361), moved there whole, with: the way in from an anchorage walked with no top-up; the buy
--                                stowed when she reaches the buy city (p_ctx `buy`: units, bulk); and each row's t_sail, t_days and t_arrive (the time
--                                to her first harbour is world.board_origin's lead_at; the rest walked; the calls on the way at time_compression).
--   RE-CUT world.board_legs      its walk is world.board_trips.
--   RE-CUT world.board_sell      one amount for every row (good_board): its legs are walked with the buy; a priced row whose units the legs were not
--                                walked with (FIT, or legs handed over by world.best_sales) is walked again with them (one walk a distinct count).
--                                days, sail_days, arrive_at, supplies, wages and profit read the walk.
--   RE-CUT world.good_board      a BUY AT row's days, sail_days and arrive_at read the walk.
--   RE-CUT world.best_sales      the legs it shares for a good bought here are not walked (`only` none): world.board_sell walks each good's priced
--                                rows with that good's own amount aboard, and only those rows are served (lean).
-- WHAT A PLAYER SEES CHANGE: on Trade and the Map, a trip's days and arrival are the SAIL's (a little later laden; much later with a full hold
--   bought on the way); the stores, wages and profit of a sale bought on the way are what the SAILs will charge and owe; from an anchorage no
--   stores are quoted for the way in. Nothing that is charged or sailed changes.
-- NOT CHANGED: the way in from an anchorage is measured to the harbour (world.board_origin's lead_nm), the SAIL's course to its roadstead; the
--   longest leg's days and `supplies.days` / `fits` (public.supply_needs) are still at her speed now. A storm or a calm is not foreseen.
-- ROWS: none. No table, job, knob or cron. -- budget: none (no table, no job, no index). -- retention: none.
-- COST: a board for a good bought elsewhere walks its priced rows again only when they buy another amount than the board's (world.best_sales:
--   once a good). Measured on the local world: dev log.
-- LOCKS: CREATE OR REPLACE x8 by hunks, CREATE FUNCTION x4 (one replaces world.trip_leg, dropped), all server only.
--   TIME: under 5 s. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): a new migration reversing the 33 hunks (each OLD text is here verbatim), re-creating 0454's world.trip_leg
--   (its body is in 0454), then dropping world.board_trips, world.trip_stow, public.stow_takes.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path and owner as before (the new ones server only, stable);
--   no other function moved; the speeds of up to 60 live fleets and every armada's unchanged and fleet_speed_of at a fleet's own hulls given =
--   voyage.fleet_speed. THE PROBE (rolled back; it sails nothing and rolls no dice, so no world_secret is read): a probe house's two hulls at
--   Lisbon: public.fleet_load loads the same tuns into the same hulls before and after; her docked board's walk (t_sea, t_sup, t_stop, t_pre,
--   t_post) is the same before and after; world.trip_leg's sail_days is the leg's miles at her speed after the real top-up; world.trip_stow puts a
--   buy where public.fleet_load does, and her speed with it walked aboard is her speed with it loaded.
-- VERSION: 0459 = prod head 0458 + 1.
-- news: none (a repair: Trade and the Map quote a trip's time, a buy on the way and an anchorage as the SAILs then take and charge them)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_fn_before text;
  v_def       text;
  v_pre       text;
  v_old       text;
  v_new       text;
  v_n         int;
  v_note      text;
  v_speeds    jsonb;
  v_after     jsonb;
  v_load0     jsonb;
  v_load1     jsonb;
  v_walk0     jsonb;
  v_walk1     jsonb;
  x           record;
  c_recut     constant text[] := array['public.fleet_load(uuid,text,numeric,numeric)', 'voyage.fleet_speed_of(jsonb,numeric,jsonb)', 'world.best_sales(uuid,uuid)', 'world.board_legs(uuid,jsonb)', 'world.board_sell(uuid,uuid,jsonb)', 'world.good_board(uuid,uuid,uuid,numeric)', 'world.trip_cost(uuid,jsonb)', 'world.trip_hulls(uuid)'];
  c_new       constant text[] := array['public.stow_takes(jsonb,numeric,numeric)', 'world.trip_stow(jsonb,numeric,numeric)',
                                       'world.board_trips(uuid,jsonb,jsonb)'];
  c_leg       constant text := 'world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)';
  c_auth      constant uuid := '00000000-0459-4000-8000-0000000000aa';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_recut || array[c_leg, 'voyage.fleet_speed_parts(uuid,boolean)', 'voyage.fleet_speed(uuid)', 'public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)',
                                                   'public.npc_leg_days(numeric,numeric)', 'public.ship_stores_room(uuid,numeric)', 'public.stores_in_hold(numeric)',
                                                   'public.ship_cargo_tuns(uuid)', 'public.ship_hold_capacity(uuid)', 'world.board_origin(uuid)', 'world.best_sales(uuid,uuid)',
                                                   'cmd.assume_identity(uuid)', 'public.form_fleet(uuid,text,uuid)']) f
              where to_regprocedure(f) is null) then
    raise exception '0459 refuses: the walk (0361, 0454), the board (0348, 0350) or an authority they compose is not in this world';
  end if;
  if exists (select 1 from unnest(c_new) f where to_regprocedure(f) is not null) then
    raise exception '0459 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGES, and what must not move ──
  create temp table pre_0459 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0459
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_recut || array[c_leg]) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select f::regprocedure::oid from unnest(c_recut || array[c_leg]) f));
  -- THE SPEEDS OF LIVE FLEETS (up to 60, and every armada's), null fill and full
  create temp table speeds_0459 (id uuid primary key) on commit drop;
  insert into speeds_0459
  select q.id from (select f.id from public.fleets f where exists (select 1 from public.ships s where s.fleet_id = f.id) order by f.id limit 60) q
  union select af.fleet_id from public.armada_fleets af where exists (select 1 from public.ships s where s.fleet_id = af.fleet_id);
  select coalesce(jsonb_agg(jsonb_build_object('f', q.id, 'now', voyage.fleet_speed_at(q.id, null), 'full', voyage.fleet_speed_at(q.id, 1)) order by q.id), '[]'::jsonb)
    into v_speeds
    from speeds_0459 q;
  -- THE PROBE (one body, run before and after; its last part needs this file's functions and runs after only): a probe house's two hulls at Lisbon
  execute $f$
create function pg_temp.probe_0459(p_auth uuid)
returns table(load jsonb, walk jsonb, note text)
language plpgsql
as $body$
declare
  v_pl    uuid;
  v_fl    uuid;
  v_lis   uuid;
  v_to    uuid;
  v_nm    numeric;
  v_good  record;
  v_legs  jsonb;
  v_parts jsonb;
  v_hulls jsonb;
  v_leg   record;
  v_need  record;
  v_s     numeric;
  v_stow  jsonb;
begin
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (p_auth, 'Probe 0459', (select n.id from public.nations n where n.code = 'PRT'), 1000000, false) returning id into v_pl;
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_fl := public.form_fleet(v_pl, 'Probe 0459', v_lis);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Probe 0459', true, true);
  perform public.commission_ship(v_pl, v_fl, 'caravelao', 'Probe 0459 II', false, true);
  -- each hull as her class is drawn (no roll: commission_ship rolls a new hull, and the runs before and after must sail the same two), whole
  update public.ships s set roll_speed = 1, roll_hold = 1, roll_stores = 1, roll_hull = 1, roll_crew = 1, roll_handling = 1,
         crew = greatest(s.crew, c.crew_required), water_t = 0, food_t = 0, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb
    from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fl;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_fl;
  select g.code, g.bulk into v_good from public.goods g order by g.bulk desc, g.code limit 1;
  -- WHAT A LOAD OF MORE THAN FITS PUTS IN EACH HULL (public.fleet_load)
  perform public.fleet_load(v_fl, v_good.code, 100000, 10);
  load := (select jsonb_agg(jsonb_build_array(s.name, s.cargo) order by s.name) from public.ships s where s.fleet_id = v_fl);
  -- HER DOCKED BOARD'S WALK, that cargo aboard (world.board_legs: every harbour she has a passage to)
  perform cmd.assume_identity(p_auth);
  v_legs := world.board_legs(v_fl, world.board_origin(v_fl) || jsonb_build_object('basis', 'on_board'));
  walk := (select jsonb_agg(jsonb_build_array(e->'id', e->'t_sea', e->'t_sup', e->'t_stop', e->'t_pre', e->'t_post') order by e->>'id')
             from jsonb_array_elements(v_legs) e where e ? 't_sea');
  if to_regprocedure('world.trip_stow(jsonb,numeric,numeric)') is not null then
    -- A LEG'S SAILING DAYS are its miles at her speed after the SAIL's own top-up (public.supply_need, cmd.do_provision), holds empty
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_fl;
    select r.port_id, r.nm into v_to, v_nm from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id
     where p.kind = 'HARBOUR' and r.nm between 600 and 1500 order by r.nm, p.code limit 1;
    v_parts := voyage.fleet_speed_parts(v_fl);
    select * into v_leg from world.trip_leg(v_parts, world.trip_hulls(v_fl), v_nm);
    select * into v_need from public.supply_need(v_fl, v_nm);
    perform cmd.do_provision(v_fl, jsonb_build_object('mode', 'DAYS', 'days', v_need.days, 'on_credit', true));
    v_s := voyage.fleet_speed(v_fl);
    if v_leg.sail_days is distinct from v_nm / v_s / 24 or v_leg.sea_days <> greatest(1, ceil(v_nm / v_s / 24)) then
      raise exception '0459 self-assert FAIL: the walk sails % nm in % d (settles %); at her speed after the top-up, % kn, it is % d', v_nm, v_leg.sail_days, v_leg.sea_days, v_s, v_nm / v_s / 24;
    end if;
    -- A BUY ON THE WAY, WALKED: world.trip_stow puts it where public.fleet_load does, and her speed with it walked aboard is her speed with it loaded
    v_parts := voyage.fleet_speed_parts(v_fl);
    v_hulls := world.trip_hulls(v_fl);
    v_stow := world.trip_stow(v_hulls, 100000, v_good.bulk);
    perform public.fleet_load(v_fl, v_good.code, 100000, 10);
    if exists (select 1 from jsonb_array_elements(v_stow) h where (h->>'cargo')::numeric <> public.ship_cargo_tuns((h->>'ship')::uuid))
       or voyage.fleet_speed_of(v_parts, null, v_stow) <> voyage.fleet_speed(v_fl) or voyage.fleet_speed(v_fl) >= v_s then
      raise exception '0459 self-assert FAIL: a buy walked aboard is not a buy loaded: walked %, loaded % (speed walked %, loaded %, empty %)', v_stow,
        (select jsonb_agg(public.ship_cargo_tuns(s.id)) from public.ships s where s.fleet_id = v_fl), voyage.fleet_speed_of(v_parts, null, v_stow), voyage.fleet_speed(v_fl), v_s;
    end if;
    note := format('LIS to %s (%s nm) sails %s d at %s kn after the top-up; a full hold of %s walked aboard is %s t in her hulls as loaded, and %s kn as loaded',
                   (select p.code from public.ports p where p.id = v_to), round(v_nm, 1), round(v_leg.sail_days, 4), v_s, v_good.code,
                   (select sum((h->>'cargo')::numeric) from jsonb_array_elements(v_stow) h), voyage.fleet_speed(v_fl));
  end if;
  return next;
end
$body$
  $f$;
  begin
    select v.load, v.walk into v_load0, v_walk0 from pg_temp.probe_0459(c_auth) v;
    raise exception sqlstate 'BV459' using message = 'before';
  exception when sqlstate 'BV459' then
    null;
  end;

  -- ── 2. THE NEW FUNCTIONS ──
  execute $f$
create function public.stow_takes(p_hulls jsonb, p_qty numeric, p_bulk numeric)
returns table(ship uuid, take numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0459: THE STOWING RULE (public.fleet_load's loop, moved here whole: 0153, 0250, 0345). p_hulls = [{ship, cap, free}]: her hold and the room in it
-- beside her cargo and stores. The largest hull is filled first (equal hulls by id), each with the whole units of p_bulk its room takes, until p_qty
-- is stowed. Answers the units each hull takes (a hull that takes none is not answered). Read by public.fleet_load (a buy, loaded) and
-- world.trip_stow (a buy on the way, walked ahead of her). Server only.
declare
  v_left numeric := p_qty;
  v_take numeric;
  r      record;
begin
  for r in select x.ship, x.free from jsonb_to_recordset(coalesce(p_hulls, '[]'::jsonb)) x(ship uuid, cap numeric, free numeric)
            order by x.cap desc, x.ship loop
    exit when v_left <= 0;
    v_take := least(v_left, floor(greatest(0, r.free) / p_bulk));
    if v_take > 0 then
      ship := r.ship;
      take := v_take;
      v_left := v_left - v_take;
      return next;
    end if;
  end loop;
end
$body$
  $f$;
  execute $f$
create function world.trip_stow(p_hulls jsonb, p_units numeric, p_bulk numeric)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0459: A BUY ON THE WAY, PUT INTO HER WALKED HULLS (world.trip_hulls' shape, as world.trip_leg leaves them at the buy city): public.stow_takes
  -- places p_units of p_bulk as public.fleet_load will (the room beside her cargo and her casks there), each hull's cargo grows by its tuns, and
  -- the room her stores may fill is public.ship_stores_room's for that cargo (as public.supply_needs reads it then). Read by world.board_trips.
  select coalesce(jsonb_agg(h.e || case when st.take is null then '{}'::jsonb
                                        else jsonb_build_object('cargo', (h.e->>'cargo')::numeric + st.take * p_bulk,
                                                                'room', public.ship_stores_room((h.e->>'ship')::uuid,
                                                                                                (h.e->>'cap')::numeric - (h.e->>'cargo')::numeric - st.take * p_bulk)) end
                            order by h.i), '[]'::jsonb)
    from jsonb_array_elements(p_hulls) with ordinality h(e, i)
    left join public.stow_takes((select jsonb_agg(jsonb_build_object('ship', x->'ship', 'cap', x->'cap',
                                                                     'free', (x->>'cap')::numeric - (x->>'cargo')::numeric
                                                                             - public.stores_in_hold(coalesce((x->>'water')::numeric, 0) + coalesce((x->>'food')::numeric, 0))))
                                   from jsonb_array_elements(p_hulls) x), p_units, p_bulk) st on st.ship = (h.e->>'ship')::uuid
$body$
  $f$;

  -- ── 3. THE WALK OF ONE LEG, with its sailing days (dropped and created: its answer gains a column) ──
  drop function world.trip_leg(jsonb, jsonb, numeric, boolean, numeric);
  execute $f$
create function world.trip_leg(p_speed jsonb, p_hulls jsonb, p_nm numeric, p_top boolean default true, p_sea numeric default null)
returns table(hulls jsonb, water_t numeric, food_t numeric, sea_days numeric, sail_days numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0361: ONE LEG OF A TRIP, WALKED (world.trip_cost and world.board_trips ask it). Every hull of p_hulls (world.trip_hulls) is topped up for a leg
-- of p_nm as cmd.do_sail tops her (public.stores_topup to public.npc_leg_days), then the leg's settled days are eaten at water_per_crew_day and
-- food_per_crew_day a crew, as voyage.settle eats them: every day begun is a day settled (voyage.total_days: the hours over 24, rounded up, never
-- under one). Answers her hulls as she arrives, the tuns of water and food the top-up took on (public.stores_cost prices them), and the days
-- settled (public.fleet_wage is owed for each).
-- 0454: AT HER SPEED AT EACH DEPARTURE, as cmd.do_sail reads it. p_speed is her voyage.fleet_speed_parts, read once by the caller: the top-up's
-- days at voyage.fleet_speed_of with the casks she carries INTO this departure (public.supply_need's reading), the settled days at
-- voyage.fleet_speed_of with the casks topped up (voyage.depart's: the speed frozen for the leg).
-- 0459: + sail_days, THE LEG'S TIME: p_nm at that frozen speed, in voyage-days with their fraction (voyage.depart's eta; sea_days is it rounded up).
-- A hull's other keys (cap, cargo: world.trip_hulls, world.trip_stow) ride through; her cargo is in her speed (voyage.fleet_speed_of).
--   p_top false  nothing is bought (a voyage already under way; or from an anchorage, where cmd.do_sail buys nothing): the leg on the casks she has
--   p_sea        the days to settle, when the caller knows them (a voyage under way: what is left of it); then no speed is read and sail_days is null
declare
  v_wpd    numeric := public.wc_num('water_per_crew_day');
  v_fpd    numeric := public.wc_num('food_per_crew_day');
  v_top    numeric;
  v_w      numeric;
  v_f      numeric;
  v_topped jsonb := '[]'::jsonb;
  h        jsonb;
begin
  if p_top then
    v_top := public.npc_leg_days(p_nm, greatest(voyage.fleet_speed_of(p_speed, null, p_hulls), 0.1));
  end if;
  water_t := 0;
  food_t := 0;
  for h in select e from jsonb_array_elements(p_hulls) e loop
    v_w := 0;
    v_f := 0;
    if p_top then
      select tu.water_t, tu.food_t into v_w, v_f
        from public.stores_topup((h->>'crew')::numeric, (h->>'water')::numeric, (h->>'food')::numeric, (h->>'room')::numeric, v_top, (h->>'full')::numeric) tu;
    end if;
    water_t := water_t + coalesce(v_w, 0);
    food_t := food_t + coalesce(v_f, 0);
    v_topped := v_topped || jsonb_build_array(h || jsonb_build_object(
      'water', coalesce((h->>'water')::numeric, 0) + coalesce(v_w, 0), 'food', coalesce((h->>'food')::numeric, 0) + coalesce(v_f, 0)));
  end loop;
  if p_sea is null then
    sail_days := p_nm / greatest(voyage.fleet_speed_of(p_speed, null, v_topped), 0.1) / 24;   -- voyage.depart: the miles at the speed frozen for the leg
  end if;
  sea_days := coalesce(p_sea, greatest(1, ceil(sail_days)));   -- voyage.total_days: every day begun is settled, never under one
  hulls := '[]'::jsonb;
  for h in select e from jsonb_array_elements(v_topped) e loop
    hulls := hulls || jsonb_build_array(h || jsonb_build_object(
      'water', greatest(0, (h->>'water')::numeric - coalesce((h->>'crew')::numeric, 0) * v_wpd * sea_days),
      'food',  greatest(0, (h->>'food')::numeric - coalesce((h->>'crew')::numeric, 0) * v_fpd * sea_days)));
  end loop;
  return next;
end
$body$
  $f$;

  -- ── 4. THE BOARD'S WALK, moved out of world.board_legs whole ──
  execute $f$
create function world.board_trips(p_fleet uuid, p_ctx jsonb, p_legs jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0459: THE TRIP TO EVERY HARBOUR SHE HAS A PASSAGE TO, AS THE GAME WILL CHARGE AND SAIL IT (0361's walk, world.board_legs' tail moved here whole;
-- world.board_legs asks it for every row, world.board_sell again for a priced row's own buy). p_legs: world.board_legs' rows (id, nm, stops,
-- max_leg); answered with each row it walks gaining
--   t_stop    the real seconds she lies in port on the way (world.trip_stop_seconds a call: every harbour before the last, the buy city among them)
--   t_sea     the days voyage.settle will owe wages for: every day begun on every leg, and what is left of a voyage under way
--   t_sup     her supplies, her casks walked along the trip (topped up before each leg, the leg's settled days eaten)
--   t_pre     the harbours she calls at carrying the cargo aboard now, in order (codes); t_post: the harbours called at after the buy
--   t_sail    0459: the voyage-days she sails: to the harbour her passages run from as world.board_origin times it (lead_at: a voyage's eta, or
--             the way in from her anchor at her speed now), then every leg at her speed as she leaves on it (world.trip_leg's sail_days)
--   t_days    t_sail and the calls on the way at time_compression (world.trip_cost's `days`)
--   t_arrive  lead_at, then the legs' days and the calls on the way in real time
-- A row whose way a leg of the sailed-distance table cannot measure gains none of them (and any it had are taken off: a row walked again).
-- It reads of p_ctx: world.board_origin's answer (origin, lead_nm, lead_at, lead_stops, where.kind, passages); basis (on_board: her cargo sailed
-- from where she is; else bought first at src.code); `only` (harbour ids: only those rows are walked); and 0459's `buy` ({units, bulk}: what is
-- bought at the buy city, stowed there by world.trip_stow and in her speed from there on; absent, nothing is bought on the way).
--   AN ANCHORAGE: the way in is walked on the casks she has (cmd.do_sail buys stores only docked); a VOYAGE UNDER WAY: what is left to settle.
declare
  v_player  uuid := public.current_player_id();
  v_origin  uuid := (p_ctx->>'origin')::uuid;
  v_lead_nm numeric := (p_ctx->>'lead_nm')::numeric;
  v_lead_at timestamptz := coalesce((p_ctx->>'lead_at')::timestamptz, now());
  v_lead_stops text[] := array(select jsonb_array_elements_text(p_ctx->'lead_stops'));
  v_passages jsonb := p_ctx->'passages';
  v_basis   text := p_ctx->>'basis';
  v_src     record;
  v_src_id  uuid;
  v_onb     boolean := coalesce((p_ctx->>'basis') = 'on_board', false);
  v_kind    text := p_ctx->'where'->>'kind';
  v_units   numeric := (p_ctx->'buy'->>'units')::numeric;
  v_bulk    numeric := (p_ctx->'buy'->>'bulk')::numeric;
  v_nb      int;                     -- the legs walked before the buy (null: nothing is bought on the way)
  v_hb      jsonb;                   -- her hulls with the buy aboard: every row reaches the buy city by the same harbours, so it is stowed once
  v_tc      numeric := public.wc_num('time_compression');
  v_lead_d  numeric;                 -- the voyage-days to the harbour her passages run from (lead_at)
  v_speed   jsonb;                   -- her voyage.fleet_speed_parts, read once: world.trip_leg asks her speed of them at each departure
  v_prep    numeric := world.trip_stop_seconds();
  v_ocode   text;
  v_hulls   jsonb;
  v_lead    boolean := false;        -- she is not in a berth: her way to the harbour her passages run from comes first
  v_h0      jsonb;
  v_sup0    bigint := 0;
  v_sea0    numeric := 0;
  v_skip    int := coalesce(cardinality(v_lead_stops), 0);
  v_pre     text[] := '{}';          -- bought first elsewhere: the harbours to the buy city, and it
  v_seq     text[];
  v_key     text;
  -- a way already walked, by its harbours in order: her hulls there, the supplies, the days settled and the days sailed so far
  m_key     text[] := '{}';
  m_h       jsonb[] := '{}';
  m_s       bigint[] := '{}';
  m_d       numeric[] := '{}';
  m_t       numeric[] := '{}';
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
  v_sail    numeric;
  v_h       jsonb;
  v_sup     bigint;
  v_seas    numeric;
  v_sails   numeric;
  v_ok      boolean;
  v_npre    int;
  v_m       jsonb;
  v_n       int;
  ti        int;
  tr        record;
begin
  select p_ctx->'src'->>'code' as code into v_src;
  v_src_id := (select p.id from public.ports p where v_basis <> 'on_board' and p.code = v_src.code);
  v_ocode := (select p.code from public.ports p where p.id = v_origin);
  v_hulls := world.trip_hulls(p_fleet);
  v_h0 := v_hulls;
  v_speed := voyage.fleet_speed_parts(p_fleet);
  v_lead_d := greatest(0, extract(epoch from v_lead_at - now())) * v_tc / 86400;
  if v_origin is not null and v_kind = 'sailing' then
    -- a voyage under way: what is left of it to settle is owed too; nothing more is bought for it
    select greatest(0, voyage.total_days(v.id) - v.last_settled_day) into v_n
      from public.voyages v where v.fleet_id = p_fleet and v.status = 'SAILING' order by v.departed_at desc limit 1;
    select tl.hulls, tl.sea_days into v_h0, v_sea0 from world.trip_leg(null, v_hulls, 0, false, coalesce(v_n, 0)) tl;   -- under way, no speed is read
    v_lead := true;
  elsif v_origin is not null and v_kind = 'at_sea' and v_lead_nm > 0 then
    -- at anchor: the miles to the nearest harbour are her first leg (0183), sailed on the casks she has: cmd.do_sail buys stores only docked
    select tl.hulls, tl.sea_days into v_h0, v_sea0 from world.trip_leg(v_speed, v_hulls, v_lead_nm, false) tl;
    v_lead := true;
  end if;
  if not v_onb and v_src_id is not null and v_src_id is distinct from v_origin then
    select array(select jsonb_array_elements_text(e->'stops')) || v_src.code into v_pre
      from jsonb_array_elements(v_passages) e
     where (e->>'port_id')::uuid = v_src_id and jsonb_typeof(e->'nm') = 'number' and jsonb_typeof(e->'stops') = 'array';
    v_pre := coalesce(v_pre, '{}');   -- no passage to the buy city: no row below has miles
  end if;
  -- THE BUY: stowed as she leaves the buy city (where she lies, or at the end of the harbours to it)
  if not v_onb and v_src_id is not null and coalesce(v_units, 0) > 0 and coalesce(v_bulk, 0) > 0 then
    v_nb := case when v_src_id = v_origin then 0 when cardinality(v_pre) > 0 then cardinality(v_pre) end;
  end if;
  for tr in
    select l.id, p.code, l.stops, l.max_leg
      from jsonb_to_recordset(p_legs) l(id uuid, nm numeric, stops text[], max_leg numeric)
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
      v_h := v_h0; v_sup := v_sup0; v_seas := v_sea0; v_sails := 0; v_ok := true;
      v_n := coalesce(cardinality(v_seq), 0);
      v_k := 0;
      -- the way to the harbour before this one is, nearly always, walked already (the rows come nearest in calls first): take it up from the longest way walked
      for ti in reverse v_n - 1 .. 1 loop
        v_pos := array_position(m_key, v_key || '>' || array_to_string(v_seq[1:ti], '>'));
        if v_pos is not null then
          v_key := m_key[v_pos]; v_h := m_h[v_pos]; v_sup := m_s[v_pos]; v_seas := m_d[v_pos]; v_sails := m_t[v_pos];
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
        if ti - 1 = v_nb then
          v_hb := coalesce(v_hb, world.trip_stow(v_h, v_units, v_bulk));   -- the buy, aboard as she leaves the buy city
          v_h := v_hb;
        end if;
        select tl.hulls, tl.water_t, tl.food_t, tl.sea_days, tl.sail_days into v_h, v_w, v_f, v_sea, v_sail from world.trip_leg(v_speed, v_h, v_nm) tl;
        v_sup := v_sup + public.stores_cost(v_player, v_w, v_f);
        v_seas := v_seas + v_sea;
        v_sails := v_sails + v_sail;
        m_key := m_key || v_key; m_h := m_h || v_h; m_s := m_s || v_sup; m_d := m_d || v_seas; m_t := m_t || v_sails;
      end loop;
      if v_ok then
        -- the harbours she arrives at with the cargo aboard now, and those after the buy
        v_npre := case when v_onb then v_n else coalesce(cardinality(v_pre), 0) end;
        v_m := v_m || jsonb_build_object('t_sea', v_seas, 't_sup', v_sup,
                 't_pre', to_jsonb(case when v_lead then array[v_ocode] else '{}'::text[] end || v_seq[1:v_npre]),
                 't_post', to_jsonb(v_seq[v_npre + 1:]),
                 't_sail', v_lead_d + v_sails,
                 't_days', v_lead_d + v_sails + (v_m->>'t_stop')::numeric * v_tc / 86400,
                 't_arrive', v_lead_at + make_interval(secs => (v_sails * 86400 / v_tc + (v_m->>'t_stop')::numeric)::double precision));
      end if;
    end if;
    v_xid := v_xid || tr.id;
    v_xj := v_xj || v_m;
  end loop;
  return (select coalesce(jsonb_agg(case when x.id is null then e
                                         else (e - array['t_stop', 't_sea', 't_sup', 't_pre', 't_post', 't_sail', 't_days', 't_arrive']) || x.j end), '[]'::jsonb)
            from jsonb_array_elements(p_legs) e
            left join unnest(v_xid, v_xj) x(id, j) on x.id = (e->>'id')::uuid);
end
$body$
  $f$;

  -- ── 5. THE HUNKS ──
  create temp table hunks_0459 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0459 values
  ($h$voyage.fleet_speed_of(jsonb,numeric,jsonb)$h$, 1,
$h$  -- ([{ship, water, food}], world.trip_hulls' shape) gives a hull those casks in place of her own: a trip walked ahead of her (world.trip_leg).
$h$,
$h$  -- ([{ship, water, food}], world.trip_hulls' shape) gives a hull those casks in place of her own: a trip walked ahead of her (world.trip_leg).
  -- 0459: and `cargo` (tuns by bulk), the cargo she carries there: a good bought on the way weighs her down from the buy city on (world.trip_stow).
$h$),
  ($h$voyage.fleet_speed_of(jsonb,numeric,jsonb)$h$, 2,
$h$jsonb_build_object('water', e -> 'water', 'food', e -> 'food'))$h$,
$h$jsonb_build_object('water', e -> 'water', 'food', e -> 'food', 'cargo', e -> 'cargo'))$h$),
  ($h$world.trip_hulls(uuid)$h$, 1,
$h$  -- 0454: `ship` (her id), so the walk asks the speed of each hull at the casks it walked (voyage.fleet_speed_of).
$h$,
$h$  -- 0454: `ship` (her id), so the walk asks the speed of each hull at the casks it walked (voyage.fleet_speed_of).
  -- 0459: `cap` (her hold, public.ship_hold_capacity) and `cargo` (her cargo in tuns, public.ship_cargo_tuns), so a buy on the way is stowed as
  -- public.fleet_load stows it and weighs her down as it will (world.trip_stow, voyage.fleet_speed_of).
$h$),
  ($h$world.trip_hulls(uuid)$h$, 2,
$h$           'ship', s.id, 'crew', s.crew, 'water', s.water_t, 'food', s.food_t,
$h$,
$h$           'ship', s.id, 'crew', s.crew, 'water', s.water_t, 'food', s.food_t,
           'cap', hc.cap, 'cargo', public.ship_cargo_tuns(s.id),
$h$),
  ($h$public.fleet_load(uuid,text,numeric,numeric)$h$, 1,
$h$  v_take numeric;
$h$,
$h$  -- 0459: v_take went with the stowing rule to public.stow_takes
$h$),
  ($h$public.fleet_load(uuid,text,numeric,numeric)$h$, 2,
$h$  for r in select s.id,
                  hc.cap,
                  hc.cap - public.ship_cargo_tuns(s.id)
                    - public.stores_in_hold(s.water_t + s.food_t) as free   -- 0345: lit, the stores keep their own space
             from public.ships s
            cross join lateral (select public.ship_hold_capacity(s.id) as cap offset 0) hc   -- 0250: read once a hull
            where s.fleet_id = p_fleet order by cap desc, s.id loop   -- 0153: equal hulls by id
    exit when v_left <= 0;
    v_take := least(v_left, floor(greatest(0, r.free) / v_bulk));
    if v_take > 0 then
      update public.ships
         set cargo = jsonb_set(cargo, array[p_good_code],
                     to_jsonb(coalesce((cargo->>p_good_code)::numeric, 0) + v_take), true)
       where id = r.id;
      v_left := v_left - v_take;
    end if;
  end loop;
$h$,
$h$  -- 0459: THE STOWING RULE is public.stow_takes (this loop's rule, moved there whole: largest hull first, equal hulls by id, whole units in the
  -- room beside her cargo and stores), so a trip walked ahead of her stows a buy on the way as this does (world.trip_stow)
  for r in select st.ship as id, st.take
             from public.stow_takes((select coalesce(jsonb_agg(jsonb_build_object('ship', s.id, 'cap', hc.cap,
                                               'free', hc.cap - public.ship_cargo_tuns(s.id)
                                                         - public.stores_in_hold(s.water_t + s.food_t))), '[]'::jsonb)   -- 0345: lit, the stores keep their own space
                                       from public.ships s
                                      cross join lateral (select public.ship_hold_capacity(s.id) as cap offset 0) hc   -- 0250: read once a hull
                                      where s.fleet_id = p_fleet), p_qty, v_bulk) st loop
    update public.ships
       set cargo = jsonb_set(cargo, array[p_good_code],
                   to_jsonb(coalesce((cargo->>p_good_code)::numeric, 0) + r.take), true)
     where id = r.id;
    v_left := v_left - r.take;
  end loop;
$h$),
  ($h$world.trip_cost(uuid,jsonb)$h$, 1,
$h$  v_speed  numeric;
$h$,
$h$  v_lsail  numeric;   -- 0459: a leg's sailing days at her speed laden with its stores (world.trip_leg), as voyage.depart times it
$h$),
  ($h$world.trip_cost(uuid,jsonb)$h$, 2,
$h$  v_speed := greatest(voyage.fleet_speed(p_fleet), 0.1);
$h$,
$h$  -- 0459: no speed in port here: each leg's days are world.trip_leg's, at her speed as she leaves on it
$h$),
  ($h$world.trip_cost(uuid,jsonb)$h$, 3,
$h$    select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_hulls, v_w, v_f, v_sea from world.trip_leg(voyage.fleet_speed_parts(p_fleet), v_hulls, v_nm) tl;
$h$,
$h$    select tl.hulls, tl.water_t, tl.food_t, tl.sea_days, tl.sail_days into v_hulls, v_w, v_f, v_sea, v_lsail from world.trip_leg(voyage.fleet_speed_parts(p_fleet), v_hulls, v_nm) tl;
$h$),
  ($h$world.trip_cost(uuid,jsonb)$h$, 4,
$h$    v_sail := v_sail + v_nm / v_speed / 24;
$h$,
$h$    v_sail := v_sail + v_lsail;
$h$),
  ($h$world.trip_cost(uuid,jsonb)$h$, 5,
$h$'days', round(v_nm / v_speed / 24, 2),$h$,
$h$'days', round(v_lsail, 2),$h$),
  ($h$world.board_legs(uuid,jsonb)$h$, 1,
$h$-- rest keep the columns they had). A leg the sailed-distance table cannot measure leaves t_sea .. t_post out.
$h$,
$h$-- rest keep the columns they had). A leg the sailed-distance table cannot measure leaves t_sea .. t_post out.
-- 0459: THE WALK IS world.board_trips (this body's tail, moved there whole; world.board_sell asks it again for a row's own buy): from an anchorage
-- nothing is bought for the way in, a good bought on the way weighs her down from the buy city on, and each row gains its days and arrive_at as walked.
$h$),
  ($h$world.board_legs(uuid,jsonb)$h$, 2,
$h$  v_legs    jsonb;
  -- 0361: the trip to every harbour
  v_onb     boolean := coalesce((p_ctx->>'basis') = 'on_board', false);
  v_kind    text := p_ctx->'where'->>'kind';
  v_speed   jsonb;                   -- 0454: her voyage.fleet_speed_parts, read once a board: world.trip_leg asks her speed of them at each departure
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
$h$,
$h$  v_legs    jsonb;
  -- 0459: the walk's own variables went with it to world.board_trips
$h$),
  ($h$world.board_legs(uuid,jsonb)$h$, 3,
$h$  -- 0361: THE TRIP TO EVERY HARBOUR SHE HAS A PASSAGE TO, walked as world.trip_cost walks it (world.trip_leg), each way walked once
  v_ocode := (select p.code from public.ports p where p.id = v_origin);
  v_hulls := world.trip_hulls(p_fleet);
  v_h0 := v_hulls;
  v_speed := voyage.fleet_speed_parts(p_fleet);
  if v_origin is not null and v_kind = 'sailing' then
    -- a voyage under way: what is left of it to settle is owed too; nothing more is bought for it
    select greatest(0, voyage.total_days(v.id) - v.last_settled_day) into v_n
      from public.voyages v where v.fleet_id = p_fleet and v.status = 'SAILING' order by v.departed_at desc limit 1;
    select tl.hulls, tl.sea_days into v_h0, v_sea0 from world.trip_leg(null, v_hulls, 0, false, coalesce(v_n, 0)) tl;   -- 0454: under way, no speed is read
    v_lead := true;
  elsif v_origin is not null and v_kind = 'at_sea' and v_lead_nm > 0 then
    -- at anchor: the miles to the nearest harbour are her first leg (0183)
    select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_h0, v_w, v_f, v_sea0 from world.trip_leg(v_speed, v_hulls, v_lead_nm) tl;
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
        select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_h, v_w, v_f, v_sea from world.trip_leg(v_speed, v_h, v_nm) tl;
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
$h$,
$h$  -- 0361: THE TRIP TO EVERY HARBOUR SHE HAS A PASSAGE TO; 0459: walked by world.board_trips (this tail, moved there whole)
  return world.board_trips(p_fleet, p_ctx, v_legs);
$h$),
  ($h$world.board_sell(uuid,uuid,jsonb)$h$, 1,
$h$  v_sell    jsonb;
$h$,
$h$  v_sell    jsonb;
  v_walked  numeric;   -- 0459: the units the legs were walked with aboard from the buy city on (null: nothing bought on the way)
$h$),
  ($h$world.board_sell(uuid,uuid,jsonb)$h$, 2,
$h$    v_legs := world.board_legs(p_fleet, p_ctx);
$h$,
$h$    -- 0459: ONE AMOUNT BOUGHT FOR EVERY ROW (not FIT): the legs are walked with it aboard from the buy city on
    if v_basis <> 'on_board' and not v_fit and coalesce(v_src.units, 0) > 0 then
      v_walked := v_src.units;
    end if;
    v_legs := world.board_legs(p_fleet, p_ctx || case when v_walked is null then '{}'::jsonb
                                                      else jsonb_build_object('buy', jsonb_build_object('units', v_walked, 'bulk', g.bulk)) end);
$h$),
  ($h$world.board_sell(uuid,uuid,jsonb)$h$, 3,
$h$           l.t_sea, l.t_sup, l.t_stop, l.t_pre, l.t_post   -- 0361: the trip there, as the game will charge it (world.board_legs)
$h$,
$h$           l.t_sea, l.t_sup, l.t_stop, l.t_pre, l.t_post,   -- 0361: the trip there, as the game will charge it (world.board_legs)
           l.t_sail, l.t_days, l.t_arrive   -- 0459: and its time as walked (world.board_trips)
$h$),
  ($h$world.board_sell(uuid,uuid,jsonb)$h$, 4,
$h$                                        t_sea numeric, t_sup bigint, t_stop numeric, t_pre text[], t_post text[]) on l.id = p.id   -- 0361
$h$,
$h$                                        t_sea numeric, t_sup bigint, t_stop numeric, t_pre text[], t_post text[],
                                        t_sail numeric, t_days numeric, t_arrive timestamptz) on l.id = p.id   -- 0361; 0459: + t_sail, t_days, t_arrive
$h$),
  ($h$world.board_sell(uuid,uuid,jsonb)$h$, 5,
$h$  ), quoted as materialized (
$h$,
$h$  ), walks as materialized (
    -- 0459: A GOOD BOUGHT FIRST WEIGHS HER DOWN from the buy city on. A priced row whose units the legs were not walked with (FIT: each row's own;
    -- legs handed over by world.best_sales: walked with nothing bought) is walked again with them aboard: world.board_trips, once a distinct count
    select (x.e->>'id')::uuid as id, (x.e->>'t_sea')::numeric as t_sea, (x.e->>'t_sup')::bigint as t_sup, (x.e->>'t_sail')::numeric as t_sail,
           (x.e->>'t_days')::numeric as t_days, (x.e->>'t_arrive')::timestamptz as t_arrive
      from (select l.n, jsonb_agg(l.id) as ids from lots l
             where v_basis <> 'on_board' and l.n > 0 and l.n is distinct from v_walked group by l.n) d
     cross join lateral jsonb_array_elements(world.board_trips(p_fleet, p_ctx || jsonb_build_object('buy', jsonb_build_object('units', d.n, 'bulk', g.bulk),
                                                                                                  'only', d.ids), v_legs)) x(e)
     where d.ids @> jsonb_build_array(x.e->'id')
  ), quoted as materialized (
$h$),
  ($h$world.board_sell(uuid,uuid,jsonb)$h$, 6,
$h$           case when r.nm is not null and v_speed > 0 then (v_lead_nm + r.nm) / v_speed / 24 end as days,
           r.t_sea, r.t_pre, r.t_post,   -- 0361
           case when r.nm is not null and v_speed > 0   -- 0361: + the real seconds in port on the way
                then v_lead_at + make_interval(secs => (r.nm / v_speed * 3600 / v_tc + coalesce(r.t_stop, 0))::double precision) end as arrive_at
      from ranked r join lots l on l.id = r.id
$h$,
$h$           -- 0459: the trip as walked (world.board_trips: her speed at each departure, the calls on the way), again with this row's own buy aboard
           -- when the legs were not walked with it (`walks`)
           case when w.id is null then r.t_days else w.t_days end as days,
           case when w.id is null then r.t_sail else w.t_sail end as t_sail,
           case when w.id is null then r.t_sup else w.t_sup end as t_sup,
           case when w.id is null then r.t_sea else w.t_sea end as t_sea, r.t_pre, r.t_post,   -- 0361
           case when w.id is null then r.t_arrive else w.t_arrive end as arrive_at
      from ranked r join lots l on l.id = r.id
      left join walks w on w.id = r.id
$h$),
  ($h$world.board_sell(uuid,uuid,jsonb)$h$, 7,
$h$'cost', coalesce(r.t_sup, r.sn_cost),$h$,
$h$'cost', coalesce(case when p.id is not null then p.t_sup else r.t_sup end, r.sn_cost),$h$),
  ($h$world.board_sell(uuid,uuid,jsonb)$h$, 8,
$h$then p.proceeds - p.cost - p.tax - p.wages - r.t_sup - p.dock_fee end,$h$,
$h$then p.proceeds - p.cost - p.tax - p.wages - p.t_sup - p.dock_fee end,$h$),
  ($h$world.board_sell(uuid,uuid,jsonb)$h$, 9,
$h$           'days', case when r.nm is not null and v_speed > 0 then round((v_lead_nm + r.nm) / v_speed / 24 + coalesce(r.t_stop, 0) * v_tc / 86400, 2) end,
           'sail_days', case when r.nm is not null and v_speed > 0 then round((v_lead_nm + r.nm) / v_speed / 24, 2) end,
$h$,
$h$           -- 0459: as walked (world.board_trips), not at her speed in port
           'days', round(case when p.id is not null then p.days else r.t_days end, 2),
           'sail_days', round(case when p.id is not null then p.t_sail else r.t_sail end, 2),
$h$),
  ($h$world.good_board(uuid,uuid,uuid,numeric)$h$, 1,
$h$    select x.id, x.t_stop, x.t_sup
$h$,
$h$    select x.id, x.t_stop, x.t_sup, x.t_sail, x.t_days, x.t_arrive   -- 0459: + the trip's time as walked
$h$),
  ($h$world.good_board(uuid,uuid,uuid,numeric)$h$, 2,
$h$x(id uuid, t_stop numeric, t_sup bigint)$h$,
$h$x(id uuid, t_stop numeric, t_sup bigint, t_sail numeric, t_days numeric, t_arrive timestamptz)$h$),
  ($h$world.good_board(uuid,uuid,uuid,numeric)$h$, 3,
$h$    select s.*, tl.t_stop, tl.t_sup,   -- 0361
           case when s.nm is not null and v_speed > 0   -- 0361: + the real seconds in port on the way
                then v_lead_at + make_interval(secs => (s.nm / v_speed * 3600 / v_tc + coalesce(tl.t_stop, 0))::double precision) end as arrive_at
$h$,
$h$    select s.*, tl.t_stop, tl.t_sup,   -- 0361
           tl.t_sail, tl.t_days, tl.t_arrive as arrive_at   -- 0459: the trip's time as walked (world.board_trips), not at her speed in port
$h$),
  ($h$world.good_board(uuid,uuid,uuid,numeric)$h$, 4,
$h$           'days', case when s.nm is not null and v_speed > 0 then round((v_lead_nm + s.nm) / v_speed / 24 + coalesce(s.t_stop, 0) * v_tc / 86400, 2) end,
           'sail_days', case when s.nm is not null and v_speed > 0 then round((v_lead_nm + s.nm) / v_speed / 24, 2) end,
$h$,
$h$           'days', round(s.t_days, 2),   -- 0459: as walked (world.board_trips)
           'sail_days', round(s.t_sail, 2),
$h$),
  ($h$world.best_sales(uuid,uuid)$h$, 1,
$h$        v_legs_buy := world.board_legs(p_fleet, v_ctx);
$h$,
$h$        -- 0459: no row is walked here (`only` none): world.board_sell walks every priced row of a good bought here with that good's own amount aboard
        v_legs_buy := world.board_legs(p_fleet, v_ctx || jsonb_build_object('only', '[]'::jsonb));
$h$),
  ($h$world.board_sell(uuid,uuid,jsonb)$h$, 10,
$h$  v_tc      numeric := public.wc_num('time_compression');
$h$,
$h$  -- 0459: v_tc went with the trip's time to world.board_trips
$h$),
  ($h$world.board_sell(uuid,uuid,jsonb)$h$, 11,
$h$  v_lead_at timestamptz := (p_ctx->>'lead_at')::timestamptz;
$h$,
$h$  -- 0459: v_lead_at went with the trip's time to world.board_trips
$h$),
  ($h$world.good_board(uuid,uuid,uuid,numeric)$h$, 5,
$h$  v_tc      numeric := public.wc_num('time_compression');
$h$,
$h$  -- 0459: v_tc went with the trip's time to world.board_trips
$h$),
  ($h$world.good_board(uuid,uuid,uuid,numeric)$h$, 6,
$h$  v_lead_at timestamptz := now();
$h$,
$h$  -- 0459: v_lead_at went with the trip's time to world.board_trips
$h$),
  ($h$world.good_board(uuid,uuid,uuid,numeric)$h$, 7,
$h$  v_lead_at  := (v_o->>'lead_at')::timestamptz;
$h$,
$h$  -- 0459: (world.board_origin's lead_at is read by world.board_trips)
$h$);

  for x in select distinct h.fn from hunks_0459 h loop
    v_pre := (select p.def from pre_0459 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0459 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0459 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0459 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0459 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0459 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0459) <> 33 or (select count(distinct fn) from hunks_0459) <> cardinality(c_recut) then
    raise exception '0459 self-assert FAIL: the hunks are not the 33 of the 8 re-cut bodies';
  end if;

  -- ── 6. GRANTS: server only (postgres alone, as world.trip_leg stands on prod; the platform grants service_role execute on a new public function by default, so it is named) ──
  revoke all on function public.stow_takes(jsonb, numeric, numeric) from public, anon, authenticated, service_role;
  revoke all on function world.trip_stow(jsonb, numeric, numeric) from public, anon, authenticated, service_role;
  revoke all on function world.board_trips(uuid, jsonb, jsonb) from public, anon, authenticated, service_role;
  revoke all on function world.trip_leg(jsonb, jsonb, numeric, boolean, numeric) from public, anon, authenticated, service_role;

  -- ── 7. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select f::regprocedure::oid from unnest(c_recut || c_new || array[c_leg]) f))) <> v_fn_before then
    raise exception '0459 self-assert FAIL: another function moved';
  end if;
  for x in select f.fn, f.meta, f.now,
                  (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
                     from pg_proc p where p.oid = f.now::regprocedure) as now_meta
             from (select p.fn, p.meta, p.fn as now from pre_0459 p
                   union all select p.fn, p.meta, u.fn from pre_0459 p cross join unnest(c_new) u(fn) where p.fn = c_leg) f loop
    if x.now_meta is distinct from x.meta then
      raise exception '0459 self-assert FAIL: the grants, volatility, definer, search path or owner of % (or what stands in for it) is % and was %', x.now, x.now_meta, x.meta;
    end if;
  end loop;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%world.trip_leg(%'
                and p.oid <> all (array(select f::regprocedure::oid from unnest(array['world.trip_cost(uuid,jsonb)', 'world.board_trips(uuid,jsonb,jsonb)']) f))) then
    raise exception '0459 self-assert FAIL: a function other than world.trip_cost and world.board_trips walks a leg';
  end if;

  -- EVERY SPEED READ IS UNCHANGED; at a fleet's own hulls given (now with their cargo), the walk's reading is hers
  select coalesce(jsonb_agg(jsonb_build_object('f', q.id, 'now', voyage.fleet_speed_at(q.id, null), 'full', voyage.fleet_speed_at(q.id, 1)) order by q.id), '[]'::jsonb)
    into v_after
    from speeds_0459 q;
  if v_after is distinct from v_speeds then
    raise exception '0459 self-assert FAIL: a speed moved: before %, after %', left(v_speeds::text, 400), left(v_after::text, 400);
  end if;
  select count(*) into v_n from speeds_0459 q
   where voyage.fleet_speed_of(voyage.fleet_speed_parts(q.id), null, world.trip_hulls(q.id)) is distinct from voyage.fleet_speed(q.id);
  if v_n > 0 then
    raise exception '0459 self-assert FAIL: % fleet(s) read a different speed at their own hulls given', v_n;
  end if;

  -- ── 8. THE PROBE, AFTER (rolled back by a raised sentinel; it sails nothing and rolls no dice) ──
  begin
    select v.load, v.walk, v.note into v_load1, v_walk1, v_note from pg_temp.probe_0459(c_auth) v;
    raise exception sqlstate 'BV459' using message = v_note;
  exception when sqlstate 'BV459' then
    get stacked diagnostics v_note = message_text;
  end;
  if v_load1 is distinct from v_load0 or v_load0 is null or jsonb_array_length(v_load0) < 2 then
    raise exception '0459 self-assert FAIL: public.fleet_load stows differently: before %, after %', v_load0, v_load1;
  end if;
  if v_walk1 is distinct from v_walk0 or v_walk0 is null or jsonb_array_length(v_walk0) = 0 then
    raise exception '0459 self-assert FAIL: a docked board''s walk moved: before %, after %', left(v_walk0::text, 300), left(v_walk1::text, 300);
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Probe 0459') then
    raise exception '0459 self-assert FAIL: the probe was not rolled back';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0459 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0459 self-assert ok: A TRIP IS QUOTED AS IT IS SAILED. world.trip_leg answers the leg''s sailing days; the board''s walk is world.board_trips (an anchorage buys nothing, a buy on the way is stowed by public.stow_takes and weighed); 33 hunks once each and reversing; % live fleets'' speeds unchanged; grants and volatility as before; no other function moved. Probe: %; public.fleet_load stows % the same; a docked board walks % rows the same. % ms.',
    jsonb_array_length(v_speeds), v_note, v_load1, jsonb_array_length(v_walk1), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop function pg_temp.probe_0459(uuid);
  drop table hunks_0459;
  drop table speeds_0459;
  drop table pre_0459;
end $m$;
