-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0166 — THE CHART IS UNROLLED ONCE A READING  (the arrivals sweep, step 3 — nothing it decides moves)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- Prod, cron.job_run_details, byeharu-voyage:arrivals (every 15 s, budget 10 s), 2026-10-17 (read-only):
--   hour (UTC)   06–14     15     16     17     18     19     20     21 (after 0160–0163)
--   avg s        2.5–2.8   2.75   3.19   3.97   3.97   4.45   4.43   5.0–6.0
--   laps started 735–795   767    963    1136   1257   1377   1403   (≈ 1,500 / h pace)
--   routes/hour  314–352   320    407    497    543    614    645
-- The line moved with the LOAD, not with a per-arrival cost: 0150 (stuck laps answered) and 0152 (wrecks
-- towed) put twice as many merchants back to sea. Per closed stop the sweep spent 0.36 s before and
-- 0.26–0.29 s after; a regression of each run's time on what it did (1,296 runs since 15:30, r² 0.68):
-- ≈ 0.76 s a run + 0.012 s an arrival + 0.0106 s a sea-day + 0.38 s a lap start — the lap-start figure
-- the same as before 15:00 (0.42–0.46 s, 5,450 runs since 2026-10-16 22:00). The K / S lookups added
-- today are small per call (prod, read-only, 200 merchant fleets): world.ship_stats 0.44 ms,
-- public.crew_pct 0.45 ms, fleet_wage 0.30 ms, day_delay_for 0.06 ms, storm_hull_lost 0.44 ms.
--
-- WHERE A RUN'S TIME GOES (a merchants-on PGlite world, one sweep with track_functions = 'all':
-- 200 fleets, 1,755 sea-days, 185 departures, 23.3 s): voyage.segments_from_course 5.6 s self and
-- voyage.path_refusal 2.7 s self — 36 % of the sweep, ONE call each per departure (cmd.do_sail).
-- On prod, read-only, over 100 merchant stop courses: segments_from_course 107 ms a call,
-- path_refusal 43 ms a call — 150 ms of chart reading for every SAIL, ~13 departures a run (≈ 2 s of
-- a ~5 s run). THE CAUSE: both read the sea raster into a record (`select * into r from
-- public.sea_raster`) and probe it with get_bit(r.cells, …). public.sea_raster.cells is 259,200 bytes
-- stored COMPRESSED (pg_column_size 14,684), and a compressed value in a PL/pgSQL record stays
-- compressed — so EVERY get_bit decompresses the whole chart. Measured on prod: 1,000 get_bit on the
-- column 152 ms; on the same bytes unrolled once (`cells || ''::bytea`) 2.5 ms. A course reads
-- hundreds of cells (segments: up to 7 rings around every piece's midpoint; path_refusal: a sample
-- every 7.5 nm). voyage.water_roadstead (cmd.do_sail asks it twice, via voyage.water_snap_nm) reads
-- the same way.
--
-- ── WHAT THIS FILE DOES (one hunk in each of three bodies; every answer is the pre-image — asserted)
-- voyage.segments_from_course(jsonb), voyage.path_refusal(jsonb, 7 × numeric) and
-- voyage.water_roadstead(numeric, numeric): right after the raster is read, the chart is unrolled
-- ONCE into the record (`r.cells := r.cells || ''::bytea;` — the same bytes, uncompressed), so every
-- get_bit after it reads memory. The bits are the bits: no rule, no sampling step, no ring, no
-- allowance moves.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Change the table, its storage, the raster, any rule, knob, refusal text, ACL or entry point. Cache
-- anything across calls. Touch cmd.do_sail, the hazard roll, voyage.settle or the lap planner.
--
-- ── THE PROOF (all in this file; old and new on the SAME snapshot, as text) ────────────────────
-- §1 keeps the three pre-images under pg_temp names (they call nothing that changes). §3 compares:
--   * segments_from_course on a sample of production's live merchant stop courses (md5-spread, the
--     longest, the ones at the antimeridian) and on courses of this file's own (inland, antimeridian,
--     an open-ocean crossing that splits, polar water, one point, zero length) — a course that RAISES
--     (inland: voyage.sea_near finds no sea) is compared by its sqlstate and message;
--   * path_refusal on the same courses, joined at their own ends with no allowance and with a 30 nm
--     one, and the refusal branches on this file's own inputs (not an array, a bad point, off the
--     sphere, off course at either end, no length);
--   * water_roadstead at every port and on a world grid (land, sea, the 999 of no water near).
-- A difference RAISES. Each comparison must also be non-vacuous (both refusals and passes, more than
-- one shelter class, roadsteads at 0, > 0 and 999). Timings (old vs new, same inputs): raise notice
-- only — prod runs on burstable CPU; the speed verdict is cron.job_run_details after the push.
--
-- ── WHAT IT BUYS ────────────────────────────────────────────────────────────────────────────────
-- EXPECTED on prod (not measurable before the push): ~150 ms → a few ms per departure; at today's
-- ~3,100 departures an hour ≈ 450 s of the sweep's ~1,100 s an hour, i.e. arrivals avg ≈ 4.9 s → ≈ 3 s.
-- The client's SAIL preview and route saves read the same bodies and get the same cut.
--
-- ── LOCKS, AND HOW LONG THE PUSH TAKES ──────────────────────────────────────────────────────────
-- ACCESS SHARE on what it reads; CREATE OR REPLACE FUNCTION; pg_temp objects. Nothing is written to a
-- table. No LOCK TABLE, no set role, no set local, no begin. ESTIMATED on prod: 25–40 s, almost all of
-- it the OLD bodies on the sample (≈ 150 ms a course). Deploy with the clock unwound (DEPLOY_RUNBOOK).
--
-- ROLLBACK: a forward migration putting the three pre-image bodies back (the hunk's OLD text is here
-- verbatim; the self-assert proves each live body reverses to its pre-image).
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0163, LF-normalised), each asserted to
-- occur exactly once: voyage.segments_from_course (0088), voyage.path_refusal (0088),
-- voyage.water_roadstead (0085).
-- VERSION: 0166 (provisional; renumbered to head + 1 at deploy). Applies on prod head 0163.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0166(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0166 on commit drop as
select f.fn, f.tmp,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proparallel from pg_proc p where p.oid = f.fn::regprocedure) as par,
       (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = f.fn::regprocedure) as lang,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('voyage.segments_from_course(jsonb)', 'voyage.segments_from_course(', 'pg_temp.voyage_segments_from_course_0166('),
               ('voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric)',
                'voyage.path_refusal(', 'pg_temp.voyage_path_refusal_0166('),
               ('voyage.water_roadstead(numeric, numeric)', 'voyage.water_roadstead(', 'pg_temp.voyage_water_roadstead_0166('))
       f(fn, name, tmp);

