-- 0348 PROD CHECK (cost part 1 of 2), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/best-sales/parts-mid.sql
-- What world.board_sell's ranking costs per good: world.mid_price (STABLE, provolatile 's') at every harbour that lists 15 goods. Read "Execution Time".
-- Measured 2026-11-11 (head 0345): 710 and 764 ms for 15 goods x 249 harbours, so about 50 ms a good. EXPLAIN ANALYZE only of STABLE functions (CLAUDE.md).
begin transaction read only;
explain (analyze, format json)
select count(m) from (select world.mid_price(p.id, pg.good_id, pg.stock) m
  from public.port_goods pg join public.ports p on p.id = pg.port_id
 where p.kind = 'HARBOUR' and pg.good_id in (select id from public.goods order by code limit 15)) x;
commit;
