-- 0350 PROD CHECK (before), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/best-sales/mids-before.sql
-- THE PREMISE, on the live market: the price worked out in one pass (world.mid_from_terms on the row's terms, as world.good_mids will) is world.mid_price for every
-- market row of 15 goods. Wanted: rows > 0, differ 0. STABLE and IMMUTABLE functions only; nothing is written.
begin transaction read only;
select count(*) as rows,
       count(*) filter (where world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.glut, pg.stock_target, pg.stock, pg.drift,
                                                   pg.season_mod, p.dev_commerce,
                                                   (select public.wc_num('price_elasticity')), (select public.wc_num('mid_dev_discount')),
                                                   (select public.wc_num('price_band_lo')), (select public.wc_num('price_band_hi')))
                              is distinct from world.mid_price(pg.port_id, pg.good_id, pg.stock)) as differ
  from public.port_goods pg
  join public.goods g on g.id = pg.good_id
  join public.ports p on p.id = pg.port_id
 where pg.good_id in (select g.id from public.goods g order by g.code limit 15);
commit;
