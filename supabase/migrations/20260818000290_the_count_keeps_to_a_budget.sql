-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0290 — THE COUNT KEEPS TO A BUDGET
--        (the Stats count does at most a fixed amount of work in each of three places; whatever it cannot
--         do carries to the next run, so a missed run can no longer make the next one heavier)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM ─────────────────────────────────────────────────────────────────────────
--   2026-10-31: "STATS NOT WORKING, THINGS ARE GETTING SLOW... FIND THE ROOT, FIX IT. BUT DO NOT CHANGE
--   ANYTHING REGARDING TIME - THE SECONDLY DATA RENEWAL STAYS IN STATS, AND SO ON."
--   2026-11-01: "the game has become slow, especially stats which isn't working properly."
--   So nothing about time moves in this file: not the cron or its schedule, not drift_slot_seconds, not the
--   client's one-second reads, not the journal's one row per change, not world.stats_now().
--
-- ── WHAT IS BROKEN (prod, read-only, 2026-11-01; docs/dev-log/2026-11-01-stats-budget.md §2) ──────
--   The count (public.tick_stats, cron byeharu-voyage:stats, 6,21,36,51 * * * *) has FAILED on every run since
--   2026-10-30 18:21: 92 failed runs in the last 24 h at 118.7 s each (the 120 s statement_timeout), none
--   succeeded. The last good row is stats_world.at 2026-10-30 18:06:00. 0287's indexes (live, valid) did not
--   revive it. Meanwhile public.stats_live_deltas (the live figures' journal) holds ~1.9 M rows (250 MB), grows
--   ~19 rows a second, and world.stats_now() sums all of it on every read. The stats tables carry a primary key
--   and nothing else: stats_city_good 565 k rows (221 MB), stats_good 218 k (69 MB), stats_city 92 k (43 MB),
--   so every range the fold reads is a sequential scan.
--
-- ── WHY IT CANNOT RECOVER BY ITSELF — THE ROOT ──────────────────────────────────────────────────
--   The count is an UNBOUNDED BATCH at three layers, and a failed run rolls everything back, so no layer ever
--   makes progress and each further miss only makes the next run heavier:
--     1. the WINDOW   tick_stats reads where the last SUCCESSFUL row ended, so every flow window is
--                     (last row, now]: now 44 h, and one more run longer each quarter hour.
--     2. the FOLD     stats_compact re-scans [edge - 14 days, edge) of all five tables on every run and keeps no
--                     memory of what it already folded; after an outage every fine row has aged past the fine
--                     edge at once, so the first run must fold the whole backlog in one statement.
--     3. the JOURNAL  stats_live_fold deletes the WHOLE journal in one statement (1.9 M rows).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   Every count run does at most a fixed amount of work in each place; what is left carries to the next run.
--   (1) FIVE KNOBS (no existing knob changes value):
--         stats_max_window_minutes 120   the most one count reads back: window = (max(last row, now - this), now]
--         stats_fold_batch_hours   4     hourly buckets folded per table per run
--         stats_fold_batch_days    1     daily buckets folded per table per run
--         stats_live_batch_rows    300000  journal rows compacted per run while the journal is over this size
--         stats_budget_secs        60    optional work (the fold, the journal compaction) starts only while the
--                                        run has used less than this
--   (2) THE SEAMS, each ONE job, so each bound is provable on its own:
--         public.stats_window_start(prev, now)   THE one rule for how far back a count may read   (STABLE)
--         public.stats_late()                    "this run has used its budget"; nothing else decides lateness
--         public.stats_live_compact(table, n)    replaces n journal-shaped rows by ONE row (their sum)
--         public.stats_fold_marks                how far each stats table is folded, per tier (hour / day)
--   (3) SEVEN INDEXES on the stats tables' `at` and `slot` (plain CREATE INDEX: only the count writes them).
--   (4) THE RE-CUTS — this file SUPERSEDES three function bodies; each is a re-cut of the LIVE body (prod head
--       0289, read with pg_get_functiondef), nothing else moves with them:
--         public.tick_stats       0269's body, three hunks sliced from it (pre-image md5 d2e72eede1406c36a08dc08b99caf604):
--                                 the window start goes through stats_window_start and the span the cap left
--                                 uncounted is kept as `skipped` (the receipt in stats_runs carries it).
--         public.stats_compact    0246's body, re-cut WHOLE (pre-image md5 6ae5bf23fc0fe2ddb848ce9c693a32e3): the same five
--                                 tables, tiers and public.stats_fold calls; each table now folds from its mark by
--                                 at most one batch, day tier first, and starts only while the run has budget.
--                                 stats_fold_back_days stays a knob and is no longer read.
--         public.stats_live_fold  0224's body, ONE hunk at the top (pre-image md5 baa36db2387718e4173c6d8cfcebcc7f): while
--                                 the journal holds more than stats_live_batch_rows rows it is drained in batches
--                                 (the reconcile waits); otherwise the body is the old one, byte for byte.
--   The cap is a no-op when the gap is under it (a healthy count never meets it); the fold is the same fold,
--   in batches; the drain preserves base + journal, which is all world.stats_now() reads.
--
-- ── SAID PLAINLY ────────────────────────────────────────────────────────────────────────────────
--   * The first count after this file records the 44 h it cannot read as `skipped` {from, to} and counts the last
--     120 minutes. `period` (the money flows by kind) is a difference of two `recent` maps and stays exact; the
--     trades (sold, bought, units, trades) of the skipped span are not counted into that one row.
--   * THE FIRST MARK. A table with no mark starts at the bucket the old unbounded fold had reached at the last
--     count before this one: bucket(that count's `at` - the tier's window) less one bucket. The one bucket of slack
--     is harmless because public.stats_fold is idempotent. "The last count before this one" is the newest
--     stats_world row BEFORE p_now: tick_stats has already written this run's own row when it calls stats_compact.
--   * The journal is drained 300000 rows a run: ~7 runs (~1.75 h) for the backlog, after which the reconcile runs.
--     world.stats_now() stays right throughout (base + sum of the journal, and the compaction keeps the sum).
--   * A count can still miss if its mandatory work alone exceeds 120 s; the budget bounds the OPTIONAL work.
--
-- ── SELF-ASSERT (probe rows only, in rolled-back sub-transactions; no probe counts, sums or locks a table that ──
--    grows on prod: the journal is read only by a limit-2 test and a one-row compaction, the stats tables only
--    in 2004 or in the far future)
--   (a) as found: knobs and defaults, no existing knob moved; the marks table (RLS, no client grant, primary key,
--       its check bites); the seven indexes from pg_index (table, columns, predicate; never a planner's choice); the
--       new functions' ACL and volatility; every hunk reverses to its pre-image; EVERY OTHER function in
--       public/cmd/world/voyage md5-unmoved (exactly the three re-cuts differ, exactly three are new); the registry
--       and the walls as found.
--   (b) the cap: stats_window_start by explicit instants; then THE COUNT END TO END, once, at an instant 40 days
--       ahead (so its windows are empty and its cost is its fixed phases): over five hours of gap `since` is the
--       cap and `skipped` is {from, to}; the receipt keeps it; and the live body cut right after the cap, asked 15
--       minutes after that count, skips nothing (`skipped` null).
--   (c) the fold: the first mark, from the last count BEFORE this one; one batch a call, the mark moving by exactly
--       the batch, never past the edge, the day edge lifting the hour tier; a last call folding nothing; and the
--       lateness test (stats_budget_secs set to 0 inside the probe) removing nothing and leaving every mark.
--   (d) the journal: stats_live_compact on a TEMP table of the journal's shape (the sum of every column unchanged,
--       the count n - p_rows + 1, the returned number right); stats_live_fold with stats_live_batch_rows 1 drains
--       (draining, folded 0, stats_live untouched), and waits when it is late.
-- ROLLBACK (forward): drop the seven indexes; re-create tick_stats and stats_live_fold by reversing the hunks (each
--   OLD text is in this file, verbatim) and stats_compact from 0246 (its body, lines 302-350); drop the three
--   functions, the marks table and the five knobs. Nothing else was written.
-- DEPLOY: the seven CREATE INDEX statements take SHARE locks on stats_good / stats_city / stats_city_good until the
--   commit; only the count writes them, and its own lock_timeout (2 s) fails the one run that overlaps. This file's
--   lock_timeout is 5 s: if the count holds those tables when it starts, it fails cleanly; push again after the run
--   (the count runs at :06 :21 :36 :51 and takes up to 120 s).
-- VERSION: 0290 (prod head 0289, read-only 2026-11-01); deploys AFTER 0289, one migration at a time.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.tick_stats(timestamptz)') is null
     or to_regprocedure('public.stats_compact(timestamptz)') is null
     or to_regprocedure('public.stats_fold(text,text,timestamptz,timestamptz)') is null
     or to_regprocedure('public.stats_fold_day(bigint)') is null
     or to_regprocedure('public.stats_live_fold(timestamptz,boolean)') is null
     or to_regclass('public.stats_runs') is null
     or to_regclass('public.stats_live_deltas') is null then
    raise exception '0290 refuses: 0224 / 0232 / 0246 / 0269 (the count, its fold and its journal) are not in this world';
  end if;
  if to_regclass('public.stats_fold_marks') is not null
     or to_regprocedure('public.stats_window_start(timestamptz,timestamptz)') is not null
     or to_regprocedure('public.stats_late()') is not null
     or to_regprocedure('public.stats_live_compact(regclass,bigint)') is not null
     or to_regclass('public.stats_good_at') is not null
     or exists (select 1 from public.world_config
                 where key in ('stats_max_window_minutes', 'stats_fold_batch_hours', 'stats_fold_batch_days',
                               'stats_live_batch_rows', 'stats_budget_secs')) then
    raise exception '0290 refuses: it has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0290(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0290 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_stats(timestamptz)'),
               ('public.stats_compact(timestamptz)'),
               ('public.stats_live_fold(timestamptz,boolean)')) f(fn);

