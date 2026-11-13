-- 0360 PROD CHECK BEFORE, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/trip-cost/before.sql
-- Nothing is called but the catalog (to_regprocedure, pg_get_functiondef, pg_proc) and plain SELECTs of world_config. No game function runs.
-- Wanted: head 20260818000359 (0354 to 0359 are other branches': this file deploys after them); fn_absent true; registry_anchor_times 1 and
--         registry_row_present false; readers all 's' (or 'i'); sibling_acl and sibling_vol printed (the self-assert holds the new read to
--         world.route_legs' own). `knobs` says what a trip will read on prod today: whether the economy is closed (dock fees and port time in
--         force), the port time, the dock fee's base and share, the clock's compression.
begin transaction read only;
with h(old) as (values ($h$      ('world',       'route_legs',            'uuid, jsonb'),
$h$))
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'fn_absent', to_regprocedure('world.trip_cost(uuid,jsonb)') is null,
  'registry_anchor_times', (select (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old)
                              from h cross join lateral (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def) d),
  'registry_row_present', position('trip_cost' in pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure)) > 0,
  'readers', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile::text) from pg_proc p
               where p.oid in ('public.supply_needs(uuid,numeric[])'::regprocedure, 'public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)'::regprocedure,
                               'public.stores_cost(uuid,numeric,numeric)'::regprocedure, 'public.npc_leg_days(numeric,numeric)'::regprocedure,
                               'public.ship_stores_room(uuid,numeric)'::regprocedure, 'public.ship_hold_capacity(uuid)'::regprocedure,
                               'public.ship_cargo_tuns(uuid)'::regprocedure, 'public.fleet_wage(uuid,boolean,integer)'::regprocedure,
                               'public.port_fee(uuid,uuid,numeric)'::regprocedure, 'public.fleet_stock_at_cost(uuid)'::regprocedure,
                               'public.economy_closed()'::regprocedure, 'voyage.segments_from_course(jsonb)'::regprocedure,
                               'voyage.reach_from(uuid)'::regprocedure, 'voyage.fleet_speed(uuid)'::regprocedure,
                               'public.current_player_id()'::regprocedure, 'public.wc_num(text)'::regprocedure)),
  'sibling_acl', (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.route_legs(uuid,jsonb)'::regprocedure),
  'sibling_vol', (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'world.route_legs(uuid,jsonb)'::regprocedure),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c
             where c.key in ('economy_closed', 'city_treasury_enabled', 'port_prep_seconds', 'port_fee_base', 'port_fee_pct', 'time_compression',
                             'water_per_crew_day', 'food_per_crew_day'))
) as checks
from h;
commit;
