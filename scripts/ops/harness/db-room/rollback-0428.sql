-- 0428 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none"
-- and deploy it as any migration (owner only).
-- Gives the three hunks back (world.price_series x2, public.stats_span_unit: a month from the hours again), the four knobs their values before 0428,
-- and the fourteen tables the settings 0412 / 0226 gave them. Rows 0428's rules already folded or pruned do not come back: the hours past 8 days
-- were folded into their days (kept); a month chart drawn from the hours again shows hours only from the day this runs.
-- The knobs alone (no hunk) are the quick way back for the space: stats_fine_hours 72, stats_hour_days 30, price_history_hour_days 30
-- (a month chart then still reads the days, which are whole).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_fn  text[] := array['world.price_series(uuid,uuid,text)', 'world.price_series(uuid,uuid,text)', 'public.stats_span_unit(text)'];
  v_new text[] := array[
$h$  elsif p_span in ('1w', '1m') then
    v_tier := 'hour'; v_step := 3600;
$h$,
$h$       and (p_span = 'all' or d.day >= ((v_now - interval '365 days') at time zone 'UTC')::date);
$h$,
$h$  return case p_span when '1d' then 'fine' when '1w' then 'hour' when '1m' then 'hour' else 'day' end;
$h$];
  v_old text[] := array[
$h$  elsif p_span = '1w' then
    -- 0428: a week is drawn from the hours; a month from the days (price_history_hour keeps price_history_hour_days, 8)
    v_tier := 'hour'; v_step := 3600;
$h$,
$h$       and (p_span = 'all' or d.day >= ((v_now - case when p_span = '1m' then interval '30 days' else interval '365 days' end) at time zone 'UTC')::date);
$h$,
$h$  -- 0428: a month is drawn from the days (stats_hour_days 8 keeps a week of hours); a week from the hours
  return case p_span when '1d' then 'fine' when '1w' then 'hour' else 'day' end;
$h$];
  v_def text;
  t     record;
begin
  perform set_config('lock_timeout', '8s', true);
  for i in 1 .. 3 loop
    v_def := replace(pg_get_functiondef(v_fn[i]::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, v_old[i], ''))) / length(v_old[i]) <> 1 then
      raise exception 'rollback-0428: hunk % is not once in %', i, v_fn[i];
    end if;
    execute replace(v_def, v_old[i], v_new[i]);
  end loop;
  update public.world_config set value = to_jsonb(72) where key = 'stats_fine_hours' and value = to_jsonb(30);
  update public.world_config set value = to_jsonb(30) where key = 'stats_hour_days' and value = to_jsonb(8);
  update public.world_config set value = to_jsonb(30) where key = 'price_history_hour_days' and value = to_jsonb(8);
  update public.world_config set value = to_jsonb(30) where key = 'stats_city_good_keep_days' and value = to_jsonb(90);
  -- budget: puts back 0412's fixed thresholds (all at or over 20,000) and 0226's price_history_hour 1,000 with scale factor 0, the settings before 0428
  for t in select * from (values ('events', 200000), ('ledger', 150000), ('voyage_events', 150000), ('voyages', 60000), ('standing_route_laps', 50000),
                                 ('orders', 50000), ('stats_city_good', 100000), ('stats_good', 50000), ('stats_city', 25000), ('price_history', 50000),
                                 ('treasury_flows', 100000), ('trade_daily', 50000), ('insured_voyages', 50000)) x(tbl, thr) loop
    -- budget: 0412's own values, each 25,000 or more
    execute format('alter table public.%I set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = %s)', t.tbl, t.thr);
  end loop;
  -- budget: price_history_hour back to 0226's 1,000 dead rows with scale factor 0 (the setting the daily read flags; the rollback restores it as it was)
  alter table public.price_history_hour reset (autovacuum_vacuum_cost_delay, autovacuum_vacuum_cost_limit);
  alter table public.price_history_hour set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);
  raise notice 'rollback-0428: three hunks reversed, four knobs and fourteen tables back';
end $r$;
