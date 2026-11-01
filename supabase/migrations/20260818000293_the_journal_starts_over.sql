-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0293 — THE JOURNAL STARTS OVER   (a LOAD-ONLY slice: a 2.1 M-row cache of live totals is wiped and re-seeded from the world itself)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY (prod, read-only, head 0290, 2026-11-01 ~13:25 → 15:20 UTC) ────────────────────────────
-- The Stats "right now" band reads world.stats_now() = the base row public.stats_live + the SUM of every row of the journal
-- public.stats_live_deltas (0224: one row per change, folded away by the count). The count was dead from 2026-10-30 18:21 until
-- 2026-11-01 15:06, so nothing was folded: the journal holds ~2,147,539 rows (250 MB; ~7 a second more) and every stats_now() call sums
-- all of them — 57.8 s per call on the saturated disk, every second, per open Stats tab (the client asks again as soon as one answers).
-- 0290 made the fold drain in 300,000-row batches, but only while a count has budget left, and the count is still near its 120 s wall: it
-- would take many runs. The owner (2026-11-01): "if there is a big load of data that is causing this slowness, remove them and start over".
--
-- ── WHY IT IS SAFE TO START OVER ───────────────────────────────────────────────────────────────
-- The journal is a CACHE, not a record: base + Σ journal = the live figures, and the base is SET to the world's own aggregates (players',
-- merchants' and cities' ducats, escrows, accruals, fleets at sea) by every fold (public.stats_live_fold's `a`). The seed step 0224 itself
-- used (`p_seed = true`) does exactly this from an empty journal. No player-owned row, ledger line, event, order or stats HISTORY row is
-- read for deletion: the history tables (stats_world/_good/_city/_city_goods/_merchants) are NOT touched.
--
-- ── WHAT CHANGES (one DO block, so one transaction; see the note inside it) ────────────────────────────────────────────────────────────
--   lock table public.stats_live_deltas in access exclusive mode;     -- writers wait, nothing is lost: they commit AFTER this
--   truncate public.stats_live_deltas;                                 -- the 2.1 M rows go (instant; the heap file is dropped)
--   update public.stats_live set counted_through = clock_timestamp();  -- "trades since the count" starts now: its windows are empty
--   perform public.stats_live_fold(clock_timestamp(), true);           -- base := the aggregates, drift := {}, folded := 0, in one statement
-- Under the lock no writer can add a delta between the wipe and the reseed, so base + (empty) journal is exactly the world at the commit.
--
-- ── WHAT DOES NOT MOVE ────────────────────────────────────────────────────────────────────────
-- No function body, row of any other table, grant, knob, switch, schedule or cron job. Asserted below: every function in public/cmd/world/voyage
-- md5-unmoved, the registry count, the walls (0/0/0) and both owner switches as found. The journal's writers (public.stats_live_add and its
-- triggers) are untouched and write the new, empty table from the commit on.
--
-- ── SELF-ASSERT (catalog + the table's own lock; nothing counts or sums a growing table) ──────────
--   (a) the guard: both tables exist, public.stats_live holds exactly its one row;
--   (b) under the lock, after the wipe and the reseed: the journal is EMPTY (the lock makes this exact), stats_live has folded = 0, an empty
--       drift and counted_through at or after the lock; world.stats_now() serves exactly the base (nothing journalled yet);
--   (c) every function unmoved by md5, the registry, the walls and the two switches as found.
--   Printed, never asserted: the journal's estimated rows and bytes before, the seconds under the lock.
-- ROLLBACK: none needed and none possible by design — a journal row is a delta against a base that is itself re-derivable; the next count's
--   fold keeps the cache honest (it reconciles base against the aggregates and records any drift).
-- VERSION: 0293 — prod head 0290 today. 0291 (the laps' autovacuum) and 0292 (the port_goods rewrite) deploy first.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. GUARD ────────────────────────────────────────────────────────────────────────────────────
do $guard$
begin
  perform set_config('statement_timeout', '10min', false);
  perform set_config('lock_timeout', '5s', false);
  if to_regclass('public.stats_live_deltas') is null or to_regclass('public.stats_live') is null then
    raise exception '0293 refuses: public.stats_live or public.stats_live_deltas is not in this world';
  end if;
  if (select count(*) from public.stats_live) <> 1 then
    raise exception '0293 refuses: public.stats_live must hold exactly its one row';
  end if;
end $guard$;

-- ── 1. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table before_0293 as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns_md5,
       (select value from public.world_config where key = 'economy_closed') as economy_closed,
       (select value from public.world_config where key = 'city_treasury_enabled') as city_treasury_enabled,
       (select c.reltuples::bigint from pg_class c where c.oid = 'public.stats_live_deltas'::regclass) as est_rows,
       pg_total_relation_size('public.stats_live_deltas') as bytes_before;

create temp table clock_0293 (k text primary key, t timestamptz not null);

-- ── 3. THE SELF-ASSERT (the last statement of the file) ─────────────────────────────────────────
do $assert$
declare
  f      record;
  l      record;
  v_n    bigint;
  v_now  jsonb;
  v_t_lock   timestamptz;
  v_t_done   timestamptz;
begin
  -- THE LOCK, THE WIPE, THE RESEED AND THE ASSERTS IN ONE BLOCK: they share one transaction, so the lock is held across all of them. (The
  -- deploy runner is NOT a transaction block: a bare top-level LOCK TABLE is refused there — prod push 2026-11-01 15:49, `LOCK TABLE can only be
  -- used in transaction blocks` — and a statement boundary may end the implicit transaction, so nothing that needs the lock may sit outside this block.)
  lock table public.stats_live_deltas in access exclusive mode;
  insert into clock_0293 values ('locked', clock_timestamp());

  truncate public.stats_live_deltas;

  update public.stats_live set counted_through = clock_timestamp() where id;
  perform public.stats_live_fold(clock_timestamp(), true);
  insert into clock_0293 values ('reseeded', clock_timestamp());

  select * into f from before_0293;
  select t into v_t_lock from clock_0293 where k = 'locked';
  select t into v_t_done from clock_0293 where k = 'reseeded';

  -- (b) the journal is empty (exact: this transaction holds the table's ACCESS EXCLUSIVE lock) and the base is the reseeded one
  select count(*) into v_n from public.stats_live_deltas;
  if v_n <> 0 then
    raise exception '0293 self-assert FAIL: the journal holds % row(s) after the wipe, under the lock', v_n;
  end if;
  select * into l from public.stats_live;
  if l.folded <> 0 or l.drift is distinct from '{}'::jsonb or l.counted_through < v_t_lock then
    raise exception '0293 self-assert FAIL: the base was not re-seeded (folded %, drift %, counted_through % vs lock %)',
      l.folded, l.drift, l.counted_through, v_t_lock;
  end if;
  v_now := world.stats_now();
  if (v_now->>'players')::bigint <> l.players or (v_now->>'merchants')::bigint <> l.merchants
     or (v_now->>'cities')::bigint <> l.cities or (v_now->>'set_aside')::bigint <> l.set_aside
     or (v_now->>'at_sea')::bigint <> l.at_sea or (v_now->'since_count'->>'trades')::bigint <> l.trades then
    raise exception '0293 self-assert FAIL: world.stats_now() does not serve exactly the re-seeded base over an empty journal';
  end if;

  -- (c) nothing else moved
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> f.fns
     or (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> f.fns_md5 then
    raise exception '0293 self-assert FAIL: a function in public/cmd/world/voyage moved or was added — this file creates and changes none';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> f.entry_points
     or (select value from public.world_config where key = 'economy_closed') is distinct from f.economy_closed
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from f.city_treasury_enabled then
    raise exception '0293 self-assert FAIL: the registry or an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0293 self-assert FAIL: a wall moved';
  end if;

  raise notice '0293 self-assert ok: THE JOURNAL STARTS OVER. public.stats_live_deltas was wiped (estimated % rows, % bytes before) under one ACCESS EXCLUSIVE lock and is EMPTY; public.stats_live was re-seeded from the world''s own totals (folded 0, drift {}, counted_through at the lock), and world.stats_now() serves exactly that base over the empty journal. No stats history table was touched. Every function in public/cmd/world/voyage unmoved by md5 (% functions), the registry unchanged at % entry points, the walls 0 / 0 / 0, both owner switches as found. Printed, never asserted: % s under the lock (wipe + reseed), % s from the lock through the last assert.',
    f.est_rows, f.bytes_before, f.fns, f.entry_points,
    round(extract(epoch from v_t_done - v_t_lock)::numeric, 2),
    round(extract(epoch from clock_timestamp() - v_t_lock)::numeric, 2);

  drop table if exists pg_temp.before_0293, pg_temp.clock_0293;
end $assert$;

reset statement_timeout;
reset lock_timeout;
