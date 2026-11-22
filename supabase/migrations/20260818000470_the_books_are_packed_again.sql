-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0470 — THE BOOKS ARE PACKED AGAIN   (a LOAD-ONLY slice: four tables are rewritten compact in place, the way 0297 rewrote voyages;
--                                     no row, function, option, knob, switch, cron job or schedule moves)
-- news: none
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY (prod, read-only, head 0467, 2026-11-22 00:20 UTC; scripts/ops/harness/hot-set/before-0470.sql) ──────────────────────────
-- The lead's daily read (09:18 KST): over = hot_set_mb 780 (the ten biggest tables no longer fit the ~700 MB of cache) and cache_hit_pct
-- 98.55. Database 1,060 MB, beat 122 ms. The catalog read (relpages; the row width is the sum of pg_stats.avg_width plus 28 bytes of
-- header, packed at fillfactor 100; an index's fresh size is its entries x (16 + key width) at a leaf fill of 90 %):
--
--   table             MB    heap pages  rows      width  packed heap   indexes, pages now -> fresh                            idx_scan
--   stats_city_good   124    5,743      266,761    100    ~4,200        pkey 8,744 -> ~2,050 (4x); at 1,421 -> ~870            4.3 M / 2.3 k
--   voyages           122   13,991       43,850  1,126    ~6,300        fleet_ended 842 -> ~235; pkey 711 -> ~190;             7.9 M / 237 M /
--                                                                        due_at 93 -> ~5; one_sailing 9 -> ~5                   1.7 M / 22 M
--   events            111    8,140       85,685    330    ~3,750        created_at 3,292 -> ~280 (12x); player_created 1,189   125 k / 712 k /
--                                                                        -> ~470; pkey 815 -> ~375; trades_window 731 -> ~250;  52 M / 26 k / 9
--                                                                        trades_port_good 78 -> ~20
--   port_goods        102   10,721      159,766    122    (fillfactor 30, churn by design: 0292 / 0297; LEFT ALONE)
--   voyage_events      91    7,949       85,568     88    ~1,220        pkey 3,684 -> ~420 (9x)                                354 M
--   (then price_history_hour 69, stats_good 66, stats_city 41, battles 30, arrivals_beats_kept 24: none of them over 1.5x; left alone)
--
-- WHY THEY ARE LOOSE. voyages, events and voyage_events are the drain left by 0463: on 11-20 they held 90,698 / 132,000 / 435,000 live
-- rows; 0463 let the compactor reach the houses with no ledger and it cut them to 43,850 / 85,685 / 85,568 (dead now 2,254 / 1,149 /
-- 11,781: the vacuums keep up). A vacuum makes the freed room reusable but never gives a page back, so the files stay the size of the
-- peak: voyages 2.2x its packed size, events 2.2x, voyage_events 6.5x, and their indexes 3-12x. The cause is gone (0463), so a rewrite
-- stays compact: the rows stay where the compactor holds them (npc_retention_hours), and the vacuum (0428: 5,000 + 10 % dead) reuses room.
-- stats_city_good is the other kind: its heap is near packed (1.4x) but its primary key is 4.3x, because the Stats count adds a slot to
-- every (harbour, good) range of the tree four times an hour and the fold deletes the fine slots after 26 hours; a b-tree page that is
-- half emptied is never merged, only reused. It grew 62 -> 79 MB of index in two days (2026-11-20 -> 22, docs/dev-log/2026-11-20-hot-set.md),
-- so it WILL grow back (~8 MB a day at that rate); the daily read's hot_set_mb line shows when. No option fixes that (a lower fillfactor
-- of a b-tree only makes it bigger), so this file packs it and says so.
--
-- NO INDEX IS DROPPED. Every index on these tables is read: the smallest count is events_trades_port_good (9 scans, last 11-12; 0227's
-- city trade list reads it), 78 pages (0.6 MB) — not worth a reader. battles_ended (5,273 scans) is not in this file.
-- NO OPTION MOVES. Each of the four keeps its own autovacuum options (0428, asserted); port_goods keeps its own.
--
-- ── WHAT CHANGES ───────────────────────────────────────────────────────────────────────────────
--   cluster public.stats_city_good using stats_city_good_pkey; cluster public.voyage_events using voyage_events_pkey;
--   cluster public.events using events_pkey; cluster public.voyages using voyages_pkey — each under its own ACCESS EXCLUSIVE lock, taken
--   right before its own rewrite, the rows read before and after under it. CLUSTER, not VACUUM FULL: VACUUM cannot run inside a DO block,
--   and the primary key is the only full index of each (CLUSTER refuses a partial one). CLUSTER fires no trigger (events' append-only
--   trigger is untouched) and deletes nothing.
--   Expected (MB, heap + indexes): stats_city_good 124 -> ~56, voyages 122 -> ~52, events 111 -> ~40, voyage_events 91 -> ~13:
--   about 287 MB back to the disk, the database 1,060 -> ~775 MB, and the hot set 781 -> ~480-505 MB (voyage_events leaves the ten; the
--   eleventh table, 24 MB or less, joins), inside the ~700 MB with ~200 MB of room.
-- -- budget: a one-time rewrite, about 482,000 rows read and written once (four tables); no job, threshold, schedule or fillfactor is set
--
-- ── THE LOCK, AND WHAT A PLAYER SEES ──────────────────────────────────────────────────────────
-- db push runs the file and its schema_migrations row as ONE implicit transaction (docs/RESUME.md), so every lock taken here is held to the
-- commit. The tables are therefore locked one at a time, in the order a player feels them least to most: stats_city_good (the Stats
-- count and the city charts), voyage_events (a voyage's journal), events (every action writes one), voyages last. The work: ~280 MB of
-- heap read (most of it cached: hit 98.5 %), ~125 MB of new heap and indexes written, about as much WAL. 0292's CLUSTER of port_goods did
-- 336 MB read / 122 MB written in 42.7 s on a saturated disk, so expect in all ~20-45 s on a saturated disk (60 s as the pessimistic
-- bound) and ~5-10 s while the disk bursts. Held, roughly: stats_city_good the whole run, voyage_events from ~25 %, events from ~45 %,
-- voyages for its own ~10-15 s (saturated). A request that touches a locked table WAITS — anon is cut at 3 s, authenticated at 8 s — and
-- fails with a timeout after that; a request that touches none of them is unaffected. bv-deploy.sh unwinds the clock first, so no beat,
-- count or compactor run queues behind it. lock_timeout is 10 s a lock: a lock that cannot be had is refused and the file rolls back clean,
-- and is simply deployed again. A session that holds voyages and then waits for events while this file holds events and waits for voyages
-- is a deadlock: the server breaks it after 1 s by cancelling the side that has waited longer, which is the player's (it would have timed out).
--
-- ── SELF-ASSERT (one DO block; nothing is written but the rewrites) ──────────────────────────────
--   for each of the four tables, under its lock:
--   (a) the SAME ROWS: count, min / max of the key and sum(hashtext(key)) before and after, both read under the lock (exact);
--   (b) the heap was rewritten (a new relfilenode), never grew by more than a page, and a heap of 4,000 pages (32 MB) or more lost at least a tenth;
--   (c) its indexes: the same set with the same definitions, valid / ready / live, EVERY ONE rebuilt (a new relfilenode), the primary key marked clustered;
--   (d) its own options, its constraints, the foreign keys in and out, and its triggers as found;
--   then (e) every relation's options in public, every function in public/cmd/world/voyage (md5), the registry, the walls (0/0/0) and both owner switches as found.
--   Printed, never asserted: each table's heap and index pages before and after, the seconds under each lock and in all.
--   The chain's own world holds few rows in these tables, so CI proves the mechanism (four locks and four CLUSTERs inside one DO block, the
--   rebuilds, the options) and prod proves the row identity under the locks.
-- ROLLBACK: none is needed and none is possible (a compact table is the goal; the rows, options and functions are as found). CLUSTER again
--   if one bloats again: the daily read's hot_set_mb line says when.
-- VERSION: 0470 — prod head 0467 today. 0468 and 0469 are other branches' feature migrations and deploy first; this file touches no function,
--   so it applies on top of either.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. GUARD ────────────────────────────────────────────────────────────────────────────────────
do $guard$
declare
  t text;
