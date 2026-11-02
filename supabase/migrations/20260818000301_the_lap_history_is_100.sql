-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0301 — THE LAP HISTORY IS 100   (the owner's order: world_config.standing_route_lap_keep 200 -> 100; ONE knob row, nothing else)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ORDER (owner, 2026-11-02, verbatim) ─────────────────────────────────────────────────────
--   "route lap history - we actually don't need this. 100 would be good"
--   The knob is public.world_config key `standing_route_lap_keep`: 200 since 0097 (30 before). This file sets it to 100. It is the ONE knob change the
--   owner authorised: no other knob, switch, cron job or schedule moves. Design and numbers: docs/dev-log/2026-11-02-lap-history-100.md.
--
-- ── WHAT IT DOES: ONE UPDATE OF ONE ROW ─────────────────────────────────────────────────────────
--   update public.world_config set value = to_jsonb(100), description = (the same sentence with the history), updated_at = now()
--    where key = 'standing_route_lap_keep';
--   to_jsonb(100) is how 0290 / 0097 write an integer knob (a jsonb number); world_config has NO updated_at trigger (the only trigger on it fires for
--   `time_compression` alone), so updated_at is set by hand, as 0021 does. NO purge, NO function change, NO table rewrite in this file.
--
-- ── THE TRIM IS LAZY, AND ALREADY WRITTEN ───────────────────────────────────────────────────────
--   The knob has exactly ONE reader: cmd.standing_route_close_lap(uuid, timestamptz) (read on prod 2026-11-01: no other function in any schema names the
--   key). At every lap close it runs, for THAT route only,
--       delete from public.standing_route_laps x where x.route_id = p_route and x.lap_no <= l.lap_no - public.wc_int('standing_route_lap_keep');
--   so once the knob reads 100 each route trims itself to its newest 100 closed laps (+ the open one) at its NEXT lap close: ~100 rows per route,
--   about 837 x 100 = ~84,000 rows in all, over the first hour or two (the 837 routes close ~2,800 laps an hour when the disk is quiet = a lap per route
--   every ~18 minutes on average, and every 30-60 minutes in the busy hours; a route that is laid up or paused trims when it next closes one).
--   Rows now: 167,587 over 837 routes = 200-201 each; afterwards ~84,500. The heap (227 MB) keeps its size: the freed room is
--   reused by new laps, and a LATER migration compacts the table - this file does not.
--
-- ── WHAT DEPENDS ON HOW MANY LAPS ARE KEPT (every reader of the laps table, read on prod) ───────
--   Needs the newest 1-10 laps only: cmd.standing_route_close_lap (the previous lap's stock_out), cmd.run_standing_route (the last N laps lost money,
--   N = the route's own guard, 1 to 20; the newest started/closed lap), cmd.standing_route_note_skip (the open lap), public.lap_trades (one lap),
--   public.npc_leg_lines (the newest 2 closed laps), world.npc_fleet_card (the newest lap's skipped), world.standing_routes (the newest 10),
--   public.route_earnings `lap` / `laps_recent` (the newest 7), world.fleet_trades (the newest 8). route_earnings `laps_done` is max(lap_no) and `total`
--   comes from public.route_month_laps (0278), the all-time book: neither moves.
--   Needs the LAST 24 HOURS of laps (so it reads as many laps as a route closes in a day): public.route_earnings (`day`, `day_laps`, `day_since`,
--   `day_full`), world.fleet_trades (`day`) and public.stats_merchants_window(now - 24 h, now) (the Stats count's merchants block every 15 minutes:
--   profit_day, laps_day, losing_pct, top, bottom, and each house's day and laps).
--   SAID PLAINLY: for a route that closes MORE than 100 laps in a day, the newest 100 cover less than 24 hours, so its "so far today" is shorter
--   and the Stats merchants day counts fewer laps. Measured on prod (read-only, 2026-11-01 23:30 UTC, DB clock): over the last 24 h 34 of 781 routes
--   closed 100+ laps (max 132); but the last three whole hours ran at the quiet-disk rate (2,747 / 2,812 / 2,804 laps an hour, against about 800-1,700,
--   and one hour of 459, in the busy hours), and at THAT rate x 8 about 278 of 760 routes (37 %) close 100+ laps a day (p50 80, p90 160, max 328), and the laps beyond each
--   route's newest 100 are 12,056 of 66,904 (18 %). EVERY ONE OF THEM IS A MERCHANT (NPC) ROUTE: the world has 838 routes, 837 merchants' and ONE
--   player's (Havana - Matsumae, which has never closed a lap), so no human player's own sheet is cut short. The merchant sheet already prints
--   "So far - over the last <span>" when `day_full` is false (src/live/MerchantSheet.tsx), so the shorter day is labelled, not hidden.
--
-- ── WHAT DOES NOT MOVE ──────────────────────────────────────────────────────────────────────────
--   Every other world_config row (key, value, description, updated_at: one md5, before = after), every function in public / cmd / world / voyage (md5,
--   asserted; no function is created, re-cut or dropped), the registry, the walls (0 / 0 / 0), both owner switches (economy_closed,
--   city_treasury_enabled), every cron job and schedule. No lap row is read or written by this file (asserted from this backend's own counters on the table and its indexes).
--
-- ── THE BUDGET OF THIS FILE (docs/OPS_HEALTH.md section 4) ──────────────────────────────────────
--   bv-deploy.sh pauses every cron job for the whole push. statement_timeout 90 s and lock_timeout 5 s from the first statement: a slow file FAILS FAST
--   and rolls back whole. The update and every assert share ONE DO block (the runner is not a transaction block: a statement outside it would be
--   kept after a failed assert). The self-assert reads the catalog (678 function bodies on prod, twice), the 291-row knob table (twice) and nothing else:
--   milliseconds, independent of the size of any real table. It looks ONLY at its own row, never runs a real step and never reads the laps.
--
-- ── PROD CHECKS (before the push; read-only; in the PR body) ────────────────────────────────────
--   * select max(version) from supabase_migrations.schema_migrations                        = 20260818000300
--   * select value::text from public.world_config where key = 'standing_route_lap_keep'     = 200  (this file also accepts 100: re-runnable)
--   * select count(*) from public.world_config                                              = 291  (unchanged after)
--   * select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public','cmd','world','voyage')
--       and p.prosrc like '%standing_route_lap_keep%'                                        = 1    (cmd.standing_route_close_lap, the only reader)
--
-- ── SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────────
--   (a) the knob reads exactly 100 (jsonb number; wc_int and wc_num agree), and its sibling standing_route_lap_trades_keep still reads 7;
--   (b) EVERY OTHER world_config row is unmoved: one md5 over key, value, description and updated_at of every row but this one, and the row count;
--   (c) the closer is still the only reader and still trims per route by lap_no against the knob (its live text, once); every function in
--       public / cmd / world / voyage is md5-unmoved (count and one md5 by identity);
--   (d) the registry, the walls (0 / 0 / 0) and both owner switches as found;
--   (e) this backend made no scan, no fetch, no insert, no update and no delete on public.standing_route_laps or any of its indexes (pg_stat_get_xact_*,
--       before = after inside the block: they count what the block itself did, whichever scan the planner chose).
--   Printed, never asserted: the elapsed time. Run against 14 deliberate breakages of this file and a knob at 150 on a populated local world (docs/dev-log): each fails, for the intended reason.
-- ROLLBACK (forward, a NEW migration): set the knob back to 200 (rows already trimmed do not come back).
-- VERSION: 0301 — prod head 0300 (the hourly reconcile, deployed 2026-11-01); deploys AFTER 0300, one migration at a time.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. GUARD ────────────────────────────────────────────────────────────────────────────────────
-- The timeouts come FIRST. The knob must read exactly 200 - or already 100, so an earlier push of this very file that died after the update (it cannot:
-- the update and its asserts are one block) or a second run finds the row where it was left. Any other value means the owner moved it since: refuse.
do $guard$
declare
  v_keep jsonb;
begin
  perform set_config('statement_timeout', '90s', false);   -- the push pauses every cron job while it runs: 90 s is the most this file may take
  perform set_config('lock_timeout', '5s', false);
  if to_regclass('public.world_config') is null
     or to_regclass('public.standing_route_laps') is null
     or to_regprocedure('cmd.standing_route_close_lap(uuid,timestamptz)') is null
     or to_regprocedure('public.wc_int(text)') is null then
    raise exception '0301 refuses: the knob table, the laps table or the lap closer is not in this world';
  end if;
  select c.value into v_keep from public.world_config c where c.key = 'standing_route_lap_keep';
  if not found then
    raise exception '0301 refuses: world_config has no standing_route_lap_keep';
  end if;
  if v_keep is distinct from to_jsonb(200) and v_keep is distinct from to_jsonb(100) then
    raise exception '0301 refuses: standing_route_lap_keep reads % - this file moves 200 to 100 and nothing else (the owner changed it since?)', v_keep;
  end if;
end $guard$;

-- ── 1. THE UPDATE AND THE SELF-ASSERT: ONE block, so a failed assert keeps nothing of this file ───
do $main$
declare
  c_key    constant text := 'standing_route_lap_keep';
  c_laps   constant oid := 'public.standing_route_laps'::regclass::oid;
  v_t0     timestamptz := clock_timestamp();
  v_before jsonb;
  v_n      int;
  v_rows0  bigint;
  v_oth0   text;
  v_nfn0   bigint;
  v_fns0   text;
  v_entry  bigint;
  v_econ   jsonb;
  v_city   jsonb;
  v_laps0  bigint;
  v_def    text;
  v_readers text[];
  v_moved  boolean := false;
begin
  -- ── AS FOUND ──────────────────────────────────────────────────────────────────────────────────
  select c.value into v_before from public.world_config c where c.key = c_key;
  select count(*) into v_rows0 from public.world_config;
  select md5(string_agg(c.key || '=' || c.value::text || '|' || c.description || '|' || c.updated_at::text, E'\n' order by c.key collate "C"))
    into v_oth0 from public.world_config c where c.key <> c_key;
  select count(*), md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_nfn0, v_fns0
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select count(*) into v_entry from public.client_rpc_entry_points();
  select c.value into v_econ from public.world_config c where c.key = 'economy_closed';
  select c.value into v_city from public.world_config c where c.key = 'city_treasury_enabled';
  -- this backend's own counters on the laps table AND its indexes so far (a file that never touches them leaves the sum where it is): scans, tuples
  -- returned and fetched on the table and on every index (an index scan or an index-only read counts on the index, not on the table), and the
  -- table's inserts, updates and deletes
  v_laps0 := (select coalesce(sum(coalesce(pg_stat_get_xact_numscans(x.o), 0) + coalesce(pg_stat_get_xact_tuples_returned(x.o), 0)
                                  + coalesce(pg_stat_get_xact_tuples_fetched(x.o), 0)
                                  + case when x.o = c_laps then coalesce(pg_stat_get_xact_tuples_inserted(x.o), 0) + coalesce(pg_stat_get_xact_tuples_updated(x.o), 0)
                                                                 + coalesce(pg_stat_get_xact_tuples_deleted(x.o), 0) else 0 end), 0)
                from (select c_laps as o union all select i.indexrelid from pg_index i where i.indrelid = c_laps) x);

  -- ── THE ONE UPDATE ────────────────────────────────────────────────────────────────────────────
  if v_before = to_jsonb(200) then
    update public.world_config
       set value       = to_jsonb(100),
           description = '0092: how many lap rows are kept per route; older laps are pruned at each lap close (cmd.standing_route_close_lap, the only reader). 30 at 0092, 200 at 0097, 100 at 0301 (owner, 2026-11-02: "route lap history - we actually don''t need this. 100 would be good").',
           updated_at  = now()
     where key = c_key and value = to_jsonb(200);
    get diagnostics v_n = row_count;
    if v_n <> 1 then
      raise exception '0301 self-assert FAIL: the update moved % row(s), not exactly the one knob', v_n;
    end if;
    v_moved := true;
  else
    raise notice '0301: standing_route_lap_keep already reads 100 - not moved again (an earlier run of this file got this far)';
  end if;

  -- ── (a) THE KNOB ──────────────────────────────────────────────────────────────────────────────
  if (select c.value from public.world_config c where c.key = c_key) is distinct from to_jsonb(100)
     or jsonb_typeof((select c.value from public.world_config c where c.key = c_key)) <> 'number'
     or public.wc_int(c_key) <> 100 or public.wc_num(c_key) <> 100 then
    raise exception '0301 self-assert FAIL: standing_route_lap_keep does not read exactly 100 (%)', (select c.value from public.world_config c where c.key = c_key);
  end if;
  if public.wc_int('standing_route_lap_trades_keep') <> 7 then
    raise exception '0301 self-assert FAIL: the sibling knob standing_route_lap_trades_keep moved (reads %)', public.wc_int('standing_route_lap_trades_keep');
  end if;

  -- ── (b) EVERY OTHER KNOB ROW UNMOVED ──────────────────────────────────────────────────────────
  if (select count(*) from public.world_config) <> v_rows0 then
    raise exception '0301 self-assert FAIL: the number of world_config rows changed (% -> %)', v_rows0, (select count(*) from public.world_config);
  end if;
  if (select md5(string_agg(c.key || '=' || c.value::text || '|' || c.description || '|' || c.updated_at::text, E'\n' order by c.key collate "C"))
        from public.world_config c where c.key <> c_key) is distinct from v_oth0 then
    raise exception '0301 self-assert FAIL: a world_config row other than standing_route_lap_keep moved';
  end if;

  -- ── (c) THE CLOSER IS THE ONLY READER AND STILL TRIMS PER ROUTE; NO FUNCTION MOVED ───────────
  select array_agg(n.nspname || '.' || p.proname order by n.nspname, p.proname) into v_readers
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%standing_route_lap_keep%';
  if v_readers is distinct from array['cmd.standing_route_close_lap'] then
    raise exception '0301 self-assert FAIL: the readers of the knob are %, not the lap closer alone', v_readers;
  end if;
  v_def := replace(pg_get_functiondef('cmd.standing_route_close_lap(uuid,timestamptz)'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, 'public.wc_int(''standing_route_lap_keep'')', ''))) / length('public.wc_int(''standing_route_lap_keep'')') <> 1
     or position('delete from public.standing_route_laps x
   where x.route_id = p_route and x.lap_no <= l.lap_no - public.wc_int(''standing_route_lap_keep'');' in v_def) = 0 then
    raise exception '0301 self-assert FAIL: the lap closer no longer trims one route at a time against the knob, once - the lazy trim this file relies on is not there';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_nfn0
     or (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) is distinct from v_fns0 then
    raise exception '0301 self-assert FAIL: a function in public/cmd/world/voyage moved, appeared or vanished';
  end if;

  -- ── (d) THE REGISTRY, THE WALLS, BOTH OWNER SWITCHES AS FOUND ─────────────────────────────────
  if (select count(*) from public.client_rpc_entry_points()) <> v_entry
     or (select c.value from public.world_config c where c.key = 'economy_closed') is distinct from v_econ
     or (select c.value from public.world_config c where c.key = 'city_treasury_enabled') is distinct from v_city then
    raise exception '0301 self-assert FAIL: the registry or an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0301 self-assert FAIL: a wall moved';
  end if;

  -- ── (e) NO LAP ROW WAS READ OR WRITTEN ────────────────────────────────────────────────────────
  if (select coalesce(sum(coalesce(pg_stat_get_xact_numscans(x.o), 0) + coalesce(pg_stat_get_xact_tuples_returned(x.o), 0)
                          + coalesce(pg_stat_get_xact_tuples_fetched(x.o), 0)
                          + case when x.o = c_laps then coalesce(pg_stat_get_xact_tuples_inserted(x.o), 0) + coalesce(pg_stat_get_xact_tuples_updated(x.o), 0)
                                                         + coalesce(pg_stat_get_xact_tuples_deleted(x.o), 0) else 0 end), 0)
        from (select c_laps as o union all select i.indexrelid from pg_index i where i.indrelid = c_laps) x) <> v_laps0 then
    raise exception '0301 self-assert FAIL: this file touched public.standing_route_laps or one of its indexes (a scan, fetch, insert, update or delete)';
  end if;

  raise notice '0301 self-assert ok: THE LAP HISTORY IS 100. public.world_config standing_route_lap_keep % -> 100 (jsonb number; wc_int and wc_num read 100; moved by this run: %); its sibling standing_route_lap_trades_keep still 7; the other % world_config rows unmoved (one md5 over key, value, description and updated_at, before = after); the lap closer cmd.standing_route_close_lap is the only function that names the knob and still trims one route at a time by lap_no (each route trims itself to its newest 100 laps at its NEXT close - no purge here); all % functions in public/cmd/world/voyage md5-unmoved; registry % entry points, walls 0 / 0 / 0, economy_closed and city_treasury_enabled as found; public.standing_route_laps and its indexes not scanned, fetched, inserted, updated or deleted by this block. Printed, never asserted: % ms.',
    v_before, v_moved, v_rows0 - 1, v_nfn0, v_entry, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $main$;

reset statement_timeout;
reset lock_timeout;
