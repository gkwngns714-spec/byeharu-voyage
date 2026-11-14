-- before.sql: READ ONLY on prod, one statement, BEFORE 0419 is pushed. Each hunk of 0419 occurs exactly once in the live body it cuts (want 1 1 1 1),
-- nothing of 0419 is there yet, the head is 0418, and the Stats count's last four runs (ms, and its merchants phase: the new phase sits after it).
-- Catalog reads, pg_get_functiondef (STABLE) and stats_runs (7 days of receipts) only.
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'absent', to_regclass('public.stats_fleets') is null and to_regprocedure('world.stats_fleets()') is null and to_regprocedure('public.stats_fleets_count(timestamptz,timestamptz)') is null,
  'hunks', (select jsonb_agg((length(b.def) - length(replace(b.def, h.old, ''))) / length(h.old) order by h.ord)
              from (values
                (1, 'public.tick_stats(timestamp with time zone)', $h$  v_w int := 0; v_g int := 0; v_c int := 0; v_cg int := 0; v_m int := 0; v_x int := 0;
$h$),
                (2, 'public.tick_stats(timestamp with time zone)', $h$  get diagnostics v_m = row_count;
  v_ph := v_ph || jsonb_build_object('merchants', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$),
                (3, 'public.tick_stats(timestamp with time zone)', $h$                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x, 'fold', v_fold,
$h$),
                (4, 'public.client_rpc_entry_points()', $h$      ('world',       'stats_me',              ''),
$h$)) h(ord, fn, old)
              cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) b),
  'runs', (select jsonb_agg(jsonb_build_object('at', x.at, 'ms', x.ms, 'merchants_ms', x.receipt -> 'phases' -> 'merchants') order by x.at desc)
             from (select r.at, r.ms, r.receipt from public.stats_runs r order by r.at desc limit 4) x)
) as before_0419;
commit;
