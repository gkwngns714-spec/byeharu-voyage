-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 135 - THE CITY PEOPLE CHART TELLS THE RIGHT TIME  (migration 0434)
--
--   0413 made the population's step population_slot_seconds long (3,000 s in this world), counted on from the clock's anchor; the Stats city
--   reader world.stats_city_people still dated a step slot x 600 (0305). On the world's own writer (public.population_tick), rolled back by
--   proof.mjs's transaction. EVERY MARKER FAILS ON THE 0305 BODY: past the anchor, slot x 600 counts back to a slot far below the step's own.
--
-- @pass CP_STEP_DATED   two real steps (now, and one step later): each point's `at` counts back, through the writer's own counter
--                        (public.clock_count), to the slot the writer stamped; the step that holds now() is dated inside the last step
-- @pass CP_STEP_LENGTH  neighbouring steps stand population_slot_seconds apart (not 600): the two steps after now's always, and now's step and
--                        the next too, unless now's step is the one 0413's seam stretched (a world built inside the last step: main's
--                        from-zero run, 2026-11-24), whose length is the seam's own (the anchor's epoch + one step - its true start)
-- @pass CP_BEFORE_SEAM  a step logged before the clock's anchor is still dated by the length there was (it counts back to its own slot,
--                        before the anchor's instant)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_lon   uuid;
  v_len   numeric := public.wc_num('population_slot_seconds');
  v_anc   jsonb := (select wc.value -> 'population_slot' from public.world_config wc where wc.key = 'market_clock_anchor');
  v_s1    bigint;
  v_s2    bigint;
  v_s3    bigint;
  v_c     timestamptz;
  v_want  numeric;
  v_old   bigint;
  v_r     jsonb;
  v_k     int;
  v_a     timestamptz;
  v_b     timestamptz;
  v_o     timestamptz;
  v_now   timestamptz := now();
begin
  if v_anc is null or v_len = 600 then
    raise exception 'PROOF 135 FAIL: this world''s clock has not moved (anchor %, step % s): the proof needs 0413''s seam', v_anc, v_len;
  end if;
  select id into v_lon from public.ports where code = 'LON';

  -- CP_STEP_DATED: the writer steps every harbour now and one step later
  v_s1 := (public.population_tick(v_now) ->> 'slot')::bigint;
  v_s2 := (public.population_tick(v_now + make_interval(secs => v_len::double precision)) ->> 'slot')::bigint;
  v_s3 := (public.population_tick(v_now + make_interval(secs => (2 * v_len)::double precision)) ->> 'slot')::bigint;
  if v_s2 <> v_s1 + 1 or v_s3 <> v_s1 + 2 or v_s1 <> public.clock_count('population_slot', v_now) then
    raise exception 'PROOF 135 FAIL: the writer stamped slots %, % and % (the counter reads % now)', v_s1, v_s2, v_s3, public.clock_count('population_slot', v_now);
  end if;
  v_r := world.stats_city_people(v_lon);
  v_k := jsonb_array_length(v_r -> 'series');
  v_a := (v_r -> 'series' -> (v_k - 3) ->> 'at')::timestamptz;
  v_b := (v_r -> 'series' -> (v_k - 2) ->> 'at')::timestamptz;
  v_c := (v_r -> 'series' -> (v_k - 1) ->> 'at')::timestamptz;
  -- `at` is printed to the whole second: a second later is inside the step it begins
  if v_k < 3 or public.clock_count('population_slot', v_a + interval '1 second') <> v_s1
     or public.clock_count('population_slot', v_b + interval '1 second') <> v_s2
     or public.clock_count('population_slot', v_c + interval '1 second') <> v_s3
     or not (v_a <= v_now and v_a > v_now - make_interval(secs => v_len::double precision)) then
    raise exception 'PROOF 135 FAIL: steps % and % dated % and % (counted as % and %), now %', v_s1, v_s2, v_a, v_b,
      public.clock_count('population_slot', v_a + interval '1 second'), public.clock_count('population_slot', v_b + interval '1 second'), v_now;
  end if;
  raise notice 'PASS: CP_STEP_DATED — slot % dated % (now %; slot x 600 would read %)', v_s1, v_a, v_now, to_timestamp(v_s1 * 600);

  -- CP_STEP_LENGTH. The two steps after now's are whole steps of the new length in every world. Now's own step is one too, unless it is the
  -- step the clock's rate moved in: 0413 re-timed that one about the seam (public.clock_set), so it runs from its true start to the anchor's
  -- epoch + one step, and a world built within the last step (a from-zero apply) is still inside it. Its length is read from the anchor, never
  -- from public.clock_start, which is what the reader under test dates with.
  v_want := case when v_s1 = (v_anc ->> 'count')::bigint then (v_anc ->> 'epoch')::numeric + v_len - (v_anc ->> 'start')::numeric else v_len end;
  if abs(extract(epoch from v_c - v_b) - v_len) > 1 or abs(extract(epoch from v_b - v_a) - v_want) > 1 or v_want = 600 then
    raise exception 'PROOF 135 FAIL: neighbouring steps % s and % s apart, not % and % (now''s step % ; the seam''s %)',
      extract(epoch from v_b - v_a), extract(epoch from v_c - v_b), v_want, v_len, v_s1, v_anc ->> 'count';
  end if;
  raise notice 'PASS: CP_STEP_LENGTH — % s apart, then % s%', extract(epoch from v_b - v_a), extract(epoch from v_c - v_b),
    case when v_want <> v_len then ' (now''s step is the seam''s own, ' || v_want || ' s by the anchor)' else '' end;

  -- CP_BEFORE_SEAM: a step logged a thousand steps (of the old 600 s) before the anchored one, older than any row this world kept
  v_old := (v_anc ->> 'count')::bigint - 1000;
  insert into public.population_log (port_id, slot, population, kind, reason) values (v_lon, v_old, 135001, 'HOLD', null)
  on conflict (port_id, slot) do update set population = excluded.population;
  v_r := world.stats_city_people(v_lon);
  if (v_r -> 'series' -> 0 ->> 'population')::bigint <> 135001 then
    raise exception 'PROOF 135 FAIL: the planted old step is not the first point: %', v_r -> 'series' -> 0;
  end if;
  v_o := (v_r -> 'series' -> 0 ->> 'at')::timestamptz;
  if public.clock_count('population_slot', v_o + interval '1 second') <> v_old or extract(epoch from v_o) >= (v_anc ->> 'at')::numeric then
    raise exception 'PROOF 135 FAIL: the step before the seam (slot %) dated % (counted as %; anchor at %)', v_old, v_o,
      public.clock_count('population_slot', v_o + interval '1 second'), v_anc ->> 'at';
  end if;
  raise notice 'PASS: CP_BEFORE_SEAM — slot % dated %, before the anchor', v_old, v_o;
end
$p$;
