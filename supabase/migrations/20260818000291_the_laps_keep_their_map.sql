-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0291 — THE LAPS KEEP THEIR MAP   (a LOAD-ONLY slice: one table's autovacuum is told to keep up; no row, function or value moves)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY (prod, read-only, head 0290, 2026-11-01 14:50–15:05 UTC) ───────────────────────────────
-- The Stats count (public.tick_stats, 0290) STILL failed on its first run after 0290: 14:51:00, 120.7 s, `canceling statement
-- due to statement timeout` inside public.stats_merchants_window — and it is not the backlog 0290 bounds. Timed read-only, phase by
-- phase, on the saturated database: the count's windowed reads cost 0–4 s each (totals, founded, goods, cities, city goods over
-- 120 min), but `public.stats_merchants_window(now() - 24 h, now())` ran past 115 s ALONE. It is a fixed-size read (the closed laps of
-- the last 24 hours, ~36,000 of them) and it was ~12 s on 2026-10-30.
--   The plan is right: an Index Only Scan on standing_route_laps_window (0287's covering partial index). The scan is not index-only:
--   EXPLAIN (ANALYZE, BUFFERS) on the plain lap read, 1 hour:  rows 833, Heap Fetches 833;  3 hours: rows 3,222, Heap Fetches 3,264.
--   EVERY row costs a random heap read, because the table's visibility map covers only 63.5 % of its pages (18,461 of 29,094
--   all-visible) and none of the recent laps' pages. Why: a lap row is inserted when the lap starts and UPDATED when it closes
--   (closed_at, net — closed_at is the indexed key, so the update is never HOT), ~1,500 laps an hour; the table has the DEFAULT autovacuum
--   thresholds (50 + 20 % of 167,305 rows = 33,511 dead rows, or 34,461 inserts), so it was last vacuumed at 11:17 UTC, hours ago, and
--   every page touched since is unmapped. 36,000 random reads on a disk this saturated is the 115 s.
-- THE REST OF THE CHAIN ALREADY KNOWS THIS: events, ledger, voyages, voyage_events and price_history all carry
--   `autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000..2000` (0224 / 0226 / 0275) and are 97–100 % all-visible, vacuumed
--   minutes ago. standing_route_laps — 355 MB, the table the count's merchants window and every lap-close reads — was left on the defaults.
--
-- ── WHAT CHANGES (one statement) ────────────────────────────────────────────────────────────────
--   alter table public.standing_route_laps set (
--     autovacuum_vacuum_scale_factor = 0,        autovacuum_vacuum_threshold = 500,          -- a vacuum per ~500 dead rows (~20 min of closes)
--     autovacuum_vacuum_insert_scale_factor = 0, autovacuum_vacuum_insert_threshold = 500,   -- and per ~500 inserts: new pages get mapped too
--     autovacuum_analyze_scale_factor = 0,       autovacuum_analyze_threshold = 2000);       -- the planner's counts stay current
-- A vacuum of this table skips every page already marked all-visible, so once the map is fresh each run reads only the pages touched since
-- the last one (hundreds, not 29,094). The first run, which starts within a minute of the commit (the table already has ~20,000 dead rows),
-- reads the ~10,600 unmapped pages once and sets their bits: after it the 24 h lap read is index-only for every page but the newest.
-- ALTER TABLE … SET (reloption) takes SHARE UPDATE EXCLUSIVE and rewrites nothing; no row moves, no lock beyond a running vacuum's.
--
-- ── WHAT DOES NOT MOVE ──────────────────────────────────────────────────────────────────────────
-- No function body, row, column, index, grant, knob, switch, schedule or cron job; no other table's options. Asserted below: the md5 of every
-- function in public/cmd/world/voyage, the registry count, the walls (0/0/0), both owner switches, and every OTHER table's reloptions as found.
--
-- ── SELF-ASSERT (catalog only; nothing is written but the one option set) ────────────────────────
--   (a) the guard: a permanent table; it carries no autovacuum option yet (this has been applied once otherwise);
--   (b) the six options are on the table with exactly these values (read from pg_class.reloptions);
--   (c) every OTHER table in public keeps its reloptions (an md5 over name + options, before = after), and no index of the table moved;
--   (d) every function unmoved by md5, the registry, the walls and the two switches as found.
--   Printed, never asserted: the table's pages, its all-visible share and dead rows at the moment of the commit (the after-check compares).
-- ROLLBACK (forward, a NEW migration, never an edit): alter table public.standing_route_laps reset (autovacuum_vacuum_scale_factor,
--   autovacuum_vacuum_threshold, autovacuum_vacuum_insert_scale_factor, autovacuum_vacuum_insert_threshold,
--   autovacuum_analyze_scale_factor, autovacuum_analyze_threshold);
-- VERSION: 0291 — prod head 0290 today. It deploys FIRST of the queued migrations (it unblocks the Stats count); the port_goods rewrite is 0292.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. GUARD ────────────────────────────────────────────────────────────────────────────────────
do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '10s', true);
  if not exists (select 1 from pg_class c
                  where c.oid = to_regclass('public.standing_route_laps') and c.relkind = 'r' and c.relpersistence = 'p') then
    raise exception '0291 refuses: public.standing_route_laps (a permanent table) is not in this world';
  end if;
  if exists (select 1 from pg_class c, unnest(c.reloptions) o
              where c.oid = 'public.standing_route_laps'::regclass and o like 'autovacuum%') then
    raise exception '0291 refuses: public.standing_route_laps already carries autovacuum options — this has been applied once';
  end if;
