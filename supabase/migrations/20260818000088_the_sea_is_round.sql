-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0088 — THE SEA IS ROUND
--        Longitude is modular. A course segment whose two ends straddle the antimeridian is read
--        the SHORT way round by every server reader — the verifier, the segment cutter and the
--        closed-form position — through ONE longitude rule, voyage.lon_lerp. Tokyo to Callao
--        crosses the South Pacific; it is no longer refused as "the long way round".
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 98, 2026-09-14) ────────────────────────────
--   "the map should be continuous on left to right, and the ship going from tokyo to callao
--    should cross south pacific ocean."
--
-- ── WHAT WAS WRONG, MEASURED ON THE APPLIED CHAIN (2026-09-14, _probe on main 2209a92) ────────
--   The grid has always been round: `colOf`/`isWater` wrap the column (src/lib/sea/grid.ts:66),
--   the A* neighbour expansion wraps (pathfind.ts), and so does every cell lookup in this chain
--   (`((floor((lon + 180) / 0.25)::int % 1440) + 1440) % 1440`). The search FOUND the Pacific:
--   Tokyo → Acapulco came back as [[35.13,140.38],[39.13,179.88],[39.13,-179.88],[16.63,-99.88]]
--   — 6,223.5 nm, with the two cell centres either side of the seam 0.25° apart. Two readers
--   then refused to believe it:
--     * src/lib/sea/pathfind.ts `segmentIsWater` returned false for any |Δlon| > 180, so the
--       straightener could never merge across the seam (the kink above), and
--     * voyage.path_refusal (0046:443) returned `E_BAD_PATH: segment 1 jumps the antimeridian the
--       long way round` for that 0.25° hop — so a seam-crossing course could be found and shown
--       and NEVER SAILED. cmd.do_sail raises the refusal; the fleet stays where she is.
--   And two more readers would have swept the world had the refusal not stood in front of them:
--   voyage.segments_from_course (0047:274-275) cuts a segment into ceil(nm/500) pieces by
--   `lon1 + (lon2 - lon1) * k / pieces`, and voyage.position (0047:536) places the ship by
--   `a + (b - a) * leg_frac` — on 179.88 → −179.88 both walk 359.75° of longitude westward
--   through Asia, Africa and the Atlantic instead of the 0.25° she sails.
--   The measure was never wrong: voyage.gc_distance_nm (0002) is the haversine, whose
--   sin²(Δλ/2) is periodic in 360°, so it has always taken the short way (asserted below).
--
-- ── THE CONVENTION, stated once and written on both sides of the wire ──────────────────────────
--   1. Every vertex of a course lies in [−180, 180]. (Already the law: path_refusal's "off the
--      sphere" check; the pathfinder emits cell centres and served roadsteads, never anything
--      else.)
--   2. A segment MAY straddle the antimeridian — its two vertices on opposite sides of ±180 —
--      and it is ALWAYS read the short way round, the way whose |Δlon| ≤ 180. There is no long
--      way; nothing can express one.
--   3. Every reader steps longitude through ONE rule: voyage.lon_lerp(lon1, lon2, f) here,
--      `lonLerp` in src/lib/geo on the client. Never `a + (b − a) · f` on raw degrees again.
--   The alternative — forbid straddling and have the pathfinder split every crossing into a
--   pair of vertices [lat, 180], [lat, −180] — was measured and rejected: it creates a zero-
--   length segment that segments_from_course drops (`continue when seg_nm <= 0`), after which
--   course_of re-joins the two sides into exactly the straddling segment it was meant to avoid,
--   and position/drift would divide by that zero length. A rule that every reader must special-
--   case is not one rule (docs/NO_SPAGHETTI.md §1).
--
-- ── WHAT THIS FILE DOES — it SUPERSEDES three deployed bodies, sliced, not retyped ─────────────
--   1. voyage.lon_lerp(float8, float8, float8) — THE longitude interpolation of a course segment.
--      IMMUTABLE, server-only. f=0 returns lon1 and f=1 returns lon2 exactly (a vertex is never
--      rewritten, ±180 included); in between, the short way, wrapped back into [−180, 180].
--   2. voyage.path_refusal — SLICED (3 hunks, occur-exactly-once): the |Δlon| > 180 refusal is
--      deleted; the sample longitude is voyage.lon_lerp; the header comment says so.
--   3. voyage.segments_from_course — SLICED (4 hunks): the piece ends and the midpoint step
--      through voyage.lon_lerp, so a piece's `a`/`b` stay in range and its sea_id/shelter are
--      asked of the water it actually crosses.
--   4. voyage.position — SLICED (2 hunks): the served lon is voyage.lon_lerp along the segment.
--   Nothing is dropped, so no ACL moves — and the grants are re-issued below anyway, then
--   asserted, because a re-cut is exactly where 0085's header says a function loses its ACL.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ───────────────────────────────────────────────────────────
--   * It does not touch public.sea_raster, public.sea_cells or public.sea_reaches. The reach
--     figures for seam-crossing pairs were measured by the same search over the same round grid
--     (Tokyo → Acapulco 6,223.5 nm, the short way) and carry only the ≤0.25° kink at the seam;
--     the next generated sea migration re-measures them with the straightener merged across it.
--   * It does not re-cut cmd.do_sail, cmd.divert, voyage.assert_paths_water or world.fleets:
--     each composes path_refusal / segments_from_course / position by name and inherits the
--     reading.
--   * It does not change how the chart is PANNED. The chart's track and drift compose the same
--     rule in the same PR (src/chart/route.ts `sheetPieces` cuts a straddling segment at ±180
--     into two pieces on the one sheet; src/chart/drift.ts steps through `lonLerp`); the
--     continuous left-to-right sheet — a wrapped copy of the world beside the seam so the two
--     pieces meet under the finger — is the next slice (docs/NAVIGATION_PLAN.md §7).
--   * It moves no water, no price, no player row, no voyage in flight: a stored path is a list
--     of pieces with their own nm, and every piece stored before this file has |Δlon| ≤ 180
--     (the old verifier refused anything else), for which the new reading is byte-identical.
--
-- Depends on: 0002 (gc_distance_nm), 0040 (sea_at), 0046 (sea_raster, path_refusal, path_nm),
-- 0047 (segments_from_course, position, sea_near), 0076/0085 (the roadsteads the control course
-- begins and ends at).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool (its own copy, by necessity — tests/duplication.spec.ts:365-380) ─────────
create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0088 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then
    execute format('drop function %s', p_fn::text);
  end if;
  execute v_def;
