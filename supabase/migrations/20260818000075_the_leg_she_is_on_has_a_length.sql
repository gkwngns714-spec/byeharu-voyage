-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0075 — THE LEG SHE IS ON HAS A LENGTH, AND THE MAP IS TOLD IT
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, docs/OWNER_REQUESTS.md row 50: *"i need a real timer in map, telling me how long
-- i've been on the sea, my provision depleting as the time goes, and my ship marker should be
-- updated more frequently"*.
--
-- This is the THIRD of that row's three parts and, like 0063 before it, it is one field wide.
--
-- ── WHAT WAS MEASURED, ON PRODUCTION, BEFORE ANY OF THIS WAS WRITTEN ───────────────────────────
-- A fleet was put to sea on the live game and her marker's screen position was sampled every
-- 600 ms for the whole passage. She moved SIX times in twenty seconds and stood perfectly still
-- in between:
--
--     0.0s 304,323 | 1.2s 267,332 | 2.1s 267,332 | 3.2s 267,332 | 4.1s 292,341 | 5.1s 292,341
--     6.2s 292,341 | 7.1s 255,350 | 8.1s 255,350 | 9.2s 255,350 | 10.1s 218,359 | ...
--
-- Three seconds frozen, then a jump of 25-68 px. That is the read cadence made visible
-- (AppShell.readIntervalMs, 3 000 ms at compression 9600) and it is exactly the owner's
-- complaint: she teleports, and never once looks like she is sailing.
--
-- ── WHY A SERVER CHANGE AT ALL, WHEN THE FIX IS A DRAWING ──────────────────────────────────────
-- The constraint the ledger sets on this part is absolute and correct: *"the voyage is settled by
-- a FROZEN speed profile and the read is the catch-up, so a faster marker must be a finer
-- INTERPOLATION of the same authority, never a second mover."*
--
-- voyage.position (0047:504) places her LINEARLY in lat/lon along the segment her progress falls
-- in, and voyage.course_of (0047:315) serves that path's vertices in order — so course[i] is
-- segment i's a and course[i+1] is its b. A client that walks leg_frac from 0 to 1 between those
-- two points reproduces the server's own arithmetic exactly, digit for digit.
--
-- What it cannot do is turn a few more nautical miles into a few more leg_frac, because THE
-- LENGTH OF THE SEGMENT IS NOT ON THE WIRE. voyage.position computes v_nm (0047:520) and returns
-- everything but. voyage.course_of drops every nm and keeps only the vertices.
--
-- The client could measure the leg itself — haversineNm sits unused in src/lib/geo for exactly
-- the reason it is unused. A second measurement of a course the server has already measured is a
-- second mover by definition: the two numbers need not agree, and the disagreement compounds
-- along the passage. So the number is SERVED, off the frozen path itself, and the client does no
-- geometry at all.
--
-- ── WHY IT IS THE PATH AND NOT A NEW RETURN COLUMN ─────────────────────────────────────────────
-- Adding seg_nm to voyage.position's `returns table` is a signature change: drop and recreate,
-- with world.fleets() and voyage.path_refusal both calling it. This reads the SAME frozen row the
-- same function reads — v.path -> pos.seg_index ->> 'nm', the element voyage.depart (0047:453)
-- wrote and nothing ever rewrites — and adds one key beside the object it already serves. No
-- signature moves, no function is dropped, and the number cannot disagree with the one
-- voyage.position used, because it IS that one.
--
-- ── WHY A SLICE AND NOT A REWRITE ──────────────────────────────────────────────────────────────
-- world.fleets() is 0009's, re-cut by 0017, 0028, 0047, 0055, 0063 and 0074. Retyping it to add
-- one key is how a body drifts from the one that is deployed. So the deployed definition is read
-- back with pg_get_functiondef, ONE hunk is replaced, and the helper refuses unless that hunk
-- occurs exactly once. The anchor is the line 0063 itself left behind; 0074 re-cut a different
-- hunk (the ships array) and did not touch it.
--
-- ── WHAT THIS DOES NOT DO ──────────────────────────────────────────────────────────────────────
-- It does not move her. voyage.position is untouched, voyage.progress_nm is untouched, the speed
-- profile is untouched, and the read cadence is untouched. The server's answer to "where is she"
-- is the same answer it gave before this file. This adds one measurement the server had already
-- made and was throwing away.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── THE SLICER. Same helper 0063 used, same law: a hunk that is not unique is a failed apply. ──
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
      raise exception '0075 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
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

-- ── PRE-IMAGE. "Nothing else moved" is a comparison, never a sentence (NO_SPAGHETTI §3.3). ─────
create temporary table defs_before_0075 as
  select 'world.fleets'::text as fn,
         pg_get_functiondef('world.fleets()'::regprocedure) as def,
         (select p.proacl::text from pg_proc p where p.oid = 'world.fleets()'::regprocedure) as acl;

