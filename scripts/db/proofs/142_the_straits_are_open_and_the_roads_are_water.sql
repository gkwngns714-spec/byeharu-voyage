-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 142 - THE STRAITS ARE OPEN AND THE ROADS ARE WATER  (migration 0441; docs/dev-log/2026-11-15-land-channels.md; the owner,
--   2026-11-15: "some ships go pass through land - such as hadibu ... fix this properly"; no ship crosses land)
--
--   On the world itself, read only. The chart's 1:10m land is not in the database: the full audit of every course and roadstead against
--   it is tests/sea.noLandCrossing.spec.ts and scripts/db/audit-land-crossings.mjs. What the database holds is held here. FAILS BEFORE
--   0441: the Corfu channel was raster land, Hadibu was reached from its quay on Socotra's shore, and no table of drawn roadsteads existed.
--
-- @pass LC_CHANNELS  the charted channels (Corfu, Tsugaru, the Wielingen) are in voyage.channels and every cell they opened is raster water; a course from Corfu's roads up the North Corfu channel is water with every sample checked (no approach slack)
-- @pass LC_ROADS     every harbour in voyage.drawn_roadsteads is reached from that point: voyage.water_roadstead answers it for the quay, public.sea_reaches holds it, its cell is raster water, and snap_nm is the quay's distance to it; Hadibu's is off the quay
-- @pass LC_LANES     no lane or coast course to or from such a harbour, and no route leg out of one (a stop's course leaves its port), begins or ends anywhere but its roadstead; every coast course is raster water by voyage.path_refusal
-- @pass LC_COAST     public.npc_coast_legs reads a coast course backwards whole, every point of it
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_join numeric := public.wc_num('course_join_nm');
  v_bad  text;
  v_n    int;
  v_ctl  jsonb;
  r      record;
begin
  -- LC_CHANNELS
  if (select count(*) from voyage.channels c where c.id in ('corfu', 'tsugaru', 'western-scheldt')
        and jsonb_array_length(c.carved_cells) = c.opens_land and c.opens_land > 0) <> 3 then
    raise exception 'PROOF 142 FAIL: the charted channels are not all in voyage.channels';
  end if;
  select string_agg(c.id || ':' || k.v, ' '), count(*) into v_bad, v_n
    from voyage.channels c cross join lateral jsonb_array_elements_text(c.carved_cells) k(v), public.sea_raster s
   where s.id = 1 and c.id in ('corfu', 'tsugaru', 'western-scheldt') and get_bit(s.cells, k.v::int * s.bits_per_cell) <> 1;
  if v_n > 0 then
    raise exception 'PROOF 142 FAIL: charted cell(s) not water: %', v_bad;
  end if;
  select jsonb_build_array(jsonb_build_array(sr.roadstead_lat, sr.roadstead_lon)) || '[[39.7, 19.96], [39.74, 19.975], [39.785, 19.968], [39.83, 19.93], [39.92, 19.85], [39.97, 19.72]]'::jsonb
    into v_ctl from public.sea_reaches sr join public.ports p on p.id = sr.port_id where p.code = 'COR';
  if v_ctl is null or voyage.path_refusal(v_ctl, (v_ctl -> 0 ->> 0)::numeric, (v_ctl -> 0 ->> 1)::numeric, 39.97, 19.72, 0, 0, 0) is not null then
    raise exception 'PROOF 142 FAIL: the North Corfu channel is not water from the town''s roads: %',
      voyage.path_refusal(v_ctl, (v_ctl -> 0 ->> 0)::numeric, (v_ctl -> 0 ->> 1)::numeric, 39.97, 19.72, 0, 0, 0);
  end if;
  raise notice 'PASS: LC_CHANNELS — 3 charted channels, every opened cell water; Corfu''s roads to the north mouth of the channel: water';

  -- LC_ROADS
  select string_agg(d.code, ' '), count(*) into v_bad, v_n
    from voyage.drawn_roadsteads d
    join public.ports p on p.code = d.code
    join public.sea_reaches sr on sr.port_id = p.id
   cross join lateral voyage.water_roadstead(p.lat, p.lon) w,
         public.sea_raster s
   where s.id = 1
     and (w.lat <> d.lat or w.lon <> d.lon or sr.roadstead_lat <> d.lat or sr.roadstead_lon <> d.lon
          or abs(sr.snap_nm - voyage.gc_distance_nm(p.lat::float8, p.lon::float8, d.lat::float8, d.lon::float8)::numeric) > 0.01
          or get_bit(s.cells, (least(s.rows - 1, greatest(0, floor((90 - d.lat) / s.cell_deg)::int)) * s.cols
                              + ((floor((d.lon + 180) / s.cell_deg)::int % s.cols) + s.cols) % s.cols) * s.bits_per_cell) <> 1);
  if v_n > 0 then
    raise exception 'PROOF 142 FAIL: drawn roadstead(s) not served as the rule answers: %', v_bad;
  end if;
  if not exists (select 1 from voyage.drawn_roadsteads d join public.ports p on p.code = d.code join public.sea_reaches sr on sr.port_id = p.id
                  where d.code = 'HAD' and sr.snap_nm > 0) then
    raise exception 'PROOF 142 FAIL: Hadibu is not reached from a drawn roadstead off its quay';
  end if;
  raise notice 'PASS: LC_ROADS — % drawn roadsteads, each the rule''s answer, the served point and raster water; Hadibu off its quay',
    (select count(*) from voyage.drawn_roadsteads);

  -- LC_LANES
  select string_agg(x.k, ' '), count(*) into v_bad, v_n
    from (select a.code || '->' || b.code as k, c.course, ra.roadstead_lat as alat, ra.roadstead_lon as alon, rb.roadstead_lat as blat, rb.roadstead_lon as blon
            from (select from_port, to_port, course from public.npc_courses union all select from_port, to_port, course from public.npc_coast_courses) c
            join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port
            join public.sea_reaches ra on ra.port_id = a.id join public.sea_reaches rb on rb.port_id = b.id
           where a.code in (select code from voyage.drawn_roadsteads) or b.code in (select code from voyage.drawn_roadsteads)) x
   where (x.course -> 0 ->> 0)::numeric <> x.alat or (x.course -> 0 ->> 1)::numeric <> x.alon
      or (x.course -> -1 ->> 0)::numeric <> x.blat or (x.course -> -1 ->> 1)::numeric <> x.blon;
  if v_n > 0 then
    raise exception 'PROOF 142 FAIL: % lane(s) or coast course(s) of a drawn-roadstead harbour do not run roads to roads: %', v_n, left(v_bad, 1500);
  end if;
  select string_agg(s.route_id || '#' || s.ord, ' '), count(*) into v_bad, v_n
    from public.standing_route_stops s
    join public.ports p on p.id = s.port_id
    join public.sea_reaches sr on sr.port_id = p.id
   where s.course is not null and p.code in (select code from voyage.drawn_roadsteads)
     and ((s.course -> 0 ->> 0)::numeric <> sr.roadstead_lat or (s.course -> 0 ->> 1)::numeric <> sr.roadstead_lon);
  if v_n > 0 then
    raise exception 'PROOF 142 FAIL: % route leg(s) out of a drawn-roadstead harbour begin elsewhere: %', v_n, left(v_bad, 1500);
  end if;
  select string_agg(a.code || '->' || b.code || ': ' || x.ref, '; '), count(*) into v_bad, v_n
    from public.npc_coast_courses c join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port
   cross join lateral (select voyage.path_refusal(c.course, (c.course -> 0 ->> 0)::numeric, (c.course -> 0 ->> 1)::numeric,
                                                  (c.course -> -1 ->> 0)::numeric, (c.course -> -1 ->> 1)::numeric, v_join, 25, 25) as ref) x
   where x.ref is not null;
  if v_n > 0 then
    raise exception 'PROOF 142 FAIL: coast course(s) refused by voyage.path_refusal: %', left(v_bad, 1500);
  end if;
  raise notice 'PASS: LC_LANES — every lane, coast course and route leg of a drawn-roadstead harbour runs roads to roads; % coast courses raster water',
    (select count(*) from public.npc_coast_courses);

  -- LC_COAST
  v_n := 0;
  for r in select c.from_port, c.to_port, c.course from public.npc_coast_courses c
            where not exists (select 1 from public.npc_coast_courses d where d.from_port = c.to_port and d.to_port = c.from_port)
              and not exists (select 1 from public.npc_known_legs(c.to_port) k where k.to_port = c.from_port) loop
    if (select l.course from public.npc_coast_legs(r.to_port) l where l.to_port = r.from_port)
         is distinct from (select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(r.course) with ordinality t(x, i)) then
      raise exception 'PROOF 142 FAIL: a coast course is not read backwards whole: %', r.course;
    end if;
    v_n := v_n + 1;
  end loop;
  raise notice 'PASS: LC_COAST — % coast course(s) read backwards whole by public.npc_coast_legs (% of them longer than a straight line)', v_n,
    (select count(*) from public.npc_coast_courses where jsonb_array_length(course) > 2);
end
$$;
