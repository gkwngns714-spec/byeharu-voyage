-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0292 — THE MARKET TABLE KEEPS ROOM   (a LOAD-ONLY slice: the table is rewritten compact; every row is identical)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY (prod, read-only, head 0289, 2026-11-01 14:13–14:22 UTC) ───────────────────────────────
-- The owner (rows 256/259): "the game became unimaginably slower… do not change anything regarding time."
-- 0289 halved the row versions the every-minute market writes (one UPDATE a row, not two). The TABLE is
-- still the problem, not the cadence. Measured on prod, read-only:
--   public.port_goods     154,734 rows (246 ports × 629 goods; no insert and no delete since the server started at
--                         09:34 UTC), ~123 B a row = ~22.6 MB of live data in a heap of 307,044,352 B (293 MB,
--                         37,481 pages): 13× bloat. Three indexes, 37,961,728 B. reloptions NULL (fillfactor 100).
--   updates since 09:34   39,123,759 (at 14:14); HOT 13,064,570 = 33.4 %, and every other update, 26,059,189, went
--                         to a NEW page; n_dead_tup 84,638 (autovacuum has run 162 times, the last at 14:13:19).
--   the drift job         260 calls since 09:44: mean 37.6 s, max 118.9 s (the 120 s wall); PER CALL 3,928 blocks
--                         dirtied, 3,558 read, 50.9 MiB of WAL (1,775 full-page images).
--   the whole database    WAL 61.8 MiB/min over 283 min (17,495 MiB, 2,058,184 full-page images).
--   cron, hourly means    08:00 → 14:00 UTC — drift 17.8, 42.6, 38.4, 39.1, 41.5, 43.1, 51.3 s (max 120.4 s, 13
--                         timeouts since 10:00); compact 3.2 → 23.5 s (max 92.4); price-snapshot 3.8 → 35.3 s.
--   compute               shared_buffers 256 MB, maintenance_work_mem 64 MB, statement_timeout 120 s: a 293 MB
--                         table plus its 36 MB of indexes never stays cached.
--
-- ── WHY ONLY A THIRD ARE HOT ───────────────────────────────────────────────────────────────────
-- No indexed column is written by the market: the indexes are (good_id), (port_id, good_id) and the partial
-- (port_id, good_id) WHERE haul_nm = 0, and the market writes drift, drift_slot, stock, glut, glut_at,
-- last_regen_day, stock_target, base_target and updated_at. So every update COULD be a HOT update, which writes
-- no index entry. But a HOT update needs free room on the SAME page, and at fillfactor 100 a page full of live
-- rows and not-yet-pruned dead versions has none. A non-HOT update leaves a dead version that its index entries
-- pin until a VACUUM, so the room never comes back between vacuums: a loop only a rewrite WITH spare room breaks.
--
-- ── WHAT CHANGES (two statements, in this order, in this transaction) ────────────────────────
--   alter table public.port_goods set (fillfactor = 30);
--   cluster public.port_goods using port_goods_pkey;     -- rewrites the heap and all three indexes, honours the
--                                                        -- fillfactor, and lays a harbour's rows side by side
-- Fillfactor 30 leaves 70 % of every page empty: ~15-16 live rows on a page that holds ~52 tuples, so a page takes
-- a whole minute of new versions beside the old ones (16 + 16 <= 52) AND a second minute while a long snapshot (the
-- Stats count, a minute-long statement) still pins the first: three versions of every row fit (3 x 16 = 48 <= 52).
-- A trade touching stock stays in the page too, and the in-page pruning clears the old versions at the next visit
-- once nothing pins them. Expected table ~80 MB (vs 293 MB).
-- The cluster order (port_id, good_id) is the order the per-harbour drift reads, so a harbour's rows share pages.
--
-- ── WHY NOTHING AFTER THE REWRITE MAY DEPEND ON THE TRANSACTION SURVIVING IT ─────────────────────
-- CI's real Postgres (the Supabase CLI's statement pipeline, PR #444 run 41321070873) failed `relation "clock_0292" does not exist` at the statement
-- right after `analyze`: a transaction-scoped (ON COMMIT DROP) scratch table did not survive the rewrite there, though it did on PGlite. So: the scratch
-- tables live as long as the session and are dropped by the last assert; ANALYZE is gone (CLUSTER itself refreshes relpages and reltuples; the column
-- statistics are those of the same rows; the next autovacuum-analyze refreshes them); and the same-rows assert holds on its own because port_goods is a
-- fixed catalogue (246 ports x 629 goods: no insert, no delete), lock or no lock.
--
-- ── WHAT DOES NOT MOVE ────────────────────────────────────────────────────────────────────────
-- No function body (tick_market_drift, which writes this table, is 0289's and is not touched), no row, column,
-- grant, knob, switch, schedule or cron job. The rewrite copies every tuple: no value changes, so no economy
-- number can move. The md5 of every function in public/cmd/world/voyage, the registry count, the walls and the
-- two owner switches are asserted as found.
--
-- ── THE LOCK, AND WHAT PAYS FOR IT ────────────────────────────────────────────────────────────
-- CLUSTER of ONE named table is allowed inside a transaction block (only the no-argument form refuses one) and
-- takes ACCESS EXCLUSIVE on port_goods until this transaction commits, so the lock is taken FIRST and everything
-- after the rewrite stays catalog-light: one pass over the new compact table (count and key checksum), the
-- catalogs, one probe row. The deploy (~/bin/bv-deploy.sh) unwinds the clock first, so only player reads wait.
-- The wait for the lock is bounded (10 s): a longer wait would queue every reader of the market behind it, and a
-- refused lock rolls back clean and is simply deployed again. statement_timeout is lifted for this transaction
-- (the role's 120 s would cancel a rewrite on a saturated disk). The receipt prints the measured seconds.
--
-- ── SELF-ASSERT (the rewrite itself is the migration's effect; the one probe write is rolled back) ──
--   (a) the SAME ROWS: under the lock, count(*), min/max(port_id) and sum(hashtext(port_id || good_id)) before and
--       after (port_goods is a fixed catalogue, so equality is valid once the lock is held); never empty;
--   (b) reloptions carry fillfactor=30;
--   (c) the three indexes exist, valid, ready and live, with the SAME pg_get_indexdef text as before, each REBUILT
--       (a new relfilenode), and the primary key is the table's clustered index;
--   (d) the table's relfilenode changed (the rewrite happened);
--   (e) one probe UPDATE of a single real row's updated_at is counted as a HOT update (the transaction's own HOT
--       counter rises by 1), then rolled back and asserted gone;
--   (f) every function in public/cmd/world/voyage unmoved by md5, the registry count, the walls (0/0/0) and the
--       two owner switches as found.
--   A size and a timing are printed, never asserted. The receipt's seconds are for the chain logs (local, CI):
--   `supabase db push` prints no notices, so the deploy reads the prod durations afterwards from pg_stat_statements
--   (utility statements are tracked: the CLUSTER, ALTER TABLE and the last DO rows of this transaction)
--   or samples pg_locks while it runs.
-- ROLLBACK (forward, a NEW migration, never an edit): alter table public.port_goods reset (fillfactor);
--   cluster public.port_goods using port_goods_pkey;
-- VERSION: 0292 — prod head 0290 today. 0291 (the laps' autovacuum, which unblocks the Stats count) deploys first; this file deploys AFTER it.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. GUARD ────────────────────────────────────────────────────────────────────────────────────
do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '10s', true);
  if not exists (select 1 from pg_class c
                  where c.oid = to_regclass('public.port_goods') and c.relkind = 'r' and c.relpersistence = 'p')
     or to_regclass('public.port_goods_pkey') is null then
    raise exception '0292 refuses: public.port_goods (a permanent table) or port_goods_pkey is not in this world';
  end if;
  if not exists (select 1 from pg_index i
                  where i.indexrelid = 'public.port_goods_pkey'::regclass and i.indrelid = 'public.port_goods'::regclass
                    and i.indisprimary and i.indisvalid and i.indisready) then
    raise exception '0292 refuses: port_goods_pkey is not the valid primary key of public.port_goods';
  end if;
  if exists (select 1 from pg_class c, unnest(c.reloptions) o
              where c.oid = 'public.port_goods'::regclass and o like 'fillfactor=%') then
    raise exception '0292 refuses: public.port_goods already carries a fillfactor — this has been applied once';
  end if;
end $guard$;

-- ── 1. AS FOUND, before the lock (catalog reads only; nothing here touches the table) ───────────
create temp table before_0292 as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns_md5,
       (select value from public.world_config where key = 'economy_closed') as economy_closed,
       (select value from public.world_config where key = 'city_treasury_enabled') as city_treasury_enabled;

create temp table clock_0292 (k text primary key, t timestamptz not null);

-- ── 2. THE LOCK FIRST, then the table as found ─────────────────────────────────────────────────
do $lock$
begin
  lock table public.port_goods in access exclusive mode;
  insert into clock_0292 values ('locked', clock_timestamp());
end $lock$;

create temp table table_before_0292 as
select k.n, k.min_port, k.max_port, k.key_sum,
       c.relfilenode as table_filenode,
       pg_relation_size(c.oid) as heap_bytes,
       pg_indexes_size(c.oid) as indexes_bytes
  from (select count(*) as n, min(port_id::text) as min_port, max(port_id::text) as max_port,
               sum(hashtext(port_id::text || good_id::text)) as key_sum
          from public.port_goods) k,
       pg_class c
 where c.oid = 'public.port_goods'::regclass;

create temp table idx_before_0292 as
select i.indexrelid::regclass::text as name,
       pg_get_indexdef(i.indexrelid) as def,
       ic.relfilenode as filenode
  from pg_index i
  join pg_class ic on ic.oid = i.indexrelid
 where i.indrelid = 'public.port_goods'::regclass;

-- ── 3. THE REWRITE ──────────────────────────────────────────────────────────────────────────────
insert into clock_0292 values ('rewrite_start', clock_timestamp());
alter table public.port_goods set (fillfactor = 30);
cluster public.port_goods using port_goods_pkey;
insert into clock_0292 values ('rewritten', clock_timestamp());

-- ── 4. THE SELF-ASSERT (the last statement of the file) ────────────────────────────────────────
do $assert$
declare
  b record;
  f record;
  v_n bigint;
  v_min text;
  v_max text;
  v_sum bigint;
  v_filenode oid;
  v_idx_n int;
  v_missing int;
  v_moved int;
  v_same_file int;
  v_not_ok int;
  v_clustered boolean;
  v_port uuid;
  v_good uuid;
  v_old timestamptz;
  v_new timestamptz;
  v_rows int;
  v_hot0 bigint;
  v_hot1 bigint;
  v_heap_after bigint;
  v_indexes_after bigint;
  v_block int := current_setting('block_size')::int;
  v_t_locked timestamptz;
  v_t_start timestamptz;
  v_t_done timestamptz;
  v_t_end timestamptz;
begin
  select * into b from table_before_0292;
  select * into f from before_0292;
  select t into v_t_locked from clock_0292 where k = 'locked';
  select t into v_t_start from clock_0292 where k = 'rewrite_start';
  select t into v_t_done from clock_0292 where k = 'rewritten';

  -- (a) the SAME ROWS: nothing was lost, added or re-keyed by the rewrite
  if b.n is null or b.n = 0 then
    raise exception '0292 self-assert FAIL: public.port_goods was empty under the lock — there is nothing to rewrite, and the HOT probe would have no row';
  end if;
  select count(*), min(port_id::text), max(port_id::text), sum(hashtext(port_id::text || good_id::text))
    into v_n, v_min, v_max, v_sum
    from public.port_goods;
  if v_n is distinct from b.n or v_min is distinct from b.min_port or v_max is distinct from b.max_port
     or v_sum is distinct from b.key_sum then
    raise exception '0292 self-assert FAIL: the rewrite changed the key set — % rows / checksum % / % .. % before, % rows / checksum % / % .. % after',
      b.n, b.key_sum, b.min_port, b.max_port, v_n, v_sum, v_min, v_max;
  end if;

  -- (b) the fillfactor is on the table
  if not exists (select 1 from pg_class c where c.oid = 'public.port_goods'::regclass and c.reloptions @> array['fillfactor=30']) then
    raise exception '0292 self-assert FAIL: public.port_goods does not carry fillfactor=30 (reloptions %)',
      (select c.reloptions from pg_class c where c.oid = 'public.port_goods'::regclass);
  end if;

  -- (c) the indexes: the same set, the same definitions, valid / ready / live, each rebuilt, the key is clustered
  select count(*) filter (where b2.name is null or a.name is null),
         count(*) filter (where b2.def is distinct from a.def),
         count(*) filter (where b2.filenode = a.filenode),
         count(*) filter (where not coalesce(a.ok, false)),
         count(*)
    into v_missing, v_moved, v_same_file, v_not_ok, v_idx_n
    from idx_before_0292 b2
    full join (select i.indexrelid::regclass::text as name,
                      pg_get_indexdef(i.indexrelid) as def,
                      ic.relfilenode as filenode,
                      (i.indisvalid and i.indisready and i.indislive) as ok
                 from pg_index i
                 join pg_class ic on ic.oid = i.indexrelid
                where i.indrelid = 'public.port_goods'::regclass) a on a.name = b2.name;
  if v_idx_n <> 3 or v_missing <> 0 then
    raise exception '0292 self-assert FAIL: public.port_goods has % index(es) after the rewrite (% missing or new), not the same three as before', v_idx_n, v_missing;
  end if;
  if v_moved <> 0 then
    raise exception '0292 self-assert FAIL: % index definition(s) differ from the text taken before the rewrite', v_moved;
  end if;
  if v_not_ok <> 0 then
    raise exception '0292 self-assert FAIL: % index(es) are not valid, ready and live after the rewrite', v_not_ok;
  end if;
  if v_same_file <> 0 then
    raise exception '0292 self-assert FAIL: % index(es) kept their relfilenode — they were not rebuilt', v_same_file;
  end if;
  select i.indisclustered into v_clustered from pg_index i where i.indexrelid = 'public.port_goods_pkey'::regclass;
  if v_clustered is distinct from true then
    raise exception '0292 self-assert FAIL: port_goods_pkey is not marked as the table''s clustered index';
  end if;

  -- (d) the heap really was rewritten
  select c.relfilenode into v_filenode from pg_class c where c.oid = 'public.port_goods'::regclass;
  if v_filenode is not distinct from b.table_filenode then
    raise exception '0292 self-assert FAIL: public.port_goods kept relfilenode % — the rewrite did not happen', v_filenode;
  end if;

  -- (e) THE POINT OF THE SLICE: a market update of one real row finds room on its page — a HOT update.
  --     The probe is rolled back in a sub-transaction and asserted gone.
  v_hot0 := coalesce(pg_stat_get_xact_tuples_hot_updated('public.port_goods'::regclass), 0);
  select g.port_id, g.good_id, g.updated_at into v_port, v_good, v_old
    from public.port_goods g
   order by g.port_id, g.good_id
   limit 1;
  begin
    update public.port_goods g
       set updated_at = v_old + interval '1 second'
     where g.port_id = v_port and g.good_id = v_good;
    get diagnostics v_rows = row_count;
    v_hot1 := coalesce(pg_stat_get_xact_tuples_hot_updated('public.port_goods'::regclass), 0);
    raise exception using errcode = 'ZX291', message = 'rollback';
  exception when sqlstate 'ZX291' then
    null;
  end;
  if v_rows is distinct from 1 then
    raise exception '0292 self-assert FAIL: the probe update touched % row(s), not 1', v_rows;
  end if;
  if v_hot1 - v_hot0 is distinct from 1 then
    raise exception '0292 self-assert FAIL: the probe update of one row was not a HOT update (the transaction''s HOT counter went % -> %) — the rewritten page has no room for the new version',
      v_hot0, v_hot1;
  end if;
  select g.updated_at into v_new from public.port_goods g where g.port_id = v_port and g.good_id = v_good;
  if v_new is distinct from v_old then
    raise exception '0292 self-assert FAIL: the probe update survived its rollback (updated_at % -> %)', v_old, v_new;
  end if;

  -- (f) nothing else moved
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> f.fns
     or (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> f.fns_md5 then
    raise exception '0292 self-assert FAIL: a function in public/cmd/world/voyage moved or was added — this file creates and changes none';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> f.entry_points
     or (select value from public.world_config where key = 'economy_closed') is distinct from f.economy_closed
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from f.city_treasury_enabled then
    raise exception '0292 self-assert FAIL: the registry or an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0292 self-assert FAIL: a wall moved';
  end if;

  select pg_relation_size('public.port_goods'::regclass), pg_indexes_size('public.port_goods'::regclass)
    into v_heap_after, v_indexes_after;
  v_t_end := clock_timestamp();

  raise notice '0292 self-assert ok: THE MARKET TABLE KEEPS ROOM. public.port_goods was rewritten in place by CLUSTER on port_goods_pkey with fillfactor 30, under one ACCESS EXCLUSIVE lock taken before the first read. The same % rows and the same key checksum % (min / max port and sum of hashtext(port || good)) before and after; reloptions %; the % indexes valid, ready and live, each rebuilt (a new relfilenode) and defined exactly as before, the primary key marked clustered; the table moved from relfilenode % to %. A probe UPDATE of one real row (updated_at, rolled back and asserted gone) was a HOT update — the transaction''s own HOT counter rose % -> %. Every function in public/cmd/world/voyage unmoved by md5 (% functions), the registry unchanged at % entry points, the walls 0 / 0 / 0, both owner switches as found. Printed, never asserted: heap % -> % bytes (% -> % pages of %), indexes % -> % bytes; seconds under the ACCESS EXCLUSIVE lock — the read before the rewrite %, the rewrite (alter + cluster) %, the asserts after it %, in all % through the last assert.',
    b.n, b.key_sum,
    (select c.reloptions from pg_class c where c.oid = 'public.port_goods'::regclass),
    v_idx_n, b.table_filenode, v_filenode, v_hot0, v_hot1,
    f.fns, f.entry_points,
    b.heap_bytes, v_heap_after, b.heap_bytes / v_block, v_heap_after / v_block, v_block,
    b.indexes_bytes, v_indexes_after,
    round(extract(epoch from v_t_start - v_t_locked)::numeric, 2),
    round(extract(epoch from v_t_done - v_t_start)::numeric, 2),
    round(extract(epoch from v_t_end - v_t_done)::numeric, 2),
    round(extract(epoch from v_t_end - v_t_locked)::numeric, 2);

  -- the scratch tables are session-lived (see the header): drop them here, after the receipt has been printed
  drop table if exists pg_temp.before_0292, pg_temp.clock_0292, pg_temp.table_before_0292, pg_temp.idx_before_0292;
end $assert$;
