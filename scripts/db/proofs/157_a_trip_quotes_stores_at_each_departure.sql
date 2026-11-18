-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 157 — A TRIP'S STORES ARE QUOTED AT THE SPEED OF EACH DEPARTURE  (migration 0454: world.trip_leg asks her speed with the walked casks)
--
--   The fault (recorded 2026-11-16, PR #752): world.trip_cost and Trade's board (world.board_legs) walked every leg of a trip at her speed IN PORT,
--   before any stores were aboard. The SAIL reads her speed twice (cmd.do_sail): before the top-up (public.supply_need: the days she is topped up
--   for) and after it (voyage.depart: the speed she sails the leg at, so the days voyage.settle settles, eats and owes wages for). Laden with her
--   stores she is a shade slower, so a leg that ends just inside a day in port runs into the next one at sea: one more day eaten, one more day
--   owed, and the next leg's casks start emptier, so the next top-up buys more than the quote said.
--
--   This proof builds that case on purpose and sails it. A probe house's barca lies at Lisbon with empty casks; the sea is calmed for this
--   transaction (hazard_p_max 0: no storm, calm or raider moves a day) and the economy is open (no dock fee, no port time). Her first leg is one
--   whose days in port fall just under a whole day count, and her hull is worn (durability, a straight write) until her speed in port leaves
--   that leg inside n days while her speed laden with the leg's own top-up (cmd.do_provision, rolled back) runs it into n + 1. Then
--   world.trip_cost quotes the two-leg trip, cmd.issue_lines queues both SAILs, and every arrival is settled at its own instant.
--
-- @pass STORES_QUOTE_SCENE      the scene: in port her first leg settles n days, laden with its top-up n + 1 (the case the in-port walk missed)
-- @pass STORES_QUOTE_SUPPLIES   the purse fell at the departures by exactly the quote's supplies
-- @pass STORES_QUOTE_WAGES      the wages owed over the trip are exactly the quote's wages
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth constant uuid := '00000000-0454-4000-8000-0000000000aa';
  v_pl     uuid;
  v_fl     uuid;
  v_sh     uuid;
  v_lis    uuid;
  v_base   numeric;
  v_a      text;
  v_b      text;
  v_c1     jsonb;
  v_c2     jsonb;
  v_nm1    numeric;
  v_nm2    numeric;
  v_port   numeric;
  v_laden  numeric;
  v_target numeric;
  v_lo     numeric;
  v_hi     numeric;
  v_mid    numeric;
  v_n      int;
  v_need   record;
  v_trip   jsonb;
  v_r      jsonb;
  v_p      bigint;
  v_q      bigint;
  v_sup    bigint := 0;
  v_owed0  numeric;
  v_owed1  numeric;
  v_voy    record;
  v_codes  text[];
  v_legs_t text := '';
  v_paid   bigint;
  v_settled int;
  k        int;
  i        int;
begin
  -- a calm sea and an open economy, for this transaction only: no day is moved by the weather, no dock fee or port time is in the way
  update public.world_config set value = '0'::jsonb where key = 'hazard_p_max';
  update public.world_config set value = 'false'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (c_auth, 'Casa da Prova 157', (select n.id from public.nations n where n.code = 'PRT'), 100000, false)
  returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Prova', v_lis);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova', true, true);
  select s.id into v_sh from public.ships s where s.fleet_id = v_fl limit 1;
  update public.ships set crew = greatest(crew, 20), water_t = 0, food_t = 0, cargo = '{}'::jsonb where id = v_sh;
  v_base := (public.ship_base(v_sh)).durability;
  perform cmd.assume_identity(c_auth);
  v_port := voyage.fleet_speed(v_fl);

  -- HER FIRST LEG: from Lisbon, the one whose days in port lie closest under a whole day count (the least wear brings it to the edge), at least
  -- one day; her second: from there, the shortest leg on with a course (not back to Lisbon)
  select q.code, q.course, q.nm into v_a, v_c1, v_nm1
    from (select p.code, proof.course('LIS', p.code) as course from public.ports p where p.kind = 'HARBOUR' and p.code <> 'LIS') c
   cross join lateral (select c.code, c.course, (select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(c.course)) s) as nm) q
   where c.course is not null and q.nm / 24 / v_port >= 1.05
     and ceil(q.nm / 24 / v_port) - q.nm / 24 / v_port >= 0.01 * ceil(q.nm / 24 / v_port)   -- room for half a top-up's slowing
   order by ceil(q.nm / 24 / v_port) - q.nm / 24 / v_port, q.code
   limit 1;
  select q.code, q.course, q.nm into v_b, v_c2, v_nm2
    from (select p.code, proof.course(v_a, p.code) as course from public.ports p where p.kind = 'HARBOUR' and p.code not in ('LIS', v_a)) c
   cross join lateral (select c.code, c.course, (select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(c.course)) s) as nm) q
   where c.course is not null
   order by q.nm, q.code
   limit 1;
  if v_a is null or v_b is null then
    raise exception 'PROOF 157 FAIL: no two-leg trip from Lisbon with a course for each leg';
  end if;
  v_n := ceil(v_nm1 / 24 / v_port);

  -- HOW MUCH SLOWER HER LEG-ONE TOP-UP MAKES HER (cmd.do_provision, the SAIL's own top-up, rolled back to a savepoint)
  begin
    select * into v_need from public.supply_need(v_fl, v_nm1);
    perform cmd.do_provision(v_fl, jsonb_build_object('mode', 'DAYS', 'days', v_need.days, 'on_credit', true));
    v_laden := voyage.fleet_speed(v_fl);
    raise exception sqlstate 'BV157';
  exception when sqlstate 'BV157' then
    null;
  end;
  -- THE EDGE: her speed in port a hair over the speed that sails the leg in exactly n days, by half of what the top-up takes off; the hull worn to it
  v_target := v_nm1 / 24 / v_n * (1 + (v_port / v_laden - 1) / 2);
  if v_target > v_port then
    raise exception 'PROOF 157 FAIL: the leg to % (% nm, % d in port) cannot be brought to the edge by wear', v_a, round(v_nm1, 1), round(v_nm1 / 24 / v_port, 3);
  end if;
  v_lo := 0;
  v_hi := v_base;
  for i in 1 .. 40 loop
    v_mid := (v_lo + v_hi) / 2;
    update public.ships set durability = v_mid where id = v_sh;
    if voyage.fleet_speed(v_fl) >= v_target then v_hi := v_mid; else v_lo := v_mid; end if;
  end loop;
  update public.ships set durability = v_hi where id = v_sh;
  v_port := voyage.fleet_speed(v_fl);
  begin
    select * into v_need from public.supply_need(v_fl, v_nm1);
    perform cmd.do_provision(v_fl, jsonb_build_object('mode', 'DAYS', 'days', v_need.days, 'on_credit', true));
    v_laden := voyage.fleet_speed(v_fl);
    raise exception sqlstate 'BV157';
  exception when sqlstate 'BV157' then
    null;
  end;
  if ceil(v_nm1 / 24 / v_port) <> v_n or ceil(v_nm1 / 24 / v_laden) <> v_n + 1 then
    raise exception 'PROOF 157 FAIL: the scene did not form: leg to % is % nm, % d in port at %, % d laden at %', v_a, round(v_nm1, 1),
      round(v_nm1 / 24 / v_port, 4), v_port, round(v_nm1 / 24 / v_laden, 4), v_laden;
  end if;
  raise notice 'PASS: STORES_QUOTE_SCENE — LIS to % (% nm) then % (% nm): in port at % kn the first leg is % d (settles %), laden with its top-up at % kn % d (settles %)',
    v_a, round(v_nm1, 1), v_b, round(v_nm2, 1), v_port, round(v_nm1 / 24 / v_port, 4), v_n, v_laden, round(v_nm1 / 24 / v_laden, 4), v_n + 1;

  -- THE QUOTE, before she leaves (the legs measured from the very courses she sails)
  v_trip := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_a, 'course', v_c1),
                                                     jsonb_build_object('from', v_a, 'to', v_b, 'course', v_c2)));
  if (v_trip->>'supplies') is null or (v_trip->>'wages') is null then
    raise exception 'PROOF 157 FAIL: world.trip_cost priced nothing: %', v_trip;
  end if;
  select coalesce(sum(w.owed), 0) into v_owed0 from public.fleet_wages w where w.fleet_id = v_fl;
  select ducats into v_p from public.players where id = v_pl;

  -- THE TRIP, queued whole
  v_r := cmd.issue_lines(v_fl, jsonb_build_array(jsonb_build_object('text', 'SAIL ' || v_a, 'path', v_c1), jsonb_build_object('text', 'SAIL ' || v_b, 'path', v_c2)), null);
  if (v_r->>'ok')::boolean is not true or exists (select 1 from jsonb_array_elements(v_r->'orders') o where o->>'status' in ('failed', 'cancelled')) then
    raise exception 'PROOF 157 FAIL: the two SAILs were not queued: %', v_r;
  end if;
  v_codes := array[v_a, v_b];
  for k in 1 .. 2 loop
    if (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
      raise exception 'PROOF 157 FAIL: leg % did not leave', k;
    end if;
    select ducats into v_q from public.players where id = v_pl;
    v_paid := v_p - v_q;
    v_sup := v_sup + v_paid;
    v_p := v_q;
    select v.id, v.eta into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
    v_settled := voyage.total_days(v_voy.id);
    for i in 1 .. 30 loop
      exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING'
             or (select v.status from public.voyages v where v.id = v_voy.id) <> 'SAILING';
      perform voyage.settle(v_fl, (select v.eta from public.voyages v where v.id = v_voy.id));
    end loop;
    if (select v.status from public.voyages v where v.id = v_voy.id) = 'SAILING'
       or (select coalesce(v.delay_hours, 0) from public.voyages v where v.id = v_voy.id) <> 0 then
      raise exception 'PROOF 157 FAIL: leg % to % did not end on a calm sea', k, v_codes[k];
    end if;
    if k = 2 and (select f.status from public.fleets f where f.id = v_fl) = 'SAILING' then
      raise exception 'PROOF 157 FAIL: she sailed on past %', v_b;
    end if;
    v_legs_t := v_legs_t || format('%sleg %s: stores %s, settled %s d at %s kn', case when k > 1 then '; ' end, k, v_paid, v_settled,
      (select round((v.speed_profile ->> 0)::numeric, 4) from public.voyages v where v.id = v_voy.id));
    select ducats into v_q from public.players where id = v_pl;
    if v_q <> v_p and k = 2 then
      raise exception 'PROOF 157 FAIL: the arrival at % moved the purse by % with the economy open', v_b, v_p - v_q;
    end if;
  end loop;
  if (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fl) is distinct from v_b then
    raise exception 'PROOF 157 FAIL: she did not make %', v_b;
  end if;

  if v_sup <> (v_trip->>'supplies')::bigint then
    raise exception 'PROOF 157 FAIL: the supplies cost % over the trip and the quote said % (%; quote %)', v_sup, v_trip->>'supplies', v_legs_t, v_trip;
  end if;
  raise notice 'PASS: STORES_QUOTE_SUPPLIES — % over 2 departures, as quoted (%)', v_sup, v_legs_t;

  select coalesce(sum(w.owed), 0) into v_owed1 from public.fleet_wages w where w.fleet_id = v_fl;
  if round(v_owed1 - v_owed0) <> (v_trip->>'wages')::numeric then
    raise exception 'PROOF 157 FAIL: she owes her crew % for the trip and the quote said % (%)', round(v_owed1 - v_owed0), v_trip->>'wages', v_legs_t;
  end if;
  raise notice 'PASS: STORES_QUOTE_WAGES — % owed, as quoted', round(v_owed1 - v_owed0);
end
$$;