-- every function in the four schemas, by its own md5: the proof that EVERY OTHER function is unmoved
create temp table fns_before_0290 on commit drop as
select p.oid::regprocedure::text as fn,
       md5(replace(pg_get_functiondef(p.oid), E'\r', '')) as md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');

create temp table before_0290 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select value from public.world_config where key = 'economy_closed') as economy_closed,
       (select value from public.world_config where key = 'city_treasury_enabled') as city_treasury_enabled,
       (select md5(string_agg(c.key || '=' || c.value::text, ',' order by c.key)) from public.world_config c) as knobs_md5;

-- ── 1. THE FIVE KNOBS ───────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('stats_max_window_minutes', to_jsonb(120),
   '0290: the most one count reads back. A count''s flow window is (max(the last row''s at, now - this), now]; a count that missed runs reads this much and records the rest as `skipped` in its receipt (public.stats_runs), instead of one window that grows with every miss. Read by public.stats_window_start.'),
  ('stats_fold_batch_hours', to_jsonb(4),
   '0290: the hourly buckets public.stats_compact folds per table per run; what is left carries to the next run (public.stats_fold_marks).'),
  ('stats_fold_batch_days', to_jsonb(1),
   '0290: the daily buckets public.stats_compact folds per table per run; what is left carries to the next run (public.stats_fold_marks).'),
  ('stats_live_batch_rows', to_jsonb(300000),
   '0290: the journal rows public.stats_live_fold compacts into one row per run while public.stats_live_deltas holds more than this; the full reconcile waits until the journal is this size or less.'),
  ('stats_budget_secs', to_jsonb(60),
   '0290: optional work (the fold, the journal compaction) starts only while the count has used less than this many seconds of its run (public.stats_late). The statement_timeout is 120 s.')
on conflict (key) do nothing;

-- ── 2. THE SEAMS ────────────────────────────────────────────────────────────────────────────────
create function public.stats_window_start(p_prev timestamptz, p_now timestamptz)
returns timestamptz
language sql
stable
set search_path = public, pg_temp
as $$
  -- 0290: THE ONE RULE for how far back a count may read: where the last count ended, but never further back than
  -- stats_max_window_minutes. Called by public.tick_stats alone.
  select greatest(p_prev, p_now - make_interval(mins => public.wc_int('stats_max_window_minutes')))
$$;
comment on function public.stats_window_start(timestamptz, timestamptz) is
  '0290: the instant a count''s flow window starts: greatest(the last count''s at, p_now - stats_max_window_minutes). Server-only; called by public.tick_stats.';

create function public.stats_late()
returns boolean
language sql
volatile
set search_path = public, pg_temp
as $$
  -- 0290: "this run has used its budget": the time since the running statement began (the cron's one select) is at
  -- least stats_budget_secs. Used by public.stats_compact and by the journal drain in public.stats_live_fold; nothing
  -- else decides lateness. VOLATILE: it reads the clock.
  select clock_timestamp() - statement_timestamp() >= make_interval(secs => public.wc_num('stats_budget_secs')::double precision)
$$;
comment on function public.stats_late() is
  '0290: true once the running statement has used stats_budget_secs. Optional work (the fold, the journal drain) starts only while it is false. Server-only.';

create function public.stats_live_compact(p_tbl regclass, p_rows bigint)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- 0290: replace p_rows rows of a journal-shaped table (the first a scan finds, by ctid) with ONE row: `at` their newest,
-- every figure their sum. The table's sum is unchanged by construction. Returns how many rows it replaced (0 when
-- p_rows < 1 or the table is empty). One statement, so the delete and the insert share a snapshot. Called by
-- public.stats_live_fold on public.stats_live_deltas; the self-assert calls it on a TEMP table of the same shape.
declare
  v_n bigint;
begin
  if p_rows is null or p_rows < 1 then
    return 0;
  end if;
  execute format($q$
    with d as (
      delete from %1$s where ctid = any(array(select ctid from %1$s limit %2$s)) returning *
    ), s as (
      select count(*) as n, max(at) as at,
             sum(players) as players, sum(merchants) as merchants, sum(cities) as cities, sum(set_aside) as set_aside,
             sum(at_sea) as at_sea, sum(at_sea_merchants) as at_sea_merchants,
             sum(trades) as trades, sum(units) as units, sum(sold) as sold, sum(bought) as bought
        from d
    ), i as (
      insert into %1$s (at, players, merchants, cities, set_aside, at_sea, at_sea_merchants, trades, units, sold, bought)
      select at, players, merchants, cities, set_aside, at_sea, at_sea_merchants, trades, units, sold, bought from s where n > 0
    )
    select n from s $q$, p_tbl, p_rows) into v_n;
  return v_n;
end $fn$;
comment on function public.stats_live_compact(regclass, bigint) is
  '0290: replaces p_rows rows of a journal-shaped table with ONE row (at = their newest, every figure = their sum) and returns how many it replaced. The table''s sum is unchanged. Server-only; called by public.stats_live_fold.';

create table public.stats_fold_marks (
  tbl     text        not null,
  unit    text        not null check (unit in ('hour', 'day')),
  through timestamptz not null,
  primary key (tbl, unit)
);
comment on table public.stats_fold_marks is
  '0290: how far each stats table is folded, per tier: `through` is the exclusive upper edge of what public.stats_compact has folded at that tier (hour or day). One writer: public.stats_compact, in the same transaction as the fold, so a count that fails rolls its marks back with it. A table with no mark starts where the last count before the running one had got to. Server-only.';
alter table public.stats_fold_marks enable row level security;
revoke all on table public.stats_fold_marks from public, anon, authenticated;

revoke all on function public.stats_window_start(timestamptz, timestamptz), public.stats_late(),
                       public.stats_live_compact(regclass, bigint) from public, anon, authenticated;

