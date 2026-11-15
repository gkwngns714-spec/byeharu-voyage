// The SQL of migration 0441, as scripts/build-isthmus.mjs fills it in. A template only: the generator
// owns every number in it.

const PR = 'voyage.path_refusal(jsonb,numeric,numeric,numeric,numeric,numeric,numeric,numeric)'
const GUARD = 'voyage.assert_paths_water()'

/** The hunks of voyage.path_refusal, shared by the migration, the prod check and the forward rollback. */
export const HUNKS = [
  {
    fn: PR,
    old:
      "-- is the line sailed. Samples inside the head/tail allowance of the path's FIRST/LAST point are\n" +
      '-- exempt: a harbour sits ON the coast and its cell is usually land at this resolution; the\n' +
      '-- allowance is the MEASURED snap of that harbour (sea_reaches.snap_nm), never a fixed guess.\n',
    new:
      '-- is the line sailed.\n' +
      '-- 0441 AN APPROACH IS THE LAND AN END STANDS IN, AND NOTHING ELSE. Until 0441 every sample inside the\n' +
      '-- head/tail allowance was skipped unread, whatever it was: two roadsteads 46 nm apart across the\n' +
      '-- isthmus of Panama, 25 nm each, and the straight line between them had no sample left to read. Now\n' +
      '-- a land sample is passed only when the STATED end (p_from / p_to) itself lies in a land cell (a fleet\n' +
      '-- on a clipped corner of the coast; never a roadstead, which is water) and the sample is in the\n' +
      '-- UNBROKEN run of land that begins at that end, inside its allowance. Once she has reached water any\n' +
      '-- land is refused, wherever it is; and a course with no water sample between two land ends (the two\n' +
      "-- approaches chained) is refused. The client's segmentIsWater and courseRefusedAt read it identically.\n",
  },
  {
    fn: PR,
    old: '  v_total  float8;\nbegin\n',
    new:
      '  v_total  float8;\n' +
      '  v_at        float8;            -- 0441: nm from the first point of the course to this sample\n' +
      '  v_head_open boolean;           -- 0441: the origin stands on land and she has not yet reached water\n' +
      '  v_tail_open boolean;           -- 0441: the destination stands on land\n' +
      "  v_tail_run  text := null;      -- 0441: the refusal held for land that may be the destination's own approach\n" +
      'begin\n',
  },
  {
    fn: PR,
    old:
      '  -- Sample every segment. v_done tracks nm already walked, so the head/tail allowances are\n' +
      "  -- against the whole path's ends, exactly as the client's own straightener applies them.\n" +
      '  for v_i in 0 .. v_n - 2 loop\n' +
      '    v_lat1 := (p_path->v_i->>0)::float8;     v_lon1 := (p_path->v_i->>1)::float8;\n' +
      '    v_lat2 := (p_path->(v_i+1)->>0)::float8; v_lon2 := (p_path->(v_i+1)->>1)::float8;\n' +
      '    v_nm := voyage.gc_distance_nm(v_lat1, v_lon1, v_lat2, v_lon2)::float8;\n' +
      '    v_step := greatest(2, ceil(v_nm / 7.50)::int);\n' +
      '    for v_s in 1 .. v_step - 1 loop\n' +
      '      v_f := v_s::float8 / v_step;\n' +
      "      -- exempt only the measured approaches at the path's own two ends\n" +
      '      continue when v_done + v_f * v_nm < p_head_nm;\n' +
      '      continue when v_total - (v_done + v_f * v_nm) < p_tail_nm;\n' +
      '      v_lat := v_lat1 + (v_lat2 - v_lat1) * v_f;\n' +
      '      v_lon := voyage.lon_lerp(v_lon1, v_lon2, v_f);\n' +
      '      v_row := least(719, greatest(0, floor((90 - v_lat) / 0.25)::int));\n' +
      '      v_col := ((floor((v_lon + 180) / 0.25)::int % 1440) + 1440) % 1440;\n' +
      '      if get_bit(r.cells, (v_row * 1440 + v_col) * r.bits_per_cell) = 0 then\n' +
      "        return format('E_LAND: the course touches land near %s°, %s° (segment %s)',\n" +
      '                      round(v_lat::numeric, 2), round(v_lon::numeric, 2), v_i);\n' +
      '      end if;\n' +
      '    end loop;\n' +
      '    v_done := v_done + v_nm;\n' +
      '  end loop;\n' +
      '  return null;\n',
    new:
      '  -- 0441: an end has an approach only when the place she lies at, or is bound for, is itself land.\n' +
      '  v_row := least(719, greatest(0, floor((90 - p_from_lat::float8) / 0.25)::int));\n' +
      '  v_col := ((floor((p_from_lon::float8 + 180) / 0.25)::int % 1440) + 1440) % 1440;\n' +
      '  v_head_open := coalesce(p_head_nm, 0) > 0 and get_bit(r.cells, (v_row * 1440 + v_col) * r.bits_per_cell) = 0;\n' +
      '  v_row := least(719, greatest(0, floor((90 - p_to_lat::float8) / 0.25)::int));\n' +
      '  v_col := ((floor((p_to_lon::float8 + 180) / 0.25)::int % 1440) + 1440) % 1440;\n' +
      '  v_tail_open := coalesce(p_tail_nm, 0) > 0 and get_bit(r.cells, (v_row * 1440 + v_col) * r.bits_per_cell) = 0;\n' +
      '\n' +
      '  -- Sample every segment. v_done tracks nm already walked, so the head/tail allowances are\n' +
      "  -- against the whole path's ends, exactly as the client's own straightener applies them.\n" +
      '  for v_i in 0 .. v_n - 2 loop\n' +
      '    v_lat1 := (p_path->v_i->>0)::float8;     v_lon1 := (p_path->v_i->>1)::float8;\n' +
      '    v_lat2 := (p_path->(v_i+1)->>0)::float8; v_lon2 := (p_path->(v_i+1)->>1)::float8;\n' +
      '    v_nm := voyage.gc_distance_nm(v_lat1, v_lon1, v_lat2, v_lon2)::float8;\n' +
      '    v_step := greatest(2, ceil(v_nm / 7.50)::int);\n' +
      '    for v_s in 1 .. v_step - 1 loop\n' +
      '      v_f := v_s::float8 / v_step;\n' +
      '      v_at := v_done + v_f * v_nm;\n' +
      '      v_lat := v_lat1 + (v_lat2 - v_lat1) * v_f;\n' +
      '      v_lon := voyage.lon_lerp(v_lon1, v_lon2, v_f);\n' +
      '      v_row := least(719, greatest(0, floor((90 - v_lat) / 0.25)::int));\n' +
      '      v_col := ((floor((v_lon + 180) / 0.25)::int % 1440) + 1440) % 1440;\n' +
      '      if get_bit(r.cells, (v_row * 1440 + v_col) * r.bits_per_cell) = 1 then\n' +
      "        -- 0441 water: she has put to sea. Land behind her that was held as the destination's approach was not one.\n" +
      '        if v_tail_run is not null then\n' +
      '          return v_tail_run;\n' +
      '        end if;\n' +
      '        v_head_open := false;\n' +
      '        continue;\n' +
      '      end if;\n' +
      '      -- 0441 land: passed only as the unbroken run from an end that stands on land, inside its allowance\n' +
      '      continue when v_head_open and v_at < p_head_nm;\n' +
      '      if v_tail_open and v_total - v_at < p_tail_nm then\n' +
      "        v_tail_run := coalesce(v_tail_run, format('E_LAND: the course touches land near %s°, %s° (segment %s)',\n" +
      '                                                  round(v_lat::numeric, 2), round(v_lon::numeric, 2), v_i));\n' +
      '        continue;\n' +
      '      end if;\n' +
      "      return format('E_LAND: the course touches land near %s°, %s° (segment %s)',\n" +
      '                    round(v_lat::numeric, 2), round(v_lon::numeric, 2), v_i);\n' +
      '    end loop;\n' +
      '    v_done := v_done + v_nm;\n' +
      '  end loop;\n' +
      '  -- 0441: both ends on land and no water between them. Two approaches chained are a crossing.\n' +
      '  if v_head_open and v_tail_open then\n' +
      "    return format('E_LAND: the course touches land near %s°, %s° (segment %s)',\n" +
      '                  round((p_path->0->>0)::numeric, 2), round((p_path->0->>1)::numeric, 2), 0);\n' +
      '  end if;\n' +
      '  return null;\n',
  },
]

