-- 0363 PROD CHECK (before the deploy), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/second-ship/before.sql
-- Wanted: head is the migration before 0363 in the deploy order; yard_plan_applied true (0358 is live: 0363 refuses without it); barca_parts is exactly
-- [{"item": "anchor-and-cable", "qty": 1}, {"item": "suit-of-sails", "qty": 1}] and barca_note the "Two fittings" sentence (the file refuses anything else);
-- barca_goods 4; hulls_with_a_part 14; carlat_parts 4; nau_parts 5; update_rows 0. Only rule tables and the catalog are read.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select p.prosrc like '%0358: THE WHOLE LIST%' from pg_proc p where p.oid = 'world.yard_sources(uuid,text)'::regprocedure) as yard_plan_applied,
       (select coalesce(jsonb_agg(jsonb_build_object('item', hi.item_code, 'qty', hi.qty) order by hi.item_code), '[]'::jsonb)
          from public.hull_recipe_items hi where hi.class_code = 'barca') as barca_parts,
       (select r.note from public.hull_recipes r where r.class_code = 'barca') as barca_note,
       (select count(*) from public.hull_recipe_goods hg where hg.class_code = 'barca') as barca_goods,
       (select count(distinct hi.class_code) from public.hull_recipe_items hi) as hulls_with_a_part,
       (select count(*) from public.hull_recipe_items hi where hi.class_code = 'carlat') as carlat_parts,
       (select count(*) from public.hull_recipe_items hi where hi.class_code = 'nau') as nau_parts,
       (select count(*) from public.world_news w where w.key = 'update:0363') as update_rows;
commit;
