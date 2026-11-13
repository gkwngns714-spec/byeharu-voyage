-- 0363 PROD CHECK (after the deploy), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/second-ship/after.sql
-- Wanted: head 20260818000363; barca_parts []; barca_note the new sentence (no "fittings"); barca_goods 4; hulls_with_a_part 13; carlat_parts 4; nau_parts 5;
-- sheet_parts [] and sheet_goods 4, each with a seller (world.yard_sources is STABLE); update_rows 1. Then run holders.sql again and read it against the answer kept before.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select coalesce(jsonb_agg(jsonb_build_object('item', hi.item_code, 'qty', hi.qty) order by hi.item_code), '[]'::jsonb)
          from public.hull_recipe_items hi where hi.class_code = 'barca') as barca_parts,
       (select r.note from public.hull_recipes r where r.class_code = 'barca') as barca_note,
       (select count(*) from public.hull_recipe_goods hg where hg.class_code = 'barca') as barca_goods,
       (select count(distinct hi.class_code) from public.hull_recipe_items hi) as hulls_with_a_part,
       (select count(*) from public.hull_recipe_items hi where hi.class_code = 'carlat') as carlat_parts,
       (select count(*) from public.hull_recipe_items hi where hi.class_code = 'nau') as nau_parts,
       y.answer -> 'items' as sheet_parts,
       jsonb_array_length(y.answer -> 'goods') as sheet_goods,
       (select jsonb_agg(jsonb_build_object('good', e.value ->> 'code', 'at', e.value ->> 'name', 'miles', e.value -> 'miles', 'ask', e.value -> 'ask') order by e.value ->> 'code')
          from jsonb_array_elements(y.answer -> 'goods') e) as sheet_sellers,
       (select count(*) from public.world_news w where w.key = 'update:0363') as update_rows
  from (select world.yard_sources((select id from public.ports where code = 'LIS'), 'barca') as answer) y;
commit;
