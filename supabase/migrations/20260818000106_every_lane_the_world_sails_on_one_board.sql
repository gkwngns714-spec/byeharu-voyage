-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0106 — EVERY LANE THE WORLD SAILS, ON ONE BOARD
--        Owner row 115 (docs/OWNER_REQUESTS.md, 2026-10-11). docs/NPC_FLEET_SCALE.md slice F.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ─────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-11: *"show all trade routes created"* · *"rank them with distance, earning
-- prices, etc."*
--
-- Every standing route in the world — the captain's own and the merchant companies' — on one
-- readable board, with the figures a player would rank them by. The board is a READ: it composes
-- no order, exactly as the chart does not (DESIGN law 3). Tapping a route on it is how you find
-- out about a lane, not how you take it.
--
-- ── NOTHING HERE IS A NEW NUMBER ────────────────────────────────────────────────────────────────
-- Both figures the owner named already exist, and this file re-derives neither:
--
--   DISTANCE is the sum of the loop's BAKED leg courses. `standing_route_stops.course` is the
--   verified water the route actually sails — authored once, re-verified by `cmd.do_sail` at every
--   departure — and `voyage.segments_from_course` is the server's own measure of a course in
--   nautical miles, the same one a voyage's ETA is built on. A straight line between two harbours
--   would be a different, shorter and untrue number, and the chart has never drawn one.
--
--   EARNINGS is `public.route_earnings` — THE one earnings reading (0097), laps and never the
--   ledger, with its own hard-won rule that lap 1 is not averaged at all because a lap closes
--   before the home stop's SELL runs. The board prints what that function says, including the
--   absence: `lap` is null until a second lap has closed, and `lap_basis` says what the figure
--   stands on. Printing a figure where the server says "not yet" is how a board lies.
--
-- `public.route_nm` is new, and is the ONE distance reading for a loop, so the board and whatever
-- ranks, gates or sorts routes next cannot come to disagree about how long a route is.
--
-- ── WHOSE ROUTES ARE ON IT ──────────────────────────────────────────────────────────────────────
-- The caller's own, and the MERCHANTS' (`players.is_npc`, the one predicate). Never another
-- player's: DESIGN §E.5 keeps other captains off the chart and a board is not a loophole in that.
-- Asserted below, with a second player's route planted as the positive control.
--
-- Dark (the merchant switch off) the board is the captain's own routes and nothing else — which is
-- what the world honestly holds then.
--
-- ── WHAT THIS SUPERSEDES ────────────────────────────────────────────────────────────────────────
-- `public.client_rpc_entry_points` (0018, re-cut by every file that adds a door) and nothing else:
-- the board is a NEW read, and the registry is re-cut only to name it, by one hunk, with the
-- pre-image and the ACL asserted unmoved below. No existing function's body changes — the
-- distance comes from the new `public.route_nm` and the earnings from 0097's `public.route_earnings`
-- exactly as it stands. With no caller the change is invisible: a client that never asks for the
-- board sees a registry one row longer and the same answers to everything else.
--
-- ── THE CAP, AND WHOSE ROUTES SURVIVE IT ────────────────────────────────────────────────────────
-- `route_board_max` (400) bounds the payload, and `total` / `omitted` are served, the posture 0102
-- set for `world.sea_traffic`: a read that truncates silently teaches the player the world is
-- smaller than it is. When the cap bites, the LONGEST routes survive, because a board of the
-- world's trade that drops the India run and keeps a coastal hop is not a board of the world's
-- trade. The caller's OWN routes are never dropped — they are hers, and a board that hides them
-- while showing strangers' is not a board she can use.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

insert into public.world_config (key, value, description) values
  ('route_board_max', to_jsonb(400),
   '0106 (owner row 115): the most route rows world.route_board may serve in one read. The '
   'caller''s own routes are never dropped; beyond those the longest survive. The read serves '
   '`total` and `omitted`, so a cap is never a silent truncation.');

