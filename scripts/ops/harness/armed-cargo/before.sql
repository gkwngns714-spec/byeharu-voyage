-- 0328 PROD CHECK, read-only, one statement: supabase db query --linked -f scripts/ops/harness/armed-cargo/before.sql
-- Every function read here is STABLE (pg_get_functiondef, to_regprocedure, replace). No game function is called.
-- Wanted: every `times` 1; armed_keys 0; upkeep_word 0; armed_on null; armed_hulls 0; class_ok 1; head 0327 (0324 until #527 and #529 land).
begin transaction read only;
with h(fn, ord, old) as (values
  ('public.cargo_ship_step(uuid,timestamp with time zone)'::regprocedure, 1, $h$--   Then, port time done (fleets.ready_at), the next leg. Off she still sails: she is carrying funds home, and the circuit is the only way she knows.
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)'::regprocedure, 2, $h$    if v_load is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: idle, she may be due a new home. Off at her capital: IDLE
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)'::regprocedure, 3, $h$  perform voyage.depart(p_fleet, l.segments, f.port_id, l.to_port, p_now);
$h$),
  ('public.cargo_rebase(uuid,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure, 1, $h$  perform voyage.depart(p_fleet, voyage.segments_from_course(v_leg -> 'course'), p_port, v_to, p_now);
$h$),
  ('public.cargo_ships_commission(uuid)'::regprocedure, 1, $h$    perform public.commission_ship(v_player, v_fleet, public.wc_text('convoy_ship_class'), format('Cargo ship %s', v_n), true, false);
$h$),
  ('public.fleet_wage(uuid,boolean,integer)'::regprocedure, 1, $h$  -- (0149's early exit: a house holding no HOUSE-scope skill — every merchant — reads nothing more)
$h$),
  ('public.npc_refit_step(uuid,timestamp with time zone)'::regprocedure, 1, $h$  v_why    text;
  v_short  int;
  v_hands  int;
  v_give   int;
  v_ev     uuid;
  s        record;
begin
$h$),
  ('public.npc_refit_step(uuid,timestamp with time zone)'::regprocedure, 2, $h$  -- A merchant's hands from the quay, what public.crew_hire_cost says it can give her. The rest she hires herself. A cargo ship sails crewless until W8.
  if public.fleet_kind(p_fleet) = 'MERCHANT' then
    v_short := public.fleet_crew_shortfall(p_fleet);
$h$)
)
select jsonb_build_object(
  'hunks', (select jsonb_agg(jsonb_build_object('fn', h.fn::text, 'ord', h.ord,
                     'times', (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old)) order by h.fn::text, h.ord)
              from h cross join lateral (select replace(pg_get_functiondef(h.fn), E'\r', '') as def) d),
  'armed_keys', (select count(*) from public.world_config c where c.key in ('convoy_armed_enabled', 'convoy_armed_class', 'convoy_upkeep_per_leg', 'convoy_store_days')),
  'upkeep_word', (select count(*) from public.stats_flow_words w where w.kind = 'CONVOY_UPKEEP'),
  'armed_on', to_regprocedure('public.cargo_armed_on()'),
  'armed_hulls', (select count(*) from public.cargo_ships c join public.ships s on s.fleet_id = c.fleet_id join public.ship_classes k on k.id = s.class_id where k.attack > 0 or s.crew > 0),
  'class_ok', (select count(*) from public.ship_classes k where k.code = 'navire' and k.attack > 0 and k.crew_required > 0),
  'head', (select max(version) from supabase_migrations.schema_migrations)
) as checks;
commit;
