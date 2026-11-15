-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 143 - AN APPROACH IS NOT A CANAL  (migration 0441; docs/dev-log/2026-11-15-isthmus.md; the owner, 2026-11-15: no ship
--   crosses land, ever, and it must not happen again)
--
--   voyage.path_refusal skipped every sample within the allowance of each end of a course unread (25 nm at a harbour). Panama
--   City's roadstead and Portobelo's lie 46 nm apart across the isthmus: the straight line had no sample left to read. FAILS
--   BEFORE 0441: that line was accepted, a fleet at Panama City sailed it, and an 18 nm line across inland Castile was water.
--
-- @pass AP_CANAL     the straight line from Panama City's roads to Portobelo's is E_LAND with the harbour allowance (25, 25), the same answer as with none; a fleet lying at Panama City is refused it by cmd.do_sail, with no course (E_NO_COURSE) and with the line as a hand-made course (E_LAND)
-- @pass AP_CHAIN     a course that lies wholly on the land between two land ends, inside both allowances, is refused: two approaches do not chain
-- @pass AP_ROADS     every roadstead lies in a raster water cell, so no harbour end has an approach; every lane and coast course is water by the rule, and the allowance changes the answer for none of them
-- @pass AP_APPROACH  an end that stands on land still leaves it: Lisbon's quay reaches its own roadstead inside its measured snap + 25 nm, and is refused when the allowance is taken away; the land guard skips, and counts, voyages that departed before 0441
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth constant uuid := '00000000-0143-4000-8000-000000000001';
  v_join numeric := public.wc_num('course_join_nm');
  v_player uuid;
  v_fleet  uuid;
  v_pan uuid; v_prt uuid;
  a record; b record; q record;
  v_line jsonb;
  v_ref  text;
  v_bad  text;
  v_n    int;
  v_msg  text;
  g      record;
