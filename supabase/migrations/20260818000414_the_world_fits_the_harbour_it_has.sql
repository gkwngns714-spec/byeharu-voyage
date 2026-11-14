-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0414 - THE WORLD FITS THE HARBOUR IT HAS  (the minute jobs read less, the old books go, the compactor's limits are knobs)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none
--
-- WHY (prod, read-only, 2026-11-14 09:07 to 09:50 UTC, head 0408; docs/dev-log/2026-11-14-slim-db.md):
--   The database is 2,826 MB on a 1 GB instance (shared_buffers 256 MB). Since 09:07 every session waits on the disk: the arrivals beat takes
--   about 12 s where it took 0.6 s, the compactor cuts ONE house a minute where it must cut about fifteen, and the Stats count takes 23 to 26 s.
--   What reads the disk, by pg_stat_statements since 11-01 (blocks read):
--     the drift job        197,142,635 over 18,648 runs: 83 MB a minute. It rewrites EVERY port_goods row every minute (156,621 rows; the heap is
--                          113 MB at fillfactor 30 with 224,914 dead rows) and counts each harbour's rows first: the whole heap, read and dirtied.
--     the Stats count      28,872,851 over 1,215 runs: 190 MB a run. Its `day` phase (7 to 9.5 s) sums every harbour's port_goods stock: that heap
--                          again, whole; its `merchants` phase (3.6 to 4.7 s) reads a day of laps out of a 226 MB heap that holds 87,000 rows.
--     world.sea_roster     16,102,016 over 2,383 calls: 53 MB a call. It places every merchant fleet from voyages and voyage_events.
--   What lies on the disk for nobody: public.city_wants keeps every period since 10-28 (446,425 rows, 112 MB; the game reads two periods);
--   public.stats_city_good keeps a daily tier nobody reads (its trim, 0316, ships OFF) and a primary key swollen to 273 MB; the merchants' books
--   (events 881,000 rows, ledger 503,000) are six hours of a fleet that writes 117,000 events an hour.
--
-- THE OWNER'S ORDER (2026-11-14, verbatim): "reduce the #1, #2 to a reasonable amount. #3 also."  #1 the market repriced every minute for all
--   156,000 port goods; #2 the history; #3 the Stats count.
--
-- WHAT THIS FILE DOES. Every amount is a named knob; the old value is in its description.
--   1. THE DRIFT JOB STEPS ONE HARBOUR IN TEN A RUN (knob drift_spread_runs 10; 1 = every harbour every run, as before). The job still runs
--      every minute; public.drift_ports_due (new, THE answer to "whose turn is it") gives it the harbours whose place in the port order falls
--      on this minute. A harbour stepped after k missed slots takes ONE COMPOUNDED STEP in public.tick_market_drift:
--          drift <- theta^k * drift + sigma * sqrt((1 - theta^(2k)) / (1 - theta^2)) * N(0,1)
--      which is exactly the law of k one-slot steps (the clamp aside, 10.0 on prod: never met), so a price moves as far in a game day as it does
--      now: drift_sigma and drift_theta are NOT touched, the walk is no stronger and no gentler. For k = 1 the expression is the old one,
--      figure for figure. The stock's regeneration and the glut's decay were already closed-form over the game-days and the hours missed
--      (0137, 0271). A quay somebody opens is still stepped on that read (world.market calls the step for its own harbour), so a player sees
--      the price of this minute. PER GAME DAY: a harbour nobody looks at is repriced game_day_seconds / (60 x drift_spread_runs) times a game
--      day: 6 times at a one-hour day, once every ten game-days at the 60 s day prod serves today; nothing here assumes either.
--   2. THE BOOKS:
--      a. public.city_wants: past periods go (knob city_wants_keep_periods 10, about four hours; the game reads the period and the one before).
--         The table stays append-only: its trigger is now public.city_wants_guard, which lets ONE thing through, the compactor's delete of a
--         period older than the keep (byeharu.wants_trim, transaction-local, set by public.tick_compact alone).
--      b. A MERCHANT's lap history: a lap that is BOTH past her route's newest npc_route_lap_keep (24) AND closed more than
--         npc_route_lap_keep_hours (26) ago goes, in public.npc_compact_houses, at most compact_trim_rows (2,000) a batch. Every reader of a
--         merchant's laps still finds what it reads (the 24 h of route_earnings / fleet_trades / stats_merchants_window and the one lap before
--         them; the newest 20 inside 3 days of npc_share_budget; the newest 8, 2, 1). A PLAYER's route keeps standing_route_lap_keep (100).
--         cmd.standing_route_close_lap is NOT touched.
--      c. public.stats_city_good: its trim is lit (stats_city_good_keep_days 0 -> 3: 0316's own rule, 20,000 rows a history run, never under
--         3 days) and its fine window is 26 hours (stats_city_good_fine_hours 48 -> 26: the readers want 24 h and the row at 24 h).
--      d. The merchants' books are kept three hours (npc_retention_hours 6 -> 3): voyages, voyage_events, ledger, events, orders.
--      e. public.standing_route_laps_closed_at is dropped: 44 scans in thirteen days (pg_stat_user_indexes), and every lap close wrote to it.
--   3. THE STATS COUNT RUNS TWICE AN HOUR (pg_cron byeharu-voyage:stats '6,21,36,51 * * * *' -> '6,36 * * * *'). The Stats tab's figures are
--      the count plus the minutes since (0232), so they still move by the second; the points of a 1-day graph are 30 minutes apart.
--   4. THE COMPACTOR'S LIMITS ARE KNOBS, at the values they had: compact_budget_ms 8000, compact_hold_ms 200, compact_batch_max 25.
--
-- WHAT A PLAYER LOSES: "who bought what" at a city lists merchants' trades of the last three hours, not six (a player's own stay). A 1-day
--   Stats graph has a point every 30 minutes, not every 15. A harbour nobody is looking at moves its price every ten minutes, in one step as
--   large as its ten small ones. Nothing else: no screen reads a row this file lets go.
-- NOT BUILT (docs/dev-log/2026-11-14-slim-db.md): the month graphs still draw from hourly rows (price_history_hour, stats_good, stats_city: 30
--   days); moving them to the daily rows is a change to world.price_series, the Stats spans and their specs. The players' own books stay whole.
-- DELETES: none here. Every row goes by the compactor's own rule, a bounded batch a run. This file's probe rows are rolled back.
-- LOCKS: DROP INDEX and the trigger swap take brief ACCESS EXCLUSIVE / SHARE ROW EXCLUSIVE locks (lock_timeout 5 s: the file fails rather than
--   queue the beat behind it); CREATE OR REPLACE x4 by hunks. TIME: the probes run in rolled-back sub-transactions: one harbour's
--   drift step twice, one compactor pass with its budget at 1 ms (it reads the due list and trims up to 2,000 old wants), one merchant house
--   compacted as of ten years ago (her books are not read). Expected under 10 s on prod. BUDGET: statement_timeout 90 s; fails above 60 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/slim-db/rollback-0414.sql, a draft. At once, with no file: drift_spread_runs 1 steps every
--   harbour every run again; npc_route_lap_keep 0 and city_wants_keep_periods 0 stop those trims; stats_city_good_keep_days 0 stops that one.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then the probes.
-- VERSION: 0414 (0409 to 0413 are other builders' open work). It re-cuts no function they re-cut.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.tick_market_drift(timestamp with time zone,uuid)', 'public.tick_market_drift_each_port()',
                                 'public.npc_compact_houses(uuid[],timestamp with time zone)', 'public.tick_compact(boolean,boolean)'];
  c_new constant text[] := array['public.drift_ports_due(timestamp with time zone)', 'public.city_wants_guard()'];
  v_t0        timestamptz := clock_timestamp();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_port      uuid;
  v_good      uuid;
  v_slot      bigint;
  v_d         numeric;
  v_house     uuid;
  v_route     uuid;
  v_lapno     int;
  v_ids       uuid[];
  v_left      int;
  v_period    bigint;
  v_live      bigint;
  v_note      text := '';
  v_at        timestamptz := now() - interval '3650 days';   -- the laps' probe is compacted as of this instant
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'drift_spread_runs') or to_regprocedure('public.drift_ports_due(timestamp with time zone)') is not null then
    raise exception '0414 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.tick_compact(boolean,boolean)') is null or to_regprocedure('public.history_trim(timestamp with time zone)') is null
     or not exists (select 1 from pg_trigger where tgrelid = 'public.city_wants'::regclass and tgname = 'city_wants_append_only') then
    raise exception '0414 refuses: the compactor (0265), the history trim (0316) or the wants'' append-only trigger (0255) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0414 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0414
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('drift_spread_runs', to_jsonb(10),
     '0414: the drift job (pg_cron byeharu-voyage:drift, every minute) steps one harbour in this many a run, by its place in the port order (public.drift_ports_due); a harbour stepped after k missed slots takes one compounded step with the law of k steps (public.tick_market_drift), and a quay somebody opens is stepped on that read. 1 = every harbour every run (the rule before 0414).'),
    ('city_wants_keep_periods', to_jsonb(10),
     '0414: public.tick_compact deletes public.city_wants rows of a want-period older than this many periods before the current one, compact_trim_rows a run; never fewer than 2 are kept (the draw reads the period before). 0 = OFF, nothing is deleted (the rule before 0414: every period since 0255 was kept).'),
    ('npc_route_lap_keep', to_jsonb(24),
     '0414: a MERCHANT route keeps its newest this-many laps whatever their age, and every lap closed inside npc_route_lap_keep_hours; a lap past both goes in public.npc_compact_houses. Never under 20 (public.npc_share_budget reads 20). 0 = OFF: a merchant route keeps standing_route_lap_keep laps like a player''s (the rule before 0414: 100).'),
    ('npc_route_lap_keep_hours', to_jsonb(26),
     '0414: see npc_route_lap_keep. Never under 25: the day figures read the last 24 hours and the lap before them.'),
    ('compact_trim_rows', to_jsonb(2000),
     '0414: the most rows one trim statement of the compactor deletes (the merchants'' old laps a batch of houses; the past city wants a run).'),
    ('compact_budget_ms', to_jsonb(8000),
     '0414: public.tick_compact''s work a minute, at most (the constant c_budget before 0414: 8 s). Raising it lets a backlog be walked faster: more transactions a minute, each still holding its houses compact_hold_ms.'),
    ('compact_hold_ms', to_jsonb(200),
     '0414: the longest one compaction transaction should hold its houses, in ms; batches are sized to it (the constant c_hold before 0414: 200). A beat that touches one of those houses waits this long: raising it costs the beat.'),
    ('compact_batch_max', to_jsonb(25),
     '0414: the most houses one compaction transaction cuts (the constant c_bmax before 0414: 25).');
  update public.world_config
     set value = to_jsonb(3),
         description = '0316: public.tick_history deletes stats_city_good rows older than this many days, 20,000 a run. 0 = OFF, nothing is deleted (its value before 0414). Never below 3 days. Nothing reads the old rows (docs/dev-log/2026-11-05-history-graphs.md). 0414: 3, by the owner''s order of 2026-11-14.'
   where key = 'stats_city_good_keep_days' and value = to_jsonb(0);
  update public.world_config
     set value = to_jsonb(26),
         description = '0214: the fine window of public.stats_city_good, the largest table (one row per city per good per slot), in hours; older rows are folded to one an hour. 48 before 0414; 26 since: its readers want the last 24 hours and the row at 24 hours.'
   where key = 'stats_city_good_fine_hours' and value = to_jsonb(48);
  update public.world_config
     set value = to_jsonb(3),
         description = '0097: merchant books (voyages, ledger, events, orders, trade_daily) are compacted past this window, in hours. 6 before 0414; 3 since.'
   where key = 'npc_retention_hours' and value = to_jsonb(6);

  -- ── 3. WHOSE TURN IT IS, AND THE WANTS' GUARD ──
  create function public.drift_ports_due(p_now timestamptz)
  returns table (id uuid, code text)
  language sql stable
  set search_path = public, pg_temp
  as $f$
    -- 0414: THE harbours the drift job steps in the run of p_now's minute: every harbour whose place in the port order (by id) falls on this
    -- minute, one in drift_spread_runs. Over drift_spread_runs consecutive minutes every harbour is given exactly once. 1 (or less): all.
    select x.id, x.code
      from (select po.id, po.code, row_number() over (order by po.id) as k from public.ports po) x
     cross join (select greatest(1, public.wc_int('drift_spread_runs')) as n) s
     where s.n = 1 or x.k % s.n = floor(extract(epoch from p_now) / 60)::bigint % s.n
  $f$;
  revoke all on function public.drift_ports_due(timestamptz) from public, anon, authenticated;

  create function public.city_wants_guard()
  returns trigger
  language plpgsql
  as $f$
  begin
    -- 0414: public.city_wants IS APPEND-ONLY, WITH ONE EXEMPTION: a row of a period older than the keep may be DELETED by the compactor alone
    -- (byeharu.wants_trim is set transaction-locally by public.tick_compact and nowhere else). The period before the current one is read by
    -- the next draw (public.wants_draw), so no setting lets it or the current one go.
    if tg_op = 'DELETE'
       and current_setting('byeharu.wants_trim', true) = 'on'
       and old.period < public.want_period(now()) - 1 then
      return old;
    end if;
    raise exception '% is append-only: % is not permitted', tg_table_name, tg_op
      using errcode = '42501';
  end $f$;
  revoke all on function public.city_wants_guard() from public, anon, authenticated;
  drop trigger city_wants_append_only on public.city_wants;
  create trigger city_wants_append_only before delete or update on public.city_wants
    for each row execute function public.city_wants_guard();

  -- ── 4. THE INDEX NOBODY READS ──
  drop index if exists public.standing_route_laps_closed_at;

  -- ── 5. THE HUNKS ──
  create temp table hunk_0414 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0414 values
  (1, c_cut[1],
$h$     set drift = case when pg.drift_slot < v_slot then greatest(-v_clamp, least(v_clamp,
                   v_theta * pg.drift
                   + v_sigma * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random()))) else pg.drift end,
