-- 0358 PROD CHECK (who this is for), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/yard-sources/who.sql
-- The human companies by country: how many, how many ships they hold, how many hold one ship (the companies the sheet is for) and how many hold two or more.
-- Wanted: nothing asserted; the design counted 19 human companies, 3 with two hulls. Counts only, no name.
begin transaction read only;
select n.code as country,
       count(*) as companies,
       sum(s.ships) as ships,
       count(*) filter (where s.ships = 1) as with_one_ship,
       count(*) filter (where s.ships >= 2) as with_two_or_more,
       max(s.ships) as most_ships
  from public.players pl
  join public.nations n on n.id = pl.nation_id
 cross join lateral (select count(*) as ships from public.ships sh where sh.player_id = pl.id) s
 where not pl.is_npc
 group by n.code
 order by companies desc, n.code;
commit;
