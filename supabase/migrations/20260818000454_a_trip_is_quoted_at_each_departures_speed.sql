-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0454 - A TRIP IS QUOTED AT EACH DEPARTURE'S SPEED  (the Map's trip and Trade's board walked her stores at her speed in port; the SAIL reads
--        her speed with the casks she carries at each departure, so a later leg could cost one day of stores, and one day's wage, more)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE FAULT (recorded 2026-11-16 in PR #752, proof 63: "24 against 23"; reproduced on the local chain at 0453 by proof 157): world.trip_cost
--   (the Map's Send fleet) and world.board_legs (Trade's board, world.board_sell's t_sup / t_sea) walk a trip with world.trip_leg at ONE speed,
--   voyage.fleet_speed read once in port (trip_cost) or world.board_origin's `speed` (the board), before any stores are aboard. The SAIL reads her
--   speed twice a leg (cmd.do_sail): public.supply_need BEFORE the top-up (the days she is topped up for: public.npc_leg_days at her speed with
--   the casks she carries into that departure) and voyage.depart AFTER it (the speed frozen for the leg: the days voyage.settle settles, eats and
--   owes a wage for). Stores weigh (voyage.ship_speed_at: fill = cargo + water + food over her hold, load_speed_penalty 0.25), so laden she is a
--   shade slower. A leg that ends just inside a day in port runs into the next one at sea: one more day eaten and owed, and the next leg's casks
--   start emptier, so its top-up buys more than the quote said. Proof 157, before this file: Lisbon to Arpoador 1,064.5 nm, 2.9927 d in port at
--   14.8212 kn, 3.0073 d laden at 14.7491: the quote said supplies 12, wages 80; the SAILs charged 14 and owed 100.
-- THE FIX (decided by default): ONE speed rule, cut in two at the fill, so the walk can ask it of the casks it walked without reading every hull
--   again each leg (a first cut that re-read them made Trade's board 3 times slower: dev log).
--   NEW voyage.ship_speed_parts(ship)            what one hull's speed is made of, all but her fill: k = her speed stat x her hull's state x her
--                                                hands x the wind (DESIGN K.1), her hold stat, her cargo by bulk, her casks. voyage.ship_speed_at's
--                                                reading of the hull, cut out of it.
--   NEW voyage.ship_speed_of(parts, fill)        the fill put in: round(k x (1 - load_speed_penalty x fill), 4), fill = the one asked, or her cargo
--                                                and casks over her hold. voyage.ship_speed_at's arithmetic, cut out of it.
--   NEW voyage.fleet_speed_parts(fleet, alone)   every hull's parts, the fleet's factor (formation x captains x Navigation, 0015/0027/B.3), and
--                                                either her kind's multiplier (0422) or, in an armada (0367), its other fleets' parts.
--   NEW voyage.fleet_speed_of(parts, fill, stores) the fleet's speed from its parts; `stores` ([{ship, water, food}], world.trip_hulls' shape)
--                                                gives a hull other casks than her own. voyage.fleet_speed_alone_at's and fleet_speed_at's arithmetic.
--   RE-CUT (whole body) voyage.ship_speed_at = ship_speed_of(ship_speed_parts(ship), fill); voyage.fleet_speed_alone_at and voyage.fleet_speed_at
--                                                = fleet_speed_of(fleet_speed_parts(fleet, alone), fill, null). Their signatures stay; EVERY SPEED
--                                                READ TODAY IS UNCHANGED, to the digit (asserted below on live fleets, every armada's among them).
--   NEW world.trip_leg(speed parts, hulls, nm, top, sea)  replaces world.trip_leg(hulls, nm, speed, top, sea) (dropped): the same walk, the
--                                                top-up's days at fleet_speed_of(her walked casks), the leg's settled days at fleet_speed_of(her
--                                                casks topped up): exactly where cmd.do_sail reads her speed. Under way (top false, sea given): no speed.
--   RE-CUT world.trip_hulls (2 hunks)   each hull carries `ship` (her id), so the speed can be asked of each hull's walked casks.
--   RE-CUT world.trip_cost  (1 hunk)    asks world.trip_leg(voyage.fleet_speed_parts(p_fleet), v_hulls, v_nm).
--   RE-CUT world.board_legs (6 hunks)   reads her speed parts once a board and hands them to each world.trip_leg; its v_speed (p_ctx speed, read
--                                       only for the walk) goes.
-- WHAT A PLAYER SEES CHANGE: on Trade and on the Map's Send fleet, a trip's supplies and wages are what the SAILs then charge and owe (a leg that
--   runs into one more day laden now says so: one more day's wage, and the stores that day eats). Nothing that is charged changes.
-- NOT CHANGED (said on the PR): a trip's `days` / `sail_days` / arrive_at are still at her speed in port (world.trip_cost's v_sail and
--   world.board_sell's days; proof 63 holds the time within 3 %). A good bought first on the way weighs her down too; the board still walks
--   the cargo aboard now (0361's "what it does not know"). The way to the nearest harbour from an anchorage is walked with a top-up as before.
-- ROWS: none. No table, job, knob or cron. -- budget: none (no table, no job, no index). -- retention: none.
-- COST: a speed read builds a small jsonb a hull (measured: dev log). The board asks the parts once and does arithmetic each leg.
-- LOCKS: CREATE OR REPLACE x6 (3 whole bodies, 3 by hunks), CREATE FUNCTION x5, DROP FUNCTION x1 (server only: no grant, no client caller).
--   TIME: under 5 s. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): a new migration putting back the three speed bodies (this file's pre-images: 0367's fleet_speed_at and
--   fleet_speed_alone_at, 0250's ship_speed_at), re-creating 0361's world.trip_leg(jsonb,numeric,numeric,boolean,numeric) and reversing the 9
--   hunks (each OLD text is here verbatim); then dropping the five new functions.
-- SELF-ASSERT: each hunk once and reversing; each old speed body swapped whole and reversing; grants, volatility, definer, search path and owner
--   as the functions they stand in for; no other function moved; the speeds of up to 60 live fleets, every armada's fleet and up to 10 of the
--   navy's and the pirates' (null fill and full) and of their hulls (null fill, half, full) unchanged to the digit; fleet_speed_of at a fleet's
--   own casks given = voyage.fleet_speed. THE PROBE (rolled back; it sails nothing and rolls no dice, so no world_secret is read): a probe
--   house's barca at Lisbon, casks empty: the walk's top-up for a leg is public.supply_need's (cmd.do_provision then buys exactly it), the walk's
--   settled days are ceil(nm / her speed after that real top-up / 24), and her speed at written casks equals fleet_speed_of at the same casks given.
-- VERSION: 0454 = prod head 0453 + 1.
-- news: none (a repair: Trade and the Map quote a trip's stores and wages as the SAILs then charge them)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_fn_before text;
  v_def       text;
  v_pre       text;
  v_body      text;
  v_old       text;
  v_new       text;
  v_n         int;
  v_note      text;
  v_speeds    jsonb;
  v_after     jsonb;
  v_pl        uuid;
  v_fl        uuid;
  v_sh        uuid;
  v_lis       uuid;
  v_to        uuid;
  v_nm        numeric;
  v_hulls     jsonb;
  v_need      record;
  v_leg       record;
  v_s0        numeric;
  v_s1        numeric;
  v_w         numeric;
  v_f         numeric;
  x           record;
  c_speed     constant text[] := array['voyage.ship_speed_at(uuid,numeric)', 'voyage.fleet_speed_alone_at(uuid,numeric)', 'voyage.fleet_speed_at(uuid,numeric)'];
  c_new       constant text[] := array['voyage.ship_speed_parts(uuid)', 'voyage.ship_speed_of(jsonb,numeric)', 'voyage.fleet_speed_parts(uuid,boolean)',
                                       'voyage.fleet_speed_of(jsonb,numeric,jsonb)', 'world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)'];
  c_recut     constant text[] := array['world.trip_hulls(uuid)', 'world.trip_cost(uuid,jsonb)', 'world.board_legs(uuid,jsonb)'];
  c_leg_old   constant text := 'world.trip_leg(jsonb,numeric,numeric,boolean,numeric)';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_speed || c_recut || array[c_leg_old, 'public.supply_need(uuid,numeric)', 'public.npc_leg_days(numeric,numeric)',
                                                             'public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)', 'cmd.do_provision(uuid,jsonb)',
                                                             'voyage.fleet_speed(uuid)', 'public.fleet_speed_mult(uuid)', 'public.fleet_kind(uuid)', 'world.ship_stats(uuid)',
                                                             'public.crew_pct(uuid,uuid,text,uuid,timestamp with time zone)', 'public.player_skill_bonus(uuid,text)', 'public.form_fleet(uuid,text,uuid)']) f
              where to_regprocedure(f) is null) or to_regclass('public.armada_fleets') is null then
    raise exception '0454 refuses: the speed (0203, 0367, 0422), the trip walk (0361) or an authority they compose is not in this world';
  end if;
  if exists (select 1 from unnest(c_new) f where to_regprocedure(f) is not null) then
    raise exception '0454 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0454 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0454
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_speed || c_recut || array[c_leg_old]) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select f::regprocedure::oid from unnest(c_speed || c_recut || array[c_leg_old]) f));
  -- THE SPEEDS OF LIVE FLEETS (up to 60, every armada's, up to 10 of the navy's and the pirates'), null fill and full, and of their hulls
  create temp table speeds_0454 (id uuid primary key) on commit drop;
  insert into speeds_0454
  select q.id from (select f.id from public.fleets f where exists (select 1 from public.ships s where s.fleet_id = f.id) order by f.id limit 60) q
  union select af.fleet_id from public.armada_fleets af where exists (select 1 from public.ships s where s.fleet_id = af.fleet_id)
  union select q.id from (select f.id from public.fleets f
                           where public.fleet_kind(f.id) in ('NAVY', 'PIRATE') and exists (select 1 from public.ships s where s.fleet_id = f.id) order by f.id limit 10) q;
  select coalesce(jsonb_agg(jsonb_build_object('f', q.id, 'now', voyage.fleet_speed_at(q.id, null), 'full', voyage.fleet_speed_at(q.id, 1),
                                               'alone', voyage.fleet_speed_alone_at(q.id, null),
                                               'hulls', (select jsonb_agg(jsonb_build_array(s.id, voyage.ship_speed_at(s.id, null), voyage.ship_speed_at(s.id, 0.5), voyage.ship_speed_at(s.id, 1)) order by s.id)
                                                           from public.ships s where s.fleet_id = q.id)) order by q.id), '[]'::jsonb)
    into v_speeds
    from speeds_0454 q;

  -- ── 2. THE SPEED RULE, CUT IN TWO AT THE FILL: what a hull's and a fleet's speed is made of, and the fill put in ──
  execute $f$
create function voyage.ship_speed_parts(p_ship uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0454: WHAT ONE HULL'S SPEED IS MADE OF, all but her fill (voyage.ship_speed_at's reading of the hull, 0074 / 0203 / 0250, cut out of it):
--   k      her speed stat (world.ship_stats, the fitted hull) x her hull's state (hull_speed_floor up to 1 by durability over her rolled max) x her hands
--          (crew_short_speed_mult when short) x the wind (wind_mult_v0; M_officer 1.00: DESIGN K.1)
--   hold   her hold stat (null when she has none: voyage.ship_speed_of refuses then, only where it needs her own fill)
--   cargo  her cargo in tuns by bulk (DESIGN G.3: bullion is dense and cheap to carry, timber is not); water, food: her casks
-- voyage.ship_speed_of puts the fill in. Read by voyage.fleet_speed_parts and voyage.ship_speed_at. Server only.
declare
  s         public.ships%rowtype;
  c         public.ship_classes%rowtype;
  v_cargo_t numeric;
  v_stats   jsonb;
begin
  select * into s from public.ships where id = p_ship;
  select * into c from public.ship_classes where id = s.class_id;
  if s.id is null then
    raise exception 'E_NO_SUCH_SHIP: %', p_ship using errcode = 'P0001';
  end if;
  select coalesce(sum((select (e.value)::text::numeric * g.bulk from public.goods g where g.code = e.key)), 0) into v_cargo_t
    from jsonb_each(s.cargo) e;
  v_stats := world.ship_stats(p_ship);
  if (v_stats ->> 'speed') is null then
    raise exception 'E_NO_SUCH_STAT: no ship % has a stat called "%"', p_ship, 'speed' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'ship', p_ship,
    'k', (v_stats ->> 'speed')::numeric
         * (public.wc_num('hull_speed_floor') + (1 - public.wc_num('hull_speed_floor')) * least(1.0, s.durability / (public.ship_base(p_ship)).durability))
         * (case when s.crew >= c.crew_required then 1.0 else public.wc_num('crew_short_speed_mult') end)
         * public.wc_num('wind_mult_v0'),
    'hold', (v_stats ->> 'hold')::numeric,
    'cargo', v_cargo_t,
    'water', s.water_t,
    'food', s.food_t);