-- ── 3. THE SEVEN INDEXES (stats_fold reads [lo, hi) by `at`; stats_fold_day reads and clears by `slot`) ─────
create index stats_good_at on public.stats_good (at);
create index stats_good_slot on public.stats_good (slot);
create index stats_good_day on public.stats_good (slot) where day is not null;
create index stats_city_at on public.stats_city (at);
create index stats_city_slot on public.stats_city (slot);
create index stats_city_day on public.stats_city (slot) where day is not null;
create index stats_city_good_at on public.stats_city_good (at);
comment on index public.stats_good_at is '0290: public.stats_fold''s range [lo, hi) by `at`; the table had a primary key (good_id, slot) and nothing else.';
comment on index public.stats_good_slot is '0290: public.stats_fold_day''s 24 h range by `slot` (the primary key leads with good_id).';
comment on index public.stats_good_day is '0290: the one slot that carries `day` (public.stats_fold_day clears the older ones): ~565 rows, not the table.';
comment on index public.stats_city_at is '0290: public.stats_fold''s range [lo, hi) by `at`; the table had a primary key (port_id, slot) and nothing else.';
comment on index public.stats_city_slot is '0290: public.stats_fold_day''s 24 h range by `slot` (the primary key leads with port_id).';
comment on index public.stats_city_day is '0290: the one slot that carries `day` (public.stats_fold_day clears the older ones): ~214 rows, not the table.';
comment on index public.stats_city_good_at is '0290: public.stats_fold''s range [lo, hi) by `at`; the largest stats table (565 k rows) had a primary key (port_id, good_id, slot) and nothing else.';