-- ── 1. HOW LONG A LOOP IS — one reading ────────────────────────────────────────────────────────
create or replace function public.route_nm(p_route uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0106: THE distance of a standing route, in nautical miles: the sum of its stops' BAKED leg
-- courses, each measured by voyage.segments_from_course — the server's own measure, the one a
-- voyage's ETA is built from. Every stop carries the course for the leg FROM it TO the next and
-- the loop closes on stop 0, so summing every stop's course is the whole loop exactly once.
--
-- NULL FOR A LOOP IT CANNOT MEASURE, AND WHY THAT IS NOT A SHRUG. voyage.segments_from_course
-- RAISES on a course the two rasters disagree about (E_NO_SEA: 0040's membership against 0046's
-- passability) — found here by this file's own positive control, which bent a baked course and
-- brought the whole migration down from inside the board's read. A route is validated at the door
-- it is saved through and again at every departure, so a baked course the sea disputes is a FAULT
-- and not a game state; but the board is a read of every route in the world, and one faulted loop
-- must not blank all of them. So the measure is taken per stop, and a stop it cannot measure makes
-- the whole route's figure null — "the server will not say how far this is" — which the board
-- prints as an absence and ranks last. Null also for a route that does not exist. 0 is a real
-- answer and is neither of those.
declare
  st    record;
  v_nm  numeric;
  v_sum numeric := 0;
begin
  if not exists (select 1 from public.standing_routes r where r.id = p_route) then
    return null;
  end if;
  for st in select s.course from public.standing_route_stops s where s.route_id = p_route loop
    begin
      select sum((x->>'nm')::numeric) into v_nm
        from jsonb_array_elements(voyage.segments_from_course(st.course)) x;
    exception when others then
      return null;
    end;
    if v_nm is null then return null; end if;
    v_sum := v_sum + v_nm;
  end loop;
  return v_sum;
end $$;

comment on function public.route_nm(uuid) is
  '0106: how far a standing route sails in one lap — the sum of its baked leg courses, measured by '
  'voyage.segments_from_course. The ONE distance reading for a loop, so the board and whatever '
  'ranks or gates routes next cannot disagree about it. Null for a route that does not exist, and '
  'for one whose baked course the sea disputes (segments_from_course raises): one faulted loop must '
  'not blank a board of every route in the world. Server-only.';

-- ── 2. THE BOARD ───────────────────────────────────────────────────────────────────────────────
create or replace function world.route_board()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0106: EVERY LANE THE WORLD SAILS (owner row 115). The caller's own routes and the merchants',
-- with the figures to rank them by; never another player's. A READ — it composes no order.
declare
  v_me    uuid := public.current_player_id();
  v_on    boolean := public.npc_traders_on();
  v_max   int := greatest(1, public.wc_int('route_board_max'));
  v_total int;
  v_rows  jsonb;
begin
  if v_me is null then
    raise exception 'E_NO_HOUSE: there is no company on this account' using errcode = 'P0001';
  end if;

  with r as (
    select sr.id, sr.name, sr.player_id, sr.fleet_id, sr.paused_reason,
           sr.player_id = v_me as mine,
           p.is_npc, p.company_name,
           nn.code as nation_code, h.ink,
           (select count(*) from public.standing_route_stops st where st.route_id = sr.id) as stop_count,
           public.route_nm(sr.id) as nm,
           (select count(distinct po.region_id)
              from public.standing_route_stops st join public.ports po on po.id = st.port_id
             where st.route_id = sr.id) as regions,
           (select coalesce(jsonb_agg(po.code order by st.ord), '[]'::jsonb)
              from public.standing_route_stops st join public.ports po on po.id = st.port_id
             where st.route_id = sr.id) as stops,
           public.standing_route_state(sr.id, case when p.is_npc then v_on else true end) as state,
           public.route_earnings(sr.id) as earnings
      from public.standing_routes sr
      join public.players p on p.id = sr.player_id
      left join public.npc_houses h on h.player_id = p.id
      left join public.nations nn on nn.id = p.nation_id
     where sr.player_id = v_me
        or (p.is_npc and v_on)
  ), pick as (
    -- THE CAP: her own first, whatever they measure, then the longest. Ordered by distance within
    -- each half so the cap drops the shortest hops and never the India run.
    select r.*, row_number() over (order by r.mine desc, r.nm desc nulls last, r.name, r.id) as rk
      from r
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', pick.id,
           'name', pick.name,
           'mine', pick.mine,
           'merchant', pick.is_npc,
           'company', case when pick.mine then null else pick.company_name end,
           'nation_code', pick.nation_code,
           'ink', pick.ink,
           'stops', pick.stops,
           'stop_count', pick.stop_count,
           'nm', pick.nm,
           'regions', pick.regions,
           'state', pick.state,
           'assigned', pick.fleet_id is not null,
           'earnings', pick.earnings)
         order by pick.rk), '[]'::jsonb)
    into v_rows from pick where pick.rk <= v_max;

  select count(*) into v_total
    from public.standing_routes sr join public.players p on p.id = sr.player_id
   where sr.player_id = v_me or (p.is_npc and v_on);

  return jsonb_build_object('at', now(), 'merchants', v_on, 'routes', v_rows,
                            'total', v_total,
                            'omitted', v_total - jsonb_array_length(v_rows));