end $$;

-- ── 0b. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
create temporary table defs_before_0088 as
select p.oid::regprocedure::text as fn, pg_get_functiondef(p.oid) as def, coalesce(p.proacl::text, '') as acl
  from pg_proc p
 where p.oid in ('voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric)'::regprocedure,
                 'voyage.segments_from_course(jsonb)'::regprocedure,
                 'voyage.position(uuid, timestamptz)'::regprocedure);

-- ── 1. THE ONE LONGITUDE RULE ──────────────────────────────────────────────────────────────────
create or replace function voyage.lon_lerp(p_lon1 double precision, p_lon2 double precision, p_f double precision)
returns double precision
language sql
immutable
parallel safe
as $$
  -- Longitude f of the way from lon1 to lon2 THE SHORT WAY ROUND — the signed step
  -- (lon2 − lon1) brought into [−180, 180] by whole turns — and the result wrapped back into
  -- [−180, 180] by at most one turn. The endpoints are returned as given (180 stays 180, −180
  -- stays −180): a vertex is never rewritten by the function that walks between vertices.
  select case
           when p_f <= 0 then p_lon1
           when p_f >= 1 then p_lon2
           else (select case when x > 180 then x - 360 when x < -180 then x + 360 else x end
                   from (select p_lon1 + ((p_lon2 - p_lon1) - 360 * round((p_lon2 - p_lon1) / 360)) * p_f as x) s)
         end
