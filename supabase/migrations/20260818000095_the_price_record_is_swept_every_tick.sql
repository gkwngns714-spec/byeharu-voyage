-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0095 — THE PRICE RECORD IS SWEPT EVERY TICK
--        public.price_history gets its own autovacuum trigger: a fixed dead-row count about one
--        tick's prune, instead of the default 20% of the table. Nothing else moves. The writer is NOT
--        re-cut, because measuring it showed it is not what bloated the index — see below.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT WAS MEASURED ON PRODUCTION, 2026-10-01 ────────────────────────────────────────────────
--     public.price_history          heap 14 MB, 113k live rows
--     public.price_history_pkey     738 MB, 54M index scans        <- the database read 841 MB
-- The Free plan is 500 MB; the last time this table outgrew the disk the project went READ-ONLY
-- (0057's header). `reindex index concurrently public.price_history_pkey` was run by hand: the
-- index fell to 7.3 MB and the database to 110 MB, rows unchanged (126,528).
--
-- ── THE WRITER, READ AT ITS LATEST DEFINITION ──────────────────────────────────────────────────
-- public.tick_price_snapshot is 0013:97, re-cut by 0057:302 (window = public.price_history_window())
-- and 0061:361 (only pairs public.port_offers names). Nothing after 0061 redefines it or writes
-- price_history. Per tick it is a QUEUE on the primary key (port_id, good_id, slot):
--     insert (port, good, v_slot) ... on conflict (port_id, good_id, slot) do nothing
--     delete from public.price_history where slot <= v_slot - v_keep
-- No UPDATE at all, so HOT is not in play: every tick adds one index entry per offered pair and
-- leaves one dead entry behind, and only VACUUM turns dead entries back into reusable space.
--
-- ── WHY THE INDEX WAS 50x THE TABLE: A HIGH-WATER MARK, NOT A LEAK ─────────────────────────────
-- A btree never gives a page back to the disk. VACUUM recycles an emptied page inside the file;
-- only REINDEX / VACUUM FULL shrinks it. The heap is different: VACUUM truncates its emptied tail.
-- Before 0057 the record held 7,347,231 rows (1,410 MB, heap + this index); 0057 bounded it at
-- ~3.1M and 0061 cut it to the roster (97.6% of rows deleted). The heap then came back to 14 MB
-- by truncation; the index kept every page the dense record had needed. 738 MB is that peak.
-- The 54M index scans are the same era: one ON CONFLICT probe per (port, good) per tick, at
-- 54,432 pairs a tick.
--
-- Reproduced on PGlite (the applied 0001-0094 chain, 1,348 offered pairs, window 48; ticks driven
-- 10 minutes apart with `VACUUM public.price_history` every 10 ticks, about the default trigger):
--     dense era, 40 ports sampled whole, 80 ticks      1,069,964 rows   heap 112.0 MB   index 95.2 MB
--     cut back to the roster (0061's delete) + vacuum     65,668 rows   heap 112.0 MB   index 95.2 MB
--     +120 roster ticks                                    65,668 rows   heap   7.0 MB   index 95.3 MB
--     +240 roster ticks                                    65,668 rows   heap   7.0 MB   index 95.3 MB
-- That is production's signature: the heap shrank and the index stayed at its peak.
--
-- ── THE CURRENT WRITER DOES NOT RE-BLOAT IT — AS LONG AS VACUUM REACHES IT ─────────────────────
-- Same chain, the record as it is today (roster only), the index size after N ticks:
--     VACUUM every 2 ticks     tick 100: 6.2 MB   tick 250: 6.2 MB    (flat)
--     VACUUM every 10 ticks    tick 100: 7.2 MB   tick 300: 7.2 MB    (flat)
--     never vacuumed           tick 100: 11.6 MB  tick 250: 24.8 MB   (+~100 KB a tick, unbounded)
-- So the queue is bounded by VACUUM and by nothing else. The default trigger (50 + 20% of live
-- rows) fires about every 10 ticks, because a tick prunes 1/window of the table — on production
-- ~2,400 rows a tick against a ~22,700-row trigger. That trigger also scales with the table: a
-- record that grows (a larger window, a larger roster) waits proportionally longer between sweeps.
--
-- ── WHAT WAS TRIED AND REJECTED: A RING ────────────────────────────────────────────────────────
-- Re-keying the record (port_id, good_id, slot mod window) and overwriting the aged-out point in
-- place (HOT) was built, applied and driven the same way. With VACUUM every 10 ticks the index
-- settled at 6.8 MB — no better than the queue's 7.2 MB — while the heap grew to 18.6 MB (2.8x),
-- because rows written in one tick share pages and a tick then updates whole pages at once, so
-- most updates cannot stay on their page. A schema change on a live table for no index gain and a
-- larger heap is not a fix; it is not in this file.
--
-- ── THE CHANGE ─────────────────────────────────────────────────────────────────────────────────
--   alter table public.price_history set (autovacuum_vacuum_scale_factor = 0,
--                                         autovacuum_vacuum_threshold   = 1000);
-- Autovacuum then sweeps the record once ~1,000 rows are dead — after every tick on today's roster
-- (self-assert (b) proves one tick's prune reaches it) — whatever size the record grows to. A sweep
-- of a 14 MB heap and a 7 MB index every ten minutes is negligible. The per-table setting takes a
-- SHARE UPDATE EXCLUSIVE lock for an instant; it does not rewrite the table.
--
-- ── WHAT DOES NOT CHANGE ───────────────────────────────────────────────────────────────────────
-- public.tick_price_snapshot, world.price_history, the table's columns, key, rows and grants, the
-- cron job. Self-assert (a) proves the writer and the read are byte-identical to before this file.
--
-- ── WHAT THIS FILE CANNOT DO ───────────────────────────────────────────────────────────────────
-- Shrink an index that is already large: REINDEX cannot run inside a migration's transaction
-- (CONCURRENTLY) and a plain REINDEX locks the table. Production's was reindexed by hand on
-- 2026-10-01. If the record ever grows a lot and shrinks again (a wider window, a re-densified
-- sample), the index will keep the peak again, and `reindex index concurrently
-- public.price_history_pkey` is again the remedy.
--
-- Depends on: 0013 (the table, the writer, the read), 0057 and 0061 (the deployed writer).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. THE PRE-IMAGES of what this file must NOT move ─────────────────────────────────────────
create temporary table defs_before_0095 as
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
    from (values ('public.tick_price_snapshot(timestamptz)'), ('world.price_history(uuid, int)')) as f(fn);

-- ── 1. THE SWEEP ───────────────────────────────────────────────────────────────────────────────
alter table public.price_history set (autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_opts   text[];
  v_cols   text;
  v_idx    int;
  v_pairs  int;
  v_rows   bigint;
  v_res    jsonb;
  v_now    bigint := public.drift_slot_of(now());
  v_keep   int := public.price_history_window();
  v_secs   numeric := public.wc_num('drift_slot_seconds');
begin
  -- (a) NOTHING ELSE MOVED: the writer and the read are their pre-images to the character.
  if exists (select 1 from defs_before_0095 d
              where replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '') <> d.def) then
    raise exception '0095 self-assert FAIL: a function this file must not touch changed';
  end if;

  select reloptions into v_opts from pg_class where oid = 'public.price_history'::regclass;
  if not ('autovacuum_vacuum_scale_factor=0' = any(v_opts) and 'autovacuum_vacuum_threshold=1000' = any(v_opts)) then
    raise exception '0095 self-assert FAIL: public.price_history reloptions are %, expected the sweep', v_opts;
  end if;

  -- The header's arithmetic rests on this shape: ONE index, the key (port_id, good_id, slot).
  select count(*) into v_idx from pg_index where indrelid = 'public.price_history'::regclass;
  select string_agg(a.attname, ',' order by k.ord) into v_cols
    from pg_constraint c
    cross join lateral unnest(c.conkey) with ordinality as k(attnum, ord)
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
   where c.conrelid = 'public.price_history'::regclass and c.contype = 'p';
  if v_idx <> 1 or v_cols is distinct from 'port_id,good_id,slot' then
    raise exception '0095 self-assert FAIL: public.price_history has % index(es), key (%) — the header no longer describes this table', v_idx, v_cols;
  end if;

  -- (b) ONE TICK'S PRUNE REACHES THE TRIGGER, driven — on an emptied record, rolled back. A full
  --     window is written one slot at a time, the next tick prunes the oldest slot, and that prune
  --     must kill at least 1,000 rows, or "swept every tick" is not what this file delivers.
  select count(*) into v_rows from public.price_history;
  begin
    delete from public.price_history;
    v_res := public.tick_price_snapshot(to_timestamp((v_now - v_keep) * v_secs) + interval '1 second');
    v_pairs := (v_res->>'wrote')::int;
    v_res := public.tick_price_snapshot(now());
    if (v_res->>'pruned')::int <> v_pairs or (v_res->>'wrote')::int <> v_pairs then
      raise exception '0095 self-assert FAIL: the tick one window later wrote % and pruned %, expected % and %', v_res->>'wrote', v_res->>'pruned', v_pairs, v_pairs;
    end if;
    if v_pairs < 1000 then
      raise exception '0095 self-assert FAIL: one tick prunes % row(s), under the 1,000-row sweep — the record would be swept less than every tick', v_pairs;
    end if;
    raise exception using errcode = 'P0950', message = '0095 probe rollback';
  exception when sqlstate 'P0950' then
    null;
  end;
  if (select count(*) from public.price_history) <> v_rows then
    raise exception '0095 self-assert FAIL: the probe leaked — the record holds % row(s), was %', (select count(*) from public.price_history), v_rows;
  end if;

  raise notice '0095 self-assert ok: THE PRICE RECORD IS SWEPT EVERY TICK. public.price_history carries autovacuum_vacuum_scale_factor=0 and autovacuum_vacuum_threshold=1000; it has one index, the key (port_id,good_id,slot); tick_price_snapshot and world.price_history are byte-identical to before this file. Driven on an emptied record and rolled back: one tick wrote % offered pair(s) and the tick one window (% slots) later pruned all % of them, at or over the 1,000-row trigger. Record unchanged at % row(s).',
    v_pairs, v_keep, v_pairs, v_rows;
end $$;

drop table defs_before_0095;
