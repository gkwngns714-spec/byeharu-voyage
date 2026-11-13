-- 0397 PROD CHECK (after the deploy), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-merchants/after.sql
-- Run volatility.sql first. Wanted: switch false; reader false; old_function_gone true; new_functions 6; every new_* 1 (the new text of each hunk once on the
-- live bodies); memo_rows > 0; courses_not_remembered 0 (a course the planner can be handed that the memo does not hold is sampled live: correct, slower);
-- client_can_read_memo false; loops_the_sea_would_close is what lighting sea_conditions_bite_npc would re-plan (impact.sql's merchants row says the same).
begin transaction read only;
with d as (
  select replace(pg_get_functiondef('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)'::regprocedure), E'\r', '') as cand,
         replace(pg_get_functiondef('public.npc_plan(timestamp with time zone, uuid)'::regprocedure), E'\r', '') as plan
), h as (
  select $h$public.npc_feasible_legs(p_home, p_fleet, p_speed, v_days_cap)$h$ as c1,
         $h$public.npc_feasible_legs((b->>'port_id')::uuid, p_fleet, p_speed, v_days_cap)$h$ as c2,
         $h$public.npc_feasible_legs((t->>'d')::uuid, p_fleet, p_speed, v_days_cap)$h$ as c3,
         $h$  v_sea     boolean := false;   -- 0397 (S3)$h$ as p1,
         $h$          v_sea := public.sea_conditions_npc_on() and public.npc_loop_sea_shut(r.fleet_id, v_loop);
          v_unsail := v_unsail or v_sea;
$h$ as p2,
         $h$(v_net <= 0 or v_off or v_sea or sr.lap_no % greatest(v_review, 1) = 0) then$h$ as p3
), loops as (
  select nf.fleet_id, f.status,
         public.npc_loop_sea_shut(nf.fleet_id, (select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord)
                                                  from public.standing_route_stops st where st.route_id = nf.route_id)) as shut
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where nf.route_id is not null
)
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select value from public.world_config where key = 'sea_conditions_bite_npc') as switch,
       public.sea_conditions_npc_on() as reader,
       to_regprocedure('public.npc_feasible_legs(uuid, numeric, integer)') is null as old_function_gone,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
         and p.proname in ('sea_conditions_npc_on', 'npc_course_zones', 'npc_course_zones_fill', 'npc_sea_shut', 'npc_loop_sea_shut', 'npc_feasible_legs')) as new_functions,
       (length(d.cand) - length(replace(d.cand, h.c1, ''))) / length(h.c1) as new_candidates_1,
       (length(d.cand) - length(replace(d.cand, h.c2, ''))) / length(h.c2) as new_candidates_2,
       (length(d.cand) - length(replace(d.cand, h.c3, ''))) / length(h.c3) as new_candidates_3,
       (length(d.plan) - length(replace(d.plan, h.p1, ''))) / length(h.p1) as new_plan_1,
       (length(d.plan) - length(replace(d.plan, h.p2, ''))) / length(h.p2) as new_plan_2,
       (length(d.plan) - length(replace(d.plan, h.p3, ''))) / length(h.p3) as new_plan_3,
       (select count(*) from public.npc_course_zones_memo) as memo_rows,
       (select count(*) from (select c.course from public.npc_courses c
                              union all
                              select st.course from public.standing_route_stops st join public.standing_routes sr on sr.id = st.route_id
                                join public.players p on p.id = sr.player_id and p.is_npc) x
         where not exists (select 1 from public.npc_course_zones_memo m where m.course_md5 = md5(x.course::text))) as courses_not_remembered,
       has_table_privilege('authenticated', 'public.npc_course_zones_memo', 'select') or has_table_privilege('anon', 'public.npc_course_zones_memo', 'select') as client_can_read_memo,
       (select count(*) from loops) as merchant_loops,
       (select count(*) from loops where shut) as loops_the_sea_would_close,
       (select count(*) from loops where shut and status <> 'DOCKED') as of_them_at_sea_now
  from d, h;
commit;