$$;

revoke all on function voyage.lon_lerp(double precision, double precision, double precision) from public, anon, authenticated;

comment on function voyage.lon_lerp(double precision, double precision, double precision) is
  'THE longitude interpolation of a course segment (0088): the short way round the sphere, '
  'wrapped into [-180, 180], endpoints returned as given. path_refusal, segments_from_course and '
  'position step longitude through this and nothing else; the client twin is lonLerp in src/lib/geo.';

-- ── 2. THE VERIFIER reads the short way ────────────────────────────────────────────────────────
select pg_temp.recut('voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric)'::regprocedure, false,
  $h$-- A segment jumping the antimeridian the long way (|Δlon| > 180) is refused: the pathfinder
-- never emits one, and linear interpolation across it would sample water it does not cross.$h$,
  $h$-- THE SEA IS ROUND (0088): a segment whose two ends straddle the antimeridian is read the
-- SHORT way round through voyage.lon_lerp — the one longitude rule — never refused and never
-- swept the long way; the client's segmentIsWater samples it identically.$h$,
  $h$    if abs(v_lon2 - v_lon1) > 180 then
      return format('E_BAD_PATH: segment %s jumps the antimeridian the long way round', v_i);
    end if;
$h$,
  $h$$h$,
  $h$      v_lon := v_lon1 + (v_lon2 - v_lon1) * v_f;$h$,
  $h$      v_lon := voyage.lon_lerp(v_lon1, v_lon2, v_f);$h$);

-- ── 3. THE SEGMENT CUTTER steps the short way ──────────────────────────────────────────────────
select pg_temp.recut('voyage.segments_from_course(jsonb)'::regprocedure, false,
  $h$-- as it goes instead of wearing one midpoint's answer for 3,000 nm.$h$,
  $h$-- as it goes instead of wearing one midpoint's answer for 3,000 nm.
-- 0088: longitude is stepped through voyage.lon_lerp, the short way round, so a piece may
-- straddle the antimeridian and its ends and midpoint stay in [-180, 180].$h$,
  $h$alon := lon1 + (lon2 - lon1) * k / pieces;$h$,
  $h$alon := voyage.lon_lerp(lon1, lon2, k::float8 / pieces);$h$,
  $h$blon := lon1 + (lon2 - lon1) * (k + 1) / pieces;$h$,
  $h$blon := voyage.lon_lerp(lon1, lon2, (k + 1)::float8 / pieces);$h$,
  $h$mlon := (alon + blon) / 2;$h$,
  $h$mlon := voyage.lon_lerp(alon, blon, 0.5);$h$);

-- ── 4. THE POSITION is placed the short way ────────────────────────────────────────────────────
select pg_temp.recut('voyage.position(uuid, timestamptz)'::regprocedure, false,
  $h$-- sailed and the point drawn are one line.$h$,
  $h$-- sailed and the point drawn are one line. 0088: longitude through voyage.lon_lerp — the
-- short way round — so a piece that straddles the antimeridian places her on the 0.25° she
-- sails, not 359.75° away through three continents.$h$,
  $h$      lon := round(((e->'a'->>1)::numeric + ((e->'b'->>1)::numeric - (e->'a'->>1)::numeric) * leg_frac), 4);$h$,
  $h$      lon := round(voyage.lon_lerp((e->'a'->>1)::float8, (e->'b'->>1)::float8, leg_frac::float8)::numeric, 4);$h$);

-- ── 5. THE GRANTS, re-issued (a re-cut is where an ACL goes missing — 0085's header) ───────────
revoke all on function voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric) from public, anon, authenticated;
revoke all on function voyage.segments_from_course(jsonb) from public, anon, authenticated;
revoke all on function voyage.position(uuid, timestamptz) from public, anon;
grant execute on function voyage.position(uuid, timestamptz) to authenticated;

