-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 141 - NO COURSE CROSSES THE DRAWN LAND  (migration 0440; docs/dev-log/2026-11-15-no-land-crossing.md; the owner, 2026-11-15:
--   "some ships go pass through land - such as hadibu ... fix this properly, and make procedures that this won't happen again")
--
--   On the world's own lanes and routes, read only. The land itself (the chart's 1:10m tiles) is not in the database: the full audit of every
--   course against it is tests/sea.noLandCrossing.spec.ts and scripts/db/audit-land-crossings.mjs. What the database can hold is held here:
--   the re-sailed courses are still the server's water, and the owner's own example is gone. FAILS BEFORE 0440: the lane from Hadibu to Kilwa
--   was one straight line from the quay south across the whole of Socotra.
--
-- @pass NL_LAW      every lane in public.npc_courses and every leg in public.standing_route_stops is raster water by voyage.path_refusal (join = course_join_nm, head and tail 25 nm, as cmd.do_sail passes them)
-- @pass NL_SOCOTRA  no lane and no route leg has a 1-nm sample inside solid Socotra (lat 12.45 to 12.55, lon 53.7 to 54.2: drawn land through and through)
-- @pass NL_HADIBU   the lane Hadibu -> Kilwa exists, leaves the quay by more than one straight line, and its miles are its own course's (nm = voyage.segments_from_course's sum)
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_join numeric := public.wc_num('course_join_nm');
  v_bad  text;
  v_n    int;
  v_c    jsonb;
  v_nm   numeric;
  v_box  int;
begin
  -- the samples of a course inside the Socotra box
  create function pg_temp.socotra_141(p jsonb) returns int language plpgsql stable as $s$
  declare
    i int; s int; n int; c int := 0; a jsonb; b jsonb; la float8; lo float8;
  begin
    for i in 0 .. jsonb_array_length(p) - 2 loop
      a := p -> i;
      b := p -> (i + 1);
      n := greatest(1, ceil(voyage.gc_distance_nm((a ->> 0)::numeric, (a ->> 1)::numeric, (b ->> 0)::numeric, (b ->> 1)::numeric))::int);
      for s in 0 .. n loop
        la := (a ->> 0)::float8 + ((b ->> 0)::float8 - (a ->> 0)::float8) * s / n;
        lo := voyage.lon_lerp((a ->> 1)::float8, (b ->> 1)::float8, s::float8 / n);
        if la between 12.45 and 12.55 and lo between 53.7 and 54.2 then
          c := c + 1;
        end if;
      end loop;
    end loop;
    return c;
  end
  $s$;

  select count(*), string_agg(x.k || ': ' || x.ref, '; ') into v_n, v_bad
    from (select 'lane ' || c.from_port || '->' || c.to_port as k, c.course from public.npc_courses c
          union all
          select 'route ' || s.route_id || '#' || s.ord, s.course from public.standing_route_stops s where s.course is not null) q
   cross join lateral (select q.k, voyage.path_refusal(q.course, (q.course -> 0 ->> 0)::numeric, (q.course -> 0 ->> 1)::numeric,
                                                       (q.course -> -1 ->> 0)::numeric, (q.course -> -1 ->> 1)::numeric, v_join, 25, 25) as ref) x
   where x.ref is not null;
  if v_n > 0 then
    raise exception 'PROOF 141 FAIL: % course(s) refused by voyage.path_refusal: %', v_n, left(v_bad, 1500);
  end if;
  raise notice 'PASS: NL_LAW — % lanes and % route legs, every one raster water', (select count(*) from public.npc_courses),
    (select count(*) from public.standing_route_stops where course is not null);

  select count(*) into v_box
    from (select c.course from public.npc_courses c union all select s.course from public.standing_route_stops s where s.course is not null) q
   where pg_temp.socotra_141(q.course) > 0;
  if v_box > 0 then
    raise exception 'PROOF 141 FAIL: % course(s) still sail through solid Socotra', v_box;
  end if;
  raise notice 'PASS: NL_SOCOTRA — no lane or route leg crosses the Socotra box';

  select c.course, c.nm into v_c, v_nm
    from public.npc_courses c join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port
   where a.code = 'HAD' and b.code = 'KIL';
  if v_c is null then
    raise exception 'PROOF 141 FAIL: the world holds no Hadibu -> Kilwa lane, the owner''s own example';
  end if;
  if jsonb_array_length(v_c) <= 2 then
    raise exception 'PROOF 141 FAIL: Hadibu -> Kilwa is still one straight line from the quay: %', v_c;
  end if;
  if abs(v_nm - (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(v_c)) x)) > 0.01 then
    raise exception 'PROOF 141 FAIL: Hadibu -> Kilwa''s nm % is not its course''s own measure', v_nm;
  end if;
  raise notice 'PASS: NL_HADIBU — Hadibu -> Kilwa sails % points, % nm, round the island', jsonb_array_length(v_c), round(v_nm, 1);
end
$$;