create temp table before_0166 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points;

-- THE OLD COPIES. None of the three calls another (water_snap_nm calls water_roadstead; nothing here
-- calls water_snap_nm), and nothing they call changes.
do $$
declare
  d     record;
  v_def text;
  v_n   int;
begin
  if (select count(*) from defs_before_0166 where def is not null) <> 3 then
    raise exception '0166 self-assert FAIL: % of the 3 bodies found', (select count(*) from defs_before_0166 where def is not null);
  end if;
  for d in select * from defs_before_0166 order by fn loop
    v_def := d.def;
    v_n := pg_temp.occurs_0166(v_def, 'CREATE OR REPLACE FUNCTION ' || split_part(d.fn, '(', 1) || '(');
    if v_n <> 1 then
      raise exception '0166 self-assert FAIL: the header of % occurs % time(s)', d.fn, v_n;
    end if;
    v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION ' || split_part(d.fn, '(', 1) || '(',
                     'CREATE OR REPLACE FUNCTION ' || split_part(d.tmp, '(', 1) || '(');
    if strpos(v_def, 'voyage.segments_from_course(') > 0 or strpos(v_def, 'voyage.path_refusal(') > 0
       or strpos(v_def, 'voyage.water_roadstead(') > 0 then
      raise exception '0166 self-assert FAIL: the old copy of % still calls a changed body', d.fn;
    end if;
    execute v_def;
  end loop;
  select count(*) into v_n from pg_proc where pronamespace = pg_my_temp_schema()
     and proname in ('voyage_segments_from_course_0166', 'voyage_path_refusal_0166', 'voyage_water_roadstead_0166');
  if v_n <> 3 then
    raise exception '0166 self-assert FAIL: % old cop(ies) made, not 3', v_n;
  end if;
end $$;

-- ── 2. THE RE-CUTS (one hunk each: old = verbatim from the live bodies; new = what replaces it) ──
create temp table hunks_0166 (fn text, old text, new text) on commit drop;
insert into hunks_0166
select fn,
$h$  select * into r from public.sea_raster where id = 1;
$h$,
$h$  select * into r from public.sea_raster where id = 1;
  -- 0166: THE CHART UNROLLED ONCE. sea_raster.cells is stored compressed, and a compressed value kept in
  -- a record is decompressed again by every get_bit (259,200 bytes a probe: 0.15 ms on prod). The same
  -- bytes, uncompressed, read once here — every get_bit below reads memory. The bits are the bits.
  r.cells := r.cells || ''::bytea;
$h$
  from defs_before_0166;

do $$
declare
  d     record;
  h     record;
  v_def text;
  v_n   int;
begin
  for d in select * from defs_before_0166 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0166 where fn = d.fn loop
      v_n := pg_temp.occurs_0166(v_def, h.old);
      if v_n <> 1 then
        raise exception '0166 self-assert FAIL: the hunk of % occurs % time(s), not once — the live body is not what this file was cut against',
          d.fn, v_n;
      end if;
      -- it must come before the first probe of the chart
      if strpos(v_def, h.old) > strpos(v_def, 'get_bit(r.cells') then
        raise exception '0166 self-assert FAIL: % probes the chart before it reads it', d.fn;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 3. THE COMPARISONS — old and new side by side, as text ────────────────────────────────────
-- the courses: production's live merchant stop courses (a spread, the longest, the antimeridian ones)
create temp table courses_0166 (k text, course jsonb) on commit drop;
insert into courses_0166
select 'live:md5', c.course
  from (select distinct s.course from public.standing_route_stops s
         where s.course is not null and jsonb_typeof(s.course) = 'array' and jsonb_array_length(s.course) >= 2) c
 order by md5(c.course::text) limit 80;
insert into courses_0166
select 'live:long', c.course
  from (select distinct s.course from public.standing_route_stops s
         where s.course is not null and jsonb_typeof(s.course) = 'array' and jsonb_array_length(s.course) >= 2) c
 order by voyage.path_nm(c.course) desc, md5(c.course::text) limit 8;
insert into courses_0166
select 'live:antimeridian', c.course
  from (select distinct s.course from public.standing_route_stops s
         where s.course is not null and jsonb_typeof(s.course) = 'array' and jsonb_array_length(s.course) >= 2
           and exists (select 1 from jsonb_array_elements(s.course) e where abs((e->>1)::numeric) > 170)) c
 order by md5(c.course::text) limit 6;
-- this file's own: inland (Lisbon → Madrid), across the antimeridian (Fiji), an open-Atlantic crossing
-- that splits into pieces, polar water, one point, zero length
insert into courses_0166 values
  ('own:inland',       '[[38.72, -9.14], [40.42, -3.70]]'),
  ('own:antimeridian', '[[-17.7, 178.0], [-17.5, -179.0], [-16.0, -175.0]]'),
  ('own:ocean',        '[[36.0, -30.0], [30.0, -60.0], [25.0, -75.0]]'),
  ('own:polar',        '[[70.0, -10.0], [75.0, 20.0]]'),
  ('own:one_point',    '[[36.0, -30.0]]'),
  ('own:zero_length',  '[[36.0, -30.0], [36.0, -30.0]]');

-- a course may RAISE (an inland one: voyage.sea_near finds no sea) — the refusal is an answer too
create or replace function pg_temp.segs_try_0166(p_course jsonb, p_old boolean)
returns jsonb
language plpgsql
as $$
begin
  if p_old then
    return pg_temp.voyage_segments_from_course_0166(p_course);
  end if;
  return voyage.segments_from_course(p_course);
exception when others then
  return jsonb_build_object('raised', sqlstate, 'message', sqlerrm);
end $$;

create temp table segs_0166 on commit drop as
select c.k, c.course, pg_temp.segs_try_0166(c.course, false) as new_v, pg_temp.segs_try_0166(c.course, true) as old_v
  from courses_0166 c;

-- path_refusal: every course joined at its own ends (no allowance, and a 30 nm one); the refusal
-- branches on this file's own inputs
create temp table refusal_args_0166 (k text, p jsonb, flat numeric, flon numeric, tlat numeric, tlon numeric,
                                     j numeric, hd numeric, tl numeric) on commit drop;
insert into refusal_args_0166
select c.k || x.tag, c.course, (c.course->0->>0)::numeric, (c.course->0->>1)::numeric,
       (c.course->-1->>0)::numeric, (c.course->-1->>1)::numeric, 5, x.allow, x.allow
  from courses_0166 c cross join (values (':bare', 0::numeric), (':allow30', 30::numeric)) x(tag, allow);
insert into refusal_args_0166 values
  ('own:not_array',    '{"a": 1}',                            0, 0, 0, 0, 5, 0, 0),
  ('own:bad_point',    '[[36.0, -30.0], [36.0]]',             36, -30, 36, -30, 5, 0, 0),
  ('own:off_sphere',   '[[36.0, -30.0], [95.0, -30.0]]',      36, -30, 95, -30, 5, 0, 0),
  ('own:off_start',    '[[36.0, -30.0], [30.0, -60.0]]',      38, -30, 30, -60, 5, 0, 0),
  ('own:off_end',      '[[36.0, -30.0], [30.0, -60.0]]',      36, -30, 32, -60, 5, 0, 0),
  ('own:no_length',    '[[36.0, -30.0], [36.0, -30.0]]',      36, -30, 36, -30, 5, 0, 0);

create temp table refusals_0166 on commit drop as
select a.k, voyage.path_refusal(a.p, a.flat, a.flon, a.tlat, a.tlon, a.j, a.hd, a.tl) as new_v,
       pg_temp.voyage_path_refusal_0166(a.p, a.flat, a.flon, a.tlat, a.tlon, a.j, a.hd, a.tl) as old_v
  from refusal_args_0166 a;

-- water_roadstead: every port, and a world grid (sea, coast, deep inland: the 999 of no water near)
create temp table points_0166 (k text, lat numeric, lon numeric) on commit drop;
insert into points_0166 select 'port:' || p.code, p.lat, p.lon from public.ports p where p.lat is not null and p.lon is not null;
insert into points_0166 select 'grid', la, lo from generate_series(-60, 70, 20) la cross join generate_series(-180, 150, 30) lo;
insert into points_0166 values ('own:central_africa', 0, 22), ('own:lisbon', 38.72, -9.14);

create temp table roads_0166 on commit drop as
select p.k, (select coalesce(jsonb_agg(to_jsonb(w)), '[]'::jsonb) from voyage.water_roadstead(p.lat, p.lon) w) as new_v,
       (select coalesce(jsonb_agg(to_jsonb(w)), '[]'::jsonb) from pg_temp.voyage_water_roadstead_0166(p.lat, p.lon) w) as old_v
  from points_0166 p;

create temp table proven_0166 (k text primary key, v text) on commit drop;
do $$
declare
  v_n    int;
  v_bad  int;
  v_ex   text;
  v_live int;
  v_segs int;
  v_kinds int;
begin
  -- (a) segments
  select count(*), count(*) filter (where new_v::text is distinct from old_v::text),
         min(k) filter (where new_v::text is distinct from old_v::text)
    into v_n, v_bad, v_ex from segs_0166;
  if v_bad > 0 then
    raise exception '0166 self-assert FAIL: segments_from_course — % of % courses differ from the pre-image (e.g. %)', v_bad, v_n, v_ex;
  end if;
  select count(*) filter (where k like 'live:%' and jsonb_typeof(new_v) = 'array'), sum(jsonb_array_length(new_v)) filter (where jsonb_typeof(new_v) = 'array') into v_live, v_segs from segs_0166;
  select count(distinct e->>'hazard_mult') into v_kinds from segs_0166 s
   cross join lateral jsonb_array_elements(case when jsonb_typeof(s.new_v) = 'array' then s.new_v else '[]'::jsonb end) e;
  if v_live < 1 or v_segs < 10 or v_kinds < 2 then
    raise exception '0166 self-assert FAIL: the segments comparison is vacuous (% live course(s), % segment(s), % shelter class(es))', v_live, v_segs, v_kinds;
  end if;
  insert into proven_0166 values ('segs', format('%s courses (%s live merchant stop courses; %s segments, %s shelter classes) = the pre-image as text',
    v_n, v_live, v_segs, v_kinds));

  -- (b) refusals
  select count(*), count(*) filter (where new_v is distinct from old_v), min(k) filter (where new_v is distinct from old_v)
    into v_n, v_bad, v_ex from refusals_0166;
  if v_bad > 0 then
    raise exception '0166 self-assert FAIL: path_refusal — % of % calls differ from the pre-image (e.g. %)', v_bad, v_n, v_ex;
  end if;
  if (select count(*) from refusals_0166 where new_v is null) < 1
     or (select count(*) from refusals_0166 where new_v like 'E_LAND:%') < 1
     or (select count(distinct split_part(new_v, ':', 1)) from refusals_0166 where new_v is not null) < 3 then
    raise exception '0166 self-assert FAIL: the path_refusal comparison is vacuous (% pass, % land, % code(s))',
      (select count(*) from refusals_0166 where new_v is null), (select count(*) from refusals_0166 where new_v like 'E_LAND:%'),
      (select count(distinct split_part(new_v, ':', 1)) from refusals_0166 where new_v is not null);
  end if;
  insert into proven_0166 values ('refusals', format('%s calls (%s legal water, %s E_LAND, codes %s) = the pre-image',
    v_n, (select count(*) from refusals_0166 where new_v is null), (select count(*) from refusals_0166 where new_v like 'E_LAND:%'),
    (select string_agg(distinct split_part(new_v, ':', 1), ' ') from refusals_0166 where new_v is not null)));

  -- (c) roadsteads
  select count(*), count(*) filter (where new_v::text is distinct from old_v::text), min(k) filter (where new_v::text is distinct from old_v::text)
    into v_n, v_bad, v_ex from roads_0166;
  if v_bad > 0 then
    raise exception '0166 self-assert FAIL: water_roadstead — % of % points differ from the pre-image (e.g. %)', v_bad, v_n, v_ex;
  end if;
  if (select count(*) from roads_0166 where (new_v->0->>'nm')::numeric = 0) < 1
     or (select count(*) from roads_0166 where (new_v->0->>'nm')::numeric > 0 and (new_v->0->>'nm')::numeric < 999) < 1
     or (select count(*) from roads_0166 where (new_v->0->>'nm')::numeric = 999) < 1 then
    raise exception '0166 self-assert FAIL: the roadstead comparison is vacuous (none at 0, between, or 999)';
  end if;
  insert into proven_0166 values ('roads', format('%s points (%s ports; %s on water, %s searched, %s with no water near) = the pre-image as text',
    v_n, (select count(*) from roads_0166 where k like 'port:%'),
    (select count(*) from roads_0166 where (new_v->0->>'nm')::numeric = 0),
    (select count(*) from roads_0166 where (new_v->0->>'nm')::numeric > 0 and (new_v->0->>'nm')::numeric < 999),
    (select count(*) from roads_0166 where (new_v->0->>'nm')::numeric = 999)));
end $$;

-- ── 4. THE TIMING — REPORTED, NOT GATED (old vs new, the live merchant courses, one pass each) ──
create temp table timing_0166 (what text, n int, old_ms numeric, new_ms numeric) on commit drop;
do $$
declare
  v_t0  timestamptz;
  v_old numeric;
  v_new numeric;
  v_n   int;
begin
  select count(*) into v_n from courses_0166 where k like 'live:%';
  v_t0 := clock_timestamp();
  perform count(pg_temp.voyage_segments_from_course_0166(course)::text) from courses_0166 where k like 'live:%';
  v_old := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  perform count(voyage.segments_from_course(course)::text) from courses_0166 where k like 'live:%';
  v_new := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  insert into timing_0166 values ('segments_from_course', v_n, v_old, v_new);
  select count(*) into v_n from refusal_args_0166 where k like 'live:%:bare';
  v_t0 := clock_timestamp();
  perform count(coalesce(pg_temp.voyage_path_refusal_0166(p, flat, flon, tlat, tlon, j, hd, tl), '')) from refusal_args_0166 where k like 'live:%:bare';
  v_old := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  perform count(coalesce(voyage.path_refusal(p, flat, flon, tlat, tlon, j, hd, tl), '')) from refusal_args_0166 where k like 'live:%:bare';
  v_new := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  insert into timing_0166 values ('path_refusal', v_n, v_old, v_new);
  select count(*) into v_n from points_0166 where k like 'port:%';
  v_t0 := clock_timestamp();
  perform count(w.nm) from points_0166 p cross join lateral pg_temp.voyage_water_roadstead_0166(p.lat, p.lon) w where p.k like 'port:%';
  v_old := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  perform count(w.nm) from points_0166 p cross join lateral voyage.water_roadstead(p.lat, p.lon) w where p.k like 'port:%';
  v_new := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  insert into timing_0166 values ('water_roadstead', v_n, v_old, v_new);
end $$;

-- ── 5. SELF-ASSERT (catalogue reads) ─────────────────────────────────────────────────────────────
do $$
declare
  d      record;
  h      record;
  v_def  text;
  v_back text;
  v_rev  int := 0;
  v_tim  text;
  p      record;
begin
  -- every body moved by its one hunk and reverses to its pre-image; ACL, owner, language, volatility,
  -- definer, config and parallel safety unmoved
  for d in select * from defs_before_0166 order by fn loop
    v_def  := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0166 where fn = d.fn loop
      if pg_temp.occurs_0166(v_back, h.new) <> 1 then
        raise exception '0166 self-assert FAIL: the hunk of % is not in the live body once', d.fn;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back is distinct from d.def then
      raise exception '0166 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    -- the chart is read once and unrolled before any probe
    if pg_temp.occurs_0166(v_def, 'from public.sea_raster') <> 1
       or strpos(v_def, 'r.cells := r.cells || ''''::bytea;') = 0
       or strpos(v_def, 'r.cells := r.cells || ''''::bytea;') > strpos(v_def, 'get_bit(r.cells') then
      raise exception '0166 self-assert FAIL: % does not unroll the chart once before probing it', d.fn;
    end if;
    v_rev := v_rev + 1;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, pr.proowner as owner,
           coalesce(pr.proconfig::text, '') as cfg, pr.proparallel as par, l.lanname as lang
      into p from pg_proc pr join pg_language l on l.oid = pr.prolang where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.par <> d.par
       or p.lang <> d.lang or p.owner <> d.owner then
      raise exception '0166 self-assert FAIL: % changed its ACL, owner, volatility, definer, config, parallel safety or language', d.fn;
    end if;
  end loop;
  if v_rev <> 3 then
    raise exception '0166 self-assert FAIL: % bodies checked, not 3', v_rev;
  end if;
  -- no other body reads the chart's bits (one reading each, all three cut here)
  if (select count(*) from pg_proc pr where pr.pronamespace <> pg_my_temp_schema()
         and strpos(pr.prosrc, 'get_bit(r.cells') > 0
         and pr.oid not in (select fn::regprocedure from defs_before_0166)) > 0 then
    raise exception '0166 self-assert FAIL: another body probes the chart: %',
      (select string_agg(pr.oid::regprocedure::text, ', ') from pg_proc pr where pr.pronamespace <> pg_my_temp_schema()
         and strpos(pr.prosrc, 'get_bit(r.cells') > 0 and pr.oid not in (select fn::regprocedure from defs_before_0166));
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0166) then
    raise exception '0166 self-assert FAIL: the client entry points moved (% → %)',
      (select entry_points from before_0166), (select count(*) from public.client_rpc_entry_points());
  end if;

  select string_agg(format('%s ×%s %s ms → %s ms (−%s%%)', what, n, old_ms, new_ms,
                           round(100 * (1 - new_ms / greatest(old_ms, 0.1)))), '; ' order by what)
    into v_tim from timing_0166;

  raise notice '0166 self-assert ok: THE CHART IS UNROLLED ONCE A READING — nothing the sweep decides moved. SAME ANSWERS (old vs new, as text): SEGMENTS %; REFUSALS %; ROADSTEADS %. TIMING (reported, not gated — old vs new, the same inputs, one pass): %. BODIES: segments_from_course, path_refusal and water_roadstead each read sea_raster once and unroll its cells once before any get_bit; 3 bodies reverse to their pre-images, ACL / owner / volatility / definer / config unmoved; no other body probes the chart; no new entry point.',
    (select v from proven_0166 where k = 'segs'), (select v from proven_0166 where k = 'refusals'),
    (select v from proven_0166 where k = 'roads'), v_tim;
end $$;
