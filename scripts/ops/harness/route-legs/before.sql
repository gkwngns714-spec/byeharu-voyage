-- 0346 PROD CHECK BEFORE, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/route-legs/before.sql
-- Nothing is called but the catalog (to_regprocedure, pg_get_functiondef, pg_proc) and plain SELECTs. No game function runs.
-- Wanted: head 20260818000345; fn_absent true; registry_anchor_times 1 and registry_row_present false; readers all 's';
--         sibling_acl and sibling_vol printed (the new read must match them: the self-assert holds it to world.good_board's).
begin transaction read only;
with h(old) as (values ($h$      ('cmd',         'issue_lines',           'uuid, jsonb, int'),
$h$))
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'fn_absent', to_regprocedure('world.route_legs(uuid,jsonb)') is null,
  'registry_anchor_times', (select (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old)
                              from h cross join lateral (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def) d),
  'registry_row_present', position('route_legs' in pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure)) > 0,
  'readers', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile::text) from pg_proc p
               where p.oid in ('voyage.leg_refusal(uuid,uuid,numeric,jsonb)'::regprocedure, 'public.supply_needs(uuid,numeric[])'::regprocedure,
                               'voyage.reach_passage(uuid,uuid,uuid,numeric)'::regprocedure, 'public.supply_reach(uuid)'::regprocedure,
                               'voyage.segments_from_course(jsonb)'::regprocedure, 'voyage.reach_from(uuid)'::regprocedure,
                               'voyage.fleet_speed(uuid)'::regprocedure, 'public.current_player_id()'::regprocedure, 'cmd.refusal(text,text,jsonb)'::regprocedure)),
  'sibling_acl', (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.good_board(uuid,uuid,uuid,numeric)'::regprocedure),
  'sibling_vol', (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'world.good_board(uuid,uuid,uuid,numeric)'::regprocedure)
) as checks
from h;
commit;