/** The land guard's hunk: its new text takes the instant the migration applies (format %L), as 0076's did. */
export const CUTOFF_HUNK = {
  fn: GUARD,
  old: '    v_course := voyage.course_of(v.path);\n',
  new:
    '    -- 0441 AN APPROACH IS NOT A CANAL. A voyage that departed before this instant was admitted with 25 nm of\n' +
    '    -- each end unread (0076); the rule reads them now. She is counted with the legacy paths and skipped,\n' +
    '    -- never silently: her course is history, and every course ordered since is walked.\n' +
    '    if v.departed_at < %L::timestamptz then\n' +
    '      n_legacy := n_legacy + 1;\n' +
    '      continue;\n' +
    '    end if;\n' +
    '    v_course := voyage.course_of(v.path);\n',
}

export function migrationSql(x) {
  const p = x.prodCounts
  return `-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0441 — AN APPROACH IS NOT A CANAL (owner row 352, 2026-11-15)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- GENERATED by scripts/build-isthmus.mjs (template scripts/isthmus.sql.mjs) from a world image of the
-- applied chain and production's own courses. Do not hand-edit: re-run the generator and cut a NEW migration.
--
-- THE OWNER: no ship crosses land, ever, and it must not happen again.
--
-- ── WHAT WAS LEFT AFTER 0440 ────────────────────────────────────────────────────────────────────
-- Panama City and Portobelo. Their roadsteads lie ${x.canalNm} nm apart across the isthmus. voyage.path_refusal
-- skipped every sample within the head allowance of a course's first point and the tail allowance of its
-- last, unread, and cmd.do_sail grants 25 nm at each (0076). 25 + 25 covers ${x.canalNm}: the straight line had
-- no sample left to read, the server accepted it, and the browser's search offered it. A Panama canal.
-- The same rule let ANY course run over raster land within 25 nm of either end: a spit, a cape, the
-- neck of a peninsula beside a harbour. Measured on this world (scripts/db/audit-land-crossings.mjs
-- --allowance): the straight line between two roadsteads was accepted for 1,668 harbour pairs, 161 of
-- them only because of the allowance, and 92 of those run over more than 2 nm of drawn land.
--
-- ── THE RULE NOW (voyage.path_refusal, three hunks, each once and reversing) ────────────────────
-- AN APPROACH IS THE LAND AN END STANDS IN, AND NOTHING ELSE. A land sample is passed only when
--   * the stated end (where she lies, or where she is bound) is itself in a land cell, and
--   * the sample is in the unbroken run of land that begins at that end, inside its allowance.
-- Once she has reached water, any land is refused, wherever it is. A course with no water sample
-- between two land ends (two approaches chained) is refused. So:
--   * a harbour is reached from its ROADSTEAD, and all ${x.harbours} roadsteads are raster water (the generator
--     refuses to run otherwise; proof 143 holds it): a course between two harbours has NO unread sample;
--   * a fleet lying on a clipped corner of the coast (her own cell is land: voyage.water_snap_nm > 0)
--     still leaves it, in one run, inside her measured snap + 25 nm, as before;
--   * a quay inside a bay is reached as before: its roadstead is water, and the way to it is water.
-- cmd.do_sail is not touched: the 25 it passes is now the LIMIT of an approach from a land end, and is
-- inert at a water end. The signature, grants, volatility and owner of voyage.path_refusal do not move.
-- voyage.assert_paths_water (the land guard, one hunk): a voyage that departed before this file applied
-- was admitted under the old allowance; it is counted with the legacy paths and skipped, as 0076
-- grandfathered the quay-to-quay voyages. Every voyage ordered from now on is walked by the new rule.
-- The browser: src/lib/sea/pathfind.ts segmentIsWater and src/lib/sea/refine.ts courseRefusedAt read the
-- same rule, so the search itself goes by sea (Panama City to Portobelo: ${x.bySeaNm.toLocaleString('en-US')} nm round the Horn).
--
-- ── WHAT IS RE-SAILED ───────────────────────────────────────────────────────────────────────────
-- Every stored course the new rule refuses (a merchant sent down such a lane would be refused E_LAND at
-- cmd.do_sail), and every stored course over drawn land (routes saved since 0440 by a browser tab that
-- had not reloaded). ${x.texts} distinct courses read (the chain's world${p ? ` and production's export of ${p.at}` : ''});
-- ${x.why.refused + x.why.both} refused by the new rule (${x.why.both} of them also over drawn land), ${x.why.land} over drawn land only;
-- ${x.fixes.length} entries (${x.fixes.filter((f) => f.backwards).length} are a replaced course read backwards, 0440's rule), ${x.fresh} from a fresh search; ${x.longer}% longer.
-- Each new course is water by the NEW rule and by the OLD one, and is off the drawn land.
--   the chain's world: lanes ${x.lanes} of ${x.npc}, route stops ${x.stops} of ${x.routes}, coast courses ${x.coast} of ${x.coasts}.${p ? `
--   production at the export: lanes ${p.lanes} of ${p.npc}, route stops ${p.stops} of ${p.routes}, coast courses ${p.coast}.` : ''}
--   A cargo circuit's and a navy patrol's frozen legs are pieces of lanes: each is re-cut from the replaced lanes
--   (scripts/ops/harness/isthmus/prod-shaped.mjs applied this file to production's own lanes, stops and legs).
-- Matched by md5(course::text), as 0440. Voyages already sailing finish their course.
--
-- ── NOT HERE (listed) ───────────────────────────────────────────────────────────────────────────
--   * The server still holds no coast mask: a hand-made course over an island the 0.25-degree raster cannot
--     see is accepted (the browser's course author re-sails every course; the daily prod audit lists any).
--   * course_join_nm (15 nm): a course may still begin that far from where she lies.
--   * The distance the quay quotes (public.sea_reaches.reaches) is not measured again (as 0440 left it). The search's
--     course changes with the rule for ${x.reach ? x.reach.pairs.toLocaleString('en-US') : 'some'} of the 35,775 harbour pairs (a cell of land clipped beside a harbour is
--     now sailed round)${x.reach ? `: ${x.reach.ruleMeanNm} nm longer on average, ${x.reach.ruleOver} of them by more than half a per cent` : ''}. A new figure re-prices
--     the market rows that hold a haul (world.haul_rows): its own slice, the owner's to order.
--
-- Depends on: 0046 (voyage.path_refusal), 0076 (voyage.assert_paths_water's body, roadsteads), 0088, 0164
-- (path_refusal's live body), 0440 (the roadsteads on the water, the courses, npc_course_zones_memo).
-- No table is created, no knob moves, no cron job changes.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. THE RULE: the hunks, each once and reversing ─────────────────────────────────────────────
do $$
declare
  c_pr    constant text := '${PR}';
  c_guard constant text := '${GUARD}';
  c_fns   constant text[] := array[c_pr, c_guard];
  h      record;
  v_pre  text;
  v_def  text;
  v_n    int;
  v_others text;
  v_canal jsonb;
  v_a    record;
  v_b    record;
begin
  -- THE CONTROL, BEFORE: the straight line from Panama City's roads to Portobelo's is accepted (the fault).
  select sr.roadstead_lat as lat, sr.roadstead_lon as lon into v_a from public.sea_reaches sr join public.ports p on p.id = sr.port_id where p.code = 'PAN';
  select sr.roadstead_lat as lat, sr.roadstead_lon as lon into v_b from public.sea_reaches sr join public.ports p on p.id = sr.port_id where p.code = 'PRT';
  v_canal := jsonb_build_array(jsonb_build_array(v_a.lat, v_a.lon), jsonb_build_array(v_b.lat, v_b.lon));
  if voyage.path_refusal(v_canal, v_a.lat, v_a.lon, v_b.lat, v_b.lon, ${x.joinNm}, 25, 25) is not null then
    raise exception '0441 self-assert FAIL: the Panama control was already refused before the rule changed (%): it proves nothing',
      voyage.path_refusal(v_canal, v_a.lat, v_a.lon, v_b.lat, v_b.lon, ${x.joinNm}, 25, 25);
  end if;

  create temp table hunk_0441 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0441 values
${HUNKS.map((h, i) => `  (${i + 1}, c_pr,\n$h$${h.old}$h$,\n$h$${h.new}$h$)`).join(',\n')},
  -- the land guard's cut-off: the instant THIS FILE APPLIED, written in (0076's way)
  (${HUNKS.length + 1}, c_guard,
$h$${CUTOFF_HUNK.old}$h$,
format($h$${CUTOFF_HUNK.new}$h$, now()::text));
  create temp table pre_0441 on commit drop as
  select f as fn, replace(pg_get_functiondef(f::regprocedure), E'\\r', '') as def,
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure) as meta
    from unnest(c_fns) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_others
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and not exists (select 1 from unnest(c_fns) f where f::regprocedure = p.oid);
  for h in select * from hunk_0441 order by ord loop
    v_pre := replace(pg_get_functiondef(h.fn::regprocedure), E'\\r', '');
    v_n := (length(v_pre) - length(replace(v_pre, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0441 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_pre, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0441 self-assert FAIL: hunk % is not in the new body of % once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0441 p where p.fn = h.fn) then
      raise exception '0441 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0441 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\\r', '');
    for v_n in select x.ord from hunk_0441 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, (select x.new from hunk_0441 x where x.ord = v_n), (select x.old from hunk_0441 x where x.ord = v_n));
    end loop;
    if v_def <> h.def then
      raise exception '0441 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_fns) f where f::regprocedure = p.oid)) <> v_others then
    raise exception '0441 self-assert FAIL: another function moved';
  end if;

  -- THE CONTROL, AFTER: the same line is land.
  if voyage.path_refusal(v_canal, v_a.lat, v_a.lon, v_b.lat, v_b.lon, ${x.joinNm}, 25, 25) is distinct from
     voyage.path_refusal(v_canal, v_a.lat, v_a.lon, v_b.lat, v_b.lon, ${x.joinNm}, 0, 0)
     or voyage.path_refusal(v_canal, v_a.lat, v_a.lon, v_b.lat, v_b.lon, ${x.joinNm}, 25, 25) not like 'E_LAND:%' then
    raise exception '0441 self-assert FAIL: the straight line from Panama City to Portobelo is not refused as land: %',
      coalesce(voyage.path_refusal(v_canal, v_a.lat, v_a.lon, v_b.lat, v_b.lon, ${x.joinNm}, 25, 25), 'accepted');
  end if;
end
$$;

-- ── 2. THE COURSES: the md5 of the old course's text, and the new course ────────────────────────
create function pg_temp.fix_0441() returns table (old_md5 text, course jsonb) language sql immutable as $fix$
  select v.old_md5, v.course::jsonb from (values
${x.fixes.map((f) => `    ('${f.old}', '${f.course}')`).join(',\n')}
  ) as v(old_md5, course)
$fix$;

create function pg_temp.rev_0441(p jsonb) returns jsonb language sql immutable as $r$
  select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(p) with ordinality t(x, i)
$r$;

create function pg_temp.nm_0441(p jsonb) returns numeric language sql stable as $n$
  select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(p)) x
$n$;

-- How cmd.do_sail judges a course between two harbours' roads: joined at its own ends, 25 nm at each.
create function pg_temp.law_0441(p jsonb) returns text language sql stable as $l$
  select voyage.path_refusal(p, (p -> 0 ->> 0)::numeric, (p -> 0 ->> 1)::numeric, (p -> -1 ->> 0)::numeric, (p -> -1 ->> 1)::numeric, ${x.joinNm}, 25, 25)
$l$;

-- THE ONE STEP (0440's, for this list): every row that holds a replaced course takes the new one; a cargo circuit's
-- and a navy patrol's frozen pieces of a replaced lane or coast course are re-cut, either way round.
create function pg_temp.clear_0441() returns jsonb language plpgsql as $c$
declare
  v_lanes int;
  v_stops int;
  v_coast int;
  v_legs  int := 0;
  v_patrol int := 0;
  v_memo  int;
  l       record;
  v_in    jsonb;
  v_out   jsonb;
  v_n     int;
  v_i     int;
  v_hit   record;
  v_moved boolean;
begin
  create temp table recut_0441 on commit drop as
  select distinct on (x.old) ((x.old -> 0 -> 'a')::text || (x.old -> 0 -> 'b')::text) as head, x.old, x.new, jsonb_array_length(x.old) as n
    from (select voyage.segments_from_course(q.c) as old, voyage.segments_from_course(q.n) as new
            from (select c.course as c, f.course as n
                    from (select course from public.npc_courses union select course from public.npc_coast_courses) c
                    join pg_temp.fix_0441() f on md5(c.course::text) = f.old_md5
                  union all
                  select pg_temp.rev_0441(c.course), pg_temp.rev_0441(f.course)
                    from (select course from public.npc_courses union select course from public.npc_coast_courses) c
                    join pg_temp.fix_0441() f on md5(c.course::text) = f.old_md5) q) x
   order by x.old;
  create index on recut_0441 (head);
  -- ONE PASS, LEFT TO RIGHT: at each piece of a leg, the LONGEST replaced lane whose pieces the leg holds there,
  -- piece for piece (by their ends), is swapped for its new pieces, and the walk goes on past it.
  for l in select 'cargo' as k, g.circuit_id as id, g.ord, g.segments as s from public.cargo_circuit_legs g
           union all
           select 'patrol', n.station_id, n.ord, n.segments from public.navy_patrol_legs n loop
    v_in := l.s;
    v_n := jsonb_array_length(v_in);
    v_out := '[]'::jsonb;
    v_i := 0;
    v_moved := false;
    while v_i < v_n loop
      select r.new, r.n into v_hit
        from recut_0441 r
       where r.head = (v_in -> v_i -> 'a')::text || (v_in -> v_i -> 'b')::text
         and r.n <= v_n - v_i
         and not exists (select 1 from generate_series(0, r.n - 1) k
                          where (r.old -> k -> 'a') is distinct from (v_in -> (v_i + k) -> 'a')
                             or (r.old -> k -> 'b') is distinct from (v_in -> (v_i + k) -> 'b'))
       order by r.n desc
       limit 1;
      if found then
        v_out := v_out || v_hit.new;
        v_i := v_i + v_hit.n;
        v_moved := true;
      else
        v_out := v_out || jsonb_build_array(v_in -> v_i);
        v_i := v_i + 1;
      end if;
    end loop;
    if v_moved and v_out is distinct from v_in then
      if l.k = 'cargo' then
        update public.cargo_circuit_legs g
           set segments = v_out, nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(v_out) x)
         where g.circuit_id = l.id and g.ord = l.ord;
        v_legs := v_legs + 1;
      else
        update public.navy_patrol_legs n
           set segments = v_out, nm = (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(v_out) x)
         where n.station_id = l.id and n.ord = l.ord;
        v_patrol := v_patrol + 1;
      end if;
    end if;
  end loop;
  drop table recut_0441;

  update public.npc_courses c set course = f.course, nm = pg_temp.nm_0441(f.course)
    from pg_temp.fix_0441() f where md5(c.course::text) = f.old_md5;
  get diagnostics v_lanes = row_count;

  update public.npc_coast_courses c set course = f.course, nm = pg_temp.nm_0441(f.course)
    from pg_temp.fix_0441() f where md5(c.course::text) = f.old_md5;
  get diagnostics v_coast = row_count;

  update public.standing_route_stops s set course = f.course, course_nm = pg_temp.nm_0441(f.course)
    from pg_temp.fix_0441() f where md5(s.course::text) = f.old_md5;
  get diagnostics v_stops = row_count;

  insert into public.npc_course_zones_memo (course_md5, zones)
  select distinct on (k.h) k.h, k.zones
    from (select md5(f.course::text) as h, public.course_zones(f.course) as zones from pg_temp.fix_0441() f
          union all
          select md5(pg_temp.rev_0441(f.course)::text), public.course_zones(f.course) from pg_temp.fix_0441() f) k
   order by k.h
  on conflict (course_md5) do nothing;
  get diagnostics v_memo = row_count;

  return jsonb_build_object('lanes', v_lanes, 'stops', v_stops, 'coast', v_coast, 'cargo_legs', v_legs, 'patrol_legs', v_patrol, 'memo', v_memo);
end
$c$;

-- ── 3. SELF-ASSERT, on properties, with a probe that is rolled back ────────────────────────────
do $$
declare
  v_bad   text;
  v_old   jsonb;
  v_new   jsonb;
  v_old2  jsonb;
  v_new2  jsonb;
  v_nat   uuid;
  v_circ  bigint;
  v_station bigint;
  v_port  uuid;
  v_got   jsonb;
  v_want  jsonb;
  v_res   jsonb;
  v_ref   text;
  q       record;
begin
  -- (a) NO ROADSTEAD HAS AN APPROACH: every one lies in a raster water cell (so the 25 nm is inert at a harbour).
  select string_agg(p.code, ' ') into v_bad
    from public.sea_reaches sr join public.ports p on p.id = sr.port_id, public.sea_raster s
   where s.id = 1
     and get_bit(s.cells, (least(s.rows - 1, greatest(0, floor((90 - sr.roadstead_lat) / s.cell_deg)::int)) * s.cols
                          + ((floor((sr.roadstead_lon + 180) / s.cell_deg)::int % s.cols) + s.cols) % s.cols) * s.bits_per_cell) <> 1;
  if v_bad is not null then
    raise exception '0441 self-assert FAIL: roadstead(s) in a raster land cell: %', v_bad;
  end if;

  -- (b) THE CHAIN: a line that lies wholly on the land between two land ends (inland Castile, 18 nm, well inside
  --     25 + 25) is refused. Before 0441 it had no sample read at all.
  v_ref := voyage.path_refusal('[[40.0, -4.0], [40.3, -4.0]]'::jsonb, 40.0, -4.0, 40.3, -4.0, 1, 25, 25);
  if v_ref is null or v_ref not like 'E_LAND:%' then
    raise exception '0441 self-assert FAIL: a course that never reaches water is accepted (%)', coalesce(v_ref, 'accepted');
  end if;

  -- (c) AN ALLOWANCE AT A WATER END IS INERT. For every harbour that lies off its quay: the line from her roads
  --     (water) to the quay (land), judged with 25 nm at the roads and with none, has the same answer.
  for q in
    select p.code, p.lat, p.lon, sr.roadstead_lat as rlat, sr.roadstead_lon as rlon, sr.snap_nm
      from public.sea_reaches sr join public.ports p on p.id = sr.port_id
     where p.kind = 'HARBOUR' and sr.snap_nm > 0
  loop
    v_old := jsonb_build_array(jsonb_build_array(q.rlat, q.rlon), jsonb_build_array(q.lat, q.lon));
    v_ref := voyage.path_refusal(v_old, q.rlat, q.rlon, q.lat, q.lon, 1, 25, q.snap_nm + 25);
    if voyage.path_refusal(v_old, q.rlat, q.rlon, q.lat, q.lon, 1, 0, q.snap_nm + 25) is distinct from v_ref then
      raise exception '0441 self-assert FAIL: %: an allowance at a water end changed the answer', q.code;
    end if;
  end loop;
  -- AN END ON THE LAND STILL LEAVES IT, by name: Lisbon's quay is in a land cell and its roadstead is the nearest
  -- water. Quay to roads is accepted as her approach (her measured snap + 25, as cmd.do_sail grants a fleet's own
  -- position), and refused when the approach is taken away.
  select p.lat, p.lon, sr.roadstead_lat as rlat, sr.roadstead_lon as rlon, sr.snap_nm into q
    from public.sea_reaches sr join public.ports p on p.id = sr.port_id where p.code = 'LIS';
  if q.snap_nm > 7.5 then
    v_old := jsonb_build_array(jsonb_build_array(q.lat, q.lon), jsonb_build_array(q.rlat, q.rlon));
    if voyage.path_refusal(v_old, q.lat, q.lon, q.rlat, q.rlon, 1, q.snap_nm + 25, 25) is not null then
      raise exception '0441 self-assert FAIL: a quay on the land no longer reaches its own roadstead: %',
        voyage.path_refusal(v_old, q.lat, q.lon, q.rlat, q.rlon, 1, q.snap_nm + 25, 25);
    end if;
    if voyage.path_refusal(v_old, q.lat, q.lon, q.rlat, q.rlon, 1, 0, 0) is null then
      raise exception '0441 self-assert FAIL: the Lisbon approach control crosses no land: it proves nothing';
    end if;
  end if;

  -- (d) THE SERVER'S LAW: every new course is water by the new rule, as cmd.do_sail judges a roads-to-roads course.
  select string_agg(f.old_md5 || ': ' || pg_temp.law_0441(f.course), '; ') into v_bad
    from pg_temp.fix_0441() f where pg_temp.law_0441(f.course) is not null;
  if v_bad is not null then
    raise exception '0441 self-assert FAIL: a re-sailed course is refused by voyage.path_refusal: %', left(v_bad, 2000);
  end if;

  -- (e) THE PROBE: a cargo circuit of its own whose one leg is two replaced lanes, the second read backwards.
  --     After the step its leg must be exactly the two new lanes' pieces. Rolled back whole.
  begin
    select c.course, f.course into v_old, v_new
      from public.npc_courses c join pg_temp.fix_0441() f on md5(c.course::text) = f.old_md5 order by f.old_md5 limit 1;
    select c.course, f.course into v_old2, v_new2
      from public.npc_courses c join pg_temp.fix_0441() f on md5(c.course::text) = f.old_md5 order by f.old_md5 desc limit 1;
    if v_old is not null then
      v_nat := (select g.nation_id from public.great_powers g order by g.nation_id limit 1);
      v_port := (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1);
      insert into public.cargo_circuits (nation_id, start_port) values (v_nat, v_port) returning id into v_circ;
      insert into public.cargo_circuit_legs (circuit_id, ord, to_port, nm, segments)
      values (v_circ, 1, v_port, 1, voyage.segments_from_course(v_old) || voyage.segments_from_course(pg_temp.rev_0441(v_old2)));
      v_station := (select x.id from public.navy_stations x order by x.id limit 1);
      if v_station is not null then
        insert into public.navy_patrol_legs (station_id, ord, to_port, nm, segments)
        values (v_station, 9999, v_port, 1, voyage.segments_from_course(v_old) || voyage.segments_from_course(pg_temp.rev_0441(v_old2)));
      end if;
      v_res := pg_temp.clear_0441();
      v_got := (select g.segments from public.cargo_circuit_legs g where g.circuit_id = v_circ and g.ord = 1);
      v_want := voyage.segments_from_course(v_new) || voyage.segments_from_course(pg_temp.rev_0441(v_new2));
      if v_got is distinct from v_want then
        raise exception '0441 self-assert FAIL: the probe cargo leg was not re-cut to the new lanes (% pieces, % wanted)',
          jsonb_array_length(v_got), jsonb_array_length(v_want);
      end if;
      if v_station is not null and (select n.segments from public.navy_patrol_legs n where n.station_id = v_station and n.ord = 9999) is distinct from v_want then
        raise exception '0441 self-assert FAIL: the probe patrol leg was not re-cut to the new lanes';
      end if;
    end if;
    raise exception using errcode = 'ZX441', message = coalesce(v_res, '{}'::jsonb)::text;
  exception when sqlstate 'ZX441' then
    raise notice '0441 probe (rolled back): %', sqlerrm;
  end;
end
$$;

-- ── 4. THE STEP, for real; then the law over every lane the merchants sail ─────────────────────
do $$
declare
  v_res jsonb := pg_temp.clear_0441();
  v_bad text;
begin
  -- Lanes and coast courses are seeded only by migrations (no function of the world writes them), so this reads
  -- no row the live world can add: a lane the rule refuses would stop its merchants at cmd.do_sail.
  select string_agg(a.code || '->' || b.code, ' ') into v_bad
    from (select from_port, to_port, course from public.npc_courses union all select from_port, to_port, course from public.npc_coast_courses) c
    join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port
   where pg_temp.law_0441(c.course) is not null;
  if v_bad is not null then
    raise exception '0441 self-assert FAIL: lane(s) the new rule refuses, not on this file''s list (export prod again and re-run scripts/build-isthmus.mjs): %', left(v_bad, 2000);
  end if;
  raise notice '0441 self-assert ok: AN APPROACH IS NOT A CANAL. Panama City to Portobelo: accepted before, E_LAND after; a course that never reaches water is refused; no roadstead has an approach; a quay on the land still reaches its roads; ${x.fixes.length} course(s) on the list, every one water by the new rule; every lane and coast course is water by it; the probe legs re-cut and rolled back. Rewritten: %', v_res;
end
$$;
`
}
