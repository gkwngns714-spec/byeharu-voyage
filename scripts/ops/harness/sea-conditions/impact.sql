-- PROD CHECK (read-only, ONE statement): npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-conditions/impact.sql
-- WHAT LIGHTING THE SEA CONDITIONS WOULD DO, read off the world as it stands (docs/SEA_CONDITIONS_AND_REGIONS.md section 10). It lights nothing and judges
-- nothing through the switch: every verdict here is public.sea_refusal (the one rule), asked with her own title and her fleet's own wave.
-- Rows, each {section, data}:
--   switches        the two switches and the knobs read
--   ladder          for a fleet lying at Lisbon: the harbours she could sail to, by title 1-8 and by hull (barca 12, caravel 26, caravel + two fittings 31,
--                   nau 39, nau + planking 44, galleon 51, a ship of state 75)
--   company         ONE ROW A HUMAN COMPANY: her title and the two levels it is the lower of, her country and whether its capital's sea is open to her title,
--                   and each fleet: her wave, her hulls, the seas and harbours open to her, where she lies and whether that sea is open, the harbours she can
--                   still reach from there, whether she can get back to her capital, and the first sea that would refuse her voyage under way, each queued
--                   SAIL and each leg of her standing route
--   humans          the same, counted
--   merchants       IF sea_conditions_bite_npc WERE LIT (S3): fleets, loops with a leg her hull cannot hold, by hull size; those at sea now (they finish);
--                   closed loops whose fleet has no open known leg from where the loop starts (the "no open loop" figure: it must be 0)
--   merchants_seas  the seas that close those loops, most first
--   far_harbours    harbours no merchant loop would still call at
-- "Can reach" walks public.sea_leg_asks (the board's own table of what a harbour pair asks) over pairs no farther apart than nav_leg_nm_base, the reach of a
-- company with no navigation: a floor. A course under way and a route's legs are sampled with public.course_zones, exactly as the sail door samples them.
-- It names no table younger than 0222, so it runs on prod at any head since. Every function called is STABLE or IMMUTABLE (public.title_level, public.player_progress, public.fleet_wave, public.course_zones, public.sea_refusal,
-- public.wc_num, public.wc_int, voyage.gc_distance_nm): volatility.sql reads that on prod first.
begin transaction read only;
with recursive z as (
  select code, name, title_min, wave_min, ord from public.sea_zones
), hz as materialized (            -- a harbour's own sea: her self row in the board's table (the roadstead's zone)
  select p.id, p.code, a.zones[1] as zone, z.title_min, z.wave_min, r.roadstead_lat as lat, r.roadstead_lon as lon
    from public.ports p
    join public.sea_leg_asks a on a.from_port = p.id and a.to_port = p.id
    join z on z.code = a.zones[1]
    join public.sea_reaches r on r.port_id = p.id
   where p.kind = 'HARBOUR'
), edge as materialized (          -- a pair a company with no navigation may sail in one leg, and what its seas ask
  select a.from_port, a.to_port, a.title_min, a.wave_min
    from public.sea_leg_asks a join hz f on f.id = a.from_port join hz t on t.id = a.to_port
   where a.from_port <> a.to_port
     and voyage.gc_distance_nm(f.lat, f.lon, t.lat, t.lon) <= public.wc_num('nav_leg_nm_base')
), h as materialized (
  select p.id, p.company_name, n.code as nation, cap.id as capital, cap.code as capital_code, cap.title_min as capital_title,
         public.title_level(p.id) as title, public.player_progress(p.id) as prog
    from public.players p
    left join public.nations n on n.id = p.nation_id
    left join hz cap on cap.code = n.capital_port_code
   where not p.is_npc
), hf as materialized (
  select f.id, f.player_id, f.name, f.status, h.title, h.capital, public.fleet_wave(f.id) as wave,
         coalesce(f.port_id, v.dest_port_id) as here, v.id as voyage_id, v.path, v.dest_port_id,
         (select jsonb_agg(jsonb_build_object('class', c.code, 'wave', c.wave) order by c.wave desc)
            from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = f.id) as hulls
    from public.fleets f join h on h.id = f.player_id
    left join public.voyages v on v.fleet_id = f.id and v.status = 'SAILING'
), walk(fleet, port) as (
  select hf.id, hf.here from hf where hf.here is not null
  union
  select w.fleet, e.to_port
    from walk w join hf on hf.id = w.fleet
    join edge e on e.from_port = w.port and e.title_min <= hf.title and e.wave_min <= coalesce(hf.wave, -1)
), reach as (
  select w.fleet, count(*) - 1 as harbours, bool_or(w.port = hf.capital) as home
    from walk w join hf on hf.id = w.fleet group by w.fleet
), lw(t, hull, w, port) as (       -- the ladder: from Lisbon, by title and hull
  select t, x.hull, x.w, (select id from hz where code = 'LIS')
    from generate_series(1, 8) t
    cross join (values ('barca', 12), ('caravel', 26), ('caravel + 2 fittings', 31), ('nau', 39), ('nau + planking', 44), ('galleon', 51), ('ship of state', 75)) x(hull, w)
  union
  select l.t, l.hull, l.w, e.to_port from lw l join edge e on e.from_port = l.port and e.title_min <= l.t and e.wave_min <= l.w
), ladder as (
  select hull, w, jsonb_object_agg(t, n order by t) as by_title
    from (select t, hull, w, count(*) - 1 as n from lw group by 1, 2, 3) q group by hull, w
), voy as (                        -- a voyage under way: the seas its frozen course crosses, and its harbour's
  select hf.id as fleet,
         public.sea_refusal(hf.title, hf.wave,
           public.course_zones((select jsonb_agg(s -> 'a' order by i) || jsonb_build_array(hf.path -> -1 -> 'b')
                                  from jsonb_array_elements(hf.path) with ordinality q(s, i)))
           || coalesce((select array[d.zone] from hz d where d.id = hf.dest_port_id), '{}'::text[])) -> 'figures' ->> 'zone_name' as closes
    from hf where hf.voyage_id is not null and jsonb_typeof(hf.path) = 'array' and jsonb_array_length(hf.path) > 0
), queued as (                     -- her SAILs not yet run: the harbour's sea, and the course when the line carries one
  select o.fleet_id as fleet, count(*) as sails,
         count(*) filter (where q.refusal is not null) as closing,
         min(q.refusal -> 'figures' ->> 'zone_name') as first_sea
    from public.orders o join hf on hf.id = o.fleet_id
    left join hz d on d.id = nullif(o.args ->> 'dest', '')::uuid
    cross join lateral (select public.sea_refusal(hf.title, hf.wave,
                          case when jsonb_typeof(o.args -> 'path') = 'array' then public.course_zones(o.args -> 'path') else '{}'::text[] end
                          || coalesce(array[d.zone], '{}'::text[])) as refusal) q
   where o.verb = 'SAIL' and o.status in ('pending', 'active')
   group by o.fleet_id
), stop as (
  select st.route_id, st.ord, st.port_id, st.course,
         coalesce(lead(st.port_id) over (partition by st.route_id order by st.ord),
                  first_value(st.port_id) over (partition by st.route_id order by st.ord)) as to_port
    from public.standing_route_stops st
), rleg as materialized (          -- every leg of every standing route, with the seas its course crosses and its harbour's
  select r.id as route, r.player_id, r.fleet_id, st.ord, st.port_id as from_port, st.to_port,
         public.course_zones(st.course) || coalesce((select array[d.zone] from hz d where d.id = st.to_port), '{}'::text[]) as zones
    from public.standing_routes r join stop st on st.route_id = r.id
), hroute as (
  select l.fleet_id as fleet, count(distinct l.route) as routes, count(*) as legs,
         count(*) filter (where q.refusal is not null) as closing,
         min(q.refusal -> 'figures' ->> 'zone_name') as first_sea
    from rleg l join hf on hf.id = l.fleet_id
    cross join lateral (select public.sea_refusal(hf.title, hf.wave, l.zones) as refusal) q
   group by l.fleet_id
), fleet_row as (
  select hf.player_id, hf.id,
         jsonb_build_object(
           'fleet', hf.name, 'status', hf.status, 'wave', hf.wave, 'hulls', hf.hulls,
           'seas_open', (select count(*) from z where z.title_min <= hf.title and z.wave_min <= coalesce(hf.wave, -1)),
           'seas_closed_by_title', (select count(*) from z where z.title_min > hf.title),
           'seas_closed_by_wave_only', (select count(*) from z where z.title_min <= hf.title and z.wave_min > coalesce(hf.wave, -1)),
           'harbours_open', (select count(*) from hz where hz.title_min <= hf.title and hz.wave_min <= coalesce(hf.wave, -1)),
           'lies_at', here.code, 'her_sea', here.zone,
           'her_sea_open', here.title_min <= hf.title and here.wave_min <= coalesce(hf.wave, -1),
           'can_reach', coalesce(reach.harbours, 0), 'can_reach_capital', coalesce(reach.home, false),
           'voyage_closes_at', voy.closes,
           'queued_sails', coalesce(queued.sails, 0), 'queued_closing', coalesce(queued.closing, 0), 'queued_first_sea', queued.first_sea,
           'route_legs', coalesce(hroute.legs, 0), 'route_legs_closing', coalesce(hroute.closing, 0), 'route_first_sea', hroute.first_sea) as j,
         (here.title_min <= hf.title and here.wave_min <= coalesce(hf.wave, -1)) as here_open,
         coalesce(reach.home, false) as home, coalesce(reach.harbours, 0) as can_reach,
         voy.closes is not null as voyage_closing, coalesce(queued.closing, 0) as queued_closing, coalesce(hroute.closing, 0) as route_closing
    from hf
    left join hz here on here.id = hf.here
    left join reach on reach.fleet = hf.id
    left join voy on voy.fleet = hf.id
    left join queued on queued.fleet = hf.id
    left join hroute on hroute.fleet = hf.id
), company as (
  select h.id, h.title,
         jsonb_build_object(
           'company', h.company_name, 'title', h.title,
           'trading', (h.prog -> 'trading' ->> 'level')::int, 'exploration', (h.prog -> 'exploration' ->> 'level')::int,
           'country', h.nation, 'capital', h.capital_code, 'capital_sea_open_to_her_title', h.capital_title <= h.title,
           'seas_open_by_title', (select count(*) from z where z.title_min <= h.title),
           'harbours_open_by_title', (select count(*) from hz where hz.title_min <= h.title),
           'fleets', coalesce((select jsonb_agg(fr.j order by fr.id) from fleet_row fr where fr.player_id = h.id), '[]'::jsonb)) as j,
         coalesce(h.capital_title <= h.title, false) as capital_open
    from h
), nf as materialized (            -- a merchant fleet, her wave and her hull's size
  select nf.fleet_id, nf.route_id, f.status, public.fleet_wave(nf.fleet_id) as wave,
         (select max(cp.size) from public.ships s join public.ship_classes c on c.id = s.class_id
            join public.class_profile cp on cp.class_code = c.code where s.fleet_id = nf.fleet_id) as size,
         (select st.port_id from public.standing_route_stops st where st.route_id = nf.route_id order by st.ord limit 1) as home
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
   where nf.route_id is not null
), nleg as materialized (
  select nf.fleet_id, l.ord, q.refusal -> 'figures' ->> 'zone_name' as sea
    from nf join rleg l on l.route = nf.route_id
    cross join lateral (select public.sea_refusal(null, nf.wave, l.zones) as refusal) q
), nloop as materialized (
  select nf.fleet_id, nf.status, nf.size, nf.wave, nf.home,
         count(*) filter (where nl.sea is not null) as closed_legs, count(*) as legs
    from nf join nleg nl on nl.fleet_id = nf.fleet_id group by 1, 2, 3, 4, 5
), nopen as (                      -- a closed loop's fleet: the known ways out of where her loop starts (legs of any merchant loop from there) her hull can hold
  select n.fleet_id,
         (select count(distinct x.to_port) from rleg x
           where x.from_port = n.home and x.to_port <> n.home and public.sea_refusal(null, n.wave, x.zones) is null) as open_legs
    from nloop n where n.closed_legs > 0
)
select 'switches' as section, jsonb_build_object(
         'sea_conditions_bite', (select value from public.world_config where key = 'sea_conditions_bite'),
         'sea_conditions_bite_npc', (select value from public.world_config where key = 'sea_conditions_bite_npc'),
         'fleet_room_bite', (select value from public.world_config where key = 'fleet_room_bite'),
         'nav_leg_nm_base', public.wc_num('nav_leg_nm_base'), 'title_max', public.wc_int('title_max'),
         'seas', (select count(*) from z), 'harbours', (select count(*) from hz)) as data
union all
select 'ladder', (select jsonb_agg(jsonb_build_object('hull', hull, 'wave', w, 'harbours_by_title', by_title) order by w) from ladder)
union all
select 'company', c.j from company c
union all
select 'humans', jsonb_build_object(
         'companies', (select count(*) from company),
         'by_title', (select jsonb_object_agg(t, n) from (select title as t, count(*) as n from company group by 1) q),
         'capital_sea_closed_to_her', (select count(*) from company where not capital_open),
         'fleets', (select count(*) from fleet_row),
         'fleets_lying_in_a_sea_closed_to_them', (select count(*) from fleet_row where not here_open),
         'fleets_that_cannot_reach_their_capital', (select count(*) from fleet_row where not home),
         'fleets_with_no_harbour_to_sail_to', (select count(*) from fleet_row where can_reach = 0),
         'voyages_under_way_into_a_closed_sea', (select count(*) from fleet_row where voyage_closing),
         'queued_sails_into_a_closed_sea', (select coalesce(sum(queued_closing), 0) from fleet_row),
         'fleets_whose_standing_route_closes', (select count(*) from fleet_row where route_closing > 0))
union all
select 'merchants', jsonb_build_object(
         'fleets_on_a_loop', (select count(*) from nloop),
         'loops_with_a_closed_leg', (select count(*) from nloop where closed_legs > 0),
         'by_hull_size', (select jsonb_object_agg(size, j) from (select size, jsonb_build_object('loops', count(*), 'closed', count(*) filter (where closed_legs > 0),
                             'wave_min', min(wave), 'wave_max', max(wave)) as j from nloop group by size) q),
         'at_sea_now_on_a_closed_loop', (select count(*) from nloop where closed_legs > 0 and status <> 'DOCKED'),
         'closed_loops_with_no_open_leg_from_home', (select count(*) from nopen where open_legs = 0),
         'closed_loops_by_open_legs_from_home', (select jsonb_object_agg(k, n) from (select least(open_legs, 6) as k, count(*) as n from nopen group by 1) q))
union all
select 'merchants_seas', (select jsonb_object_agg(sea, n) from (select sea, count(distinct fleet_id) as n from nleg where sea is not null group by sea order by 2 desc) q)
union all
select 'far_harbours', (select jsonb_build_object(
         'called_at_today', count(*) filter (where today > 0),
         'still_called_at', count(*) filter (where kept > 0),
         'lost', coalesce(jsonb_agg(code order by code) filter (where today > 0 and kept = 0), '[]'::jsonb))
    from (select hz.code,
                 (select count(*) from public.standing_route_stops st join nloop n on n.fleet_id = (select nf.fleet_id from nf where nf.route_id = st.route_id) where st.port_id = hz.id) as today,
                 (select count(*) from public.standing_route_stops st join nloop n on n.fleet_id = (select nf.fleet_id from nf where nf.route_id = st.route_id) where st.port_id = hz.id and n.closed_legs = 0) as kept
            from hz) q);
commit;
