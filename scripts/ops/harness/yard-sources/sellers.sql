-- 0358 PROD CHECK (sellers), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/yard-sources/sellers.sql
-- Where each of the seven goods of a Barca is sold (the roster and the culture gate cmd.do_buy applies), the sailed miles from Lisbon, and what each seller asks now (world.price, STABLE).
-- Wanted: the nearest seller (nearest_rank 1) of flax is Riga, of hemp Naples, of iron Lisbon (0 miles); timber Funchal, ships-nails La Rochelle, cordage Portsmouth, tar Bergen;
-- every row has_market_row true (a seller with no market row would be served ask null). The asks are prod's own: the local world's are in docs/dev-log/2026-11-12-yard-plan.md.
begin transaction read only;
select g.code as good, p.code as port, p.name,
       round(case when p.code = 'LIS' then 0 else (sr.reaches ->> p.code)::numeric end) as miles,
       row_number() over (partition by g.code order by case when p.code = 'LIS' then 0 else (sr.reaches ->> p.code)::numeric end nulls last, p.name) as nearest_rank,
       exists (select 1 from public.port_goods pg where pg.port_id = p.id and pg.good_id = g.id) as has_market_row,
       (select pr.ask from public.port_goods pg cross join lateral world.price(pg.port_id, pg.good_id) pr where pg.port_id = p.id and pg.good_id = g.id) as ask
  from public.goods g
  join public.ports p on p.kind = 'HARBOUR'
  join lateral public.port_offered_goods(p.id) o on o.good_id = g.id
  left join public.sea_reaches sr on sr.port_id = (select id from public.ports where code = 'LIS')
 where g.code in ('timber', 'ships-nails', 'cordage', 'tar', 'flax', 'hemp', 'iron')
   and not public.culture_refuses(p.culture, g.culture_mask)
 order by g.code, nearest_rank;
commit;
