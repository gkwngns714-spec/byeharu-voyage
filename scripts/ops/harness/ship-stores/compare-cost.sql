-- 0345 PROD READ (cost of the migration's world compare), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/ship-stores/compare-cost.sql
-- 0345 section 6 runs this set of reads TWICE in one statement (the new body and its pg_temp pre-image). Before 0345 the two sides are the same live bodies, so this runs each read twice to price it.
-- Time it with the CLI round trip subtracted. Wanted: a few seconds at most, well inside the file's 45 s. Only STABLE functions are called (fleet_free_hold, supply_reach, supply_needs, world.ship_view).
begin transaction read only;
with sel as (
  select f.id from public.fleets f join public.players p on p.id = f.player_id where not p.is_npc
  union
  select x.id from (select f.id from public.fleets f join public.players p on p.id = f.player_id where p.is_npc order by f.id limit 20) x
)
select (select count(*) from sel f
         where public.fleet_free_hold(f.id) is distinct from public.fleet_free_hold(f.id)
            or (select r::text from public.supply_reach(f.id) r) is distinct from (select r::text from public.supply_reach(f.id) r)
            or (select string_agg(x::text, ';' order by x.nm) from public.supply_needs(f.id, array[500, 2000]::numeric[]) x)
                 is distinct from (select string_agg(x::text, ';' order by x.nm) from public.supply_needs(f.id, array[500, 2000]::numeric[]) x)) as bad_fleets,
       (select count(*) from (select s.id from public.ships s join sel on sel.id = s.fleet_id offset 0) s where world.ship_view(s.id) is distinct from world.ship_view(s.id)) as bad_ships,
       (select count(*) from sel) as fleets,
       (select count(*) from public.ships s join sel on sel.id = s.fleet_id) as ships;
commit;
