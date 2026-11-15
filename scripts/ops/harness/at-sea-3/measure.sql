-- AT-SEA-3 (0426) DIAGNOSIS: which laid-up merchants a move could help, and what a smaller cargo load would send. A PROD READ: read-only, ONE
-- statement, stable functions only.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/at-sea-3/measure.sql
-- Reads npc_fleets (~900) with their fleets, routes and houses by key; for each LAID-UP merchant (~100) the legs she could sail now
-- (public.npc_feasible_legs with her preset's days, public.npc_legs_open: STABLE), each far harbour's purse (public.treasury_balance) and
-- whether one of the goods it makes has a free buyer place (the NPC BUY lines standing there: standing_route_lines, ~5,000 rows); cargo_ships
-- (~370) with their fleets and the harbours' purses (~250), as at-sea-2/measure.sql. Run scripts/ops/harness/db-health/gate.sql first.
-- WHAT IT ANSWERS:
--   laid.eligible       laid up, not a pirate house, her house has one ship, and refused 4+ in a row or no lap closed for 6 hours
--   laid.with_dest      of those, how many have at least one harbour within her stores whose purse is >= 100,000 and that makes a good with
--                       fewer than npc_buyers_per_good merchant buyers (own country / any); dests_p50: how many such harbours she has
--   cargo.sends         per load size (250k now, 100k, 50k): ships one hourly run could load now (each realm: its idle loadable ships, the
--                       loads a run, and its need less aboard within its idle homes' room); steady: ships the need would fill at that size
--                       (each realm: its ships in service, at most need / size)
begin transaction read only;
with k as (
  select public.wc_int('npc_buyers_per_good') as kmax, public.wc_int('npc_fleet_max') as fmax
), m as (
  select nf.fleet_id, nf.route_id, nf.refused, f.port_id, f.provision_preset_id, pl.nation_id, ro.k,
         coalesce(g.pirate, false) as pirate,
         (select count(*) from public.npc_fleets n2 where n2.player_id = nf.player_id) as house_ships,
         (select max(l.closed_at) from public.standing_route_laps l where l.route_id = nf.route_id and l.closed_at is not null) as last_closed
    from public.npc_tend_roster() ro
    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id
    join public.fleets f on f.id = nf.fleet_id
    join public.standing_routes sr on sr.id = nf.route_id
    join public.players pl on pl.id = sr.player_id
    left join public.great_powers g on g.nation_id = pl.nation_id
   cross join k
   where sr.paused_reason = 'laid_up' and f.status = 'DOCKED' and ro.k <= k.fmax
), buyers as (
  select s3.port_id, l.good_id, count(distinct l.route_id) as n
    from public.standing_route_lines l
    join public.standing_route_stops s3 on s3.route_id = l.route_id and s3.ord = l.stop_ord
    join public.standing_routes sr3 on sr3.id = l.route_id and coalesce(sr3.paused_reason, '') not in ('laid_up', 'error')
    join public.players p3 on p3.id = sr3.player_id and p3.is_npc
   where l.kind = 'BUY'
   group by 1, 2
), open_h as (
  select p.id as port_id, public.port_nation(p.id) as nation_id
    from public.ports p cross join k
   where p.kind = 'HARBOUR' and not p.is_ice_closed and not public.pirate_home(p.id)
     and public.treasury_balance(p.id) >= 100000
     and exists (select 1 from public.port_goods pg left join buyers b on b.port_id = pg.port_id and b.good_id = pg.good_id
                  where pg.port_id = p.id and pg.haul_nm = 0 and coalesce(b.n, 0) < k.kmax)
), el as (
  select m.*, (select pr.days from public.provision_presets pr where pr.id = m.provision_preset_id) as pdays
    from m where not m.pirate and m.house_ships = 1
     and (m.refused >= 4 or m.last_closed is null or m.last_closed < now() - interval '6 hours')
), d as (
  select el.fleet_id,
         count(h.port_id) as dests,
         count(h.port_id) filter (where h.nation_id = el.nation_id) as own
    from el
    cross join lateral jsonb_array_elements(public.npc_legs_open(public.npc_feasible_legs(el.port_id, el.fleet_id,
                          greatest(coalesce(voyage.fleet_speed_at(el.fleet_id, 1), 0), 0.1), coalesce(el.pdays, 0)), el.port_id)) x
    left join open_h h on h.port_id = (x->>'port_id')::uuid
   group by el.fleet_id
), c as (
  select x.fleet_id, x.nation_id, x.home_port_id, x.laid_up_at, f.status, f.port_id, x.ord,
         public.convoy_ships_of(x.nation_id) as wanted,
         (select a.aboard from public.cargo_ship_aboard(x.fleet_id) a) as aboard,
         exists (select 1 from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(x.nation_id, x.home_port_id)) as has_circuit
    from public.cargo_ships x join public.fleets f on f.id = x.fleet_id
), sh as (
  select public.city_capital(t.port_id) as cap, public.city_aid_target(t.port_id) as target, public.treasury_balance(t.port_id) as bal
    from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
), need as (
  select sh.cap, sum(sh.target - sh.bal)::bigint as need from sh where sh.target > 0 and sh.bal < sh.target and sh.cap is not null group by sh.cap
), nat as (
  select c.nation_id, public.realm_capital(c.nation_id) as cap,
         count(*) filter (where c.laid_up_at is null) as svc,
         count(*) filter (where c.status = 'SAILING') as sea,
         coalesce(sum(c.aboard), 0)::bigint as aboard,
         count(*) filter (where c.laid_up_at is null and c.status = 'DOCKED' and c.port_id = c.home_port_id and c.aboard is null and c.has_circuit and c.ord <= c.wanted) as il
    from c group by c.nation_id
), nat2 as (
  select nat.*, coalesce(nd.need, 0) as need,
         (select coalesce(sum(public.cargo_load_room(h.home_port_id, nat.nation_id)), 0)::bigint
            from (select distinct c2.home_port_id from c c2 where c2.nation_id = nat.nation_id and c2.laid_up_at is null and c2.status = 'DOCKED'
                     and c2.port_id = c2.home_port_id and c2.aboard is null) h) as room
    from nat left join need nd on nd.cap = nat.cap
), sz(x) as (values (250000), (100000), (50000))
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'laid', jsonb_build_object(
     'n', (select count(*) from m), 'pirate', (select count(*) from m where m.pirate), 'multi_ship_house', (select count(*) from m where not m.pirate and m.house_ships > 1),
     'eligible', (select count(*) from el),
     'with_dest', (select count(*) from d where d.dests > 0), 'with_own_country_dest', (select count(*) from d where d.own > 0),
     'dests_p50', (select percentile_cont(0.5) within group (order by d.dests) from d),
     'healthy_harbours', (select count(*) from open_h)),
  'cargo', jsonb_build_object(
     'totals', (select jsonb_build_object('svc', sum(svc), 'sea', sum(sea), 'aboard', sum(aboard), 'idle_loadable', sum(il), 'need', sum(need),
                                          'need_less_aboard', sum(greatest(need - aboard, 0)), 'room', sum(room)) from nat2),
     'sends', (select jsonb_object_agg(sz.x::text, jsonb_build_object(
                 'run_now_20', (select sum(least(n2.il, 20, ceil(greatest(least(n2.need - n2.aboard, n2.room), 0) / sz.x::numeric))) from nat2 n2),
                 'run_now_40', (select sum(least(n2.il, 40, ceil(greatest(least(n2.need - n2.aboard, n2.room), 0) / sz.x::numeric))) from nat2 n2),
                 'steady', (select sum(least(n2.svc, ceil(n2.need / sz.x::numeric))) from nat2 n2))) from sz),
     'nations', (select jsonb_agg(jsonb_build_object('svc', svc, 'sea', sea, 'ab', aboard, 'il', il, 'need', need, 'room', room) order by svc desc) from nat2))
) as r;
commit;
