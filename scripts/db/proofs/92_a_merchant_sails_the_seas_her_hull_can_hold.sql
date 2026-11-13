-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 92 - A MERCHANT SAILS THE SEAS HER HULL CAN HOLD  (migration 0397, slice S3 of docs/SEA_CONDITIONS_AND_REGIONS.md; owner row 166: "NPCs under the same rule")
--
--   0397's own self-assert reads the catalog and cheap pure functions only: a migration never runs a real game step (docs/OPS_HEALTH.md section 4). This proof
--   runs the REAL planner (public.npc_plan, public.npc_loop_candidates) and the real sail door on the world's own merchants, with the switch it lights itself,
--   all rolled back with proof.mjs's transaction. It picks its merchants from the roster by what they are (a hull size, a leg the sea closes), never by name.
--
-- @pass SM_DARK    sea_conditions_bite_npc false (as shipped): the reader answers false, and a caravel house is still offered a known leg her hull cannot hold (the planner is what it was)
-- @pass SM_RULE    the merchant's reading is the one rule on wave only: a wave of 26 is refused the Western Ocean on a Lisbon to Havana line (E_SEA_CLOSED, wave 30 asked, no title in the figures), 39 is not; a wave of 12 holds a Pacific coast leg
-- @pass SM_MEMO    every remembered course's zones equal public.course_zones, forwards and backwards; a course the memo has not seen is sampled
-- @pass SM_LEGS    lit: her feasible legs are the dark ones less those her hull cannot hold, in the same order; no loop offered to her has such a leg, and loops are still offered
-- @pass SM_NAU     lit: a nau house with a known leg across the Western Ocean keeps it (39 holds 30)
-- @pass SM_BARCA   lit: every small-hull house keeps at least one feasible leg out of the harbour her loop starts at
-- @pass SM_PLAN    a merchant the old planner keeps buying on a loop the sea closes (planned dark, she stays): lit, the same plan at her lap start leaves her on a loop her hull can hold, or writes no BUY; the plan does not fail
-- @pass SM_DOOR    lit, and with the players' switch lit too: the sail door refuses no merchant (public.passage_gate null on the very leg the planner calls closed): a fleet at sea finishes her trip
-- @pass SM_OFF     the switch off again: the feasible legs are byte for byte what they were at the start
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_car     record;   -- a size-2 house with a known leg her hull cannot hold and one it can
  v_nau     record;   -- a nau house with a known leg across the Western Ocean
  v_shut    record;   -- a merchant whose present loop the sea closes
  v_dark    jsonb;
  v_lit     jsonb;
  v_r       jsonb;
  v_n       int;
  v_x       int;
  v_line    jsonb := '[[38.6,-9.3],[23.1,-82.4]]'::jsonb;
  v_hav     uuid := (select p.id from public.ports p where p.code = 'HAV');
  v_leg     jsonb;
  v_loop    jsonb;
