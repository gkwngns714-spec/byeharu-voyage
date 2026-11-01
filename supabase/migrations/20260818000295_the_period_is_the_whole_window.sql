-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0295 — THE PERIOD IS THE WHOLE WINDOW
--        (the Stats money log reads each count's money over every game day since the last count, not over the
--         newest three: one new STABLE reader, public.stats_recent, and ONE hunk in public.tick_stats)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHERE IT COMES FROM ─────────────────────────────────────────────────────────────────────────
--   Found while measuring the Stats slice of owner rows 256 / 259 (docs/OWNER_REQUESTS.md); not a new instruction. The owner's limit
--   on that slice stands: "DO NOT CHANGE ANYTHING REGARDING TIME - THE SECONDLY DATA RENEWAL STAYS IN STATS". Nothing about time moves
--   here: no cron job or schedule, no knob (game_day_seconds, drift_slot_seconds, any stats_* knob), no switch, no client read, and no
--   other line of tick_stats. Design: docs/dev-log/2026-11-01-stats-period.md.
--
-- ── WHAT IS BROKEN (prod, read-only, 2026-11-01) ────────────────────────────────────────────────
--   Each public.stats_world row's `period` (-> minted / removed / moved, the Stats money log) is, per kind, this count's `recent` less the
--   previous count's `recent`, where `recent` = {game_day: {kind: ducats}} over the NEWEST THREE game days of treasury_daybook + treasury_flows.
--   game_day_seconds is 60 (the every-minute market, 10-30) and the count runs every 15 minutes, so `recent` reaches back 2-3 minutes of the
--   row's 15 and two consecutive `recent` maps never share a day: `period` is the money of the newest ~2 days, not of the window.
--   The window-based figures of the SAME row are right, and so are the flows themselves:
--
--     row (UTC)        bought (window)  period.BUY   x       sold (window)  period.SELL   x      Σ BUY flows in the window   Σ SELL flows
--     11-01 18:21      22,381,382       2,605,863    8.59    21,686,528     -4,733,320    4.58   22,381,382 (= bought)       -21,686,528 (= -sold)
--     11-01 18:06      25,310,348       2,996,731    8.45    27,997,554     -4,516,147    6.20   25,310,348 (= bought)       -27,997,554 (= -sold)
--     10-30 18:06       6,565,278         659,505    9.95     6,087,608       -449,600   13.54   (the 5-13x of the design note, docs/dev-log)
--
--   So a `period` read over the whole window equals the window's `bought` / `sold` to the ducat; the money log has been 4.6-13.5 times short.
--
-- ── WHAT THIS FILE DOES (one new reader, ONE hunk: it SUPERSEDES public.tick_stats' own statement) ───────
--   public.stats_recent(p_now, p_since) STABLE, server-only (NEW): the {game_day: {kind: ducats}} map over every game day from
--       least(game_day(p_now), game_day(p_since)) - 2   to p_now's day,
--     i.e. the window's days and the two before the first of them (the three-day shape tick_stats has always kept, applied to the window).
--     It IS the inline query of tick_stats moved verbatim (daybook half + flows half, 0243's per-(day, kind) sum before the aggregate, CARRIED
--     excluded, the flows cut at p_now) except that the lower bound is the one above, computed once. The self-assert proves the move twice: the
--     function body holds the old statement text with that one bound renamed, and `stats_recent(p_now, p_now)` equals the old statement run
--     on the same rows (the old three-day shape).
--   public.tick_stats is RE-CUT (it SUPERSEDES its own 16-line statement): the LIVE body (0214 as re-cut by 0224, 0226, 0229, 0232, 0243, 0246,
--     0269 and 0290; pre-image md5 of the whole body 899a09d32771e57aa276547f639829c0, the same on prod and in the chain; 0291 / 0292 / 0293 /
--     0294 did not touch it) with ONE hunk sliced from it: the inline `select ... into v_recent` becomes
--       v_recent := public.stats_recent(p_now, v_prev_at);
--     where v_prev_at is the window start AFTER 0290's cap (stats_max_window_minutes), so a catch-up count reads at most the cap. The `period`
--     statement, `stats_window_founded`, `stats_sides` and every other line stay byte for byte (the self-assert reverses the hunk to the pre-image).
--   (and the table comment of stats_world: `recent` is no longer "the newest three game days".)
--   WHY: the money log's `period` is read over 2-3 minutes of a 15-minute window (above). NO-OP WHERE THE NEW INPUT IS ABSENT: when the window
--     lies inside the current game day (days longer than the count's cadence, e.g. game_day_seconds 2880) the bound is today's three days and
--     stats_recent returns exactly what the inline statement returned (probe R2, run on the same rows); the change moves nothing there.
--     EVERYTHING THAT MUST MOVE TOGETHER MOVES IN THIS FILE: the statement and its only caller, and the words that describe it.
--
-- ── DECIDED HERE: THE THREE THINGS THE DESIGN LEFT OPEN ─────────────────────────────────────────
--   (1) THE FIRST ROW AFTER THIS FILE. The previous row's `recent` has the OLD shape (the newest three days of its own count). The rule
--       that compares it ALREADY EXISTS and is not touched: tick_stats' `period` statement walks the NEW map's (game day, kind) pairs and
--       subtracts the previous row's value for the SAME day and kind, or nothing when the previous row held no such day. So
--           a day only in the new map counts in full · a day in both counts the difference · a day only in the old map is never read.
--       It is not a difference of totals, and needs no new code: the statement stays byte for byte. With (3) every day of an old-shape row is
--       also in the new map, so on this very first row even a difference of totals would read right; the rule matters from the second row
--       on, where the previous map holds days the new one no longer does (T2 below: 15 old-only days; a difference of totals reads 71,348
--       where the flows are 111,999). The old-shape row is the (T1) probe, the steady state is (T2), and (T2) runs the difference of totals
--       on the same two maps as the positive control that the probe can tell the rules apart. Rolling back to the old body later is as safe:
--       it walks the three-day map against a wider previous map by the same key rule.
--   (2) COST. The count's wall is 120 s and `recent` is 1.1-23 s of it (1.9 / 10.6 / 8.6 s in the last three counts). Measured read-only on
--       prod (2026-11-01 ~18:20): treasury_flows 12,042 rows / 215 pages, treasury_daybook 5,963 rows / 615 pages (6.6 MB together; the daybook
--       keeps 30 game days). The flows half filters `world.game_day(created_at) >= ...`, which no index can serve, so it evaluates EVERY flows
--       row whatever the range; the daybook half is a scan of its primary key whose second column carries the bound. Neither half reads one
--       more row or page for a wider range; only the rows that PASS grow (flows 205 for three days, 4,330 for eighteen). Timed server-side on
--       prod, the same SELECT, paired runs: 0.88 s for three days against 1.04 s for eighteen, and 0.53 s (median of four) against 0.70 s (median of three): +0.16 s
--       (+18-33 %), the bound computed once (as here) being the same as inline. When the disk is busy the same SELECT takes 7 s (measured
--       18:55): the receipts' spread is load, not range. The width is bounded above by the 120-minute window cap (at most 122 days at 60 s a day)
--       and by the two tables' size, which a range cannot grow: NO further cap is added. (A sargable lower bound on created_at, tried read-only,
--       saved only ~0.07 s of the 0.17 s: not worth a second change in the reader.)
--   (3) TWO DAYS BELOW THE WINDOW. The lower bound is the window's first day less two, not the window's first day. The count fires at
--       hh:mm:00 plus 0.06-3 s (stats_runs: 18:06:00.059, 17:36:00.082, 17:51:01.37), i.e. just after a game-day boundary, so a flow created in the
--       last moments of the previous day and committed after the previous count's snapshot sits in the day BEFORE the window's first day:
--       outside a bound that starts at the window's first day, no row would ever count it; inside this one it is in the previous row's map
--       too, and the per-key difference picks it up. This is the slack the old three-day shape always had (the current day and the two before
--       it), applied to the window; with a window inside one game day the bound is today's three days exactly. (How many flows this saves was
--       not measured: the daybook has already collapsed those days by the next roll.)
--
-- ── SAID PLAINLY ────────────────────────────────────────────────────────────────────────────────
--   * OLD ROWS KEEP THEIR UNDERSTATED `period`. History is not rewritten, and cannot be: their `recent` kept three days and the daybook keeps 30
--     game days (30 minutes), so the older windows are gone from the books. The money log steps up at the first new row.
--   * A GAP LONGER THAN THE DAYBOOK'S MEMORY (treasury_days_kept = 30 game days = 30 minutes at 60 s a day) cannot be recovered by any reader:
--     older days were collapsed into CARRIED, which `recent` has always excluded. A day that vanished this way is "only in the old map" and is
--     ignored: no negative spike.
--   * A CATCH-UP COUNT (the 0290 cap) now also counts the two game days before its capped start, which belong to the span `skipped` records
--     and no other row counts: at most two minutes of money more in that one row.
--   * `stats_world.recent` grows from ~0.9 KB to ~3.6 KB a row (17 game days of 10 kinds measured: 2,472 characters, 3,560 bytes as jsonb,
--     before compression). Nothing else reads it (grep: only tick_stats). The hourly tier keeps one row an hour for ever (the fold keeps the
--     last slot's `recent`), ~30 MB a year; trimming it is the fold's business and is not touched here.
--
-- ── SELF-ASSERT (ONE atomic block: if anything below fails, nothing of this file is kept) ───────
--   Probe rows only, dated 2004 (no real game day, flow or count sits there; asserted before planting), planted in rolled-back
--   sub-transactions, with game_day_seconds pinned to 60 and stats_max_window_minutes to 120 INSIDE the probe (rolled back with it).
--   (a) as found: the hunk occurs once in the live body and reverses to the pre-image; tick_stats keeps its ACL / volatility / definer /
--       config and no longer mentions the daybook; stats_recent is STABLE, SECURITY DEFINER, server-only, and holds the old statement text
--       with the one bound renamed; EVERY OTHER function in public / cmd / world / voyage is md5-unmoved (exactly tick_stats moved and
--       stats_recent appeared); the registry, the walls (0 / 0 / 0), both owner switches and every knob as found.
--   (b) stats_recent on planted daybook + flows rows (both halves, one day in both, CARRIED, a flow after p_now, days below the bound):
--       (R1) a 15-day window -> exactly its 18 days; (R2) p_since = p_now -> the old three-day shape, EQUAL to the old statement run on the
--       same rows; (R3) p_since after p_now -> the same three days; (R4) p_since 30 days back -> every planted day.
--   (c) the real tick_stats body, cut right after the `period` statement (as 0290's cut after the cap), on planted previous rows:
--       (T1) a previous row of the OLD shape -> `period` = the hand-computed flows of the window; (T2) a previous row of the NEW shape one
--       window later -> the new flows only, the 15 old-only days ignored, and the plain difference of totals differs; (T3) a previous row
--       five hours old -> the cap decides the bound (`since`, `skipped`), and a day below the capped bound is absent from `recent`.
--   (d) nothing survives: no probe row, no knob moved, the scratch functions dropped.
-- ROLLBACK (forward): re-create public.tick_stats by reversing the hunk (the OLD text is in this file, verbatim) and drop public.stats_recent;
--   the previous row's wider `recent` is read by the old body by the same key rule. Nothing else was written.
-- DEPLOY: no lock beyond the two function rows and a table-comment row (stats_world), plus, for the seconds a probe runs, row locks on two
--   world_config rows (readers are not blocked); the running count keeps its old body until it ends. This file's lock_timeout is 5 s. The self-assert takes ~8 scans of treasury_flows (~1-2 s each on prod).
-- VERSION: 0295 (prod head 0294, read-only 2026-11-01); deploys AFTER 0294, one migration at a time.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', false);
  perform set_config('lock_timeout', '5s', false);
  if to_regprocedure('public.tick_stats(timestamptz)') is null
     or to_regprocedure('public.stats_window_start(timestamptz,timestamptz)') is null
     or to_regprocedure('world.game_day(timestamptz)') is null
     or to_regclass('public.treasury_daybook') is null
     or to_regclass('public.treasury_flows') is null
     or to_regclass('public.stats_world') is null then
    raise exception '0295 refuses: 0214 / 0243 / 0290 (the count, its two halves and its window cap) are not in this world';
  end if;
  if to_regprocedure('public.stats_recent(timestamptz,timestamptz)') is not null then
    raise exception '0295 refuses: public.stats_recent exists — this has been applied once';
  end if;
end $guard$;

-- ONE block: the two functions, the table comment and every assert share one transaction, so a failed assert keeps none of them (the deploy
-- runner is not a transaction block: statements outside this one would be kept).
do $main$
declare
  -- the hunk: OLD is the live body's own text (lines 51-66 of the pre-image), NEW is the call
  c_old    constant text := $h$  -- THE WORLD: the newest three game days per kind over daybook + flows, and the period as the difference
  select coalesce(jsonb_object_agg(d.gd, d.kinds), '{}'::jsonb) into v_recent
    from (select x.gd, jsonb_object_agg(x.kind, x.s) as kinds
            -- 0243: a (day, kind) in BOTH halves is ONE figure — summed here, before the aggregate keeps only the last key
            from (select y.gd, y.kind, sum(y.s) as s
                    from (select d.game_day as gd, d.kind, sum(d.ducats) as s
                            from public.treasury_daybook d
                           where d.kind <> 'CARRIED' and d.game_day >= world.game_day(p_now) - 2
                           group by 1, 2
                          union all
                          select world.game_day(f.created_at), f.kind, sum(f.ducats)
                            from public.treasury_flows f
                           where f.created_at <= p_now and world.game_day(f.created_at) >= world.game_day(p_now) - 2
                           group by 1, 2) y
                   group by 1, 2) x
           group by x.gd) d;
$h$;
  c_new    constant text := $h$  -- THE WORLD: every game day of the window and the two before its first (never fewer than the newest three), per kind, over daybook + flows
  -- (public.stats_recent, 0295) — and the period as the difference. The difference is taken per (game day, kind) of THIS map: this value less the
  -- previous row's value for the same day and kind, nothing when the previous row held no such day; a day only the previous row holds is never read.
  v_recent := public.stats_recent(p_now, v_prev_at);   -- 0295: v_prev_at is the window's start AFTER 0290's cap
$h$;
  -- where the cut body ends: the last line of the `period` statement (unchanged by this file)
  c_anchor constant text := $h$          select h.kind, h.ducats from public.stats_window_founded(v_prev_at, p_now) h) k;   -- 0232: one reading of the window
$h$;
  c_fn     constant text := $f$create function public.stats_recent(p_now timestamptz, p_since timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
-- 0295: THE MONEY THAT MOVED, per game day and kind — {game_day: {kind: ducats}} over the daybook (rolled) + the flows (not yet rolled), from
-- two game days before the first day of the window [p_since, p_now] to p_now's day (never fewer than the newest three: p_since after p_now
-- reads those). tick_stats' own statement, moved here verbatim (0243's per-(day, kind) sum before the aggregate, CARRIED excluded, the flows cut
-- at p_now) with ONE change: the lower bound v_lo, computed once. tick_stats keeps it as `recent`, the next row's baseline; `period` is the per-key
-- difference of two such maps. Cost: both halves read every row of their table whatever the range (no index serves the day filter), so a
-- wider range adds only the rows that pass. Server-only; called by public.tick_stats alone.
declare
  v_lo     int := least(world.game_day(p_now), world.game_day(p_since)) - 2;
  v_recent jsonb;
