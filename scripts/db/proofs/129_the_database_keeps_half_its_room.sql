-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 129 - THE DATABASE KEEPS HALF ITS ROOM  (migration 0428; docs/dev-log/2026-11-15-db-room.md; the owner, 2026-11-15: "there should be a
--   room of course, not just too tight")
--
--   On the world's own tables and jobs, every scene rolled back with proof.mjs's transaction. EVERY MARKER FAILS ON THE RULES BEFORE 0428: the
--   churn tables swept at a fixed 50,000-200,000 dead rows, price_history_hour at 1,000; the hours kept 30 days; a month drawn from the hours.
--
-- @pass DR_SWEEP   the fourteen tables sweep at 5,000 + 10 % of their rows (price_history_hour 5 %), at 0412's pace, none with autovacuum off;
--                  port_goods and city_wants untouched
-- @pass DR_KNOBS   stats_fine_hours 30, stats_hour_days 8, price_history_hour_days 8, stats_city_good_keep_days 90, each description naming 0428
-- @pass DR_PRUNE   the price-snapshot job, run once, takes a planted hour 10 days old and keeps the one 6 days old (price_history_hour_days 8)
-- @pass DR_SPANS   a month of prices is the day tier, 30 days (a planted day 20 days old in, one 40 days old out); a week is the hours; the
--                  stats spans group a month by day
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  t       record;
  v_opts  text[];
  v_port  uuid;
  v_good  uuid;
  v_s     jsonb;
  v_h     timestamptz := date_trunc('hour', now());
begin
  -- DR_SWEEP
  for t in select * from (values ('events', '0.1'), ('ledger', '0.1'), ('voyage_events', '0.1'), ('voyages', '0.1'), ('standing_route_laps', '0.1'),
                                 ('orders', '0.1'), ('stats_city_good', '0.1'), ('stats_good', '0.1'), ('stats_city', '0.1'), ('price_history', '0.1'),
                                 ('treasury_flows', '0.1'), ('trade_daily', '0.1'), ('insured_voyages', '0.1'), ('price_history_hour', '0.05')) x(tbl, sf) loop
    select c.reloptions into v_opts from pg_class c where c.oid = ('public.' || t.tbl)::regclass;
    if not (v_opts @> array['autovacuum_vacuum_scale_factor=' || t.sf, 'autovacuum_vacuum_threshold=5000', 'autovacuum_vacuum_cost_delay=20',
                            'autovacuum_vacuum_cost_limit=25'])
       or exists (select 1 from unnest(v_opts) o where o like 'autovacuum_enabled=%') then
      raise exception 'PROOF 129 FAIL: public.% reads %', t.tbl, v_opts;
    end if;
  end loop;
  if exists (select 1 from unnest((select c.reloptions from pg_class c where c.oid = 'public.port_goods'::regclass)) o where o like 'autovacuum_vacuum_scale_factor=0.%')
     or exists (select 1 from unnest((select c.reloptions from pg_class c where c.oid = 'public.city_wants'::regclass)) o where o = 'autovacuum_vacuum_threshold=5000') then
    raise exception 'PROOF 129 FAIL: port_goods or city_wants was touched';
  end if;
  raise notice 'PASS: DR_SWEEP - fourteen tables at 5,000 + 10 %% (price_history_hour 5 %%), cost delay 20 / limit 25; port_goods and city_wants as they were';

  -- DR_KNOBS
  if public.wc_int('stats_fine_hours') <> 30 or public.wc_int('stats_hour_days') <> 8 or public.wc_int('price_history_hour_days') <> 8
     or public.wc_int('stats_city_good_keep_days') <> 90
     or (select count(*) from public.world_config c where c.key in ('stats_fine_hours', 'stats_hour_days', 'price_history_hour_days', 'stats_city_good_keep_days')
                                                    and c.description like '%0428:%') <> 4 then
    raise exception 'PROOF 129 FAIL: the knobs read % / % / % / %', public.wc_int('stats_fine_hours'), public.wc_int('stats_hour_days'),
      public.wc_int('price_history_hour_days'), public.wc_int('stats_city_good_keep_days');
  end if;
  raise notice 'PASS: DR_KNOBS - stats_fine_hours 30, stats_hour_days 8, price_history_hour_days 8, stats_city_good_keep_days 90, each saying 0428';

  -- a market row with no hour and no day in the record: its rows are the scene's alone
  select pg.port_id, pg.good_id into v_port, v_good
    from public.port_goods pg
   where not exists (select 1 from public.price_history_day d where d.port_id = pg.port_id and d.good_id = pg.good_id)
     and not exists (select 1 from public.price_history_hour h where h.port_id = pg.port_id and h.good_id = pg.good_id)
   order by pg.port_id, pg.good_id limit 1;
  if v_port is null then
    raise exception 'PROOF 129 FAIL: no market row without a record in this world';
  end if;

  -- DR_PRUNE
  insert into public.price_history_hour (port_id, good_id, hour, bid_o, bid_h, bid_l, bid_c, n)
  values (v_port, v_good, v_h - interval '10 days', 1, 1, 1, 1, 6), (v_port, v_good, v_h - interval '6 days', 2, 2, 2, 2, 6);
  perform public.tick_price_snapshot(now());
  if exists (select 1 from public.price_history_hour h where h.port_id = v_port and h.good_id = v_good and h.hour = v_h - interval '10 days')
     or not exists (select 1 from public.price_history_hour h where h.port_id = v_port and h.good_id = v_good and h.hour = v_h - interval '6 days') then
    raise exception 'PROOF 129 FAIL: the job kept the hour 10 days old or took the one 6 days old';
  end if;
  raise notice 'PASS: DR_PRUNE - the price-snapshot job took the hour 10 days old and kept the one 6 days old';

  -- DR_SPANS
  insert into public.price_history_day (port_id, good_id, day, bid_o, bid_h, bid_l, bid_c, n)
  select v_port, v_good, (now() at time zone 'UTC')::date - d, 10 + d, 10 + d, 10 + d, 10 + d, 96 from unnest(array[20, 40]) d;
  v_s := world.price_series(v_port, v_good, '1m');
  -- (the job above may have folded the planted hour into its day too: the read is judged by the two planted days alone)
  if v_s->>'tier' is distinct from 'day' or (v_s->>'step_seconds')::int <> 86400
     or not exists (select 1 from jsonb_array_elements(v_s->'points') x where (x->>'bid')::numeric = 30)
     or exists (select 1 from jsonb_array_elements(v_s->'points') x where (x->>'bid')::numeric = 50)
     or exists (select 1 from jsonb_array_elements(v_s->'points') x where (x->>'at')::timestamptz < now() - interval '31 days') then
    raise exception 'PROOF 129 FAIL: a month of prices: %', v_s;
  end if;
  v_s := world.price_series(v_port, v_good, '1w');
  if v_s->>'tier' is distinct from 'hour' or jsonb_array_length(v_s->'points') <> 1 or (v_s->'points'->0->>'bid')::numeric <> 2 then
    raise exception 'PROOF 129 FAIL: a week of prices: %', v_s;
  end if;
  if public.stats_span_unit('1d') <> 'fine' or public.stats_span_unit('1w') <> 'hour' or public.stats_span_unit('1m') <> 'day'
     or public.stats_span_unit('1y') <> 'day' or public.stats_span_unit('all') <> 'day' then
    raise exception 'PROOF 129 FAIL: the stats spans read 1w % 1m %', public.stats_span_unit('1w'), public.stats_span_unit('1m');
  end if;
  raise notice 'PASS: DR_SPANS - 1m the day 20 days old (not the one 40), tier day; 1w the hour 6 days old, tier hour; the stats spans group a month by day';
end
$p$;