begin
  if to_regprocedure('public.sea_conditions_npc_on()') is null then
    raise exception 'PROOF 92 FAIL: 0397 is not in this world';
  end if;
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');

  create temp table m70 on commit drop as
  select nf.fleet_id, nf.route_id, nf.player_id, nf.roster_ord, public.fleet_wave(nf.fleet_id) as wave,
         greatest(coalesce(voyage.fleet_speed_at(nf.fleet_id, 1), 0), 0.1) as speed,
         (select max(cp.size) from public.ships s join public.ship_classes c on c.id = s.class_id join public.class_profile cp on cp.class_code = c.code where s.fleet_id = nf.fleet_id) as size,
         (select st.port_id from public.standing_route_stops st where st.route_id = nf.route_id order by st.ord limit 1) as home
    from public.npc_fleets nf where nf.route_id is not null;

  -- ── SM_DARK ──
  if public.sea_conditions_npc_on() then
    raise exception 'PROOF 92 FAIL: sea_conditions_bite_npc is on as shipped';
  end if;
  select m.* into v_car
    from m70 m
   where m.size = 2 and m.wave < 30
     and exists (select 1 from jsonb_array_elements(public.npc_feasible_legs(m.home, m.fleet_id, m.speed, 400)) x
                  where public.npc_sea_shut(m.wave, (x->>'port_id')::uuid, x->'course') is not null)
     and exists (select 1 from jsonb_array_elements(public.npc_feasible_legs(m.home, m.fleet_id, m.speed, 400)) x
                  where public.npc_sea_shut(m.wave, (x->>'port_id')::uuid, x->'course') is null)
   order by m.roster_ord limit 1;
  if v_car.fleet_id is null then
    raise exception 'PROOF 92 FAIL: no size-2 merchant has both a known leg her hull cannot hold and one it can';
  end if;
  v_dark := public.npc_feasible_legs(v_car.home, v_car.fleet_id, v_car.speed, 400);
  raise notice 'PASS: SM_DARK - the switch ships false; dark, a caravel house (wave %) is offered % known legs, % of them through seas her hull cannot hold',
    v_car.wave, jsonb_array_length(v_dark),
    (select count(*) from jsonb_array_elements(v_dark) x where public.npc_sea_shut(v_car.wave, (x->>'port_id')::uuid, x->'course') is not null);

  -- ── SM_RULE ──
  v_r := public.npc_sea_shut(26, v_hav, v_line);
  if v_r is null or v_r->>'code' <> 'E_SEA_CLOSED' or v_r->'figures'->>'zone' <> 'NOR-MID' or (v_r->'figures'->>'needs_wave')::int <> 30
     or (v_r->'figures'->>'wave')::numeric <> 26 or jsonb_typeof(v_r->'figures'->'title') <> 'null' then
    raise exception 'PROOF 92 FAIL: a wave of 26 on the Lisbon to Havana line is not refused by the Western Ocean on wave alone: %', v_r;
  end if;
  if public.npc_sea_shut(39, v_hav, v_line) is not null then
    raise exception 'PROOF 92 FAIL: a wave of 39 is refused the Lisbon to Havana line: %', public.npc_sea_shut(39, v_hav, v_line);
  end if;
  select count(*), count(*) filter (where public.npc_sea_shut(12, c.to_port, c.course) is null) into v_n, v_x
    from public.npc_courses c
   where public.harbour_zone(c.from_port) in ('NRT-AM', 'STH-AM') and public.harbour_zone(c.to_port) = public.harbour_zone(c.from_port) and c.nm < 800;
  if v_n < 1 or v_x < 1 then
    raise exception 'PROOF 92 FAIL: no short Pacific coast leg holds a wave of 12 (% legs, % open)', v_n, v_x;
  end if;
  raise notice 'PASS: SM_RULE - 26 is refused the Western Ocean (wave 30 asked, no title judged), 39 is not; % of % short Pacific coast legs hold a barca', v_x, v_n;

  -- ── SM_MEMO ──
  select count(*) into v_n
    from public.npc_courses c
   where public.npc_course_zones(c.course) is distinct from public.course_zones(c.course)
      or (select m.zones from public.npc_course_zones_memo m where m.course_md5 = md5(c.course::text)) is distinct from public.course_zones(c.course)
      or (select m.zones from public.npc_course_zones_memo m
           where m.course_md5 = md5((select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(c.course) with ordinality t(x, i))::text))
         is distinct from public.course_zones(c.course);
  if v_n <> 0 then
    raise exception 'PROOF 92 FAIL: % remembered courses disagree with public.course_zones, or are not remembered both ways', v_n;
  end if;
  if exists (select 1 from public.npc_course_zones_memo m where m.course_md5 = md5(v_line::text))
     or public.npc_course_zones(v_line) is distinct from public.course_zones(v_line) then
    raise exception 'PROOF 92 FAIL: a course the memo has not seen is not sampled';
  end if;
  raise notice 'PASS: SM_MEMO - % remembered courses equal the sampler both ways; an unseen course is sampled', (select count(*) from public.npc_courses);

  -- ── LIT ──
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite_npc';
  if not public.sea_conditions_npc_on() then
    raise exception 'PROOF 92 FAIL: the switch was lit and the reader answers false';
  end if;

  -- ── SM_LEGS ──
  v_lit := public.npc_feasible_legs(v_car.home, v_car.fleet_id, v_car.speed, 400);
  if v_lit is distinct from (select jsonb_agg(x order by o) from jsonb_array_elements(v_dark) with ordinality t(x, o)
                              where public.npc_sea_shut(v_car.wave, (x->>'port_id')::uuid, x->'course') is null)
     or jsonb_array_length(v_lit) >= jsonb_array_length(v_dark) then
    raise exception 'PROOF 92 FAIL: lit, the feasible legs are not the dark ones less those her hull cannot hold (% lit, % dark)', jsonb_array_length(v_lit), jsonb_array_length(v_dark);
  end if;
  select count(*), count(*) filter (where public.npc_loop_sea_shut(v_car.fleet_id, c.stops)) into v_n, v_x
    from public.npc_loop_candidates(v_car.route_id, v_car.fleet_id, v_car.home, public.fleet_free_hold(v_car.fleet_id), v_car.speed) c;
  if v_n < 1 or v_x <> 0 then
    raise exception 'PROOF 92 FAIL: lit, % loops are offered to the caravel house and % of them hold a leg her hull cannot hold', v_n, v_x;
  end if;
  raise notice 'PASS: SM_LEGS - lit, % of her % known legs stay, in order; % loops are offered and none crosses a sea her hull cannot hold', jsonb_array_length(v_lit), jsonb_array_length(v_dark), v_n;

  -- ── SM_NAU ──
  select m.*, l.to_port as far into v_nau
    from m70 m
    cross join lateral (select (x->>'port_id')::uuid as to_port from jsonb_array_elements(public.npc_feasible_legs(m.home, m.fleet_id, m.speed, 400)) x
                         where 'NOR-MID' = any (public.npc_course_zones(x->'course')) limit 1) l
   where m.size = 3 and m.wave >= 39
   order by m.roster_ord limit 1;
  if v_nau.fleet_id is null then
    raise exception 'PROOF 92 FAIL: lit, no nau house keeps a known leg across the Western Ocean';
  end if;
  raise notice 'PASS: SM_NAU - lit, a nau house (wave %) keeps her leg across the Western Ocean', v_nau.wave;

  -- ── SM_BARCA ──
  select count(*), count(*) filter (where jsonb_array_length(public.npc_feasible_legs(m.home, m.fleet_id, m.speed, 400)) = 0)
    into v_n, v_x
    from m70 m where m.size = 1;
  if v_n < 1 then
    raise exception 'PROOF 92 FAIL: the world has no small-hull merchant to read';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc';
  select v_x - count(*) into v_x from m70 m where m.size = 1 and jsonb_array_length(public.npc_feasible_legs(m.home, m.fleet_id, m.speed, 400)) = 0;
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite_npc';
  if v_x <> 0 then
    raise exception 'PROOF 92 FAIL: lit, % small-hull houses that had a feasible leg dark have none', v_x;
  end if;
  raise notice 'PASS: SM_BARCA - lit, each of the % small-hull houses that has a feasible leg dark keeps one', v_n;

  -- ── SM_PLAN ──
  -- The subject is a merchant the OLD planner keeps on a loop the sea closes: planned with the switch off she stays on it and buys into it. Found by
  -- planning the docked merchants on such loops one by one, dark, until one stays (at most 40 tries). Then the switch is lit and the same plan is asked again.
  update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null from public.npc_fleets nf where nf.route_id = sr.id;
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc';
  v_x := 0;
  for v_shut in
    select m.* from m70 m join public.fleets f on f.id = m.fleet_id
     where f.status = 'DOCKED' and f.port_id = m.home
       and public.npc_loop_sea_shut(m.fleet_id, (select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord)
                                                   from public.standing_route_stops st where st.route_id = m.route_id))
     order by m.size desc, m.roster_ord limit 40
  loop
    v_x := v_x + 1;
    v_r := public.npc_plan(now(), v_shut.route_id);
    select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord) into v_loop
      from public.standing_route_stops st where st.route_id = v_shut.route_id;
    select count(*) into v_n from public.standing_route_lines l where l.route_id = v_shut.route_id and l.kind = 'BUY';
    exit when public.npc_loop_sea_shut(v_shut.fleet_id, v_loop) and v_n > 0
              and (select f.port_id from public.fleets f where f.id = v_shut.fleet_id) = (v_loop->0->>'port_id')::uuid;
    v_loop := null;
  end loop;
  if v_loop is null then
    raise exception 'PROOF 92 FAIL: of % docked merchants on a loop the sea closes, the old planner kept none on such a loop with a BUY: the proof has no subject', v_x;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite_npc';
  v_r := public.npc_plan(now(), v_shut.route_id);
  select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord) into v_loop
    from public.standing_route_stops st where st.route_id = v_shut.route_id;
  select count(*) into v_n from public.standing_route_lines l where l.route_id = v_shut.route_id and l.kind = 'BUY';
  if coalesce((v_r->>'failed')::int, 1) <> 0 or coalesce((v_r->>'planned')::int, 0) <> 1
     or (public.npc_loop_sea_shut(v_shut.fleet_id, v_loop) and v_n > 0) then
    raise exception 'PROOF 92 FAIL: lit, the planner left a merchant buying into a loop her hull cannot hold, or failed: %, closed %, BUY lines %', v_r, public.npc_loop_sea_shut(v_shut.fleet_id, v_loop), v_n;
  end if;
  raise notice 'PASS: SM_PLAN - dark, the planner kept a merchant (hull size %, wave %) buying on a loop the sea closes (found at try %); lit, the same plan left her on %, BUY lines %',
    v_shut.size, v_shut.wave, v_x, case when public.npc_loop_sea_shut(v_shut.fleet_id, v_loop) then 'that loop with no BUY' else 'a loop her hull can hold' end, v_n;

  -- ── SM_DOOR ──
  select x into v_leg from jsonb_array_elements(v_dark) x where public.npc_sea_shut(v_car.wave, (x->>'port_id')::uuid, x->'course') is not null limit 1;
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  if public.passage_gate(v_car.player_id, v_car.fleet_id, (v_leg->>'nm')::numeric, (v_leg->>'port_id')::uuid, v_leg->'course') is not null
     or public.passage_gate(v_car.player_id, v_car.fleet_id, 999999, null, null) is not null then
    raise exception 'PROOF 92 FAIL: lit, the sail door refuses a merchant: %', public.passage_gate(v_car.player_id, v_car.fleet_id, (v_leg->>'nm')::numeric, (v_leg->>'port_id')::uuid, v_leg->'course');
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  raise notice 'PASS: SM_DOOR - with both switches lit the sail door answers null for a merchant on the very leg the planner calls closed';

  -- ── SM_OFF ──
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc';
  if public.npc_feasible_legs(v_car.home, v_car.fleet_id, v_car.speed, 400) is distinct from v_dark then
    raise exception 'PROOF 92 FAIL: the switch off again, the feasible legs are not what they were';
  end if;
  raise notice 'PASS: SM_OFF - the switch off again: the feasible legs are byte for byte what they were';
end $$;
