-- THE HQ BOARD FROM THE SERVER (0480), BEFORE. A PROD CHECK: read-only, ONE statement. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/hq-board/before-0480.sql
-- Expect: head 20260818000479; knobs {} (none of the eight hq_board_*); fn_absent true; the one hunk's OLD text once (old 1) and its new
-- marker absent (new 0) in public.client_rpc_entry_points; `lit` as prod runs the switches the board reads (sea_conditions_bite false).
-- THE COST the board will carry, read here without the board: `idle` the companies' idle fleets (DOCKED, nothing queued: what
-- hq_board_fleets bounds), `max_idle` the most one company has; `best_sales_ms` ONE world.best_sales (STABLE, the desk's read, the board's
-- main cost a fleet) for the newest company's oldest idle fleet where she lies, timed: the identity is set for this transaction alone
-- (set_config, local: nothing is written), `cut` whether its own 2.5 s budget ran out.
-- Reads: the catalog (one pg_get_functiondef), world_config by key, players (companies), their fleets and queued orders, one
-- world.best_sales. No function that writes is called. ROLLBACK: nothing to roll back (read only; the transaction ends with rollback).
begin transaction read only;
with hu as materialized (
  select p.id, p.auth_uid, p.created_at from public.players p where not p.is_npc
), idle as materialized (
  select hu.id as player_id, hu.auth_uid, hu.created_at as founded, f.id as fleet, f.port_id, f.created_at
    from hu join public.fleets f on f.player_id = hu.id
   where f.status = 'DOCKED' and f.port_id is not null
     and not exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active'))
), who as materialized (
  select i.*, set_config('request.jwt.claim.sub', i.auth_uid::text, true) as a,
         set_config('request.jwt.claims', json_build_object('sub', i.auth_uid)::text, true) as b
    from idle i order by i.founded desc, i.created_at, i.fleet limit 1
), t0 as materialized (
  select who.*, clock_timestamp() as t0 from who
), bs as materialized (
  select t0.*, world.best_sales(t0.fleet, t0.port_id) as r, clock_timestamp() as t1 from t0
), d as (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'hq\_board\_%'),
  'fn_absent', to_regprocedure('world.hq_board()') is null and to_regprocedure('public.hq_board_for(uuid)') is null,
  'hunk', (select jsonb_build_object(
             'old', (length(d.def) - length(replace(d.def, '      (''world'',       ''goods_mastery'',         ''''),', ''))) / length('      (''world'',       ''goods_mastery'',         ''''),'),
             'new', (length(d.def) - length(replace(d.def, '''hq_board''', ''))) / length('''hq_board''')) from d),
  'lit', (select jsonb_object_agg(c.key, c.value) from public.world_config c
           where c.key in ('sea_conditions_bite', 'yard_order_enabled', 'city_treasury_enabled', 'economy_closed', 'pirate_bounties_enabled',
                           'pirates_bite', 'land_enabled', 'first_hour_enabled', 'near_choice_enabled', 'goods_mastery_enabled')),
  'companies', (select count(*) from hu),
  'idle', (select count(*) from idle),
  'max_idle', (select coalesce(max(z.n), 0) from (select count(*) as n from idle group by idle.player_id) z),
  'best_sales_ms', (select round(extract(epoch from bs.t1 - bs.t0) * 1000) from bs),
  'best_sales_at', (select p.code from bs join public.ports p on p.id = bs.port_id),
  'cut', (select bs.r -> 'cut' from bs),
  'paying', (select count(*) from bs cross join jsonb_array_elements(bs.r -> 'goods') g where (g ->> 'pays')::boolean));
rollback;
