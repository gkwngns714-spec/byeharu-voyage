-- 0460 PROD CHECK, AFTER the deploy (every raw good has a quay), read-only, one SELECT inside `begin transaction read only; ... commit;`:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/quay-goods/after-0460.sql
-- One row, one jsonb column `r`. Plain columns of small tables and port_goods (one scan); no function but the catalog's.
-- Wanted: head 20260818000460; knobs exactly as before-0460 read them; affinity_knobs_as_0460 true; raw_on_no_quay 7 (the land's);
--   raw_no_source 0; offers 1448; offers_0460 36; market_rows 159766 (0460 adds no market row); base_target_set as before;
--   untouched_digest EXACTLY as before-0460 read it (no row of any other good moved); water: rows 254, bil_base 402, lis_base 554
--   (Bilbao is Fresh Water's producer and Lisbon's nearest source did not move: both rows unmoved).
begin transaction read only; ... commit;`:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/quay-goods/after-0460.sql
-- One row, one jsonb column `r`. Plain columns of small tables and port_goods (one scan); no function but the catalog's.
-- Wanted: head 20260818000460; knobs exactly as before-0460 read them; affinity_knobs_as_0460 true; raw_on_no_quay 0; offers 1455;
--   offers_0460 43; market_rows unchanged (159766: 0460 adds no market row); base_target_set as before;
--   water: rows 254, bil_base 4020, lis_base 5540 (the rule: 0005 x market_depth 10); bil_target / lis_target = base x the
--   harbour's multiple (about 10 x what before-0460 read). market_digest: a new value (the re-derived rows moved).
begin transaction read only;
with pairs(port, good) as (values ('ARI', 'agave'), ('DUB', 'apple'), ('COL', 'bamboo'), ('PAN', 'bark'), ('CHE', 'betel-leaf'), ('LAR', 'cabbage'), ('ARI', 'cacao-bean'), ('PRT', 'cassava-root'), ('MLG', 'cattle'), ('BSR', 'coffee-bean'), ('XIA', 'eel'), ('OPO', 'eggs'), ('BIL', 'fresh-water'), ('ROT', 'goose-feathers'), ('LPA', 'grapes'), ('ZAN', 'honeybush-leaf'), ('QUA', 'lychee'), ('BND', 'milk'), ('TAI', 'mint'), ('BNT', 'nipa'), ('RIO', 'palm-fruit'), ('MOM', 'palm-leaf'), ('ISL', 'palm-sap'), ('CPT', 'pandanus'), ('ARK', 'pear'), ('PTH', 'plum'), ('LUA', 'raffia'), ('SAK', 'ramie'), ('ALG', 'rose'), ('BEI', 'sesame'), ('CPT', 'shea-nut'), ('BAN', 'shrimp'), ('YEO', 'soybean'), ('SGO', 'sugar-cane'), ('YEO', 'tea-leaf'), ('BOS', 'witch-hazel-bark')),
k as (select c.key, c.value from public.world_config c
       where c.key in ('affinity_curve', 'affinity_home', 'affinity_producer', 'affinity_reach_nm', 'affinity_span',
                       'market_depth', 'depth_by_investment', 'stock_tier_scale', 'stock_rare_scale', 'stock_floor_units'))
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(k.key, k.value) from k),
  'affinity_knobs_as_0460', (select count(*) = 5 from k where (k.key, k.value) in (('affinity_curve', '0.88'::jsonb), ('affinity_home', '1.00'::jsonb),
                              ('affinity_producer', '0.93'::jsonb), ('affinity_reach_nm', '9500'::jsonb), ('affinity_span', '0.76'::jsonb))),
  'raw_on_no_quay', (select count(*) from public.goods g where g.tier = 0 and not exists (select 1 from public.port_specialties s where s.good_id = g.id)),
  'raw_no_source', (select count(*) from public.goods g where g.tier = 0 and not exists (select 1 from public.port_specialties s where s.good_id = g.id)
                     and not exists (select 1 from public.land_actions a where a.good_id = g.id and a.kind = 'gather')),
  'land_enabled', (select c.value from public.world_config c where c.key = 'land_enabled'),
  'offers', (select count(*) from public.port_specialties),
  'offers_0460', (select count(*) from pairs x join public.ports p on p.code = x.port join public.goods g on g.code = x.good
                   join public.port_specialties s on s.port_id = p.id and s.good_id = g.id),
  'market_rows', (select count(*) from public.port_goods),
  -- every market row of a good 0460 does not place: affinity, base max, production, haul, demand (equal before and after)
  'untouched_digest', (select md5(coalesce(string_agg(p.code || '|' || g.code || '|' || pg.affinity::text || '|' || coalesce(pg.base_target, pg.stock_target)::text
         || '|' || pg.production_rate::text || '|' || coalesce(pg.haul_nm::text, '-') || '|' || coalesce(pg.haul::text, '-') || '|' || pg.demand::text,
         ';' order by p.code collate "C", g.code collate "C"), ''))
    from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id
   where g.code not in (select x.good from pairs x)),
  'base_target_set', (select count(*) from public.port_goods pg where pg.base_target is not null),
  -- 0460's section 5b digest: each market row's affinity, base max (coalesce(base_target, stock_target)) and production
  'market_digest', (select md5(coalesce(string_agg(p.code || '|' || g.code || '|' || pg.affinity::numeric(6,3)::text || '|'
         || coalesce(pg.base_target, pg.stock_target)::numeric(14,2)::text || '|' || pg.production_rate::numeric(14,2)::text,
         ';' order by p.code collate "C", g.code collate "C"), ''))
    from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id),
  'water', (select jsonb_build_object('rows', count(*), 'sum_target', sum(pg.stock_target),
                    'bil_target', max(pg.stock_target) filter (where p.code = 'BIL'), 'lis_target', max(pg.stock_target) filter (where p.code = 'LIS'),
                    'bil_base', max(coalesce(pg.base_target, pg.stock_target)) filter (where p.code = 'BIL'),
                    'lis_base', max(coalesce(pg.base_target, pg.stock_target)) filter (where p.code = 'LIS'))
              from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id where g.code = 'fresh-water')) as r;
commit;
