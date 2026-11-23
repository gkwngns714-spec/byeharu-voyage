-- STANDING FLEET JOBS (0481), BEFORE. A PROD CHECK: read-only, ONE statement. It carries the gate's own beat figure, so it is the one read.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/fleet-jobs/before-0481.sql
-- Expect: head 20260818000480; knobs {} (none of the five fleet_jobs_*); absent true (no table, no function, no cron job of 0481); the
-- one hunk's OLD text once (old 1) and its new marker absent (new 0) in public.client_rpc_entry_points; `beat` the arrivals beat's last
-- 5 minutes (the gate refuses over 2,000 ms mean); `lit` the switches a job reads (land_enabled, standing_routes_enabled).
-- THE COST a `best` job's plan will carry, read here without the job: `idle` the companies' idle fleets (DOCKED, nothing queued: what a
-- job acts on), `max_idle` the most one company has; for the newest company's oldest idle fleet where she lies: `best_sales_ms` ONE
-- world.best_sales (STABLE, the plan's main cost), `cut` whether its own 2.5 s budget ran out, `passages_ms` ONE world.board_passages,
-- `legs_ms` the remembered courses out of her harbour (public.npc_known_legs + npc_coast_legs, STABLE), and `coursed` how many of her
-- paying sales end at a harbour a remembered course reaches directly (the job sails only those, through stops when the passage has them).
-- The identity is set for this transaction alone (set_config, local: nothing is written).
-- Reads: the catalog (one pg_get_functiondef), cron.job by name, world_config by key, arrivals_beats (the ring), players (companies),
-- their fleets and queued orders, one world.best_sales, one world.board_passages, the known legs. No function that writes is called.
-- ROLLBACK: nothing to roll back (read only; the transaction ends with rollback).
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
), ps as materialized (
  select bs.t1 as t0, world.board_passages(bs.player_id, bs.fleet, bs.port_id, (select sr.cap_nm from public.supply_reach(bs.fleet) sr)) as r,
         clock_timestamp() as t1 from bs
), lg as materialized (
  select ps.t1 as t0, (select array_agg(k.code) from public.npc_known_legs(bs.port_id) k) || coalesce((select array_agg(c.code) from public.npc_coast_legs(bs.port_id) c), '{}'::text[]) as codes,
         clock_timestamp() as t1
    from ps, bs
), d as (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'beat', (select jsonb_build_object('beats', count(*), 'mean_ms', round(avg(b.ms)), 'p95_ms', round((percentile_cont(0.95) within group (order by b.ms))::numeric))
             from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'fleet\_jobs\_%'),
  'absent', to_regclass('public.fleet_jobs') is null and to_regprocedure('world.away_report()') is null
            and not exists (select 1 from cron.job j where j.jobname = 'byeharu-voyage:fleet-jobs'),
  'hunk', (select jsonb_build_object(
             'old', (length(d.def) - length(replace(d.def, '      (''world'',       ''hq_board'',              ''''),', ''))) / length('      (''world'',       ''hq_board'',              ''''),'),
             'new', (length(d.def) - length(replace(d.def, '''set_fleet_job''', ''))) / length('''set_fleet_job''')) from d),
  'lit', (select jsonb_object_agg(c.key, c.value) from public.world_config c
           where c.key in ('land_enabled', 'standing_routes_enabled', 'hq_board_enabled', 'economy_closed', 'yard_order_enabled')),
  'companies', (select count(*) from hu),
  'idle', (select count(*) from idle),
  'max_idle', (select coalesce(max(z.n), 0) from (select count(*) as n from idle group by idle.player_id) z),
  'at', (select p.code from bs join public.ports p on p.id = bs.port_id),
  'best_sales_ms', (select round(extract(epoch from bs.t1 - bs.t0) * 1000) from bs),
  'cut', (select bs.r -> 'cut' from bs),
  'passages_ms', (select round(extract(epoch from ps.t1 - ps.t0) * 1000) from ps),
  'legs_ms', (select round(extract(epoch from lg.t1 - lg.t0) * 1000) from lg),
  'legs', (select cardinality(lg.codes) from lg),
  'paying', (select count(*) from bs cross join jsonb_array_elements(bs.r -> 'goods') g where (g ->> 'pays')::boolean and g ->> 'port' is not null),
  'coursed', (select count(*) from bs cross join lg cross join jsonb_array_elements(bs.r -> 'goods') g
               where (g ->> 'pays')::boolean and g ->> 'port' = any (lg.codes)));
rollback;
