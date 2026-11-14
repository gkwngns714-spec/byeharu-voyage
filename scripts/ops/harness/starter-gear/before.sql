-- 0424 BEFORE-CHECK (a PROD CHECK: read-only, ONE static statement, no game table scanned beyond the small catalogue rows named).
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/starter-gear/before.sql
-- Run scripts/ops/harness/db-health/gate.sql first; do not run this while the gate is red.
-- WANT: head 421 (or the reserved 0422-0424 if they deployed first); no starter object yet (no_table, no_items 0, no_word 0,
--   no_core); each of the three hunk anchors occurs exactly ONCE in its live body (anchor_mount 1, anchor_ws 1, anchor_rpc 1);
--   the three grade-1 pieces present (g1 3); 254 harbours; the knobs as read (purses lit, wear biting, the two scales 3).
-- Functions called: to_regclass, to_regprocedure, pg_get_functiondef (all stable), replace, length (immutable). Nothing volatile.
begin transaction read only;
with d as (
  select replace(pg_get_functiondef('public.mount_fitting(uuid,text)'::regprocedure), E'\r', '') as mount,
         replace(pg_get_functiondef('world.workstation(uuid,uuid)'::regprocedure), E'\r', '') as ws,
         replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as rpc
), a as (
  select $h$  -- 0132: ONE ROW PER MOUNTED UNIT.
  insert into public.fitted_units (ship_id, item_code) values (v_ship.id, k.code);
$h$ as mount,
         $h$     where k.kind = 'fitting'));   -- 0135: once per item (0159: and its city); 0162: fittings only (a promotion item is never made)
$h$ as ws,
         $h$      ('world',       'stats_fleets',          ''),
$h$ as rpc
)
select (select max(version) from supabase_migrations.schema_migrations) as head,
       to_regclass('public.starter_gear') is null as no_table,
       (select count(*) from public.item_kinds k where k.code like 'starter-%') as no_items,
       (select count(*) from public.stats_flow_words w where w.kind = 'GEAR') as no_word,
       to_regprocedure('public.buy_starter_for(uuid,uuid,uuid,text)') is null as no_core,
       (length(d.mount) - length(replace(d.mount, a.mount, ''))) / length(a.mount) as anchor_mount,
       (length(d.ws) - length(replace(d.ws, a.ws, ''))) / length(a.ws) as anchor_ws,
       (length(d.rpc) - length(replace(d.rpc, a.rpc, ''))) / length(a.rpc) as anchor_rpc,
       (select count(*) from public.item_profile ip where ip.item_code in ('broadside-guns', 'suit-of-sails', 'deal-planking') and ip.grade = 1 and ip.meta = 0) as g1,
       (select count(*) from public.ports p where p.kind = 'HARBOUR') as harbours,
       (select jsonb_object_agg(c.key, c.value) from public.world_config c
         where c.key in ('city_treasury_enabled', 'gear_wear_bite', 'economy_closed', 'hold_scale', 'speed_scale', 'starting_ducats')) as knobs
  from d, a;
commit;
