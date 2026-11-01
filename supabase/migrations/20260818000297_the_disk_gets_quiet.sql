-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0297 — THE DISK GETS QUIET   (a LOAD-ONLY slice: one table stops being re-read for nothing, one bloated table is rewritten compact;
--                               no row, function, knob, switch, cron job or schedule moves)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY (prod, read-only, head 0294, 2026-11-01 18:14–19:05 UTC; PG 17.6, Micro compute, shared_buffers 256 MB, up since 09:34) ──
-- The database is I/O-bound and code cannot add IOPS, so this removes reads the database does to itself. The brief's pg_stat_io readings (18:14–18:20, 150 s apart):
-- 20.7 k blocks a minute read from disk, 69 % of them by AUTOVACUUM workers (14.25 k), 6.4 k by client backends; 10.8 k written.
-- Per table (pg_statio_user_tables, two snapshots 547 s apart, 18:32:17 → 18:41:23, one Stats count inside): 402,466 block reads of tables and their
-- indexes, 44 k a minute. The largest shares:
--   standing_route_laps 25 %  — LEFT ALONE: 0291's options are what keep its visibility map fresh for the Stats count's index-only scans
--   port_goods          21 %  — 84,435 reads: 8 autovacuum and 6 autoanalyze passes in 9 minutes, beside 1,547,576 updates, every one of them HOT
--   voyages              9 %  — 36,559 reads (one vacuum, one analyze); 70,478 in the next 11 minutes (two vacuums)
--
-- ── port_goods: WHY THE PASSES BUY NOTHING ─────────────────────────────────────────────────────
-- 154,734 rows in 14,374 pages (112 MB, fillfactor 30 since 0292), updated ~154 k times a minute by the every-minute market. EVERY update is in-page (HOT):
-- 309,481 of 309,481 in a 53 s window, 1,547,576 of 1,547,576 in 9 minutes. A HOT update writes no index entry and the pruning that runs on the next visit to
-- the page removes the old version, so there is nothing for VACUUM to remove; the pages it marks all-visible are written again within the minute; and the planner
-- statistics it refreshes serve primary-key lookups that do not depend on them. Yet autovacuum has started on it 369 times and autoanalyze 305 times since the
-- restart (23 and 20 of them in the last 30 minutes), each pass reading 6–14 k of its 14,374 pages. WHY it never rests: n_dead_tup is the number of dead versions
-- NET OF PRUNING (heap_page_prune subtracts what it reclaims), so it stands at about one market pass and never falls under the default trigger
-- (50 + 0.2 × 154,734 = 30,997). Traced for 14 minutes (72 samples, 18:51-19:06) it ran 113,345 .. 254,846 between vacuums (0 right after one), and across the pass of 18:52:26 — 154,734 rows updated — it rose
-- by only 73,125, because the pass pruned ~81,600 of the previous pass's versions on its way. The table is above the line ALL THE TIME, so a pass begins as soon as
-- the last one ends.
--
-- ── voyages: WHY IT IS REWRITTEN ───────────────────────────────────────────────────────────────
-- 25,372 pages (198 MB) for 22.7–25.2 k live rows (the brief's count: 24,932 ARRIVED history, 359 SAILING, 156 ABORTED; the live count FALLS ~80 a minute, ~156 deleted
-- against ~70 inserted) whose column widths (pg_stats) sum to ~980 B a row, ~26 MB, ~3,200 pages: 8x bloat. Its four indexes hold 3,019 pages for ~25 k entries (the
-- primary key 1,221 pages where ~90 would do, voyages_fleet_ended_0249 1,759 where ~110 would). Every autoanalyze reads the whole heap (its 30,000-row sample is larger
-- than the table) and every autovacuum a heap pass and the four index passes: 77 vacuums and 30 analyzes since the restart, 5 and 5 of them in the last 30 minutes,
-- 70,478 block reads in the 11 minutes polled. The rewrite is CLUSTER on the primary key because that is the only FULL index (the other three are partial, and CLUSTER
-- refuses a partial index).
--
-- ── NOT IN THIS FILE ──────────────────────────────────────────────────────────────────────────
-- public.price_history_hour: the brief called it ~19x bloated ("~14 k live rows"). It is not: 246,321 rows in 3,697 pages (66 a page, 174 hours of history). The 14,300
-- was n_live_tup, which restarted from 0 at 09:34 (no vacuum or analyze has run on the table since). Left as it is. Likewise every table that has its own options.
--
-- ── WHAT CHANGES ───────────────────────────────────────────────────────────────────────────────
--   A. alter table public.port_goods set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000000,
--                                         autovacuum_analyze_scale_factor = 0, autovacuum_analyze_threshold = 4500000);
--      fillfactor = 30 stays (ALTER … SET adds to a table's options, it does not replace them — asserted). The two numbers differ ON PURPOSE:
--      • ANALYZE counts every change, HOT or not (n_mod_since_analyze rose by 154,734 in one pass: 154,857 → 309,591). 4,500,000 is 29 minutes of the market:
--        one analyze every ~29 minutes instead of one every ~1.5. The statistics are static (a fixed catalogue of 246 ports × 629 goods).
--      • VACUUM counts dead versions net of pruning, which has not passed ~255 k (one more pass pinned by a long snapshot would add 154,734). A threshold of "30 minutes
--        of updates" (4.5 M) could never be reached — it would switch the vacuum off, and a pin or a non-HOT leak (each leaves dead index entries that only a vacuum clears)
--        would pile up unseen. 1,000,000 is 3.9x the highest routine reading: routine churn never trips it; a real leak trips it within ~5 market passes. Expected: no routine pass.
--   B. public.voyages is rewritten in place: lock table … in access exclusive mode; the rows read; cluster public.voyages using voyages_pkey; the rows read again.
--      Its own options (autovacuum scale factor 0, threshold 2000) stay as they are (asserted). Expected: ~3,200 pages (~25 MB), indexes ~2 MB, from 198 MB and 24 MB.
--
-- ── ANTI-WRAPAROUND IS NOT AFFECTED BY ANY OF THIS ─────────────────────────────────────────────
-- autovacuum starts a freeze pass on any table whose age(relfrozenxid) passes autovacuum_freeze_max_age (200,000,000) whatever its thresholds say: in
-- relation_needs_vacanalyze the force_vacuum flag sets dovacuum before the thresholds are read. Measured: age(relfrozenxid) of port_goods 1,429–4,880 (the 1.5-minute
-- passes keep it near 0 — the only thing they buy), the oldest age in the database 14.5 M (the system catalogs), xids consumed at 16.8 a second (30,424 in 1,813 s,
-- 18:26:18 → 18:56:31; 1.45 M a day). With no regular pass at all port_goods reaches 200,000,000 in 138 days and a freeze pass then starts by itself, 1.9 billion xids
-- short of wraparound (3.7 years at this rate; the failsafe is at 1.6 billion). Multixacts: ~10 a second (9.4-11.1 in three windows) against a limit of 400,000,000 — ~450 days.
--
-- ── THE LOCK, AND WHAT A PLAYER SEES ──────────────────────────────────────────────────────────
-- CLUSTER holds ACCESS EXCLUSIVE on voyages from the first read to the commit (everything else in this file is catalog-light). The same statement on port_goods in 0292 took
-- 42.72 s on this disk (pg_stat_statements: 42,944 blocks = 336 MB read from a 307 MB heap, 122 MB written: ~11 MB/s of data, ~14 MB/s with the WAL). voyages is 198 MB and
-- writes a quarter as much, so expect ~15–30 s of lock on a saturated disk (40 s as the pessimistic bound), 2–5 s if the disk is bursting. A request that touches voyages WAITS for the lock — anon is cut at 3 s,
-- authenticated and authenticator at 8 s — and fails with a timeout after that; a request that does not touch voyages is unaffected. The deploy (bv-deploy.sh) unwinds the clock
-- first, so no beat or count queues behind it. lock_timeout is 10 s: a lock that cannot be had is refused and rolled back clean, and the file is simply deployed again.
-- Everything after the as-found reads is ONE DO block, so ONE transaction in every runner (the runner is not a transaction block: a top-level LOCK TABLE is refused there, and a
-- statement boundary may end the implicit transaction): the change commits whole or not at all, and a failed run is simply run again.
--
-- ── SELF-ASSERT (all in the one DO block; nothing is written but the changes themselves) ──────────
--   (a) public.port_goods carries fillfactor=30 and the four new options, exactly those five;
--   (b) public.voyages: the SAME ROWS — count, min / max of id and sum(hashtext(id)) before and after, both read under the lock (exact: the lock is held from before the first read);
--   (c) the heap was rewritten (a new relfilenode), never grew by more than a page, and a heap of 4,000 pages (32 MB) or more is at least HALVED;
--   (d) the four indexes: the same set with the same definitions, valid / ready / live, EVERY ONE rebuilt (a new relfilenode), the primary key marked clustered;
--   (e) public.voyages keeps its own options, its constraints, the foreign keys in and out, and its trigger;
--   (f) every OTHER relation's options, every function in public/cmd/world/voyage (md5), the registry, the walls (0/0/0) and both owner switches as found.
--   Printed, never asserted: the heap and index sizes before and after, the age of port_goods' relfrozenxid, the seconds under the lock. The chain's own world has an EMPTY voyages (0 rows,
--   346 dead pages), so CI proves the mechanism (lock, CLUSTER inside a DO block, the rebuilds, the options) and prod proves the row identity at 25 k rows under the lock.
-- ROLLBACK (forward, a NEW migration, never an edit): alter table public.port_goods reset (autovacuum_vacuum_scale_factor, autovacuum_vacuum_threshold,
--   autovacuum_analyze_scale_factor, autovacuum_analyze_threshold); — the voyages rewrite is not undone and needs no undo (a compact table is the goal; CLUSTER again if it bloats again).
-- VERSION: 0297 — prod head 0294 today. 0295 (stats-period) and 0296 (reconcile-wall) are other branches' migrations and deploy first; this file deploys AFTER 0296.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. GUARD ────────────────────────────────────────────────────────────────────────────────────
do $guard$
begin
  perform set_config('statement_timeout', '10min', false);
  perform set_config('lock_timeout', '10s', false);
  if not exists (select 1 from pg_class c
                  where c.oid = to_regclass('public.port_goods') and c.relkind = 'r' and c.relpersistence = 'p')
     or not exists (select 1 from pg_class c
                     where c.oid = to_regclass('public.voyages') and c.relkind = 'r' and c.relpersistence = 'p') then
    raise exception '0297 refuses: public.port_goods or public.voyages (a permanent table) is not in this world';
  end if;
  if to_regclass('public.voyages_pkey') is null
     or not exists (select 1 from pg_index i
                     where i.indexrelid = 'public.voyages_pkey'::regclass and i.indrelid = 'public.voyages'::regclass
                       and i.indisprimary and i.indisvalid and i.indisready) then
    raise exception '0297 refuses: voyages_pkey is not the valid primary key of public.voyages';
  end if;
  if not exists (select 1 from pg_class c
                  where c.oid = 'public.port_goods'::regclass and c.reloptions @> array['fillfactor=30']) then
    raise exception '0297 refuses: public.port_goods does not carry fillfactor=30 — 0292 has not been applied';
  end if;
end $guard$;

-- ── 1. THE CHANGE AND ITS SELF-ASSERT: ONE DO BLOCK, the last statement of the file that does work ─
do $assert$
declare
  -- the world as found (catalog reads only, taken before any change and before the lock)
  v_entry_points   int;
  v_fns            int;
  v_fns_md5        text;
  v_economy        jsonb;
  v_treasury       jsonb;
  v_other_opts_md5 text;
  v_voy_opts       text[];
  v_voy_rel_md5    text;
  v_pg_opts        text[];
  v_pg_want        text[] := array['fillfactor=30',
                                   'autovacuum_vacuum_scale_factor=0', 'autovacuum_vacuum_threshold=1000000',
                                   'autovacuum_analyze_scale_factor=0', 'autovacuum_analyze_threshold=4500000'];
  v_pg_age         int;
  -- public.voyages under its lock
  v_block          int := current_setting('block_size')::int;
  v_n_b            bigint;
  v_min_b          text;
  v_max_b          text;
  v_sum_b          bigint;
  v_file_b         oid;
  v_heap_b         bigint;
  v_idxb_b         bigint;
  v_ix_defs_b      text;
  v_ix_names_b     text[];
  v_ix_files_b     oid[];
  v_n_a            bigint;
  v_min_a          text;
  v_max_a          text;
  v_sum_a          bigint;
  v_file_a         oid;
  v_heap_a         bigint;
  v_idxb_a         bigint;
  v_ix_defs_a      text;
  v_ix_names_a     text[];
  v_ix_files_a     oid[];
  v_ix_bad         int;
  v_clustered      boolean;
  v_voy_opts_a     text[];
  v_voy_rel_md5_a  text;
  v_t_lock         timestamptz;
  v_t_start        timestamptz;
  v_t_done         timestamptz;
  v_t_end          timestamptz;
begin
  -- AS FOUND (no lock yet)
  select count(*) into v_entry_points from public.client_rpc_entry_points();
  select count(*), md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fns, v_fns_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select value into v_economy from public.world_config where key = 'economy_closed';
  select value into v_treasury from public.world_config where key = 'city_treasury_enabled';
  select md5(string_agg(c.relname || '=' || coalesce(c.reloptions::text, ''), ',' order by c.relname collate "C"))
    into v_other_opts_md5
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'm', 'i')
     and c.oid <> 'public.port_goods'::regclass;
  select c.reloptions into v_voy_opts from pg_class c where c.oid = 'public.voyages'::regclass;
  -- what hangs on public.voyages besides its rows: its constraints and the foreign keys that reference it, and its triggers
  select md5(coalesce((select string_agg(k.conrelid::regclass::text || '.' || k.conname || '=' || pg_get_constraintdef(k.oid), ',' order by k.conrelid::regclass::text, k.conname)
                         from pg_constraint k
                        where k.conrelid = 'public.voyages'::regclass or k.confrelid = 'public.voyages'::regclass), '')
              || '|' ||
              coalesce((select string_agg(t.tgname || '=' || pg_get_triggerdef(t.oid), ',' order by t.tgname)
                          from pg_trigger t where t.tgrelid = 'public.voyages'::regclass and not t.tgisinternal), ''))
    into v_voy_rel_md5;

  -- A. public.port_goods: autovacuum and autoanalyze stop re-reading a table whose updates are all in-page (fillfactor 30 stays)
  alter table public.port_goods set (
    autovacuum_vacuum_scale_factor = 0,
    autovacuum_vacuum_threshold = 1000000,
    autovacuum_analyze_scale_factor = 0,
    autovacuum_analyze_threshold = 4500000);
  comment on table public.port_goods is
    '0297: no routine autovacuum — every update of this table is in-page (HOT, fillfactor 30), so a pass finds nothing to remove. The vacuum trigger (1,000,000 dead versions, counted net of pruning) is a safety net, the analyze trigger (4,500,000 changes, ~29 minutes of the market) keeps the planner''s counts; anti-wraparound autovacuum ignores both.';

  -- B. public.voyages: rewritten compact in place. The lock, the rows read before, the rewrite and the rows read after are ONE transaction
  --    here (the runner is not a transaction block: nothing that needs the lock may sit outside this block).
  lock table public.voyages in access exclusive mode;
  v_t_lock := clock_timestamp();

  select count(*), min(id::text), max(id::text), coalesce(sum(hashtext(id::text)::bigint), 0)
    into v_n_b, v_min_b, v_max_b, v_sum_b
    from public.voyages;
  select c.relfilenode, pg_relation_size(c.oid), pg_indexes_size(c.oid)
    into v_file_b, v_heap_b, v_idxb_b
    from pg_class c where c.oid = 'public.voyages'::regclass;
  select md5(string_agg(i.indexrelid::regclass::text || '=' || pg_get_indexdef(i.indexrelid), E'\n' order by i.indexrelid::regclass::text collate "C")),
         array_agg(i.indexrelid::regclass::text order by i.indexrelid::regclass::text collate "C"),
         array_agg(ic.relfilenode order by i.indexrelid::regclass::text collate "C")
    into v_ix_defs_b, v_ix_names_b, v_ix_files_b
    from pg_index i join pg_class ic on ic.oid = i.indexrelid
   where i.indrelid = 'public.voyages'::regclass;

  v_t_start := clock_timestamp();
  cluster public.voyages using voyages_pkey;
  v_t_done := clock_timestamp();

  select count(*), min(id::text), max(id::text), coalesce(sum(hashtext(id::text)::bigint), 0)
    into v_n_a, v_min_a, v_max_a, v_sum_a
    from public.voyages;
  select c.relfilenode, pg_relation_size(c.oid), pg_indexes_size(c.oid)
    into v_file_a, v_heap_a, v_idxb_a
    from pg_class c where c.oid = 'public.voyages'::regclass;
  select md5(string_agg(i.indexrelid::regclass::text || '=' || pg_get_indexdef(i.indexrelid), E'\n' order by i.indexrelid::regclass::text collate "C")),
         array_agg(i.indexrelid::regclass::text order by i.indexrelid::regclass::text collate "C"),
         array_agg(ic.relfilenode order by i.indexrelid::regclass::text collate "C"),
         count(*) filter (where not (i.indisvalid and i.indisready and i.indislive))
    into v_ix_defs_a, v_ix_names_a, v_ix_files_a, v_ix_bad
    from pg_index i join pg_class ic on ic.oid = i.indexrelid
   where i.indrelid = 'public.voyages'::regclass;
  select i.indisclustered into v_clustered from pg_index i where i.indexrelid = 'public.voyages_pkey'::regclass;
  select c.reloptions into v_voy_opts_a from pg_class c where c.oid = 'public.voyages'::regclass;
  select md5(coalesce((select string_agg(k.conrelid::regclass::text || '.' || k.conname || '=' || pg_get_constraintdef(k.oid), ',' order by k.conrelid::regclass::text, k.conname)
                         from pg_constraint k
                        where k.conrelid = 'public.voyages'::regclass or k.confrelid = 'public.voyages'::regclass), '')
              || '|' ||
              coalesce((select string_agg(t.tgname || '=' || pg_get_triggerdef(t.oid), ',' order by t.tgname)
                          from pg_trigger t where t.tgrelid = 'public.voyages'::regclass and not t.tgisinternal), ''))
    into v_voy_rel_md5_a;

  -- THE SELF-ASSERT
  -- (a) public.port_goods carries fillfactor=30 and exactly the four new options, nothing else
  select c.reloptions, age(c.relfrozenxid) into v_pg_opts, v_pg_age from pg_class c where c.oid = 'public.port_goods'::regclass;
  if v_pg_opts is null or not (v_pg_opts @> v_pg_want and v_pg_want @> v_pg_opts) then
    raise exception '0297 self-assert FAIL: public.port_goods carries %, not exactly %', v_pg_opts, v_pg_want;
  end if;

  -- (b) public.voyages: the SAME ROWS (exact: this transaction holds the table's ACCESS EXCLUSIVE lock from before the first read)
  if v_n_a is distinct from v_n_b or v_min_a is distinct from v_min_b or v_max_a is distinct from v_max_b
     or v_sum_a is distinct from v_sum_b then
    raise exception '0297 self-assert FAIL: the rewrite changed the key set of public.voyages — % rows / checksum % / % .. % before, % rows / checksum % / % .. % after',
      v_n_b, v_sum_b, v_min_b, v_max_b, v_n_a, v_sum_a, v_min_a, v_max_a;
  end if;

  -- (c) the heap was rewritten, never grew by more than a page, and a heap of 4,000 pages (32 MB) or more is at least halved
  if v_file_a is not distinct from v_file_b then
    raise exception '0297 self-assert FAIL: public.voyages kept relfilenode % — the rewrite did not happen', v_file_a;
  end if;
  if v_heap_a / v_block > v_heap_b / v_block + 1 then
    raise exception '0297 self-assert FAIL: the rewrite made the heap of public.voyages larger — % pages before, % after', v_heap_b / v_block, v_heap_a / v_block;
  end if;
  if v_heap_b / v_block >= 4000 and (v_heap_a / v_block) * 2 >= v_heap_b / v_block then
    raise exception '0297 self-assert FAIL: the rewrite did not halve the heap of public.voyages — % pages before, % after', v_heap_b / v_block, v_heap_a / v_block;
  end if;

  -- (d) the indexes: the same set with the same definitions, valid / ready / live, EVERY ONE rebuilt (a new relfilenode), the key marked clustered
  if v_ix_names_a is distinct from v_ix_names_b or v_ix_defs_a is distinct from v_ix_defs_b then
    raise exception '0297 self-assert FAIL: the indexes of public.voyages are not the same set with the same definitions (% before, % after)', v_ix_names_b, v_ix_names_a;
  end if;
  if v_ix_bad <> 0 then
    raise exception '0297 self-assert FAIL: % index(es) of public.voyages are not valid, ready and live after the rewrite', v_ix_bad;
  end if;
  if exists (select 1 from unnest(v_ix_names_b, v_ix_files_b) as b(n, f), unnest(v_ix_names_a, v_ix_files_a) as a(n, f)
              where a.n = b.n and a.f = b.f) then
    raise exception '0297 self-assert FAIL: an index of public.voyages kept its relfilenode — it was not rebuilt';
  end if;
  if v_clustered is distinct from true then
    raise exception '0297 self-assert FAIL: voyages_pkey is not marked as the clustered index of public.voyages';
  end if;

  -- (e) public.voyages keeps its own options, constraints, foreign keys in and out, and triggers
  if v_voy_opts_a is distinct from v_voy_opts or v_voy_rel_md5_a is distinct from v_voy_rel_md5 then
    raise exception '0297 self-assert FAIL: the options, constraints or triggers of public.voyages moved (options % -> %)', v_voy_opts, v_voy_opts_a;
  end if;

  -- (f) nothing else moved: every other relation's options, every function, the registry, the walls, the two owner switches
  if (select md5(string_agg(c.relname || '=' || coalesce(c.reloptions::text, ''), ',' order by c.relname collate "C"))
        from pg_class c
       where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'm', 'i')
         and c.oid <> 'public.port_goods'::regclass) is distinct from v_other_opts_md5 then
    raise exception '0297 self-assert FAIL: another relation''s options moved — this file sets the options of one table';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fns
     or (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fns_md5 then
    raise exception '0297 self-assert FAIL: a function in public/cmd/world/voyage moved or was added — this file creates and changes none';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_entry_points
     or (select value from public.world_config where key = 'economy_closed') is distinct from v_economy
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from v_treasury then
    raise exception '0297 self-assert FAIL: the registry or an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0297 self-assert FAIL: a wall moved';
  end if;

  v_t_end := clock_timestamp();

  raise notice '0297 self-assert ok: THE DISK GETS QUIET. public.port_goods carries exactly % (fillfactor kept; routine autovacuum and autoanalyze stop re-reading a table whose updates are all in-page; age(relfrozenxid) % of the % that forces a freeze pass). public.voyages was rewritten in place by CLUSTER on voyages_pkey under one ACCESS EXCLUSIVE lock taken before the first read: the same % rows and key checksum % (min / max id and sum of hashtext(id)) before and after; its % indexes are valid, ready and live, defined exactly as before and every one rebuilt (a new relfilenode), the primary key marked clustered; its options, constraints, foreign keys and triggers are as found. Every other relation''s options and every function in public/cmd/world/voyage are unmoved by md5 (% functions), the registry is unchanged at % entry points, the walls 0 / 0 / 0, both owner switches as found. Printed, never asserted: voyages heap % -> % pages (% -> % MB), indexes % -> % bytes; seconds under the ACCESS EXCLUSIVE lock — the read before the rewrite %, the rewrite %, the reads and asserts after it %, in all %.',
    v_pg_opts, v_pg_age, current_setting('autovacuum_freeze_max_age'),
    v_n_b, v_sum_b, cardinality(v_ix_names_a), v_fns, v_entry_points,
    v_heap_b / v_block, v_heap_a / v_block, round(v_heap_b / 1048576.0, 1), round(v_heap_a / 1048576.0, 1),
    v_idxb_b, v_idxb_a,
    round(extract(epoch from v_t_start - v_t_lock)::numeric, 2),
    round(extract(epoch from v_t_done - v_t_start)::numeric, 2),
    round(extract(epoch from v_t_end - v_t_done)::numeric, 2),
    round(extract(epoch from v_t_end - v_t_lock)::numeric, 2);
end $assert$;

reset statement_timeout;
reset lock_timeout;
