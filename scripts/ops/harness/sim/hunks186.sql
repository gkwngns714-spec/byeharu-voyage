begin transaction read only;
select json_agg(json_build_array(fn, n, (length(d) - length(replace(d, old, ''))) / length(old)) order by fn, n)
  from (select v.fn, v.n, v.old, replace(pg_get_functiondef(v.fn::regprocedure), E'', '') d from (values ('public.npc_plan(timestamp with time zone,uuid)', 1, $o0$--   * Nothing pays on any leg of the loop written: it is written as it stands — SELL at a profit at
--     every stop and no BUY. Counted `ballast`.$o0$),
('public.npc_plan(timestamp with time zone,uuid)', 2, $o1$  v_aboard  numeric;       -- 0181: the tuns she carries now (public.ship_cargo_tuns)
$o1$),
('public.npc_plan(timestamp with time zone,uuid)', 3, $o2$      -- 0115: Nothing pays: the loop is written as it stands — SELL at a profit at every stop and no
      -- BUY. Counted `ballast`.
      if not v_any then
        v_laid := v_laid + 1;
      end if;
$o2$),
('public.npc_plan(timestamp with time zone,uuid)', 4, $o3$      if not v_any and v_choose and not v_off and coalesce(v_aboard, 0) <= 0 then$o3$),
('public.npc_plan(timestamp with time zone,uuid)', 5, $o4$'No cargo pays on any leg of her loops at present; she waits in port.'$o4$),
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 1, $o5$--   far   : (hold >= npc_route_far_hold_tuns) out-and-back on the npc_route_far_candidates
--           farthest known legs of npc_route_far_nm or more; her harbour having none, via each
--           neighbour's farthest such leg (home -> X -> F -> X -> home).
$o5$),
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 2, $o6$  v_farn    int     := public.wc_int('npc_route_far_candidates');
  v_far_nm  numeric := public.wc_num('npc_route_far_nm');
  v_far_hld numeric := public.wc_num('npc_route_far_hold_tuns');
$o6$),
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 3, $o7$  v_farset  jsonb;
$o7$),
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 4, $o8$  if p_hold >= v_far_hld then
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

$o8$),
('public.npc_loop_candidates(uuid,uuid,uuid,numeric,numeric)', 5, $o9$  v_xf      jsonb;
  v_fx      jsonb;
$o9$)) v(fn, n, old)) z;
rollback;