$h$,
$h$     -- 0414: ONE COMPOUNDED STEP FOR THE SLOTS MISSED. A row k slots behind (the drift job steps one harbour in drift_spread_runs a run; a
     -- skipped harbour; a job that was down) takes theta^k x drift + sigma x sqrt((1 - theta^2k) / (1 - theta^2)) x N(0,1): the law of k
     -- one-slot steps, so a price moves as far in a game day whatever the spread. k = 1 is the step as it always was (theta x drift +
     -- sigma x N). k is read to 10,000 slots: past that the walk has forgotten where it was.
     set drift = case when pg.drift_slot < v_slot then greatest(-v_clamp, least(v_clamp,
                   case when v_slot - pg.drift_slot <= 1 then v_theta
                        else power(v_theta, least(v_slot - pg.drift_slot, 10000)::numeric) end * pg.drift
                   + v_sigma * case when v_slot - pg.drift_slot <= 1 or abs(v_theta) >= 1 then 1
                                    else sqrt((1 - power(v_theta, (2 * least(v_slot - pg.drift_slot, 10000))::numeric)) / (1 - v_theta * v_theta)) end
                     * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random()))) else pg.drift end,
$h$),
  (2, c_cut[2],
$h$  for p in select po.id, po.code from public.ports po order by po.id loop
$h$,
$h$  -- 0414: the harbours whose turn this minute is (public.drift_ports_due: one in drift_spread_runs; the step is compounded over the slots missed)
  for p in select d.id, d.code from public.drift_ports_due(v_now) d order by d.id loop
$h$),
  (3, c_cut[3],
$h$  get diagnostics v_ev = row_count;

  perform set_config('byeharu.npc_compact', 'off', true);
$h$,
$h$  get diagnostics v_ev = row_count;

  -- 0414: A MERCHANT'S LAP HISTORY. A closed lap of one of these houses' routes that is BOTH past the route's newest npc_route_lap_keep AND
  -- closed more than npc_route_lap_keep_hours ago goes, at most compact_trim_rows a batch (the rest at her next visit). What stays is what
  -- the game reads of a merchant's laps: the last 24 hours and the lap before them (public.route_earnings, world.fleet_trades,
  -- public.stats_merchants_window), the newest 20 inside three days (public.npc_share_budget), the newest few. A player's route is not read
  -- here (v_hs holds merchants alone); cmd.standing_route_close_lap keeps standing_route_lap_keep of it, as before. 0 = OFF.
  if public.wc_int('npc_route_lap_keep') > 0 then
    delete from public.standing_route_laps x
     where x.id = any(array(
             select l.id
               from public.standing_routes sr
               join public.standing_route_laps l on l.route_id = sr.id
              where sr.player_id = any(v_hs)
                and l.closed_at is not null
                and l.closed_at < p_now - make_interval(hours => greatest(public.wc_int('npc_route_lap_keep_hours'), 25))
                and l.lap_no <= sr.lap_no - greatest(public.wc_int('npc_route_lap_keep'), 20)
                and l.id is distinct from sr.lap_id
              limit greatest(public.wc_int('compact_trim_rows'), 1)));
  end if;

  perform set_config('byeharu.npc_compact', 'off', true);
