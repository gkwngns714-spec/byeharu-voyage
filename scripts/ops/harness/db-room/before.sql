-- 0428 PROD CHECK, BEFORE the deploy (the same read as after.sql), read-only, ONE statement (run scripts/ops/harness/db-health/gate.sql first: gate_ok true):
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/db-room/before.sql
-- One row, one jsonb column `r`. It reads the catalog, the statistics views, world_config, stats_fold_marks (10 rows), the beat's ring, and the
-- two re-cut readers' bodies; the probe pair is found by key (port_goods with no day / hour row, LIMIT 1). No game table is scanned.
-- BEFORE, wanted: applied false; hunks[] old 1 new 0 for each of the three; knobs stats_fine_hours 72, stats_hour_days 30, price_history_hour_days 30,
--   stats_city_good_keep_days 30; tables[] the 0412 settings (scale factor 0, thresholds 25,000-200,000) and price_history_hour's 1000 / 0;
--   probe_pair not null (the migration's probe runs on it; null = it skips, proof 129 still reads the spans). WRITE tables[] DOWN: it is the "before".
begin transaction read only;
with ps as (select replace(pg_get_functiondef('world.price_series(uuid,uuid,text)'::regprocedure), E'\r', '') as d),
     su as (select replace(pg_get_functiondef('public.stats_span_unit(text)'::regprocedure), E'\r', '') as d),
     h(i, body, old, new) as (values
  (1, (select d from ps), $h$  elsif p_span in ('1w', '1m') then
    v_tier := 'hour'; v_step := 3600;
$h$, $h$  elsif p_span = '1w' then
    -- 0428: a week is drawn from the hours; a month from the days (price_history_hour keeps price_history_hour_days, 8)
    v_tier := 'hour'; v_step := 3600;
$h$),
  (2, (select d from ps), $h$       and (p_span = 'all' or d.day >= ((v_now - interval '365 days') at time zone 'UTC')::date);
$h$, $h$       and (p_span = 'all' or d.day >= ((v_now - case when p_span = '1m' then interval '30 days' else interval '365 days' end) at time zone 'UTC')::date);
$h$),
  (3, (select d from su), $h$  return case p_span when '1d' then 'fine' when '1w' then 'hour' when '1m' then 'hour' else 'day' end;
$h$, $h$  -- 0428: a month is drawn from the days (stats_hour_days 8 keeps a week of hours); a week from the hours
  return case p_span when '1d' then 'fine' when '1w' then 'hour' else 'day' end;
$h$))
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', (select position('-- 0428:' in d) > 0 from ps),
  'hunks', (select jsonb_agg(jsonb_build_object('hunk', i, 'old', (length(body) - length(replace(body, old, ''))) / length(old),
                                                'new', (length(body) - length(replace(body, new, ''))) / length(new)) order by i) from h),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c
             where c.key in ('stats_fine_hours', 'stats_hour_days', 'price_history_hour_days', 'stats_city_good_keep_days',
                             'stats_city_good_fine_hours', 'stats_city_good_hour_days', 'stats_fold_batch_hours', 'stats_fold_batch_days')),
  'tables', (select jsonb_agg(jsonb_build_object('t', c.relname, 'mb', ((c.relpages + coalesce((select sum(ic.relpages) from pg_index i join pg_class ic on ic.oid = i.indexrelid where i.indrelid = c.oid), 0))::numeric * 8192 / 1048576)::int,
                                                 'live', s.n_live_tup, 'dead', s.n_dead_tup, 'last_av', s.last_autovacuum, 'opts', c.reloptions) order by c.relname)
               from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
               left join pg_stat_user_tables s on s.relid = c.oid
              where c.relkind = 'r' and c.relname in ('events', 'ledger', 'voyage_events', 'voyages', 'standing_route_laps', 'orders', 'stats_city_good',
                    'stats_good', 'stats_city', 'price_history', 'treasury_flows', 'trade_daily', 'insured_voyages', 'price_history_hour', 'port_goods')),
  'db_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
  'beat', (select jsonb_build_object('beats', count(*), 'mean_ms', round(avg(b.ms))) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
  'fold_marks', (select jsonb_agg(jsonb_build_object('t', m.tbl, 'u', m.unit, 'through', m.through) order by m.tbl, m.unit) from public.stats_fold_marks m),
  'probe_pair', (select jsonb_build_object('port', pg.port_id, 'good', pg.good_id) from public.port_goods pg
                  where not exists (select 1 from public.price_history_day d where d.port_id = pg.port_id and d.good_id = pg.good_id)
                    and not exists (select 1 from public.price_history_hour x where x.port_id = pg.port_id and x.good_id = pg.good_id) limit 1)
) as r;
commit;
