-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0360 — A TRIP SAYS ITS TIME AND ITS PRICE: world.trip_cost(fleet, legs), a read. NO TABLE, NO KNOB, NO SWITCH.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-13, of the Map's Send fleet: "i want the game to calculate which cities to cross automatically, and just tell me the final time, price
-- reaching the destination when pressed send fleet." Then: "add wages and dock fees to the price too", "but separately", and "docking - resailing takes
-- time too. So this also needs to be accounted for."
--
-- WHY A READ OF ITS OWN. world.route_legs (0346) judges each leg and serves each leg's days and its supplies AS HER HOLD STANDS NOW. Added up over a trip
-- of several legs that under-reads: her casks are fuller now than they will be at the third harbour. It serves no wages, no dock fee and no port time.
-- world.good_board serves wages and a dock fee, but only for the sale of one good at one city. No read prices a plain trip, so this file adds one.
--
-- WHAT THIS FILE ADDS (read only, STABLE, one function):
--   world.trip_cost(p_fleet uuid, p_legs jsonb)   p_legs = [{from, to, course}] as world.route_legs takes them (harbour CODES, the client's proposed course
--                                                or null). Answers
--                                                  {legs: [{from, to, nm, days, supplies, dock_fee, stop_seconds}],
--                                                   sail_days, stop_seconds, days, supplies, wages, dock_fee, total}
--                                                null when the fleet is not the caller's. Granted to authenticated only, as its sibling world.route_legs.
-- THE HUNK (once, reversing): public.client_rpc_entry_points gains the one row, after world.route_legs.
--
-- NOTHING IS PRICED HERE THAT THE GAME DOES NOT ALREADY PRICE. Each figure is the authority that charges it, asked:
--   nm, days      the leg measured as world.route_legs and cmd.do_sail measure it (voyage.segments_from_course; with no course, voyage.reach_from), at
--                 voyage.fleet_speed.
--   supplies      WALKED ALONG THE TRIP. Before each leg every hull is topped up as cmd.do_sail tops her (public.stores_topup to public.npc_leg_days, in the
--                 room public.supply_needs reads, priced by public.stores_cost); then the leg's settled days are eaten at water_per_crew_day and
--                 food_per_crew_day a crew, as voyage.settle eats them: every day begun is a day settled (voyage.total_days: the hours over 24, rounded
--                 up, never under one). The first leg is public.supply_need's figure exactly (asserted below).
--   wages         public.fleet_wage (THE daily wage) for every settled day of every leg, as voyage.settle owes it (public.owe_wages): a day begun is a day
--                 owed. Wages are OWED as she sails and paid out of her next sale's profit (0128): a cost of the trip, not a debit at departure.
--                 world.good_board prints a sale's `wages` as the wage times the days at sea with their fraction (round(wage x days)): on a trip of
--                 several short legs that line reads lower than what settle owes. This read serves what settle owes.
--   dock_fee      public.port_fee (THE dock fee, 0237) of every harbour the trip calls at, the last included, for the cargo aboard now at cost
--                 (public.fleet_stock_at_cost, what public.port_call charges on). 0 while the economy is open.
--   stop_seconds  THE TIME A CALL ON THE WAY TAKES, in real seconds: port_prep_seconds (0237: fleets.ready_at = the arrival + that knob) while the economy is
--                 closed, else 0; 0 on the last leg. The arrivals job runs every second (0242), so a waiting SAIL leaves within about a second of that
--                 instant: no allowance is added for it.
--   days          sail_days + stop_seconds at time_compression: the whole trip in voyage-days, what the client prints with the real time beside it.
--   total         supplies + wages + dock_fee.
-- A leg that cannot be measured (an unknown harbour, a course the server cannot read) has null figures, and so have the totals: never a part sum.
--
-- WHAT IT DOES NOT KNOW (said on the row's PR): a storm or a calm that lengthens a leg (more days, more eaten, more owed); cargo bought or sold on the
-- way (the dock fee is for the cargo aboard now); a purse that runs short (supplies then go on credit, 0241; the figure is the same).
--
-- DECIDED BY DEFAULT (the owner may reverse any of these afterwards):
--   * world.route_legs is NOT re-cut: it still serves each leg as her hold stands now, which is what the route builder's Confirm reads. This read is beside it.
--   * world.good_board is NOT re-cut: Trade's board still prints the sale's own lines. The Trade panel reads this read for its trip's time only.
--   * Wages are what voyage.settle owes (whole settled days a leg), not world.good_board's fractional line: the price shown is the price charged. Trade's
--     board keeps its own line until its own re-cut.
--
-- NOT TOUCHED: every other function, every table, every switch, every knob.
-- COST: one ownership read, one speed, the hulls once, then per leg one measure, one top-up a hull and one port_fee. No pathfinder. Timed below.
-- ROLLBACK (forward, owner only): a new migration dropping world.trip_cost(uuid, jsonb) and reversing the hunk. Nothing else depends on it; the client
-- falls back to world.route_legs' figures when this read is missing.
-- NEWS: this file posts its own UPDATE row, public.news_update('0360', 'Trip time and price', '항해 시간과 비용') (0347's law, tests/news.lint.spec.ts).
-- SELF-ASSERT: the catalog, then a probe house of its own rolled-back rows (the economy flag is turned both ways INSIDE the rolled-back probe only).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- VERSION: 0360. 0354 to 0359 are held by other branches; none of them is needed here. The registry row is anchored on the world.route_legs line (0346).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t1          timestamptz;
  v_def         text;
  v_pre         text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_rel_before  text;
  v_acl_legs    text;
  v_pl          uuid;
  v_fl          uuid;
  v_sh          uuid;
  v_other       uuid;
  v_lis         uuid;
  v_near        record;
  v_r           jsonb;
  v_r2          jsonb;
  v_one         bigint;
  v_wage        numeric;
  v_fee         bigint;
  v_prep        numeric;
  v_comp        numeric;
  v_wpd         numeric;
  v_fpd         numeric;
  v_lived       boolean := false;
  v_ms          numeric;
  v_note        text := '';
  c_uid  constant uuid := '00000000-0360-4000-8000-000000000001';
  c_old  constant text := $h$      ('world',       'route_legs',            'uuid, jsonb'),
$h$;
  c_new  constant text := $h$      ('world',       'route_legs',            'uuid, jsonb'),
      -- 0360: what a trip of SAILs takes and costs (the Map's Send fleet; owner 2026-11-13).
      ('world',       'trip_cost',             'uuid, jsonb'),
$h$;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('world.trip_cost(uuid,jsonb)') is not null then
    raise exception '0360 refuses: it has been applied once';
  end if;
  if to_regprocedure('world.route_legs(uuid,jsonb)') is null or to_regprocedure('public.supply_needs(uuid,numeric[])') is null
     or to_regprocedure('public.supply_need(uuid,numeric)') is null
     or to_regprocedure('public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)') is null
     or to_regprocedure('public.stores_cost(uuid,numeric,numeric)') is null or to_regprocedure('public.npc_leg_days(numeric,numeric)') is null
     or to_regprocedure('public.ship_stores_room(uuid,numeric)') is null or to_regprocedure('public.ship_hold_capacity(uuid)') is null
     or to_regprocedure('public.ship_cargo_tuns(uuid)') is null or to_regprocedure('public.fleet_wage(uuid,boolean,integer)') is null
     or to_regprocedure('public.port_fee(uuid,uuid,numeric)') is null or to_regprocedure('public.fleet_stock_at_cost(uuid)') is null
     or to_regprocedure('public.economy_closed()') is null or to_regprocedure('voyage.segments_from_course(jsonb)') is null
     or to_regprocedure('voyage.reach_from(uuid)') is null or to_regprocedure('voyage.fleet_speed(uuid)') is null
     or to_regprocedure('public.current_player_id()') is null or to_regprocedure('public.news_update(text,text,text)') is null
     or to_regprocedure('public.wc_num(text)') is null then
    raise exception '0360 refuses: a reader it composes is not in this world (0047 / 0142 / 0150 / 0154 / 0203 / 0225 / 0237 / 0345 / 0346 / 0347)';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.proname <> 'client_rpc_entry_points';
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  select coalesce(p.proacl::text, '') into v_acl_legs from pg_proc p where p.oid = 'world.route_legs(uuid,jsonb)'::regprocedure;

  -- ── 1. THE READ ──
  execute $f$
create function world.trip_cost(p_fleet uuid, p_legs jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0360 (owner, 2026-11-13): WHAT A TRIP OF SAILS TAKES AND COSTS. p_legs = [{from, to, course}] as world.route_legs takes them. Answers
-- {legs: [{from, to, nm, days, supplies, dock_fee, stop_seconds}], sail_days, stop_seconds, days, supplies, wages, dock_fee, total}.
--   supplies      her casks walked along the trip: topped up before each leg as cmd.do_sail tops her, the leg's settled days eaten as voyage.settle eats them
--   wages         public.fleet_wage for every settled day of every leg (a day begun is a day owed); owed as she sails, paid out of her next sale's profit
--   dock_fee      public.port_fee of every harbour called at, for the cargo aboard now at cost; 0 while the economy is open
--   stop_seconds  port_prep_seconds a call on the way while the economy is closed (fleets.ready_at), else 0; `days` carries them at time_compression
-- A leg that cannot be measured has null figures and so have the totals. null when the fleet is not the caller's. Judges nothing: world.route_legs does.
declare
  v_player uuid := public.current_player_id();
  v_speed  numeric;
  v_n      int;
  v_in     jsonb;
  v_from   uuid;
  v_to     uuid;
  v_course jsonb;
  v_nm     numeric;
  v_hulls  jsonb;
  v_next   jsonb;
  v_wpd    numeric := public.wc_num('water_per_crew_day');
  v_fpd    numeric := public.wc_num('food_per_crew_day');
  v_prep   numeric := case when public.economy_closed() then greatest(coalesce(public.wc_num('port_prep_seconds'), 0), 0) else 0 end;
  v_comp   numeric := public.wc_num('time_compression');
  v_stock  numeric;
  v_top    numeric;
  v_sea    numeric;
  v_w      numeric;
  v_f      numeric;
  v_cost   bigint;
  v_fee    bigint;
  v_stop   numeric;
  v_sail   numeric := 0;
  v_sup    bigint := 0;
  v_fees   bigint := 0;
  v_stops  numeric := 0;
  v_whole  boolean := true;
  v_seas   numeric := 0;
  v_wages  bigint;
  v_out    jsonb := '[]'::jsonb;
  h        record;
  t        record;
  i        int;
begin
  if v_player is null or p_fleet is null
     or not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = v_player) then
    return null;
  end if;
  if p_legs is null or jsonb_typeof(p_legs) <> 'array' or jsonb_array_length(p_legs) = 0 then
    return jsonb_build_object('legs', '[]'::jsonb, 'sail_days', null, 'stop_seconds', 0, 'days', null, 'supplies', null, 'wages', null, 'dock_fee', null, 'total', null);
  end if;
  v_n := jsonb_array_length(p_legs);
  v_speed := greatest(voyage.fleet_speed(p_fleet), 0.1);
  v_stock := public.fleet_stock_at_cost(p_fleet);
  -- HER HULLS, read once, exactly as public.supply_needs reads them (0225, 0250, 0345): the room her stores may fill and her full mark
  select coalesce(jsonb_agg(jsonb_build_object(
           'crew', s.crew, 'water', s.water_t, 'food', s.food_t,
           'room', public.ship_stores_room(s.id, hc.cap - public.ship_cargo_tuns(s.id)),
           'full', public.ship_stores_room(s.id, hc.cap * s.store_ratio))), '[]'::jsonb)
    into v_hulls
    from public.ships s
   cross join lateral (select public.ship_hold_capacity(s.id) as cap offset 0) hc
   where s.fleet_id = p_fleet;

  for i in 1 .. v_n loop
    v_in := p_legs -> (i - 1);
    v_from := (select p.id from public.ports p where p.code = v_in ->> 'from' and p.kind = 'HARBOUR');
    v_to   := (select p.id from public.ports p where p.code = v_in ->> 'to' and p.kind = 'HARBOUR');
    v_course := case when jsonb_typeof(v_in -> 'course') = 'array' then v_in -> 'course' end;
    -- THE LEG MEASURED, as world.route_legs and cmd.issue_lines measure a SAIL
    v_nm := null;
    if v_to is not null then
      if v_course is not null then
        begin
          select sum((s ->> 'nm')::numeric) into v_nm from jsonb_array_elements(voyage.segments_from_course(v_course)) s;
        exception when others then
          v_nm := null;
        end;
      elsif v_from is not null then
        select r.nm into v_nm from voyage.reach_from(v_from) r where r.port_id = v_to;
      end if;
    end if;
    if v_nm is null or v_nm <= 0 then
      v_whole := false;
      v_out := v_out || jsonb_build_array(jsonb_build_object('from', v_in -> 'from', 'to', v_in -> 'to', 'nm', null, 'days', null,
                                                             'supplies', null, 'dock_fee', null, 'stop_seconds', 0));
      continue;
    end if;
    -- THE STORES: every hull topped up for this leg as cmd.do_sail tops her, then the leg's whole days at sea eaten as voyage.settle eats them
    v_top := public.npc_leg_days(v_nm, v_speed);
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
    v_cost := public.stores_cost(v_player, v_w, v_f);
    v_fee  := public.port_fee(v_to, v_player, v_stock);
    v_stop := case when i < v_n then v_prep else 0 end;
    v_sail := v_sail + v_nm / v_speed / 24;
    v_seas := v_seas + v_sea;
    v_sup  := v_sup + v_cost;
    v_fees := v_fees + v_fee;
    v_stops := v_stops + v_stop;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'from', v_in -> 'from', 'to', v_in -> 'to', 'nm', round(v_nm, 1), 'days', round(v_nm / v_speed / 24, 2),
      'supplies', v_cost, 'dock_fee', v_fee, 'stop_seconds', v_stop));
  end loop;

  if not v_whole then
    return jsonb_build_object('legs', v_out, 'sail_days', null, 'stop_seconds', v_stops, 'days', null, 'supplies', null, 'wages', null, 'dock_fee', null, 'total', null);
  end if;
  v_wages := round(public.fleet_wage(p_fleet, false) * v_seas)::bigint;   -- voyage.settle: the day's wage, every settled day
  return jsonb_build_object(
    'legs', v_out,
    'sail_days', round(v_sail, 2),
    'stop_seconds', v_stops,
    'days', round(v_sail + v_stops * v_comp / 86400, 2),
    'supplies', v_sup,
    'wages', v_wages,
    'dock_fee', v_fees,
    'total', v_sup + v_wages + v_fees);
end
$body$
  $f$;

  revoke all on function world.trip_cost(uuid, jsonb) from public, anon;
  grant execute on function world.trip_cost(uuid, jsonb) to authenticated;
  comment on function world.trip_cost(uuid, jsonb) is
    '0360 (owner 2026-11-13): what a trip of SAILs takes and costs for the caller''s fleet: days with the calls on the way, supplies walked along the trip, wages, dock fees, total. A read; null for a fleet not yours.';

  -- ── 2. THE HUNK: the registry row (once, and reversing) ──
  v_def := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  v_pre := v_def;
  v_n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  if v_n <> 1 then
    raise exception '0360 self-assert FAIL: the registry hunk occurs % time(s), not once: the deployed body is not what this file was written against', v_n;
  end if;
  execute replace(v_def, c_old, c_new);
  v_def := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) <> 1 then
    raise exception '0360 self-assert FAIL: the registry hunk is not in the new body once';
  end if;
  if replace(v_def, c_new, c_old) <> v_pre then
    raise exception '0360 self-assert FAIL: public.client_rpc_entry_points does not reverse to its pre-image';
  end if;

  -- ── 3. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.proname <> 'client_rpc_entry_points'
         and p.oid::regprocedure::text <> 'world.trip_cost(uuid,jsonb)') <> v_fn_before then
    raise exception '0360 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0360 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  if (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'world.trip_cost(uuid,jsonb)'::regprocedure)
     is distinct from (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'world.route_legs(uuid,jsonb)'::regprocedure) then
    raise exception '0360 self-assert FAIL: the read is not STABLE, definer, with the search path its sibling world.route_legs has';
  end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.trip_cost(uuid,jsonb)'::regprocedure) <> v_acl_legs
     or has_function_privilege('anon', 'world.trip_cost(uuid,jsonb)', 'execute') or not has_function_privilege('authenticated', 'world.trip_cost(uuid,jsonb)', 'execute') then
    raise exception '0360 self-assert FAIL: the grants are not its sibling''s: the read to authenticated only';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'trip_cost' and e.arg_types = 'uuid, jsonb' and e.fn is not null) then
    raise exception '0360 self-assert FAIL: the read is not in the client registry';
  end if;
  if world.trip_cost((select f.id from public.fleets f order by f.id limit 1), '[]'::jsonb) is not null then
    raise exception '0360 self-assert FAIL: a caller with no company reads a fleet''s trip';
  end if;

  -- ── 4. THE SELF-ASSERT: a probe house of its own rows, every one rolled back. No money moves; the economy flag is turned only inside this block. ──
  begin
    v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa do Preco 0360', (select n.id from public.nations n where n.code = 'PRT'), 0, false)
    returning id into v_pl;
    v_fl := public.form_fleet(v_pl, 'Preco', v_lis);
    perform public.commission_ship(v_pl, v_fl, 'barca', 'Preco', true, true);
    select s.id into v_sh from public.ships s where s.fleet_id = v_fl limit 1;
    update public.ships set crew = greatest(crew, 20), water_t = 0, food_t = 0 where id = v_sh;   -- empty casks: every leg must buy
    perform cmd.assume_identity(c_uid);
    v_wpd := public.wc_num('water_per_crew_day');
    v_fpd := public.wc_num('food_per_crew_day');
    v_comp := public.wc_num('time_compression');

    -- the nearest harbour a whole day or more away, that her empty casks can be filled for
    select r.port_id, r.code, r.nm into v_near
      from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id
     where p.kind = 'HARBOUR' and r.nm / greatest(voyage.fleet_speed(v_fl), 0.1) / 24 >= 1
       and (select n.fits from public.supply_need(v_fl, r.nm) n)
     order by r.nm limit 1;
    if v_near.port_id is null then
      raise exception '0360 self-assert FAIL: the probe at Lisbon has no harbour a day away that her stores fit';
    end if;

    -- (a) ONE LEG, THE ECONOMY OPEN: supplies are public.supply_need's figure exactly; wages are the settled days' wage; no fee, no port time
    update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
    v_r := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code, 'course', null)));
    v_one := (select n.cost from public.supply_need(v_fl, v_near.nm) n);
    v_wage := public.fleet_wage(v_fl, false);
    if jsonb_array_length(v_r -> 'legs') <> 1 or v_one is null or v_one <= 0
       or (v_r ->> 'supplies')::bigint is distinct from v_one or (v_r -> 'legs' -> 0 ->> 'supplies')::bigint is distinct from v_one
       or (v_r ->> 'sail_days')::numeric is distinct from round(v_near.nm / greatest(voyage.fleet_speed(v_fl), 0.1) / 24, 2)
       or (v_r ->> 'days')::numeric is distinct from (v_r ->> 'sail_days')::numeric
       or (v_r ->> 'wages')::bigint is distinct from round(v_wage * greatest(1, ceil(v_near.nm / greatest(voyage.fleet_speed(v_fl), 0.1) / 24)))::bigint
       or (v_r ->> 'dock_fee')::bigint <> 0 or (v_r ->> 'stop_seconds')::numeric <> 0
       or (v_r ->> 'total')::bigint is distinct from (v_r ->> 'supplies')::bigint + (v_r ->> 'wages')::bigint + (v_r ->> 'dock_fee')::bigint then
      raise exception '0360 self-assert FAIL: LIS -> % open: not supply_need''s % for supplies, fleet_wage x settled days for wages, no fee and no port time: %', v_near.code, v_one, v_r;
    end if;

    -- (b) OUT AND HOME, THE CASKS WALKED: the second leg buys again (a day was eaten) but never more than a leg bought on empty casks; the totals add up
    v_r := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code), jsonb_build_object('from', v_near.code, 'to', 'LIS')));
    v_r2 := world.route_legs(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code), jsonb_build_object('from', v_near.code, 'to', 'LIS')));
    if jsonb_array_length(v_r -> 'legs') <> 2
       or (v_r -> 'legs' -> 0 ->> 'supplies')::bigint is distinct from v_one
       or (v_r -> 'legs' -> 1 ->> 'supplies')::bigint <= 0 or (v_r -> 'legs' -> 1 ->> 'supplies')::bigint > v_one
       or (v_r ->> 'supplies')::bigint is distinct from (v_r -> 'legs' -> 0 ->> 'supplies')::bigint + (v_r -> 'legs' -> 1 ->> 'supplies')::bigint
       or (v_r -> 'legs' -> 0 ->> 'days')::numeric is distinct from (v_r2 -> 'legs' -> 0 ->> 'days')::numeric
       or (v_r -> 'legs' -> 1 ->> 'nm')::numeric is distinct from (v_r2 -> 'legs' -> 1 ->> 'nm')::numeric
       or (v_r ->> 'stop_seconds')::numeric <> 0
       or (v_r ->> 'total')::bigint is distinct from (v_r ->> 'supplies')::bigint + (v_r ->> 'wages')::bigint + (v_r ->> 'dock_fee')::bigint then
      raise exception '0360 self-assert FAIL: LIS -> % -> LIS on empty casks: the second leg is not bought again within a first leg''s price, or the totals do not add up: %', v_near.code, v_r;
    end if;
    v_note := format('empty casks out and home: %s then %s', v_r -> 'legs' -> 0 ->> 'supplies', v_r -> 'legs' -> 1 ->> 'supplies');

    -- (c) FULL CASKS UNDER-READ NO MORE: with a leg's stores aboard the first leg is free, and the walk still charges the second (route_legs serves it free)
    update public.ships s set water_t = t.water_t, food_t = t.food_t
      from (select tu.water_t, tu.food_t
              from public.ships x
             cross join lateral public.stores_topup(x.crew, 0, 0, public.ship_stores_room(x.id, public.ship_hold_capacity(x.id) - public.ship_cargo_tuns(x.id)),
                                                    public.npc_leg_days(v_near.nm, greatest(voyage.fleet_speed(v_fl), 0.1)),
                                                    public.ship_stores_room(x.id, public.ship_hold_capacity(x.id) * x.store_ratio)) tu
             where x.id = v_sh) t
     where s.id = v_sh;
    v_r := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code), jsonb_build_object('from', v_near.code, 'to', 'LIS')));
    v_r2 := world.route_legs(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code), jsonb_build_object('from', v_near.code, 'to', 'LIS')));
    if (v_r -> 'legs' -> 0 ->> 'supplies')::bigint <> 0 or (v_r2 -> 'legs' -> 0 -> 'supplies' ->> 'cost')::bigint <> 0
       or (v_r2 -> 'legs' -> 1 -> 'supplies' ->> 'cost')::bigint <> 0 or (v_r -> 'legs' -> 1 ->> 'supplies')::bigint <= 0 then
      raise exception '0360 self-assert FAIL: with a leg''s stores aboard the first leg is not free, or the second is not charged where route_legs serves it free: % against %', v_r, v_r2;
    end if;
    v_note := v_note || format('; a leg''s stores aboard: 0 then %s (route_legs: 0 then 0)', v_r -> 'legs' -> 1 ->> 'supplies');

    -- (d) THE ECONOMY CLOSED: each harbour called at charges public.port_fee, and the call on the way takes port_prep_seconds, carried into `days`
    update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
    v_prep := greatest(coalesce(public.wc_num('port_prep_seconds'), 0), 0);
    v_fee := public.port_fee(v_near.port_id, v_pl, public.fleet_stock_at_cost(v_fl)) + public.port_fee(v_lis, v_pl, public.fleet_stock_at_cost(v_fl));
    v_r := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code), jsonb_build_object('from', v_near.code, 'to', 'LIS')));
    if (v_r ->> 'dock_fee')::bigint is distinct from v_fee
       or (v_r ->> 'stop_seconds')::numeric is distinct from v_prep
       or (v_r -> 'legs' -> 0 ->> 'stop_seconds')::numeric is distinct from v_prep or (v_r -> 'legs' -> 1 ->> 'stop_seconds')::numeric <> 0
       or abs((v_r ->> 'days')::numeric - ((v_r ->> 'sail_days')::numeric + v_prep * v_comp / 86400)) > 0.011
       or (v_r ->> 'total')::bigint is distinct from (v_r ->> 'supplies')::bigint + (v_r ->> 'wages')::bigint + v_fee then
      raise exception '0360 self-assert FAIL: closed, LIS -> % -> LIS: not port_fee''s % for the two calls, or not % s for the one call on the way: %', v_near.code, v_fee, v_prep, v_r;
    end if;
    v_note := v_note || format('; closed: dock fees %s over two calls, %s s a call on the way', v_fee, v_prep);

    -- (e) A FLEET NOT YOURS reads null; a leg that cannot be measured has null figures and null totals
    select f.id into v_other from public.fleets f where f.player_id <> v_pl order by f.id limit 1;
    if v_other is not null and world.trip_cost(v_other, '[]'::jsonb) is not null then
      raise exception '0360 self-assert FAIL: the probe reads another house''s fleet';
    end if;
    v_r := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code), jsonb_build_object('from', v_near.code, 'to', 'NO SUCH 0360')));
    if v_r -> 'total' <> 'null'::jsonb or v_r -> 'days' <> 'null'::jsonb or v_r -> 'supplies' <> 'null'::jsonb
       or v_r -> 'legs' -> 1 -> 'nm' <> 'null'::jsonb or v_r -> 'legs' -> 0 -> 'nm' = 'null'::jsonb then
      raise exception '0360 self-assert FAIL: a trip with an unknown harbour does not answer null totals: %', v_r;
    end if;

    -- (f) SIX TIMED CALLS of a two-leg trip, the call a row of the Send fleet tray makes
    v_t1 := clock_timestamp();
    for v_n in 1 .. 6 loop
      v_r := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code), jsonb_build_object('from', v_near.code, 'to', 'LIS')));
    end loop;
    v_ms := round(extract(epoch from clock_timestamp() - v_t1) * 1000 / 6);
    raise exception using errcode = 'ZX360', message = 'PROBE_ROLLBACK_0360';
  exception when sqlstate 'ZX360' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0360 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa do Preco 0360' or p.auth_uid = c_uid) then
    raise exception '0360 self-assert FAIL: the probe left rows behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0360 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0360 self-assert FAIL: a world_config row moved: this file sets no knob, and the probe''s flag did not roll back';
  end if;

  -- ── 5. THE NEWS (0347's law): the Map's Send fleet says a trip's whole time and its price from the deploy on ──
  perform public.news_update('0360', 'Trip time and price', '항해 시간과 비용');

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0360 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0360 self-assert ok: A TRIP SAYS ITS TIME AND ITS PRICE. One read, STABLE, to authenticated only, as world.route_legs; one hunk, once and reversing; no other function, knob or table moved. Open: supplies are supply_need''s, wages fleet_wage x settled days, no fee, no port time. %. Not yours: null; an unknown harbour: null totals. A two-leg trip: % ms a call (6 calls). % ms.',
    v_note, v_ms, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
