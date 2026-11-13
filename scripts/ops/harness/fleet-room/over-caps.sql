-- 0354 PROD CHECK (over-caps), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/fleet-room/over-caps.sql
-- READ THIS BEFORE LIGHTING `fleet_room_bite` (F6). For every company, what the LIT caps would be, against what she holds today, by kind of house.
-- The lit caps are public.fleet_room_caps (the ladders, which do not read the switch) and, for hulls, fleets x ships a fleet for a human and public.house_ship_max for every other house
-- (lit, 0321 leaves a merchant's hull cap as it is). All three are STABLE (volatility-0354.sql). It runs dark or lit and needs only 0321.
-- Wanted: over_fleets, over_ships_a_fleet and over_hulls 0 in every row. A house over a cap meets E_SHIP_MAX, E_FLEET_MAX or E_FLEET_SHIP_MAX on her next new ship, new fleet or moved ship (the caps trigger, 0021),
-- never on a voyage or a trade. `at_*` counts houses standing exactly at a cap: lit, their next hull or fleet is refused. `names` lists up to 20 houses over a cap.
begin transaction read only;
with h as (
  select p.id, p.company_name, p.is_npc,
         case when not p.is_npc then 'HUMAN'
              when exists (select 1 from public.cargo_ships c where c.player_id = p.id) then 'CARGO_SHIP'
              when exists (select 1 from public.navy_ships n where n.player_id = p.id) then 'NAVY'
              when exists (select 1 from public.pirate_ships n where n.player_id = p.id) then 'PIRATE'
              else 'MERCHANT' end as kind,
         public.fleet_room_caps(p.id) as lit,
         (select count(*) from public.fleets f where f.player_id = p.id) as fleets,
         (select count(*) from public.ships s where s.player_id = p.id) as ships,
         (select coalesce(max(x.n), 0) from (select count(*) as n from public.ships s where s.player_id = p.id group by s.fleet_id) x) as most
    from public.players p
), j as (
  select h.*, (h.lit ->> 'fleet_max')::int as lit_fleets, (h.lit ->> 'fleet_ship_max')::int as lit_ships,
         case when h.is_npc then public.house_ship_max(h.id) else (h.lit ->> 'fleet_max')::int * (h.lit ->> 'fleet_ship_max')::int end as lit_hulls
    from h
)
select j.kind, count(*) as houses,
       count(*) filter (where j.fleets > j.lit_fleets) as over_fleets,
       count(*) filter (where j.most > j.lit_ships) as over_ships_a_fleet,
       count(*) filter (where j.ships > j.lit_hulls) as over_hulls,
       count(*) filter (where j.fleets = j.lit_fleets) as at_fleets,
       count(*) filter (where j.most = j.lit_ships) as at_ships_a_fleet,
       count(*) filter (where j.ships = j.lit_hulls) as at_hulls,
       max(j.fleets) as most_fleets, min(j.lit_fleets) as least_lit_fleets,
       max(j.most) as most_ships_a_fleet, min(j.lit_ships) as least_lit_ships_a_fleet,
       max(j.ships) as most_hulls, min(j.lit_hulls) as least_lit_hulls,
       (select coalesce(jsonb_agg(q.company_name order by q.company_name), '[]'::jsonb)
          from (select k.company_name from j k where k.kind = j.kind and (k.fleets > k.lit_fleets or k.most > k.lit_ships or k.ships > k.lit_hulls) order by k.company_name limit 20) q) as names
  from j
 group by j.kind
 order by j.kind;
commit;
