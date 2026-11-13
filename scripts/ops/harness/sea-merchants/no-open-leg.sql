-- PROD CHECK (read-only, ONE statement): npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-merchants/no-open-leg.sql
-- WHO ARE THE MERCHANTS WITH NO OPEN LEG? The merchants' guard (public.sea_conditions_npc_ready, 0399) read `merchants_with_no_open_leg` 8 on prod on
-- 2026-11-14: merchants whose loop has a leg their hull cannot hold AND who have no known leg from home that it can. This names each one, counted exactly as
-- the guard counts (0397's readers, the plain rule on wave only), so it runs at head 0399, before 0400:
--   company, fleet, status, hulls (class and wave), her fleet's wave
--   home (the first stop of her route), its sea and what that sea asks (title rank / wave); her house's home port when it is another harbour
--   known_legs, and the nearest of them with the sea that refuses it and the wave it asks
--   nearest_open: the nearest harbour whose pair row (public.sea_leg_asks, the straight line from her home) her wave holds, and its miles
--   held_with_home_waters: how many of her known legs 0400's floor would open (seas of her home's rank asking no more wave than her home's sea)
-- Every function called is STABLE or IMMUTABLE (public.fleet_wave, voyage.fleet_speed_at, public.npc_loop_sea_shut, public.npc_feasible_legs,
-- public.npc_sea_shut, public.npc_course_zones, public.harbour_zone, voyage.gc_distance_nm): public.sea_conditions_npc_ready, itself STABLE, calls the same.
begin transaction read only;
with m as materialized (
  select nf.fleet_id, nf.player_id, f.status, public.fleet_wave(nf.fleet_id) as wave,
         greatest(coalesce(voyage.fleet_speed_at(nf.fleet_id, 1), 0), 0.1) as speed,
         (select st.port_id from public.standing_route_stops st where st.route_id = nf.route_id order by st.ord limit 1) as home,
         public.npc_loop_sea_shut(nf.fleet_id, (select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord)
                                                  from public.standing_route_stops st where st.route_id = nf.route_id)) as shut
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
   where nf.route_id is not null
), legs as materialized (
  select m.*, l.legs
    from m cross join lateral (select public.npc_feasible_legs(m.home, m.fleet_id, m.speed, 400) as legs) l
   where m.shut and m.home is not null
), stuck as (
  select g.* from legs g
   where jsonb_array_length(g.legs) > 0
     and not exists (select 1 from jsonb_array_elements(g.legs) x where public.npc_sea_shut(g.wave, (x ->> 'port_id')::uuid, x -> 'course') is null)
)
select pl.company_name as company, f.name as fleet, s.status, s.wave,
       (select string_agg(c.code || ' ' || c.wave, ', ' order by c.wave desc) from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = s.fleet_id) as hulls,
       hp.code as home, hz.code as home_sea, hz.title_min as home_rank, hz.wave_min as home_sea_asks_wave,
       (select p.code from public.npc_houses nh join public.ports p on p.id = nh.home_port_id where nh.player_id = s.player_id and nh.home_port_id <> s.home) as house_home_if_other,
       jsonb_array_length(s.legs) as known_legs,
       (select jsonb_build_object('to', x ->> 'code', 'nm', round((x ->> 'nm')::numeric),
                                  'refused_by', r.j -> 'figures' ->> 'zone_name', 'asks_wave', (r.j -> 'figures' ->> 'needs_wave')::int)
          from jsonb_array_elements(s.legs) x
         cross join lateral (select public.npc_sea_shut(s.wave, (x ->> 'port_id')::uuid, x -> 'course') as j) r
         order by (x ->> 'nm')::numeric limit 1) as nearest_known_leg,
       (select jsonb_build_object('to', p.code, 'nm', round(voyage.gc_distance_nm(ra.roadstead_lat, ra.roadstead_lon, rb.roadstead_lat, rb.roadstead_lon)::numeric))
          from public.sea_leg_asks a join public.ports p on p.id = a.to_port and p.kind = 'HARBOUR'
          join public.sea_reaches ra on ra.port_id = a.from_port join public.sea_reaches rb on rb.port_id = a.to_port
         where a.from_port = s.home and a.to_port <> s.home and a.wave_min <= s.wave
         order by voyage.gc_distance_nm(ra.roadstead_lat, ra.roadstead_lon, rb.roadstead_lat, rb.roadstead_lon) limit 1) as nearest_open,
       (select count(*) from jsonb_array_elements(s.legs) x
         where not exists (select 1 from public.sea_zones z
                            where z.code = any (public.npc_course_zones(x -> 'course') || array_remove(array[public.harbour_zone((x ->> 'port_id')::uuid)], null))
                              and z.wave_min > case when z.title_min = hz.title_min then greatest(s.wave, hz.wave_min) else s.wave end)) as held_with_home_waters
  from stuck s
  join public.players pl on pl.id = s.player_id
  join public.fleets f on f.id = s.fleet_id
  join public.ports hp on hp.id = s.home
  left join public.sea_leg_asks ha on ha.from_port = s.home and ha.to_port = s.home
  left join public.sea_zones hz on hz.code = ha.zones[1]
 order by hz.title_min, hp.code, pl.company_name;
commit;