begin
  select coalesce(jsonb_object_agg(d.gd, d.kinds), '{}'::jsonb) into v_recent
    from (select x.gd, jsonb_object_agg(x.kind, x.s) as kinds
            -- 0243: a (day, kind) in BOTH halves is ONE figure — summed here, before the aggregate keeps only the last key
            from (select y.gd, y.kind, sum(y.s) as s
                    from (select d.game_day as gd, d.kind, sum(d.ducats) as s
                            from public.treasury_daybook d
                           where d.kind <> 'CARRIED' and d.game_day >= v_lo
                           group by 1, 2
                          union all
                          select world.game_day(f.created_at), f.kind, sum(f.ducats)
                            from public.treasury_flows f
                           where f.created_at <= p_now and world.game_day(f.created_at) >= v_lo
                           group by 1, 2) y
                   group by 1, 2) x
           group by x.gd) d;
  return v_recent;
end $fn$
$f$;
  d_probe  constant int := 130;      -- the probe's key space is [D - d_probe, D + 20]
  c_a      constant text := 'PROBE_0295';
  c_b      constant text := 'PROBE_0295_B';
  v_def    text;
  v_acl    text;
  v_vol    "char";
  v_secdef boolean;
  v_cfg    text;
  v_new    text;
  v_stmt   text;
  v_fns0   jsonb;
  v_fns1   jsonb;
  v_diff   text[];
  v_entry  bigint;
  v_econ   jsonb;
  v_city   jsonb;
  v_knobs  text;
  v_n      int;
  pr       record;
  -- the probes
  v_now    timestamptz := '2004-06-01 12:30:30+00';          -- 30 s into its game day
  v_now2   timestamptz;                                       -- 15 game days (15 minutes) later
  v_d      int;
  v_port   uuid;
  v_r1     jsonb;
  v_r2     jsonb;
  v_r3     jsonb;
  v_r4     jsonb;
  v_t1     jsonb;
  v_t2     jsonb;
  v_t3     jsonb;
  v_old    jsonb;
  v_plain  numeric;
