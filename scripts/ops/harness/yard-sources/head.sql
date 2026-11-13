-- 0358 PROD CHECK (head), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/yard-sources/head.sql
-- Wanted: head is the migration before 0358 in the deploy order (0357 when 0354 to 0357 have deployed); yard_sources_recut false (0358 is not applied); update_rows 0.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select p.prosrc like '%0358%' from pg_proc p where p.oid = 'world.yard_sources(uuid,text)'::regprocedure) as yard_sources_recut,
       (select count(*) from public.world_news w where w.key = 'update:0358') as update_rows;
commit;
