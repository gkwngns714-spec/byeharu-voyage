-- 0403 PROD CHECK, BEFORE and AFTER the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pair-table/counts-0403.sql
-- How many harbours Trade lists as open, one leg away, for a title-1 company in a barca (wave 12) lying at each of four harbours, her capital's sea being
-- that harbour's own: the door's judge (public.sea_judge, stable) over the pair row's seas and the destination's sea, as public.sea_routes asks it lit.
-- Cached world, before -> after: Lisbon 82 -> 82; Sakai 55 -> 45; Surat 108 -> 25; Port Royal 24 -> 19.
begin transaction read only;
select o.name, o.code, count(*) filter (where public.sea_judge(1, 12, s.zones || od.zones, zo.title_min, zo.wave_min, zo.title_min, zo.wave_min) is null) as open_harbours,
       count(*) as harbours
  from public.ports o
  join public.sea_leg_asks os on os.from_port = o.id and os.to_port = o.id
  join public.sea_zones zo on zo.code = os.zones[1]
  join public.sea_leg_asks s on s.from_port = o.id and s.to_port <> o.id
  join public.sea_leg_asks od on od.from_port = s.to_port and od.to_port = s.to_port
 where o.code in ('LIS', 'SAK', 'SRT', 'POR')
 group by o.name, o.code order by o.name;
commit;
