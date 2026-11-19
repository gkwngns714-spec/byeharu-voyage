-- 0457 AFTER-CHECK (the land keeps the market guard), read-only, one SELECT inside `begin transaction read only; ... commit;`. Run after
-- the deploy:   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/land/after-0457.sql
-- Wanted: head 20260818000457; rows_as_0457 true; comment_0457 true; land_enabled false; land_yield_pct 100; working 0; iron 645 / clay 16970.
-- Calls no function.
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'rows_as_0457', (select md5(string_agg(a.code || ':' || a.seconds || ':' || a.xp, ',' order by a.ord)) from public.land_actions a) = 'bd9026a3e5eb6ef5f240215fa438e73f',
  'comment_0457', (select d.description like '0457%' from pg_description d where d.objoid = 'public.land_actions'::regclass and d.objsubid = 0),
  'land_enabled', (select c.value from public.world_config c where c.key = 'land_enabled'),
  'land_yield_pct', (select c.value from public.world_config c where c.key = 'land_yield_pct'),
  'working', (select count(*) from public.land_parties lp where lp.action is not null),
  'iron_clay', (select jsonb_object_agg(a.code, a.seconds) from public.land_actions a where a.code in ('iron', 'clay'))) as r;
commit;
