-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 9 — THE FLEET NEVER TOUCHES LAND, AND THE ARCTIC STAYS CLOSED
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner's law (docs/OWNER_REQUESTS.md row 41): "i don't want the fleet to ever touch land."
-- Under 0039 it holds BY CONSTRUCTION — a course is verified against the raster before a voyage
-- exists — but a law held by construction still needs its guard PROVEN able to bite, or the next
-- refactor removes the construction and nothing goes red. So this proof:
--
--   1. sails real voyages (a coastal hop as a player, the Lisbon→Nagasaki long haul as a fixture,
--      since no starter hull carries 100 days of stores) and WALKS every stored course at
--      sub-cell intervals through voyage.assert_paths_water — the one sampler;
--   2. PLANTS a voyage whose course runs straight across Iberia and requires the guard to refuse
--      it as E_LAND — the non-vacuity control, run on every proof run, not once at review;
--   3. holds the door shut on the old defect: the road to Japan measures over 12,000 nm and never
--      leaves the temperate band — the leg graph served 7,565 nm over the pole at 88.6°N;
--   4. states the inland approaches out loud — and, since 0076, states the RIGHT thing about them.
--
-- ── WHY MARKER 4 WAS RE-CUT (migration 0076, 2026-09-04) ───────────────────────────────────────
-- It used to read *"the river ports' snap to open water is real water INSIDE the served figures
-- now, never a silent teleport"*, and it printed "approach included" on every line. **That claim
-- is false after 0076 and the marker was re-cut rather than deleted.** The approach is no longer
-- sailed at all: a course now BEGINS and ENDS at the port's ROADSTEAD — the one point of open
-- water it is reached from — and `voyage.settle` docks her at the port itself on the ETA, exactly
-- as it has since 0007. The approach is a MEASURED, SERVED, DRAWN fact about the place
-- (`sea_reaches.roadstead_lat/lon` and `snap_nm`, on the wire as `snapshot.ports[].roadstead`),
-- and no keel crosses it. So the new law is: **the approach is measured, served and drawn, and
-- the course does not enter it.**
--
-- Deleting the marker would have been the cheap move and the wrong one: the thing it guards — that
-- an inland port's water is a real, published quantity and not a silent teleport — is still the
-- second half of the owner's row 41, and 0076 changed only WHERE the fleet meets it.
--
-- @pass NEVER_TOUCH_LAND_WALKED   the guard walked every freshly sailed course and found water
-- @pass NEVER_TOUCH_LAND_BITES    a planted straight-across-Iberia voyage was refused as E_LAND
-- @pass ARCTIC_IS_CLOSED          Lisbon→Nagasaki sails >12,000 nm and never crosses 67°N
-- @pass INLAND_APPROACH_HONEST    every approach is measured, served and drawn — and no course sails it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth constant uuid := '00000000-0008-4000-8000-000000000001';
  v_player uuid;
  v_fleet  uuid;
  v_lis uuid; v_cad uuid; v_nag uuid; v_bcn uuid;
  v_res  jsonb;
  v_nag_course jsonb;
  v_nag_voyage uuid;
  v_nag_nm numeric;
  v_maxlat numeric;
  g record;
  v_walked0 int;
  v_guard_msg text;
  r record;
  v_inland int := 0;
  v_off_quay int;
  v_worst_nm numeric;
  v_far_code text;
  v_far_nm numeric;
  v_far_course jsonb;
  v_far_ref text;
  v_sailed_from numeric;
  v_sailed_to numeric;