begin
  -- ── 0. THE SCRATCH FUNCTIONS (pg_temp: gone with the session, dropped again at the end) ─────────
  execute $q$create function pg_temp.occurs_0295(p_hay text, p_needle text)
returns int language sql immutable
as $b$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $b$
$q$;
  -- the instant `p_off` seconds into game day `p_d` (the probe pins game_day_seconds to 60)
  execute $q$create function pg_temp.at_0295(p_d int, p_off numeric)
returns timestamptz language sql immutable
as $b$ select to_timestamp((p_d::numeric * 60 + p_off)::double precision) $b$
$q$;
  -- a recent map from a spec 'offset:a=amount,b=amount;offset:a=amount;...' (a / b = the two probe kinds; offsets from the day D)
  execute $q$create function pg_temp.map_0295(p_d int, p_spec text)
returns jsonb language sql
as $b$
  select coalesce(jsonb_object_agg((p_d + x.o)::text, x.kinds), '{}'::jsonb)
    from (select split_part(s.item, ':', 1)::int as o,
                 jsonb_object_agg(case split_part(kv.pair, '=', 1) when 'a' then 'PROBE_0295' when 'b' then 'PROBE_0295_B' end,
                                  split_part(kv.pair, '=', 2)::bigint) as kinds
            from unnest(string_to_array(p_spec, ';')) s(item),
                 unnest(string_to_array(split_part(s.item, ':', 2), ',')) kv(pair)
           group by 1) x
