-- 0470 PROD CHECK, AFTER the deploy (the same read as before-0470.sql), read-only, ONE statement, catalog and statistics views only (no game table, no volatile function):
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/hot-set/after-0470.sql
-- For the ten biggest tables (relpages, so the same figure daily.sql's hot_set_mb sums): heap and index pages, the planner's rows, the width the
-- statistics give a row (sum of pg_stats.avg_width) and so the pages a compact heap would need, dead rows, churn counters, options; for every index
-- on them: pages, entries, scans since the statistics began, its definition and an estimate of the pages a fresh build would need.
-- WANTED AFTER 0470: head 20260818000470; hot10_mb ~480-505 (from 781); stats_city_good ~56, voyages ~52, events ~40, voyage_events ~13 MB; every index near its est_pages (est_pages uses the entry count the last vacuum saw: re-read after one); the same indexes, none dropped.
begin transaction read only;
with top as (
  select c.oid, c.relname, c.relpages, c.reltuples, c.reloptions,
         c.relpages + coalesce((select sum(ic.relpages) from pg_index i join pg_class ic on ic.oid = i.indexrelid where i.indrelid = c.oid), 0)
                    + coalesce((select tc.relpages from pg_class tc where tc.oid = c.reltoastrelid), 0) as tot,
         coalesce((select tc.relpages from pg_class tc where tc.oid = c.reltoastrelid), 0) as toast
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
   order by tot desc limit 10
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'hot10_mb', (select round(sum(tot) * 8192 / 1048576.0) from top),
  'cache', (select jsonb_build_object('hit', blks_hit, 'read', blks_read, 'reset', stats_reset) from pg_stat_database where datname = current_database()),
  'tables', (select jsonb_agg(jsonb_build_object(
       't', top.relname, 'mb', round(top.tot * 8192 / 1048576.0), 'heap_pages', top.relpages, 'toast_pages', top.toast, 'rows', top.reltuples::bigint,
       'row_width', (select sum(s.avg_width) from pg_stats s where s.schemaname = 'public' and s.tablename = top.relname),
       'compact_pages', ceil(top.reltuples * ((select sum(s.avg_width) from pg_stats s where s.schemaname = 'public' and s.tablename = top.relname) + 28)
                              / (8168.0 * coalesce((select substr(o, 12)::numeric from unnest(top.reloptions) o where o like 'fillfactor=%'), 100) / 100)),
       'opts', top.reloptions,
       'live', st.n_live_tup, 'dead', st.n_dead_tup, 'ins', st.n_tup_ins, 'upd', st.n_tup_upd, 'hot', st.n_tup_hot_upd, 'del', st.n_tup_del,
       'av', st.autovacuum_count, 'last_av', st.last_autovacuum, 'seq', st.seq_scan, 'idx', st.idx_scan,
       'heap_read', io.heap_blks_read, 'heap_hit', io.heap_blks_hit, 'idx_read', io.idx_blks_read, 'idx_hit', io.idx_blks_hit,
       'indexes', (select jsonb_agg(jsonb_build_object(
            'i', ic.relname, 'pages', ic.relpages, 'entries', ic.reltuples::bigint, 'scans', si.idx_scan, 'last_scan', si.last_idx_scan,
            'uniq', i.indisunique, 'pk', i.indisprimary, 'valid', i.indisvalid, 'partial', i.indpred is not null,
            'key_width', (select sum(s.avg_width) from unnest(i.indkey) k(n) join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.n
                                   join pg_stats s on s.schemaname = 'public' and s.tablename = top.relname and s.attname = a.attname),
            'est_pages', ceil(ic.reltuples * (16 + coalesce((select sum(s.avg_width) from unnest(i.indkey) k(n) join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.n
                                   join pg_stats s on s.schemaname = 'public' and s.tablename = top.relname and s.attname = a.attname), 0)) / (8168.0 * 0.9)),
            'def', pg_get_indexdef(i.indexrelid)) order by ic.relpages desc)
          from pg_index i join pg_class ic on ic.oid = i.indexrelid left join pg_stat_user_indexes si on si.indexrelid = i.indexrelid
         where i.indrelid = top.oid)) order by top.tot desc)
     from top left join pg_stat_user_tables st on st.relid = top.oid left join pg_statio_user_tables io on io.relid = top.oid)
) as r;
commit;
