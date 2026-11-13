-- ROLLBACK DRAFT for 0397 (a merchant sails the seas her hull can hold). NOT a migration and NOT a prod check. THE FIRST ROLLBACK IS THE SWITCH (owner only):
--   update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc' returning key, value;
-- With it false the planner is byte for byte what it was before 0397 (the file's own assert, proof 92 SM_OFF and the dark scene). This draft is the FORWARD
-- removal of the code, for the owner to turn into a new migration (the next free number) if the code itself must go: it puts the three-argument
-- public.npc_feasible_legs back, reverses the six hunks, and drops what 0397 added. A real migration must wrap it in one `do` block with the hunk-once
-- asserts of 0397 (each NEW text exactly once, each body equal to its pre-image after), and must not carry the guard line below.
-- LOCAL PGlite WORLD ONLY while it carries this guard (scripts/ops/harness/README.md): it writes.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_def text;
  v_n   int;
  r     record;
  hk    record;
begin
  if exists (select 1 from public.world_config where key = 'sea_conditions_bite_npc' and value = 'true'::jsonb) then
    raise exception 'rollback-0397 refuses: sea_conditions_bite_npc is lit; switch it off first (owner)';
  end if;
  create temp table hunks_r0397 (fn text, ord int, new text, old text) on commit drop;
  insert into hunks_r0397 values
  ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 1, $h$public.npc_feasible_legs(p_home, p_fleet, p_speed, v_days_cap)$h$, $h$public.npc_feasible_legs(p_home, p_speed, v_days_cap)$h$),
  ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 2, $h$public.npc_feasible_legs((b->>'port_id')::uuid, p_fleet, p_speed, v_days_cap)$h$, $h$public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap)$h$),
  ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 3, $h$public.npc_feasible_legs((t->>'d')::uuid, p_fleet, p_speed, v_days_cap)$h$, $h$public.npc_feasible_legs((t->>'d')::uuid, p_speed, v_days_cap)$h$),
  ('public.npc_plan(timestamp with time zone, uuid)', 1,
$h$  v_sea     boolean := false;   -- 0397 (S3): her present loop has a leg her hull cannot hold (only while sea_conditions_bite_npc is on)
$h$, ''),
  ('public.npc_plan(timestamp with time zone, uuid)', 2,
$h$        -- 0397 (S3, docs/SEA_CONDITIONS_AND_REGIONS.md section 4): WHILE THE SEA CONDITIONS BITE FOR MERCHANTS, HER PRESENT LOOP WITH A LEG HER HULL CANNOT
        -- HOLD IS UNSAILABLE (public.npc_loop_sea_shut: the one rule, on wave only). The loops on offer need no such test: public.npc_feasible_legs never
        -- offers her such a leg. The sail door stays exempt for a merchant, so she finishes the lap she is on.
        if i = 0 then
          v_sea := public.sea_conditions_npc_on() and public.npc_loop_sea_shut(r.fleet_id, v_loop);
          v_unsail := v_unsail or v_sea;
        end if;
$h$, ''),
  ('public.npc_plan(timestamp with time zone, uuid)', 3,
$h$(v_net <= 0 or v_off or v_sea or sr.lap_no % greatest(v_review, 1) = 0) then   -- 0397 (S3): a loop the sea closes to her is reviewed at this lap start, not at the next review lap
$h$,
$h$(v_net <= 0 or v_off or sr.lap_no % greatest(v_review, 1) = 0) then
$h$);

  -- the three-argument function first (the reversed candidates call it)
  create function public.npc_feasible_legs(p_port uuid, p_speed numeric, p_days integer)
  returns jsonb language sql stable security definer set search_path = public, pg_temp
  as $body$
  -- 0120: the known legs out of p_port (public.npc_known_legs) a fleet of speed p_speed may sail
  -- with p_days of stores: an open harbour (the berth fact voyage.sail_refusal reads; 0139 removed
  -- the draft gate — any hull enters any harbour), and a passage her stores cover at
  -- endurance_margin, one day spare — the stores gate as the sail gate judges it. Nearest first,
  -- then the port id.
  select coalesce(jsonb_agg(jsonb_build_object('port_id', l.to_port, 'code', l.code, 'course', l.course, 'nm', l.nm)
                            order by l.nm, l.to_port), '[]'::jsonb)
    from public.npc_known_legs(p_port) l
    join public.ports p on p.id = l.to_port
   where p.kind = 'HARBOUR' and not p.is_ice_closed
     and public.npc_leg_days(l.nm, p_speed) <= p_days   -- 0203: the door's measure (voyage.stores_need_days), one day spare
$body$;
  revoke all on function public.npc_feasible_legs(uuid, numeric, integer) from public, anon, authenticated;

  for r in select distinct h.fn from hunks_r0397 h loop
    v_def := replace(pg_get_functiondef(to_regprocedure(r.fn)), E'\r', '');
    for hk in select * from hunks_r0397 x where x.fn = r.fn order by x.ord desc loop
      v_n := (length(v_def) - length(replace(v_def, hk.new, ''))) / length(hk.new);
      if v_n <> 1 then
        raise exception 'rollback-0397: hunk % of % occurs % time(s), not once', hk.ord, r.fn, v_n;
      end if;
      v_def := replace(v_def, hk.new, hk.old);
    end loop;
    execute v_def;
  end loop;

  drop function public.npc_feasible_legs(uuid, uuid, numeric, integer);
  drop function public.npc_loop_sea_shut(uuid, jsonb);
  drop function public.npc_sea_shut(numeric, uuid, jsonb);
  drop function public.npc_course_zones(jsonb);
  drop function public.npc_course_zones_fill();
  drop table public.npc_course_zones_memo;
  drop function public.sea_conditions_npc_on();
  delete from public.world_config where key = 'sea_conditions_bite_npc';
  raise notice 'rollback-0397 draft ok: the planner is 0341''s again';
end
$r$;
