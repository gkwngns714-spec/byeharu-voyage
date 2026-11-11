-- 0349 PROD CHECK (read-only): the body of world.yard_sources at Lisbon's yard for the Barca, as a plain SELECT
-- (every function it calls is STABLE: port_offered_goods, culture_refuses, made_only_in). Run BEFORE the deploy:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/yard-sources/answer.sql
-- Wanted: one row; goods = 4 rows with a seller each, items = 2 rows with a maker each; the answer itself.
begin transaction read only;
  with dist as materialized (
    select p.id, p.code, p.name, p.culture,
           case when p.id = (select id from public.ports where code = 'LIS') then 0::numeric else (sr.reaches ->> p.code)::numeric end as miles
      from public.ports p
      left join public.sea_reaches sr on sr.port_id = (select id from public.ports where code = 'LIS')
     where p.kind = 'HARBOUR'),
  sold as materialized (
    select distinct on (g.id) g.id as good_id, d.code, d.name, d.miles
      from public.hull_recipe_goods hg
      join public.goods g on g.id = hg.good_id
      cross join dist d
      join lateral public.port_offered_goods(d.id) o on o.good_id = g.id
     where hg.class_code = 'barca'
       and not public.culture_refuses(d.culture, g.culture_mask)
     order by g.id, d.miles nulls last, d.name),
  can as materialized (
    select k.code as item, d.id, d.code, d.name, d.miles
      from public.hull_recipe_items hi
      join public.item_kinds k on k.code = hi.item_code
      join public.port_buildings b on b.kind = 'workstation' and b.tier >= k.ws_tier
      join dist d on d.id = b.port_id
     where hi.class_code = 'barca'),
  made as materialized (
    select distinct on (c.item) c.item, c.code, c.name, c.miles
      from can c
     where public.made_only_in(c.item, c.id) is null
     order by c.item, c.miles nulls last, c.name)
  select jsonb_build_object(
    'port_id', (select id from public.ports where code = 'LIS'),
    'class', 'barca',
    'goods', coalesce((
      select jsonb_agg(jsonb_build_object('code', g.code, 'port', s.code, 'name', s.name, 'miles', round(s.miles)) order by g.code)
        from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id
        left join sold s on s.good_id = g.id
       where hg.class_code = 'barca'), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('code', k.code, 'port', m.code, 'name', m.name, 'miles', round(m.miles)) order by k.code)
        from public.hull_recipe_items hi join public.item_kinds k on k.code = hi.item_code
        left join made m on m.item = k.code
       where hi.class_code = 'barca'), '[]'::jsonb));
commit;
