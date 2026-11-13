-- 0363 PROD CHECK (who already holds something), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/second-ship/holders.sql
-- Run BEFORE and AFTER the deploy and keep both answers. 0363 writes to none of these rows, so the two answers differ only by what the players did in between.
-- One row a thing: the two parts the Barca took (kept in a city), the three goods only those parts took (flax, hemp, iron) in storage and in holds, and the four hull goods in storage.
-- Human companies only. Counts and sums, no name. Wanted: nothing asserted before; after, no figure is lower than before unless a player spent it.
begin transaction read only;
select 'part kept in a city' as what, pi.item_code as code, count(distinct pi.player_id) as companies, sum(pi.qty)::numeric as qty
  from public.player_items pi join public.players pl on pl.id = pi.player_id and not pl.is_npc
 where pi.item_code in ('suit-of-sails', 'anchor-and-cable')
 group by pi.item_code
union all
select 'part good in storage', g.code, count(distinct ps.player_id), sum(ps.qty)
  from public.player_storage ps join public.players pl on pl.id = ps.player_id and not pl.is_npc
  join public.goods g on g.id = ps.good_id
 where g.code in ('flax', 'hemp', 'iron')
 group by g.code
union all
select 'part good in a hold', c.key, count(distinct s.player_id), sum(c.value::numeric)
  from public.ships s join public.players pl on pl.id = s.player_id and not pl.is_npc
 cross join lateral jsonb_each_text(coalesce(s.cargo, '{}'::jsonb)) c
 where c.key in ('flax', 'hemp', 'iron') and c.value::numeric > 0
 group by c.key
union all
select 'hull good in storage', g.code, count(distinct ps.player_id), sum(ps.qty)
  from public.player_storage ps join public.players pl on pl.id = ps.player_id and not pl.is_npc
  join public.goods g on g.id = ps.good_id
 where g.code in ('timber', 'tar', 'cordage', 'ships-nails')
 group by g.code
 order by 1, 2;
commit;
