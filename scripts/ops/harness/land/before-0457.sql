-- 0457 BEFORE-CHECK (the land keeps the market guard), read-only, one SELECT inside `begin transaction read only; ... commit;`. Run before
-- the deploy:   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/land/before-0457.sql
-- Calls no function (the knobs are read from world_config's rows; md5, string_agg and percentile_disc only).
-- Wanted: head 20260818000456; rows_as_0455 true (0457 refuses otherwise); land_enabled false; working 0; knobs yield 100, level speed 0.2,
--   crowd max 10, best tool 3 (the generator's FASTEST; a faster one fails 0457's self-assert); worst_share at most 1: THE GUARD on
--   production's own port_goods (each harbour's least target, base x depth_m0), with 0457's seconds (the self-assert proves the same at the push and rolls back if it fails).
-- The seconds below are scripts/build-land-migration.mjs's output for 0457 (code, seconds).
begin transaction read only;
with k as (
  select max(case when c.key = 'land_yield_pct' then (c.value #>> '{}')::numeric end) as yield,
         max(case when c.key = 'land_level_speed_pct' then (c.value #>> '{}')::numeric end) as lvl,
         max(case when c.key = 'land_crowd_max' then (c.value #>> '{}')::numeric end) as crowd,
         (select max(t.speed_pct) from public.land_tools t) as tool
    from public.world_config c where c.key in ('land_yield_pct', 'land_level_speed_pct', 'land_crowd_max')),
new_rows(code, seconds) as (values ('coal', 295), ('iron', 645), ('clay', 16970), ('stone', 16970), ('sand', 16970), ('copper', 1700), ('salt', 1040), ('tin', 490), ('lead', 335), ('lime', 16970), ('gypsum', 16970), ('sulphur', 500), ('alum', 450), ('saltpetre', 445), ('zinc-spelter', 465), ('ochre', 445), ('feldspar', 14975), ('quartz', 12270), ('silver', 11315), ('marble', 450), ('antimony', 295), ('cobalt', 345), ('quicksilver', 1325), ('cinnabar', 255), ('alum-shale', 380), ('swedish-iron', 520), ('osmund-iron', 505), ('bar-iron', 290), ('japan-copper', 305), ('chilean-copper', 635), ('tin-ingots', 300), ('gold', 6930), ('gold-dust', 3690), ('amber', 300), ('baltic-amber', 720), ('lodestone', 305), ('potosi-silver', 3690), ('zacatecas-silver', 3300), ('turquoise', 350), ('carnelian', 380), ('malachite', 2535), ('onyx', 2930), ('lapis-lazuli', 2295), ('opals', 4495), ('peridot', 2320), ('jade', 2025), ('nephrite', 2980), ('pounamu', 765), ('emeralds', 2535), ('emerald-muzo', 2535), ('rubies', 3090), ('burma-rubies', 2065), ('ceylon-sapphires', 2490), ('diamonds', 3380), ('golconda-diamonds', 2955), ('platinum', 3690), ('andacollo-gold', 4220)),
pace as (
  select n.code, g.id as good_id,
         3600.0 / greatest(1, round(n.seconds * 100.0 / k.yield * (1 - k.lvl / 100 * 99) * (1 - k.tool / 100))) * (1 + k.crowd / 100) as per_hour
    from new_rows n join public.goods g on g.code = n.code cross join k),
mid as (
  select g.id as good_id, rg.code as region, percentile_disc(0.5) within group (order by coalesce(pg.base_target, pg.stock_target) * least(1, coalesce((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'depth_m0'), 1))) as target
    from public.goods g
    cross join unnest(g.origin_regions) o(rc)
    join public.regions rg on rg.code = o.rc
    join public.ports p on p.region_id = rg.id and p.kind = 'HARBOUR'
    join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id
   where g.code in (select n.code from new_rows n)
   group by g.id, rg.code),
share as (
  select pace.code, mid.region, mid.target, round(pace.per_hour / (mid.target / 100.0), 4) as share
    from pace join mid on mid.good_id = pace.good_id)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'rows_as_0455', (select md5(string_agg(a.code || ':' || a.seconds || ':' || a.xp, ',' order by a.ord)) from public.land_actions a) = '038762af620084222a9f7e40cacc95c5',
  'land_enabled', (select c.value from public.world_config c where c.key = 'land_enabled'),
  'working', (select count(*) from public.land_parties lp where lp.action is not null),
  'knobs', (select to_jsonb(k) from k),
  'jobs_judged', (select count(distinct s.code) from share s),
  'job_regions', (select count(*) from share s),
  'worst_share', (select jsonb_build_object('code', s.code, 'region', s.region, 'target', s.target, 'share', s.share) from share s order by s.share desc, s.code limit 1)) as r;
commit;
