-- 0350 PROD CHECK (after), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/best-sales/mids-after.sql
-- world.good_mids is world.mid_price on the live market, for every market row of 15 goods. Wanted: rows > 0, differ 0, and rows = market_rows.
-- STABLE functions only; nothing is written.
begin transaction read only;
select count(*) as rows,
       count(*) filter (where m.mid is distinct from world.mid_price(m.port_id, s.id, m.stock)) as differ,
       (select count(*) from public.port_goods pg where pg.good_id in (select g.id from public.goods g order by g.code limit 15)) as market_rows
  from (select g.id from public.goods g order by g.code limit 15) s
 cross join lateral world.good_mids(s.id) m;
commit;
