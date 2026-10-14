-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0111 — A MAJOR FLEET DRAWS HER LANE
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- Row 125, 2026-10-12: *"when i zoom out, i want cities to be bright light, in a dark map, visually
-- beautiful. so are ships but in tiny dots… and major fleet shoud also show the routes as well"*.
--
-- The chart half of that row is already drawn: a harbour is a core and a halo scaled by its
-- size_tier, and a merchant past HULL_EMBER_MAX_UNITS_PER_PX is a dim ember in her nation's ink
-- rather than a 10 px silhouette. This file serves the LAST CLAUSE — the lane a major fleet keeps —
-- and it is the only half that needed the server, because the client has no idea where a merchant's
-- loop goes. `world.sea_traffic` tells it where she is NOW and, through `voyage`, the one leg she is
-- on; the other seven legs of her loop are not on the wire at all.
--
-- ── WHY THE COURSE CANNOT SIMPLY BE SERVED ──────────────────────────────────────────────────────
-- A loop's geometry already exists and is already baked: `standing_route_stops.course` is the
-- authored polyline for the leg FROM each stop TO the next (0092), re-verified at every departure by
-- do_sail. Eight stops of some hundred points each is ~800 [lat, lon] pairs per fleet. At
-- `sea_traffic_max` = 240 fleets that is ~192,000 pairs on a read the chart re-asks on the world's
-- beat — some megabytes per beat, to draw lines that at a 360°-wide span are a few pixels long.
--
-- So the lane is DECIMATED: `fleet_lane_points_max` points, chosen by an even stride, with points
-- that are never dropped whatever the stride says —
--
--   * EVERY STOP BOUNDARY. A harbour is where the owner's eye expects the line to touch, and a
--     stride that skipped one would float the lane off the coast it calls at.
--   * THE FIRST AND LAST POINT, which on a loop are the same harbour, so the line closes.
--
-- ── WHAT A LANE IS NOT, STATED ON THE WIRE ──────────────────────────────────────────────────────
-- A decimated lane IS A SIMPLIFICATION AND CROSSES LAND. Between two kept points the straight
-- segment owes nothing to the raster — that is the whole point of dropping the others — and at a
-- span where India is 40 px wide nobody can see it. But this chain's law is that the sea is the
-- server's to say (0040, 0047), and a key that LOOKS like a course would eventually be handed to
-- something that wanted to sail it. So:
--
--   * the key is named `lane`, not `course`,
--   * it is served ONLY as a sibling of `voyage`, which carries her real, sailable leg, and
--   * nothing but the chart may read it: `public.route_lane` is revoked from every client role, the
--     same wall `public.route_nm` stands behind (0106).
--
-- ── WHAT 0106 TAUGHT, AND WHAT IS DIFFERENT HERE ────────────────────────────────────────────────
-- 0106's first cut measured every loop's course on every read of the board and cost 4,543 ms a
-- call, because `voyage.segments_from_course` WALKS THE RASTER per segment. A lane walks nothing:
-- it is jsonb element access over an array that is already in the row's page. That is a claim about
-- cost, though, and this chain does not accept claims — so (h) below times the full-world read with
-- lanes AGAINST THE CLONED PRE-IMAGE and fails the migration on a RATIO, not on a wall-clock
-- figure, because a ratio is the one timing statement a shared CI runner cannot make a liar of.
--
-- ── WHAT THIS SUPERSEDES ────────────────────────────────────────────────────────────────────────
-- IT SUPERSEDES `world.sea_traffic(jsonb)`, cut by 0102 and already re-cut once by row 120 for the
-- `hulls` key. A deployed rule changes in a NEW file that supersedes the old one, never by editing
-- the file that has run (supabase/migrations/README.md:43-48), and this is that file.
--
-- WHAT MOVES: one reading in the `m` CTE and one key on the served row. Nothing else in that
-- function is retyped — the body is re-cut out of the LIVE catalogue by substitution and the
-- substitution is then REVERSED and compared to the pre-image byte for byte (§4), so the claim
-- "only these two hunks moved" is proven rather than promised. The ACL is restated and then read
-- back (§5i), because an ACL that travels silently is an ACL nobody is checking.
--
-- WHETHER IT IS A NO-OP WHEN THE NEW INPUT IS ABSENT: YES, AND THAT IS THE DEFAULT CASE. A fleet
-- below `fleet_lane_min_ships`, or one with no standing route, is served `lane: null` — the key is
-- present and empty, never missing — and every other key she is served is byte-for-byte what 0102
-- served before this file ran. §5a asserts exactly that over the whole world, with `lane` struck
-- out of the new row, so the supersede cannot have changed an answer it was not asked to change.
-- A caller that has never heard of `lane` cannot tell this migration ran.
--
-- AND `world.port_merchants` (0104) IS NOT TOUCHED EITHER, which is a decision and not an omission.
-- That read serves a row deliberately shaped like this one, and 0104's own self-assert compares the
-- two key sets — it passes because it runs BEFORE this file in the chain, every time, on a fresh
-- apply. A harbour's list of merchants is prose and a table, not a chart; it already serves `stops`
-- (the port CODES in sailing order), which is what a reader at a quay wants, and a thinned polyline
-- is of no use to anyone who is not drawing. The client type says so out loud rather than silently
-- inheriting a key the server does not send: `PortMerchant` is `Omit<TrafficFleet, 'lane'>`.
--
-- WHAT IT DOES NOT TOUCH: the merchant predicate (`players.is_npc`, still the one), the window and
-- its padding, the cap and its ordering, `total`/`omitted`, and the dark short-circuit. In
-- particular THE CAP IS NOT RE-ORDERED to favour a fleet that keeps a lane, even though that would
-- put more lanes on the glass: 0102's nearest-to-centre ordering is the chart's own rule and a
-- lane is a decoration on it. What the cap drops is recorded, not quietly fixed — see owner row 123
-- for the one place this chain HAS decided a cap's ordering was wrong, and what that took.
--
-- ── WHAT CHANGES ────────────────────────────────────────────────────────────────────────────────
--   * `public.route_lane(route, max_points)` — the decimated loop. Server-only.
--   * two knobs: `fleet_lane_min_ships` (what "major" means) and `fleet_lane_points_max`.
--   * `world.sea_traffic` gains ONE key, `lane`, null for everyone below the threshold or without a
--     route. The pre-image is cloned and the new row is asserted to be the old row with `lane`
--     struck out, byte for byte — 0102's own parity pattern, which is a stronger statement than
--     "the rows are equal" because it also says nothing else crept in beside it.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. WHAT "MAJOR" MEANS, AND HOW MANY POINTS A LANE MAY SPEND ────────────────────────────────
insert into public.world_config (key, value, description) values
  ('fleet_lane_min_ships', to_jsonb(2),
   '0111: the fewest hulls a merchant fleet may have and still be served her loop as `lane` in '
   'world.sea_traffic (owner row 125, "major fleet"). Below it the key is null and the chart draws '
   'her as an ember and nothing more. TWO, FROM THE ROSTER AS IT ACTUALLY IS rather than from a '
   'guess: the 837 merchant fleets are 788 of one hull, 43 of two and 6 of three, because 0105''s '
   'generated roster gives every one of its 761 companies a single hull and the squadrons are all '
   '0098''s founding 76. At three this knob served SIX lanes on a world chart, which is not "the '
   'routes show"; at two it serves 49 — the top 6% of the world''s fleets, a visible grain of '
   'trade and nowhere near spaghetti. If a later roster hands out squadrons more freely this is '
   'the one number to raise, and the figure above is what it was measured against.'),
  ('fleet_lane_points_max', to_jsonb(24),
   '0111: the most [lat, lon] points one served lane may carry. The loop''s baked courses are '
   'decimated by an even stride down to this, except that every stop boundary is kept whatever '
   'the stride says, so the line still touches the harbours it calls at. A LANE IS NOT A COURSE: '
   'between kept points it crosses land, it is named `lane` for that reason, and nothing but the '
   'chart may read it.')