begin
  perform set_config('statement_timeout', '10min', false);
  perform set_config('lock_timeout', '10s', false);
  foreach t in array array['stats_city_good', 'voyage_events', 'events', 'voyages'] loop
    if not exists (select 1 from pg_class c
                    where c.oid = to_regclass('public.' || t) and c.relkind = 'r' and c.relpersistence = 'p') then
      raise exception '0470 refuses: public.% (a permanent table) is not in this world', t;
    end if;
    if to_regclass('public.' || t || '_pkey') is null
       or not exists (select 1 from pg_index i
                       where i.indexrelid = to_regclass('public.' || t || '_pkey') and i.indrelid = to_regclass('public.' || t)
                         and i.indisprimary and i.indisvalid and i.indisready and i.indpred is null) then
      raise exception '0470 refuses: public.%_pkey is not the valid primary key of public.%', t, t;
    end if;
  end loop;
end $guard$;

-- ── 1. THE REWRITES AND THEIR SELF-ASSERT: ONE DO BLOCK, the last statement of the file that does work ─
do $assert$
declare
  -- the order is the lock order: the table a player feels least first, voyages last (every lock is held to the commit)
  c_tabs           text[] := array['stats_city_good', 'voyage_events', 'events', 'voyages'];
  c_keys           text[] := array[$k$port_id::text || '/' || good_id::text || '/' || slot::text$k$,
                                   $k$voyage_id::text || '/' || day_index::text$k$,
                                   $k$id::text$k$,
                                   $k$id::text$k$];
  -- the world as found (catalog reads only, taken before any lock)
  v_entry_points   int;
  v_fns            int;
  v_fns_md5        text;
  v_economy        jsonb;
  v_treasury       jsonb;
  v_opts_md5       text;
  v_block          int := current_setting('block_size')::int;
  i                int;
  v_tbl            regclass;
  v_pk             regclass;
  v_opts_b         text[];
  v_opts_a         text[];
  v_rel_b          text;
  v_rel_a          text;
  v_n_b            bigint;
  v_min_b          text;
  v_max_b          text;
  v_sum_b          bigint;
  v_n_a            bigint;
  v_min_a          text;
  v_max_a          text;
  v_sum_a          bigint;
  v_file_b         oid;
  v_file_a         oid;
  v_heap_b         bigint;
  v_heap_a         bigint;
  v_idxb_b         bigint;
  v_idxb_a         bigint;
  v_ix_defs_b      text;
  v_ix_defs_a      text;
  v_ix_names_b     text[];
  v_ix_names_a     text[];
  v_ix_files_b     oid[];
  v_ix_files_a     oid[];
  v_ix_bad         int;
  v_clustered      boolean;
  v_t0             timestamptz := clock_timestamp();
  v_t_lock         timestamptz;
  v_t_done         timestamptz;
  v_report         text := '';
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
    into v_opts_md5
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'm', 'i');

  for i in 1 .. cardinality(c_tabs) loop
    v_tbl := ('public.' || c_tabs[i])::regclass;
    v_pk  := ('public.' || c_tabs[i] || '_pkey')::regclass;

    -- what hangs on the table besides its rows: its options, its constraints and the foreign keys that reference it, its triggers
    select c.reloptions into v_opts_b from pg_class c where c.oid = v_tbl;
    select md5(coalesce((select string_agg(k.conrelid::regclass::text || '.' || k.conname || '=' || pg_get_constraintdef(k.oid), ',' order by k.conrelid::regclass::text, k.conname)
                           from pg_constraint k
                          where k.conrelid = v_tbl or k.confrelid = v_tbl), '')
                || '|' ||
                coalesce((select string_agg(t.tgname || '=' || pg_get_triggerdef(t.oid), ',' order by t.tgname)
                            from pg_trigger t where t.tgrelid = v_tbl and not t.tgisinternal), ''))
      into v_rel_b;

    -- the lock, then the rows read before, the rewrite and the rows read after (the lock is held to the commit)
    execute format('lock table %s in access exclusive mode', v_tbl);
    v_t_lock := clock_timestamp();

    execute format('select count(*), min(k), max(k), coalesce(sum(hashtext(k)::bigint), 0) from (select %s as k from %s) s', c_keys[i], v_tbl)
      into v_n_b, v_min_b, v_max_b, v_sum_b;
    select c.relfilenode, pg_relation_size(c.oid), pg_indexes_size(c.oid)
      into v_file_b, v_heap_b, v_idxb_b
      from pg_class c where c.oid = v_tbl;
    select md5(string_agg(x.indexrelid::regclass::text || '=' || pg_get_indexdef(x.indexrelid), E'\n' order by x.indexrelid::regclass::text collate "C")),
           array_agg(x.indexrelid::regclass::text order by x.indexrelid::regclass::text collate "C"),
           array_agg(ic.relfilenode order by x.indexrelid::regclass::text collate "C")
      into v_ix_defs_b, v_ix_names_b, v_ix_files_b
      from pg_index x join pg_class ic on ic.oid = x.indexrelid
     where x.indrelid = v_tbl;

    execute format('cluster %s using %I', v_tbl, c_tabs[i] || '_pkey');
    v_t_done := clock_timestamp();

    execute format('select count(*), min(k), max(k), coalesce(sum(hashtext(k)::bigint), 0) from (select %s as k from %s) s', c_keys[i], v_tbl)
      into v_n_a, v_min_a, v_max_a, v_sum_a;
    select c.relfilenode, pg_relation_size(c.oid), pg_indexes_size(c.oid), c.reloptions
      into v_file_a, v_heap_a, v_idxb_a, v_opts_a
      from pg_class c where c.oid = v_tbl;
    select md5(string_agg(x.indexrelid::regclass::text || '=' || pg_get_indexdef(x.indexrelid), E'\n' order by x.indexrelid::regclass::text collate "C")),
           array_agg(x.indexrelid::regclass::text order by x.indexrelid::regclass::text collate "C"),
           array_agg(ic.relfilenode order by x.indexrelid::regclass::text collate "C"),
           count(*) filter (where not (x.indisvalid and x.indisready and x.indislive))
      into v_ix_defs_a, v_ix_names_a, v_ix_files_a, v_ix_bad
      from pg_index x join pg_class ic on ic.oid = x.indexrelid
     where x.indrelid = v_tbl;
    select x.indisclustered into v_clustered from pg_index x where x.indexrelid = v_pk;
    select md5(coalesce((select string_agg(k.conrelid::regclass::text || '.' || k.conname || '=' || pg_get_constraintdef(k.oid), ',' order by k.conrelid::regclass::text, k.conname)
                           from pg_constraint k
                          where k.conrelid = v_tbl or k.confrelid = v_tbl), '')
                || '|' ||
                coalesce((select string_agg(t.tgname || '=' || pg_get_triggerdef(t.oid), ',' order by t.tgname)
                            from pg_trigger t where t.tgrelid = v_tbl and not t.tgisinternal), ''))
      into v_rel_a;

    -- (a) the SAME ROWS (exact: this transaction holds the table's ACCESS EXCLUSIVE lock from before the first read)
    if v_n_a is distinct from v_n_b or v_min_a is distinct from v_min_b or v_max_a is distinct from v_max_b
       or v_sum_a is distinct from v_sum_b then
      raise exception '0470 self-assert FAIL: the rewrite changed the key set of % — % rows / checksum % / % .. % before, % rows / checksum % / % .. % after',
        v_tbl, v_n_b, v_sum_b, v_min_b, v_max_b, v_n_a, v_sum_a, v_min_a, v_max_a;
    end if;

    -- (b) the heap was rewritten, never grew by more than a page, and a heap of 4,000 pages (32 MB) or more lost at least a tenth
    if v_file_a is not distinct from v_file_b then
      raise exception '0470 self-assert FAIL: % kept relfilenode % — the rewrite did not happen', v_tbl, v_file_a;
    end if;
    if v_heap_a / v_block > v_heap_b / v_block + 1 then
      raise exception '0470 self-assert FAIL: the rewrite made the heap of % larger — % pages before, % after', v_tbl, v_heap_b / v_block, v_heap_a / v_block;
    end if;
    if v_heap_b / v_block >= 4000 and (v_heap_a / v_block) * 10 > (v_heap_b / v_block) * 9 then
      raise exception '0470 self-assert FAIL: the rewrite of % gave back less than a tenth of its heap — % pages before, % after', v_tbl, v_heap_b / v_block, v_heap_a / v_block;
    end if;

    -- (c) the indexes: the same set with the same definitions, valid / ready / live, EVERY ONE rebuilt (a new relfilenode), the key marked clustered
    if v_ix_names_a is distinct from v_ix_names_b or v_ix_defs_a is distinct from v_ix_defs_b then
      raise exception '0470 self-assert FAIL: the indexes of % are not the same set with the same definitions (% before, % after)', v_tbl, v_ix_names_b, v_ix_names_a;
    end if;
    if v_ix_bad <> 0 then
      raise exception '0470 self-assert FAIL: % index(es) of % are not valid, ready and live after the rewrite', v_ix_bad, v_tbl;
    end if;
    if exists (select 1 from unnest(v_ix_names_b, v_ix_files_b) as b(n, f), unnest(v_ix_names_a, v_ix_files_a) as a(n, f)
                where a.n = b.n and a.f = b.f) then
      raise exception '0470 self-assert FAIL: an index of % kept its relfilenode — it was not rebuilt', v_tbl;
    end if;
    if v_clustered is distinct from true then
      raise exception '0470 self-assert FAIL: % is not marked as the clustered index of %', v_pk, v_tbl;
    end if;

    -- (d) its own options, constraints, foreign keys in and out, and triggers as found
    if v_opts_a is distinct from v_opts_b or v_rel_a is distinct from v_rel_b then
      raise exception '0470 self-assert FAIL: the options, constraints or triggers of % moved (options % -> %)', v_tbl, v_opts_b, v_opts_a;
    end if;

    v_report := v_report || format(' %s: %s rows (checksum %s), heap %s -> %s pages (%s -> %s MB), %s indexes %s -> %s MB, locked at +%s s, rewritten in %s s;',
      c_tabs[i], v_n_b, v_sum_b, v_heap_b / v_block, v_heap_a / v_block,
      round(v_heap_b / 1048576.0, 1), round(v_heap_a / 1048576.0, 1),
      cardinality(v_ix_names_a), round(v_idxb_b / 1048576.0, 1), round(v_idxb_a / 1048576.0, 1),
      round(extract(epoch from v_t_lock - v_t0)::numeric, 2), round(extract(epoch from v_t_done - v_t_lock)::numeric, 2));
  end loop;

  -- (e) nothing else moved: every relation's options, every function, the registry, the walls, the two owner switches
  if (select md5(string_agg(c.relname || '=' || coalesce(c.reloptions::text, ''), ',' order by c.relname collate "C"))
        from pg_class c
       where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'm', 'i')) is distinct from v_opts_md5 then
    raise exception '0470 self-assert FAIL: a relation''s options moved — this file sets none';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fns
     or (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fns_md5 then
    raise exception '0470 self-assert FAIL: a function in public/cmd/world/voyage moved or was added — this file creates and changes none';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_entry_points
     or (select value from public.world_config where key = 'economy_closed') is distinct from v_economy
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from v_treasury then
    raise exception '0470 self-assert FAIL: the registry or an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0470 self-assert FAIL: a wall moved';
  end if;

  raise notice '0470 self-assert ok: THE BOOKS ARE PACKED AGAIN. Four tables rewritten in place by CLUSTER on their primary keys, each under its own ACCESS EXCLUSIVE lock taken before its first read, in the order stats_city_good, voyage_events, events, voyages: the same rows and key checksums before and after, every index valid, ready, live, defined as before and rebuilt, the primary key marked clustered; options, constraints, foreign keys and triggers as found. Every relation''s options and every function in public/cmd/world/voyage are unmoved by md5 (% functions), the registry is unchanged at % entry points, the walls 0 / 0 / 0, both owner switches as found. Printed, never asserted:% in all % s from the first lock to the end of the asserts.',
    v_fns, v_entry_points, v_report, round(extract(epoch from clock_timestamp() - v_t0)::numeric, 2);
end $assert$;

reset statement_timeout;
reset lock_timeout;