-- ── 6. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  -- Tokyo's roads → Callao's roads, as src/lib/sea/pathfind.ts proposes it over the applied
  -- raster after this change (2026-09-14; tests/sea.dateline.spec.ts re-proposes it live): ONE
  -- straight segment, every half-cell sample of which is water, straddling the seam. Before the
  -- change the same search proposed [[35.125,140.375],[36.375,179.875],[36.375,-179.875],
  -- [-12.125,-77.375]] — 8,358.4 nm with the kink — and this chain refused it.
  v_course   constant jsonb := '[[35.125,140.375],[-12.125,-77.375]]'::jsonb;
  v_tok      record;
  v_cll      record;
  v_ref      text;
  v_nm       numeric;
  v_gc       numeric;
  v_segs     jsonb;
  v_seg      jsonb;
  v_i        int;
  v_lon_a    float8;
  v_lon_b    float8;
  v_bad      int := 0;
  v_sea_n    uuid;
  v_sea_s    uuid;
  v_rows     int;
  v_land     text;
  v_short    float8;
  v_sailed   numeric;
begin
  -- (a) THE RULE ITSELF. The seam hop is 0.25° of water: its midpoint is the antimeridian, its
  --     quarter points 0.0625° either side of it, and both endpoints come back as given.
  if abs(voyage.lon_lerp(179.875, -179.875, 0.5)) <> 180
     or abs(voyage.lon_lerp(179.875, -179.875, 0.25) - 179.9375) > 1e-9
     or abs(voyage.lon_lerp(179.875, -179.875, 0.75) - (-179.9375)) > 1e-9
     or abs(voyage.lon_lerp(-179.875, 179.875, 0.25) - (-179.9375)) > 1e-9
     or voyage.lon_lerp(180, -180, 0) <> 180 or voyage.lon_lerp(180, -180, 1) <> -180
     or voyage.lon_lerp(10, 20, 0.5) <> 15
     or abs(voyage.lon_lerp(-9.625, 4.375, 0.5) - (-2.625)) > 1e-9 then
    raise exception '0088 self-assert FAIL: voyage.lon_lerp does not take the short way — 179.875→-179.875 at ½ = %, ¼ = %, ¾ = %; 10→20 at ½ = %',
      voyage.lon_lerp(179.875, -179.875, 0.5), voyage.lon_lerp(179.875, -179.875, 0.25),
      voyage.lon_lerp(179.875, -179.875, 0.75), voyage.lon_lerp(10, 20, 0.5);
  end if;

  -- (b) THE MEASURE already took the short way (haversine is periodic): 0.2° on the equator
  --     across the seam is 12 nm, not 21,000.
  v_short := voyage.gc_distance_nm(0, 179.9, 0, -179.9);
  if abs(v_short - 12.0) > 0.05 then
    raise exception '0088 self-assert FAIL: gc_distance_nm(0,179.9 → 0,-179.9) = % nm, expected ~12 (the haversine must take the short way)', v_short;
  end if;

  -- (c) THE SEA does not fall off the grid at the seam: a point at lon +179.9 and its twin at
  --     −179.9 answer the same real sea, north and south of the equator, and the Pacific is named.
  v_sea_n := voyage.sea_at(30, 179.9);
  v_sea_s := voyage.sea_at(-20, -179.9);
  if v_sea_n is null or v_sea_s is null
     or v_sea_n is distinct from voyage.sea_at(30, -179.9)
     or v_sea_s is distinct from voyage.sea_at(-20, 179.9)
     or v_sea_n is distinct from voyage.sea_at(30, 180)
     or (select s.name from public.seas s where s.id = v_sea_n) <> 'North Pacific Ocean'
     or (select s.name from public.seas s where s.id = v_sea_s) <> 'South Pacific Ocean' then
    raise exception '0088 self-assert FAIL: the sea at the seam — (30, ±179.9) = % / %, (-20, ±179.9) = % / %',
      (select s.name from public.seas s where s.id = voyage.sea_at(30, 179.9)),
      (select s.name from public.seas s where s.id = voyage.sea_at(30, -179.9)),
      (select s.name from public.seas s where s.id = voyage.sea_at(-20, 179.9)),
      (select s.name from public.seas s where s.id = voyage.sea_at(-20, -179.9));
  end if;

  -- (d) TOKYO → CALLAO CROSSES THE SOUTH PACIFIC. The control course begins at Tokyo's served
  --     roads and ends at Callao's, straddles the seam, and the verifier accepts it under exactly
  --     the figures cmd.do_sail passes for a roads-to-roads course (join = course_join_nm, head
  --     and tail = the flat 25 nm slack of 0076).
  select sr.roadstead_lat::float8 as lat, sr.roadstead_lon::float8 as lon into v_tok
    from public.sea_reaches sr where sr.code = 'TOK';
  select sr.roadstead_lat::float8 as lat, sr.roadstead_lon::float8 as lon into v_cll
    from public.sea_reaches sr where sr.code = 'CLL';
  if v_tok.lat is null or v_cll.lat is null then
    raise exception '0088 self-assert FAIL: Tokyo (TOK) or Callao (CLL) serves no roadstead';
  end if;
  v_i := 0;
  for v_seg in select * from jsonb_array_elements(v_course) loop
    if v_i > 0 and abs((v_seg->>1)::float8 - v_lon_a) > 180 then v_bad := v_bad + 1; end if;
    if abs((v_seg->>1)::float8) > 180 or abs((v_seg->>0)::float8) > 90 then
      raise exception '0088 self-assert FAIL: control course vertex % is off the sphere: %', v_i, v_seg;
    end if;
    v_lon_a := (v_seg->>1)::float8;
    v_i := v_i + 1;
  end loop;
  if v_bad <> 1 then
    raise exception '0088 self-assert FAIL: the control course straddles the seam % time(s), expected exactly 1 — it is not the course this file is about', v_bad;
  end if;
  v_ref := voyage.path_refusal(v_course, v_tok.lat::numeric, v_tok.lon::numeric, v_cll.lat::numeric, v_cll.lon::numeric,
                               public.wc_num('course_join_nm'), 25, 25);
  if v_ref is not null then
    raise exception '0088 self-assert FAIL: the Tokyo → Callao course across the seam is still refused: %', v_ref;
  end if;
  --     ITS LENGTH is the Pacific's, not the world's. TWO figures, both 0047's: voyage.path_nm
  --     sums the great-circle chord of each vertex pair (8,337.3 nm here — this course is ONE
  --     segment, so that is the arc itself), and the pieces segments_from_course cuts sum to the
  --     length of the lat/lon-STRAIGHT line she actually sails, judges and is drawn on (0047's
  --     geometry: position interpolates linearly, path_refusal samples linearly) — 8,615.2 nm,
  --     the figure cmd.do_sail gates, prices and stores as total_nm. On the short segments every
  --     pre-0088 course is made of the two agree within 0.1 %; on one 8,000-nm segment the line
  --     is 3.3 % longer than the arc. Neither is this file's to change; both are asserted in
  --     THE BAND: the great circle between the two roads is a hard floor (a polyline measured
  --     segment by segment on the sphere cannot be shorter than the arc between its ends), and
  --     1.15× that arc is the ceiling — a line-of-sight-straightened 8-connected grid path
  --     measures 2–8 % over the straight line (docs/NAVIGATION_PLAN.md §3, every pair there),
  --     while the way this course was refused into before — round the Cape or through the
  --     Indian Ocean — is ≥ 1.5× (Tokyo → Calabar, the same latitude band the long way,
  --     measured 10,876 nm against a 7,143 nm arc).
  v_nm := voyage.path_nm(v_course);
  v_gc := voyage.gc_distance_nm(v_tok.lat, v_tok.lon, v_cll.lat, v_cll.lon)::numeric;
  if v_nm < v_gc - 0.01 or v_nm > v_gc * 1.15 then
    raise exception '0088 self-assert FAIL: Tokyo → Callao measures % nm against a % nm great circle — outside [1.00, 1.15]×', round(v_nm, 1), round(v_gc, 1);
  end if;
  --     ITS PIECES stay on the sphere and every one of them has a sea: segments_from_course cuts
  --     the straddling segment into ceil(nm/500) equal-parameter pieces whose ends and midpoints
  --     step the short way. (A piece's own nm is NOT ≤ 500: 0047 divides the parameter, not the
  --     arc, and a lat/lon-linear line measures unevenly on the sphere — 450 nm off Japan, 529 nm
  --     on the equator here. That is 0047's rule, unchanged, and not this file's business.)
  v_segs := voyage.segments_from_course(v_course);
  v_bad := 0;
  for v_seg in select * from jsonb_array_elements(v_segs) loop
    v_lon_a := (v_seg->'a'->>1)::float8;
    v_lon_b := (v_seg->'b'->>1)::float8;
    if abs(v_lon_a) > 180 or abs(v_lon_b) > 180 or (v_seg->>'sea_id') is null then
      v_bad := v_bad + 1;
    end if;
  end loop;
  if v_bad <> 0 then
    raise exception '0088 self-assert FAIL: % piece(s) of the Tokyo → Callao course are off the sphere or in no sea', v_bad;
  end if;
  if jsonb_array_length(v_segs) <> ceil(v_nm / 500) then
    raise exception '0088 self-assert FAIL: the course was cut into % pieces, 0047''s rule says ceil(%/500) = %', jsonb_array_length(v_segs), round(v_nm, 1), ceil(v_nm / 500);
  end if;
  v_sailed := (select sum((s->>'nm')::numeric) from jsonb_array_elements(v_segs) s);
  if v_sailed < v_nm - 0.01 or v_sailed > v_gc * 1.15 then
    raise exception '0088 self-assert FAIL: the pieces sum to % nm — below the % nm chord or outside [1.00, 1.15]× the % nm great circle',
      round(v_sailed, 1), round(v_nm, 1), round(v_gc, 1);
  end if;
  if (select count(*) from jsonb_array_elements(v_segs) s where abs((s->'a'->>1)::float8 - (s->'b'->>1)::float8) > 180) <> 1 then
    raise exception '0088 self-assert FAIL: exactly one piece should straddle the seam';
  end if;
  if (select count(distinct s->>'sea_id') from jsonb_array_elements(v_segs) s) < 2 then
    raise exception '0088 self-assert FAIL: a course from Japan to Peru crosses only one sea';
  end if;

  -- (e) LAND IS STILL LAND — and the short-way reading is what finds it. A straddling segment
  --     across Fiji's Vanua Levu (16.375°S, 178.5°E → 178.5°W; the seam cell on that row is
  --     land in the raster, its two ends water) is refused as E_LAND, not as "the long way
  --     round" — and read the OLD way, through the Indian Ocean and the Atlantic, those two ends
  --     would have sampled 21,000 miles of water she never crossed.
  v_land := voyage.path_refusal('[[-16.375,178.5],[-16.375,-178.5]]'::jsonb,
                                -16.375, 178.5, -16.375, -178.5, 0.5, 0, 0);
  if v_land is null or v_land not like 'E_LAND:%' then
    raise exception '0088 self-assert FAIL: a straddling segment over land is not refused as E_LAND (got %)', coalesce(v_land, 'null');
  end if;
  --     And a plain overland course is still refused exactly as before.
  v_land := voyage.path_refusal('[[38.71,-9.14],[39.5,-4.5],[41.4,2.2]]'::jsonb, 38.71, -9.14, 41.4, 2.2, 1, 0, 0);
  if v_land is null or v_land not like 'E_LAND:%' then
    raise exception '0088 self-assert FAIL: Lisbon → Barcelona overland is not refused as E_LAND (got %)', coalesce(v_land, 'null');
  end if;

  -- (f) THE PRE-IMAGES: each body is the deployed one with only the declared hunks swapped in
  --     (no retyping), each ACL unmoved, and the grants read the way they did.
  for v_seg in select to_jsonb(d) from defs_before_0088 d loop
    if pg_get_functiondef((v_seg->>'fn')::regprocedure) = (v_seg->>'def') then
      raise exception '0088 self-assert FAIL: % is byte-identical to its pre-image — the slice did nothing', v_seg->>'fn';
    end if;
    if pg_get_functiondef((v_seg->>'fn')::regprocedure) not like '%voyage.lon_lerp(%' then
      raise exception '0088 self-assert FAIL: % does not step longitude through voyage.lon_lerp', v_seg->>'fn';
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = (v_seg->>'fn')::regprocedure), '') <> (v_seg->>'acl') then
      raise exception '0088 self-assert FAIL: the ACL of % moved — was [%], is now [%]', v_seg->>'fn', v_seg->>'acl',
        coalesce((select p.proacl::text from pg_proc p where p.oid = (v_seg->>'fn')::regprocedure), '');
    end if;
  end loop;
  if pg_get_functiondef('voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric)'::regprocedure) like '%long way round%'
     or pg_get_functiondef('voyage.segments_from_course(jsonb)'::regprocedure) like '%(lon2 - lon1)%'
     or pg_get_functiondef('voyage.position(uuid, timestamptz)'::regprocedure) like '%(e->''b''->>1)::numeric - (e->''a''->>1)::numeric%' then
    raise exception '0088 self-assert FAIL: an old raw-degree longitude step survives in a re-cut body';
  end if;
  if has_function_privilege('anon', 'voyage.lon_lerp(float8, float8, float8)', 'execute')
     or has_function_privilege('authenticated', 'voyage.lon_lerp(float8, float8, float8)', 'execute')
     or has_function_privilege('anon', 'voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric)', 'execute')
     or has_function_privilege('authenticated', 'voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric)', 'execute')
     or has_function_privilege('anon', 'voyage.segments_from_course(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'voyage.segments_from_course(jsonb)', 'execute')
     or has_function_privilege('anon', 'voyage.position(uuid, timestamptz)', 'execute')
     or not has_function_privilege('authenticated', 'voyage.position(uuid, timestamptz)', 'execute') then
    raise exception '0088 self-assert FAIL: the grants on lon_lerp / path_refusal / segments_from_course / position are not as 0046/0047 left them';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception '0088 self-assert FAIL: the grant lockdown does not read zero on both halves';
  end if;
  select count(*) into v_rows from jsonb_array_elements(v_segs);

  raise notice '0088 self-assert ok: THE SEA IS ROUND. voyage.lon_lerp takes the short way (179.875→-179.875 at ½ is the antimeridian); gc_distance_nm across the seam is % nm for 0.2°; the sea at (30, ±179.9) is the North Pacific and at (-20, ±179.9) the South Pacific; Tokyo''s roads → Callao''s roads across the seam is ACCEPTED by path_refusal; its chord measures % nm against a % nm great circle (×%) and the % pieces she sails sum to % nm (×%), every one in [-180, 180] with a sea; a straddling segment over Fiji is refused E_LAND and Lisbon → Barcelona overland still is; path_refusal / segments_from_course / position are their pre-images with only the declared hunks swapped in, ACLs unmoved; 0 client write grants, 0 client-executable writers.',
    round(v_short::numeric, 2), round(v_nm, 1), round(v_gc, 1), round(v_nm / v_gc, 3), v_rows, round(v_sailed, 1), round(v_sailed / v_gc, 3);
end $$;

drop table if exists defs_before_0088;
