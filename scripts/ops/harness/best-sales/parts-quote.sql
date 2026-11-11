-- 0348 PROD CHECK (cost part 2 of 2), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/best-sales/parts-quote.sql
-- What world.board_sell's priced rows cost: world.quote (STABLE, provolatile 's'), 15 harbours x 15 goods, sell 50 units. Read "Execution Time".
-- Measured 2026-11-11 (head 0345): 594 and 1,354 ms for 225 quotes, so 3 to 6 ms a quote.
begin transaction read only;
explain (analyze, format json)
select count(q.total) from (select pg.port_id, pg.good_id, row_number() over (partition by pg.good_id order by pg.port_id) rn
  from public.port_goods pg join public.ports p on p.id = pg.port_id
 where p.kind = 'HARBOUR' and pg.good_id in (select id from public.goods order by code limit 15)) s
 cross join lateral world.quote(s.port_id, s.good_id, 50, 'sell', null, null) q
 where s.rn <= 15;
commit;
