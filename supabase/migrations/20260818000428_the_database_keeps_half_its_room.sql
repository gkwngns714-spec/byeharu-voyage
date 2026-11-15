-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0428 - THE DATABASE KEEPS HALF ITS ROOM  (the sweeper scales with each table again; the stats keep 30 hours of fine points and a week of
--        hours; the price record a week of hours; a month chart draws a point a day; the city goods' days kept 90 days)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER (2026-11-15): "there should be a room of course, not just too tight": the database within about HALF of each limit in
--   docs/DATABASE_BUDGET.md: size under ~750 MB of the 1,500, cache hit 99 % or better, the ten biggest tables inside the ~700 MB of cache.
--
-- MEASURED (prod, read-only, the gate green: beat 128 ms mean / 398 p95, 0 disk waits; docs/dev-log/2026-11-15-db-room.md has every figure):
--   1,002 MB at 00:42 UTC (907 at 20:30, 939 at 23:40); hot set 735 MB; cache hit 98.25 %. WHY IT GROWS:
--   a. 0412's FIXED THRESHOLDS ARE NOW BIGGER THAN THE TABLES. 0412 sized them (scale factor 0, 50,000 to 200,000 dead rows) for the tables
--      of 11-14 morning, five to ten times today's; 0409's retention then cut the live rows. A dead row's slot is reused only after a pass,
--      so every churn table grows to its live rows PLUS its threshold before it is swept: voyages 46,233 dead beside 43,791 live (51 %),
--      events 109,353 / 79,676, ledger 96,171 / 33,222, voyage_events 89,916 / 288,521, stats_city_good 82,390 / 205,634, insured_voyages
--      41,958 / 5,204, standing_route_laps 31,151 / 10,397, orders 26,649 / 17,717, trade_daily 23,041 / 1,203, treasury_flows 19,461 / 1,268:
--      ~470,000 dead rows held on purpose. events was last swept 11:40, voyage_events 11:43, ledger 14:08, voyages 20:39. More ships at sea
--      since 0423 / 0425 fill those quotas faster (voyages ~370,000 dead rows a day, orders ~640,000).
--   b. THE STATS AND PRICE TIERS ARE STILL FILLING. 0421 doubled the Stats count (4 an hour) and its fine tier keeps 72 hours; the hourly
--      tiers keep 30 days and the world is ~23 days old, so stats_good (79 -> 103 MB since 20:30), stats_city and price_history_hour
--      (155 MB, 703,000 rows) grow until day 30: about +100 MB more at the rules of today.
--   NOT THE CAUSE: no long transaction (the oldest 1 s; every backend's xmin age under 10); port_goods (flat at 92-93 MB since 11-01: 99 %
--      of its updates are HOT and pruned on the page; its dead share is a 2-35 % saw every 13 minutes, so the daily read now leaves it out).
--
-- WHAT THIS FILE DOES (storage parameters, four knobs, three hunks in two readers; no table, no index, no cron, no row of the game):
--   1. THE SWEEPER SCALES WITH THE TABLE (docs/DATABASE_BUDGET.md rule 5). The 13 churn tables of 0412 (city_wants untouched) get
--      autovacuum_vacuum_scale_factor 0.1 and autovacuum_vacuum_threshold 5,000: a pass when the dead rows reach 5,000 + 10 % of the live,
--      so a table carries at most ~15 % dead instead of 50-1,800 %. Their insert and analyze settings and 0412's pace (cost delay 20 ms,
--      cost limit 25: ~5 MB/s read, ~0.5 MB/s dirtied) are kept. price_history_hour: 1,000 dead rows with scale factor 0 (0226; the daily
--      read's autovac_low line) -> scale factor 0.05 and 5,000, at the same pace.
--        table               live now   dead/day (now)   pass at (now -> settled)   passes a day   0412's    room held   after a rewrite
--        voyages              43,800       ~370,000          9,400                       ~40           60,000     84 MB        ~40 MB
--        orders               17,700       ~640,000          6,800                       ~90           50,000     37           ~12
--        events               79,700       ~290,000         13,000                       ~22          200,000     49           ~21
--        ledger               33,200       ~260,000          8,300                       ~31          150,000     10           ~4
--        voyage_events       288,500       ~220,000         34,000                       ~6           150,000     46           ~34
--        treasury_flows        1,300       ~260,000          5,100                       ~50          100,000     21           ~3
--        standing_route_laps  10,400       ~240,000          6,000                       ~30           50,000     11           ~4
--        trade_daily           1,200        ~55,000          5,100                       ~11           50,000     27           ~3
--        insured_voyages       5,200        ~37,000          5,500                       ~7            50,000     14           ~3
--        price_history        68,700       ~200,000         11,900                       ~17           50,000     24           ~14
--        stats_good          425,000 -> ~200,000  ~240,000  ~25,000                      ~10           50,000    103           ~42
--        stats_city          168,700 -> ~85,000   ~100,000  ~13,500                      ~7            25,000     76           ~35
--        stats_city_good     205,600             ~250,000  ~25,600                      ~10          100,000     65           ~47
--        price_history_hour  703,500 -> ~225,000   ~28,000  ~16,000 (scale 0.05)         ~2            1,000     155           ~48
--      ~330 passes a day in all, over tables of 2-60 MB that sit in the cache (0412 cut ~3,000 passes a day over 200-550 MB tables that
--      did not; the age-driven anti-wraparound pass is untouched). "after a rewrite" is the runbook's VACUUM FULL (below), not this file.
--   2. THE STATS KEEP 30 HOURS OF FINE POINTS AND A WEEK OF HOURS: stats_fine_hours 72 -> 30 (stats_world, stats_merchants, stats_good,
--      stats_city; a 1-day graph reads 24 hours, the day-ago lookups the row at 24 hours, the history job's close of yesterday at 00:12
--      reads fine rows at most 24 h 12 min old) and stats_hour_days 30 -> 8 (stats_good, stats_city: a 1-week graph reads 7 days of hours,
--      a good's "7 days ago" price the row at 7 days). Past 8 days a row is folded to its day, flows added, as 0246 always folded past day 30.
--      stats_compact folds 4 hours and 1 day a run per table (0290): the day marks stand at 10-16 (prod), so ~22 runs, ~5.5 hours, ~15,000 rows a run.
--   3. THE PRICE RECORD KEEPS A WEEK OF HOURS: price_history_hour_days 30 -> 8. Its days are kept for ever as before (price_history_day).
--      The first price-snapshot run after this file prunes the ~480,000 hours past 8 days ONCE (its own unbounded prune, 0226: ~30 s and
--      ~110 MB of WAL, one time; the price-snapshot job is the only one that waits); then ~1,200 rows an hour as now.
--   4. A MONTH CHART DRAWS A POINT A DAY (the readers follow 2 and 3, the change 0409 and 0416 named and left): public.stats_span_unit
--      '1m' -> 'day' (world.stats_overview, world.stats_city, world.stats_merchants group a month by day: purse / holders the day's last,
--      flows the day's sum) and world.price_series '1m' -> the daily tier (open / high / low / close of each day, both sides), 30 days.
--      1d stays the fine points, 1w the hours, 1y and all the days. A month chart had 720 hourly points; it now has 30, the newest the last
--      whole day (as 1y). The client's own copy of that table (src/features/stats/statsFaces.ts SPAN_PERIOD) moves with it in this PR.
--   5. THE CITY GOODS' DAYS ARE KEPT 90 DAYS (stats_city_good_keep_days 30 -> 90; the owner asked for longer, docs/dev-log/2026-11-14-slim-laps.md):
--      one row a pair a day, ~0.3 MB a day: +18 MB over the next two months, nothing now.
--
-- WHAT IT COSTS / WHAT IT GIVES (MB; the dev-log has the arithmetic): this file alone shrinks no file (PostgreSQL reuses freed space inside a
--   table); it stops the growth at once and lets each table settle at its live rows + ~15 %. The space comes back with the runbook,
--   scripts/ops/harness/db-room/RUNBOOK.md (VACUUM FULL, one statement a call, the lead's to run after the trims drain): 1,002 -> ~590 MB, then
--   ~650-680 MB with the dead room and 0427's battles (~100 rows a minute, kept 48 h: ~50 MB). Hot set ~450 MB (limit ~700).
-- NOT CHANGED, AND WHY: port_goods (its fillfactor 30 is the owner's call, RUNBOOK 3b; the runbook offers fillfactor 50 as an optional step,
--   -35 MB); city_wants (small, not over); every insert-vacuum and analyze threshold; every cron job; the 1d / 1w / 1y / all spans.
-- LOAD: no new rows a minute. The sweeper: ~330 passes a day of 2-60 MB cached tables at 0412's pace (the table above).
-- LOCKS: ALTER TABLE SET (storage parameters) takes SHARE UPDATE EXCLUSIVE (no read or write waits; an autovacuum in the way is cancelled
--   after deadlock_timeout); CREATE OR REPLACE x2 by hunks; four world_config rows. lock_timeout 8 s, statement_timeout 60 s: a table that
--   cannot be had fails the file with its name and nothing is changed.
-- ROLLBACK (forward, owner only): scripts/ops/harness/db-room/rollback-0428.sql, a draft: the three hunks reversed, the four knobs and the
--   fourteen tables' 0412 / 0226 settings back. Rows already folded or pruned are not brought back (their days are kept).
-- SELF-ASSERT: the catalog (every table reads back its settings and kept every other option), the knobs, each hunk once and reversing, no
--   other function moved; a probe on ONE pair that has no day row, rolled back: three planted days and one hour, read back through
--   world.price_series by span. Its behaviour over the world: proof 129.
-- VERSION: 0428 = prod head 0425 + 0426 (PR #703) + 0427 (PR #706), each queued ahead. 0426 / 0427 touch none of these bodies or knobs.
-- news: one update row (a month chart draws a point a day).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0       timestamptz := clock_timestamp();
  c_ps       constant text := 'world.price_series(uuid,uuid,text)';
  c_su       constant text := 'public.stats_span_unit(text)';
  v_pre_ps   text;
  v_pre_su   text;
  v_meta_ps  text;
  v_meta_su  text;
  v_fn_before text;
  v_def      text;
  v_old      text[];
  v_new      text[];
  v_fn       text[];
  v_pre      text;
  i          int;
  v_n        int;
  v_kept     text := '';
  t          record;
  v_was      text[];
  v_now      text[];
  v_want     text[];
  v_o        text;
  v_port     uuid;
  v_good     uuid;
  v_s        jsonb;
  v_note     text := 'no market row without a day row in this world: proof 129 reads the spans';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '8s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_ps) is null or to_regprocedure(c_su) is null or to_regprocedure('public.news_update(text,text,text)') is null
     or (select count(*) from public.world_config where key in ('stats_fine_hours', 'stats_hour_days', 'price_history_hour_days', 'stats_city_good_keep_days')) <> 4 then
    raise exception '0428 refuses: the price record (0226), the stats spans (0246), the news or the four knobs are not all in this world';
  end if;
  if position('-- 0428:' in pg_get_functiondef(c_ps::regprocedure)) > 0 then
    raise exception '0428 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  v_pre_ps := replace(pg_get_functiondef(c_ps::regprocedure), E'\r', '');
  v_pre_su := replace(pg_get_functiondef(c_su::regprocedure), E'\r', '');
  select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
    into v_meta_ps from pg_proc p where p.oid = c_ps::regprocedure;
  select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
    into v_meta_su from pg_proc p where p.oid = c_su::regprocedure;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid not in (c_ps::regprocedure, c_su::regprocedure);

  -- ── 2. THE KNOBS. Each moves only from the value this file was written against (prod's at 00:42 UTC 2026-11-15); an owner's own value is
  --    left and named in the receipt.
  update public.world_config set value = to_jsonb(30), updated_at = now(),
         description = coalesce(description, '') || ' 0428: 72 -> 30 (the owner, 2026-11-15: "there should be a room"; a 1-day graph reads 24 h, the day-ago rows 24 h, the history job''s close of yesterday under 24 h 12 min).'
   where key = 'stats_fine_hours' and value = to_jsonb(72);
  if not found then v_kept := v_kept || 'stats_fine_hours '; end if;
  update public.world_config set value = to_jsonb(8), updated_at = now(),
         description = coalesce(description, '') || ' 0428: 30 -> 8 (a 1-week graph reads 7 days of hours, a good''s 7-day price the row at 7 days; a month graph is drawn from the days since 0428).'
   where key = 'stats_hour_days' and value = to_jsonb(30);
  if not found then v_kept := v_kept || 'stats_hour_days '; end if;
  update public.world_config set value = to_jsonb(8), updated_at = now(),
         description = coalesce(description, '') || ' 0428: 30 -> 8 (world.price_series reads hours for 1w only; 1m reads price_history_day since 0428).'
   where key = 'price_history_hour_days' and value = to_jsonb(30);
  if not found then v_kept := v_kept || 'price_history_hour_days '; end if;
  update public.world_config set value = to_jsonb(90), updated_at = now(),
         description = coalesce(description, '') || ' 0428: 30 -> 90 (the owner asked to keep the city goods longer; a day is one row a pair, ~0.3 MB a day).'
   where key = 'stats_city_good_keep_days' and value = to_jsonb(30);
  if not found then v_kept := v_kept || 'stats_city_good_keep_days '; end if;
  if public.wc_int('stats_hour_days') * 24 <= public.wc_int('stats_fine_hours') then
    raise exception '0428 self-assert FAIL: stats_hour_days % does not exceed stats_fine_hours % (stats_compact would refuse every count)',
      public.wc_int('stats_hour_days'), public.wc_int('stats_fine_hours');
  end if;

  -- ── 3. THE HUNKS (LF; each once in its live body, reversing to its pre-image) ──
  v_fn  := array[c_ps, c_ps, c_su];
  v_old := array[
$h$  elsif p_span in ('1w', '1m') then
    v_tier := 'hour'; v_step := 3600;
$h$,
$h$       and (p_span = 'all' or d.day >= ((v_now - interval '365 days') at time zone 'UTC')::date);
$h$,
$h$  return case p_span when '1d' then 'fine' when '1w' then 'hour' when '1m' then 'hour' else 'day' end;
$h$];
  v_new := array[
$h$  elsif p_span = '1w' then
    -- 0428: a week is drawn from the hours; a month from the days (price_history_hour keeps price_history_hour_days, 8)
    v_tier := 'hour'; v_step := 3600;
$h$,
$h$       and (p_span = 'all' or d.day >= ((v_now - case when p_span = '1m' then interval '30 days' else interval '365 days' end) at time zone 'UTC')::date);
$h$,
$h$  -- 0428: a month is drawn from the days (stats_hour_days 8 keeps a week of hours); a week from the hours
  return case p_span when '1d' then 'fine' when '1w' then 'hour' else 'day' end;
$h$];
  for i in 1 .. 3 loop
    v_def := replace(pg_get_functiondef(v_fn[i]::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, v_old[i], ''))) / length(v_old[i]);
    if v_n <> 1 then
      raise exception '0428 self-assert FAIL: hunk % occurs % time(s) in %, not once: the deployed body is not what this file was written against', i, v_n, v_fn[i];
    end if;
    execute replace(v_def, v_old[i], v_new[i]);
  end loop;
  for i in 1 .. 3 loop
    v_def := replace(pg_get_functiondef(v_fn[i]::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, v_new[i], ''))) / length(v_new[i]) <> 1 then
      raise exception '0428 self-assert FAIL: hunk % is not in the new body of % once', i, v_fn[i];
    end if;
  end loop;
  v_def := replace(pg_get_functiondef(c_ps::regprocedure), E'\r', '');
  if replace(replace(v_def, v_new[1], v_old[1]), v_new[2], v_old[2]) <> v_pre_ps then
    raise exception '0428 self-assert FAIL: % does not reverse to its pre-image', c_ps;
  end if;
  v_def := replace(pg_get_functiondef(c_su::regprocedure), E'\r', '');
  if replace(v_def, v_new[3], v_old[3]) <> v_pre_su then
    raise exception '0428 self-assert FAIL: % does not reverse to its pre-image', c_su;
  end if;
  if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
        from pg_proc p where p.oid = c_ps::regprocedure) <> v_meta_ps
     or (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
        from pg_proc p where p.oid = c_su::regprocedure) <> v_meta_su then
    raise exception '0428 self-assert FAIL: the grants, volatility, definer, search path or owner of a re-cut reader moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid not in (c_ps::regprocedure, c_su::regprocedure)) <> v_fn_before then
    raise exception '0428 self-assert FAIL: another function moved';
  end if;

  -- ── 4. THE SWEEPER SCALES WITH THE TABLE ──
  -- budget: scale factor 0.1 (0.05 on price_history_hour) with a threshold of 5,000 is NOT a fixed threshold: a pass comes at 5,000 + 10 % of
  --   the live rows (rule 5 of docs/DATABASE_BUDGET.md). ~330 passes a day in all over 2-60 MB cached tables at 0412's pace; the table in the header.
  create temp table set_0428 (tbl text primary key, sf numeric, thr int) on commit drop;
  insert into set_0428 values
    ('events', 0.1, 5000), ('ledger', 0.1, 5000), ('voyage_events', 0.1, 5000), ('voyages', 0.1, 5000), ('standing_route_laps', 0.1, 5000),
    ('orders', 0.1, 5000), ('stats_city_good', 0.1, 5000), ('stats_good', 0.1, 5000), ('stats_city', 0.1, 5000), ('price_history', 0.1, 5000),
    ('treasury_flows', 0.1, 5000), ('trade_daily', 0.1, 5000), ('insured_voyages', 0.1, 5000), ('price_history_hour', 0.05, 5000);
  for t in select * from set_0428 order by tbl loop
    if to_regclass('public.' || t.tbl) is null then
      raise exception '0428 refuses: public.% is not in this world', t.tbl;
    end if;
    select c.reloptions into v_was from pg_class c where c.oid = ('public.' || t.tbl)::regclass;
    begin
      -- budget: the threshold scales with the table (scale factor 0.1 / 0.05, never 0); the pace is 0412's on every one of them
      execute format('alter table public.%I set (autovacuum_vacuum_scale_factor = %s, autovacuum_vacuum_threshold = %s, '
                     || 'autovacuum_vacuum_cost_delay = 20, autovacuum_vacuum_cost_limit = 25)', t.tbl, t.sf, t.thr);
    exception when lock_not_available then
      raise exception '0428 could not have public.% within 8 s (SHARE UPDATE EXCLUSIVE): a VACUUM that cannot be cancelled, or a schema change, holds it. Nothing was changed. Run the deploy again in a few minutes.', t.tbl;
    end;
    select c.reloptions into v_now from pg_class c where c.oid = ('public.' || t.tbl)::regclass;
    v_want := array['autovacuum_vacuum_scale_factor=' || t.sf, 'autovacuum_vacuum_threshold=' || t.thr,
                    'autovacuum_vacuum_cost_delay=20', 'autovacuum_vacuum_cost_limit=25'];
    if not (v_now @> v_want) then
      raise exception '0428 self-assert FAIL: public.% reads % and not %', t.tbl, v_now, v_want;
    end if;
    foreach v_o in array coalesce(v_was, '{}'::text[]) loop
      if split_part(v_o, '=', 1) not in ('autovacuum_vacuum_scale_factor', 'autovacuum_vacuum_threshold', 'autovacuum_vacuum_cost_delay', 'autovacuum_vacuum_cost_limit')
         and not (v_o = any(v_now)) then
        raise exception '0428 self-assert FAIL: public.% lost its option %', t.tbl, v_o;
      end if;
    end loop;
    if exists (select 1 from unnest(v_now) o where o like 'autovacuum_enabled=%') then
      raise exception '0428 self-assert FAIL: public.% carries autovacuum_enabled: this file never turns the sweeper off', t.tbl;
    end if;
  end loop;

  -- ── 5. THE NEWS (0347's law) ──
  perform public.news_update('0428', 'Month charts draw a point a day', '한 달 차트는 하루에 한 점');

  -- ── 6. THE PROBE, rolled back by a raised sentinel: ONE market row that has no day row in the record (its own rows only): three planted
  --    days (3, 20 and 40 days ago) and one planted hour (2 hours ago). 1m reads the two days inside 30 days from the day tier; 1w reads the
  --    hour; 1y reads all three days.
  select pg.port_id, pg.good_id into v_port, v_good
    from public.port_goods pg
   where not exists (select 1 from public.price_history_day d where d.port_id = pg.port_id and d.good_id = pg.good_id)
     and not exists (select 1 from public.price_history_hour h where h.port_id = pg.port_id and h.good_id = pg.good_id)
   limit 1;
  if v_port is not null then
    begin
      insert into public.price_history_day (port_id, good_id, day, ask_o, ask_h, ask_l, ask_c, bid_o, bid_h, bid_l, bid_c, n)
      select v_port, v_good, ((now() at time zone 'UTC')::date - d), null, null, null, null, 4280 + d, 4290 + d, 4270 + d, 4285 + d, 96
        from unnest(array[3, 20, 40]) d;
      insert into public.price_history_hour (port_id, good_id, hour, ask_o, ask_h, ask_l, ask_c, bid_o, bid_h, bid_l, bid_c, n)
      values (v_port, v_good, date_trunc('hour', now()) - interval '2 hours', null, null, null, null, 4201, 4209, 4200, 4204, 6);
      v_s := world.price_series(v_port, v_good, '1m');
      if v_s->>'tier' <> 'day' or (v_s->>'step_seconds')::int <> 86400 or jsonb_array_length(v_s->'points') <> 2
         or (v_s->'points'->0->>'bid')::numeric <> 4305 or (v_s->'points'->1->>'bid')::numeric <> 4288 then
        raise exception '0428 self-assert FAIL: 1m did not read the two planted days inside 30 days from the day tier: %', v_s;
      end if;
      v_s := world.price_series(v_port, v_good, '1w');
      if v_s->>'tier' <> 'hour' or jsonb_array_length(v_s->'points') <> 1 or (v_s->'points'->0->>'bid')::numeric <> 4204 then
        raise exception '0428 self-assert FAIL: 1w did not read the planted hour from the hour tier: %', v_s;
      end if;
      v_s := world.price_series(v_port, v_good, '1y');
      if v_s->>'tier' <> 'day' or jsonb_array_length(v_s->'points') <> 3 then
        raise exception '0428 self-assert FAIL: 1y did not read the three planted days: %', v_s;
      end if;
      if public.stats_span_unit('1m') <> 'day' or public.stats_span_unit('1w') <> 'hour' or public.stats_span_unit('1d') <> 'fine'
         or public.stats_span_unit('1y') <> 'day' or public.stats_span_unit('all') <> 'day' then
        raise exception '0428 self-assert FAIL: the stats spans read 1d %, 1w %, 1m %, 1y %, all %', public.stats_span_unit('1d'),
          public.stats_span_unit('1w'), public.stats_span_unit('1m'), public.stats_span_unit('1y'), public.stats_span_unit('all');
      end if;
      v_note := 'one market row: 1m two planted days from the day tier, 1w the planted hour, 1y three days; the stats spans 1m -> day';
      raise exception sqlstate 'BV428';
    exception when sqlstate 'BV428' then null;
    end;
    if v_note not like 'one market row%' then
      raise exception '0428 self-assert FAIL: the probe did not run to its end';
    end if;
    if exists (select 1 from public.price_history_day d where d.port_id = v_port and d.good_id = v_good)
       or exists (select 1 from public.price_history_hour h where h.port_id = v_port and h.good_id = v_good) then
      raise exception '0428 self-assert FAIL: the probe rows were not rolled back';
    end if;
  end if;

  -- ── 7. THE KNOBS READ BACK ──
  if v_kept = '' and (public.wc_int('stats_fine_hours') <> 30 or public.wc_int('stats_hour_days') <> 8 or public.wc_int('price_history_hour_days') <> 8
                      or public.wc_int('stats_city_good_keep_days') <> 90) then
    raise exception '0428 self-assert FAIL: the knobs read % / % / % / %, not 30 / 8 / 8 / 90', public.wc_int('stats_fine_hours'),
      public.wc_int('stats_hour_days'), public.wc_int('price_history_hour_days'), public.wc_int('stats_city_good_keep_days');
  end if;
  if clock_timestamp() - v_t0 > interval '60 seconds' then
    raise exception '0428 self-assert FAIL: the file took % (budget 60 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0428 self-assert ok: THE DATABASE KEEPS HALF ITS ROOM. Fourteen tables sweep at 5,000 + 10 %% of their rows (price_history_hour 5 %%), at 0412''s pace; every other option kept. Knobs: stats_fine_hours %, stats_hour_days %, price_history_hour_days %, stats_city_good_keep_days %.% Three hunks (world.price_series x2, public.stats_span_unit), each once and reversing; grants and volatility unmoved; no other function moved. Probe: %; % ms.',
    public.wc_int('stats_fine_hours'), public.wc_int('stats_hour_days'), public.wc_int('price_history_hour_days'), public.wc_int('stats_city_good_keep_days'),
    case when v_kept = '' then '' else ' Left at the owner''s value: ' || v_kept || '.' end, v_note,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
