-- WHAT PROD PLANS WITH (world.best_sales). A PROD CHECK: read-only, ONE statement, the catalog alone (a few ms). Nothing is run or written.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/best-sales-fast/plans.sql
-- Read: `tables` (rows the planner believes, pages, dead rows, when last analyzed: a null or old one on port_goods, sea_leg_asks or world_config
--   means stale statistics), `indexes` (port_goods needs one led by good_id and one by port_id), `settings`, `sql_readers` (SQL-language readers on this
--   path that PostgreSQL 17 plans again at each call). explain.sql beside it shows one plan (EXPLAIN, never ANALYZE).
begin transaction read only;
select json_build_object(
  'settings', (select json_object_agg(s.name, s.setting) from pg_settings s
                where s.name in ('server_version', 'shared_buffers', 'work_mem', 'plan_cache_mode', 'jit', 'random_page_cost', 'effective_cache_size', 'track_functions')),
  'tables', (select json_agg(json_build_object('t', c.relname, 'rows', c.reltuples, 'pages', c.relpages, 'toast_pages', t.relpages, 'live', st.n_live_tup, 'dead', st.n_dead_tup,
                                               'analyzed', greatest(st.last_analyze, st.last_autoanalyze), 'mod', st.n_mod_since_analyze, 'seq', st.seq_scan, 'idx', st.idx_scan) order by c.relname)
               from pg_class c left join pg_class t on t.oid = c.reltoastrelid left join pg_stat_user_tables st on st.relid = c.oid
              where c.relnamespace = 'public'::regnamespace
                and c.relname in ('port_goods', 'ports', 'goods', 'world_config', 'sea_leg_asks', 'sea_reaches', 'sea_reach_matrix', 'sea_raster', 'port_treasury', 'fleets', 'ships', 'orders')),
  'indexes', (select json_agg(i.indexdef order by i.indexname) from pg_indexes i where i.schemaname = 'public' and i.tablename in ('port_goods', 'sea_leg_asks', 'world_config')),
  'sql_readers', (select json_agg(p.oid::regprocedure::text order by 1) from pg_proc p join pg_language l on l.oid = p.prolang
                   where l.lanname = 'sql' and p.prosecdef and p.proname in ('ship_base', 'ship_cargo_tuns', 'ship_hold_capacity', 'ship_stores_space', 'ship_stores_room', 'fleet_free_hold',
                         'fleet_cargo_qty', 'trip_hulls', 'trip_stow', 'board_passages', 'current_player_id', 'supply_reach', 'supply_need', 'storage_used')),
  'own_settings', (select json_agg(json_build_object('fn', p.oid::regprocedure::text, 'set', p.proconfig)) from pg_proc p where p.proconfig::text like '%plan_cache_mode%')) as plans;
rollback;