$b$
$q$;
  -- Σ of one kind over every day of a map (the plain difference of totals, the positive control)
  execute $q$create function pg_temp.total_0295(p_map jsonb, p_kind text)
returns numeric language sql
as $b$ select coalesce(sum(kv.value::numeric), 0) from jsonb_each(p_map) r, jsonb_each_text(r.value) kv where kv.key = p_kind $b$
$q$;
  -- the two knobs the probe depends on (rolled back with the probe)
  execute $q$create function pg_temp.pin_0295()
returns void language plpgsql
as $b$
declare
  v_n int;
begin
  update public.world_config w set value = v.val
    from (values ('game_day_seconds', to_jsonb(60)), ('stats_max_window_minutes', to_jsonb(120))) v(key, val)
   where w.key = v.key;
  get diagnostics v_n = row_count;
  if v_n <> 2 then
    raise exception '0295 self-assert FAIL: the probe could not pin its two knobs (%)', v_n;
  end if;
end $b$
$q$;
  -- a previous count's row, with a slot above every real one, so that `order by slot desc limit 1` finds it
  execute $q$create function pg_temp.prev_0295(p_at timestamptz, p_recent jsonb)
returns void language sql
as $b$
  insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside, minted, removed, moved,
                                  sold, bought, units, trades, period, recent, n)
  select coalesce(max(w.slot), 0) + 1000000, p_at, world.game_day(p_at), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '{}'::jsonb, p_recent, 1
    from public.stats_world w