on conflict (key) do update set value = excluded.value, description = excluded.description;

-- ── 2. THE DECIMATED LOOP ──────────────────────────────────────────────────────────────────────
create or replace function public.route_lane(p_route uuid, p_max int default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0111: this loop's shape, cheap enough to serve on the world's beat. Null when the route has no
-- stops. The points are the baked `standing_route_stops.course` arrays in `ord` order, de-duplicated
-- at the joins (a leg ENDS where the next BEGINS), then thinned by an even stride with every stop
-- boundary pinned. NOT SAILABLE — see this file's header.
declare
  v_max    int := greatest(2, coalesce(p_max, public.wc_int('fleet_lane_points_max')));
  v_pts    jsonb;
  v_n      int;
  v_harb   int;
  v_budget int;
  v_water  int;
  v_stride numeric;
begin
  -- EVERY POINT OF THE LOOP, with a flag saying which ones are harbours. A leg's last point is the
  -- next leg's first, so a point is dropped when it is the first of its leg and its leg is not the
  -- first leg — which keeps exactly one copy of each harbour and all the water between.
  with legs as (
    select st.ord, st.course,
           jsonb_array_length(st.course) as len,
           row_number() over (order by st.ord) as leg_no
      from public.standing_route_stops st
     where st.route_id = p_route
  ), pts as (
    select legs.leg_no, i.i, legs.course->i.i as pt,
           (i.i = 0 or i.i = legs.len - 1) as is_stop
      from legs
      cross join lateral generate_series(0, legs.len - 1) as i(i)
     where not (i.i = 0 and legs.leg_no > 1)
  )
  select coalesce(jsonb_agg(jsonb_build_array(pts.pt, pts.is_stop)
                            order by pts.leg_no, pts.i), '[]'::jsonb)
    into v_pts from pts;

  v_n := jsonb_array_length(v_pts);
  if v_n < 2 then
    return null;
  end if;

  if v_n <= v_max then
    return (select coalesce(jsonb_agg(x.v->0 order by x.i), '[]'::jsonb)
              from jsonb_array_elements(v_pts) with ordinality as x(v, i));
  end if;

  -- THE STRIDE, OVER THE WATER ONLY. The harbours are pinned, so THEY SPEND FROM THE BUDGET FIRST
  -- and the stride is laid over what is left — otherwise a loop with the full eight stops (0101
  -- raised standing_route_stop_max to exactly that) is nine pinned points PLUS a stride's worth,
  -- and a cap of 24 serves 33. The ceiling this function actually keeps is therefore
  -- `greatest(p_max, harbours)`: A HARBOUR IS NEVER DROPPED, whatever the budget says, because a
  -- lane that misses the coast it calls at is a wrong drawing rather than a coarse one. With the
  -- world's stop cap at 8 the harbours are at most 9, well under the default 24 — (d) asserts that
  -- rather than trusting it.
  select count(*) filter (where (x.v->>1)::boolean) into v_harb
    from jsonb_array_elements(v_pts) as x(v);

  -- A BUDGET THE HARBOURS HAVE ALREADY EATEN leaves no water to draw, so a loop with more calls
  -- than the budget is served its harbours and nothing between them. Honest and legible: the line
  -- still touches every coast, it is simply straight between them. Unreachable while the world's
  -- stop cap is 8 against a budget of 24, and here so that the ceiling is a rule rather than a
  -- coincidence of two knobs.
  if v_harb >= v_max then
    return (select coalesce(jsonb_agg(x.v->0 order by x.i), '[]'::jsonb)
              from jsonb_array_elements(v_pts) with ordinality as x(v, i)
             where (x.v->>1)::boolean);
  end if;

  v_budget := v_max - v_harb;
  v_water  := greatest(1, v_n - v_harb);
  v_stride := v_water::numeric / v_budget;

  -- `wr` is the point's position AMONG THE WATER POINTS — a running count, so the stride is even in
  -- water and is not pulled about by wherever the harbours happen to fall. `floor(wr / stride)`
  -- CHANGING is the test, which spaces the kept points along the loop instead of clustering them at
  -- its head, and keeps exactly `v_budget` of them. NO END PINS: the first and last point of a loop
  -- are both harbours, so `is_stop` has already pinned them, and a redundant pin here would be the
  -- one way this could overshoot its own cap.
  return (
    select coalesce(jsonb_agg(w.pt order by w.i), '[]'::jsonb)
      from (
        select x.v->0 as pt, x.i, (x.v->>1)::boolean as is_stop,
               count(*) filter (where not (x.v->>1)::boolean)
                 over (order by x.i rows between unbounded preceding and current row) as wr
          from jsonb_array_elements(v_pts) with ordinality as x(v, i)
      ) w
     where w.is_stop
        or floor((w.wr - 1) / v_stride) <> floor((w.wr - 2) / v_stride)
  );
end $$;

comment on function public.route_lane(uuid, int) is
  '0111: a loop''s shape, decimated to fleet_lane_points_max points with every stop boundary kept, '
  'for drawing a major fleet''s route at a wide zoom (owner row 125). NOT A COURSE and not '
  'sailable: between kept points it crosses land. Null when the route has no stops. Reachable by '
  'nobody but the server.';

revoke all on function public.route_lane(uuid, int) from public, anon, authenticated;

-- ── 3. THE PRE-IMAGE, CLONED BEFORE IT IS REPLACED ─────────────────────────────────────────────
-- The parity claim of this file rests on this clone: every key but `lane` must answer exactly what
-- it answered before, and the only way to say so without believing it is to keep the old read alive
-- in pg_temp and ask them both.
do $$
declare
  v_def text;
begin
  v_def := replace(pg_get_functiondef('world.sea_traffic(jsonb)'::regprocedure), E'\r', '');
  if strpos(v_def, 'CREATE OR REPLACE FUNCTION world.sea_traffic(p_view jsonb DEFAULT NULL::jsonb)') <> 1 then
    raise exception '0111: world.sea_traffic(jsonb) is not where this migration expects it: %',
      left(v_def, 160);
  end if;
  execute replace(v_def,
    'CREATE OR REPLACE FUNCTION world.sea_traffic(p_view jsonb DEFAULT NULL::jsonb)',
    'CREATE OR REPLACE FUNCTION pg_temp.traffic_before_0111(p_view jsonb DEFAULT NULL::jsonb)');
end $$;

-- ── 4. THE HUNKS ───────────────────────────────────────────────────────────────────────────────
-- Two, both re-cut out of the live body by reverse substitution so the rest of the read is proven
-- untouched rather than retyped: one reading the lane in the `m` CTE beside the other per-fleet
-- readings, and one serving it on the row.
create temp table hunks_0111 (ord int primary key, before text, after text);

insert into hunks_0111 (ord, before, after) values
(1,
$h$           (select world.voyage_view(v.id, false) from public.voyages v
             where v.fleet_id = f.id and v.status = 'SAILING') as vv
      from public.fleets f$h$,
$h$           (select world.voyage_view(v.id, false) from public.voyages v
             where v.fleet_id = f.id and v.status = 'SAILING') as vv,
           -- HER LANE (owner row 125, 0111). Read HERE, in the one CTE that already gathers a
           -- fleet's per-row facts, so it is asked once per fleet and not once per mention — which
           -- is the whole of what 0110 had to go back and fix on the route board. The threshold is
           -- tested in SQL rather than inside route_lane so a fleet below it costs not even a call.
           case when (select count(*) from public.ships s where s.fleet_id = f.id)
                     >= greatest(1, public.wc_int('fleet_lane_min_ships'))
                then public.route_lane(nf.route_id) end as lane
      from public.fleets f$h$),
(2,
$h$           'voyage', pick.vv,$h$,
$h$           'voyage', pick.vv,
           -- THE LANE a major fleet keeps, or null (owner row 125, 0111). A SIBLING OF `voyage`
           -- deliberately: that key is her real, raster-verified leg and this one is a thinned
           -- drawing of the whole loop, and anything that confused the two would be sailing a line
           -- that crosses land. The name says so, the comment on public.route_lane says so, and no
           -- client role can reach the function that makes it.
           'lane', pick.lane,$h$);

do $$
declare
  v_def  text;
  v_new  text;
  v_back text;
  h      record;
begin
  v_def := replace(pg_get_functiondef('world.sea_traffic(jsonb)'::regprocedure), E'\r', '');
  v_new := v_def;
  for h in select * from hunks_0111 order by ord loop
    if (length(v_new) - length(replace(v_new, h.before, ''))) / length(h.before) <> 1 then
      raise exception '0111: hunk % does not appear exactly once in world.sea_traffic', h.ord;
    end if;
    v_new := replace(v_new, h.before, h.after);
  end loop;

  -- PARITY BY REVERSE SUBSTITUTION: putting every hunk back must land on the pre-image exactly, so
  -- the re-cut body is the old body plus the declared hunks and nothing else.
  v_back := v_new;
  for h in select * from hunks_0111 order by ord desc loop
    v_back := replace(v_back, h.after, h.before);
  end loop;
  if v_back <> v_def then
    raise exception '0111: the re-cut body is not the pre-image plus the declared hunks';
  end if;

  execute v_new;
end $$;

-- The ACL the pre-image carried, restated rather than assumed. create-or-replace keeps an ACL, so
-- this cannot fail — but (i) below asks for it afterwards, and a file that states what it expects is
-- worth more than one that trusts a behaviour.
revoke all on function world.sea_traffic(jsonb) from public, anon;
grant execute on function world.sea_traffic(jsonb) to authenticated;

-- ── 5. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before   jsonb;
  v_after    jsonb;
  v_max      int := public.wc_int('fleet_lane_points_max');
  v_minships int := public.wc_int('fleet_lane_min_ships');
  v_route    uuid;
  v_lane     jsonb;
  v_full     jsonb;
  v_majors   int;
  v_lanes    int;
  v_more     int;
  v_t0       timestamptz;
  v_old_ms   numeric;
  v_new_ms   numeric;
  v_ratio    numeric;
  v_was_npc  jsonb;
  v_was_rt   jsonb;
  v_served   int;
  i          int;
begin
  -- ── THE SWITCH, AND WHY IT IS FLIPPED BY HAND ────────────────────────────────────────────────
  -- `world.sea_traffic` answers `enabled: false` with an EMPTY fleet list while the merchants are
  -- dark, and 0105 deliberately leaves them dark. Every assertion below is about the read, so the
  -- read has to be lit.
  --
  -- THE TWO KEYS, BY NAME, because `public.npc_traders_on()` (0097) is `npc_traders_enabled` AND
  -- `standing_routes_on()` — a merchant needs routes — and the first cut of this file wrote to a
  -- key called `npc_traders_switch`, WHICH DOES NOT EXIST. `npc_traders_switch` is the FUNCTION
  -- that flips the real key; the UPDATE matched no row, said nothing, and the read stayed dark. The
  -- positive control (c) caught it — 6 routed majors in the tables and not one lane on the wire —
  -- but assertion (a) had already PASSED VACUOUSLY on two empty fleet lists, which is why (a0)
  -- below now refuses an empty sea before parity is allowed to mean anything.
  --
  -- NOT `public.npc_traders_switch(true)`, which is what 0102's own assert calls. That function
  -- PLANS AND STARTS every merchant in the world; at 0102's 76 fleets that was cheap, and at the
  -- 837 this file runs against it is the operation that took some twenty minutes on production.
  -- Nothing here needs a merchant at sea: a lane comes from her standing ROUTE, which 0105 wrote,
  -- and `sea_traffic` serves a fleet lying at her home quay as readily as one on passage.
  select public.wc('npc_traders_enabled'), public.wc('standing_routes_enabled')
    into v_was_npc, v_was_rt;
  update public.world_config set value = 'true'::jsonb
   where key in ('npc_traders_enabled', 'standing_routes_enabled');
  if not public.npc_traders_on() then
    raise exception '0111 self-assert FAIL: both switch keys were set and the merchants are still dark';
  end if;

  -- (a0) THE SEA IS NOT EMPTY. Parity between two empty lists is not parity, it is two nothings
  -- agreeing, and that is exactly the pass this file's first cut got while the switch was dark. So
  -- the read must serve a real sheet of merchants, and at least one of them must be a MAJOR, before
  -- any claim below is allowed to mean anything.
  v_before := pg_temp.traffic_before_0111();
  v_after  := world.sea_traffic();
  v_served := jsonb_array_length(v_after->'fleets');
  if (v_after->>'enabled')::boolean is not true or v_served < 20 then
    raise exception '0111 self-assert FAIL: the read served % fleet(s), enabled % — nothing below would mean anything',
      v_served, v_after->>'enabled';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_after->'fleets') x
                  where (x->>'ships')::int >= v_minships) then
    raise exception '0111 self-assert FAIL: not one of the % served fleet(s) has % hull(s) — the cap dropped every major',
      v_served, v_minships;
  end if;

  -- (a) PARITY. The whole world, both reads, with `lane` struck out of the new one.
  if (select coalesce(jsonb_agg(x.v - 'lane' order by x.i), '[]'::jsonb)
        from jsonb_array_elements(v_after->'fleets') with ordinality as x(v, i))
       is distinct from v_before->'fleets' then
    raise exception '0111 self-assert FAIL: the read is not its pre-image plus `lane` — % row(s) vs %',
      jsonb_array_length(v_after->'fleets'), jsonb_array_length(v_before->'fleets');
  end if;
  if (v_after->>'total') <> (v_before->>'total') or (v_after->>'omitted') <> (v_before->>'omitted') then
    raise exception '0111 self-assert FAIL: total/omitted moved — % / %, was % / %',
      v_after->>'total', v_after->>'omitted', v_before->>'total', v_before->>'omitted';
  end if;

  -- (b) THE KEY IS ON EVERY ROW, present-but-null rather than absent, so the client never has to
  -- tell "she keeps no lane" from "an older server".
  if exists (select 1 from jsonb_array_elements(v_after->'fleets') x where not x ? 'lane') then
    raise exception '0111 self-assert FAIL: a merchant row is missing the lane key entirely';
  end if;

  -- (c) POSITIVE CONTROL: somebody is actually drawing one. If the roster holds no routed major
  -- fleet the claim is untested, and an untested claim fails here rather than passing quietly.
  select count(*) into v_majors
    from public.fleets f
    join public.players p on p.id = f.player_id and p.is_npc
    join public.npc_fleets nf on nf.fleet_id = f.id
   where nf.route_id is not null
     and (select count(*) from public.ships s where s.fleet_id = f.id) >= v_minships;
  if v_majors = 0 then
    raise exception '0111 self-assert FAIL: no routed merchant has % hull(s) — the lane is untested',
      v_minships;
  end if;

  select count(*) into v_lanes
    from jsonb_array_elements(v_after->'fleets') x
   where x->'lane' is not null and x->'lane' <> 'null'::jsonb;
  if v_lanes = 0 then
    raise exception '0111 self-assert FAIL: % routed major fleet(s) and not one lane served', v_majors;
  end if;

  -- (d) SHAPE. Every served lane is an array of at least two [lat, lon] pairs, inside the cap, and
  -- on the globe. A lane that left the globe would be a chart line drawn through nothing.
  if exists (select 1 from jsonb_array_elements(v_after->'fleets') x
              where x->'lane' <> 'null'::jsonb
                and (jsonb_typeof(x->'lane') <> 'array'
                     or jsonb_array_length(x->'lane') < 2
                     or jsonb_array_length(x->'lane') > v_max)) then
    raise exception '0111 self-assert FAIL: a lane is not an array of 2..% points', v_max;
  end if;
  if exists (select 1 from jsonb_array_elements(v_after->'fleets') x,
                         jsonb_array_elements(x->'lane') pt
              where x->'lane' <> 'null'::jsonb
                and (jsonb_typeof(pt) <> 'array' or jsonb_array_length(pt) <> 2
                     or (pt->>0)::double precision not between -90 and 90
                     or (pt->>1)::double precision not between -180 and 180)) then
    raise exception '0111 self-assert FAIL: a lane carries a point that is not a [lat, lon] on the globe';
  end if;

  -- (e) THE HARBOURS ARE KEPT. Take the longest-looped routed major in the roster and prove her
  -- lane still contains the first point of EVERY leg — which is the one promise decimation makes.
  select nf.route_id into v_route
    from public.fleets f
    join public.players p on p.id = f.player_id and p.is_npc
    join public.npc_fleets nf on nf.fleet_id = f.id
   where nf.route_id is not null
     and (select count(*) from public.ships s where s.fleet_id = f.id) >= v_minships
     and (select count(*) from public.standing_route_stops st where st.route_id = nf.route_id) >= 2
   order by (select count(*) from public.standing_route_stops st where st.route_id = nf.route_id) desc,
            nf.route_id
   limit 1;
  if v_route is null then
    raise exception '0111 self-assert FAIL: no routed major fleet with two stops to test the harbours on';
  end if;

  v_lane := public.route_lane(v_route);
  if v_lane is null then
    raise exception '0111 self-assert FAIL: route_lane answered null for a loop that has stops';
  end if;
  if exists (select 1 from public.standing_route_stops st
              where st.route_id = v_route
                and not (v_lane @> jsonb_build_array(st.course->0))) then
    raise exception '0111 self-assert FAIL: a lane dropped a harbour — route %, % lane point(s)',
      v_route, jsonb_array_length(v_lane);
  end if;

  -- (f) DECIMATION ACTUALLY HAPPENED, and it is lossy on purpose. The full loop must be longer than
  -- the lane or this file is doing nothing and the cap is untested. Asked with a huge budget, so
  -- the comparison is lane-against-loop and not lane-against-lane.
  v_full := public.route_lane(v_route, 100000);
  if jsonb_array_length(v_full) <= jsonb_array_length(v_lane) then
    raise exception '0111 self-assert FAIL: the longest loop in the roster is % point(s) — the cap of % is untested',
      jsonb_array_length(v_full), v_max;
  end if;
  -- …and every kept point is the loop's own: a subsequence, never a re-drawing. Walked point by
  -- point rather than set-compared, because a lane that invented water would be exactly the defect
  -- this file's header promises it does not have.
  for i in 0 .. jsonb_array_length(v_lane) - 1 loop
    if not (v_full @> jsonb_build_array(v_lane->i)) then
      raise exception '0111 self-assert FAIL: lane point % is not a point of the loop', i;
    end if;
  end loop;
  if v_lane->0 is distinct from v_full->0
     or v_lane->(jsonb_array_length(v_lane) - 1)
        is distinct from v_full->(jsonb_array_length(v_full) - 1) then
    raise exception '0111 self-assert FAIL: a lane does not begin and end where its loop does';
  end if;

  -- (g) THE THRESHOLD IS A REAL KNOB, not a number in a comment. Nobody under the line is served a
  -- lane; raise the line past everyone and the lanes go; drop it to one hull and more appear.
  if exists (select 1 from jsonb_array_elements(v_after->'fleets') x
              where (x->>'ships')::int < v_minships and x->'lane' <> 'null'::jsonb) then
    raise exception '0111 self-assert FAIL: a fleet below % hull(s) was served a lane', v_minships;
  end if;
  update public.world_config set value = to_jsonb(99) where key = 'fleet_lane_min_ships';
  if exists (select 1 from jsonb_array_elements(world.sea_traffic()->'fleets') x
              where x->'lane' <> 'null'::jsonb) then
    raise exception '0111 self-assert FAIL: fleet_lane_min_ships = 99 and somebody still drew a lane';
  end if;
  update public.world_config set value = to_jsonb(1) where key = 'fleet_lane_min_ships';
  select count(*) into v_more from jsonb_array_elements(world.sea_traffic()->'fleets') x
   where x->'lane' <> 'null'::jsonb;
  if v_more <= v_lanes then
    raise exception '0111 self-assert FAIL: fleet_lane_min_ships = 1 served % lane(s), no more than %',
      v_more, v_lanes;
  end if;
  update public.world_config set value = to_jsonb(v_minships) where key = 'fleet_lane_min_ships';

  -- (h) THE COST, AS A RATIO. 0106 was 4,543 ms a call before anybody timed it, so this file times
  -- itself. Against the CLONED PRE-IMAGE, over the same rows, in the same transaction, on whatever
  -- runner this is — a ratio is the only timing claim a shared runner cannot make a liar of, which
  -- this chain learned the week two 30-minute CI budgets were killed by variance alone.
  v_t0 := clock_timestamp();
  for i in 1 .. 3 loop perform pg_temp.traffic_before_0111(); end loop;
  v_old_ms := extract(epoch from clock_timestamp() - v_t0) * 1000 / 3;
  v_t0 := clock_timestamp();
  for i in 1 .. 3 loop perform world.sea_traffic(); end loop;
  v_new_ms := extract(epoch from clock_timestamp() - v_t0) * 1000 / 3;
  v_ratio := v_new_ms / greatest(0.001, v_old_ms);
  if v_ratio > 2.5 then
    raise exception '0111 self-assert FAIL: the lane costs %x the read (% ms vs % ms, % lane(s)) — bake it at the write',
      round(v_ratio, 2), round(v_new_ms, 1), round(v_old_ms, 1), v_lanes;
  end if;

  -- (i) THE WALL. The chart's own read stays authenticated-only and route_lane is reachable by
  -- nobody, so a lane can never be asked for by anything that might then try to sail it.
  if has_function_privilege('authenticated', 'public.route_lane(uuid, int)', 'execute')
     or has_function_privilege('anon', 'public.route_lane(uuid, int)', 'execute')
     or has_function_privilege('anon', 'world.sea_traffic(jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'world.sea_traffic(jsonb)', 'execute') then
    raise exception '0111 self-assert FAIL: route_lane is reachable, or sea_traffic is not exactly authenticated-only';
  end if;

  -- THE SWITCH GOES BACK TO WHAT IT WAS. 0105 leaves the merchants dark on purpose and a migration
  -- that lit the world as a side effect of proving itself would be a migration that changed the
  -- game while testing it.
  update public.world_config set value = v_was_npc where key = 'npc_traders_enabled';
  update public.world_config set value = v_was_rt  where key = 'standing_routes_enabled';
  if public.wc('npc_traders_enabled') is distinct from v_was_npc
     or public.wc('standing_routes_enabled') is distinct from v_was_rt then
    raise exception '0111 self-assert FAIL: the switch was not put back as it was found';
  end if;

  raise notice '0111 self-assert ok: A MAJOR FLEET DRAWS HER LANE. The read is its pre-image plus '
    'one key, byte for byte, over % served fleet(s). % routed major fleet(s) at >= % hull(s), '
    '% lane(s) served, longest '
    'loop % point(s) thinned to % with every harbour kept and both ends pinned. The knob moves it '
    'both ways (99 -> none, 1 -> % lane(s)). Cost %x the pre-image (% ms vs % ms a call). '
    'public.route_lane is reachable by nobody.',
    v_served, v_majors, v_minships, v_lanes, jsonb_array_length(v_full), jsonb_array_length(v_lane),
    v_more, round(v_ratio, 2), round(v_new_ms, 1), round(v_old_ms, 1);
end $$;
