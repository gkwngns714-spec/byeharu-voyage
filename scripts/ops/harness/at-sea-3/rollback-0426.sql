-- 0426 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none"
-- and deploy it as any migration (owner only).
-- Gives public.waiting_ask_plan back its 0425 body (the hunk reversed, checked once), turns the moves off and the three knobs back to 0425's.
-- The knobs alone are the quick way back: npc_rehome_per_run 0 (no merchant moves; public.npc_rehome answers null at once), npc_min_return_pct 5,
-- convoy_load_max 250000, convoy_loads_per_run 20. A merchant already moved keeps her new home (it is where she lies); public.npc_rehome and
-- npc_fleets.rehomed_at stay (unreached with the hunk reversed; drop them in a later file if wanted).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  c_fn  constant text := 'public.waiting_ask_plan(uuid)';
  v_def text := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  v_old text :=
$h$  v_res := public.npc_plan(now(), q.route_id);
  if coalesce((v_res->>'planned')::int, 0) = 0 or coalesce((v_res->>'waiting')::int, 0) > 0 then
    return 0;   -- not planned, or nothing pays: she waits on (0181)
  end if;
$h$;
  v_new text :=
$h$  v_res := public.npc_plan(now(), q.route_id);
  if coalesce((v_res->>'planned')::int, 0) = 0 or coalesce((v_res->>'waiting')::int, 0) > 0 then
    -- 0426: NOTHING FROM HER HARBOUR PAYS: she may move her home (public.npc_rehome: a healthy harbour near, on a passage that pays).
    -- Moved, she is resumed by the open step like any paying ask; else she waits on.
    if coalesce((v_res->>'planned')::int, 0) > 0 and public.npc_rehome(p_fleet) is not null then
      return 1;
    end if;
    return 0;   -- not planned, or nothing pays: she waits on (0181)
  end if;
$h$;
begin
  if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
    raise exception 'rollback-0426 refuses: 0426''s hunk is not in the live body once';
  end if;
  execute replace(v_def, v_new, v_old);
  update public.world_config set value = to_jsonb(0) where key = 'npc_rehome_per_run';
  update public.world_config set value = to_jsonb(5) where key = 'npc_min_return_pct' and value = to_jsonb(2);
  update public.world_config set value = to_jsonb(250000) where key = 'convoy_load_max' and value = to_jsonb(100000);
  update public.world_config set value = to_jsonb(20) where key = 'convoy_loads_per_run' and value = to_jsonb(30);
  raise notice 'rollback-0426 ok: waiting_ask_plan is 0425''s again; npc_rehome_per_run %, npc_min_return_pct %, convoy_load_max %, convoy_loads_per_run %',
    public.wc_int('npc_rehome_per_run'), public.wc_int('npc_min_return_pct'), public.wc_int('convoy_load_max'), public.wc_int('convoy_loads_per_run');
end $r$;
