-- 0392 PROD CHECK (before the deploy), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-merchants/before.sql
-- HEAD IT MEETS: 20260818000391 (0392 deploys after 0391, the wall; 0379 to 0390 deploy before both). Wanted head below: 20260818000391.
-- Wanted: nothing_of_0392 true; old_function true; other_callers 0; every hunk_* 1 (each of the six hunks occurs exactly once on the live bodies);
-- sea_rule_in true (0215 and 0216); switch_players is whatever it is (0392 does not read it); merchant_fleets and courses are the size of the memo's fill
-- (one public.course_zones a distinct course, inside the file's 45 s budget). Any other answer: do not deploy, the file refuses or the body moved.
begin transaction read only;
with d as (
  select replace(pg_get_functiondef('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)'::regprocedure), E'\r', '') as cand,
         replace(pg_get_functiondef('public.npc_plan(timestamp with time zone, uuid)'::regprocedure), E'\r', '') as plan
), h as (
  select $h$public.npc_feasible_legs(p_home, p_speed, v_days_cap)$h$ as c1,
         $h$public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap)$h$ as c2,
         $h$public.npc_feasible_legs((t->>'d')::uuid, p_speed, v_days_cap)$h$ as c3,
         $h$  v_notes   jsonb := '[]'::jsonb;
begin
  if not public.npc_traders_on() then
$h$ as p1,
         $h$        v_unsail := coalesce(v_unsail, true);
$h$ as p2,
         $h$        if i = 0 and v_choose and (v_net <= 0 or v_off or sr.lap_no % greatest(v_review, 1) = 0) then
$h$ as p3
)
select (select max(version) from supabase_migrations.schema_migrations) as head,
       to_regprocedure('public.sea_conditions_npc_on()') is null and to_regprocedure('public.npc_sea_shut(numeric, uuid, jsonb)') is null
         and to_regclass('public.npc_course_zones_memo') is null
         and not exists (select 1 from public.world_config where key = 'sea_conditions_bite_npc') as nothing_of_0392,
       to_regprocedure('public.npc_feasible_legs(uuid, numeric, integer)') is not null as old_function,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%npc_feasible_legs(%'
           and p.proname not in ('npc_loop_candidates', 'npc_leg_days', 'npc_feasible_legs')) as other_callers,
       (length(d.cand) - length(replace(d.cand, h.c1, ''))) / length(h.c1) as hunk_candidates_1,
       (length(d.cand) - length(replace(d.cand, h.c2, ''))) / length(h.c2) as hunk_candidates_2,
       (length(d.cand) - length(replace(d.cand, h.c3, ''))) / length(h.c3) as hunk_candidates_3,
       (length(d.plan) - length(replace(d.plan, h.p1, ''))) / length(h.p1) as hunk_plan_1,
       (length(d.plan) - length(replace(d.plan, h.p2, ''))) / length(h.p2) as hunk_plan_2,
       (length(d.plan) - length(replace(d.plan, h.p3, ''))) / length(h.p3) as hunk_plan_3,
       to_regprocedure('public.sea_refusal(integer, numeric, text[])') is not null and to_regprocedure('public.course_zones(jsonb)') is not null
         and to_regprocedure('public.npc_legs_open(jsonb, uuid)') is not null as sea_rule_in,
       (select value from public.world_config where key = 'sea_conditions_bite') as switch_players,
       (select count(*) from public.npc_fleets where route_id is not null) as merchant_fleets,
       (select count(*) from public.npc_courses) as courses,
       (select count(*) from public.standing_route_stops st join public.standing_routes sr on sr.id = st.route_id join public.players p on p.id = sr.player_id and p.is_npc) as merchant_stops
  from d, h;
commit;
