-- AT-SEA (0423) DIAGNOSIS, MERCHANTS. A PROD READ: read-only, ONE statement, stable functions only.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/at-sea/measure-merchants.sql
-- Reads npc_fleets (~900 rows), their fleets, routes and houses by key, each merchant's last three closed laps through
-- standing_route_laps_route_closed, the BUY lines standing at the laid-up merchants' home harbours (standing_route_stops_port), the
-- waiting line (public.npc_waiting_queue, STABLE) and the beat's ring. No big table is scanned beyond an index.
-- WHAT IT ANSWERS:
--   state{}      every merchant by what she is doing now: sailing, laid_up, resting (hold_until ahead), port_prep (ready_at ahead), mid_lap
--                (a lap open, docked), due (no lap, no hold: waiting for the lap-start job), dark (beyond npc_fleet_max), other paused, wreck.
--   rest         the resting: minutes left (mean, max); laps: the mean real minutes of a lap and of the time from a lap's close to the next start.
--   laid_up      by refusals in a row, broke (< npc_ask_broke_under), purse quartiles, hours since her last lap closed, minutes since last ask,
--                due now by the line's rule, pirate houses; her home harbour: how many laid up there, its purse, the goods it makes, and how
--                many of those goods already have npc_buyers_per_good other merchants buying them there (a full harbour cannot give her a BUY).
--   beat         the last 30 minutes of the arrivals ring: beats, mean / p95 ms, fleets and voyage-days settled a minute.
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
)
select jsonb_build_object(
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
) as r;
commit;