-- ── 1. THE POSITION CARRIES THE LENGTH OF ITS OWN LEG — SUPERSEDES 0063's position hunk ───────
select pg_temp.recut('world.fleets()'::regprocedure, false,
  $do$                 'position', (select to_jsonb(pos) from voyage.position(v.id) pos))$do$,
  $dn$                 -- 0075: HOW LONG THE LEG IS. voyage.position places her linearly between
                 -- course[seg_index] and course[seg_index+1]; without the leg's own nm the
                 -- client can read that point but cannot advance it, so the marker can only
                 -- teleport once per read. Read off the FROZEN path (voyage.depart wrote it and
                 -- nothing rewrites it), which is the same element voyage.position measured, so
                 -- the two numbers cannot disagree. Null for a voyage whose path has no such
                 -- element, which is a state the client already draws (it just does not drift).
                 'position', (select to_jsonb(pos) || jsonb_build_object(
                     'seg_nm', (v.path -> pos.seg_index ->> 'nm')::numeric)
                   from voyage.position(v.id) pos))$dn$);

-- An assumed grant is how a read wall came down in 0018 and had to be rebuilt in 0023. Re-issued
-- explicitly, and asserted unmoved below.
revoke all on function world.fleets() from public, anon;
grant execute on function world.fleets() to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe   constant uuid := '00000000-0075-4000-8000-000000000001';
  -- THE SAME Lisbon -> Cadiz COURSE 0047 PROVES IS WATER (0047:1221) and 0063 re-used: a course
  -- typed fresh here would be a second fixture that could drift off the raster the law walks.
  c_course  constant jsonb := '[[38.71,-9.14],[36.875,-9.125],[36.625,-8.875],[36.53,-6.3]]'::jsonb;
  v_player  uuid;
  v_fleet   uuid;
  v_before  text;
  v_after   text;
  v_acl_b   text;
  v_acl_a   text;
  v_payload jsonb;
  v_pos     jsonb;
  v_seg     int;
  v_served  numeric;
  v_row     numeric;
  v_frac    numeric;
  v_lat     numeric;
  v_a       numeric;
  v_b       numeric;
  v_sum     numeric;
  v_total   numeric;
  v_grants  int;
  v_res     jsonb;