begin
  -- AP_CANAL
  select p.id, sr.roadstead_lat as lat, sr.roadstead_lon as lon into a from public.sea_reaches sr join public.ports p on p.id = sr.port_id where p.code = 'PAN';
  select p.id, sr.roadstead_lat as lat, sr.roadstead_lon as lon into b from public.sea_reaches sr join public.ports p on p.id = sr.port_id where p.code = 'PRT';
  v_pan := a.id; v_prt := b.id;
  v_line := jsonb_build_array(jsonb_build_array(a.lat, a.lon), jsonb_build_array(b.lat, b.lon));
  if voyage.gc_distance_nm(a.lat::float8, a.lon::float8, b.lat::float8, b.lon::float8) >= 50 then
    raise exception 'PROOF 143 FAIL: the two roadsteads are no longer within 25 + 25 nm of each other: the control proves nothing';
  end if;
  v_ref := voyage.path_refusal(v_line, a.lat, a.lon, b.lat, b.lon, v_join, 25, 25);
  if v_ref is null or v_ref not like 'E_LAND:%' or v_ref is distinct from voyage.path_refusal(v_line, a.lat, a.lon, b.lat, b.lon, v_join, 0, 0) then
    raise exception 'PROOF 143 FAIL: the straight line across the isthmus is not refused as land: %', coalesce(v_ref, 'accepted');
  end if;
  -- the order itself: a fleet lying at Panama City
  v_player := public.new_house(c_auth, 'Casa del Istmo', 'PRT');
  perform cmd.assume_identity(c_auth);
  select id into v_fleet from public.fleets where player_id = v_player;
  perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
  perform cmd.do_hire(v_fleet, jsonb_build_object('count',
    (select (public.ship_base(sh.id)).crew_max - sh.crew from public.ships sh where sh.fleet_id = v_fleet)));
  update public.fleets set port_id = v_pan where id = v_fleet;
  begin
    perform cmd.do_sail(v_fleet, jsonb_build_object('dest', v_prt));
    raise exception 'PROOF 143 FAIL: a fleet sailed from Panama City to Portobelo with no course: across the isthmus';
  exception when others then
    if sqlerrm like 'PROOF 143 FAIL%' then raise; end if;
    v_msg := sqlerrm;
  end;
  if v_msg not like 'E_NO_COURSE:%' then
    raise exception 'PROOF 143 FAIL: the order with no course was refused, but not for the land: %', v_msg;
  end if;
  begin
    perform cmd.do_sail(v_fleet, jsonb_build_object('dest', v_prt, 'path', v_line));
    raise exception 'PROOF 143 FAIL: a fleet sailed the hand-made straight course from Panama City to Portobelo';
  exception when others then
    if sqlerrm like 'PROOF 143 FAIL%' then raise; end if;
    v_msg := sqlerrm;
  end;
  if v_msg not like 'E_LAND:%' then
    raise exception 'PROOF 143 FAIL: the hand-made course was refused, but not as land: %', v_msg;
  end if;
  raise notice 'PASS: AP_CANAL — Panama City to Portobelo, % nm roads to roads: the straight line is % with the allowance and with none; cmd.do_sail refuses it with no course and as a hand-made course',
    round(voyage.gc_distance_nm(a.lat::float8, a.lon::float8, b.lat::float8, b.lon::float8)::numeric, 1), v_ref;

  -- AP_CHAIN
  v_ref := voyage.path_refusal('[[40.0, -4.0], [40.3, -4.0]]'::jsonb, 40.0, -4.0, 40.3, -4.0, 1, 25, 25);
  if v_ref is null or v_ref not like 'E_LAND:%' then
    raise exception 'PROOF 143 FAIL: 18 nm across inland Castile, inside both allowances, is accepted (%)', coalesce(v_ref, 'accepted');
  end if;
  -- and a longer one: land at both ends, the middle read
  v_ref := voyage.path_refusal('[[40.0, -4.0], [41.0, -4.0]]'::jsonb, 40.0, -4.0, 41.0, -4.0, 1, 25, 25);
  if v_ref is null or v_ref not like 'E_LAND:%' then
    raise exception 'PROOF 143 FAIL: 60 nm across inland Castile is accepted (%)', coalesce(v_ref, 'accepted');
  end if;
  raise notice 'PASS: AP_CHAIN — a line wholly on the land between two land ends is refused: 18 nm (inside 25 + 25) and 60 nm';

  -- AP_ROADS
  select string_agg(p.code, ' '), count(*) into v_bad, v_n
    from public.sea_reaches sr join public.ports p on p.id = sr.port_id, public.sea_raster s
   where s.id = 1
     and get_bit(s.cells, (least(s.rows - 1, greatest(0, floor((90 - sr.roadstead_lat) / s.cell_deg)::int)) * s.cols
                          + ((floor((sr.roadstead_lon + 180) / s.cell_deg)::int % s.cols) + s.cols) % s.cols) * s.bits_per_cell) <> 1;
  if v_n > 0 then
    raise exception 'PROOF 143 FAIL: roadstead(s) in a raster land cell (they would have an approach): %', v_bad;
  end if;
  select string_agg(x.k || ': ' || coalesce(x.with_allowance, 'ok') || ' / ' || coalesce(x.with_none, 'ok'), '; '), count(*) into v_bad, v_n
    from (select a2.code || '->' || b2.code as k,
                 voyage.path_refusal(c.course, (c.course -> 0 ->> 0)::numeric, (c.course -> 0 ->> 1)::numeric,
                                     (c.course -> -1 ->> 0)::numeric, (c.course -> -1 ->> 1)::numeric, v_join, 25, 25) as with_allowance,
                 voyage.path_refusal(c.course, (c.course -> 0 ->> 0)::numeric, (c.course -> 0 ->> 1)::numeric,
                                     (c.course -> -1 ->> 0)::numeric, (c.course -> -1 ->> 1)::numeric, v_join, 0, 0) as with_none
            from (select from_port, to_port, course from public.npc_courses union all select from_port, to_port, course from public.npc_coast_courses) c
            join public.ports a2 on a2.id = c.from_port join public.ports b2 on b2.id = c.to_port) x
   where x.with_allowance is not null or x.with_none is not null;
  if v_n > 0 then
    raise exception 'PROOF 143 FAIL: % lane(s) or coast course(s) refused, or judged differently with the allowance: %', v_n, left(v_bad, 1500);
  end if;
  raise notice 'PASS: AP_ROADS — % roadsteads, every one raster water; % lanes and coast courses, every one water with every sample read',
    (select count(*) from public.sea_reaches), (select count(*) from public.npc_courses) + (select count(*) from public.npc_coast_courses);

  -- AP_APPROACH
  select p.lat, p.lon, sr.roadstead_lat as rlat, sr.roadstead_lon as rlon, sr.snap_nm into q
    from public.sea_reaches sr join public.ports p on p.id = sr.port_id where p.code = 'LIS';
  v_line := jsonb_build_array(jsonb_build_array(q.lat, q.lon), jsonb_build_array(q.rlat, q.rlon));
  if q.snap_nm <= 7.5 or voyage.path_refusal(v_line, q.lat, q.lon, q.rlat, q.rlon, 1, 0, 0) is null then
    raise exception 'PROOF 143 FAIL: Lisbon''s quay no longer lies on the land off its roadstead: the approach control proves nothing';
  end if;
  v_ref := voyage.path_refusal(v_line, q.lat, q.lon, q.rlat, q.rlon, 1, q.snap_nm + 25, 25);
  if v_ref is not null then
    raise exception 'PROOF 143 FAIL: an end on the land can no longer leave it (Lisbon quay to its roads): %', v_ref;
  end if;
  -- the land guard: nothing in this world departed before 0441 applied is walked by the new rule; it says how many it skipped
  select * into g from voyage.assert_paths_water();
  if g.legacy_skipped < (select count(*) from public.voyages v where v.path -> 0 ? 'legacy') then
    raise exception 'PROOF 143 FAIL: the land guard skipped fewer voyages than there are legacy paths';
  end if;
  if position('0441 AN APPROACH IS NOT A CANAL' in pg_get_functiondef('voyage.assert_paths_water()'::regprocedure)) = 0 then
    raise exception 'PROOF 143 FAIL: the land guard does not hold the 0441 cut-off';
  end if;
  raise notice 'PASS: AP_APPROACH — Lisbon''s quay, % nm inland of its roads, reaches them inside its snap + 25 and is refused without; the land guard walked % voyage(s) and skipped % admitted before',
    q.snap_nm, g.voyages_walked, g.legacy_skipped;
end
$$;