end
$body$
  $f$;
  execute $f$
create function voyage.ship_speed_of(p_parts jsonb, p_fill numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0454: ONE HULL'S SPEED FROM ITS PARTS (voyage.ship_speed_parts) AND A FILL (voyage.ship_speed_at's arithmetic, cut out of it): p_fill (1 = her
-- hold full, the slowest she leaves at; 0203), or, null, the fill her parts carry: cargo + water + food over her hold. round(k x (1 -
-- load_speed_penalty x fill), 4). A caller that walks her ahead (voyage.fleet_speed_of) hands other casks in the parts. Server only.
declare
  v_fill numeric;
begin
  if p_fill is null and (p_parts ->> 'hold') is null then
    raise exception 'E_NO_SUCH_STAT: no ship % has a stat called "%"', p_parts ->> 'ship', 'hold' using errcode = 'P0001';
  end if;
  v_fill := case when p_fill is null then least(1.0, ((p_parts ->> 'cargo')::numeric + (p_parts ->> 'water')::numeric + (p_parts ->> 'food')::numeric)
                                                      / (p_parts ->> 'hold')::numeric)
                 else least(1.0, greatest(0.0, p_fill)) end;
  return round((p_parts ->> 'k')::numeric * (1 - public.wc_num('load_speed_penalty') * v_fill), 4);
