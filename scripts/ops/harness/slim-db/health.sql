-- SLIM-DB HEALTH (0409 and 0416; docs/dev-log/2026-11-14-slim-db.md), THE GUARD: is the database still the size the instance can hold. Read-only, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/slim-db/health.sql
-- One row, one jsonb column `r`. It reads the catalog (sizes, row estimates), the statistics views, the knobs, three small ring tables, and the
-- FIRST entry of three indexes (an oldest row each). It scans no large table. Run it once a day, and before and after any maintenance.
--
-- WHAT IT SAYS, AND THE NUMBERS IT SHOULD STAY UNDER (each is in the row beside the figure, as `under`):
--   database_mb      the whole database.            under 1,500 once the RUNBOOK's maintenance has run (2,826 on 2026-11-14).
--   top10[]          the ten largest tables, heap + indexes + toast, with the planner's row estimate.
--   kept[]           every table with a retention rule: its rows (estimate), its size, its oldest row against its keep window, and `ok`.
--     city_wants          oldest period no older than city_wants_keep_periods + 15 periods (the trim runs every minute, 2,000 rows a run).
--     stats_city_good     oldest row no older than stats_city_good_keep_days + 1 day.       rows under 300,000.
--     standing_route_laps (0416) a merchant route keeps her newest npc_route_lap_keep (10) and what she closed since the compactor last
--                         cut her house; a player's keeps 100. rows under 25,000. The figure `merchant_laps_over_a_day` (laps of
--                         merchants closed over 30 hours ago) is only a quiet route's newest ten: under 10 a merchant route.
--     route_hour_laps     (0416) the hour book: oldest hour no older than route_hour_keep_hours + 3 h. rows under 90,000.
--     merchants' books    the compactor's own newest receipt: the oldest ledger row waiting is under 2 h past the cut, `left` under 60.
--     events / ledger / voyages / voyage_events   rows (estimate) under 600,000 / 350,000 / 70,000 / 950,000 at npc_retention_hours 3.
--     price_history_hour  rows under 1,150,000 (30 days of hours; it reaches that about 2026-11-25 and then stays).
--     stats_good, stats_city   rows under 480,000 / 200,000.
--   port_goods       the table the drift rewrites: size under 110 MB (heap + indexes), dead rows under 320,000, last autovacuum.
--   drift            drift_spread_runs, and how many harbours are stepped this minute (about ports / drift_spread_runs).
-- IF A LINE IS NOT ok: the compactor is behind (read `compactor`), a knob was put to 0, or a new table has started to grow: top10 names it.
begin transaction read only;
with k as (
  select (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'city_wants_keep_periods') as wants_keep,
         (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'want_period_seconds') as want_secs,
         (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'stats_city_good_keep_days') as cg_days,
         (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'npc_route_lap_keep') as lap_keep,
         (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'npc_route_lap_keep_hours') as lap_hours,
         (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'npc_retention_hours') as npc_hours,
         (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'route_hour_keep_hours') as hb_hours,
         (select (c.value #>> '{}')::int from public.world_config c where c.key = 'drift_spread_runs') as spread
), sz as (
  select c.relname as tbl, c.reltuples::bigint as rows, pg_total_relation_size(c.oid) / 1048576 as mb, pg_relation_size(c.oid) / 1048576 as heap_mb
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
), wants as (
  select (select w.period from public.city_wants w order by w.period limit 1) as oldest,
         floor(extract(epoch from now()) / (select want_secs from k))::bigint as now_period
), cg as (
  select (select s.at from public.stats_city_good s order by s.at limit 1) as oldest
), laps as (
  -- merchants' laps closed before the window (an index range on closed_at; after the trim these are only a quiet route's newest 24)
  select count(*) filter (where p.is_npc) as merchant_old, count(distinct l.route_id) filter (where p.is_npc) as merchant_routes,
         count(*) filter (where not p.is_npc) as player_old
    from public.standing_route_laps l
    join public.standing_routes r on r.id = l.route_id
    join public.players p on p.id = r.player_id
   where l.lap_no >= 2 and l.closed_at < now() - interval '30 hours'
), cr as (
  select c.at, c.ms, c.receipt from public.compact_runs c order by c.at desc limit 1
)
select jsonb_build_object(
  'at', now(),
  'database_mb', jsonb_build_object('mb', pg_database_size(current_database()) / 1048576, 'under', 1500,
                                    'ok', pg_database_size(current_database()) / 1048576 < 1500),
  'top10', (select jsonb_agg(jsonb_build_object('table', t.tbl, 'mb', t.mb, 'heap_mb', t.heap_mb, 'rows', t.rows) order by t.mb desc)
              from (select * from sz order by mb desc limit 10) t),
  'kept', jsonb_build_array(
    jsonb_build_object('table', 'city_wants', 'rule', 'city_wants_keep_periods', 'keep', (select wants_keep from k),
                       'rows', (select rows from sz where tbl = 'city_wants'), 'mb', (select mb from sz where tbl = 'city_wants'),
                       'oldest_periods_back', (select now_period - oldest from wants), 'under', (select wants_keep + 15 from k),
                       'ok', (select wants_keep from k) > 0 and coalesce((select now_period - oldest from wants), 0) <= (select wants_keep + 15 from k)),
    jsonb_build_object('table', 'stats_city_good', 'rule', 'stats_city_good_keep_days', 'keep', (select cg_days from k),
                       'rows', (select rows from sz where tbl = 'stats_city_good'), 'rows_under', 300000, 'mb', (select mb from sz where tbl = 'stats_city_good'),
                       'oldest', (select oldest from cg), 'oldest_days_back', (select round((extract(epoch from now() - oldest) / 86400)::numeric, 1) from cg),
                       'under', (select cg_days + 1 from k),
                       'ok', (select cg_days from k) > 0 and coalesce((select extract(epoch from now() - oldest) / 86400 from cg), 0) <= (select cg_days + 1 from k)),
    jsonb_build_object('table', 'standing_route_laps', 'rule', 'npc_route_lap_keep / npc_route_lap_keep_hours',
                       'keep', (select lap_keep from k), 'keep_hours', (select lap_hours from k),
                       'rows', (select rows from sz where tbl = 'standing_route_laps'), 'rows_under', 25000, 'mb', (select mb from sz where tbl = 'standing_route_laps'),
                       'merchant_laps_over_a_day', (select merchant_old from laps), 'on_routes', (select merchant_routes from laps),
                       'under', (select greatest((select lap_keep from k), 10) * greatest(merchant_routes, 1) from laps), 'player_laps_over_a_day', (select player_old from laps),
                       'ok', (select lap_keep from k) > 0 and (select merchant_old <= greatest((select lap_keep from k), 10) * greatest(merchant_routes, 1) from laps)
                             and (select rows < 25000 from sz where tbl = 'standing_route_laps')),
    jsonb_build_object('table', 'route_hour_laps', 'rule', 'route_hour_keep_hours', 'keep_hours', (select hb_hours from k),
                       'rows', (select rows from sz where tbl = 'route_hour_laps'), 'rows_under', 90000, 'mb', (select mb from sz where tbl = 'route_hour_laps'),
                       'oldest', (select b.hour from public.route_hour_laps b order by b.hour limit 1), 'under_hours', (select hb_hours + 3 from k),
                       'ok', coalesce((select extract(epoch from now() - b.hour) / 3600 <= (select hb_hours + 3 from k) from public.route_hour_laps b order by b.hour limit 1), true)),
    jsonb_build_object('table', 'the merchants'' books (events, ledger, voyages, voyage_events, orders)', 'rule', 'npc_retention_hours',
                       'keep_hours', (select npc_hours from k),
                       'rows', jsonb_build_object('events', (select rows from sz where tbl = 'events'), 'ledger', (select rows from sz where tbl = 'ledger'),
                                                  'voyages', (select rows from sz where tbl = 'voyages'), 'voyage_events', (select rows from sz where tbl = 'voyage_events')),
                       'rows_under', jsonb_build_object('events', 600000, 'ledger', 350000, 'voyages', 70000, 'voyage_events', 950000),
                       'mb', jsonb_build_object('events', (select mb from sz where tbl = 'events'), 'ledger', (select mb from sz where tbl = 'ledger'),
                                                'voyages', (select mb from sz where tbl = 'voyages'), 'voyage_events', (select mb from sz where tbl = 'voyage_events')),
                       'oldest_waiting', (select receipt->>'oldest' from cr), 'cut', (select receipt->>'before' from cr),
                       'hours_past_cut', (select round((extract(epoch from (receipt->>'before')::timestamptz - (receipt->>'oldest')::timestamptz) / 3600)::numeric, 2) from cr),
                       'under_hours', 2, 'left', (select receipt->'left' from cr), 'left_under', 60,
                       'ok', coalesce((select extract(epoch from (receipt->>'before')::timestamptz - (receipt->>'oldest')::timestamptz) / 3600 < 2 from cr), true)
                             and coalesce((select (receipt->>'left')::int < 60 from cr), true)),
    jsonb_build_object('table', 'price_history_hour', 'rule', 'price_history_hour_days (30)', 'rows', (select rows from sz where tbl = 'price_history_hour'),
                       'rows_under', 1150000, 'mb', (select mb from sz where tbl = 'price_history_hour'),
                       'ok', (select rows < 1150000 from sz where tbl = 'price_history_hour')),
    jsonb_build_object('table', 'stats_good', 'rule', 'stats_fine_hours / stats_hour_days', 'rows', (select rows from sz where tbl = 'stats_good'),
                       'rows_under', 480000, 'mb', (select mb from sz where tbl = 'stats_good'), 'ok', (select rows < 480000 from sz where tbl = 'stats_good')),
    jsonb_build_object('table', 'stats_city', 'rule', 'stats_fine_hours / stats_hour_days', 'rows', (select rows from sz where tbl = 'stats_city'),
                       'rows_under', 200000, 'mb', (select mb from sz where tbl = 'stats_city'), 'ok', (select rows < 200000 from sz where tbl = 'stats_city'))),
  'port_goods', (select jsonb_build_object('mb', (select mb from sz where tbl = 'port_goods'), 'under_mb', 110, 'rows', s.n_live_tup, 'dead', s.n_dead_tup, 'dead_under', 320000,
                                           'last_autovacuum', s.last_autovacuum, 'updates', s.n_tup_upd, 'hot_updates', s.n_tup_hot_upd,
                                           'ok', (select mb from sz where tbl = 'port_goods') < 110 and s.n_dead_tup < 320000)
                   from pg_stat_user_tables s where s.schemaname = 'public' and s.relname = 'port_goods'),
  'drift', jsonb_build_object('drift_spread_runs', (select spread from k), 'ports', (select count(*) from public.ports),
                              'stepped_this_minute', (select count(*) from (select row_number() over (order by po.id) as n from public.ports po) x
                                                       where coalesce((select spread from k), 1) <= 1
                                                          or x.n % (select spread from k) = floor(extract(epoch from now()) / 60)::bigint % (select spread from k))),
  'compactor', (select jsonb_build_object('at', at, 'ms', ms, 'houses', receipt->'houses', 'due', receipt->'due', 'left', receipt->'left',
                                          'ms_house', receipt->'ms_house', 'failed', receipt->'failed', 'note', receipt->'note') from cr)
) as r;
commit;
