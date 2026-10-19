CREATE OR REPLACE FUNCTION public.npc_loop_candidates(p_route uuid, p_fleet uuid, p_home uuid, p_hold numeric, p_speed numeric)
 RETURNS TABLE(stops jsonb, kind text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- The loops a merchant may price at a lap start, each a jsonb array of stops
-- [{port_id, code, course, nm}, …] whose stop i's course is the leg to stop i + 1 (the last leg
-- returns home). Bounded by the knobs; every destination must be an open harbour (0139: any hull
-- enters any harbour) within the days of stores she can carry. Deterministic (ties fall to the port id).
--   near  : out-and-back to each of the npc_route_neighbours nearest known harbours;
--   near3 : home -> B -> C -> home where B and C are neighbours and the roster knows B -> C,
--           the shortest first, filling what npc_route_candidates leaves;
--   trade : 0186 (the owner, 2026-10-18: "why is there a route that has no profit? this is design
--           defect") LOOPS BUILT FROM PAYING TRADES, for every hull: out-and-back to the
--           npc_route_trade_candidates harbours where the goods her harbour makes sell for the most
--           over what they cost here, and the way back pays the same way — ranked by THE distance
--           premium (port_goods.haul, 0173's one derivation) both ways, over every feasible known leg of hers (home -> D -> home) and every known leg of npc_route_far_nm or
--           more out of a neighbour (home -> X -> D -> X -> home). The leg planner
--           (public.npc_leg_lines, through npc_plan) prices each, and only a loop that pays is sailed.
--           Replaces 0120's 'far' (the farthest legs, and only for a hold of 200 tuns or more: a far
--           city pays by the unit, so a small hull is paid there too).
declare
  v_near    int     := public.wc_int('npc_route_neighbours');
  v_tradn   int     := public.wc_int('npc_route_trade_candidates');   -- 0186
  v_far_nm  numeric := public.wc_num('npc_route_far_nm');
  v_max     int     := public.wc_int('npc_route_candidates');
  v_days_cap int;
  v_capacity numeric;
  v_crew    int;
  v_preset  int;
  v_stores  numeric;
  v_home    jsonb;
  v_legs    jsonb;
  v_nearset jsonb;
  v_dests   jsonb := '[]'::jsonb;   -- 0186: every destination a trade loop may make, with its way there
  v_xd      jsonb;                 -- 0186
  v_cache   jsonb := '{}'::jsonb;
  v_out     int := 0;
  v_room    int;
  b         jsonb;
  c         jsonb;
  v_ret     jsonb;
  v_bc      jsonb;
  v_three   jsonb := '[]'::jsonb;
  t         jsonb;
  v_fx      jsonb;
begin
  select coalesce(sum(public.ship_hold_capacity(s.id)), 0), coalesce(sum(s.crew), 0)
    into v_capacity, v_crew
    from public.ships s join public.ship_classes cl on cl.id = s.class_id where s.fleet_id = p_fleet;
  select pr.days into v_preset
    from public.fleets f join public.provision_presets pr on pr.id = f.provision_preset_id where f.id = p_fleet;
  v_stores   := v_crew * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day'));
  -- THE DAYS SHE CAN CARRY: her preset as it stands, or what the planner may raise it to — the knob,
  -- and never more than half her hold in stores.
  v_days_cap := greatest(coalesce(v_preset, 0),
                         least(public.wc_int('npc_preset_days_max'),
                               coalesce(floor(0.5 * v_capacity / nullif(v_stores, 0))::int, 0)));
  select jsonb_build_object('port_id', p.id, 'code', p.code) into v_home from public.ports p where p.id = p_home;

  -- the feasible known legs out of a harbour, read once per harbour this call touches
  v_legs := public.npc_feasible_legs(p_home, p_speed, v_days_cap);
  v_cache := jsonb_build_object(p_home::text, v_legs);

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_nearset
    from (select x from jsonb_array_elements(v_legs) x where (x->>'nm')::numeric < v_far_nm
           order by (x->>'nm')::numeric, x->>'port_id' limit v_near) z;

  -- OUT AND BACK to the nearest. The way back is a known leg of the destination's.
  for b in select x from jsonb_array_elements(v_nearset) x loop
    exit when v_out >= v_max - 1;
    if not v_cache ? (b->>'port_id') then
      v_cache := v_cache || jsonb_build_object(b->>'port_id',
                   public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap));
    end if;
    select x into v_ret from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = p_home::text;
    continue when v_ret is null;
    stops := jsonb_build_array(v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
                              jsonb_build_object('port_id', b->'port_id', 'code', b->'code',
                                                 'course', v_ret->'course', 'nm', v_ret->'nm'));
    kind := 'near';
    v_out := v_out + 1;
    return next;
  end loop;

  -- 0186: TRADE LOOPS. Every destination she can reach on known legs that is not a near loop
  -- already: directly (home -> D), or for a long haul through a neighbour (home -> X -> D, D
  -- npc_route_far_nm or more from X).
  for b in select x from jsonb_array_elements(v_legs) x loop
    continue when v_nearset @> jsonb_build_array(jsonb_build_object('port_id', b->'port_id'));
    v_dests := v_dests || jsonb_build_object('d', b->'port_id', 'out', b);
  end loop;
  for b in select x from jsonb_array_elements(v_nearset) x loop
    continue when not v_cache ? (b->>'port_id');
    for v_xd in select x from jsonb_array_elements(v_cache->(b->>'port_id')) x
                 where (x->>'nm')::numeric >= v_far_nm and x->>'port_id' <> p_home::text loop
      continue when v_dests @> jsonb_build_array(jsonb_build_object('d', v_xd->'port_id'));
      v_dests := v_dests || jsonb_build_object('d', v_xd->'port_id', 'x', b, 'out', v_xd);
    end loop;
  end loop;
  -- THE RANK, by the distance premium (port_goods.haul, 0173's one derivation — haul_nm 0 is a city that
  -- makes the good): the best haul any good her harbour makes fetches at D, plus the best haul any good D
  -- makes fetches here — the way back carries a paying good where one exists. One read of the two
  -- market rows per good, for every destination at once. Then, best first, the way back is found (a known
  -- leg D -> home, or D -> X -> home) and the first npc_route_trade_candidates loops are offered; the leg
  -- planner (through npc_plan) says whether each pays.
  for t in
    select dd.x
      from jsonb_array_elements(v_dests) dd(x)
      left join lateral (
        select max(case when ph.haul_nm = 0 then pd.haul end) as out_haul,
               max(case when pd.haul_nm = 0 then ph.haul end) as back_haul
          from public.port_goods pd
          join public.port_goods ph on ph.port_id = p_home and ph.good_id = pd.good_id
         where pd.port_id = (dd.x->>'d')::uuid and (ph.haul_nm = 0 or pd.haul_nm = 0)) hh on true
     order by coalesce(hh.out_haul, 1) + coalesce(hh.back_haul, 1) desc, dd.x->>'d'
  loop
    exit when v_tradn <= 0 or v_out >= v_max - 1;
    if not v_cache ? (t->>'d') then
      v_cache := v_cache || jsonb_build_object(t->>'d', public.npc_feasible_legs((t->>'d')::uuid, p_speed, v_days_cap));
    end if;
    if t ? 'x' then
      select x into v_fx from jsonb_array_elements(v_cache->(t->>'d')) x where x->>'port_id' = t->'x'->>'port_id';
      select x into v_ret from jsonb_array_elements(v_cache->(t->'x'->>'port_id')) x where x->>'port_id' = p_home::text;
      continue when v_fx is null or v_ret is null;
      stops := jsonb_build_array(
        v_home || jsonb_build_object('course', t->'x'->'course', 'nm', t->'x'->'nm'),
        jsonb_build_object('port_id', t->'x'->'port_id', 'code', t->'x'->'code', 'course', t->'out'->'course', 'nm', t->'out'->'nm'),
        jsonb_build_object('port_id', t->'out'->'port_id', 'code', t->'out'->'code', 'course', v_fx->'course', 'nm', v_fx->'nm'),
        jsonb_build_object('port_id', t->'x'->'port_id', 'code', t->'x'->'code', 'course', v_ret->'course', 'nm', v_ret->'nm'));
    else
      select x into v_ret from jsonb_array_elements(v_cache->(t->>'d')) x where x->>'port_id' = p_home::text;
      continue when v_ret is null;
      stops := jsonb_build_array(v_home || jsonb_build_object('course', t->'out'->'course', 'nm', t->'out'->'nm'),
                                jsonb_build_object('port_id', t->'out'->'port_id', 'code', t->'out'->'code',
                                                   'course', v_ret->'course', 'nm', v_ret->'nm'));
    end if;
    kind := 'trade';
    v_out := v_out + 1;
    v_tradn := v_tradn - 1;
    return next;
  end loop;

  -- THREE STOPS among the neighbours, the shortest first, into the room that is left.
  v_room := v_max - 1 - v_out;
  if v_room > 0 then
    for b in select x from jsonb_array_elements(v_nearset) x loop
      for c in select x from jsonb_array_elements(v_nearset) x loop
        continue when c->>'port_id' = b->>'port_id';
        select x into v_bc from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = c->>'port_id';
        continue when v_bc is null;
        select x into v_ret from jsonb_array_elements(v_cache->(c->>'port_id')) x where x->>'port_id' = p_home::text;
        continue when v_ret is null;
        v_three := v_three || jsonb_build_object(
          'nm', (b->>'nm')::numeric + (v_bc->>'nm')::numeric + (v_ret->>'nm')::numeric,
          'loop', jsonb_build_array(
            v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
            jsonb_build_object('port_id', b->'port_id', 'code', b->'code', 'course', v_bc->'course', 'nm', v_bc->'nm'),
            jsonb_build_object('port_id', c->'port_id', 'code', c->'code', 'course', v_ret->'course', 'nm', v_ret->'nm')));
      end loop;
    end loop;
    for t in select x from jsonb_array_elements(v_three) x
              order by (x->>'nm')::numeric, x->'loop'->1->>'port_id', x->'loop'->2->>'port_id' limit v_room loop
      stops := t->'loop';
      kind := 'near3';
      return next;
    end loop;
  end if;
  return;
end $function$