-- ── 4. THE HUNKS (tick_stats ×3, stats_live_fold ×1) — each occurs exactly once in the LIVE body ────────
create temp table hunks_0290 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0290 (fn, n, old, new) values
-- ·· tick_stats: the two locals
('public.tick_stats(timestamptz)', 1,
$h$  v_prev_at   timestamptz;
  v_prev_rec  jsonb;
$h$,
$h$  v_prev_at   timestamptz;
  v_prev_rec  jsonb;
  v_start     timestamptz;   -- 0290: where this count's window may start (public.stats_window_start)
  v_skip      jsonb;         -- 0290: the span the cap left uncounted {from, to}, or null (the receipt's `skipped`)
$h$),
-- ·· tick_stats: the window has a ceiling
('public.tick_stats(timestamptz)', 2,
$h$  v_prev_at := coalesce(v_prev_at, p_now - make_interval(secs => v_secs::double precision));
$h$,
$h$  v_prev_at := coalesce(v_prev_at, p_now - make_interval(secs => v_secs::double precision));
  -- 0290: THE WINDOW HAS A CEILING (stats_max_window_minutes). A count that missed runs reads at most that far back; the
  -- span it leaves uncounted is written down (`skipped`) instead of being read in one statement that grows with every miss.
  v_start := public.stats_window_start(v_prev_at, p_now);
  if v_start > v_prev_at then
    v_skip := jsonb_build_object('from', v_prev_at, 'to', v_start);
    v_prev_at := v_start;
  end if;
$h$),
-- ·· tick_stats: the return (and so the receipt) carries what the cap left
('public.tick_stats(timestamptz)', 3,
$h$                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x, 'fold', v_fold,
$h$,
$h$                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x, 'fold', v_fold,
                            'skipped', v_skip,   -- 0290: what the window cap left uncounted {from, to}; null when it left nothing
$h$),
-- ·· stats_live_fold: the journal is drained in batches, not deleted whole
('public.stats_live_fold(timestamptz,boolean)', 1,
$h$  r record;
begin
  with d as (
$h$,
$h$  r record;
  v_batch bigint := public.wc_int('stats_live_batch_rows');   -- 0290: the most journal rows one count compacts
begin
  -- 0290: THE JOURNAL IS DRAINED IN BATCHES, NOT DELETED WHOLE. While it holds more than v_batch rows (the test stops after
  -- v_batch + 1: it never counts a backlog) the full reconcile below waits, and this count only compacts v_batch rows into
  -- ONE row (their sum, public.stats_live_compact: base + journal, which world.stats_now() reads, is unchanged), and only
  -- while it has budget left (public.stats_late). Once the journal is v_batch rows or fewer the reconcile runs as it did.
  if (select count(*) from (select 1 from public.stats_live_deltas limit v_batch + 1) j) > v_batch then
    select l.drift, l.counted_through, l.counted_at into r from public.stats_live l;
    return jsonb_build_object('drift', r.drift, 'folded', 0, 'through', r.counted_through, 'at', r.counted_at,
                              'draining', true,
                              'compacted', case when public.stats_late() then 0
                                                else public.stats_live_compact('public.stats_live_deltas', v_batch) end);
  end if;
  with d as (
$h$);

do $apply$
declare
  d     record;
  h     record;
  v_def text;
  v_n   int;
begin
  for d in select * from defs_before_0290 where fn in ('public.tick_stats(timestamptz)', 'public.stats_live_fold(timestamptz,boolean)') order by fn loop
    v_def := d.def;
    for h in select * from hunks_0290 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0290(v_def, h.old);
      if v_n <> 1 then
        raise exception '0290 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $apply$;

-- ── 5. stats_compact, RE-CUT WHOLE (0246's tiers and public.stats_fold calls, now in batches from a mark) ──────
create or replace function public.stats_compact(p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- 0290: the stats tables' retention, in batches (0246's body, re-cut whole). Per table: the fine window -> HOURLY rows -> DAILY
-- rows kept for ever (stats_world and stats_merchants stay hourly for ever). Each tier folds from its MARK (public.stats_fold_marks)
-- by at most one batch (stats_fold_batch_days / stats_fold_batch_hours) and never past its edge, day tier first (the hour tier
-- then starts above the day edge). The mark moves in this transaction, so a failed count rolls it back with the fold. A table with
-- no mark starts where the last count BEFORE this one had got: bucket(that count's `at` - the tier's window) less one bucket.
-- Starts only while the run has budget (public.stats_late). Returns the rows removed, per table, and ms (+ late when it did not start).
-- All arithmetic in HOURS (make_interval(hours => ...)), so a bucket edge never meets a DST shift. stats_fold_back_days is no longer read.
declare
  v_t0     timestamptz := clock_timestamp();
  v_bh     interval := make_interval(hours => public.wc_int('stats_fold_batch_hours'));
  v_bd     interval := make_interval(hours => 24 * public.wc_int('stats_fold_batch_days'));
  v_last   timestamptz := coalesce((select max(w.at) from public.stats_world w where w.at < p_now), p_now);   -- the count BEFORE this one
  t        record;
  v_h_hi   timestamptz; v_d_hi timestamptz;
  v_lo     timestamptz; v_hi timestamptz;
  v_r      jsonb;
  v_out    jsonb := '{}'::jsonb;
  v_rm     bigint := 0;
  v_tbl    bigint;
begin
  if public.stats_late() then
    return jsonb_build_object('removed', 0, 'tables', '{}'::jsonb, 'late', true, 'ms', 0);
  end if;
  for t in
    select x.tbl, x.fine, x.hour
      from (values ('stats_world',     make_interval(hours => public.wc_int('stats_fine_hours')), null::interval),
                   ('stats_merchants', make_interval(hours => public.wc_int('stats_fine_hours')), null::interval),
                   ('stats_good',      make_interval(hours => public.wc_int('stats_fine_hours')), make_interval(hours => 24 * public.wc_int('stats_hour_days'))),
                   ('stats_city',      make_interval(hours => public.wc_int('stats_fine_hours')), make_interval(hours => 24 * public.wc_int('stats_hour_days'))),
                   ('stats_city_good', make_interval(hours => public.wc_int('stats_city_good_fine_hours')), make_interval(hours => 24 * public.wc_int('stats_city_good_hour_days')))
           ) x(tbl, fine, hour)
  loop
    v_tbl := 0;
    v_h_hi := public.stats_bucket(p_now - t.fine, 'hour');
    if t.hour is not null then
      if t.hour <= t.fine then
        raise exception '0290 stats_compact: the hourly window of % (%) must exceed its fine window (%)', t.tbl, t.hour, t.fine;
      end if;
      v_d_hi := public.stats_bucket(p_now - t.hour, 'day');
      v_lo := coalesce((select m.through from public.stats_fold_marks m where m.tbl = t.tbl and m.unit = 'day'),
                       public.stats_bucket(v_last - t.hour, 'day') - make_interval(hours => 24));
      v_hi := least(v_d_hi, v_lo + v_bd);
      if v_hi > v_lo then
        v_r := public.stats_fold(t.tbl, 'day', v_lo, v_hi);
        v_tbl := v_tbl + (v_r->>'removed')::bigint;
        insert into public.stats_fold_marks (tbl, unit, through) values (t.tbl, 'day', v_hi)
          on conflict (tbl, unit) do update set through = excluded.through;
      end if;
    end if;
    v_lo := coalesce((select m.through from public.stats_fold_marks m where m.tbl = t.tbl and m.unit = 'hour'),
                     public.stats_bucket(v_last - t.fine, 'hour') - make_interval(hours => 1));
    if t.hour is not null then
      v_lo := greatest(v_lo, v_d_hi);   -- the hour tier lives above the day edge
    end if;
    v_hi := least(v_h_hi, v_lo + v_bh);
    if v_hi > v_lo then
      v_r := public.stats_fold(t.tbl, 'hour', v_lo, v_hi);
      v_tbl := v_tbl + (v_r->>'removed')::bigint;
      insert into public.stats_fold_marks (tbl, unit, through) values (t.tbl, 'hour', v_hi)
        on conflict (tbl, unit) do update set through = excluded.through;
    end if;
    v_rm := v_rm + v_tbl;
    v_out := v_out || jsonb_build_object(t.tbl, v_tbl);
  end loop;
  return jsonb_build_object('removed', v_rm, 'tables', v_out,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $fn$;
comment on function public.stats_compact(timestamptz) is
  '0246, re-cut by 0290: the stats tables'' retention - fine -> hourly -> daily, by fold, in batches from a mark (public.stats_fold_marks), only while the run has budget (public.stats_late). Called by tick_stats on every count.';

-- ── 6. THE SELF-ASSERT: (a) AS FOUND — the catalog, the hunks, every other function ──────────────────────
do $assert_a$
declare
  d      record;
  h      record;
  x      record;
  pr     record;
  v_def  text;
  v_n    int;
  v_diff text[];
begin
  -- the five knobs, with their defaults; no existing knob moved
  if public.wc_int('stats_max_window_minutes') <> 120 or public.wc_int('stats_fold_batch_hours') <> 4
     or public.wc_int('stats_fold_batch_days') <> 1 or public.wc_int('stats_live_batch_rows') <> 300000
     or public.wc_num('stats_budget_secs') <> 60 then
    raise exception '0290 self-assert FAIL: the five knobs are not 120 / 4 / 1 / 300000 / 60';
  end if;
  if (select count(*) from public.world_config where key in ('stats_max_window_minutes', 'stats_fold_batch_hours', 'stats_fold_batch_days',
                                                              'stats_live_batch_rows', 'stats_budget_secs')
                                                and description is not null and btrim(description) <> '') <> 5 then
    raise exception '0290 self-assert FAIL: a new knob has no description';
  end if;
  if (select md5(string_agg(c.key || '=' || c.value::text, ',' order by c.key)) from public.world_config c
       where c.key not in ('stats_max_window_minutes', 'stats_fold_batch_hours', 'stats_fold_batch_days', 'stats_live_batch_rows', 'stats_budget_secs'))
     is distinct from (select knobs_md5 from before_0290) then
    raise exception '0290 self-assert FAIL: an existing knob moved';
  end if;

  -- the marks table: server-only, keyed (tbl, unit), and its check bites
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.stats_fold_marks'::regclass)
     or has_table_privilege('anon', 'public.stats_fold_marks', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.stats_fold_marks', 'select,insert,update,delete') then
    raise exception '0290 self-assert FAIL: stats_fold_marks is not server-only (RLS on, no client privilege)';
  end if;
  if (select array_agg(a.attname::text order by u.ord)
        from pg_index i
        cross join lateral unnest(string_to_array(i.indkey::text, ' ')::int2[]) with ordinality u(attnum, ord)
        join pg_attribute a on a.attrelid = i.indrelid and a.attnum = u.attnum
       where i.indrelid = 'public.stats_fold_marks'::regclass and i.indisprimary) is distinct from array['tbl', 'unit'] then
    raise exception '0290 self-assert FAIL: stats_fold_marks is not keyed (tbl, unit)';
  end if;
  begin
    insert into public.stats_fold_marks (tbl, unit, through) values ('stats_world', 'week', now());
    raise exception '0290 self-assert FAIL: stats_fold_marks took a unit that is not hour or day';
  exception when check_violation then
    null;
  end;

  -- the seven indexes, from the catalog (table, key column, predicate): valid, ready, live, one btree key, no INCLUDE, not unique
  for x in select * from (values
      ('stats_good_at',      'stats_good',      'at',   false),
      ('stats_good_slot',    'stats_good',      'slot', false),
      ('stats_good_day',     'stats_good',      'slot', true),
      ('stats_city_at',      'stats_city',      'at',   false),
      ('stats_city_slot',    'stats_city',      'slot', false),
      ('stats_city_day',     'stats_city',      'slot', true),
      ('stats_city_good_at', 'stats_city_good', 'at',   false)) v(ix, tbl, col, partial)
  loop
    select i.indrelid, i.indisvalid, i.indisready, i.indislive, i.indisunique, i.indnatts, i.indnkeyatts,
           (select array_agg(a.attname::text order by u.ord)
              from unnest(string_to_array(i.indkey::text, ' ')::int2[]) with ordinality u(attnum, ord)
              join pg_attribute a on a.attrelid = i.indrelid and a.attnum = u.attnum) as cols,
           pg_get_expr(i.indpred, i.indrelid) as pred,
           (select am.amname from pg_class ic join pg_am am on am.oid = ic.relam where ic.oid = i.indexrelid) as am
      into pr
      from pg_index i where i.indexrelid = to_regclass('public.' || x.ix);
    if not found or pr.indrelid <> ('public.' || x.tbl)::regclass
       or not pr.indisvalid or not pr.indisready or not pr.indislive or pr.indisunique
       or pr.indnatts <> 1 or pr.indnkeyatts <> 1 or pr.cols is distinct from array[x.col] or pr.am <> 'btree'
       or (x.partial and (pr.pred is null or pr.pred not like '%day IS NOT NULL%'))
       or (not x.partial and pr.pred is not null) then
      raise exception '0290 self-assert FAIL: index % is not % (%) % — found %', x.ix, x.tbl, x.col,
        case when x.partial then 'WHERE day IS NOT NULL' else '(whole table)' end, pg_get_indexdef(to_regclass('public.' || x.ix));
    end if;
  end loop;

  -- the new functions: server-only, and the volatility the seams are for
  for x in select * from (values
      ('public.stats_window_start(timestamptz,timestamptz)', 's', false),
      ('public.stats_late()',                                'v', false),
      ('public.stats_live_compact(regclass,bigint)',         'v', true)) v(fn, vol, secdef)
  loop
    select p.oid, p.provolatile, p.prosecdef into pr from pg_proc p where p.oid = to_regprocedure(x.fn);
    if not found or pr.provolatile <> x.vol or pr.prosecdef <> x.secdef
       or has_function_privilege('anon', pr.oid, 'execute') or has_function_privilege('authenticated', pr.oid, 'execute') then
      raise exception '0290 self-assert FAIL: % is not server-only with volatility % (definer %)', x.fn, x.vol, x.secdef;
    end if;
  end loop;

  -- the hunks reverse to the live pre-images; ACL / volatility / definer / config of the three re-cuts as found
  for d in select * from defs_before_0290 order by fn loop
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into pr from pg_proc p where p.oid = d.fn::regprocedure;
    if pr.acl <> d.acl or pr.vol <> d.vol or pr.secdef <> d.secdef or pr.cfg <> d.cfg then
      raise exception '0290 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
    if d.fn = 'public.stats_compact(timestamptz)' then
      continue;   -- re-cut whole by this file (no hunks to reverse); that it moved, and nothing else did, is asserted below
    end if;
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0290 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0290(v_def, h.new) <> 1 then
        raise exception '0290 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0290 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
  end loop;
  v_def := replace(pg_get_functiondef('public.stats_compact(timestamptz)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0290(v_def, 'public.stats_late()') <> 1 or pg_temp.occurs_0290(v_def, 'public.stats_fold(t.tbl,') <> 2
     or pg_temp.occurs_0290(v_def, 'stats_fold_back_days') <> 1 then   -- the one mention is the comment saying it is no longer read
    raise exception '0290 self-assert FAIL: stats_compact is not the re-cut body (one lateness test, one fold call per tier)';
  end if;

  -- EVERY OTHER FUNCTION in public / cmd / world / voyage is md5-unmoved: exactly the three re-cuts differ, exactly three are new
  select array_agg(q.fn order by q.fn) into v_diff
    from (select coalesce(a.fn, b.fn) as fn
            from (select p.oid::regprocedure::text as fn, md5(replace(pg_get_functiondef(p.oid), E'\r', '')) as md5
                    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) a
            full join fns_before_0290 b on b.fn = a.fn
           where a.md5 is distinct from b.md5) q;
  if v_diff is distinct from (select array_agg(e order by e) from unnest(array[
        to_regprocedure('public.tick_stats(timestamptz)')::text, to_regprocedure('public.stats_compact(timestamptz)')::text,
        to_regprocedure('public.stats_live_fold(timestamptz,boolean)')::text, to_regprocedure('public.stats_window_start(timestamptz,timestamptz)')::text,
        to_regprocedure('public.stats_late()')::text, to_regprocedure('public.stats_live_compact(regclass,bigint)')::text]) e) then
    raise exception '0290 self-assert FAIL: the functions that moved or appeared are %, not exactly the three re-cuts and the three new seams', v_diff;
  end if;
  select count(*) into v_n from fns_before_0290;

  -- the registry and the walls and both owner switches as found
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0290)
     or (select value from public.world_config where key = 'economy_closed') is distinct from (select economy_closed from before_0290)
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from (select city_treasury_enabled from before_0290) then
    raise exception '0290 self-assert FAIL: the registry or an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0290 self-assert FAIL: a wall moved';
  end if;

  raise notice '0290 self-assert ok: (a)  AS FOUND. The five knobs read 120 / 4 / 1 / 300000 / 60 and every other knob is unmoved; stats_fold_marks is server-only (RLS, no client privilege), keyed (tbl, unit), its unit check bites; the seven indexes are valid, ready, live, one btree key, on their table and column, the two day indexes partial on day IS NOT NULL (read from pg_index, never a planner''s choice); the three seams are server-only (stats_window_start STABLE, stats_late and stats_live_compact VOLATILE); the four hunks reverse to their pre-images and the three re-cuts keep their ACL, volatility, definer and config; EVERY OTHER function in public/cmd/world/voyage is md5-unmoved (% functions: exactly tick_stats, stats_compact, stats_live_fold differ, exactly three are new); registry % unchanged; walls 0 / 0 / 0; both owner switches as found.',
    v_n, (select entry_points from before_0290);
end $assert_a$;

-- ── 7. (b) THE CAP, AND THE COUNT END TO END ─────────────────────────────────────────────────────
-- Helpers for the probes. The probes pin the knobs they depend on (rolled back with the probe), plant rows only in 2004 or in the far
-- future, and never look at a growing table's contents.
create function pg_temp.pin_0290()
returns void
language plpgsql
as $$
declare
  v_n int;
begin
  update public.world_config w set value = v.val
    from (values ('stats_fine_hours', to_jsonb(72)), ('stats_city_good_fine_hours', to_jsonb(48)),
                 ('stats_hour_days', to_jsonb(30)), ('stats_city_good_hour_days', to_jsonb(7)),
                 ('stats_fold_batch_hours', to_jsonb(4)), ('stats_fold_batch_days', to_jsonb(1)),
                 ('stats_budget_secs', to_jsonb(86400)), ('stats_max_window_minutes', to_jsonb(120))) v(key, val)
   where w.key = v.key;
  get diagnostics v_n = row_count;
  if v_n <> 8 then
    raise exception '0290 self-assert FAIL: the probe could not pin its eight knobs (%)', v_n;
  end if;
end $$;

-- the eight marks, one line: 'stats_city/day=2004-08-02 00:00, ...' (UTC, by table then unit, collation-free)
create function pg_temp.marks_0290()
returns text
language sql
as $$ select coalesce(string_agg(m.tbl || '/' || m.unit || '=' || to_char(m.through at time zone 'UTC', 'YYYY-MM-DD HH24:MI'), ', '
                                 order by m.tbl collate "C", m.unit collate "C"), '(none)') from public.stats_fold_marks m $$;

create function pg_temp.mark_0290(p_tbl text, p_unit text)
returns timestamptz
language sql
as $$ select m.through from public.stats_fold_marks m where m.tbl = p_tbl and m.unit = p_unit $$;

create function pg_temp.plant_marks_0290(p_at timestamptz)
returns void
language sql
as $$ insert into public.stats_fold_marks (tbl, unit, through)
      select t.tbl, u.unit, p_at
        from (values ('stats_world'), ('stats_merchants'), ('stats_good'), ('stats_city'), ('stats_city_good')) t(tbl),
             (values ('hour'), ('day')) u(unit)
       where u.unit = 'hour' or t.tbl in ('stats_good', 'stats_city', 'stats_city_good') $$;

do $probe_b$
declare
  c_now  constant timestamptz := '2004-06-01 12:00:00+00';
  v_p1   timestamptz := now() + interval '40 days';   -- an instant no real row is near: every window of the count is empty
  v_p2   timestamptz := now() + interval '40 days' + interval '15 minutes';
  v_run1 jsonb;
  v_run2 jsonb;
  v_info jsonb;
  v_t0   timestamptz;
  v_ms1  numeric;
  v_cap  text;
  v_cut  text;
begin
  -- the cap, by explicit instants: under it unchanged, at it unchanged, over it capped; and it reads its knob
  if public.stats_window_start(c_now - interval '30 minutes', c_now) <> c_now - interval '30 minutes'
     or public.stats_window_start(c_now - interval '120 minutes', c_now) <> c_now - interval '120 minutes'
     or public.stats_window_start(c_now - interval '43 hours', c_now) <> c_now - interval '120 minutes' then
    raise exception '0290 self-assert FAIL: stats_window_start does not leave a gap of 30 / 120 minutes alone and cap a gap of 43 hours at 120 minutes';
  end if;
  begin
    update public.world_config set value = to_jsonb(60) where key = 'stats_max_window_minutes';
    if public.stats_window_start(c_now - interval '90 minutes', c_now) <> c_now - interval '60 minutes' then
      raise exception '0290 self-assert FAIL: stats_window_start does not read stats_max_window_minutes';
    end if;
    raise exception using errcode = 'ZX290', message = 'rollback';
  exception when sqlstate 'ZX290' then
    null;
  end;
  if public.wc_int('stats_max_window_minutes') <> 120 then
    raise exception '0290 self-assert FAIL: the cap probe left the knob moved';
  end if;

  -- THE COUNT END TO END, once. A far-future instant: the capped window and the 24 h laps window are empty, the marks are the
  -- probe's (2004) so the fold touches nothing real, the journal batch is 1 (a limit-2 test and a one-row compaction at most);
  -- what is left is the count's fixed phases. (A second whole count would cost as much again, so the under-the-cap case below is
  -- the same live body cut right after the cap.)
  if exists (select 1 from public.stats_world w where w.at >= v_p1 - interval '1 day')
     or exists (select 1 from public.stats_runs r where r.at >= v_p1 - interval '1 day') then
    raise exception '0290 self-assert FAIL: a count already sits at the end-to-end probe''s instant';
  end if;
  begin
    perform pg_temp.pin_0290();
    update public.world_config set value = to_jsonb(1) where key = 'stats_live_batch_rows';
    perform pg_temp.plant_marks_0290('2004-01-01 00:00:00+00');
    -- the count before: five hours earlier
    insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside, minted, removed, moved,
                                    sold, bought, units, trades, period, recent, n)
    values (public.drift_slot_of(v_p1 - interval '5 hours'), v_p1 - interval '5 hours', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            '{}'::jsonb, '{}'::jsonb, 1);

    v_t0 := clock_timestamp();
    v_run1 := public.tick_stats(v_p1);
    v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
    if v_run1->>'note' is not null or (v_run1->>'since')::timestamptz is distinct from v_p1 - interval '120 minutes'
       or (v_run1->'skipped'->>'from')::timestamptz is distinct from v_p1 - interval '5 hours'
       or (v_run1->'skipped'->>'to')::timestamptz is distinct from v_p1 - interval '120 minutes' then
      raise exception '0290 self-assert FAIL: five hours after the last count the count read since % and skipped %, not the cap {% .. %}',
        v_run1->>'since', v_run1->'skipped', v_p1 - interval '5 hours', v_p1 - interval '120 minutes';
    end if;
    if (select r.receipt->'skipped' from public.stats_runs r where r.at = v_p1) is distinct from v_run1->'skipped' then
      raise exception '0290 self-assert FAIL: the count''s receipt (stats_runs) does not carry what it skipped';
    end if;
    if v_run1->'fold' ? 'late' or (v_run1->'fold'->>'removed') is null then
      raise exception '0290 self-assert FAIL: the end-to-end count''s fold was late, or reported nothing: %', v_run1->'fold';
    end if;
    -- the fold ran by one batch from the planted marks, through stats_compact
    if pg_temp.marks_0290() not like '%stats_world/hour=2004-01-01 04:00%' or pg_temp.marks_0290() not like '%stats_good/day=2004-01-02 00:00%' then
      raise exception '0290 self-assert FAIL: the count did not move the marks by one batch: %', pg_temp.marks_0290();
    end if;

    -- UNDER THE CAP: the live body cut right after the cap (it returns what the cap decided), asked 15 minutes after the count
    -- that just ran, which is now the last count: nothing is skipped and the window starts where that count ended
    v_cap := (select h.new from hunks_0290 h where h.fn = 'public.tick_stats(timestamptz)' and h.n = 2);
    v_cut := replace(pg_get_functiondef('public.tick_stats(timestamptz)'::regprocedure), E'\r', '');
    if pg_temp.occurs_0290(v_cut, v_cap) <> 1 then
      raise exception '0290 self-assert FAIL: the live tick_stats does not carry the cap exactly once';
    end if;
    execute replace(substr(v_cut, 1, strpos(v_cut, v_cap) + length(v_cap) - 1)
                    || E'  return jsonb_build_object(''since'', v_prev_at, ''skipped'', v_skip);\nend $function$\n',
                    'CREATE OR REPLACE FUNCTION public.tick_stats(', 'CREATE FUNCTION pg_temp.tick_cut_0290(');
    v_run2 := pg_temp.tick_cut_0290(v_p2);
    if jsonb_typeof(v_run2->'skipped') is distinct from 'null' or (v_run2->>'since')::timestamptz is distinct from v_p1 then
      raise exception '0290 self-assert FAIL: 15 minutes after the last count the window starts at % and skips % (expected %, skipped null)',
        v_run2->>'since', v_run2->'skipped', v_p1;
    end if;
    raise exception using errcode = 'ZX290', message = jsonb_build_object('ms1', v_ms1, 'fold', v_run1->'fold')::text;
  exception when sqlstate 'ZX290' then
    v_info := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.stats_world w where w.at >= v_p1 - interval '1 day')
     or exists (select 1 from public.stats_runs r where r.at >= v_p1 - interval '1 day')
     or exists (select 1 from public.stats_good g where g.at >= v_p1 - interval '1 day')
     or exists (select 1 from public.stats_city c where c.at >= v_p1 - interval '1 day')
     or exists (select 1 from public.stats_city_good c where c.at >= v_p1 - interval '1 day')
     or exists (select 1 from public.stats_merchants m where m.at >= v_p1 - interval '1 day')
     or exists (select 1 from public.stats_fold_marks) then
    raise exception '0290 self-assert FAIL: the end-to-end probe survived its rollback';
  end if;
  if public.wc_int('stats_live_batch_rows') <> 300000 or public.wc_int('stats_max_window_minutes') <> 120 or public.wc_num('stats_budget_secs') <> 60 then
    raise exception '0290 self-assert FAIL: the end-to-end probe left a knob moved';
  end if;
  raise notice '0290 self-assert ok: (b)  THE CAP. stats_window_start leaves a 30- and a 120-minute gap alone, caps a 43-hour gap at 120 minutes and reads its knob. THE COUNT END TO END at an instant 40 days ahead (empty windows; marks planted in 2004; journal batch 1): five hours after the last count it read since now - 120 minutes and skipped {from the last count, to the cap}, its receipt in stats_runs kept it, its fold moved the marks by one batch; the live body cut right after the cap, asked 15 minutes after that count, skipped null and started at the last count. Rolled back and asserted gone (the count took % ms).',
    v_info->>'ms1';
end $probe_b$;

-- ── 8. (c) THE FOLD IN BATCHES, FROM A MARK ──────────────────────────────────────────────────────
-- P = 2004-09-10 12:30 UTC. With the knobs pinned (fine 72 h / 48 h, hourly window 30 d / 7 d) the edges are
--   E72 = 2004-09-07 12:00   E48 = 2004-09-08 12:00   D30 = 2004-08-11 00:00   D7 = 2004-09-03 00:00.
do $probe_c$
declare
  c_p    constant timestamptz := '2004-09-10 12:30:00+00';
  v_good uuid;
  v_r    jsonb;
  v_m0   text;
  v_w0   int;
  v_g0   int;
  v_sum  numeric;
  v_i    int;
  v_wm   timestamptz[] := array['2004-09-07 09:00+00', '2004-09-07 12:00+00', '2004-09-07 12:00+00', '2004-09-07 12:00+00', '2004-09-07 12:00+00'];
  v_gm   timestamptz[] := array['2004-08-08 00:00+00', '2004-08-09 00:00+00', '2004-08-10 00:00+00', '2004-08-11 00:00+00', '2004-08-11 00:00+00'];
  v_wr   int[] := array[10, 7, 7, 7, 7];
  v_gr   int[] := array[7, 6, 5, 4, 4];
  v_rm   int[] := array[5, 4, 1, 1, 0];
begin
  select g.id into v_good from public.goods g order by g.id limit 1;
  if v_good is null then
    raise exception '0290 self-assert FAIL: no good to plant the fold probe at';
  end if;
  if exists (select 1 from public.stats_world w where w.at >= '2004-01-01' and w.at < '2005-01-01')
     or exists (select 1 from public.stats_good g where g.at >= '2004-01-01' and g.at < '2005-01-01')
     or exists (select 1 from public.stats_fold_marks) then
    raise exception '0290 self-assert FAIL: a row or a mark already sits in 2004 — the fold probe cannot prove its own';
  end if;

  -- (c1) NO MARKS: the first range starts where the last count BEFORE this one had got (the count's own row, at P, is not "the last count")
  begin
    perform pg_temp.pin_0290();
    insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside, minted, removed, moved,
                                    sold, bought, units, trades, period, recent, n)
    select public.drift_slot_of(t), t, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, '{}'::jsonb, '{}'::jsonb, 1
      from unnest(array['2004-08-29 08:06+00', '2004-08-29 08:36+00',    -- the hour before the first range: untouched
                        '2004-08-29 09:06+00', '2004-08-29 09:36+00',    -- inside it: one row
                        '2004-08-29 13:06+00', '2004-08-29 13:36+00',    -- after it: untouched
                        '2004-09-01 10:21+00',                           -- the last count before this one
                        '2004-09-10 12:30+00']::timestamptz[]) t;        -- THIS count's own row
    v_r := public.stats_compact(c_p);
    if v_r ? 'late' or (v_r->>'removed')::int <> 1 or (v_r->'tables'->>'stats_world')::int <> 1 then
      raise exception '0290 self-assert FAIL: with no marks the fold removed %, not the one row of the first range', v_r;
    end if;
    if (select array_agg(w.at order by w.at) from public.stats_world w where w.at >= '2004-08-29' and w.at < '2004-08-30')
         is distinct from array['2004-08-29 08:06+00', '2004-08-29 08:36+00', '2004-08-29 09:36+00', '2004-08-29 13:06+00', '2004-08-29 13:36+00']::timestamptz[]
       or (select array_agg(w.n::int order by w.at) from public.stats_world w where w.at >= '2004-08-29' and w.at < '2004-08-30') is distinct from array[1, 1, 2, 1, 1] then
      raise exception '0290 self-assert FAIL: with no marks the first range is not [2004-08-29 09:00, 13:00) — the hour before and the hour after were touched, or the range was not folded';
    end if;
    if pg_temp.marks_0290() is distinct from 'stats_city/day=2004-08-02 00:00, stats_city/hour=2004-08-29 13:00, stats_city_good/day=2004-08-25 00:00, '
                                           'stats_city_good/hour=2004-09-03 04:00, stats_good/day=2004-08-02 00:00, stats_good/hour=2004-08-29 13:00, '
                                           'stats_merchants/hour=2004-08-29 13:00, stats_world/hour=2004-08-29 13:00' then
      raise exception '0290 self-assert FAIL: the first marks are not those of the last count before this one: %', pg_temp.marks_0290();
    end if;
    raise exception using errcode = 'ZX290', message = 'rollback';
  exception when sqlstate 'ZX290' then
    null;
  end;

  -- (c2) MARKS PLANTED: world hour mark 05:00 over seven hours of two rows; good day mark 08-07 over four days of two rows; the others one step
  -- from their edge, the good's hour mark below the day edge. Lateness first (budget 0): nothing moves.
  begin
    perform pg_temp.pin_0290();
    insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside, minted, removed, moved,
                                    sold, bought, units, trades, period, recent, n)
    select public.drift_slot_of(t), t, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, '{}'::jsonb, '{}'::jsonb, 1
      from generate_series('2004-09-07 05:00+00'::timestamptz, '2004-09-07 11:00+00', interval '1 hour') h,
           lateral (select h + interval '6 minutes' union all select h + interval '36 minutes') x(t);
    insert into public.stats_good (good_id, slot, at, mid, markets, stock, stock_target, sold, bought, sold_ducats, bought_ducats)
    select v_good, public.drift_slot_of(t), t, 5, 1, 100, 100, 1, 1, 1, 1
      from generate_series('2004-08-07 00:00+00'::timestamptz, '2004-08-10 00:00+00', interval '1 day') d,
           lateral (select d + interval '3 hours 51 minutes' union all select d + interval '23 hours 51 minutes') x(t);
    insert into public.stats_fold_marks (tbl, unit, through) values
      ('stats_world', 'hour', '2004-09-07 05:00+00'), ('stats_merchants', 'hour', '2004-09-07 11:00+00'),
      ('stats_good', 'hour', '2004-08-01 00:00+00'), ('stats_good', 'day', '2004-08-07 00:00+00'),
      ('stats_city', 'hour', '2004-09-07 11:00+00'), ('stats_city', 'day', '2004-08-10 00:00+00'),
      ('stats_city_good', 'hour', '2004-09-08 11:00+00'), ('stats_city_good', 'day', '2004-09-02 00:00+00');
    v_m0 := pg_temp.marks_0290();
    v_w0 := (select count(*) from public.stats_world w where w.at >= '2004-09-01' and w.at < '2004-10-01');
    v_g0 := (select count(*) from public.stats_good g where g.at >= '2004-08-01' and g.at < '2004-09-01');
    v_sum := (select sum(w.minted) from public.stats_world w where w.at >= '2004-09-01' and w.at < '2004-10-01');
    if v_w0 <> 14 or v_g0 <> 8 then
      raise exception '0290 self-assert FAIL: the fold probe planted % world rows and % good rows, not 14 and 8', v_w0, v_g0;
    end if;

    update public.world_config set value = to_jsonb(0) where key = 'stats_budget_secs';
    v_r := public.stats_compact(c_p);
    if (v_r->>'late') is distinct from 'true' or (v_r->>'removed')::int <> 0 or v_r->'tables' <> '{}'::jsonb
       or pg_temp.marks_0290() <> v_m0
       or (select count(*) from public.stats_world w where w.at >= '2004-09-01' and w.at < '2004-10-01') <> v_w0
       or (select count(*) from public.stats_good g where g.at >= '2004-08-01' and g.at < '2004-09-01') <> v_g0 then
      raise exception '0290 self-assert FAIL: a late fold (budget 0) did not return late and leave every row and every mark alone: %', v_r;
    end if;
    update public.world_config set value = to_jsonb(86400) where key = 'stats_budget_secs';

    -- call 1: the batch, the edges, the lift
    v_r := public.stats_compact(c_p);
    if pg_temp.marks_0290() is distinct from 'stats_city/day=2004-08-11 00:00, stats_city/hour=2004-09-07 12:00, stats_city_good/day=2004-09-03 00:00, '
                                           'stats_city_good/hour=2004-09-08 12:00, stats_good/day=2004-08-08 00:00, stats_good/hour=2004-08-11 04:00, '
                                           'stats_merchants/hour=2004-09-07 12:00, stats_world/hour=2004-09-07 09:00' then
      raise exception '0290 self-assert FAIL: after one fold the marks are not (batch of 4 hours / 1 day, never past an edge, the hour tier above the day edge): %', pg_temp.marks_0290();
    end if;
    if (select array_agg(w.at order by w.at) from public.stats_world w where w.at >= '2004-09-01' and w.at < '2004-10-01' and w.n = 2)
         is distinct from array['2004-09-07 05:36+00', '2004-09-07 06:36+00', '2004-09-07 07:36+00', '2004-09-07 08:36+00']::timestamptz[]
       or (select array_agg(g.at order by g.at) from public.stats_good g where g.at >= '2004-08-01' and g.at < '2004-09-01' and g.n = 2)
         is distinct from array['2004-08-07 23:51+00']::timestamptz[] then
      raise exception '0290 self-assert FAIL: one fold did not fold exactly the first 4 world hours (05..08) and the first good day (08-07)';
    end if;

    -- calls 1..5: each moves the mark by exactly the batch (or to the edge), removes exactly what it folded; the last folds nothing
    v_i := 1;
    loop
      if v_i > 1 then v_r := public.stats_compact(c_p); end if;
      if pg_temp.mark_0290('stats_world', 'hour') <> v_wm[v_i] or pg_temp.mark_0290('stats_good', 'day') <> v_gm[v_i]
         or (select count(*) from public.stats_world w where w.at >= '2004-09-01' and w.at < '2004-10-01') <> v_wr[v_i]
         or (select count(*) from public.stats_good g where g.at >= '2004-08-01' and g.at < '2004-09-01') <> v_gr[v_i]
         or (v_r->>'removed')::int <> v_rm[v_i] then
        raise exception '0290 self-assert FAIL: fold call % left world mark % / good-day mark % / world rows % / good rows % and removed % (expected % / % / % / % / %)',
          v_i, pg_temp.mark_0290('stats_world', 'hour'), pg_temp.mark_0290('stats_good', 'day'),
          (select count(*) from public.stats_world w where w.at >= '2004-09-01' and w.at < '2004-10-01'),
          (select count(*) from public.stats_good g where g.at >= '2004-08-01' and g.at < '2004-09-01'), v_r->>'removed',
          v_wm[v_i], v_gm[v_i], v_wr[v_i], v_gr[v_i], v_rm[v_i];
      end if;
      v_i := v_i + 1;
      exit when v_i > 5;
    end loop;
    if (select sum(w.minted) from public.stats_world w where w.at >= '2004-09-01' and w.at < '2004-10-01') <> v_sum
       or (select sum(w.n) from public.stats_world w where w.at >= '2004-09-01' and w.at < '2004-10-01') <> 14 then
      raise exception '0290 self-assert FAIL: folding by batches changed the world rows'' flow sum or their slot count';
    end if;
    raise exception using errcode = 'ZX290', message = 'rollback';
  exception when sqlstate 'ZX290' then
    null;
  end;

  if exists (select 1 from public.stats_world w where w.at >= '2004-01-01' and w.at < '2005-01-01')
     or exists (select 1 from public.stats_good g where g.at >= '2004-01-01' and g.at < '2005-01-01')
     or exists (select 1 from public.stats_fold_marks)
     or public.wc_int('stats_fine_hours') <> 72 or public.wc_num('stats_budget_secs') <> 60 or public.wc_int('stats_fold_batch_hours') <> 4 then
    raise exception '0290 self-assert FAIL: the fold probe survived its rollback, or left a knob moved';
  end if;
  raise notice '0290 self-assert ok: (c)  THE FOLD IN BATCHES, probe rows dated 2004 only. With NO marks the first range starts at bucket(the last count BEFORE this one - the window) less one hour (2004-08-29 09:00..13:00), not at the count''s own row; all eight first marks are as that rule says. With marks planted: a late fold (budget 0) returns late, removes nothing and leaves every row and mark; one call folds exactly 4 world hours (05..08 of seven) and the first of four good days and moves the marks by exactly the batch, never past an edge, the hour tier lifted above the day edge; the next calls fold the rest (3 hours, then a day each) and the last folds nothing; the flow sum and the slot count are unchanged. Rolled back and asserted gone.';
end $probe_c$;

-- ── 9. (d) THE JOURNAL: COMPACTED IN BATCHES, THE SUM KEPT ──────────────────────────────────────
-- the sum of every column of a journal-shaped table, as one jsonb (NEVER called on the real journal)
create function pg_temp.jsum_0290(p_tbl regclass)
returns jsonb
language plpgsql
as $$
declare
  v jsonb;
begin
  execute format('select to_jsonb(s) from (select sum(players) as players, sum(merchants) as merchants, sum(cities) as cities,
                         sum(set_aside) as set_aside, sum(at_sea) as at_sea, sum(at_sea_merchants) as at_sea_merchants,
                         sum(trades) as trades, sum(units) as units, sum(sold) as sold, sum(bought) as bought from %s) s', p_tbl) into v;
  return v;
end $$;

do $probe_d$
declare
  v_t     regclass;
  v_sum   jsonb;
  v_n     bigint;
  v_cnt   bigint;
  v_base  jsonb;
  v_r     jsonb;
  v_r2    jsonb;
begin
  -- (d1) stats_live_compact on a TEMP table of the journal's shape — never the real journal
  begin
    create temp table jt_0290 (like public.stats_live_deltas including defaults) on commit drop;
    v_t := 'pg_temp.jt_0290'::regclass;
    insert into jt_0290 (at, players, merchants, cities, set_aside, at_sea, at_sea_merchants, trades, units, sold, bought)
    select '2004-06-01 00:00+00'::timestamptz + i * interval '1 minute', i * 10, -i, i * 100, i, i % 3, i % 2, 1, i * 0.5, i * 7, i * 3
      from generate_series(1, 10) i;
    v_sum := pg_temp.jsum_0290(v_t);

    v_n := public.stats_live_compact(v_t, 4);
    select count(*) into v_cnt from jt_0290;
    if v_n <> 4 or v_cnt <> 7 or pg_temp.jsum_0290(v_t) <> v_sum then
      raise exception '0290 self-assert FAIL: compacting 4 of 10 journal rows returned %, left % rows (expected 7) or changed a sum', v_n, v_cnt;
    end if;
    if not exists (select 1 from jt_0290 j where j.at = '2004-06-01 00:04+00' and j.players = 100 and j.merchants = -10 and j.cities = 1000
                      and j.set_aside = 10 and j.at_sea = 4 and j.at_sea_merchants = 2 and j.trades = 4 and j.units = 5.0 and j.sold = 70 and j.bought = 30) then
      raise exception '0290 self-assert FAIL: the one row that replaced the first 4 is not their newest `at` with every figure their sum';
    end if;
    v_n := public.stats_live_compact(v_t, 100);                       -- p_rows over the table: it all becomes one row
    select count(*) into v_cnt from jt_0290;
    if v_n <> 7 or v_cnt <> 1 or pg_temp.jsum_0290(v_t) <> v_sum then
      raise exception '0290 self-assert FAIL: compacting more rows than the table holds returned %, left % rows (expected 1) or changed a sum', v_n, v_cnt;
    end if;
    v_n := public.stats_live_compact(v_t, 5);                         -- one row asked to be replaced by one
    if v_n <> 1 or (select count(*) from jt_0290) <> 1 or pg_temp.jsum_0290(v_t) <> v_sum
       or public.stats_live_compact(v_t, 0) <> 0 or public.stats_live_compact(v_t, null) <> 0 or (select count(*) from jt_0290) <> 1 then
      raise exception '0290 self-assert FAIL: compacting one row, or asking for none, changed the table';
    end if;
    delete from jt_0290;
    if public.stats_live_compact(v_t, 5) <> 0 or (select count(*) from jt_0290) <> 0 then
      raise exception '0290 self-assert FAIL: compacting an empty journal returned a count or invented a row';
    end if;
    raise exception using errcode = 'ZX290', message = 'rollback';
  exception when sqlstate 'ZX290' then
    null;
  end;

  -- (d2) stats_live_fold on the REAL journal with stats_live_batch_rows = 1: three planted rows make it "over"; it drains one batch (one row
  -- compacted), reconciles nothing (stats_live untouched) and waits; late (budget 0) it compacts nothing. The real journal is only ever
  -- tested with limit 2 and compacted by ONE row, then rolled back.
  begin
    perform pg_temp.pin_0290();
    update public.world_config set value = to_jsonb(1) where key = 'stats_live_batch_rows';
    perform public.stats_live_add('{"players": 5}'::jsonb);
    perform public.stats_live_add('{"players": 7}'::jsonb);
    perform public.stats_live_add('{"players": 11}'::jsonb);
    v_base := (select to_jsonb(l) from public.stats_live l);
    v_r := public.stats_live_fold(now());
    if (v_r->>'draining') is distinct from 'true' or (v_r->>'folded')::int <> 0 or (v_r->>'compacted')::bigint <> 1
       or (v_r->>'through')::timestamptz is distinct from (v_base->>'counted_through')::timestamptz
       or (select to_jsonb(l) from public.stats_live l) is distinct from v_base then
      raise exception '0290 self-assert FAIL: a journal over its batch did not drain one batch and leave public.stats_live alone: %', v_r;
    end if;
    update public.world_config set value = to_jsonb(0) where key = 'stats_budget_secs';
    v_r2 := public.stats_live_fold(now());
    if (v_r2->>'draining') is distinct from 'true' or (v_r2->>'compacted')::bigint <> 0 or (select to_jsonb(l) from public.stats_live l) is distinct from v_base then
      raise exception '0290 self-assert FAIL: a late drain (budget 0) compacted, or reconciled: %', v_r2;
    end if;
    raise exception using errcode = 'ZX290', message = 'rollback';
  exception when sqlstate 'ZX290' then
    null;
  end;

  if (select to_jsonb(l) from public.stats_live l) is distinct from v_base or public.wc_int('stats_live_batch_rows') <> 300000
     or public.wc_num('stats_budget_secs') <> 60 or to_regclass('pg_temp.jt_0290') is not null then
    raise exception '0290 self-assert FAIL: the journal probes survived their rollback, or left a knob moved';
  end if;
  raise notice '0290 self-assert ok: (d)  THE JOURNAL. stats_live_compact on a TEMP table of the journal''s shape: 4 of 10 rows become one (their newest `at`, every figure their sum), the sum of every column unchanged, the count n - p_rows + 1 = 7 and the returned number right; asking for more rows than the table holds leaves one; one row, none and null change nothing; an empty table invents no row. stats_live_fold with stats_live_batch_rows 1 on the real journal (three planted rows, a limit-2 test, ONE row compacted) returns draining, folded 0, compacted 1 and leaves public.stats_live untouched; late (budget 0) it compacts nothing. The real journal is only ever read by that limit-2 test and the one-row compaction: never counted, summed or locked whole. Rolled back and asserted gone.';
end $probe_d$;

do $done$
begin
  if exists (select 1 from public.stats_fold_marks)
     or public.wc_int('stats_max_window_minutes') <> 120 or public.wc_int('stats_fold_batch_hours') <> 4 or public.wc_int('stats_fold_batch_days') <> 1
     or public.wc_int('stats_live_batch_rows') <> 300000 or public.wc_num('stats_budget_secs') <> 60 then
    raise exception '0290 self-assert FAIL: a probe left a mark or moved a new knob';
  end if;
  raise notice '0290 self-assert ok: THE COUNT KEEPS TO A BUDGET. Window capped at 120 minutes (the span left is kept as `skipped`), the fold in batches of 4 hours / 1 day from a mark per table and tier (stats_fold_marks), the journal drained 300000 rows a run, the optional work (fold, drain) only while the run has used less than 60 s, seven indexes on the stats tables'' at / slot; tick_stats, stats_compact and stats_live_fold re-cut, every other function unmoved; no probe left a row, a mark or a knob behind.';
end $done$;
