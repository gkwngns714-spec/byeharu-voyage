-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0258 — A FEW HOUSES ARE CUT AT THE NORMAL CUT  (the hourly compactor rolls each house once, for good,
--        a few houses a transaction sized by the clock, so the quay is never held long)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, MEASURED (prod, 2026-10-27, the two hourly runs under 0257) ──────────────────────
-- 0257's batches of 100 houses compacted 26-30 k ledger rows and 41-47 k events a run, 0 failed, but:
--   * each batch held the quay lock (public.hold_the_quay) for ~20 s, so the arrivals beats that met one
--     waited for it: beats p95 9.0 s / 14.6 s and max 27.0 s / 26.0 s in xx:07-xx:10 (outside: p95 ~1.6 s);
--   * the compact phase ran 42-43 s against its 30 s budget (the budget was checked only BEFORE a batch);
--   * each batch compacted a 6-hour slice (0253), so a house's ledger stayed ~1,100 rows long and every
--     batch summed it twice per house (the explicit check and the deferred trigger), cold, from disk;
--   * the ended voyages were read fleet by fleet and their voyage_events / insurance rows deleted by the
--     cascade one voyage at a time.
--   Net drain ~10 k ledger rows an hour against ~800 k waiting: ~3-4 days.
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- 1. public.npc_compact_houses (THE rules, one authority; 2 hunks) reads the batch's ended voyages SET-BASED:
--    the batch's fleets, then `fleet_id = any(fleets)` on voyages_fleet_ended_0249 (one bitmap scan, each
--    page once, in block order), and deletes their voyage_events and their insured_voyages rows by
--    `voyage_id = any(...)` BEFORE the voyages. The same voyages go and so do the same child rows: those two
--    tables are the only ones that name a voyage, both ON DELETE CASCADE (prod catalog, 10-27), so the
--    cascade now finds nothing left to do. The keep rule (a voyage a route's OPEN lap still reads stays) is
--    the same rule, read once a batch from the open laps (standing_routes.lap_id → orders_route_lap: ~840
--    laps) instead of a pass over every done SAIL order (a seq scan of orders, measured ~1 s a batch on
--    the local world, paid by every batch however few its houses). Nothing else moves.
-- 2. tick_reconcile's compact step (3 hunks) compacts AT THE NORMAL CUT (now − npc_retention_hours: the
--    cut npc_compact always used), not a 6-hour slice, so a house is rolled once for good and from then on
--    her checks sum ~150 recent rows, not ~1,100 cold ones. The houses are taken in 0253's order (the one
--    with the oldest row awaiting a roll first), A FEW A TRANSACTION, SIZED BY THE CLOCK:
--      * the run measures every compaction transaction's time inside the lock (from the lock to the commit)
--        and keeps a rate, ms a house = the slower of the last transaction's and the run's mean;
--      * the next transaction takes as many houses as that rate fits in 1.5 s, 1 to 25 (the first of a run
--        is one house: no rate yet);
--      * it STARTS only if, at that rate, it ends inside the 30 s budget (0257 checked only the start);
--      * a batch that fails is rolled back whole and its houses are then done one a transaction, each
--        under the same check, so a bad house holds back only herself (0257's rule, kept).
--    The receipt drops `slices` / `upto` (no slices now) and adds `hold_ms`, `batch_ms_max`,
--    `batch_houses_max` and `ms_house`.
--    DECIDED BY DEFAULT: the hold target is 1.5 s, not 5 s. A beat that meets a transaction waits for all of
--    it, so a 5 s hold alone would put every such beat over the 2 s goal; 25 houses stays the ceiling.
--    The companies step (~5 s, one transaction) is unchanged and still holds the quay once an hour.
-- Batch ≡ house by house ≡ npc_compact, byte for byte: asserted below on a rolled-back probe, four ways.
-- public.npc_compact_house, public.npc_compact, the orders step, the purse invariant, credit, the beat and
-- the arrivals run are unchanged (md5). (Dev-log 2026-10-27-reconcile-timeout.md, "0258".)
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward slice reverses the five hunks below (each OLD text is here verbatim).
--
-- VERSION: 0258 (prod head 0257 when cut). Hunks cut from the LIVE bodies on prod at head 0257, LF-normalised.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.npc_compact_houses(uuid[],timestamptz)') is null or to_regclass('public.reconcile_runs') is null
     or to_regprocedure('public.hold_the_quay()') is null or to_regclass('public.insured_voyages') is null then
    raise exception '0258 refuses: 0257 is not in this world';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0258(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table defs_before_0258 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.npc_compact_houses(uuid[],timestamptz)'), ('public.tick_reconcile(boolean)')) f(fn);

create temp table before_0258 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p where p.oid in ('public.npc_compact(timestamptz)'::regprocedure,
                                         'public.npc_compact_house(uuid,timestamptz)'::regprocedure,
                                         'public.npc_compact_orders(timestamptz)'::regprocedure,
                                         'public.ledger_sum(uuid)'::regprocedure,
                                         'public.assert_ledger_reconciles(uuid)'::regprocedure,
                                         'public.credit(uuid,text,bigint,uuid)'::regprocedure,
                                         'public.hold_the_quay()'::regprocedure,
                                         'public.npc_upkeep_scope(timestamptz)'::regprocedure,
                                         'public.tick_arrivals(timestamptz)'::regprocedure,
                                         'public.tick_arrivals_each_second(int)'::regprocedure)) as others_md5;

-- the 0257 batch, kept for the self-assert's comparison run
do $$
begin
  if pg_temp.occurs_0258((select def from defs_before_0258 where fn = 'public.npc_compact_houses(uuid[],timestamptz)'),
                         'FUNCTION public.npc_compact_houses(') <> 1 then
    raise exception '0258 self-assert FAIL: npc_compact_houses''s definition does not name itself once';
  end if;
  execute replace((select def from defs_before_0258 where fn = 'public.npc_compact_houses(uuid[],timestamptz)'),
                  'FUNCTION public.npc_compact_houses(', 'FUNCTION pg_temp.npc_compact_houses_old_0258(');
end $$;

-- ── THE HUNKS ───────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0258 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0258 (fn, n, old, new) values
('public.npc_compact_houses(uuid[],timestamptz)', 1,
$h$  v_hs      uuid[];          -- the batch's merchants
$h$,
$h$  v_hs      uuid[];          -- the batch's merchants
  v_fl      uuid[];          -- 0258: their fleets
  v_vids    uuid[];          -- 0258: their ended voyages that go
  v_keepv   uuid[];          -- 0258: the voyages the routes' open laps still read (kept)
$h$),
('public.npc_compact_houses(uuid[],timestamptz)', 2,
$h$  delete from public.voyages v
   using public.fleets f
   where v.fleet_id = f.id and f.player_id = any(v_hs)
     and v.status <> 'SAILING' and v.eta < v_cut
     and not exists (select 1 from public.orders o
                       join public.standing_routes sr on sr.lap_id = o.route_lap_id
                      where o.verb = 'SAIL' and o.status = 'done'
                        and (o.result->>'voyage_id')::uuid = v.id);
  get diagnostics v_voy = row_count;
$h$,
$h$  -- 0258: THE SAME VOYAGES, READ AND CLEARED SET-BASED. The batch's fleets, then their ended voyages by
  -- `fleet_id = any(...)` (voyages_fleet_ended_0249: one bitmap scan, each page once, in block order); then
  -- their voyage_events and insured_voyages rows (the only two tables that name a voyage, both ON DELETE
  -- CASCADE) by `voyage_id = any(...)`, BEFORE the voyages, so the cascade finds nothing left. The same rows go.
  -- The voyages a route's open lap still reads stay (the same rule): read once, from the open laps
  -- (standing_routes.lap_id → orders_route_lap, one probe a lap), not by a pass over every SAIL order.
  v_keepv := array(select (o.result->>'voyage_id')::uuid
                     from public.standing_routes sr
                     cross join lateral (select o.result from public.orders o
                                          where o.route_lap_id = sr.lap_id and o.verb = 'SAIL' and o.status = 'done'
                                            and o.result->>'voyage_id' is not null) o
                    where sr.lap_id is not null);
  v_fl := array(select f.id from public.fleets f where f.player_id = any(v_hs) order by f.id);
  v_vids := array(select v.id from public.voyages v
                   where v.fleet_id = any(v_fl)
                     and v.status <> 'SAILING' and v.eta < v_cut
                     and not (v.id = any(v_keepv))
                   order by v.id);
  delete from public.voyage_events ve where ve.voyage_id = any(v_vids);
  delete from public.insured_voyages iv where iv.voyage_id = any(v_vids);
  delete from public.voyages v where v.id = any(v_vids);
  get diagnostics v_voy = row_count;
$h$),
('public.tick_reconcile(boolean)', 1,
$h$  -- 0253: the compactor's slices — compact every house as of v_slice, six hours past the last slice finished
  v_keep     interval;
  v_upto     timestamptz;          -- the last slice finished (from the last receipt that says)
  v_slice    timestamptz;
  v_slices   int := 0;
  -- 0257: the slice's houses, ~100 a transaction (public.npc_compact_houses)
  v_order    uuid[];
  v_batch    uuid[];
  v_bsize    constant int := 100;
  v_i        int;
  v_j        int;
  v_bfail    text;
  v_batches  int := 0;
$h$,
$h$  -- 0258: the compactor at the normal cut, a few houses a transaction, sized by the clock
  v_order    uuid[];
  v_batch    uuid[];
  v_retry    uuid[] := '{}';                 -- a failed batch's houses, done one a transaction next
  v_r        int := 1;
  v_i        int := 1;
  v_bsize    int;
  v_single   boolean;
  v_bfail    text;
  v_batches  int := 0;
  v_hold     constant numeric := 1500;      -- ms: the longest a compaction transaction should hold the quay
  v_bmax     constant int := 25;            -- houses a transaction, at most
  v_rate     numeric;                       -- ms a house: the slower of the last transaction's and the run's mean
  v_tb       timestamptz;
  v_bms      numeric;
  v_held     numeric := 0;                  -- ms the compaction transactions held the quay, all told
  v_heldh    int := 0;                      -- houses in them
  v_bmsmax   numeric := 0;
  v_bhmax    int := 0;
$h$),
('public.tick_reconcile(boolean)', 2,
$h$    -- 0253: THE OLDEST HOURS FIRST, SIX AT A TIME. A slice compacts every house as of v_slice (the same
    -- rules: public.npc_compact_house). Its houses all read the same few hours of rows, which lie together
    -- and stay in the cache; one house's whole backlog lay a row to a page across days (0249's first run:
    -- 12 houses in 30 s). A slice finished is kept in the receipt (`upto`); one the budget cut short is
    -- done again next hour. Compacting as of T, then as of a later T', leaves what compacting as of T'
    -- leaves (0253's self-assert).
    v_keep := make_interval(hours => public.wc_int('npc_retention_hours'));
    v_upto := (select (rr.receipt->'merchant_upkeep'->'compact'->>'upto')::timestamptz
                 from public.reconcile_runs rr
                where rr.at < v_now and rr.receipt->'merchant_upkeep'->'compact' ? 'upto'
                order by rr.at desc limit 1);
    loop
      -- the next slice: six hours past the last one finished, or past the oldest merchant ledger row still
      -- awaiting a roll beyond it, whichever is later (an empty stretch is jumped, not walked); never past now
      v_slice := least(v_now, greatest(coalesce(v_upto, '-infinity'::timestamptz),
                                       coalesce((select min(l.created_at) from public.ledger l
                                                   join public.players p on p.id = l.player_id and p.is_npc
                                                  where l.kind <> 'NPC_CARRIED'
                                                    and l.created_at >= coalesce(v_upto - v_keep, '-infinity'::timestamptz)) + v_keep,
                                                v_now))
                                + interval '6 hours');
      v_cleft := 0;
      -- the house with the oldest row awaiting a roll first (her NPC_CARRIED row skipped: two index entries),
      -- so a slice the budget cuts short is never short of the same houses twice
      v_order := array(select p.id from public.players p where p.is_npc
                        order by (select min(l.created_at) from public.ledger l
                                   where l.player_id = p.id and l.kind <> 'NPC_CARRIED') nulls last, p.id);
      -- 0257: A HUNDRED HOUSES A TRANSACTION (public.npc_compact_houses: the same rules, each page of the slice
      -- read once for the hundred, in block order; one house a transaction read a page per row). A batch that
      -- fails is rolled back whole, then its houses are done one at a time, each its own transaction, so a
      -- bad house holds back only herself. The 30 s budget is checked before every transaction.
      v_i := 1;
      while v_i <= coalesce(cardinality(v_order), 0) loop
        if clock_timestamp() >= v_cby then
          v_cleft := v_cleft + cardinality(v_order) - v_i + 1;
          exit;
        end if;
        v_batch := v_order[v_i : v_i + v_bsize - 1];
        v_i := v_i + v_bsize;
        v_bfail := null;
        if p_commit then perform public.hold_the_quay(); end if;
        perform public.npc_upkeep_scope(v_deadline);
        begin
          v_ch := public.npc_compact_houses(v_batch, v_slice);
          v_cvoy := v_cvoy + coalesce((v_ch->>'voyages')::int, 0);
          v_cled := v_cled + coalesce((v_ch->>'ledger_rolled')::int, 0);
          v_cev  := v_cev  + coalesce((v_ch->>'events')::int, 0);
          v_ctd  := v_ctd  + coalesce((v_ch->>'trade_daily')::int, 0);
          v_cdone := v_cdone + cardinality(v_batch);
          v_batches := v_batches + 1;
        exception when others then
          v_bfail := sqlerrm;
        end;
        if p_commit then commit; end if;
        if v_bfail is not null then
          v_cnote := coalesce(v_cnote, 'batch of ' || cardinality(v_batch) || ': ' || v_bfail);
          for v_j in 1 .. cardinality(v_batch) loop
            if clock_timestamp() >= v_cby then
              v_cleft := v_cleft + cardinality(v_batch) - v_j + 1;
              exit;
            end if;
            if p_commit then perform public.hold_the_quay(); end if;
            perform public.npc_upkeep_scope(v_deadline);
            begin
              v_ch := public.npc_compact_house(v_batch[v_j], v_slice);
              v_cvoy := v_cvoy + coalesce((v_ch->>'voyages')::int, 0);
              v_cled := v_cled + coalesce((v_ch->>'ledger_rolled')::int, 0);
              v_cev  := v_cev  + coalesce((v_ch->>'events')::int, 0);
              v_ctd  := v_ctd  + coalesce((v_ch->>'trade_daily')::int, 0);
              v_cdone := v_cdone + 1;
            exception when others then
              v_cfail := v_cfail + 1;
              v_cnote := coalesce(v_cnote, 'house ' || v_batch[v_j] || ': ' || sqlerrm);
            end;
            if p_commit then commit; end if;
          end loop;
        end if;
      end loop;
      exit when v_cleft > 0;   -- the budget ran out inside this slice: it is done again next hour
      v_upto := v_slice;
      v_slices := v_slices + 1;
      exit when v_slice >= v_now or clock_timestamp() >= v_cby;
    end loop;
$h$,
$h$    -- 0258: AT THE NORMAL CUT, A FEW HOUSES A TRANSACTION, SIZED BY THE CLOCK. Every house is compacted as
    -- of now (public.npc_compact_houses: its cut is now − npc_retention_hours, the cut npc_compact always
    -- used), so she is rolled once for good and her checks sum her recent rows only (0257's 6-hour slices
    -- kept ~1,100 cold rows a house in every check). The house with the oldest row awaiting a roll first
    -- (her NPC_CARRIED row skipped: two index entries), so the houses the budget leaves are first next hour.
    -- Each transaction is timed inside the quay lock; the next one takes as many houses as the measured
    -- rate fits in v_hold (1 to v_bmax; the run's first is one house), and it STARTS only if, at that rate,
    -- it ends inside the 30 s budget. A batch that fails is rolled back whole and its houses are then done
    -- one a transaction, under the same check, so a bad house holds back only herself.
    v_order := array(select p.id from public.players p where p.is_npc
                      order by (select min(l.created_at) from public.ledger l
                                 where l.player_id = p.id and l.kind <> 'NPC_CARRIED') nulls last, p.id);
    v_rate := v_hold;   -- no measurement yet: a house is assumed to take the whole hold
    loop
      v_single := v_r <= cardinality(v_retry);
      exit when not v_single and v_i > coalesce(cardinality(v_order), 0);
      if v_single then
        v_bsize := 1;
      else
        v_bsize := greatest(1, least(v_bmax, floor(v_hold / v_rate)::int,
                                     floor(extract(epoch from v_cby - clock_timestamp()) * 1000 / v_rate)::int));
      end if;
      if clock_timestamp() + make_interval(secs => (v_bsize * v_rate / 1000)::double precision) > v_cby then
        v_cleft := greatest(coalesce(cardinality(v_order), 0) - v_i + 1, 0) + cardinality(v_retry) - v_r + 1;
        exit;
      end if;
      if v_single then
        v_batch := array[v_retry[v_r]];
        v_r := v_r + 1;
      else
        v_batch := v_order[v_i : v_i + v_bsize - 1];
        v_i := v_i + v_bsize;
      end if;
      v_bfail := null;
      if p_commit then perform public.hold_the_quay(); end if;
      v_tb := clock_timestamp();
      perform public.npc_upkeep_scope(v_deadline);
      begin
        v_ch := public.npc_compact_houses(v_batch, v_now);
        v_cvoy := v_cvoy + coalesce((v_ch->>'voyages')::int, 0);
        v_cled := v_cled + coalesce((v_ch->>'ledger_rolled')::int, 0);
        v_cev  := v_cev  + coalesce((v_ch->>'events')::int, 0);
        v_ctd  := v_ctd  + coalesce((v_ch->>'trade_daily')::int, 0);
        v_cdone := v_cdone + cardinality(v_batch);
        if not v_single then v_batches := v_batches + 1; end if;
      exception when others then
        if v_single then
          v_cfail := v_cfail + 1;
          v_cnote := coalesce(v_cnote, 'house ' || v_batch[1] || ': ' || sqlerrm);
        else
          v_bfail := sqlerrm;
        end if;
      end;
      if p_commit then commit; end if;
      -- the rate: ms a house this transaction held the quay (its commit included), and the run's mean
      v_bms := extract(epoch from clock_timestamp() - v_tb) * 1000;
      v_held := v_held + v_bms;
      v_heldh := v_heldh + cardinality(v_batch);
      v_rate := greatest(v_bms / cardinality(v_batch), v_held / v_heldh, 1);
      v_bmsmax := greatest(v_bmsmax, v_bms);
      v_bhmax := greatest(v_bhmax, cardinality(v_batch));
      if v_bfail is not null then
        v_cnote := coalesce(v_cnote, 'batch of ' || cardinality(v_batch) || ': ' || v_bfail);
        v_retry := v_batch;
        v_r := 1;
      end if;
    end loop;
$h$),
('public.tick_reconcile(boolean)', 3,
$h$    'slices', v_slices, 'upto', v_upto,   -- 0253: slices finished this run; the last instant every house is compacted as of
    'batches', v_batches,                 -- 0257: transactions of ~100 houses that committed
$h$,
$h$    'batches', v_batches,                 -- 0257: batch transactions that committed (0258: sized by the clock)
    'hold_ms', v_hold, 'batch_ms_max', round(v_bmsmax), 'batch_houses_max', v_bhmax,   -- 0258: the longest hold
    'ms_house', round(v_rate, 1),         -- 0258: the measured rate the last transaction was sized by
$h$);

create or replace function pg_temp.recut_0258(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0258 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0258 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0258(v_def, h.old);
    if v_n <> 1 then
      raise exception '0258 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0258(fn) from defs_before_0258 order by fn;

comment on function public.npc_compact_houses(uuid[], timestamptz) is
  '0257: THE merchant compaction rules, set-based for a batch of houses (each step one statement, each page read once; 0258: the ended voyages too, their voyage_events and insurance cleared before them). public.npc_compact_house is the batch of one; public.tick_reconcile runs a few houses a transaction, sized by the clock. Server-only.';

-- ── THE PROBE: the new batch leaves what the 0257 batch, the house step and npc_compact leave ──────
-- Four houses with rows from before a 2026-08-01 cut (earlier than every real row on prod — the first are
-- from 2026-08-22 — so only the probe's rows are touched): A and C merchants with rows to roll, B a merchant
-- with ONE old ledger row (not rolled, her old events still go), P a PLAYER (never touched). Each has two
-- ended voyages before the cut and one after it, each with voyage_events and an insurance row; of the two old
-- ones, a merchant's route's OPEN lap reads one (it stays) and a closed lap names the other (it goes). Compacted from the same rolled-back state four ways: (old) the 0257 batch, kept in
-- pg_temp; (batch) the new public.npc_compact_houses; (one) public.npc_compact_house house by house; (all)
-- public.npc_compact, the whole world. All four must leave byte-identical rows and the same answers.
create or replace function pg_temp.digest_0258(p_house uuid)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'ledger', (select md5(coalesce(string_agg(concat_ws('|', l.kind, l.ducats_delta, l.balance_after, l.ref_event_id, l.created_at),
                                              ',' order by l.created_at, l.kind, l.ducats_delta, l.ref_event_id), ''))
                 from public.ledger l where l.player_id = p_house),
    'ledger_n', (select count(*) from public.ledger l where l.player_id = p_house),
    'carried', (select count(*) from public.ledger l where l.player_id = p_house and l.kind = 'NPC_CARRIED'),
    'events', (select md5(coalesce(string_agg(ev.id::text, ',' order by ev.id), '')) from public.events ev where ev.player_id = p_house),
    'events_n', (select count(*) from public.events ev where ev.player_id = p_house),
    'voyages', (select md5(coalesce(string_agg(v.id::text, ',' order by v.id), '')) from public.voyages v
                  join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'voyages_n', (select count(*) from public.voyages v join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'voyage_events', (select md5(coalesce(string_agg(concat_ws('|', ve.voyage_id, ve.day_index, ve.kind), ',' order by ve.voyage_id, ve.day_index), ''))
                        from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
                        join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'voyage_events_n', (select count(*) from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
                          join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'insured', (select md5(coalesce(string_agg(concat_ws('|', iv.voyage_id, iv.value, iv.written_at), ',' order by iv.voyage_id), ''))
                  from public.insured_voyages iv where iv.player_id = p_house),
    'insured_n', (select count(*) from public.insured_voyages iv where iv.player_id = p_house),
    'trade_daily', (select md5(coalesce(string_agg(concat_ws('|', td.port_id, td.good_id, td.game_day, td.qty), ',' order by td.game_day), ''))
                      from public.trade_daily td where td.player_id = p_house),
    'purse', (select p.ducats from public.players p where p.id = p_house),
    'ledger_sum', public.ledger_sum(p_house))
$$;

create or replace function pg_temp.run_0258(p_how text, p_houses uuid[], p_now timestamptz)
returns jsonb
language plpgsql
as $$
declare
  v_a jsonb := '{}'::jsonb;
  v_r jsonb;
  v_d jsonb := '{}'::jsonb;
  h   uuid;
  k   text;
begin
  begin
    if p_how = 'old' then
      v_a := pg_temp.npc_compact_houses_old_0258(p_houses, p_now);
    elsif p_how = 'batch' then
      v_a := public.npc_compact_houses(p_houses, p_now);
    elsif p_how = 'all' then
      v_a := public.npc_compact(p_now) - 'orders' - 'before';
    else
      foreach h in array (select array_agg(x order by x) from unnest(p_houses) x) loop
        v_r := public.npc_compact_house(h, p_now);
        for k in select jsonb_object_keys(v_r) loop
          v_a := v_a || jsonb_build_object(k, coalesce((v_a->>k)::int, 0) + (v_r->>k)::int);
        end loop;
      end loop;
    end if;
    foreach h in array p_houses loop
      v_d := v_d || jsonb_build_object(h::text, pg_temp.digest_0258(h));
    end loop;
    raise exception using errcode = 'ZY258',
      message = jsonb_build_object('a', v_a, 'd', v_d)::text;
  exception when sqlstate 'ZY258' then
    return sqlerrm::jsonb;
  end;
end $$;

do $$
declare
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  c_now   constant timestamptz := '2026-08-01 00:00:00+00';
  c_old   constant timestamptz := '2026-07-31 12:00:00+00';   -- before the cut (2026-07-31 18:00)
  v_res   jsonb;
begin
  select * into v_before from before_0258;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved; nothing else moved
  for v_d in select * from defs_before_0258 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0258 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0258(v_def, v_h.new) <> 1 then
        raise exception '0258 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0258 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0258 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid in ('public.npc_compact(timestamptz)'::regprocedure,
                                       'public.npc_compact_house(uuid,timestamptz)'::regprocedure,
                                       'public.npc_compact_orders(timestamptz)'::regprocedure,
                                       'public.ledger_sum(uuid)'::regprocedure,
                                       'public.assert_ledger_reconciles(uuid)'::regprocedure,
                                       'public.credit(uuid,text,bigint,uuid)'::regprocedure,
                                       'public.hold_the_quay()'::regprocedure,
                                       'public.npc_upkeep_scope(timestamptz)'::regprocedure,
                                       'public.tick_arrivals(timestamptz)'::regprocedure,
                                       'public.tick_arrivals_each_second(int)'::regprocedure)) <> v_before.others_md5 then
    raise exception '0258 self-assert FAIL: npc_compact, the house step, the orders step, the purse invariant, credit, the quay lock, the scope, the beat or the arrivals run moved';
  end if;
  v_def := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0258(v_def, 'public.npc_compact_houses(v_batch, v_now)') <> 1
     or pg_temp.occurs_0258(v_def, 'public.npc_compact_houses(') <> 1
     or pg_temp.occurs_0258(v_def, 'public.npc_compact_house(') <> 0
     or pg_temp.occurs_0258(v_def, 'v_slice') <> 0
     or pg_temp.occurs_0258(v_def, 'if p_commit then perform public.hold_the_quay(); end if;') <> 4
     or pg_temp.occurs_0258(v_def, 'if p_commit then commit; end if;') <> 4 then
    raise exception '0258 self-assert FAIL: tick_reconcile does not compact at the normal cut through the one batch call, each transaction after the quay lock';
  end if;
  v_def := replace(pg_get_functiondef('public.npc_compact_houses(uuid[],timestamptz)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0258(v_def, 'using public.fleets f') <> 0
     or pg_temp.occurs_0258(v_def, 'delete from public.voyage_events ve where ve.voyage_id = any(v_vids);') <> 1
     or pg_temp.occurs_0258(v_def, 'delete from public.insured_voyages iv where iv.voyage_id = any(v_vids);') <> 1
     or pg_temp.occurs_0258(v_def, 'delete from public.voyages v where v.id = any(v_vids);') <> 1 then
    raise exception '0258 self-assert FAIL: the batch does not clear its voyages set-based';
  end if;
  -- the only tables that name a voyage are the two cleared before it (a third would need its own step)
  if (select count(*) from pg_constraint c where c.contype = 'f' and c.confrelid = 'public.voyages'::regclass) <> 2
     or (select count(*) from pg_constraint c where c.contype = 'f' and c.confrelid = 'public.voyages'::regclass
           and c.conrelid in ('public.voyage_events'::regclass, 'public.insured_voyages'::regclass) and c.confdeltype = 'c') <> 2 then
    raise exception '0258 self-assert FAIL: a table other than voyage_events and insured_voyages names a voyage';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and p.oid <> 'public.tick_reconcile(boolean)'::regprocedure
         and p.oid <> 'public.tick_arrivals_each_second(int)'::regprocedure
         and pg_get_functiondef(p.oid) like '%hold_the_quay()%'
         and p.oid <> 'public.hold_the_quay()'::regprocedure) <> 0 then
    raise exception '0258 self-assert FAIL: another function takes the quay lock';
  end if;
  if has_function_privilege('anon', 'public.npc_compact_houses(uuid[], timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_compact_houses(uuid[], timestamptz)', 'execute') then
    raise exception '0258 self-assert FAIL: a client can run the batch compactor';
  end if;

  -- (b) THE NEW BATCH LEAVES WHAT THE 0257 BATCH, THE HOUSE STEP AND npc_compact LEAVE (rolled back whole)
  begin
    declare
      v_a    uuid; v_b uuid; v_c uuid; v_p uuid;
      v_all4 uuid[];
      v_port uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1);
      v_port2 uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_port order by p.code limit 1);
      v_good uuid := (select g.id from public.goods g order by g.code limit 1);
      v_gd   int := world.game_day(c_now);
      v_old jsonb; v_batch jsonb; v_one jsonb; v_all jsonb; v_pre jsonb := '{}'::jsonb;
      v_m   uuid; v_f uuid; v_k int;
      e1 uuid; e2 uuid; e3 uuid; e4 uuid; v0 uuid; v1 uuid; v2 uuid; v_sr uuid; v_lap uuid; v_lap0 uuid;
    begin
      if not public.npc_traders_on() then
        update public.world_config set value = 'true'::jsonb
         where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
        if not public.npc_traders_on() then
          raise exception '0258 self-assert FAIL: cannot light the merchants for the probe';
        end if;
      end if;
      v_a := public.new_house(null, 'Casa dos Poucos A 0258', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_b := public.new_house(null, 'Casa dos Poucos B 0258', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_c := public.new_house(null, 'Casa dos Poucos C 0258', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_p := public.new_house(null, 'Casa dos Poucos P 0258', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => false);
      v_all4 := array[v_a, v_b, v_c, v_p];
      v_k := 0;
      foreach v_m in array v_all4 loop
        v_k := v_k + 1;
        v_f := (select f.id from public.fleets f where f.player_id = v_m order by f.created_at limit 1);
        if v_f is null then
          insert into public.fleets (player_id, name, port_id) values (v_m, 'Poucos 0258 ' || v_k, v_port) returning id into v_f;
        end if;
        e1 := gen_random_uuid(); e2 := gen_random_uuid(); e3 := gen_random_uuid(); e4 := gen_random_uuid();
        v0 := gen_random_uuid(); v1 := gen_random_uuid(); v2 := gen_random_uuid();
        -- E1, E2 old (both go), E3 named by a kept ledger row (stays), E4 FOUNDED (stays)
        insert into public.events (id, player_id, kind, payload, created_at) values
          (e1, v_m, 'PROBE_0258', '{}', c_old - interval '3 hours'), (e2, v_m, 'PROBE_0258', '{}', c_old),
          (e3, v_m, 'PROBE_0258', '{}', c_old), (e4, v_m, 'FOUNDED', '{}', c_old - interval '1 day');
        if v_m = v_b then
          -- B: ONE old ledger row (summing to 0 with the purse kept): nothing to roll; E2 is not named by it
          insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at) values
            (v_m, 'PROBE_0258', 0, 1000, null, c_old - interval '2 hours'),
            (v_m, 'PROBE_0258', 0, 1000, e3, c_now);
        else
          -- old rows summing to 0 (C's amounts differ from A's), one of them naming E2; E3 named by a new row
          insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at) values
            (v_m, 'PROBE_0258', 100 * v_k, 1000 + 100 * v_k, null, c_old - interval '3 hours'),
            (v_m, 'PROBE_0258', 300, 1300 + 100 * v_k, null, c_old - interval '2 hours'),
            (v_m, 'PROBE_0258', -300 - 100 * v_k + 50, 1050, null, c_old - interval '1 hour'),
            (v_m, 'PROBE_0258', -50, 1000, e2, c_old),
            (v_m, 'PROBE_0258', 0, 1000, e3, c_now);
        end if;
        -- V0, V1 ended before the cut (V0 goes with its voyage_events and insurance; V1 too, but for a
        -- merchant's open lap below); V2 ended after it (stays)
        insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status,
                                    origin_port_id, dest_port_id, created_at) values
          (v0, v_f, v_m, '[]', 100, '{}', c_old - interval '1 day', c_old - interval '3 hours', 'ARRIVED', v_port, v_port2, c_old - interval '1 day'),
          (v1, v_f, v_m, '[]', 100, '{}', c_old - interval '2 hours', c_old, 'ARRIVED', v_port2, v_port, c_old - interval '2 hours'),
          (v2, v_f, v_m, '[]', 100, '{}', c_old, c_now, 'ARRIVED', v_port, v_port2, c_old);
        -- V1 is read by her route's OPEN lap (a done SAIL order of that lap names it): it stays, old as it is;
        -- V0 is named by a done SAIL order of a CLOSED lap: it goes
        if v_m <> v_p then
          v_sr := gen_random_uuid(); v_lap := gen_random_uuid(); v_lap0 := gen_random_uuid();
          insert into public.standing_routes (id, player_id, name, fleet_id) values (v_sr, v_m, 'Poucos 0258', null);
          insert into public.standing_route_laps (id, route_id, lap_no, started_at, closed_at) values
            (v_lap0, v_sr, 1, c_old - interval '1 day', c_old - interval '3 hours'),
            (v_lap, v_sr, 2, c_old - interval '2 hours', null);
          update public.standing_routes set lap_id = v_lap, lap_no = 2 where id = v_sr;
          insert into public.orders (fleet_id, player_id, seq, raw_text, verb, status, result, route_lap_id) values
            (v_f, v_m, 900001, 'SAIL probe 0258', 'SAIL', 'done', jsonb_build_object('voyage_id', v0), v_lap0),
            (v_f, v_m, 900002, 'SAIL probe 0258', 'SAIL', 'done', jsonb_build_object('voyage_id', v1), v_lap),
            (v_f, v_m, 900003, 'SAIL probe 0258', 'SAIL', 'done', '{}'::jsonb, v_lap);
        end if;
        insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
        select v.id, d.i, k.code, '{}', c_old
          from (values (v0), (v1), (v2)) v(id), generate_series(1, 2) d(i),
               (select code from public.voyage_event_kinds order by code limit 1) k;
        insert into public.insured_voyages (voyage_id, fleet_id, player_id, port_id, cargo, basis, value, risk, price, keep_pct, written_at)
        select v.id, v_f, v_m, v_port, '{}', '{}', 100 + v_k, 0.1, 10, 0.1, v.w
          from (values (v0, c_old - interval '1 day'), (v1, c_old - interval '2 hours'), (v2, c_old)) v(id, w);
        insert into public.trade_daily (player_id, port_id, good_id, game_day, qty) values
          (v_m, v_port, v_good, v_gd - 2, 3), (v_m, v_port, v_good, v_gd - 1, 5), (v_m, v_port, v_good, v_gd, 7);
        v_pre := v_pre || jsonb_build_object(v_m::text, pg_temp.digest_0258(v_m));
      end loop;

      v_old   := pg_temp.run_0258('old',   v_all4, c_now);
      v_batch := pg_temp.run_0258('batch', v_all4, c_now);
      v_one   := pg_temp.run_0258('one',   v_all4, c_now);
      v_all   := pg_temp.run_0258('all',   v_all4, c_now);

      if v_old->'d' is distinct from v_batch->'d' or v_old->'d' is distinct from v_one->'d' or v_old->'d' is distinct from v_all->'d' then
        raise exception '0258 self-assert FAIL: the new batch left other rows than the 0257 batch (old %, batch %, one %, whole world %)',
          v_old, v_batch, v_one, v_all;
      end if;
      if v_old->'a' is distinct from v_batch->'a' or v_old->'a' is distinct from v_one->'a' or v_old->'a' is distinct from v_all->'a' then
        raise exception '0258 self-assert FAIL: the new batch answered otherwise than the 0257 batch (old %, batch %, one %, whole world %)',
          v_old->'a', v_batch->'a', v_one->'a', v_all->'a';
      end if;
      -- what went is exactly what the rules say: A and C roll 4 rows into 1 and lose E1, E2, V0 (with its 2
      -- voyage_events and its insurance row), two trade days; B rolls nothing (one old row) and loses E1, E2,
      -- V0, two trade days; every merchant keeps V1 (her open lap reads it) and V2 and their rows; P is untouched
      if v_old->'a' <> jsonb_build_object('voyages', 3, 'ledger_rolled', 8, 'events', 6, 'trade_daily', 6) then
        raise exception '0258 self-assert FAIL: the probe did not compact as the rules say: %', v_old->'a';
      end if;
      if v_old->'d'->v_p::text is distinct from v_pre->v_p::text then
        raise exception '0258 self-assert FAIL: a player''s rows were touched (before %, after %)', v_pre->v_p::text, v_old->'d'->v_p::text;
      end if;
      foreach v_m in array array[v_a, v_b, v_c] loop
        if (v_old->'d'->v_m::text->>'voyages_n')::int <> (v_pre->v_m::text->>'voyages_n')::int - 1
           or (v_old->'d'->v_m::text->>'voyage_events_n')::int <> (v_pre->v_m::text->>'voyage_events_n')::int - 2
           or (v_old->'d'->v_m::text->>'insured_n')::int <> (v_pre->v_m::text->>'insured_n')::int - 1
           or (v_old->'d'->v_m::text->>'insured_n')::int < 2
           or (v_old->'d'->v_m::text->>'events_n')::int <> (v_pre->v_m::text->>'events_n')::int - 2 then
          raise exception '0258 self-assert FAIL: house % did not lose exactly her one unread old voyage and its rows (before %, after %)',
            v_m, v_pre->v_m::text, v_old->'d'->v_m::text;
        end if;
      end loop;
      foreach v_m in array array[v_a, v_c] loop
        if (v_old->'d'->v_m::text->>'carried')::int <> 1
           or (v_old->'d'->v_m::text->>'ledger_n')::int <> (v_pre->v_m::text->>'ledger_n')::int - 3
           or (v_old->'d'->v_m::text->>'ledger_sum')::bigint <> (v_pre->v_m::text->>'purse')::bigint
           or (v_old->'d'->v_m::text->>'purse')::bigint <> (v_pre->v_m::text->>'purse')::bigint then
          raise exception '0258 self-assert FAIL: house % did not roll as the rules say (before %, after %)',
            v_m, v_pre->v_m::text, v_old->'d'->v_m::text;
        end if;
      end loop;
      if (v_old->'d'->v_b::text->>'carried')::int <> 0
         or (v_old->'d'->v_b::text->>'ledger')::text <> (v_pre->v_b::text->>'ledger')::text then
        raise exception '0258 self-assert FAIL: the one-row house did not compact as the rules say (before %, after %)',
          v_pre->v_b::text, v_old->'d'->v_b::text;
      end if;
      v_res := jsonb_build_object('answer', v_batch->'a', 'houses', 4);
      raise exception using errcode = 'ZY25F', message = v_res::text;
    end;
  exception when sqlstate 'ZY25F' then
    v_res := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.players where company_name like 'Casa dos Poucos % 0258') then
    raise exception '0258 self-assert FAIL: a probe house was left behind';
  end if;

  -- (c) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0258 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0258 self-assert FAIL: a wall moved';
  end if;

  raise notice '0258 self-assert ok: A FEW HOUSES ARE CUT AT THE NORMAL CUT. public.npc_compact_houses clears its ended voyages set-based, their voyage_events and insurance before them, the open laps'' voyages read once (2 hunks); tick_reconcile compacts at the normal cut, a few houses a transaction sized by the measured rate to a 1.5 s hold (1 to 25), none started unless it ends inside the 30 s budget (3 hunks); all reverse to their pre-images, ACL / volatility / definer / config unmoved; npc_compact, the house step, the orders step, ledger_sum, assert_ledger_reconciles, credit, the quay lock, the scope, the beat and tick_arrivals unmoved; no other function takes the quay lock; only voyage_events and insured_voyages name a voyage; registry unchanged; walls 0. PROBE (3 merchants + 1 player, rows before a 2026-08-01 cut, an open lap keeping one old voyage, rolled back): the 0257 batch, the new batch, the house step and npc_compact left byte-identical rows and answers: %. The player untouched. Nothing left behind.',
    v_res;
end $$;