end
$body$
  $f$;
  execute $f$
create function voyage.fleet_speed_parts(p_fleet uuid, p_alone boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0454: WHAT A FLEET'S SPEED IS MADE OF (voyage.fleet_speed_alone_at's and voyage.fleet_speed_at's readings, cut out of them):
--   hulls    voyage.ship_speed_parts of every hull (E_NO_SHIPS when she has none)
--   f        DESIGN B.3's formation (1.00 for up to 3 ships, 0.98 for 4-6, 0.95 for 7+) x (1 + the captains seated in her, public.crew_pct 'speed')
--            x (1 + her company's NAVIGATION, public.player_skill_bonus 'SPEED'): multiplied, never added (0015 / 0027 / 0157)
--   mult     her kind's multiplier (public.fleet_speed_mult, 0422), for a fleet in no armada
--   members  in an armada (0367): its other fleets that have a ship, each alone; she sails at the least of them and herself
-- p_alone: the fleet by herself (no mult, no members): voyage.fleet_speed_alone_at. voyage.fleet_speed_of reads these. Server only.
declare
  v_hulls  jsonb;
  v_ships  int;
  v_player uuid;
  v_skill  numeric := 0;
  v_arm    uuid;
  v_out    jsonb;
begin
  if not p_alone then
    select af.armada_id into v_arm from public.armada_fleets af where af.fleet_id = p_fleet;
  end if;
  select coalesce(jsonb_agg(voyage.ship_speed_parts(s.id) order by s.id), '[]'::jsonb), count(*) into v_hulls, v_ships
    from public.ships s where s.fleet_id = p_fleet;
  if v_ships = 0 then
    raise exception 'E_NO_SHIPS: fleet % has no ships', p_fleet using errcode = 'P0001';
  end if;
  select f.player_id into v_player from public.fleets f where f.id = p_fleet;
  if v_player is not null then
    v_skill := public.player_skill_bonus(v_player, 'SPEED');
  end if;
  v_out := jsonb_build_object('hulls', v_hulls,
                              'f', (case when v_ships <= 3 then 1.00 when v_ships <= 6 then 0.98 else 0.95 end)
                                   * (1 + public.crew_pct(p_fleet, null, 'speed')) * (1 + v_skill));
  if p_alone then
    return v_out;
  elsif v_arm is null then
    return v_out || jsonb_build_object('mult', public.fleet_speed_mult(p_fleet));
  end if;
  return v_out || jsonb_build_object('members',
    (select coalesce(jsonb_agg(voyage.fleet_speed_parts(m.fleet_id, true) order by m.fleet_id), '[]'::jsonb)
       from public.armada_fleets m
      where m.armada_id = v_arm and m.fleet_id <> p_fleet
        and exists (select 1 from public.ships s where s.fleet_id = m.fleet_id)));
end
$body$
  $f$;
  execute $f$
create function voyage.fleet_speed_of(p_parts jsonb, p_fill numeric, p_stores jsonb)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0454: THE SPEED OF A FLEET FROM ITS PARTS (voyage.fleet_speed_parts), at the fill asked (null: each hull's own; 0203). Her slowest hull x her
  -- factor, to 4 places; x her kind's multiplier; in an armada, the least of hers and its other fleets' (each alone, at the same fill). p_stores
  -- ([{ship, water, food}], world.trip_hulls' shape) gives a hull those casks in place of her own: a trip walked ahead of her (world.trip_leg).
  select case when p_parts ? 'members'
              then least(v.self, (select min(voyage.fleet_speed_of(m, p_fill, null)) from jsonb_array_elements(p_parts -> 'members') m))
              when p_parts ? 'mult' then v.self * (p_parts ->> 'mult')::numeric
              else v.self end
    from (select round(min(voyage.ship_speed_of(h || coalesce((select jsonb_strip_nulls(jsonb_build_object('water', e -> 'water', 'food', e -> 'food'))
                                                                 from jsonb_array_elements(coalesce(p_stores, '[]'::jsonb)) e
                                                                where e ->> 'ship' = h ->> 'ship' limit 1), '{}'::jsonb), p_fill))
                       * (p_parts ->> 'f')::numeric, 4) as self
            from jsonb_array_elements(p_parts -> 'hulls') h) v
$body$
  $f$;

  -- THE THREE OLD NAMES: each whole body becomes the one call (a hunk: the whole old body, once; reversed below)
  for x in select u.fn, u.ord from unnest(c_speed) with ordinality u(fn, ord) loop
    v_pre := (select p.def from pre_0454 p where p.fn = x.fn);
    v_old := substring(v_pre from position(E'AS $function$\n' in v_pre) + length(E'AS $function$\n'));
    v_old := left(v_old, length(v_old) - length(E'$function$\n'));
    if right(v_pre, length(E'$function$\n')) <> E'$function$\n' or (length(v_pre) - length(replace(v_pre, v_old, ''))) / length(v_old) <> 1 then
      raise exception '0454 self-assert FAIL: the body of % is not once in its definition, between its quotes', x.fn;
    end if;
    v_new := case x.ord
      when 1 then E'begin\n  -- 0454: THE SPEED of one hull at the fill asked, or at her own casks: voyage.ship_speed_of her voyage.ship_speed_parts (this body, cut in two there).\n  return voyage.ship_speed_of(voyage.ship_speed_parts(p_ship), p_fill);\nend '
      when 2 then E'begin\n  -- 0454: the fleet by herself: voyage.fleet_speed_of her voyage.fleet_speed_parts alone (this body, cut in two there), at her own casks.\n  return voyage.fleet_speed_of(voyage.fleet_speed_parts(p_fleet, true), p_fill, null);\nend '
      else E'begin\n  -- 0454: THE SPEED OF A FLEET: voyage.fleet_speed_of her voyage.fleet_speed_parts (this body, cut in two there; the kind''s multiplier, an armada''s least), at her own casks.\n  return voyage.fleet_speed_of(voyage.fleet_speed_parts(p_fleet), p_fill, null);\nend ' end;
    execute replace(v_pre, v_old, v_new);
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 or replace(v_def, v_new, v_old) <> v_pre then
      raise exception '0454 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 3. THE WALK: one leg, with her speed asked at each departure ──
  execute $f$
create function world.trip_leg(p_speed jsonb, p_hulls jsonb, p_nm numeric, p_top boolean default true, p_sea numeric default null)
returns table(hulls jsonb, water_t numeric, food_t numeric, sea_days numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0361: ONE LEG OF A TRIP, WALKED (world.trip_cost and world.board_legs ask it). Every hull of p_hulls (world.trip_hulls) is topped up for a leg
-- of p_nm as cmd.do_sail tops her (public.stores_topup to public.npc_leg_days), then the leg's settled days are eaten at water_per_crew_day and
-- food_per_crew_day a crew, as voyage.settle eats them: every day begun is a day settled (voyage.total_days: the hours over 24, rounded up, never
-- under one). Answers her hulls as she arrives, the tuns of water and food the top-up took on (public.stores_cost prices them), and the days
-- settled (public.fleet_wage is owed for each).
-- 0454: AT HER SPEED AT EACH DEPARTURE, as cmd.do_sail reads it (it replaces 0361's one speed in port). p_speed is her voyage.fleet_speed_parts,
-- read once by the caller: the top-up's days at voyage.fleet_speed_of with the casks she carries INTO this departure (public.supply_need's
-- reading), the settled days at voyage.fleet_speed_of with the casks topped up (voyage.depart's: the speed frozen for the leg).
--   p_top false  nothing is bought (a voyage already under way: she provisioned when she left)
--   p_sea        the days to settle, when the caller knows them (a voyage under way: what is left of it); then no speed is read
declare
  v_wpd    numeric := public.wc_num('water_per_crew_day');
  v_fpd    numeric := public.wc_num('food_per_crew_day');
  v_top    numeric;
  v_w      numeric;
  v_f      numeric;
  v_topped jsonb := '[]'::jsonb;
  h        record;
begin
  if p_top then
    v_top := public.npc_leg_days(p_nm, greatest(voyage.fleet_speed_of(p_speed, null, p_hulls), 0.1));
  end if;
  water_t := 0;
  food_t := 0;
  for h in select * from jsonb_to_recordset(p_hulls) x(ship uuid, crew numeric, water numeric, food numeric, room numeric, "full" numeric) loop
    v_w := 0;
    v_f := 0;
    if p_top then
      select tu.water_t, tu.food_t into v_w, v_f from public.stores_topup(h.crew, h.water, h.food, h.room, v_top, h."full") tu;
    end if;
    water_t := water_t + coalesce(v_w, 0);
    food_t := food_t + coalesce(v_f, 0);
    v_topped := v_topped || jsonb_build_array(jsonb_build_object(
      'ship', h.ship, 'crew', h.crew, 'water', coalesce(h.water, 0) + coalesce(v_w, 0), 'food', coalesce(h.food, 0) + coalesce(v_f, 0), 'room', h.room, 'full', h."full"));
  end loop;
  sea_days := coalesce(p_sea, greatest(1, ceil(p_nm / greatest(voyage.fleet_speed_of(p_speed, null, v_topped), 0.1) / 24)));   -- voyage.total_days: every day begun is settled, never under one
  hulls := '[]'::jsonb;
  for h in select * from jsonb_to_recordset(v_topped) x(ship uuid, crew numeric, water numeric, food numeric, room numeric, "full" numeric) loop
    hulls := hulls || jsonb_build_array(jsonb_build_object(
      'ship', h.ship, 'crew', h.crew,
      'water', greatest(0, h.water - coalesce(h.crew, 0) * v_wpd * sea_days),
      'food',  greatest(0, h.food - coalesce(h.crew, 0) * v_fpd * sea_days),
      'room', h.room, 'full', h."full"));
  end loop;
  return next;
end
$body$
  $f$;

  -- ── 4. THE HUNKS: the walk's three callers ──
  create temp table hunks_0454 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0454 values
  ('world.trip_hulls(uuid)', 1,
$h$  -- 0345): [{crew, water, food, room, full}], the room her stores may fill and her full mark. Read by world.trip_cost and world.board_legs. Server only.
$h$,
$h$  -- 0345): [{ship, crew, water, food, room, full}], the room her stores may fill and her full mark. Read by world.trip_cost and world.board_legs. Server only.
  -- 0454: `ship` (her id), so the walk asks the speed of each hull at the casks it walked (voyage.fleet_speed_of).
$h$),
  ('world.trip_hulls(uuid)', 2,
$h$           'crew', s.crew, 'water', s.water_t, 'food', s.food_t,
$h$,
$h$           'ship', s.id, 'crew', s.crew, 'water', s.water_t, 'food', s.food_t,
$h$),
  ('world.trip_cost(uuid,jsonb)', 1,
$h$    select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_hulls, v_w, v_f, v_sea from world.trip_leg(v_hulls, v_nm, v_speed) tl;
$h$,
$h$    -- 0454: her speed at each departure (the top-up's, then the leg's), not v_speed in port: the walk asks it of the casks it walked
    select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_hulls, v_w, v_f, v_sea from world.trip_leg(voyage.fleet_speed_parts(p_fleet), v_hulls, v_nm) tl;
$h$),
  ('world.board_legs(uuid,jsonb)', 1,
$h$-- It also reads of p_ctx: speed and where.kind (world.board_origin's), and `only` (harbour ids: the trip is walked to those alone, for a reader of a few rows; the
$h$,
$h$-- It also reads of p_ctx: where.kind (world.board_origin's; 0454: not its speed, the walk asks her speed at each departure), and `only` (harbour ids: the trip is walked to those alone, for a reader of a few rows; the
$h$),
  ('world.board_legs(uuid,jsonb)', 2,
$h$  v_speed   numeric := greatest(coalesce((p_ctx->>'speed')::numeric, 0), 0.1);
$h$,
$h$  v_speed   jsonb;                   -- 0454: her voyage.fleet_speed_parts, read once a board: world.trip_leg asks her speed of them at each departure
$h$),
  ('world.board_legs(uuid,jsonb)', 3,
$h$    select tl.hulls, tl.sea_days into v_h0, v_sea0 from world.trip_leg(v_hulls, 0, v_speed, false, coalesce(v_n, 0)) tl;
$h$,
$h$    select tl.hulls, tl.sea_days into v_h0, v_sea0 from world.trip_leg(null, v_hulls, 0, false, coalesce(v_n, 0)) tl;   -- 0454: under way, no speed is read
$h$),
  ('world.board_legs(uuid,jsonb)', 4,
$h$  v_hulls := world.trip_hulls(p_fleet);
  v_h0 := v_hulls;
$h$,
$h$  v_hulls := world.trip_hulls(p_fleet);
  v_h0 := v_hulls;
  v_speed := voyage.fleet_speed_parts(p_fleet);
$h$),
  ('world.board_legs(uuid,jsonb)', 5,
$h$        select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_h, v_w, v_f, v_sea from world.trip_leg(v_h, v_nm, v_speed) tl;
$h$,
$h$        select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_h, v_w, v_f, v_sea from world.trip_leg(v_speed, v_h, v_nm) tl;
$h$),
  ('world.board_legs(uuid,jsonb)', 6,
$h$    select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_h0, v_w, v_f, v_sea0 from world.trip_leg(v_hulls, v_lead_nm, v_speed) tl;
$h$,
$h$    select tl.hulls, tl.water_t, tl.food_t, tl.sea_days into v_h0, v_w, v_f, v_sea0 from world.trip_leg(v_speed, v_hulls, v_lead_nm) tl;
$h$);

  for x in select distinct h.fn from hunks_0454 h loop
    v_pre := (select p.def from pre_0454 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0454 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0454 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0454 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0454 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0454 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0454) <> 9 then
    raise exception '0454 self-assert FAIL: the hunks are not the 9 of the three re-cut bodies';
  end if;
  if exists (select 1 from unnest(c_recut) f where pg_get_functiondef(f::regprocedure) like '%world.trip_leg(v_hulls, v_nm, v_speed)%'
                                                 or pg_get_functiondef(f::regprocedure) like '%world.trip_leg(v_h, v_nm, v_speed)%'
                                                 or pg_get_functiondef(f::regprocedure) like '%world.trip_leg(v_hulls, v_lead_nm, v_speed)%'
                                                 or pg_get_functiondef(f::regprocedure) like '%world.trip_leg(v_hulls, 0, v_speed%') then
    raise exception '0454 self-assert FAIL: a caller still asks the old walk';
  end if;
  drop function world.trip_leg(jsonb, numeric, numeric, boolean, numeric);

  -- ── 5. GRANTS: server only, as the functions they stand in for ──
  revoke all on function voyage.ship_speed_parts(uuid) from public, anon, authenticated;
  revoke all on function voyage.ship_speed_of(jsonb, numeric) from public, anon, authenticated;
  revoke all on function voyage.fleet_speed_parts(uuid, boolean) from public, anon, authenticated;
  revoke all on function voyage.fleet_speed_of(jsonb, numeric, jsonb) from public, anon, authenticated;
  revoke all on function world.trip_leg(jsonb, jsonb, numeric, boolean, numeric) from public, anon, authenticated;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select f::regprocedure::oid from unnest(c_speed || c_recut || c_new) f))) <> v_fn_before then
    raise exception '0454 self-assert FAIL: another function moved';
  end if;
  for x in select f.fn, f.meta,
                  (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
                     from pg_proc p where p.oid = f.now::regprocedure) as now_meta
             from (select p.fn, p.meta, p.fn as now from pre_0454 p where p.fn <> c_leg_old
                   union all select p.fn, p.meta, u.fn from pre_0454 p cross join unnest(c_new) u(fn) where p.fn = c_leg_old) f loop
    if x.now_meta is distinct from x.meta then
      raise exception '0454 self-assert FAIL: the grants, volatility, definer, search path or owner of % (or what stands in for it) is % and was %', x.fn, x.now_meta, x.meta;
    end if;
  end loop;

  -- EVERY SPEED READ IS UNCHANGED, to the digit; and at her own casks given, the new reading is the old one
  select coalesce(jsonb_agg(jsonb_build_object('f', q.id, 'now', voyage.fleet_speed_at(q.id, null), 'full', voyage.fleet_speed_at(q.id, 1),
                                               'alone', voyage.fleet_speed_alone_at(q.id, null),
                                               'hulls', (select jsonb_agg(jsonb_build_array(s.id, voyage.ship_speed_at(s.id, null), voyage.ship_speed_at(s.id, 0.5), voyage.ship_speed_at(s.id, 1)) order by s.id)
                                                           from public.ships s where s.fleet_id = q.id)) order by q.id), '[]'::jsonb)
    into v_after
    from speeds_0454 q;
  if v_after is distinct from v_speeds or jsonb_array_length(v_speeds) = 0 then
    raise exception '0454 self-assert FAIL: a speed moved (or no fleet was there to hold it on): before %, after %', left(v_speeds::text, 400), left(v_after::text, 400);
  end if;
  select count(*) into v_n from speeds_0454 q
   where voyage.fleet_speed_of(voyage.fleet_speed_parts(q.id), null, world.trip_hulls(q.id)) is distinct from voyage.fleet_speed(q.id);
  if v_n > 0 then
    raise exception '0454 self-assert FAIL: % fleet(s) read a different speed at their own casks given', v_n;
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (it sails nothing and rolls no dice) ──
  begin
    v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
    select r.port_id, r.nm into v_to, v_nm from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id
     where p.kind = 'HARBOUR' and r.nm between 600 and 1500 order by r.nm, p.code limit 1;
    if v_lis is null or v_to is null then
      raise exception '0454 self-assert FAIL: no Lisbon, or no harbour 600 to 1,500 nm from it, in this world';
    end if;
    insert into public.players (company_name, nation_id, ducats, is_npc)
    values ('Probe 0454', (select n.id from public.nations n where n.code = 'PRT'), 1000000, false) returning id into v_pl;
    v_fl := public.form_fleet(v_pl, 'Probe 0454', v_lis);
    perform public.commission_ship(v_pl, v_fl, 'barca', 'Probe 0454', true, true);
    select s.id into v_sh from public.ships s where s.fleet_id = v_fl limit 1;
    update public.ships set crew = greatest(crew, 20), water_t = 0, food_t = 0, cargo = '{}'::jsonb where id = v_sh;
    v_hulls := world.trip_hulls(v_fl);
    v_s0 := voyage.fleet_speed(v_fl);
    select * into v_leg from world.trip_leg(voyage.fleet_speed_parts(v_fl), v_hulls, v_nm);
    -- THE TOP-UP: the walk's is the SAIL's (public.supply_need's days; cmd.do_provision buys exactly it)
    select * into v_need from public.supply_need(v_fl, v_nm);
    perform cmd.do_provision(v_fl, jsonb_build_object('mode', 'DAYS', 'days', v_need.days, 'on_credit', true));
    select sum(s.water_t), sum(s.food_t) into v_w, v_f from public.ships s where s.fleet_id = v_fl;
    if v_w <> v_leg.water_t or v_f <> v_leg.food_t or v_w <= 0 then
      raise exception '0454 self-assert FAIL: the walk tops her up %/% t and the SAIL''s top-up took %/% t', v_leg.water_t, v_leg.food_t, v_w, v_f;
    end if;
    -- THE LEG: the walk settles the days at her speed with that top-up aboard (voyage.depart's reading)
    v_s1 := voyage.fleet_speed(v_fl);
    if v_s1 >= v_s0 or v_leg.sea_days <> greatest(1, ceil(v_nm / v_s1 / 24)) then
      raise exception '0454 self-assert FAIL: laden % kn (in port %), the walk settles % d for % nm', v_s1, v_s0, v_leg.sea_days, v_nm;
    end if;
    -- HER CASKS GIVEN = HER CASKS ABOARD: emptied again, her speed with those casks given is the speed she had with them aboard
    update public.ships set water_t = 0, food_t = 0 where id = v_sh;
    if voyage.fleet_speed(v_fl) <> v_s0
       or voyage.fleet_speed_of(voyage.fleet_speed_parts(v_fl), null, jsonb_build_array(jsonb_build_object('ship', v_sh, 'water', v_w, 'food', v_f))) <> v_s1
       or voyage.fleet_speed_of(voyage.fleet_speed_parts(v_fl), 1, jsonb_build_array(jsonb_build_object('ship', v_sh, 'water', v_w, 'food', v_f))) <> voyage.fleet_speed_at(v_fl, 1) then
      raise exception '0454 self-assert FAIL: her speed at casks given is not her speed with them aboard (% / % against %)', v_s0,
        voyage.fleet_speed_of(voyage.fleet_speed_parts(v_fl), null, jsonb_build_array(jsonb_build_object('ship', v_sh, 'water', v_w, 'food', v_f))), v_s1;
    end if;
    v_note := format('LIS to %s (%s nm): in port %s kn, laden %s kn; the walk tops her up %s/%s t as the SAIL does and settles %s d (in port it said %s)',
                     (select p.code from public.ports p where p.id = v_to), round(v_nm, 1), v_s0, v_s1, v_w, v_f, v_leg.sea_days, greatest(1, ceil(v_nm / v_s0 / 24)));
    raise exception sqlstate 'BV454' using message = v_note;
  exception when sqlstate 'BV454' then
    get stacked diagnostics v_note = message_text;
  end;
  if exists (select 1 from public.players p where p.company_name = 'Probe 0454') then
    raise exception '0454 self-assert FAIL: the probe was not rolled back';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0454 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0454 self-assert ok: A TRIP IS QUOTED AT EACH DEPARTURE''S SPEED. The speed rule cut in two at the fill (parts, then the fill put in); its 3 old names call it, % live fleets'' speeds unchanged to the digit; 9 hunks once each and reversing; world.trip_leg asks her speed at each departure; grants and volatility as before; no other function moved. Probe: %. % ms.',
    jsonb_array_length(v_speeds), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0454;
  drop table speeds_0454;
  drop table pre_0454;
end $m$;
