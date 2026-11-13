-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 95 - A MERCHANT KEEPS HER HOME WATERS  (migration 0400; the merchants' side of 0396's home waters; owner rows 166, 324)
--
--   0400's self-assert reads the catalog and pure figures only. This proof plays THE PROD CASE on the world's own merchants, rolled back with proof.mjs's
--   transaction: a merchant homed in a far sea whose hull is too weak for every sea about her (her hull is changed to a fusta, wave 6, here: the eight on
--   prod are that shape), then the real readers and the real planner at her lap start, dark and lit.
--
-- @pass MH_DARK       the switch off: the weak merchant is still offered every known leg her stores allow, the ones her hull cannot hold among them; the plain rule (0397) refuses every one of them
-- @pass MH_HOME       lit: she keeps the known legs that stay in seas of her home's rank and ask no more wave than her home's sea; without the floor she would keep none
-- @pass MH_OTHER      lit: a leg that touches a sea of ANOTHER rank asking more than her hull is not offered; her floors raise her wave nowhere else
-- @pass MH_LAP_START  lit: the real planner (public.npc_plan) at her lap start does not lay her up and leaves her on a loop with no leg her floors do not hold; the guard read counts her as a merchant WITH an open leg
-- @pass MH_STRONG     lit: a merchant whose hull holds every sea of her loop is offered the same legs as under 0397's plain rule (the floors take nothing away and add nothing she lacked)
-- @pass MH_OFF        the switch off again: her legs are byte for byte the dark ones
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_m      record;
  v_s      record;
  v_fl     record;
  v_dark   jsonb;
  v_lit    jsonb;
  v_r      jsonb;
  v_n      int;
  v_fusta  uuid := (select id from public.ship_classes where code = 'fusta');