$b$
$q$;

  -- ── 1. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
  select replace(pg_get_functiondef(p.oid), E'\r', ''), coalesce(p.proacl::text, ''), p.provolatile, p.prosecdef, coalesce(p.proconfig::text, '')
    into v_def, v_acl, v_vol, v_secdef, v_cfg
    from pg_proc p where p.oid = 'public.tick_stats(timestamptz)'::regprocedure;
  select jsonb_object_agg(p.oid::regprocedure::text, md5(replace(pg_get_functiondef(p.oid), E'\r', ''))) into v_fns0
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select count(*) into v_entry from public.client_rpc_entry_points();
  select value into v_econ from public.world_config where key = 'economy_closed';
  select value into v_city from public.world_config where key = 'city_treasury_enabled';
  select md5(string_agg(c.key || '=' || c.value::text, ',' order by c.key)) into v_knobs from public.world_config c;

  if pg_temp.occurs_0295(v_def, c_old) <> 1 then
    raise exception '0295 self-assert FAIL: the hunk occurs % time(s) in the live tick_stats, not once — the live body is not what this file was cut against',
      pg_temp.occurs_0295(v_def, c_old);
  end if;

  -- ── 2. THE READER, THEN THE ONE HUNK ────────────────────────────────────────────────────────────
  execute c_fn;
  comment on function public.stats_recent(timestamptz, timestamptz) is
    '0295: {game_day: {kind: ducats}} over the daybook + the flows, from two game days before the first day of the window [p_since, p_now] to p_now''s day (never fewer than the newest three). tick_stats keeps it as `recent`; `period` is the per-(day, kind) difference of two such maps. STABLE, server-only; called by public.tick_stats alone.';
  revoke all on function public.stats_recent(timestamptz, timestamptz) from public, anon, authenticated;

  v_new := replace(v_def, c_old, c_new);
  execute v_new;

  -- ── 3. (a) AS FOUND, AFTER: the hunk, the reader, every other function ──────────────────────────
  select replace(pg_get_functiondef(p.oid), E'\r', '') into v_new from pg_proc p where p.oid = 'public.tick_stats(timestamptz)'::regprocedure;
  if pg_temp.occurs_0295(v_new, c_new) <> 1 or pg_temp.occurs_0295(v_new, c_old) <> 0 then
    raise exception '0295 self-assert FAIL: the new hunk is not in the live body exactly once (or the old text is still there)';
  end if;
  if replace(v_new, c_new, c_old) <> v_def then
    raise exception '0295 self-assert FAIL: tick_stats does not reverse to its pre-image';
  end if;
  if pg_temp.occurs_0295(v_new, 'treasury_daybook') <> 0 then
    raise exception '0295 self-assert FAIL: tick_stats still reads treasury_daybook — the query did not move whole';
  end if;
  select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
    into pr from pg_proc p where p.oid = 'public.tick_stats(timestamptz)'::regprocedure;
  if pr.acl <> v_acl or pr.vol <> v_vol or pr.secdef <> v_secdef or pr.cfg <> v_cfg then
    raise exception '0295 self-assert FAIL: tick_stats changed its ACL, volatility, definer or config';
  end if;

  select p.oid, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, '') as cfg, coalesce(p.proacl::text, '') as acl, p.prosrc
    into pr from pg_proc p where p.oid = to_regprocedure('public.stats_recent(timestamptz,timestamptz)');
  if not found or pr.provolatile <> 's' or not pr.prosecdef or pr.cfg not like '%search_path=public, pg_temp%'
     or has_function_privilege('anon', pr.oid, 'execute') or has_function_privilege('authenticated', pr.oid, 'execute')
     or pr.acl like '%,=X/%' or pr.acl like '{=X/%' then
    raise exception '0295 self-assert FAIL: stats_recent is not a STABLE, SECURITY DEFINER, server-only function with the search_path set (acl %)', pr.acl;
  end if;
  -- the statement moved whole: the old statement text (its comment line dropped) with the one bound renamed
  v_stmt := replace(substr(c_old, strpos(c_old, E'\n') + 1), 'world.game_day(p_now) - 2', 'v_lo');
  if pg_temp.occurs_0295(pr.prosrc, v_stmt) <> 1 or pg_temp.occurs_0295(c_old, 'world.game_day(p_now) - 2') <> 2 then
    raise exception '0295 self-assert FAIL: stats_recent does not hold the old statement with only the bound renamed';
  end if;

  -- EVERY OTHER FUNCTION in public / cmd / world / voyage is md5-unmoved: exactly tick_stats differs, exactly stats_recent is new
  select jsonb_object_agg(p.oid::regprocedure::text, md5(replace(pg_get_functiondef(p.oid), E'\r', ''))) into v_fns1
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select array_agg(q.fn order by q.fn) into v_diff
    from (select coalesce(a.key, b.key) as fn
            from jsonb_each_text(v_fns1) a full join jsonb_each_text(v_fns0) b on b.key = a.key
           where a.value is distinct from b.value) q;
  if v_diff is distinct from (select array_agg(e order by e) from unnest(array[
        to_regprocedure('public.tick_stats(timestamptz)')::text, to_regprocedure('public.stats_recent(timestamptz,timestamptz)')::text]) e) then
    raise exception '0295 self-assert FAIL: the functions that moved or appeared are %, not exactly tick_stats and stats_recent', v_diff;
  end if;
  select count(*) into v_n from jsonb_object_keys(v_fns0);

  -- the registry, the walls, both owner switches and every knob as found
  if (select count(*) from public.client_rpc_entry_points()) <> v_entry
     or (select value from public.world_config where key = 'economy_closed') is distinct from v_econ
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from v_city then
    raise exception '0295 self-assert FAIL: the registry or an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0295 self-assert FAIL: a wall moved';
  end if;
  if (select md5(string_agg(c.key || '=' || c.value::text, ',' order by c.key)) from public.world_config c) is distinct from v_knobs then
    raise exception '0295 self-assert FAIL: a knob moved';
  end if;
  raise notice '0295 self-assert ok: (a)  AS FOUND. The one hunk occurs once in the live tick_stats and reverses to its pre-image; tick_stats keeps its ACL, volatility, definer and config and no longer reads the daybook; stats_recent is STABLE, SECURITY DEFINER, server-only (no anon / authenticated / PUBLIC execute), search_path set, and holds the old statement text with only the lower bound renamed; EVERY OTHER function in public/cmd/world/voyage is md5-unmoved (% functions: exactly tick_stats differs, exactly stats_recent is new); registry % unchanged; walls 0 / 0 / 0; both owner switches and every knob as found.',
    v_n, v_entry;

  -- ── 4. THE PROBE FUNCTIONS: the old statement, and the live body cut after the period ───────────
  execute 'create function pg_temp.recent_old_0295(p_now timestamptz) returns jsonb language plpgsql as $b$ declare v_recent jsonb; begin '
          || c_old || ' return v_recent; end $b$';
  if pg_temp.occurs_0295(v_new, c_anchor) <> 1 then
    raise exception '0295 self-assert FAIL: the end of the period statement occurs % time(s) in the live body, not once', pg_temp.occurs_0295(v_new, c_anchor);
  end if;
  execute replace(substr(v_new, 1, strpos(v_new, c_anchor) + length(c_anchor) - 1)
                  || E'  return jsonb_build_object(''since'', v_prev_at, ''skipped'', v_skip, ''recent'', v_recent, ''period'', v_period);\nend $function$\n',
                  'CREATE OR REPLACE FUNCTION public.tick_stats(', 'CREATE FUNCTION pg_temp.tick_cut_0295(');

  -- ── 5. (b) THE READER AND (c) THE COUNT, ON PLANTED ROWS DATED 2004 ─────────────────────────────
  -- Day D = the probe's p_now's game day. Daybook (the rolled half), kind a unless said: D-19 2 · D-18 1 · D-17 7,000 · D-16 11,000 · D-15 60 ·
  -- D-14 5 · D-13 100 · D-12 200 (+ b 50) · D-11 300 · D-10 400 (+ CARRIED 777,777) · D-9 500.
  -- Flows (the not yet rolled half): D-15 40 (before the previous count, 30 s in) and 40 (after it) · D-14 6 (a day in BOTH halves: 5 + 6 = 11) ·
  -- D-8 .. D-1: 1,000 .. 8,000 · D-3 b 30 · D-2 b 40 · D 9,000 (before p_now) and 99,999 (after it) · D+1 .. D+15: 100 .. 1,500.
  begin
    perform pg_temp.pin_0295();
    v_d := world.game_day(v_now);
    v_now2 := pg_temp.at_0295(v_d + 15, 30);
    if pg_temp.at_0295(v_d, 30) <> v_now or world.game_day(pg_temp.at_0295(v_d - 3, 0)) <> v_d - 3 or world.game_day(pg_temp.at_0295(v_d + 7, 59.9)) <> v_d + 7
       or world.game_day(v_now2) <> v_d + 15 or v_now2 - v_now <> interval '15 minutes' then
      raise exception '0295 self-assert FAIL: the probe''s day arithmetic is off (game_day_seconds pinned to %)', public.wc_num('game_day_seconds');
    end if;
    -- no real day, flow or count sits in the probe's key space
    if exists (select 1 from public.treasury_daybook b where b.game_day between v_d - d_probe and v_d + 20)
       or exists (select 1 from public.treasury_flows f where f.created_at >= pg_temp.at_0295(v_d - d_probe, 0) and f.created_at < pg_temp.at_0295(v_d + 21, 0))
       or exists (select 1 from public.stats_world w where w.at >= '2004-01-01' and w.at < '2005-01-01') then
      raise exception '0295 self-assert FAIL: a real row already sits in the probe''s 2004 key space';
    end if;
    select id into v_port from public.ports where kind = 'HARBOUR' order by id limit 1;
    if v_port is null then
      raise exception '0295 self-assert FAIL: no harbour to plant the probe at';
    end if;

    insert into public.treasury_daybook (port_id, game_day, kind, ducats)
    select v_port, v_d + t.o, t.k, t.a
      from (values (-19, c_a, 2), (-18, c_a, 1), (-17, c_a, 7000), (-16, c_a, 11000), (-15, c_a, 60), (-14, c_a, 5), (-13, c_a, 100),
                   (-12, c_a, 200), (-12, c_b, 50), (-11, c_a, 300), (-10, c_a, 400), (-10, 'CARRIED', 777777), (-9, c_a, 500)) t(o, k, a);
    insert into public.treasury_flows (port_id, kind, ducats, created_at)
    select v_port, t.k, t.a, pg_temp.at_0295(v_d + t.o, t.s)
      from (values (-15, c_a, 40, 10), (-15, c_a, 40, 50), (-14, c_a, 6, 20),
                   (-8, c_a, 1000, 20), (-7, c_a, 2000, 20), (-6, c_a, 3000, 20), (-5, c_a, 4000, 20),
                   (-4, c_a, 5000, 20), (-3, c_a, 6000, 20), (-2, c_a, 7000, 20), (-1, c_a, 8000, 20),
                   (-3, c_b, 30, 21), (-2, c_b, 40, 21), (0, c_a, 9000, 10), (0, c_a, 99999, 50),
                   (1, c_a, 100, 10), (2, c_a, 200, 10), (3, c_a, 300, 10), (4, c_a, 400, 10), (5, c_a, 500, 10),
                   (6, c_a, 600, 10), (7, c_a, 700, 10), (8, c_a, 800, 10), (9, c_a, 900, 10), (10, c_a, 1000, 10),
                   (11, c_a, 1100, 10), (12, c_a, 1200, 10), (13, c_a, 1300, 10), (14, c_a, 1400, 10), (15, c_a, 1500, 10)) t(o, k, a, s);

    -- (R1) a 15-day window: exactly its days, both halves summed, CARRIED out, the flow after p_now out, D-19 / D-18 below the bound out
    v_r1 := public.stats_recent(v_now, pg_temp.at_0295(v_d - 15, 30));
    if v_r1 is distinct from pg_temp.map_0295(v_d, '-17:a=7000;-16:a=11000;-15:a=140;-14:a=11;-13:a=100;-12:a=200,b=50;-11:a=300;-10:a=400;-9:a=500;-8:a=1000;-7:a=2000;-6:a=3000;-5:a=4000;-4:a=5000;-3:a=6000,b=30;-2:a=7000,b=40;-1:a=8000;0:a=9000') then
      raise exception '0295 self-assert FAIL: (R1) the 15-day window is not its 18 days summed over both halves: %', v_r1;
    end if;
    -- (R2) no gap: the old three-day shape, and EQUAL to the old statement run on the same rows
    v_r2 := public.stats_recent(v_now, v_now);
    v_old := pg_temp.recent_old_0295(v_now);
    if v_r2 is distinct from pg_temp.map_0295(v_d, '-2:a=7000,b=40;-1:a=8000;0:a=9000') or v_r2 is distinct from v_old then
      raise exception '0295 self-assert FAIL: (R2) with no gap stats_recent is not the old three-day statement: % against %', v_r2, v_old;
    end if;
    -- (R3) a window start AFTER p_now still reads the newest three days
    v_r3 := public.stats_recent(v_now, v_now + interval '1 hour');
    if v_r3 is distinct from v_r2 then
      raise exception '0295 self-assert FAIL: (R3) a window start after p_now reads %, not the newest three days', v_r3;
    end if;
    -- (R4) a window start 30 days back reads every planted day (nothing caps it inside the reader)
    v_r4 := public.stats_recent(v_now, v_now - interval '30 days');
    if v_r4 is distinct from (pg_temp.map_0295(v_d, '-19:a=2;-18:a=1') || v_r1) then
      raise exception '0295 self-assert FAIL: (R4) a window start 30 days back does not read every planted day: %', v_r4;
    end if;

    -- (T1) THE FIRST ROW AFTER THIS FILE: the previous count, 15 minutes before, wrote the OLD shape (its newest three days, as of its instant: D-15 held 100)
    perform pg_temp.prev_0295(pg_temp.at_0295(v_d - 15, 30), pg_temp.map_0295(v_d, '-17:a=7000;-16:a=11000;-15:a=100'));
    v_t1 := pg_temp.tick_cut_0295(v_now);
    if (v_t1->>'since')::timestamptz is distinct from pg_temp.at_0295(v_d - 15, 30) or jsonb_typeof(v_t1->'skipped') is distinct from 'null'
       or v_t1->'recent' is distinct from v_r1 then
      raise exception '0295 self-assert FAIL: (T1) the count did not read the window from the previous count: since %, skipped %, recent %', v_t1->>'since', v_t1->'skipped', v_t1->'recent';
    end if;
    -- the flows of the window (after the previous count, up to p_now): a: D-15 after it 40 + D-14..D 46,511 = 46,551 · b: 50 + 30 + 40 = 120
    if v_t1->'period' is distinct from '{"PROBE_0295": 46551, "PROBE_0295_B": 120}'::jsonb then
      raise exception '0295 self-assert FAIL: (T1) the first row after the file has period %, not the window''s flows {a 46551, b 120}', v_t1->'period';
    end if;

    -- (T2) THE STEADY STATE: the previous count wrote the NEW shape (T1's map, as of p_now); one window (15 game days) later, 99,999 more landed on
    -- day D after it and 100 .. 1,500 on D+1 .. D+15. The new map is D-2 .. D+15; the previous map's D-17 .. D-3 are only in the old map and are never read.
    perform pg_temp.prev_0295(v_now, v_t1->'recent');
    v_t2 := pg_temp.tick_cut_0295(v_now2);
    if (v_t2->>'since')::timestamptz is distinct from v_now or jsonb_typeof(v_t2->'skipped') is distinct from 'null'
       or v_t2->'recent' is distinct from pg_temp.map_0295(v_d, '-2:a=7000,b=40;-1:a=8000;0:a=108999;1:a=100;2:a=200;3:a=300;4:a=400;5:a=500;6:a=600;7:a=700;8:a=800;9:a=900;10:a=1000;11:a=1100;12:a=1200;13:a=1300;14:a=1400;15:a=1500') then
      raise exception '0295 self-assert FAIL: (T2) the second count did not read D-2 .. D+15 from the first: since %, recent %', v_t2->>'since', v_t2->'recent';
    end if;
    -- a: D-2 and D-1 unchanged (0), D +99,999, D+1..D+15 12,000 = 111,999 · b: unchanged on D-2 (0), nothing else in range
    if v_t2->'period' is distinct from '{"PROBE_0295": 111999}'::jsonb then
      raise exception '0295 self-assert FAIL: (T2) the steady-state row has period %, not the new flows {a 111999}', v_t2->'period';
    end if;
    -- the positive control: a plain difference of totals on the same two maps is a different (wrong) number, so this probe can tell the rules apart
    v_plain := pg_temp.total_0295(v_t2->'recent', c_a) - pg_temp.total_0295(v_t1->'recent', c_a);
    if v_plain <> 71348 then
      raise exception '0295 self-assert FAIL: (T2) the plain difference of totals is %, expected 71348 (a number other than the per-key 111999)', v_plain;
    end if;

    raise exception using errcode = 'ZX295', message = 'rollback';
  exception when sqlstate 'ZX295' then
    null;
  end;

  -- (T3) THE CAP DECIDES THE BOUND: a previous count five hours old; the capped start (p_now - 120 minutes = D-120) is what stats_recent gets, so D-123 (inside
  -- five hours, below the capped bound D-122) is not read, and D-122 .. D-120 are. A tick_stats that passed the raw previous instant would read D-123 too.
  begin
    perform pg_temp.pin_0295();
    v_d := world.game_day(v_now);
    if exists (select 1 from public.treasury_daybook b where b.game_day between v_d - d_probe and v_d + 20)
       or exists (select 1 from public.treasury_flows f where f.created_at >= pg_temp.at_0295(v_d - d_probe, 0) and f.created_at < pg_temp.at_0295(v_d + 21, 0))
       or exists (select 1 from public.stats_world w where w.at >= '2004-01-01' and w.at < '2005-01-01') then
      raise exception '0295 self-assert FAIL: a real row already sits in the probe''s 2004 key space (T3)';
    end if;
    select id into v_port from public.ports where kind = 'HARBOUR' order by id limit 1;
    insert into public.treasury_flows (port_id, kind, ducats, created_at)
    select v_port, c_a, t.a, pg_temp.at_0295(v_d + t.o, 20)
      from (values (-123, 9), (-122, 3), (-121, 5), (-120, 7)) t(o, a);
    perform pg_temp.prev_0295(v_now - interval '5 hours', '{}'::jsonb);
    v_t3 := pg_temp.tick_cut_0295(v_now);
    if (v_t3->>'since')::timestamptz is distinct from v_now - interval '120 minutes'
       or (v_t3->'skipped'->>'from')::timestamptz is distinct from v_now - interval '5 hours'
       or (v_t3->'skipped'->>'to')::timestamptz is distinct from v_now - interval '120 minutes'
       or v_t3->'recent' is distinct from pg_temp.map_0295(v_d, '-122:a=3;-121:a=5;-120:a=7')
       or v_t3->'period' is distinct from '{"PROBE_0295": 15}'::jsonb then
      raise exception '0295 self-assert FAIL: (T3) after a five-hour gap the count read since %, skipped %, recent %, period % — not the capped window D-122 .. D-120',
        v_t3->>'since', v_t3->'skipped', v_t3->'recent', v_t3->'period';
    end if;
    raise exception using errcode = 'ZX295', message = 'rollback';
  exception when sqlstate 'ZX295' then
    null;
  end;

  -- ── 6. (d) NOTHING SURVIVES ─────────────────────────────────────────────────────────────────────
  if exists (select 1 from public.treasury_daybook where kind in (c_a, c_b))
     or exists (select 1 from public.treasury_flows where kind in (c_a, c_b))
     or exists (select 1 from public.stats_world w where w.at >= '2004-01-01' and w.at < '2005-01-01') then
    raise exception '0295 self-assert FAIL: a probe row survived its rollback';
  end if;
  if (select md5(string_agg(c.key || '=' || c.value::text, ',' order by c.key)) from public.world_config c) is distinct from v_knobs then
    raise exception '0295 self-assert FAIL: a probe left a knob moved';
  end if;
  -- the table comment last: its (share-update-exclusive) lock is then held only to the commit
  comment on table public.stats_world is
    '0214, `recent` re-read by 0295: the world''s money by holder at each slot, and what moved since the previous row: minted, removed, moved (Σ |flow| over the moved kinds), sold / bought (ducats, from SOLD / BOUGHT events), units, trades. `period` is kind → ducats this period: per (game day, kind) of `recent`, its value less the previous row''s for the same day (public.tick_stats). `recent` is {game_day: {kind: ducats}} over daybook + flows (public.stats_recent): every game day of the count''s window and the two before it, never fewer than the newest three; the next row''s baseline. A row written before 0295 holds only the newest three days and a `period` read over them. Written by public.tick_stats alone.';

  drop function pg_temp.tick_cut_0295(timestamptz), pg_temp.recent_old_0295(timestamptz), pg_temp.prev_0295(timestamptz, jsonb), pg_temp.pin_0295(),
                pg_temp.total_0295(jsonb, text), pg_temp.map_0295(int, text), pg_temp.at_0295(int, numeric), pg_temp.occurs_0295(text, text);

  raise notice '0295 self-assert ok: (b)(c)(d)  THE PERIOD IS THE WHOLE WINDOW, probe rows dated 2004 only (game_day_seconds pinned to 60 inside the probe). stats_recent on planted daybook + flows rows: a 15-day window reads exactly its 18 days with both halves summed, CARRIED and the flow after p_now out and the days below the bound out; with no gap it is the old three-day shape and EQUAL to the old statement run on the same rows; a window start after p_now reads the same three days; a start 30 days back reads every planted day. The live tick_stats body cut after the period statement: (T1) the FIRST ROW after this file, against a previous row of the OLD shape, has period = the window''s flows to the ducat (46,551 and 120); (T2) the steady state, against a previous row of the NEW shape one window later, has period = the new flows only (111,999), the 15 old-only days ignored, where a plain difference of totals would read 71,348; (T3) after a five-hour gap the 0290 cap decides the bound (since = p_now - 120 minutes, skipped {from, to}) and the day below it is absent. Rolled back and asserted gone; no knob moved.';
end $main$;

reset statement_timeout;
reset lock_timeout;