begin
  select def, acl into v_before, v_acl_b from defs_before_0075 where fn = 'world.fleets';
  v_after := pg_get_functiondef('world.fleets()'::regprocedure);
  select p.proacl::text into v_acl_a from pg_proc p where p.oid = 'world.fleets()'::regprocedure;

  -- (a) POSITIVE CONTROL — the field really was absent, so this file really added something.
  if position('seg_nm' in v_before) <> 0 then
    raise exception '0075 self-assert FAIL: the pre-image already served seg_nm — this file changes nothing and the slice is a no-op';
  end if;
  if position('seg_nm' in v_after) = 0 then
    raise exception '0075 self-assert FAIL: the re-cut body does not serve seg_nm';
  end if;

  -- (b) NOTHING ELSE MOVED — the new body IS the old one with exactly this hunk swapped in.
  if replace(v_after,
       $x$                 -- 0075: HOW LONG THE LEG IS. voyage.position places her linearly between
                 -- course[seg_index] and course[seg_index+1]; without the leg's own nm the
                 -- client can read that point but cannot advance it, so the marker can only
                 -- teleport once per read. Read off the FROZEN path (voyage.depart wrote it and
                 -- nothing rewrites it), which is the same element voyage.position measured, so
                 -- the two numbers cannot disagree. Null for a voyage whose path has no such
                 -- element, which is a state the client already draws (it just does not drift).
                 'position', (select to_jsonb(pos) || jsonb_build_object(
                     'seg_nm', (v.path -> pos.seg_index ->> 'nm')::numeric)
                   from voyage.position(v.id) pos))$x$,
       $y$                 'position', (select to_jsonb(pos) from voyage.position(v.id) pos))$y$)
     <> v_before then
    raise exception '0075 self-assert FAIL: the re-cut body is not its own pre-image with exactly the declared hunk swapped in';
  end if;

  -- (c) THE GRANTS ARE THE ONES IT HAD.
  if v_acl_a is distinct from v_acl_b then
    raise exception '0075 self-assert FAIL: world.fleets grants moved (% -> %)', v_acl_b, v_acl_a;
  end if;

  -- (d) A REAL HOUSE, A REAL VOYAGE, AND THE SERVED LEG IS THE FROZEN PATH'S OWN.
  begin
    v_player := public.new_house(c_probe, 'Casa da Milha', 'PRT');
    perform cmd.assume_identity(c_probe);
    select id into v_fleet from public.fleets where player_id = v_player;

    -- Pinned for the reason 0037 and 0063 pin it: a hazard drawn on this passage would delay her
    -- and this probe would be measuring the dice rather than the arithmetic.
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';

    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
    -- A REFUSAL IS AN ENVELOPE, NOT AN EXCEPTION (0008).
    v_res := cmd.issue(v_fleet, 'SAIL TO CAD', null, c_course);
    if coalesce(v_res->>'ok', 'false') <> 'true' then
      raise exception '0075 self-assert FAIL: the probe could not put to sea: [%: %]',
        v_res->>'error_code', v_res->>'error_message';
    end if;
    perform cmd.advance(v_fleet);

    select f into v_payload from jsonb_array_elements(world.fleets()) f
     where (f->>'id')::uuid = v_fleet;
    v_pos := v_payload->'voyage'->'position';
    if v_pos is null then
      raise exception '0075 self-assert FAIL: the probe never put a voyage to sea, so this proves nothing';
    end if;

    v_seg    := (v_pos->>'seg_index')::int;
    v_served := (v_pos->>'seg_nm')::numeric;
    if v_served is null then
      raise exception '0075 self-assert FAIL: world.fleets() served no seg_nm for a fleet at sea';
    end if;
    if v_served <= 0 then
      raise exception '0075 self-assert FAIL: the served leg is % nm — a segment of no length cannot be walked', v_served;
    end if;

    -- IT IS THE ROW'S OWN NUMBER, not a re-measurement: read the frozen path directly.
    select (path -> v_seg ->> 'nm')::numeric,
           (path -> v_seg -> 'a' ->> 0)::numeric,
           (path -> v_seg -> 'b' ->> 0)::numeric,
           round(total_nm, 4)
      into v_row, v_a, v_b, v_total
      from public.voyages where fleet_id = v_fleet and status = 'SAILING';
    if v_row is distinct from v_served then
      raise exception '0075 self-assert FAIL: served leg % is not the frozen path''s % for segment %',
        v_served, v_row, v_seg;
    end if;

    -- AND THE LEG IS THE ONE THE POINT WAS PLACED ON. The whole licence the client has to draw
    -- between reads is that voyage.position interpolated LINEARLY between exactly those two
    -- vertices; re-derive its latitude from the served frac and require the same digits.
    v_frac := (v_pos->>'leg_frac')::numeric;
    v_lat  := (v_pos->>'lat')::numeric;
    if round(v_a + (v_b - v_a) * v_frac, 4) <> v_lat then
      raise exception '0075 self-assert FAIL: the served point (lat %) is not the linear placement of leg_frac % between % and % — the client may not drift along a line the server did not use',
        v_lat, v_frac, v_a, v_b;
    end if;

    -- AND THE LEGS SUM TO THE VOYAGE. If seg_nm came from anywhere but this path, this catches it.
    --
    -- WITHIN A TENTH OF A MILE, and the tolerance is measured rather than guessed: this assertion
    -- was first written as equality and failed on its own first apply at 253.6900 against 253.7000.
    -- That gap is not a defect and finding it is the reason the probe exists — `voyage.depart`
    -- stores each leg's `nm` and the voyage's `total_nm` at DIFFERENT precisions, so summing the
    -- parts cannot reproduce the whole to the last digit. 0.05 nm is under a hundredth of the
    -- shortest leg this world sails and two orders below anything a marker could show, and it is
    -- still tight enough that a `seg_nm` taken from another path — another voyage, another
    -- segment, a client re-measurement — could not slip under it.
    select round(sum((e->>'nm')::numeric), 4) into v_sum
      from public.voyages vv, jsonb_array_elements(vv.path) e
     where vv.fleet_id = v_fleet and vv.status = 'SAILING';
    if v_sum is null or abs(v_sum - v_total) > 0.05 then
      raise exception '0075 self-assert FAIL: the legs of the frozen path sum to % but total_nm is % — further apart than the stored rounding can explain', v_sum, v_total;
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  -- (e) POSTURE UNMOVED.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0075 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0075 self-assert ok: world.fleets() serves the length of the leg she is on — proven on a real house put to sea, equal to the frozen path''s own nm for that very segment, positive (a zero-length leg cannot be walked), and the served point re-derived as the linear placement of the served leg_frac between that leg''s two vertices to four decimals, which is the whole licence the client has to draw between reads; the legs sum to total_nm; the pre-image did NOT carry the field (positive control) and the re-cut body is that pre-image with exactly the one declared hunk swapped in, byte for byte; grants byte-identical; 0 client write grants. NOTHING MOVES HER: voyage.position, voyage.progress_nm, the speed profile and the read cadence are all untouched.';
end $$;
