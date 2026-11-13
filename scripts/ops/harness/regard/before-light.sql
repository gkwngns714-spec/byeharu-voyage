-- 0373 PROD READ (before the light of regard_enabled), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/regard/before-light.sql
-- WHO PAYS MORE, AND WHO PAYS LESS, ON DAY ONE. One row a company: with each country that holds a harbour, the band and the multiplier on her profit tax and her dock fee that the light
-- gives her at once, with no row written (the base of her power's stance: home 200, ally 100, peace 0, rival -100, war -200), plus anything she has earned.
--   pays_less   countries where her factor is under 1 (Friendly x0.9, Honoured x0.8), with the band and the factor.
--   pays_more   countries where it is over 1 (Wary x1.25, Hostile x2).
--   same        how many countries stay at x1.
-- The last row (company null) is the world: the switch, earned rows (wanted 0: the migration refuses otherwise), pairs by band, and `bad` (pairs with no band or no factor: wanted 0).
-- If this file ERRORS with E_NO_REGARD_BASE, do NOT light: a stance in power_relations has no base in regard_stance_base, and lit every tax quote in that country's cities would fail.
-- It reads the same answer dark and lit (public.regard_of and public.regard_band do not read the switch). Every function called is STABLE (regard_of, regard_band, port_nation, power_stance, wc).
begin transaction read only;
with n as (
  select distinct public.port_nation(p.id) as nation_id from public.ports p where p.kind = 'HARBOUR'
), x as (
  select pl.id, pl.company_name, hn.code as home, na.code as nation,
         public.power_stance(pl.nation_id, n.nation_id) as stance,
         round(public.regard_of(pl.id, n.nation_id)) as score,
         public.regard_band(public.regard_of(pl.id, n.nation_id)) as band
    from public.players pl
    left join public.nations hn on hn.id = pl.nation_id
   cross join n
    join public.nations na on na.id = n.nation_id
   where not pl.is_npc and n.nation_id is not null
)
select x.company_name as company, x.home,
       coalesce(jsonb_agg(jsonb_build_object('country', x.nation, 'stance', x.stance, 'band', x.band ->> 'band', 'factor', (x.band ->> 'factor')::numeric) order by x.nation)
                  filter (where (x.band ->> 'factor')::numeric < 1), '[]'::jsonb) as pays_less,
       coalesce(jsonb_agg(jsonb_build_object('country', x.nation, 'stance', x.stance, 'band', x.band ->> 'band', 'factor', (x.band ->> 'factor')::numeric) order by x.nation)
                  filter (where (x.band ->> 'factor')::numeric > 1), '[]'::jsonb) as pays_more,
       count(*) filter (where (x.band ->> 'factor')::numeric = 1) as same,
       null::jsonb as world
  from x group by x.id, x.company_name, x.home
union all
select null, null, null, null, null,
       jsonb_build_object('switch', public.wc('regard_enabled'),
                          'earned_rows', (select count(*) from public.house_regard),
                          'companies', (select count(distinct x.id) from x),
                          'pairs', (select count(*) from x),
                          'bad', (select count(*) from x where x.band is null or (x.band ->> 'factor') is null),
                          'by_band', (select jsonb_object_agg(b.k, b.c) from (select x.band ->> 'band' as k, count(*) as c from x group by 1) b),
                          'tax_reads_regard', public.city_treasury_on() and public.influence_on() and public.economy_closed())
 order by 1 nulls last;
commit;
