begin transaction read only;
select json_agg(json_build_array(fn, n, (length(d) - length(replace(d, old, ''))) / length(old)) order by fn, n)
  from (select v.fn, v.n, v.old, replace(pg_get_functiondef(v.fn::regprocedure), E'', '') d from (values ('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 1, $o0$  v_notes   jsonb := '[]'::jsonb;
  v_built   int := 0;   -- 0180 (d): hulls she laid down this hour
  v_waiting int := 0;   -- 0181: laid up in port, nothing on her loops paying
$o0$),
('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 2, $o1$      -- 0180 (d): SHE SPENDS HER SURPLUS ON HER FLEET — lying docked at a build yard while her house
      -- stands above her purse ceiling, one hull (public.npc_build_for: the players' doors, paid into
      -- this city). Budgeted like the dear work above.
      if f.status = 'DOCKED' and not public.npc_upkeep_spent() then
        v_res := public.npc_build_for(r.fleet_id, p_now);
        if v_res is not null then
          v_built := v_built + coalesce((v_res->>'built')::int, 0);
          v_notes := v_notes || (jsonb_build_object('route', sr.name) || v_res);
        end if;
      end if;

      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
$o1$),
('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 3, $o2$                            'built', v_built,   -- 0180 (d)
                            'waiting', v_waiting,   -- 0181
$o2$),
('public.npc_tend_houses(timestamp with time zone)', 1, $o3$  v_inv      jsonb := '{}'::jsonb;
  v_ceil     jsonb := '{}'::jsonb;   -- 0180 (a): the purse ceiling's pass
$o3$),
('public.npc_tend_houses(timestamp with time zone)', 2, $o4$    v_notes := v_notes || coalesce(v_inv->'notes', '[]'::jsonb);
  end if;

  -- 0180 (a): ABOVE HER PURSE CEILING, the rest goes to the cities of her loop (public.npc_give_above_ceiling).
  if v_on then
    v_ceil := public.npc_give_above_ceiling(p_now);
    v_deferred := v_deferred + coalesce((v_ceil->>'deferred')::int, 0);
    v_failed := v_failed + coalesce((v_ceil->>'failed')::int, 0);
    v_notes := v_notes || coalesce(v_ceil->'notes', '[]'::jsonb);
  end if;
$o4$),
('public.npc_tend_houses(timestamp with time zone)', 3, $o5$                            'donated', coalesce((v_inv->>'donated')::int, 0),   -- 0145
                            'ceiling', coalesce((v_ceil->>'ceiling')::int, 0),   -- 0180 (a)
                            'ceiling_given', coalesce((v_ceil->>'given')::bigint, 0) + coalesce((v_ceil->>'shares')::bigint, 0),
$o5$),
('public.npc_tend_sum(jsonb,jsonb)', 1, $o6$                             'built', 'ceiling', 'ceiling_given', 'waiting'] loop   -- 0145: donated; 0180: built, ceiling, ceiling_given; 0181: waiting
$o6$),
('public.made_only_in(text,uuid)', 1, $o7$  return coalesce(
$o7$),
('world.building_yard(uuid)', 1, $o8$                     and yw.held is null,                                                -- 0165: and, a famous ship, not one it keeps
$o8$),
('world.building_yard(uuid)', 2, $o9$        || case when yw.held is null then '{}'::jsonb else jsonb_build_object('famous_held', yw.held) end
$o9$),
('world.building_yard(uuid)', 3, $o10$                                 public.famous_held(v_player, c.code) as held) yw));                     -- 0165
$o10$),
('cmd.do_build(uuid,jsonb)', 1, $o11$    raise exception 'E_NOT_BUILDABLE: % is not a hull any yard lays down', c.name using errcode = 'P0001';
  end if;
$o11$)) v(fn, n, old)) z;
rollback;