end $$;

comment on function world.route_board() is
  '0106 (owner row 115): every standing route the caller may know of — her own and the merchants'' '
  '— with the stops, the distance (public.route_nm, the baked courses), how many regions the loop '
  'touches, its state and public.route_earnings. Never another player''s route. Capped at '
  'route_board_max with `total` and `omitted`; her own routes never drop. A READ: no order.';

-- ── 3. THE REGISTRY ────────────────────────────────────────────────────────────────────────────
create temporary table hunks_0106 (fn text not null, n int not null, old text not null, new text not null);
create temporary table defs_before_0106 (fn text primary key, def text not null, acl text not null);

insert into hunks_0106 values
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'standing_routes',       ''),$h$,
$h$      ('world',       'standing_routes',       ''),
      -- 0106 (owner row 115): every lane the world sails, the captain's and the merchants', with
      -- the figures to rank them by. A read; it composes no order and names no player id.
      ('world',       'route_board',           ''),$h$);

insert into defs_before_0106
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', ''),
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '')
  from (select distinct fn from hunks_0106) as f(fn);

create or replace function pg_temp.recut_0106(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0106 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0106 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0106: hunk % of % matches the pre-image % time(s), not once', h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0106('public.client_rpc_entry_points()');

-- ── 4. GRANTS ──────────────────────────────────────────────────────────────────────────────────
revoke all on function public.route_nm(uuid)    from public, anon, authenticated;
revoke all on function world.route_board()      from public, anon;
grant execute on function world.route_board()   to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.okeys_0106(p jsonb)
returns text[]
language sql
immutable
as $$
  select coalesce(array_agg(k order by k collate "C"), '{}') from jsonb_object_keys(p) k
$$;

do $$
declare
  c_auth    constant uuid := '00000000-0106-4000-8000-0000000000a1';
  c_other   constant uuid := '00000000-0106-4000-8000-0000000000a2';
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  v_n       int;
  v_me      uuid;
  v_them    uuid;
  v_fleet   uuid;
  v_leg     jsonb;
  v_back_c  jsonb;
  v_route   uuid;
  v_oroute  uuid;
  v_lis     uuid;
  v_fnc     uuid;
  v_board   jsonb;
  v_row     jsonb;
  v_keys    text[];
  v_dark    jsonb;
  v_base    int;
  v_nm      numeric;
  v_sum     numeric;
  v_mine    int;
  v_mer     int;
  v_total   int;
  v_ms      numeric;
  v_t0      timestamptz;
  v_err     text;
begin
  -- (a) THE REGISTRY IS ITS PRE-IMAGE PLUS ONLY THIS FILE'S HUNK, ACL UNMOVED.
  for v_fn in select distinct fn from hunks_0106 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0106 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0106 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0106 where fn = v_fn) or v_def = v_back then
      raise exception '0106 self-assert FAIL: % is not its pre-image plus only 0106''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0106 where fn = v_fn) then
      raise exception '0106 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) THE GRANTS AND THE WALLS.
  if not has_function_privilege('authenticated', 'world.route_board()', 'execute')
     or has_function_privilege('anon', 'world.route_board()', 'execute')
     or has_function_privilege('authenticated', 'public.route_nm(uuid)', 'execute')
     or has_function_privilege('anon', 'public.route_nm(uuid)', 'execute') then
    raise exception '0106 self-assert FAIL: the board is not exactly authenticated-only, or route_nm is reachable';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where e.function_name = 'route_board' and e.arg_types = '' and e.fn is not null) <> 1
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0106 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;

  -- (c) THE BOARD ITSELF, on probe companies, rolled back.
  select count(*) into v_base from public.players;
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_fnc from public.ports where code = 'FNC';
    v_leg := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                       jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                from public.sea_reaches a, public.sea_reaches b
               where a.port_id = v_lis and b.port_id = v_fnc);
    v_back_c := jsonb_build_array(v_leg->1, v_leg->0);

    -- the caller, with one route of her own...
    v_me := public.new_house(c_auth, 'Casa do Quadro', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_me;
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fleet;
    -- `id`, not `route_id`: cmd.standing_route_save_for answers {ok, id, name, stops} (0096).
    v_route := (cmd.standing_route_save_for(v_me, null, 'A minha rota',
                  jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                    jsonb_build_object('port', 'FNC', 'course', v_back_c)),
                  null, null, 0)->>'id')::uuid;
    -- ...and ANOTHER CAPTAIN, whose route must never appear (DESIGN §E.5). The positive control.
    v_them := public.new_house(c_other, 'Casa Alheia', 'PRT');
    v_oroute := (cmd.standing_route_save_for(v_them, null, 'A rota alheia',
                   jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                     jsonb_build_object('port', 'FNC', 'course', v_back_c)),
                   null, null, 0)->>'id')::uuid;
    if v_route is null or v_oroute is null then
      raise exception '0106 self-assert FAIL: a probe route was not saved (mine %, theirs %)', v_route, v_oroute;
    end if;

    perform cmd.assume_identity(c_auth);

    -- (c1) DARK: her own route, and not one merchant.
    v_dark := world.route_board();
    if (v_dark->>'merchants')::boolean
       or jsonb_array_length(v_dark->'routes') <> 1
       or (v_dark->'routes'->0->>'id')::uuid <> v_route
       or (v_dark->'routes'->0->>'mine')::boolean is not true
       or (v_dark->>'omitted')::int <> 0 then
      raise exception '0106 self-assert FAIL: dark, the board is not her one route: %', left(v_dark::text, 400);
    end if;

    -- (c2) ON: the merchants' routes too, and still no other captain's.
    perform public.npc_traders_switch(true);
    v_board := world.route_board();
    select count(*) filter (where (x->>'mine')::boolean),
           count(*) filter (where (x->>'merchant')::boolean)
      into v_mine, v_mer from jsonb_array_elements(v_board->'routes') x;
    v_total := jsonb_array_length(v_board->'routes');
    if not (v_board->>'merchants')::boolean or v_mine <> 1 or v_mer < 20 then
      raise exception '0106 self-assert FAIL: on, the board served % row(s) — % hers, % merchants''',
        v_total, v_mine, v_mer;
    end if;
    if exists (select 1 from jsonb_array_elements(v_board->'routes') x where (x->>'id')::uuid = v_oroute) then
      raise exception '0106 self-assert FAIL: another captain''s route is on the board';
    end if;
    if exists (select 1 from jsonb_array_elements(v_board->'routes') x
                where not (x->>'merchant')::boolean and not (x->>'mine')::boolean) then
      raise exception '0106 self-assert FAIL: a row is neither hers nor a merchant''s';
    end if;
    -- hers carries no company name (she knows whose it is); a merchant's does
    if v_board->'routes'->0->'company' <> 'null'::jsonb
       or not exists (select 1 from jsonb_array_elements(v_board->'routes') x
                       where (x->>'merchant')::boolean and x->>'company' is not null
                         and x->>'nation_code' is not null and x->>'ink' is not null) then
      raise exception '0106 self-assert FAIL: a merchant row does not name its company, nation and ink';
    end if;

    -- (c3) THE EXACT KEY SETS — the contract.
    v_keys := pg_temp.okeys_0106(v_board);
    if v_keys <> array['at', 'merchants', 'omitted', 'routes', 'total'] then
      raise exception '0106 self-assert FAIL: board top-level keys %', v_keys;
    end if;
    select x into v_row from jsonb_array_elements(v_board->'routes') x where (x->>'merchant')::boolean limit 1;
    v_keys := pg_temp.okeys_0106(v_row);
    if v_keys <> array['assigned', 'company', 'earnings', 'id', 'ink', 'merchant', 'mine', 'name',
                       'nation_code', 'nm', 'regions', 'state', 'stop_count', 'stops'] then
      raise exception '0106 self-assert FAIL: a route row''s keys %', v_keys;
    end if;
    -- the earnings object is route_earnings' own, not a second shape
    if pg_temp.okeys_0106(v_row->'earnings') <> pg_temp.okeys_0106(public.route_earnings((v_row->>'id')::uuid)) then
      raise exception '0106 self-assert FAIL: the board''s earnings object is not public.route_earnings''';
    end if;

    -- (c4) THE DISTANCE IS THE BAKED COURSES, re-derived here off the stops themselves.
    v_nm := (select (x->>'nm')::numeric from jsonb_array_elements(v_board->'routes') x
              where (x->>'id')::uuid = (v_row->>'id')::uuid);
    select sum(g.nm) into v_sum
      from public.standing_route_stops st
      cross join lateral (select sum((s->>'nm')::numeric) as nm
                            from jsonb_array_elements(voyage.segments_from_course(st.course)) s) g
     where st.route_id = (v_row->>'id')::uuid;
    if v_nm is null or v_sum is null or abs(v_nm - v_sum) > 0.01 or v_nm <= 0 then
      raise exception '0106 self-assert FAIL: the board says % nm and her stops measure % nm', v_nm, v_sum;
    end if;
    -- POSITIVE CONTROL: shorten one baked course and the figure MOVES. The bend is a PREFIX of the
    -- course she already sails — every consecutive pair in it is a pair the full course already had,
    -- so every segment is water the rasters still agree on, and the only thing that changed is how
    -- far it goes. (The first cut of this control bent the course geometrically instead;
    -- voyage.segments_from_course raised E_NO_SEA at 48.92, 5.00 and brought the whole migration
    -- down from inside the board's own read, which is how route_nm came to answer null for a loop
    -- it cannot measure — proven two assertions below.)
    update public.standing_route_stops st
       set course = (select jsonb_agg(p.v order by p.i)
                       from jsonb_array_elements(st.course) with ordinality as p(v, i)
                      where p.i <= greatest(2, jsonb_array_length(st.course) / 2))
     where st.route_id = (v_row->>'id')::uuid and st.ord = 0
       and jsonb_array_length(st.course) >= 5;
    if public.route_nm((v_row->>'id')::uuid) >= v_nm then
      raise exception '0106 self-assert FAIL: half a baked course did not shorten the figure (% nm, was % nm) — it is not the loop''s water',
        public.route_nm((v_row->>'id')::uuid), v_nm;
    end if;
    if public.route_nm('00000000-0000-4000-8000-000000000000'::uuid) is not null then
      raise exception '0106 self-assert FAIL: route_nm answered for a route that does not exist';
    end if;
    -- AND A LOOP THE SEA DISPUTES MEASURES NULL RATHER THAN BRINGING THE BOARD DOWN. This is the
    -- very course that faulted: two points over eastern France, which segments_from_course refuses
    -- E_NO_SEA. A read of every route in the world cannot be one bad row away from serving nothing,
    -- and the wire type of `nm` is nullable because of this rather than as a convenience.
    update public.standing_route_stops st
       set course = jsonb_build_array(jsonb_build_array(48.92, 5.00), jsonb_build_array(48.50, 5.50))
     where st.route_id = v_route and st.ord = 0;
    if public.route_nm(v_route) is not null then
      raise exception '0106 self-assert FAIL: a course the sea disputes measured % nm instead of null',
        public.route_nm(v_route);
    end if;
    if (select count(*) from jsonb_array_elements(world.route_board()->'routes') x) < 20
       or (select x->'nm' from jsonb_array_elements(world.route_board()->'routes') x
            where (x->>'id')::uuid = v_route) <> 'null'::jsonb then
      raise exception '0106 self-assert FAIL: one unmeasurable loop blanked the board, or it printed a figure for it';
    end if;

    -- (c5) THE CAP BITES, HER OWN SURVIVES IT, and the board owns up to what it left out.
    update public.world_config set value = to_jsonb(3) where key = 'route_board_max';
    v_board := world.route_board();
    if jsonb_array_length(v_board->'routes') <> 3
       or (v_board->>'total')::int <> v_total
       or (v_board->>'omitted')::int <> v_total - 3
       or not exists (select 1 from jsonb_array_elements(v_board->'routes') x where (x->>'id')::uuid = v_route) then
      raise exception '0106 self-assert FAIL: capped at 3 the board served % of % (omitted %) and %s her own',
        jsonb_array_length(v_board->'routes'), v_board->>'total', v_board->>'omitted',
        case when exists (select 1 from jsonb_array_elements(v_board->'routes') x
                           where (x->>'id')::uuid = v_route) then 'kept' else 'dropped' end;
    end if;
    -- and beyond her own, the LONGEST survive: every merchant row kept is at least as long as
    -- every merchant route left off.
    if exists (
      select 1 from public.standing_routes sr
        join public.players p on p.id = sr.player_id and p.is_npc
       where not exists (select 1 from jsonb_array_elements(v_board->'routes') x where (x->>'id')::uuid = sr.id)
         and public.route_nm(sr.id) > (select min((x->>'nm')::numeric)
                                         from jsonb_array_elements(v_board->'routes') x
                                        where (x->>'merchant')::boolean)) then
      raise exception '0106 self-assert FAIL: the cap dropped a longer merchant route than one it kept';
    end if;
    update public.world_config set value = to_jsonb(400) where key = 'route_board_max';

    -- (c6) WHAT IT COSTS. The board measures every loop's baked course on every read, so the
    --      number goes on the record rather than being hoped for.
    v_t0 := clock_timestamp();
    for v_n in 1..10 loop perform world.route_board(); end loop;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 10, 2);

    -- (c7) NO HOUSE, NO BOARD — in words, not as a crash.
    perform cmd.assume_identity('00000000-0106-4000-8000-0000000000ff'::uuid);
    begin
      perform world.route_board();
      raise exception '0106 self-assert FAIL: the board answered an account with no company';
    exception when others then
      v_err := sqlerrm;
      if v_err not like 'E_NO_HOUSE%' then raise; end if;
    end;

    raise exception 'ROLLBACK_0106';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0106' then raise; end if;
  end;

  if (select count(*) from public.players) <> v_base
     or public.wc_int('route_board_max') <> 400
     or public.npc_traders_on() then
    raise exception '0106 self-assert FAIL: the probe did not leave the world as it found it';
  end if;

  raise notice '0106 self-assert ok: EVERY LANE THE WORLD SAILS, ON ONE BOARD. '
    'client_rpc_entry_points is its pre-image plus only this file''s one hunk, ACL unmoved, and it '
    'names world.route_board(); the board is authenticated-only and public.route_nm is reachable by '
    'nobody. On probe companies, rolled back: DARK the board is her ONE route and no merchant; ON it '
    'carries % row(s) — 1 hers and % merchants'' — and NOT the second captain''s route that was '
    'planted beside hers, every row being either hers or a merchant''s, hers naming no company and a '
    'merchant''s naming company, nation and ink. The top-level and row key sets are exact and the '
    'earnings object IS public.route_earnings'' own. The distance is the loop''s BAKED courses: the '
    'board''s % nm equals the sum re-derived off her stops through voyage.segments_from_course, and '
    'bending one baked course MOVED the figure (positive control), while a route that does not exist '
    'measures null rather than zero. Capped at 3 the board served 3 of %, said it omitted %, kept HER '
    'route, and dropped no merchant route longer than one it kept. An account with no company is '
    'refused E_NO_HOUSE in words. The board took % ms a call over 10 calls at this roster.',
    v_total, v_mer, v_nm, v_total, v_total - 3, v_ms;
end $$;