begin
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_cad from public.ports where code = 'CAD';
  select id into v_nag from public.ports where name = 'Nagasaki';
  select id into v_bcn from public.ports where name = 'Barcelona';

  v_player := public.new_house(c_auth, 'Casa da Costa', 'PRT');
  perform cmd.assume_identity(c_auth);
  select id into v_fleet from public.fleets where player_id = v_player;
  perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
  perform cmd.do_hire(v_fleet, jsonb_build_object('count',
    (select c.crew_max - sh.crew from public.ships sh
       join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = v_fleet)));

  -- ── 1. a real player passage, proposed and verified ─────────────────────────────────────────
  v_res := proof.sail(v_fleet, 'CAD');
  if coalesce(v_res->>'ok', 'false') <> 'true' then
    raise exception 'PROOF 9 FAILED: the Lisbon-Cadiz passage was refused: %', v_res;
  end if;

  -- ── the long haul, as a FIXTURE: no starter hull carries 100 days of stores, and this proof is
  --    about the water, not the larder. voyage.depart is the one door a voyage is born through;
  --    the course still went through voyage.segments_from_course like every other.
  v_nag_course := proof.course('LIS', 'NAG');
  if v_nag_course is null then
    raise exception 'PROOF 9 FAILED: the course fixture holds no Lisbon-Nagasaki proposal';
  end if;
  -- a second house, because a fleet holds one sailing voyage and the player fleet is at sea.
  -- (Two statements: a volatile new_house inside the sub-select's WHERE ran against a snapshot
  -- that could not yet see the fleet it had just created.)
  v_player := public.new_house('00000000-0008-4000-8000-000000000002', 'Casa do Oriente', 'PRT');
  v_nag_voyage := voyage.depart(
    (select id from public.fleets where player_id = '00000000-0008-4000-8000-000000000002'::uuid
       or player_id = v_player order by created_at desc limit 1),
    voyage.segments_from_course(v_nag_course), v_lis, v_nag);
  select total_nm into v_nag_nm from public.voyages where id = v_nag_voyage;
  select max((p.value->>0)::numeric) into v_maxlat from jsonb_array_elements(v_nag_course) p;
  if v_nag_nm < 12000 then
    raise exception 'PROOF 9 FAILED: Lisbon-Nagasaki sails only % nm - under 12,000 means the Arctic is open again (the leg graph served 7,565 over the pole)', v_nag_nm;
  end if;
  if v_maxlat >= 67 then
    raise exception 'PROOF 9 FAILED: the road to Japan reaches %°N - the pack ice is not being honoured (the leg graph reached 88.6)', v_maxlat;
  end if;
  raise notice 'PASS: ARCTIC_IS_CLOSED — Lisbon→Nagasaki is served at % nm round the Cape, its course never above %°N (the leg graph served 7,565 nm over the pole at 88.6°N)',
    v_nag_nm, v_maxlat;

  -- ── 2. the guard walks what was just sailed ─────────────────────────────────────────────────
  select * into g from voyage.assert_paths_water();
  if g.voyages_walked < 2 then
    raise exception 'PROOF 9 FAILED: the guard walked only % voyage(s) - it is asserting over too little to mean anything', g.voyages_walked;
  end if;
  v_walked0 := g.voyages_walked;
  raise notice 'PASS: NEVER_TOUCH_LAND_WALKED — % stored course(s) walked at sub-cell intervals, every sample open water (% legacy-converted skipped and said so)',
    g.voyages_walked, g.legacy_skipped;

  -- ── 3. THE BITE: a straight line across Iberia must be caught, every run ────────────────────
  insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile,
                              departed_at, eta, status, last_settled_day, origin_port_id, dest_port_id)
  select v_fleet, v_player, s.segs,
         (select sum((x->>'nm')::numeric) from jsonb_array_elements(s.segs) x),
         -- DATED NOW, deliberately (0076): the land guard grandfathers voyages that departed
         -- before that migration applied, because they were bought under the old quay-to-quay
         -- allowance. A plant dated in the past would be judged by the RETIRED rule and this
         -- marker would stop testing the law the game runs on today.
         '[4.5, 4.5]'::jsonb, now(), now() + interval '1 hour',
         'ARRIVED', 1, v_lis, v_bcn
    from (select voyage.segments_from_course(jsonb_build_array(
            jsonb_build_array((select lat from public.ports where id = v_lis),
                              (select lon from public.ports where id = v_lis)),
            jsonb_build_array((select lat from public.ports where id = v_bcn),
                              (select lon from public.ports where id = v_bcn)))) as segs) s;
  begin
    perform * from voyage.assert_paths_water();
    raise exception 'PROOF 9 FAILED: the guard swallowed a straight Lisbon-Barcelona voyage whole - it cannot catch anything';
  exception when others then
    if sqlerrm like 'PROOF 9 FAILED%' then raise; end if;
    v_guard_msg := sqlerrm;
    if position('E_LAND' in v_guard_msg) = 0 then
      raise exception 'PROOF 9 FAILED: the guard refused the planted voyage for the wrong reason: %', v_guard_msg;
    end if;
  end;
  delete from public.voyages
   where fleet_id = v_fleet and dest_port_id = v_bcn and status = 'ARRIVED';
  raise notice 'PASS: NEVER_TOUCH_LAND_BITES — the planted straight-across-Iberia voyage was refused: %', v_guard_msg;

  -- ── 4. every approach is measured, served and drawn — and no course sails it ─────────────────
  -- NON-VACUITY FIRST. If nothing in this world snapped, "no course enters the approach" would be
  -- true of a world with no approaches in it, which proves nothing about this one.
  select count(*), max(snap_nm) into v_off_quay, v_worst_nm from public.sea_reaches where snap_nm > 0;
  if v_off_quay < 100 or v_worst_nm < 20 then
    raise exception 'PROOF 9 FAILED: only % place(s) lie off their own water, worst % nm — this marker would be asserting over nothing',
      v_off_quay, v_worst_nm;
  end if;

  for r in
    select p.code, p.name, sr.snap_nm, sr.roadstead_lat, sr.roadstead_lon,
           (select (sr2.reaches->>p.code)::numeric from public.sea_reaches sr2 where sr2.port_id = v_lis) as from_lis
      from public.ports p
      join public.sea_reaches sr on sr.port_id = p.id
     where p.name in ('Suez', 'Bristol', 'Hanoi')
     order by p.code
  loop
    if r.snap_nm is null or r.from_lis is null or r.from_lis <= 0 then
      raise exception 'PROOF 9 FAILED: % has no measured approach or no reach from Lisbon', r.name;
    end if;
    -- MEASURED and SERVED: the roadstead exists, and it is exactly snap_nm off the quay, so the
    -- dotted helper line the chart draws IS the distance the table published.
    if r.roadstead_lat is null or r.roadstead_lon is null then
      raise exception 'PROOF 9 FAILED: % is served no roadstead, so a client would have to compute one', r.name;
    end if;
    if abs(voyage.gc_distance_nm((select lat from public.ports where code = r.code)::float8,
                                 (select lon from public.ports where code = r.code)::float8,
                                 r.roadstead_lat::float8, r.roadstead_lon::float8)::numeric - r.snap_nm) > 0.01 then
      raise exception 'PROOF 9 FAILED: %s roadstead is not % nm off her quay — the line drawn would not be the distance measured',
        r.name, r.snap_nm;
    end if;
    -- and it is WATER: the point a course ends at is somewhere a hull can float.
    if voyage.water_snap_nm(r.roadstead_lat, r.roadstead_lon) <> 0 then
      raise exception 'PROOF 9 FAILED: %s roadstead does not stand on sailable water', r.name;
    end if;
    v_inland := v_inland + 1;
    raise notice 'PASS: INLAND_APPROACH_HONEST — % is reached from (%, %), % nm off her quay, and lies % nm by sea from Lisbon — the approach is published and NOT sailed',
      r.name, r.roadstead_lat, r.roadstead_lon, round(r.snap_nm, 1), r.from_lis;
  end loop;
  if v_inland <> 3 then
    raise exception 'PROOF 9 FAILED: only % of the 3 named river ports could be measured', v_inland;
  end if;

  -- AND THE COURSE DOES NOT ENTER IT. Two readings, one of a proposal and one of a real voyage.
  --
  -- (a) the WORST snapping port this proof holds a course to, picked deterministically off the
  --     table rather than named here, so a raster change moves the subject instead of the claim.
  select p.code, sr.snap_nm into v_far_code, v_far_nm
    from public.ports p
    join public.sea_reaches sr on sr.port_id = p.id
   where sr.snap_nm > 0 and proof.course('LIS', p.code) is not null
   order by sr.snap_nm desc, p.code
   limit 1;
  if v_far_code is null then
    raise exception 'PROOF 9 FAILED: the course fixture holds no proposal to any port that snaps, so nothing here is tested';
  end if;
  v_far_course := proof.course('LIS', v_far_code);
  if (v_far_course->0->>0)::numeric
       is distinct from (select roadstead_lat from public.sea_reaches where code = 'LIS')
     or (v_far_course->(jsonb_array_length(v_far_course)-1)->>0)::numeric
       is distinct from (select roadstead_lat from public.sea_reaches where code = v_far_code) then
    raise exception 'PROOF 9 FAILED: the proposed LIS->% course runs quay to quay, not roads to roads', v_far_code;
  end if;
  -- THE POINT OF THE WHOLE MARKER: judged with a FLAT 25 nm of sampling slack at each end and NO
  -- snap exemption whatever, the course is open water end to end. Before 0076 this same passage
  -- was legal only because the approach bought it up to 67 nm of land to cross.
  v_far_ref := voyage.path_refusal(v_far_course,
                 (select roadstead_lat from public.sea_reaches where code = 'LIS'),
                 (select roadstead_lon from public.sea_reaches where code = 'LIS'),
                 (select roadstead_lat from public.sea_reaches where code = v_far_code),
                 (select roadstead_lon from public.sea_reaches where code = v_far_code),
                 public.wc_num('course_join_nm'), 25, 25);
  if v_far_ref is not null then
    raise exception 'PROOF 9 FAILED: the LIS->% course needs more than the flat allowance: %', v_far_code, v_far_ref;
  end if;

  -- (b) the REAL voyage this proof sailed at step 1, read off the frozen path.
  select (path->0->'a'->>0)::numeric,
         (path->(jsonb_array_length(path)-1)->'b'->>0)::numeric
    into v_sailed_from, v_sailed_to
    from public.voyages where fleet_id = v_fleet and origin_port_id = v_lis and dest_port_id = v_cad
    order by departed_at desc limit 1;
  if v_sailed_from is distinct from (select roadstead_lat from public.sea_reaches where code = 'LIS')
     or v_sailed_to is distinct from (select roadstead_lat from public.sea_reaches where code = 'CAD') then
    raise exception 'PROOF 9 FAILED: the sailed Lisbon-Cadiz voyage runs from % to % and not between the two roadsteads',
      v_sailed_from, v_sailed_to;
  end if;
  raise notice 'PASS: INLAND_APPROACH_HONEST — % place(s) lie off their own water (worst % nm) and NO keel crosses one: the proposed LIS->% passage is open water end to end under a flat 25 nm allowance with no snap exemption, and the voyage actually sailed ran from the Lisbon roads to the Cadiz roads',
    v_off_quay, round(v_worst_nm, 2), v_far_code;
end $$;
