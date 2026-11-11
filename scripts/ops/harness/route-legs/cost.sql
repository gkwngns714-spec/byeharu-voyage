-- 0346 PROD COST CHECK, read-only, one statement: time npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/route-legs/cost.sql
-- What world.route_legs composes for a SHUT leg, on the docked human fleet with the most ships: one public.supply_needs over two lengths, two
-- voyage.leg_refusal, one public.supply_reach and one voyage.reach_passage (the O(n^2) arm). Every function called is STABLE ('s', before.sql
-- prints it); no clock is read: the wall time of this call, less head.sql's, is the cost. Wanted: rows > 200, a refusal code on the far leg.
begin transaction read only;
with f as (
  select fl.id, fl.player_id, fl.port_id
    from public.fleets fl join public.players p on p.id = fl.player_id
   where not p.is_npc and fl.port_id is not null
   order by (select count(*) from public.ships s where s.fleet_id = fl.id) desc, fl.id
   limit 1
), far as (
  select r.port_id, r.nm from f cross join lateral voyage.reach_from(f.port_id) r order by r.nm desc limit 1
), near as (
  select r.port_id, r.nm from f cross join lateral voyage.reach_from(f.port_id) r where r.nm > 0 order by r.nm limit 1
)
select jsonb_build_object(
  'needs', (select jsonb_agg(to_jsonb(n)) from f, near, far, lateral public.supply_needs(f.id, array[near.nm, far.nm]) n),
  'near_refusal', (select voyage.leg_refusal(f.id, near.port_id, near.nm, null) from f, near),
  'far_refusal', (select voyage.leg_refusal(f.id, far.port_id, far.nm, null)->>'code' from f, far),
  'reach_rows', (select count(*) from f cross join lateral voyage.reach_passage(f.player_id, f.id, f.port_id, (select sr.cap_nm from public.supply_reach(f.id) sr)) r)
) as cost;
commit;