$h$),
  (4, c_cut[4],
$h$  c_budget constant interval := interval '8 seconds';   -- the minute's work, at most
  c_hold   constant numeric := 200;                     -- ms: the longest a transaction should hold its houses
  c_bmax   constant int := 25;                          -- houses a transaction, at most
$h$,
$h$  -- 0414: the three limits are knobs, at the values the constants had (8 s, 200 ms, 25)
  c_budget constant interval := make_interval(secs => greatest(public.wc_int('compact_budget_ms'), 1) / 1000.0);   -- the minute's work, at most
  c_hold   constant numeric := greatest(public.wc_int('compact_hold_ms'), 1);   -- ms: the longest a transaction should hold its houses
  c_bmax   constant int := greatest(public.wc_int('compact_batch_max'), 1);     -- houses a transaction, at most
$h$),
  (5, c_cut[4],
$h$  insert into public.compact_runs (slot, at, ms, receipt)
$h$,
$h$  -- 0414: THE CITY WANTS OF PAST PERIODS, oldest first, compact_trim_rows a run. The game reads the current period and the one before
  -- (public.wants_draw, world.city_wants_now, world.want_left); city_wants_keep_periods are kept, never fewer than 2. The table is
  -- append-only: public.city_wants_guard lets this delete through, and no other (byeharu.wants_trim, this transaction only). 0 = OFF.
  if public.wc_int('city_wants_keep_periods') > 0 then
    begin
      perform set_config('byeharu.wants_trim', 'on', true);
      delete from public.city_wants w
       where w.ctid = any(array(select x.ctid from public.city_wants x
                                 where x.period < public.want_period(v_now) - greatest(public.wc_int('city_wants_keep_periods'), 2)
                                 order by x.period
                                 limit greatest(public.wc_int('compact_trim_rows'), 1)));
      perform set_config('byeharu.wants_trim', 'off', true);
    exception when others then
      v_fail := v_fail + 1;
      v_note := coalesce(v_note, 'wants: ' || sqlerrm);
    end;
    if p_commit then commit; end if;
  end if;
  insert into public.compact_runs (slot, at, ms, receipt)
$h$);
  for h in select * from hunk_0414 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0414 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0414 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0414 p where p.fn = h.fn) then
      raise exception '0414 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0414 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0414 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0414 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0414 self-assert FAIL: another function moved';
  end if;
  if public.wc_int('drift_spread_runs') <> 10 or public.wc_int('compact_budget_ms') <> 8000 or public.wc_int('compact_hold_ms') <> 200
     or public.wc_int('compact_batch_max') <> 25 or public.wc_int('npc_route_lap_keep') <> 24 or public.wc_int('npc_route_lap_keep_hours') <> 26
     or public.wc_int('city_wants_keep_periods') <> 10 or public.wc_int('compact_trim_rows') <> 2000 then
    raise exception '0414 self-assert FAIL: the knobs are not this file''s';
  end if;
  if to_regclass('public.standing_route_laps_closed_at') is not null
     or (select p.proname from pg_trigger t join pg_proc p on p.oid = t.tgfoid
          where t.tgrelid = 'public.city_wants'::regclass and t.tgname = 'city_wants_append_only') <> 'city_wants_guard' then
    raise exception '0414 self-assert FAIL: the index stands or the wants'' trigger is not the guard';
  end if;

  -- ── 6. THE STATS COUNT, TWICE AN HOUR (pg_cron only; the schedule alone, its `active` unmoved) ──
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select cron.alter_job(j.jobid, schedule := '6,36 * * * *') from cron.job j
                where j.jobname = 'byeharu-voyage:stats' and j.schedule = '6,21,36,51 * * * *'$q$;
  end if;

  -- ── 7. THE PROBES, each on its own rows, rolled back ──
  -- 7a WHOSE TURN: over drift_spread_runs consecutive minutes every harbour is given exactly once; at 1, every harbour every minute.
  if (select count(*) from (select d.id from generate_series(0, 9) g cross join lateral public.drift_ports_due(now() + make_interval(mins => g)) d) x)
       <> (select count(*) from public.ports)
     or (select count(distinct d.id) from generate_series(0, 9) g cross join lateral public.drift_ports_due(now() + make_interval(mins => g)) d)
       <> (select count(*) from public.ports) then
    raise exception '0414 self-assert FAIL: ten runs in a row do not give every harbour exactly once';
  end if;

  -- 7b THE COMPOUNDED STEP, with the noise put out (sigma 0) so the figure is exact: 3 slots behind, drift 0.1000 -> theta^3 x 0.1; 1 behind -> theta x 0.1.
  select pg.port_id, pg.good_id into v_port, v_good from public.port_goods pg order by pg.port_id, pg.good_id limit 1;
  if v_port is not null then
    begin
      update public.world_config set value = to_jsonb(0) where key = 'drift_sigma';
      update public.world_config set value = to_jsonb(0.9) where key = 'drift_theta';
      v_slot := floor(extract(epoch from now()) / public.wc_num('drift_slot_seconds'))::bigint;
      update public.port_goods set drift = 0.1, drift_slot = v_slot - 3, last_regen_day = world.game_day(now()) where port_id = v_port and good_id = v_good;
      perform public.tick_market_drift(now(), v_port);
      select pg.drift into v_d from public.port_goods pg where pg.port_id = v_port and pg.good_id = v_good;
      if v_d is distinct from 0.0729 then
        raise exception '0414 self-assert FAIL: three slots behind, 0.1000 became % (theta 0.9, no noise: 0.0729)', v_d;
      end if;
      update public.port_goods set drift = 0.1, drift_slot = v_slot - 1 where port_id = v_port and good_id = v_good;
      perform public.tick_market_drift(now(), v_port);
      select pg.drift into v_d from public.port_goods pg where pg.port_id = v_port and pg.good_id = v_good;
      if v_d is distinct from 0.09 then
        raise exception '0414 self-assert FAIL: one slot behind, 0.1000 became % (0.0900)', v_d;
      end if;
      v_note := v_note || 'the step: 0.1000 three slots behind 0.0729, one behind 0.0900 (theta 0.9, no noise)';
      raise exception sqlstate 'BV414';
    exception when sqlstate 'BV414' then null;
    end;
    if v_note not like 'the step:%' then
      raise exception '0414 self-assert FAIL: the step''s probe did not run to its end';
    end if;
  end if;

  -- 7c THE CITY WANTS: probe rows of two periods a million back go by the compactor's own rule (its budget put to 1 ms so it cuts no house);
  --    the rows of the current period and the one before are still there; outside the compactor the table refuses a delete.
  select pg.port_id, pg.good_id into v_port, v_good from public.port_goods pg order by pg.port_id, pg.good_id limit 1;
  if v_port is not null then
    v_period := public.want_period(now());
    select count(*) into v_live from public.city_wants w where w.period >= v_period - 1;
    begin
      update public.world_config set value = to_jsonb(1) where key = 'compact_budget_ms';
      insert into public.city_wants (port_id, good_id, period, mult, cap, nearest_nm, weight)
      values (v_port, v_good, v_period - 1000000, 2, 1, 1, 1), (v_port, v_good, v_period - 1000001, 2, 1, 1, 1);
      begin
        delete from public.city_wants where period = v_period - 1000000;
        raise exception '0414 self-assert FAIL: city_wants let a delete through outside the compactor';
      exception when insufficient_privilege then null;
      end;
      call public.tick_compact(false, false);
      if exists (select 1 from public.city_wants w where w.period in (v_period - 1000000, v_period - 1000001)) then
        raise exception '0414 self-assert FAIL: the compactor left the probe wants of a period a million back (%)',
          (select c.receipt->>'note' from public.compact_runs c order by c.at desc limit 1);
      end if;
      if (select count(*) from public.city_wants w where w.period >= v_period - 1) <> v_live then
        raise exception '0414 self-assert FAIL: the compactor took a want of the current period or the one before';
      end if;
      v_note := v_note || '; the wants: two probe rows a million periods back gone by the compactor, the ' || v_live || ' of now and the period before kept, a delete outside it refused';
      raise exception sqlstate 'BV414';
    exception when sqlstate 'BV414' then null;
    end;
    if v_note not like '%the wants:%' then
      raise exception '0414 self-assert FAIL: the wants'' probe did not run to its end';
    end if;
    if exists (select 1 from public.city_wants w where w.period in (v_period - 1000000, v_period - 1000001)) or public.wc_int('compact_budget_ms') <> 8000 then
      raise exception '0414 self-assert FAIL: the wants'' probe was not rolled back';
    end if;
  end if;

  -- 7d A MERCHANT'S LAPS: on one merchant route, probe laps numbered a million up, compacted AS OF TEN YEARS AGO (v_at), so that none of
  --    the house's real books or laps is before any cut: only the probe laps, dated before v_at, are. Old and past the newest 24: gone. Old
  --    but among the newest 24: kept. Past the newest 24 but closed 20 hours before v_at: kept. The open lap: kept. With the knob at 0: none goes.
  select sr.player_id, sr.id into v_house, v_route
    from public.standing_routes sr join public.players p on p.id = sr.player_id and p.is_npc
   order by sr.id limit 1;
  if v_route is not null then
    begin
      update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
      if not public.npc_traders_on() then
        v_note := v_note || '; the laps: the merchants cannot be lit in this world, not probed';
      else
        v_lapno := 1000100;
        insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at)
        select v_route, 1000000 + g, v_at - interval '40 hours', v_at - case when g = 50 then interval '20 hours' else interval '30 hours' end
          from generate_series(1, 100) g;
        update public.standing_route_laps set closed_at = null where route_id = v_route and lap_no = 1000100;
        update public.standing_routes set lap_no = v_lapno, lap_id = (select l.id from public.standing_route_laps l where l.route_id = v_route and l.lap_no = 1000100) where id = v_route;
        update public.world_config set value = to_jsonb(0) where key = 'npc_route_lap_keep';
        perform public.npc_compact_houses(array[v_house], v_at);
        if (select count(*) from public.standing_route_laps l where l.route_id = v_route and l.lap_no > 1000000) <> 100 then
          raise exception '0414 self-assert FAIL: with npc_route_lap_keep 0 a merchant''s lap went';
        end if;
        update public.world_config set value = to_jsonb(24) where key = 'npc_route_lap_keep';
        perform public.npc_compact_houses(array[v_house], v_at);
        -- laps 1..76 are past the newest 24 (lap_no <= 1000100 - 24) and closed 30 hours ago, but for lap 50 (20 hours): 75 go; 77..100 stay
        select count(*) into v_left from public.standing_route_laps l where l.route_id = v_route and l.lap_no > 1000000;
        if v_left <> 25
           or not exists (select 1 from public.standing_route_laps l where l.route_id = v_route and l.lap_no = 1000050)
           or not exists (select 1 from public.standing_route_laps l where l.route_id = v_route and l.lap_no = 1000077)
           or not exists (select 1 from public.standing_route_laps l where l.route_id = v_route and l.lap_no = 1000100 and l.closed_at is null)
           or exists (select 1 from public.standing_route_laps l where l.route_id = v_route and l.lap_no = 1000076) then
          raise exception '0414 self-assert FAIL: of 100 probe laps % are left (25: the newest 24 and the one closed 20 hours ago)', v_left;
        end if;
        v_note := v_note || '; the laps: of 100 probe laps of one merchant route 75 went and 25 stayed (her newest 24, the open one among them, and one closed 20 hours ago); none at knob 0';
      end if;
      raise exception sqlstate 'BV414';
    exception when sqlstate 'BV414' then null;
    end;
    if v_note not like '%the laps:%' then
      raise exception '0414 self-assert FAIL: the laps'' probe did not run to its end';
    end if;
    if exists (select 1 from public.standing_route_laps l where l.route_id = v_route and l.lap_no > 1000000) or public.wc_int('npc_route_lap_keep') <> 24 then
      raise exception '0414 self-assert FAIL: the laps'' probe was not rolled back';
    end if;
  end if;

  if clock_timestamp() - v_t0 > interval '60 seconds' then
    raise exception '0414 self-assert FAIL: the file took % (budget 60 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0414 self-assert ok: THE WORLD FITS THE HARBOUR IT HAS. Five hunks over four bodies, each once and reversing; grants and volatility unmoved; no other function moved; public.drift_ports_due and public.city_wants_guard; standing_route_laps_closed_at dropped; drift_spread_runs 10, npc_retention_hours %, stats_city_good_keep_days %, stats_city_good_fine_hours %. Probes: %; % ms.',
    public.wc_int('npc_retention_hours'), public.wc_int('stats_city_good_keep_days'), public.wc_int('stats_city_good_fine_hours'),
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