begin
  if to_regprocedure('public.npc_sea_floor(uuid)') is null then
    raise exception 'PROOF 95 FAIL: 0400 is not in this world';
  end if;
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc';

  -- THE MERCHANT: homed in a sea of a far rank that asks more wave than a fusta holds, with the most known legs inside seas of that rank
  select nf.fleet_id, nf.route_id, nf.player_id, st.port_id as home, z.code as zone, z.title_min, z.wave_min into v_m
    from public.npc_fleets nf
    join lateral (select s.port_id from public.standing_route_stops s where s.route_id = nf.route_id order by s.ord limit 1) st on true
    join public.sea_leg_asks a on a.from_port = st.port_id and a.to_port = st.port_id
    join public.sea_zones z on z.code = a.zones[1]
    join public.fleets f on f.id = nf.fleet_id and f.port_id = st.port_id and f.status = 'DOCKED'
   where nf.route_id is not null and z.title_min >= 4 and z.wave_min > 6
   order by (select count(*) from public.sea_leg_asks x join public.sea_zones zx on zx.code = x.zones[1]
              where x.from_port = st.port_id and x.to_port <> st.port_id and zx.title_min = z.title_min) desc, nf.roster_ord
   limit 1;
  if v_m.fleet_id is null or v_fusta is null then
    raise exception 'PROOF 95 FAIL: the world has no merchant lying at a home in a far sea, or no fusta';
  end if;
  update public.ships set class_id = v_fusta where fleet_id = v_m.fleet_id;
  if public.fleet_wave(v_m.fleet_id) >= v_m.wave_min then
    raise exception 'PROOF 95 FAIL: a fusta holds % and her home sea asks only %', public.fleet_wave(v_m.fleet_id), v_m.wave_min;
  end if;
  select * into v_fl from public.npc_sea_floor(v_m.fleet_id);
  if v_fl.home_title is distinct from v_m.title_min or v_fl.home_wave is distinct from v_m.wave_min or v_fl.lie_title is distinct from v_m.title_min
     or v_fl.wave is distinct from public.fleet_wave(v_m.fleet_id) then
    raise exception 'PROOF 95 FAIL: her floors % are not her home sea''s asks (% / %)', to_jsonb(v_fl), v_m.title_min, v_m.wave_min;
  end if;

  -- ── MH_DARK ──
  v_dark := public.npc_feasible_legs(v_m.home, v_m.fleet_id, 5, 400);
  if jsonb_array_length(v_dark) < 2
     or exists (select 1 from jsonb_array_elements(v_dark) x where public.npc_sea_shut(v_fl.wave, (x ->> 'port_id')::uuid, x -> 'course') is null) then
    raise exception 'PROOF 95 FAIL: dark, she is offered % legs, or the plain rule holds one of them for a hull of %', jsonb_array_length(v_dark), v_fl.wave;
  end if;
  raise notice 'PASS: MH_DARK — dark, a fusta (wave %) homed in % (asks %) is offered % known legs; the plain rule refuses every one', v_fl.wave, v_m.zone, v_m.wave_min, jsonb_array_length(v_dark);

  -- ── MH_HOME ──
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite_npc';
  v_lit := public.npc_feasible_legs(v_m.home, v_m.fleet_id, 5, 400);
  if jsonb_array_length(v_lit) < 1
     or exists (select 1 from jsonb_array_elements(v_lit) x
                 where exists (select 1 from public.sea_zones z
                                where z.code = any (public.npc_course_zones(x -> 'course') || array_remove(array[public.harbour_zone((x ->> 'port_id')::uuid)], null))
                                  and (z.wave_min > v_fl.wave and (z.title_min <> v_m.title_min or z.wave_min > v_m.wave_min))))
     or exists (select 1 from jsonb_array_elements(v_lit) x where not (v_dark @> jsonb_build_array(x))) then
    raise exception 'PROOF 95 FAIL: lit, her legs are % of the dark %: none, or one that touches a sea her floors do not hold, or one that was not offered dark', jsonb_array_length(v_lit), jsonb_array_length(v_dark);
  end if;
  raise notice 'PASS: MH_HOME — lit, she keeps % of her % known legs: every one stays in seas of rank % asking no more than %; the plain rule would leave her none', jsonb_array_length(v_lit), jsonb_array_length(v_dark), v_m.title_min, v_m.wave_min;

  -- ── MH_OTHER ──
  select count(*) into v_n from jsonb_array_elements(v_dark) x
   where exists (select 1 from public.sea_zones z
                  where z.code = any (public.npc_course_zones(x -> 'course') || array_remove(array[public.harbour_zone((x ->> 'port_id')::uuid)], null))
                    and z.wave_min > v_fl.wave and (z.title_min <> v_m.title_min or z.wave_min > v_m.wave_min));
  if v_n <> jsonb_array_length(v_dark) - jsonb_array_length(v_lit) then
    raise exception 'PROOF 95 FAIL: % dark legs touch a sea her floors do not hold, and % were taken away', v_n, jsonb_array_length(v_dark) - jsonb_array_length(v_lit);
  end if;
  raise notice 'PASS: MH_OTHER — the % legs taken away are exactly those that touch a sea of another rank, or of her rank asking more than her home''s sea', v_n;

  -- ── MH_LAP_START ──
  update public.standing_routes sr set fleet_id = v_m.fleet_id, lap_id = null, paused_reason = null where sr.id = v_m.route_id;
  v_r := public.npc_plan(now(), v_m.route_id);
  if (select sr.paused_reason from public.standing_routes sr where sr.id = v_m.route_id) is not null
     or public.npc_loop_sea_shut(v_m.fleet_id, (select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord)
                                                 from public.standing_route_stops st where st.route_id = v_m.route_id))
     or (public.sea_conditions_npc_ready() ->> 'merchants_with_no_open_leg')::int <> 0 then
    raise exception 'PROOF 95 FAIL: lit, the planner at her lap start: plan %, paused %, her loop still has a leg she cannot hold, or the guard counts her without a leg (%)',
      v_r, (select sr.paused_reason from public.standing_routes sr where sr.id = v_m.route_id), public.sea_conditions_npc_ready();
  end if;
  raise notice 'PASS: MH_LAP_START — lit, the real planner at her lap start leaves her sailing a loop her floors hold, not laid up; the guard reads no merchant without an open leg';

  -- ── MH_STRONG ──
  select nf.fleet_id, st.port_id as home into v_s
    from public.npc_fleets nf
    join lateral (select s.port_id from public.standing_route_stops s where s.route_id = nf.route_id order by s.ord limit 1) st on true
   where nf.route_id is not null and nf.fleet_id <> v_m.fleet_id and public.fleet_wave(nf.fleet_id) >= 39
   order by nf.roster_ord limit 1;
  v_r := public.npc_feasible_legs(v_s.home, v_s.fleet_id, 5, 400);
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc';
  if v_s.fleet_id is null
     or v_r is distinct from (select coalesce(jsonb_agg(x order by (x ->> 'nm')::numeric, x ->> 'port_id'), '[]'::jsonb)
                                from jsonb_array_elements(public.npc_feasible_legs(v_s.home, v_s.fleet_id, 5, 400)) x
                               where public.npc_sea_shut(public.fleet_wave(v_s.fleet_id), (x ->> 'port_id')::uuid, x -> 'course') is null
                                  or exists (select 1 from public.npc_sea_floor(v_s.fleet_id) w
                                              where public.npc_sea_shut(w.wave, (x ->> 'port_id')::uuid, x -> 'course', w.lie_title, w.lie_wave, w.home_title, w.home_wave) is null)) then
    raise exception 'PROOF 95 FAIL: lit, a nau house''s legs are not the dark ones less those neither rule holds';
  end if;
  raise notice 'PASS: MH_STRONG — lit, a nau house is offered % legs: the dark ones less those her hull and her floors do not hold', jsonb_array_length(v_r);

  -- ── MH_OFF ──
  if public.npc_feasible_legs(v_m.home, v_m.fleet_id, 5, 400) is distinct from v_dark then
    raise exception 'PROOF 95 FAIL: the switch off again, her legs are not the dark ones';
  end if;
  raise notice 'PASS: MH_OFF — the switch off again: her % legs are the dark ones, byte for byte', jsonb_array_length(v_dark);
end $$;