end $guard$;

-- ── 1. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table before_0291 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns_md5,
       (select value from public.world_config where key = 'economy_closed') as economy_closed,
       (select value from public.world_config where key = 'city_treasury_enabled') as city_treasury_enabled,
       (select md5(string_agg(c.relname || '=' || coalesce(c.reloptions::text, ''), ',' order by c.relname collate "C"))
          from pg_class c
         where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'm', 'i')
           and c.oid <> 'public.standing_route_laps'::regclass) as other_options_md5,
       (select md5(string_agg(pg_get_indexdef(i.indexrelid), ',' order by i.indexrelid::regclass::text collate "C"))
          from pg_index i where i.indrelid = 'public.standing_route_laps'::regclass) as laps_indexes_md5;

-- ── 2. THE CHANGE ───────────────────────────────────────────────────────────────────────────────
alter table public.standing_route_laps set (
  autovacuum_vacuum_scale_factor = 0,
  autovacuum_vacuum_threshold = 500,
  autovacuum_vacuum_insert_scale_factor = 0,
  autovacuum_vacuum_insert_threshold = 500,
  autovacuum_analyze_scale_factor = 0,
  autovacuum_analyze_threshold = 2000);

comment on table public.standing_route_laps is
  '0291: autovacuum keeps this table''s visibility map fresh (a vacuum per ~500 dead rows or inserts): the Stats count''s 24 h merchants window reads ~36,000 closed laps through the covering index standing_route_laps_window, and an index-only scan of an unmapped page is a heap fetch each.';

-- ── 3. THE SELF-ASSERT (the last statement of the file) ─────────────────────────────────────────
do $assert$
declare
  f      record;
  v_opts text[];
  v_want text[] := array['autovacuum_vacuum_scale_factor=0', 'autovacuum_vacuum_threshold=500',
                         'autovacuum_vacuum_insert_scale_factor=0', 'autovacuum_vacuum_insert_threshold=500',
                         'autovacuum_analyze_scale_factor=0', 'autovacuum_analyze_threshold=2000'];
  v_pages int;
  v_vis   int;
  v_dead  bigint;
begin
  select * into f from before_0291;

  -- (b) the six options, exactly
  select c.reloptions into v_opts from pg_class c where c.oid = 'public.standing_route_laps'::regclass;
  if v_opts is null or not (v_opts @> v_want and v_want @> v_opts) then
    raise exception '0291 self-assert FAIL: public.standing_route_laps carries % , not exactly %', v_opts, v_want;
  end if;

  -- (c) nothing else about tables moved
  if (select md5(string_agg(c.relname || '=' || coalesce(c.reloptions::text, ''), ',' order by c.relname collate "C"))
        from pg_class c
       where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'm', 'i')
         and c.oid <> 'public.standing_route_laps'::regclass) is distinct from f.other_options_md5 then
    raise exception '0291 self-assert FAIL: another relation''s options moved — this file sets the options of one table';
  end if;
  if (select md5(string_agg(pg_get_indexdef(i.indexrelid), ',' order by i.indexrelid::regclass::text collate "C"))
        from pg_index i where i.indrelid = 'public.standing_route_laps'::regclass) is distinct from f.laps_indexes_md5 then
    raise exception '0291 self-assert FAIL: an index of public.standing_route_laps moved';
  end if;

  -- (d) nothing else moved
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> f.fns
     or (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> f.fns_md5 then
    raise exception '0291 self-assert FAIL: a function in public/cmd/world/voyage moved or was added — this file creates and changes none';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> f.entry_points
     or (select value from public.world_config where key = 'economy_closed') is distinct from f.economy_closed
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from f.city_treasury_enabled then
    raise exception '0291 self-assert FAIL: the registry or an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0291 self-assert FAIL: a wall moved';
  end if;

  select c.relpages, c.relallvisible, coalesce(s.n_dead_tup, 0)
    into v_pages, v_vis, v_dead
    from pg_class c left join pg_stat_user_tables s on s.relid = c.oid
   where c.oid = 'public.standing_route_laps'::regclass;

  raise notice '0291 self-assert ok: THE LAPS KEEP THEIR MAP. public.standing_route_laps now carries exactly the six autovacuum options % (a vacuum per ~500 dead rows, a vacuum per ~500 inserts, the planner''s counts every 2,000 changes). Every other relation''s options and every index of this table are as found; every function in public/cmd/world/voyage is unmoved by md5 (% functions), the registry unchanged at % entry points, the walls 0 / 0 / 0, both owner switches as found. Printed, never asserted: at the commit the table has % pages of which % are marked all-visible (% %), % dead rows — the after-check compares them.',
    v_want, f.fns, f.entry_points, v_pages, v_vis,
    case when v_pages > 0 then round(100.0 * v_vis / v_pages, 1)::text else 'n/a' end, '%', v_dead;
end $assert$;
