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
--   4. states the inland approaches out loud: the river ports' snap to open water is real water
--      INSIDE the served figures now, never a silent teleport (row 41's second half).
--
-- @pass NEVER_TOUCH_LAND_WALKED   the guard walked every freshly sailed course and found water
-- @pass NEVER_TOUCH_LAND_BITES    a planted straight-across-Iberia voyage was refused as E_LAND
-- @pass ARCTIC_IS_CLOSED          Lisbon→Nagasaki sails >12,000 nm and never crosses 67°N
-- @pass INLAND_APPROACH_HONEST    the river ports' water approach is measured and served
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
         '[4.5, 4.5]'::jsonb, now() - interval '1 day', now() - interval '1 hour',
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

  -- ── 4. the river approaches are measured water, not a silent teleport ───────────────────────
  for r in
    select p.code, p.name, sr.snap_nm,
           (select (sr2.reaches->>p.code)::numeric from public.sea_reaches sr2 where sr2.port_id = v_lis) as from_lis
      from public.ports p
      join public.sea_reaches sr on sr.port_id = p.id
     where p.name in ('Suez', 'Bristol', 'Hanoi')
     order by p.code
  loop
    if r.snap_nm is null or r.from_lis is null or r.from_lis <= 0 then
      raise exception 'PROOF 9 FAILED: % has no measured approach or no reach from Lisbon', r.name;
    end if;
    v_inland := v_inland + 1;
    raise notice 'PASS: INLAND_APPROACH_HONEST — % reaches open water in % nm and lies % nm by sea from Lisbon, approach included',
      r.name, round(r.snap_nm, 1), r.from_lis;
  end loop;
  if v_inland <> 3 then
    raise exception 'PROOF 9 FAILED: only % of the 3 named river ports could be measured', v_inland;
  end if;
end $$;
