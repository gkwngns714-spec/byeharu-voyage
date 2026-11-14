-- 0412 PROD CHECK, BEFORE the deploy, read-only, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/slim-autovac/before.sql
-- Written by gen.mjs. One row, one jsonb column `r`. It reads the catalog and the statistics views only; no table of the game.
-- BEFORE, wanted: applied false. tables[]: each table's reloptions as prod holds them (WRITE THEM DOWN: the chain gave events, ledger, voyages,
--   voyage_events and trade_daily a vacuum threshold of 2000; the stats tables, price_history and treasury_flows 1000; standing_route_laps 500
--   with an analyze threshold of 2000; orders, city_wants and insured_voyages none. If prod differs, 0412 still records what it finds in
--   public.autovacuum_was), with autovacuum_count, autoanalyze_count, last_autovacuum, dead rows, xid_age.
--   running[]: the autovacuum workers at work now. One that says "to prevent wraparound" cannot be cancelled: wait for it, then deploy.
--   settings: the server's own pace. THE PACE 0412 SETS ASSUMES vacuum_cost_page_miss 2 AND vacuum_cost_page_dirty 20 (PostgreSQL 14 and
--   later): at cost limit 25 every 20 ms that is about 5 MB/s read and 0.5 MB/s dirtied. If vacuum_cost_page_miss reads 10 (13 and earlier)
--   the read pace is 1 MB/s: say so before deploying.
-- AFTER, wanted: applied true; every table but port_goods carries autovacuum_vacuum_cost_delay=20, autovacuum_vacuum_cost_limit=25 and its
--   three thresholds (the migration's table); port_goods unchanged.
-- READING after the deploy, at +30 min, +3 h, +24 h (keep the before read: the counts run from the statistics' last reset): autovacuum_count
--   should grow by under one an hour on most tables where it grew by tens; `dead` may now stand as high as the table's threshold; `running`
--   mostly empty; mb should not grow by more than the migration's "room for the dead". Then scripts/ops/harness/slim-db/after.sql for the beat.
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', to_regclass('public.autovacuum_was') is not null,
  'tables', (select jsonb_agg(jsonb_build_object('table', c.relname, 'reloptions', c.reloptions, 'rows', c.reltuples::bigint,
                                                 'mb', pg_total_relation_size(c.oid) / 1048576, 'heap_mb', pg_relation_size(c.oid) / 1048576,
                                                 'dead', s.n_dead_tup, 'autovacuum_count', s.autovacuum_count, 'autoanalyze_count', s.autoanalyze_count,
                                                 'last_autovacuum', s.last_autovacuum, 'last_autoanalyze', s.last_autoanalyze,
                                                 'xid_age', age(c.relfrozenxid)) order by c.relname)
               from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
               left join pg_stat_user_tables s on s.relid = c.oid
              where c.relkind = 'r' and c.relname in ('events', 'ledger', 'voyage_events', 'voyages', 'standing_route_laps', 'orders', 'stats_city_good', 'stats_good', 'stats_city', 'price_history', 'treasury_flows', 'city_wants', 'trade_daily', 'insured_voyages', 'port_goods')),
  'running', (select coalesce(jsonb_agg(jsonb_build_object('query', left(a.query, 120), 'seconds', round(extract(epoch from now() - a.query_start)),
                                                           'wait', a.wait_event) order by a.query_start), '[]'::jsonb)
                from pg_stat_activity a where a.backend_type = 'autovacuum worker'),
  'settings', (select jsonb_object_agg(g.name, g.setting) from pg_settings g
                where g.name in ('autovacuum_vacuum_cost_delay', 'autovacuum_vacuum_cost_limit', 'vacuum_cost_limit', 'vacuum_cost_page_miss',
                                 'vacuum_cost_page_dirty', 'vacuum_cost_page_hit', 'autovacuum_max_workers', 'autovacuum_naptime',
                                 'autovacuum_freeze_max_age', 'server_version', 'deadlock_timeout'))
) as r;
commit;
