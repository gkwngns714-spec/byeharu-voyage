-- AT-SEA (0423) DIAGNOSIS: MERCHANTS, CARGO SHIPS AND NAVY IN ONE READ. A PROD READ: read-only, ONE statement, stable functions only.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/at-sea/measure.sql
-- The two halves are measure-merchants.sql and measure-crown.sql (each runnable alone; their headers say what each figure is), joined so the
-- diagnosis costs production one read. Also the after-check's body (after.sql adds the head and the knobs of 0423).
begin transaction read only;
with k as (
  select public.wc_int('npc_fleet_max') as fmax, public.wc_int('npc_buyers_per_good') as kmax, public.wc_int('npc_ask_broke_under') as broke
), m as (
  select nf.fleet_id, nf.route_id, ro.k as roster_ord, nf.refused, nf.asked_at, f.status, f.port_id, f.ready_at,
         sr.paused_reason, sr.hold_until, sr.lap_id, sr.player_id, pl.ducats, coalesce(g.pirate, false) as pirate
    from public.npc_tend_roster() ro   -- the roster RANK (k), the one npc_fleet_max is counted against; npc_fleets.roster_ord has gaps
    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id
    join public.fleets f on f.id = nf.fleet_id
    join public.standing_routes sr on sr.id = nf.route_id
    join public.players pl on pl.id = sr.player_id
    left join public.great_powers g on g.nation_id = pl.nation_id
), s as (
  select m.*, case
           when m.roster_ord > k.fmax then 'dark'
           when m.status = 'SAILING' then 'sailing'
           when m.paused_reason = 'laid_up' then 'laid_up'
           when m.paused_reason is not null then 'paused_' || m.paused_reason
           when m.status <> 'DOCKED' then 'status_' || m.status
           when m.hold_until > now() then 'resting'
           when m.ready_at > now() then 'port_prep'
           when m.lap_id is not null then 'mid_lap'
           else 'due' end as st
    from m cross join k
), lap as (
  select s.fleet_id, x.started_at, x.closed_at,
         lag(x.closed_at) over (partition by s.fleet_id order by x.closed_at) as prev_closed
    from s cross join lateral (select l.started_at, l.closed_at from public.standing_route_laps l
                                where l.route_id = s.route_id and l.closed_at is not null
                                order by l.closed_at desc limit 3) x
), lu as (
  select s.*, (select max(l.closed_at) from lap l where l.fleet_id = s.fleet_id) as last_closed,
         public.sea_conditions_npc_on() and public.npc_loop_sea_shut(s.fleet_id,
           (select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord)
              from public.standing_route_stops st where st.route_id = s.route_id)) as sea_shut,
         (select min(public.treasury_balance(st.port_id)) from public.standing_route_stops st
           where st.route_id = s.route_id and st.ord > 0) as far_purse,
         (select count(*) from public.standing_route_stops st where st.route_id = s.route_id) as stops
    from s where s.st = 'laid_up'
), home as (
  select lu.port_id, count(*) as n from lu group by lu.port_id
), made as (
  select h.port_id, pg.good_id,
         (select count(distinct l.route_id) from public.standing_route_stops s3
            join public.standing_route_lines l on l.route_id = s3.route_id and l.stop_ord = s3.ord and l.kind = 'BUY'
            join public.standing_routes sr3 on sr3.id = l.route_id and coalesce(sr3.paused_reason, '') not in ('laid_up', 'error')
           where s3.port_id = h.port_id and l.good_id = pg.good_id) as buyers
    from home h join public.port_goods pg on pg.port_id = h.port_id and pg.haul_nm = 0
), hp as (
  select h.port_id, h.n, p.code, public.treasury_balance(h.port_id) as purse,
         (select count(*) from made d where d.port_id = h.port_id) as goods_made,
         (select count(*) from made d cross join k where d.port_id = h.port_id and d.buyers >= k.kmax) as goods_full,
         (select count(*) from s where s.port_id = h.port_id and s.st <> 'laid_up' and s.status <> 'SAILING') as others_in_port
    from home h join public.ports p on p.id = h.port_id
), q as (
  select w.fleet_id, w.due_at from public.npc_waiting_queue(now()) w
), b as (
  select count(*) as beats, round(avg(a.ms)) as mean_ms, round(percentile_cont(0.95) within group (order by a.ms)::numeric) as p95_ms,
         round(sum(a.fleets)::numeric / 30, 1) as fleets_min, round(sum(a.days)::numeric / 30, 1) as days_min
    from public.arrivals_beats a where a.at > now() - interval '30 minutes'
),
c as (
  select x.fleet_id, x.nation_id, x.ord, x.home_port_id, x.circuit_id, x.leg, x.out_load, x.laid_up_at, f.status, f.port_id, f.ready_at,
         public.convoy_ships_of(x.nation_id) as wanted,
         (select a.aboard from public.cargo_ship_aboard(x.fleet_id) a) as aboard,
         (select b.created_at from public.convoy_cargo b where b.fleet_id = x.fleet_id and b.stage = 'LOADED' order by b.id desc limit 1) as last_loaded,
         (select b.stage from public.convoy_cargo b where b.fleet_id = x.fleet_id order by b.id desc limit 1) as last_stage
    from public.cargo_ships x join public.fleets f on f.id = x.fleet_id
), cs as (
  select c.*, case
           when c.laid_up_at is not null then 'laid_up'
           when c.status = 'SAILING' then 'sailing'
           when public.npc_wrecked(c.fleet_id) then 'wreck'
           when c.status <> 'DOCKED' then 'status_' || c.status
           when c.port_id = c.home_port_id and coalesce(c.aboard, 0) > 0 then 'home_loaded'
           when c.port_id = c.home_port_id then 'home_idle'
           else 'away' end as st
    from c
), sh as (
  select t.port_id, public.city_capital(t.port_id) as cap, public.city_aid_target(t.port_id) as target, public.treasury_balance(t.port_id) as bal
    from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
), n as (
  select x.fleet_id, x.nation_id, x.ord, x.station_port, x.mission, x.patrol, x.leg, x.unpaid_since, x.laid_up_at, f.status, f.port_id, f.ready_at,
         public.navy_size_of(x.nation_id) as size,
         (select max(v.eta) from public.voyages v where v.fleet_id = x.fleet_id and v.status <> 'SAILING') as last_in
    from public.navy_ships x join public.fleets f on f.id = x.fleet_id
), ns as (
  select n.*, case
           when n.status = 'SAILING' then 'sailing'
           when n.laid_up_at is not null then 'laid_up'
           when public.npc_wrecked(n.fleet_id) then 'wreck'
           when n.status <> 'DOCKED' then 'status_' || n.status
           when n.ready_at > now() then 'port_time'
           when n.mission = 'HUNT' then 'hunting'
           when n.port_id = n.station_port then 'at_station'
           else 'elsewhere' end as st
    from n
)
select jsonb_build_object('merchants', jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('npc_fleet_max', 'npc_buyers_per_good', 'npc_ask_broke_under', 'npc_route_candidates', 'npc_route_neighbours',
                             'npc_route_trade_candidates', 'npc_replan_every_minutes', 'npc_replan_within_minutes', 'route_rest_voyage_days',
                             'time_compression', 'port_prep_seconds', 'npc_lines_per_stop', 'npc_min_return_pct', 'city_treasury_enabled',
                             'economy_closed', 'sea_conditions_bite_npc', 'npc_laps_per_game_day', 'game_day_seconds', 'npc_ask_job_ms')),
  'state', (select jsonb_object_agg(z.st, z.n) from (select s.st, count(*) as n from s group by s.st) z),
  'state_pirate', (select jsonb_object_agg(z.st, z.n) from (select s.st, count(*) as n from s where s.pirate group by s.st) z),
  'rest', (select jsonb_build_object('n', count(*), 'left_min_mean', round(avg(extract(epoch from s.hold_until - now()) / 60)::numeric, 1),
                                     'left_min_max', round(max(extract(epoch from s.hold_until - now()) / 60)::numeric, 1))
             from s where s.st = 'resting'),
  'laps', (select jsonb_build_object('n', count(*), 'lap_min_mean', round(avg(extract(epoch from l.closed_at - l.started_at) / 60)::numeric, 1),
                                     'lap_min_p50', round(percentile_cont(0.5) within group (order by extract(epoch from l.closed_at - l.started_at) / 60)::numeric, 1),
                                     'gap_min_mean', round(avg(extract(epoch from l.started_at - l.prev_closed) / 60) filter (where l.started_at > l.prev_closed)::numeric, 1),
                                     'gap_min_p50', round((percentile_cont(0.5) within group (order by extract(epoch from l.started_at - l.prev_closed) / 60)
                                                         filter (where l.started_at > l.prev_closed))::numeric, 1))
             from lap l where l.closed_at > now() - interval '3 hours'),
  'due', (select jsonb_build_object('n', count(*), 'waited_min_mean', round(avg(extract(epoch from now() - coalesce(s.hold_until, now())) / 60)::numeric, 1)) from s where s.st = 'due'),
  'laid_up', (select jsonb_build_object(
      'n', count(*),
      'pirate', count(*) filter (where lu.pirate),
      'broke', count(*) filter (where lu.ducats < (select k.broke from k)),
      'purse_q', jsonb_build_array(percentile_cont(0.25) within group (order by lu.ducats), percentile_cont(0.5) within group (order by lu.ducats),
                                   percentile_cont(0.75) within group (order by lu.ducats)),
      'by_refused', jsonb_build_object('0', count(*) filter (where lu.refused = 0), '1', count(*) filter (where lu.refused = 1),
                                       '2', count(*) filter (where lu.refused = 2), '3', count(*) filter (where lu.refused = 3),
                                       '4+', count(*) filter (where lu.refused >= 4)),
      'hours_since_lap', jsonb_build_object('lt1', count(*) filter (where lu.last_closed > now() - interval '1 hour'),
                                            '1_6', count(*) filter (where lu.last_closed <= now() - interval '1 hour' and lu.last_closed > now() - interval '6 hours'),
                                            '6_24', count(*) filter (where lu.last_closed <= now() - interval '6 hours' and lu.last_closed > now() - interval '24 hours'),
                                            'gt24_or_none', count(*) filter (where lu.last_closed is null or lu.last_closed <= now() - interval '24 hours')),
      'asked_min_mean', round(avg(extract(epoch from now() - lu.asked_at) / 60)::numeric, 1),
      'due_now', (select count(*) from q join lu x on x.fleet_id = q.fleet_id where q.due_at <= now()),
      'home_ports', count(distinct lu.port_id),
      'sea_shut', count(*) filter (where lu.sea_shut),
      'far_purse_under_10k', count(*) filter (where lu.far_purse < 10000),
      'far_purse_under_100k', count(*) filter (where lu.far_purse < 100000),
      'stops', jsonb_build_object('2', count(*) filter (where lu.stops = 2), '3', count(*) filter (where lu.stops = 3), '4+', count(*) filter (where lu.stops >= 4))) from lu),
  'homes', (select jsonb_agg(jsonb_build_object('code', hp.code, 'laid', hp.n, 'others_in_port', hp.others_in_port, 'purse', hp.purse,
                                                'made', hp.goods_made, 'full', hp.goods_full) order by hp.n desc, hp.code) from hp),
  'homes_sum', (select jsonb_build_object('ports', count(*), 'laid', sum(hp.n), 'laid_where_every_made_good_full', sum(hp.n) filter (where hp.goods_made > 0 and hp.goods_full = hp.goods_made),
                                          'laid_where_makes_nothing', sum(hp.n) filter (where hp.goods_made = 0),
                                          'laid_where_purse_under_50k', sum(hp.n) filter (where hp.purse < 50000)) from hp),
  'world_purses', (select jsonb_build_object('harbours', count(*), 'under_10k', count(*) filter (where x.b < 10000), 'under_100k', count(*) filter (where x.b < 100000),
                                             'p50', percentile_cont(0.5) within group (order by x.b))
                     from (select public.treasury_balance(t.port_id) as b from public.port_treasury t) x),
  'beat', (select to_jsonb(b) from b)
),
  'crown', jsonb_build_object(
  'at', now(),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('convoys_enabled', 'convoy_rich_enabled', 'convoy_armed_enabled', 'convoy_idle_every', 'convoy_commission_per_run',
                             'convoy_retire_per_run', 'convoy_ships_min', 'convoy_ships_max', 'convoy_rebase_idle_days', 'navy_enabled', 'navy_hunt_per_day',
                             'navy_steps_per_run', 'navy_patrol_stops', 'navy_hunt_hours', 'navy_escorts', 'navy_min', 'navy_max', 'navy_purse_unit',
                             'navy_build_hours', 'pirates_enabled', 'city_treasury_enabled', 'economy_closed', 'treasury_reserve_floor', 'crown_call_share',
                             'crown_call_cover', 'city_reserve_per_tier')),
  'cargo', jsonb_build_object(
     'n', (select count(*) from cs),
     'state', (select jsonb_object_agg(z.st, z.n) from (select cs.st, count(*) as n from cs group by cs.st) z),
     'surplus_in_service', (select count(*) from cs where cs.laid_up_at is null and cs.ord > cs.wanted),
     'home_idle_ready', (select count(*) from cs where cs.st = 'home_idle' and (cs.ready_at is null or cs.ready_at <= now())),
     'home_idle_out_load', (select count(*) from cs where cs.st = 'home_idle' and cs.out_load is not null),
     'away_no_circuit', (select count(*) from cs where cs.st = 'away' and cs.circuit_id is null),
     'last_stage', (select jsonb_object_agg(coalesce(z.s, 'none'), z.n) from (select cs.last_stage as s, count(*) as n from cs group by 1) z),
     'last_loaded_hours', (select jsonb_build_object('lt1', count(*) filter (where cs.last_loaded > now() - interval '1 hour'),
                                                     '1_6', count(*) filter (where cs.last_loaded <= now() - interval '1 hour' and cs.last_loaded > now() - interval '6 hours'),
                                                     '6_24', count(*) filter (where cs.last_loaded <= now() - interval '6 hours' and cs.last_loaded > now() - interval '24 hours'),
                                                     'gt24', count(*) filter (where cs.last_loaded <= now() - interval '24 hours'),
                                                     'never', count(*) filter (where cs.last_loaded is null)) from cs),
     'aboard_sailing', (select jsonb_build_object('n', count(*), 'with_funds', count(*) filter (where cs.aboard > 0), 'funds', coalesce(sum(cs.aboard), 0)) from cs where cs.st = 'sailing'),
     'short', (select jsonb_build_object('harbours', count(*), 'need', coalesce(sum(sh.target - sh.bal), 0), 'capitals', count(distinct sh.cap),
                                         'per_capital', (select jsonb_object_agg(p.code, z.need) from (select sh2.cap, sum(sh2.target - sh2.bal) as need from sh sh2
                                                           where sh2.target > 0 and sh2.bal < sh2.target and sh2.cap is not null group by sh2.cap) z join public.ports p on p.id = z.cap))
                 from sh where sh.target > 0 and sh.bal < sh.target and sh.cap is not null),
     'nations', (select jsonb_agg(jsonb_build_object('code', na.code, 'ships', z.ships, 'in_service', z.svc, 'wanted', z.wanted, 'sailing', z.sailing,
                                                     'home_idle', z.idle, 'laid_up', z.laid,
                                                     'circuits', (select count(*) from public.cargo_circuits ci where ci.nation_id = z.nation_id),
                                                     'legs', (select count(*) from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(z.nation_id, public.realm_capital(z.nation_id))),
                                                     'nm', (select round(sum(l.nm)) from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(z.nation_id, public.realm_capital(z.nation_id))))
                                  order by na.code)
                   from (select cs.nation_id, count(*) as ships, count(*) filter (where cs.laid_up_at is null) as svc, max(cs.wanted) as wanted,
                                count(*) filter (where cs.st = 'sailing') as sailing, count(*) filter (where cs.st = 'home_idle') as idle,
                                count(*) filter (where cs.st = 'laid_up') as laid
                           from cs group by cs.nation_id) z join public.nations na on na.id = z.nation_id)),
  'navy', jsonb_build_object(
     'n', (select count(*) from ns),
     'state', (select jsonb_object_agg(z.st, z.n) from (select ns.st, count(*) as n from ns group by ns.st) z),
     'mission', (select jsonb_object_agg(coalesce(z.m, 'none'), z.n) from (select ns.mission as m, count(*) as n from ns group by 1) z),
     'unpaid', (select count(*) from ns where ns.unpaid_since is not null),
     'over_number', (select count(*) from ns where ns.ord > ns.size),
     'on_patrol_in_port', (select count(*) from ns where ns.st <> 'sailing' and ns.patrol is not null),
     'in_port_min', (select jsonb_build_object('mean', round(avg(extract(epoch from now() - ns.last_in) / 60)::numeric, 1),
                                               'p50', round((percentile_cont(0.5) within group (order by extract(epoch from now() - ns.last_in) / 60))::numeric, 1),
                                               'max', round(max(extract(epoch from now() - ns.last_in) / 60)::numeric, 1))
                       from ns where ns.st <> 'sailing' and ns.laid_up_at is null),
     'stations', (select jsonb_build_object('n', count(*), 'retired', count(*) filter (where s.retired_at is not null),
                                            'no_legs', count(*) filter (where s.retired_at is null and not exists (select 1 from public.navy_patrol_legs l where l.station_id = s.id)),
                                            'legs', (select count(*) from public.navy_patrol_legs l),
                                            'ships_at_station_without_legs', (select count(*) from ns join public.navy_stations s2 on s2.port_id = ns.port_id and s2.nation_id = ns.nation_id and s2.retired_at is null
                                                                                where ns.st = 'at_station' and not exists (select 1 from public.navy_patrol_legs l where l.station_id = s2.id)))
                    from public.navy_stations s),
     'realms', (select jsonb_agg(jsonb_build_object('ships', r.ships, 'purse', r.purse, 'paid_at', r.paid_at, 'stations_at', r.stations_at)) from public.navy_realms r))
)) as r;
commit;
