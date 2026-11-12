-- 0358 PROD CHECK (premise), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/yard-sources/premise.sql
-- The answer today for the Barca at the yard of Lisbon (world.yard_sources is STABLE), beside the recipes of her parts, which the answer does not name yet.
-- Wanted: goods = 4 rows with a seller each, items = 2 rows made at Lisbon, no qty, ask or inputs key; parts_goods names the goods of the two parts (flax, hemp, iron among them).
-- Keep the answer: after-keys.sql is read against it.
begin transaction read only;
select world.yard_sources((select id from public.ports where code = 'LIS'), 'barca') as answer_today,
       (select jsonb_agg(jsonb_build_object('part', hi.item_code, 'good', g.code, 'qty', ir.qty * hi.qty, 'bulk', g.bulk) order by hi.item_code, g.code)
          from public.hull_recipe_items hi join public.item_recipes ir on ir.item_code = hi.item_code join public.goods g on g.id = ir.good_id
         where hi.class_code = 'barca') as parts_goods,
       (select jsonb_agg(jsonb_build_object('good', g.code, 'qty', hg.qty, 'bulk', g.bulk) order by g.code)
          from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id where hg.class_code = 'barca') as hull_goods,
       (select count(*) from public.hull_recipes) as hulls,
       (select count(distinct hi.class_code) from public.hull_recipe_items hi) as hulls_with_a_part,
       (select count(*) from public.port_buildings b where b.kind = 'building_yard') as yards;
commit;
