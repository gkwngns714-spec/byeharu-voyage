-- 0347 PROD CHECK (before), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/news/before.sql
-- Wanted (head 0346, or 0345 before the route builder lands): 2 rows, each old_times 1 and new_times 0; absent true (no table, function or trigger of 0347 exists).
-- The OLD and NEW texts are 0347's own hunks, verbatim. Only the catalog is read.
begin transaction read only;
with h(fn, old, new) as (values
  ('world.stats_now()'::text, $h$           'counted_at', l.counted_at, 'counted_through', l.counted_through, 'drift', l.drift)
$h$, $h$           'news_head', (select max(n.id) from public.world_news n))$h$),
  ('public.client_rpc_entry_points()'::text, $h$      ('world',       'stats_now',             ''),
$h$, $h$'news_feed'$h$))
select h.fn,
       (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as old_times,
       (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) as new_times,
       (to_regclass('public.world_news') is null and to_regclass('public.news_kinds') is null
        and to_regprocedure('public.news_post(text,uuid,uuid,uuid,text,text,jsonb)') is null
        and not exists (select 1 from pg_trigger t where t.tgname in ('ports_news_harbour', 'power_relations_news', 'world_news_append_only'))) as absent,
       (select max(version) from supabase_migrations.schema_migrations) as head
  from h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) d
 order by h.fn;
commit;
