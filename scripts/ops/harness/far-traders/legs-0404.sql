-- 0404 PROD CHECK, BEFORE the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/far-traders/legs-0404.sql
-- Run only after before-0404.sql showed every volatility s or i. 15 rows, one a home. Wanted: open_both_ways 1 or more on EVERY row (0 on a row: the
-- migration refuses itself there and nothing is written; tell the builder). first_loop is the harbour the house will be founded sailing to.
begin transaction read only;
select h.code as home,
       (select count(*) from public.npc_known_legs(h.id) l) as remembered_legs,
       (select count(*) from public.npc_known_legs(h.id) l join public.ports p on p.id = l.to_port
         where p.kind = 'HARBOUR' and not p.is_ice_closed and public.npc_sea_shut(57, l.to_port, l.course) is null
           and not exists (select 1 from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id where a.port_id = p.id and a.home and g.pirate)
           and public.npc_sea_shut(57, h.id, (select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(l.course) with ordinality t(x, i))) is null) as open_both_ways,
       (select l.code || ' ' || round(l.nm) || ' nm' from public.npc_known_legs(h.id) l join public.ports p on p.id = l.to_port
         where p.kind = 'HARBOUR' and not p.is_ice_closed and public.npc_sea_shut(57, l.to_port, l.course) is null
           and not exists (select 1 from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id where a.port_id = p.id and a.home and g.pirate)
           and public.npc_sea_shut(57, h.id, (select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(l.course) with ordinality t(x, i))) is null
         order by l.nm, l.to_port limit 1) as first_loop
  from public.ports h
 where h.code in ('AMB','BND','CPT','DIL','GAL','HAG','HOB','KOL','MAK','OLD','PLO','STG','SYD','TER','TID')
 order by h.code;
commit;
