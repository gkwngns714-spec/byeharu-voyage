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
--   far   : (hold >= npc_route_far_hold_tuns) out-and-back on the npc_route_far_candidates
--           farthest known legs of npc_route_far_nm or more; her harbour having none, via each
--           neighbour's farthest such leg (home -> X -> F -> X -> home).
declare
  v_near    int     := public.wc_int('npc_route_neighbours');
  v_farn    int     := public.wc_int('npc_route_far_candidates');
  v_far_nm  numeric := public.wc_num('npc_route_far_nm');
  v_far_hld numeric := public.wc_num('npc_route_far_hold_tuns');
  v_max     int     := public.wc_int('npc_route_candidates');
  v_days_cap int;
  v_capacity numeric;
  v_crew    int;
  v_preset  int;
  v_stores  numeric;
  v_home    jsonb;
  v_legs    jsonb;
  v_nearset jsonb;
  v_farset  jsonb;
  v_cache   jsonb := '{}'::jsonb;
  v_out     int := 0;
  v_room    int;
  b         jsonb;
  c         jsonb;
  v_ret     jsonb;
  v_bc      jsonb;
  v_three   jsonb := '[]'::jsonb;
  t         jsonb;
  v_xf      jsonb;
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
  if p_hold >= v_far_hld then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_farset
      from (select x from jsonb_array_elements(v_legs) x where (x->>'nm')::numeric >= v_far_nm
             order by (x->>'nm')::numeric desc, x->>'port_id' limit v_farn) z;
  else
    v_farset := '[]'::jsonb;
  end if;

  -- OUT AND BACK, near then far. The way back is a known leg of the destination's.
  for b in select x from jsonb_array_elements(v_nearset || v_farset) x loop
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
    kind := case when (b->>'nm')::numeric >= v_far_nm then 'far' else 'near' end;
    v_out := v_out + 1;
    return next;
  end loop;

  -- FAR VIA A NEIGHBOUR, when her own harbour has no long haul: home -> X -> F -> X -> home.
  if p_hold >= v_far_hld and jsonb_array_length(v_farset) = 0 then
    for b in select x from jsonb_array_elements(v_nearset) x loop
      exit when v_out >= v_max - 1 or v_farn <= 0;
      select x into v_xf from jsonb_array_elements(v_cache->(b->>'port_id')) x
       where (x->>'nm')::numeric >= v_far_nm order by (x->>'nm')::numeric desc, x->>'port_id' limit 1;
      continue when v_xf is null;
      if not v_cache ? (v_xf->>'port_id') then
        v_cache := v_cache || jsonb_build_object(v_xf->>'port_id',
                     public.npc_feasible_legs((v_xf->>'port_id')::uuid, p_speed, v_days_cap));
      end if;
      select x into v_fx from jsonb_array_elements(v_cache->(v_xf->>'port_id')) x where x->>'port_id' = b->>'port_id';
      select x into v_ret from jsonb_array_elements(v_cache->(b->>'port_id')) x where x->>'port_id' = p_home::text;
      continue when v_fx is null or v_ret is null;
      stops := jsonb_build_array(
        v_home || jsonb_build_object('course', b->'course', 'nm', b->'nm'),
        jsonb_build_object('port_id', b->'port_id', 'code', b->'code', 'course', v_xf->'course', 'nm', v_xf->'nm'),
        jsonb_build_object('port_id', v_xf->'port_id', 'code', v_xf->'code', 'course', v_fx->'course', 'nm', v_fx->'nm'),
        jsonb_build_object('port_id', b->'port_id', 'code', b->'code', 'course', v_ret->'course', 'nm', v_ret->'nm'));
      kind := 'far';
      v_out := v_out + 1;
      v_farn := v_farn - 1;
      return next;
    end loop;
  end if;

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

