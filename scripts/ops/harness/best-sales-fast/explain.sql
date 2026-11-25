-- THE PLAN OF A GOOD'S 254 MARKET ROWS (world.good_mids' own read). A PROD CHECK: read-only, ONE statement, EXPLAIN without analyze: nothing runs.
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/best-sales-fast/explain.sql
-- Wanted: an index or bitmap scan of port_goods by good_id with about 254 rows. A sequential scan (159,766 rows) is the wrong plan.
begin transaction read only;
explain (verbose, costs, settings, summary)
select pg.port_id, pg.stock, pg.stock_target, g.base_value, p.dev_commerce
  from public.port_goods pg join public.goods g on g.id = pg.good_id join public.ports p on p.id = pg.port_id
 where pg.good_id = (select x.id from public.goods x where x.code = 'cinnamon');
rollback;
