-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0265 — EACH HOUSE IS CUT UNDER HER OWN LOCK, EVERY MINUTE  (the compactor leaves the quay: a few houses
--        a transaction, each house's own row locked in one order and never waited for, a slice every minute)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ROOT CAUSE, MEASURED (prod, read-only, head 0263, 2026-10-28 02:07-02:24 UTC) ─────────────
-- The merchant ledger rows waiting past the 6 h cut GROW: 809 k (10-27 20:41) → 898 k (10-28 02:10) → 901,951
-- (02:24). 20,199 rows crossed the cut in the last hour; a run clears 4.6-6.0 k (0260: 01:07, 02:07). Every
-- one of the 821 houses still has rows from 10-25 23:0x-23:5x waiting (her oldest unrolled row, p5/p50/p95);
-- her ledger holds p50 1,207 rows (p95 2,173, max 3,748), and summing all 821 of them takes 3.3 s.
-- WHY: one GLOBAL lock, public.hold_the_quay() (0249), serialises EVERY reconcile write step against the
-- per-second arrivals beat, and the compactor gets ONE 30 s window an hour inside it. 0260's receipts: the
-- compactor held the quay 13.9 / 17.0 s and WAITED for it 14.9 / 16.9 s (01:07 / 02:07): half its window is
-- spent queueing behind beats, which are themselves slowed by the queue (02:07: q up to 4.0 s, runs to 7.2 s,
-- 74 fleets due at once). 0258-0260 retuned the batch inside that window; none of them could move the window.
-- The writers that take the quay (pg_proc, every body naming hold_the_quay): the beat
-- (tick_arrivals_each_second), and four in tick_reconcile: each merchant's tend step, the companies' step, the
-- orders' step and each compaction transaction.
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- (1) public.npc_compact_locked(houses[], at): THE compaction transaction's lock. It locks the batch's
--     merchant rows in public.players — ascending id, FOR NO KEY UPDATE SKIP LOCKED — and runs THE rules,
--     public.npc_compact_houses (unchanged, md5-asserted), on the houses it got. A house a beat (or a tend
--     step) is writing is skipped, not waited for: she is first in line next minute. A beat that touches a
--     house being cut waits for that one transaction (sized to ~200 ms); a beat that does not, waits for
--     nothing. The rules' own reads stay as 0257/0258 made them: each page once, in block order.
-- (2) public.tick_compact(): THE compactor, every minute (pg_cron byeharu-voyage:compact, '* * * * *',
--     CALL; defined inactive, wind_the_clock() starts it with the clock). The due houses (a merchant whose
--     oldest unrolled ledger row is over an hour past the cut), oldest first; a few a transaction, each
--     batch compacted as of (its newest house's oldest row + retention + 6 h), never later than now — so a
--     backlog is walked oldest hours first, six hours a visit, the houses of a batch reading the same pages
--     (0253/0259's slices, kept per house in the rows themselves: no slice state, nothing re-done). Each
--     transaction is timed from its lock to its commit; the next takes as many houses as that rate fits in
--     200 ms (1 to 25); none starts unless it ends inside the minute's 8 s budget. A batch that fails is
--     rolled back whole and redone a house a transaction. The orders' step (public.npc_compact_orders,
--     unchanged) runs at :07, once an hour, after THE HOUR'S SWEEP: every merchant not due, compacted as of now
--     (the hourly pass npc_compact always made, so a house with no ledger row to roll still loses her old events,
--     voyages and trade days). One receipt a minute: public.compact_runs (a 1,440-row ring).
-- (3) tick_reconcile (2 hunks): the compactor's block and its locals leave the hourly run. Its merchants'
--     tend steps and the companies' step keep the quay, unchanged.
--
-- ── WHY THE QUAY STAYS FOR THE TEND AND COMPANIES STEPS (decided by default, the brief's design checked) ─
-- Per-house locks in one order are deadlock-free only if EVERY lock a writer takes belongs to a house and
-- is taken in that order. The beat, a tend step and the companies' step also lock the HARBOURS: city_pays /
-- treasury_post take the house's row FIRST, then the harbour's lock (public.treasury_lock, 0122/0123) — per
-- act. The beat does many acts in one transaction (house A, harbour X, then house B, harbour X, …), so it
-- holds a harbour while it asks for the next house. A tend step for house B that holds B and asks for
-- harbour X closes the cycle: that is the 10-27 04:07 deadlock that 0249's quay ended. Ordering those
-- writers by house would mean the beat locks every house and harbour it will touch before its first act —
-- a rewrite of tick_arrivals, which this file does not do. THE COMPACTOR IS DIFFERENT: it never touches a
-- harbour, a quay or a purse, and the only row it shares with any writer is the house's players row (the
-- NPC_CARRIED insert's foreign key). So it alone leaves the quay, and the drain then shrinks every house's
-- ledger, which is most of the companies' step (3.3 s of ledger sums) and of the hourly check.
--
-- ── NO DEADLOCK, BY CONSTRUCTION ───────────────────────────────────────────────────────────────
-- A deadlock is a cycle of waits. A transaction that never waits is on no cycle. The compactor's
-- transaction takes one row lock that another writer also takes — the house's players row — and takes it
-- with SKIP LOCKED, which never waits. Every other row it locks is a row no other writer locks: a merchant's
-- ledger rows and events older than the cut (append-only: public.forbid_mutation lets only this function
-- delete them), her ended voyages past the cut that no open lap reads and their voyage_events / insurance
-- rows, her past game-days of trade_daily, finished orders past the cut. Nothing it runs takes an advisory
-- lock, a FOR UPDATE / SHARE, the quay, or calls credit() (asserted below on every function it runs and every
-- trigger it fires). As a guard on that argument, each compaction transaction runs with lock_timeout 50 ms:
-- a wait that should not exist ends in 50 ms, far below deadlock_timeout (1 s), and rolls that batch back.
-- Two compactors cannot overlap (pg_cron runs a job once at a time) and, if they did, NO KEY UPDATE excludes
-- them from the same house. The beat ↔ tend ↔ companies order is the quay's, exactly as before.
--
-- ── RESULTS ARE BYTE-IDENTICAL ─────────────────────────────────────────────────────────────────
-- The rules are npc_compact_houses, unchanged. Compacting as of T, then a later T', leaves what compacting
-- as of T' leaves (0253 / 0259 / 0260's probe). The probe below runs 0260's four ways and a fifth, the new
-- locked transaction, on the same rolled-back houses: all five leave byte-identical rows.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- Switch off byeharu-voyage:compact (cron.alter_job active := false), then a forward slice reverses the two
-- tick_reconcile hunks (each OLD text is here verbatim). The new functions and table are harmless left alone.
--
-- VERSION: 0265 (prod head 0263 when cut; 0264 is the arrivals' lap-start slice). Hunks cut from the LIVE
-- tick_reconcile on prod at head 0263, LF-normalised.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.npc_compact_houses(uuid[],timestamptz)') is null or to_regclass('public.reconcile_runs') is null
     or to_regprocedure('public.hold_the_quay()') is null or to_regprocedure('public.npc_compact_orders(timestamptz)') is null
     or position('''wait_ms'', round(v_qwait)' in pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure)) = 0 then
    raise exception '0265 refuses: 0260 is not in this world';
  end if;
  if to_regclass('public.compact_runs') is not null or to_regprocedure('public.npc_compact_locked(uuid[],timestamptz)') is not null then
    raise exception '0265 refuses: it has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0265(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table defs_before_0265 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_reconcile(boolean)')) f(fn);

-- the functions this file must leave byte for byte: the rules and everything they run, the purse, the quay
create temp table kept_0265 on commit drop as
select f.fn from (values ('public.npc_compact(timestamptz)'), ('public.npc_compact_houses(uuid[],timestamptz)'),
                         ('public.npc_compact_house(uuid,timestamptz)'), ('public.npc_compact_orders(timestamptz)'),
                         ('public.ledger_sum(uuid)'), ('public.assert_ledger_reconciles(uuid)'),
                         ('public.credit(uuid,text,bigint,uuid)'), ('public.hold_the_quay()'),
                         ('public.npc_upkeep_scope(timestamptz)'), ('public.tick_arrivals(timestamptz)'),
                         ('public.tick_arrivals_each_second(int)'), ('public.forbid_mutation()'),
                         ('public.tg_reconcile_from_ledger()'), ('public.npc_traders_on()')) f(fn);

create temp table before_0265 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn))
          from kept_0265 k) as kept_md5;

-- ── 1. THE RECEIPT: ONE ROW A MINUTE OF THE DAY ─────────────────────────────────────────────────
create table public.compact_runs (
  slot     int         primary key check (slot between 0 and 1439),
  at       timestamptz not null,
  ms       numeric     not null check (ms >= 0),
  receipt  jsonb       not null
);
comment on table public.compact_runs is
  '0265: one row a minute of the day (slot = floor(epoch / 60) mod 1440), overwritten a day later: the minute''s compactor run (public.tick_compact) — its instant (the run''s now()), how long it took, and its receipt: houses due, compacted, skipped (a writer had her), failed, the rows it removed, the longest hold, the oldest row still waiting. One writer: public.tick_compact. Server-only.';
alter table public.compact_runs enable row level security;
revoke all on table public.compact_runs from public, anon, authenticated;

-- ── 2. THE LOCKED TRANSACTION: EACH HOUSE'S OWN ROW, ONE ORDER, NEVER WAITED FOR ────────────────
create function public.npc_compact_locked(p_houses uuid[], p_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- 0265: ONE COMPACTION TRANSACTION'S LOCK. The batch's merchants' rows in public.players, ascending id,
-- FOR NO KEY UPDATE SKIP LOCKED: a house another writer has (a beat's credit, a tend step) is SKIPPED, never
-- waited for; the houses got are held to this transaction's end, so no purse of theirs moves while they are
-- cut, and a beat that touches one waits for this transaction alone. Then THE rules, public.npc_compact_houses,
-- on the houses got, as of p_at. Its answer, plus how many houses were cut and how many were skipped.
-- Called by public.tick_compact, one call a transaction.
declare
  v_want int;
  v_got  uuid[];
begin
  v_want := (select count(*) from public.players p where p.id = any(p_houses) and p.is_npc);
  v_got := array(select p.id from public.players p
                  where p.id = any(p_houses) and p.is_npc
                  order by p.id
                    for no key update skip locked);
  return coalesce(public.npc_compact_houses(v_got, p_at), '{}'::jsonb)
         || jsonb_build_object('houses', cardinality(v_got), 'skipped', v_want - cardinality(v_got));
end $fn$;
comment on function public.npc_compact_locked(uuid[], timestamptz) is
  '0265: one compaction transaction: locks the batch''s merchant rows (ascending id, FOR NO KEY UPDATE SKIP LOCKED: never waits) and runs public.npc_compact_houses on those it got. Server-only; called by public.tick_compact.';
revoke all on function public.npc_compact_locked(uuid[], timestamptz) from public, anon, authenticated;

-- ── 3. THE MINUTE'S COMPACTOR ───────────────────────────────────────────────────────────────────
create procedure public.tick_compact(p_commit boolean default true, p_sweep boolean default null)
language plpgsql
as $procedure$
-- 0265: THE merchant compactor (pg_cron byeharu-voyage:compact, every minute, CALL). Not under the quay:
-- each transaction locks its own houses (public.npc_compact_locked) and never waits for one, so a beat and a
-- compaction meet only on the same house, for one transaction (sized to c_hold). THE DUE HOUSES: a merchant
-- whose oldest ledger row awaiting a roll (her NPC_CARRIED row skipped) is over c_due past the cut, oldest
-- first. A BATCH is compacted as of its newest house's oldest row + retention + c_step, never later than now:
-- a backlog is walked oldest hours first, c_step a visit, and the houses of a batch read the same pages; a
-- house rolled up to the normal cut is due again once c_due of her rows have crossed it. Compacting as of T,
-- then a later T', leaves what compacting as of T' leaves (0253 / 0259 / 0265's probes), so where a minute
-- stops changes nothing but when. THE CLOCK (0258's): each transaction timed from its lock to its commit, the
-- next sized to c_hold by the slower of the last one's rate and the run's mean (1 to c_bmax houses), none
-- started unless it ends inside c_budget; a batch that fails is rolled back whole and redone a house a
-- transaction, and a house that fails is counted and noted. THE HOUR'S SWEEP, at :07 (p_sweep null; true /
-- false forces it on / off): first every merchant NOT due, as of now — the hourly pass npc_compact always made,
-- so a house with no ledger row to roll still loses her old events, voyages and trade days (cheap: a house the
-- sweep reaches has under c_due of rows past the cut); and THE ORDERS (public.npc_compact_orders). Each
-- transaction runs with lock_timeout 50 ms (a guard: nothing it runs should ever wait).
-- p_commit = false runs the same steps in the caller's transaction (a proof inside BEGIN … ROLLBACK).
-- No SECURITY DEFINER, no SET: a procedure that commits may carry neither; it runs as the job's owner.
declare
  c_budget constant interval := interval '8 seconds';   -- the minute's work, at most
  c_hold   constant numeric := 200;                     -- ms: the longest a transaction should hold its houses
  c_bmax   constant int := 25;                          -- houses a transaction, at most
  c_step   constant interval := interval '6 hours';     -- the furthest a house is cut forward in one visit
  c_due    constant interval := interval '1 hour';      -- a house is due once this much of her rows is past the cut
  v_t0     timestamptz := clock_timestamp();
  v_now    timestamptz := now();
  v_by     timestamptz := clock_timestamp() + c_budget;
  v_on     boolean := public.npc_traders_on();
  v_keep   interval;
  v_cut    timestamptz;
  v_ids    uuid[] := '{}';
  v_old    timestamptz[] := '{}';
  v_n      int := 0;
  v_i      int := 1;
  v_retry  uuid[] := '{}';
  v_rat    timestamptz;
  v_rr     int := 1;
  v_single boolean;
  v_bsize  int;
  v_batch  uuid[];
  v_at     timestamptz;
  v_r      jsonb;
  v_bfail  text;
  v_rate   numeric := c_hold;   -- ms a house; no measurement yet: a house is assumed to take the whole hold
  v_tb     timestamptz;
  v_bms    numeric;
  v_held   numeric := 0;
  v_heldh  int := 0;
  v_bmsmax numeric := 0;
  v_bhmax  int := 0;
  v_batches int := 0;
  v_done   int := 0;
  v_skip   int := 0;
  v_fail   int := 0;
  v_note   text;
  v_ord    int;
  v_voy    int := 0;
  v_led    int := 0;
  v_ev     int := 0;
  v_td     int := 0;
  v_sweep  boolean;
  v_nsw    int := 0;
begin
  if v_on then
    v_keep := make_interval(hours => public.wc_int('npc_retention_hours'));
    v_cut := v_now - v_keep;
    v_sweep := coalesce(p_sweep, extract(minute from v_now)::int = 7);
    -- THE ORDERS, once an hour (the minute the hourly run used to do them)
    if v_sweep then
      perform set_config('lock_timeout', '50ms', true);
      begin
        v_ord := coalesce((public.npc_compact_orders(v_now)->>'orders')::int, 0);
      exception when others then
        v_fail := v_fail + 1;
        v_note := 'orders: ' || sqlerrm;
      end;
      if p_commit then commit; end if;
    end if;
    -- THE DUE HOUSES, oldest first (her NPC_CARRIED row skipped: two index entries a house)
    select coalesce(array_agg(x.id order by x.m, x.id), '{}'), coalesce(array_agg(x.m order by x.m, x.id), '{}')
      into v_ids, v_old
      from (select p.id, (select min(l.created_at) from public.ledger l
                           where l.player_id = p.id and l.kind <> 'NPC_CARRIED') as m
              from public.players p where p.is_npc) x
     where x.m < v_cut - c_due;
    if v_sweep then
      -- THE HOUR'S SWEEP first: every merchant not due, as of now (her m stands at now - retention - c_step, so
      -- her batch is cut as of now); the due houses follow
      v_nsw := (select count(*) from public.players p where p.is_npc and not (p.id = any(v_ids)));
      v_ids := array(select p.id from public.players p where p.is_npc and not (p.id = any(v_ids)) order by p.id) || v_ids;
      v_old := array_fill(v_now - v_keep - c_step, array[v_nsw]) || v_old;
    end if;
    v_n := cardinality(v_ids);
    loop
      v_single := v_rr <= cardinality(v_retry);
      exit when not v_single and v_i > v_n;
      if v_single then
        v_bsize := 1;
      else
        v_bsize := greatest(1, least(c_bmax, floor(c_hold / v_rate)::int));
      end if;
      exit when clock_timestamp() + make_interval(secs => (v_bsize * v_rate / 1000)::double precision) > v_by;
      if v_single then
        v_batch := array[v_retry[v_rr]];
        v_at := v_rat;
        v_rr := v_rr + 1;
      else
        v_batch := v_ids[v_i : v_i + v_bsize - 1];
        v_at := least(v_now, v_old[least(v_i + v_bsize - 1, v_n)] + v_keep + c_step);
        v_i := v_i + v_bsize;
      end if;
      v_bfail := null;
      v_tb := clock_timestamp();
      perform set_config('lock_timeout', '50ms', true);
      begin
        v_r := public.npc_compact_locked(v_batch, v_at);
        v_voy := v_voy + coalesce((v_r->>'voyages')::int, 0);
        v_led := v_led + coalesce((v_r->>'ledger_rolled')::int, 0);
        v_ev  := v_ev  + coalesce((v_r->>'events')::int, 0);
        v_td  := v_td  + coalesce((v_r->>'trade_daily')::int, 0);
        v_done := v_done + coalesce((v_r->>'houses')::int, 0);
        v_skip := v_skip + coalesce((v_r->>'skipped')::int, 0);
        if not v_single then v_batches := v_batches + 1; end if;
      exception when others then
        if v_single then
          v_fail := v_fail + 1;
          v_note := coalesce(v_note, 'house ' || v_batch[1] || ': ' || sqlerrm);
        else
          v_bfail := sqlerrm;
        end if;
      end;
      if p_commit then commit; end if;
      -- the rate: ms a house this transaction held its houses (its commit included), and the run's mean
      v_bms := extract(epoch from clock_timestamp() - v_tb) * 1000;
      v_held := v_held + v_bms;
      v_heldh := v_heldh + cardinality(v_batch);
      v_rate := greatest(v_bms / cardinality(v_batch), v_held / v_heldh, 1);
      v_bmsmax := greatest(v_bmsmax, v_bms);
      v_bhmax := greatest(v_bhmax, cardinality(v_batch));
      if v_bfail is not null then
        v_note := coalesce(v_note, 'batch of ' || cardinality(v_batch) || ': ' || v_bfail);
        v_retry := v_batch;
        v_rat := v_at;
        v_rr := 1;
      end if;
    end loop;
  end if;
  insert into public.compact_runs (slot, at, ms, receipt)
  values ((floor(extract(epoch from v_now) / 60)::bigint % 1440)::int, v_now,
          round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1),
          jsonb_build_object(
            'enabled', v_on, 'due', v_n - v_nsw, 'swept', v_nsw, 'houses', v_done, 'skipped', v_skip, 'failed', v_fail, 'note', v_note,
            'left', greatest(v_n - v_i + 1, 0) + greatest(cardinality(v_retry) - v_rr + 1, 0),
            'batches', v_batches, 'voyages', v_voy, 'ledger_rolled', v_led, 'events', v_ev, 'trade_daily', v_td,
            'orders', v_ord,
            'held_ms', round(v_held), 'batch_ms_max', round(v_bmsmax), 'batch_houses_max', v_bhmax,
            'ms_house', round(v_rate, 1), 'hold_ms', c_hold, 'budget_ms', extract(epoch from c_budget) * 1000,
            'oldest', case when v_n > 0 then v_old[1] end,   -- the oldest row waiting when the minute began
            'before', v_cut))
  on conflict (slot) do update set at = excluded.at, ms = excluded.ms, receipt = excluded.receipt;
  if p_commit then commit; end if;
end $procedure$;
comment on procedure public.tick_compact(boolean, boolean) is
  '0265: THE merchant compactor (pg_cron byeharu-voyage:compact, every minute, CALL): the due houses oldest first, a few a transaction under each house''s own lock (public.npc_compact_locked, never the quay), each batch cut forward up to 6 h, sized to a 200 ms hold, 8 s a minute; at :07 the hour''s sweep (every house not due, as of now) and the orders. Writes public.compact_runs. Server-only.';
revoke all on procedure public.tick_compact(boolean, boolean) from public, anon, authenticated;

-- ── 4. THE HOURLY RUN LETS THE COMPACTOR GO (2 hunks) ───────────────────────────────────────────
create temp table hunks_0265 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0265 (fn, n, old, new) values
('public.tick_reconcile(boolean)', 1,
$h$  v_cby      timestamptz;          -- the compactor's own budget: 30 s from its start
  v_cx       jsonb := '{}'::jsonb; -- the orders' answer
  v_ch       jsonb;                -- one house's answer
  v_cdone    int := 0;
  v_cleft    int := 0;
  v_cfail    int := 0;
  v_cnote    text;
  v_cvoy     int := 0;
  v_cled     int := 0;
  v_cev      int := 0;
  v_ctd      int := 0;
  -- 0253 / 0259: the compactor's slices — compact every house as of v_slice, six hours past the last slice finished
  v_keep     interval;
  v_upto     timestamptz;          -- the last slice finished (from the last receipt that says)
  v_slice    timestamptz;
  v_slices   int := 0;
  -- 0258: a few houses a transaction, sized by the clock (0259: inside each slice)
  v_order    uuid[];
  v_batch    uuid[];
  v_retry    uuid[] := '{}';                 -- a failed batch's houses, done one a transaction next
  v_r        int := 1;
  v_i        int := 1;
  v_bsize    int;
  v_single   boolean;
  v_bfail    text;
  v_batches  int := 0;
  v_hold     constant numeric := 5000;      -- ms: the longest a compaction transaction should hold the quay (0260: was 1.5 s)
  v_bmax     constant int := 100;           -- houses a transaction, at most (0260: was 25)
  v_rate     numeric;                       -- ms a house: the slower of the last transaction's and the run's mean
  v_tb       timestamptz;
  v_bms      numeric;
  v_held     numeric := 0;                  -- ms the compaction transactions held the quay, all told
  v_heldh    int := 0;                      -- houses in them
  v_bmsmax   numeric := 0;
  v_bhmax    int := 0;
  v_tw       timestamptz;                   -- 0260: when this transaction asked for the quay
  v_qwait    numeric := 0;                  -- 0260: ms the compaction transactions waited for the quay, all told
$h$,
$h$  -- 0265: the compactor's locals left with it (public.tick_compact, every minute)
$h$),
('public.tick_reconcile(boolean)', 2,
$h$  -- 0249: THE COMPACTOR, A HOUSE AT A TIME. One transaction for the whole world could not finish once its
  -- backlog passed what 120 s holds (prod 10-26 → 10-27: rolled back every hour from 10-26 00:07). The same
  -- rules (public.npc_compact_orders, public.npc_compact_house), one transaction each, the house compacted
  -- longest ago first (her oldest ledger row: her NPC_CARRIED row stands at her last cut), until 30 s have
  -- gone; the rest are first in line next hour. A house that fails is rolled back alone and counted.
  v_cby := clock_timestamp() + interval '30 seconds';
  if p_commit then perform public.hold_the_quay(); end if;
  perform public.npc_upkeep_scope(v_deadline);
  begin
    v_cx := public.npc_compact_orders(v_now);
  exception when others then
    v_cfail := v_cfail + 1;
    v_cnote := 'orders: ' || sqlerrm;
  end;
  if p_commit then commit; end if;
  if v_on then
    -- 0259: THE OLDEST HOURS FIRST AGAIN (0253's slices), A FEW HOUSES A TRANSACTION (0258). Measured on prod
    -- 10-27 21:07 under 0258's normal cut: one house's WHOLE backlog took 3.2-5 s alone (her rows lie one to a
    -- page across two days), so 6 houses were done in 30 s (5,463 ledger rows; 0257 rolled ~25 k a run). A slice
    -- compacts every house as of v_slice (public.npc_compact_houses: the same rules); the slice's rows lie
    -- together, so its batches share their pages. A slice finished is kept in the receipt (`upto`); one the
    -- budget cut short is done again next hour. Compacting as of T, then a later T', leaves what compacting as
    -- of T' leaves (0253's self-assert; 0259's). Inside a slice, 0258's clock: each transaction timed inside the
    -- quay lock, the next sized to v_hold by the measured rate (1 to v_bmax), none started unless it ends inside
    -- the 30 s budget, a failed batch redone one house a transaction.
    v_keep := make_interval(hours => public.wc_int('npc_retention_hours'));
    v_upto := (select (rr.receipt->'merchant_upkeep'->'compact'->>'upto')::timestamptz
                 from public.reconcile_runs rr
                where rr.at < v_now and rr.receipt->'merchant_upkeep'->'compact' ? 'upto'
                order by rr.at desc limit 1);
    v_rate := v_hold;   -- no measurement yet: a house is assumed to take the whole hold
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
      v_i := 1;
      v_retry := '{}';
      v_r := 1;
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
        v_tw := clock_timestamp();
        if p_commit then perform public.hold_the_quay(); end if;
        v_tb := clock_timestamp();
        v_qwait := v_qwait + extract(epoch from v_tb - v_tw) * 1000;   -- 0260
        perform public.npc_upkeep_scope(v_deadline);
        begin
          v_ch := public.npc_compact_houses(v_batch, v_slice);
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
      exit when v_cleft > 0;   -- the budget ran out inside this slice: it is done again next hour
      v_upto := v_slice;
      v_slices := v_slices + 1;
      exit when v_slice >= v_now or clock_timestamp() >= v_cby;
    end loop;
  end if;
  v_upkeep := v_upkeep || jsonb_build_object('compact', jsonb_build_object(
    'enabled', v_on, 'houses', v_cdone, 'left', v_cleft, 'failed', v_cfail, 'note', v_cnote,
    'voyages', v_cvoy, 'ledger_rolled', v_cled, 'events', v_cev, 'trade_daily', v_ctd,
    'orders', coalesce((v_cx->>'orders')::int, 0),
    'slices', v_slices, 'upto', v_upto,   -- 0253 / 0259: slices finished this run; the last instant every house is compacted as of
    'batches', v_batches,                 -- 0257: batch transactions that committed (0258: sized by the clock)
    'hold_ms', v_hold, 'batch_ms_max', round(v_bmsmax), 'batch_houses_max', v_bhmax,   -- 0258: the longest hold
    'ms_house', round(v_rate, 1),         -- 0258: the measured rate the last transaction was sized by
    'held_ms', round(v_held), 'wait_ms', round(v_qwait),   -- 0260: ms holding the quay, and waiting for it
    'before', v_now - make_interval(hours => public.wc_int('npc_retention_hours'))));
  v_ms := v_ms || jsonb_build_object('compact', round(extract(epoch from clock_timestamp() - v_t) * 1000)); v_t := clock_timestamp();
$h$,
$h$  -- 0265: THE COMPACTOR IS NOT HERE. It runs every minute (public.tick_compact, pg_cron byeharu-voyage:compact), a
  -- few houses a transaction under each house's own lock (public.npc_compact_locked), never under the quay. Here
  -- it had one 30 s window an hour and spent half of it waiting for the quay (prod 10-28 01:07 / 02:07: held
  -- 13.9 / 17.0 s, waited 14.9 / 16.9 s); the backlog grew ~15 k ledger rows an hour. Its receipt is
  -- public.compact_runs. The merchants' steps and the companies' step above keep the quay (0265's header).
$h$);

create or replace function pg_temp.recut_0265(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0265 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0265 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0265(v_def, h.old);
    if v_n <> 1 then
      raise exception '0265 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0265(fn) from defs_before_0265 order by fn;

-- ── 5. THE JOB IS DEFINED, NOT RUNNING (0078): wind_the_clock() starts it with the rest of the clock ──
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice '0265: pg_cron is not installed here (PGlite) — byeharu-voyage:compact was NOT scheduled. Call public.tick_compact() by hand.';
    return;
  end if;
  perform cron.schedule('byeharu-voyage:compact', '* * * * *', 'call public.tick_compact()');
  perform cron.alter_job(jobid, active := false) from cron.job where jobname = 'byeharu-voyage:compact';
  raise notice '0265: pg_cron present — byeharu-voyage:compact SCHEDULED BUT INACTIVE until wind_the_clock().';
end $$;

-- ── 6. THE PROBE: five ways, the same rows ──────────────────────────────────────────────────────
-- 0260's four houses (rows before a 2026-08-01 cut, earlier than every real row on prod, so only the probe's
-- rows are touched): A and C merchants with rows to roll, B a merchant with ONE old ledger row, P a PLAYER
-- (never touched); three voyages each with voyage_events and insurance, one old one kept by an open lap.
-- Compacted from the same rolled-back state five ways: (twice) the rules as of an instant whose cut falls
-- between the old rows, then as of now; (batch) the rules once; (one) public.npc_compact_house house by house;
-- (all) public.npc_compact; (locked) THE NEW TRANSACTION, public.npc_compact_locked, as tick_compact runs it.
create or replace function pg_temp.digest_0265(p_house uuid)
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

create or replace function pg_temp.run_0265(p_how text, p_houses uuid[], p_now timestamptz)
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
    if p_how = 'twice' then
      -- two slices: as of an earlier instant (its cut at 2026-07-31 10:30, between the probe's old rows), then p_now
      v_a := public.npc_compact_houses(p_houses, least(timestamptz '2026-07-31 10:30:00+00'
                                                        + make_interval(hours => public.wc_int('npc_retention_hours')),
                                                      p_now - interval '1 minute'));
      v_r := public.npc_compact_houses(p_houses, p_now);
      for k in select jsonb_object_keys(v_r) loop
        v_a := v_a || jsonb_build_object(k, coalesce((v_a->>k)::int, 0) + (v_r->>k)::int);
      end loop;
    elsif p_how = 'batch' then
      v_a := public.npc_compact_houses(p_houses, p_now);
    elsif p_how = 'all' then
      v_a := public.npc_compact(p_now) - 'orders' - 'before';
    elsif p_how = 'locked' then
      -- as tick_compact runs it: the batch's own lock, then the rules, under its lock_timeout
      perform set_config('lock_timeout', '50ms', true);
      v_a := public.npc_compact_locked(p_houses, p_now);
      if (v_a->>'houses')::int <> 3 or (v_a->>'skipped')::int <> 0 then
        raise exception '0265 self-assert FAIL: the locked transaction did not take exactly the 3 merchants (and skip none): %', v_a;
      end if;
      v_a := v_a - 'houses' - 'skipped';
      perform set_config('lock_timeout', '5s', true);
    else
      foreach h in array (select array_agg(x order by x) from unnest(p_houses) x) loop
        v_r := public.npc_compact_house(h, p_now);
        for k in select jsonb_object_keys(v_r) loop
          v_a := v_a || jsonb_build_object(k, coalesce((v_a->>k)::int, 0) + (v_r->>k)::int);
        end loop;
      end loop;
    end if;
    foreach h in array p_houses loop
      v_d := v_d || jsonb_build_object(h::text, pg_temp.digest_0265(h));
    end loop;
    raise exception using errcode = 'ZY265',
      message = jsonb_build_object('a', v_a, 'd', v_d)::text;
  exception when sqlstate 'ZY265' then
    return sqlerrm::jsonb;
  end;
end $$;

do $$
declare
  v_before record;
  v_d record; v_h record; v_pp record; v_def text; v_fn text;
  c_now   constant timestamptz := '2026-08-01 00:00:00+00';
  c_old   constant timestamptz := '2026-07-31 12:00:00+00';   -- before the cut (2026-07-31 18:00)
  v_res   jsonb;
  -- 0265: every function the compaction transaction runs, and every trigger it fires: none may take a lock
  -- another writer takes (no FOR UPDATE / SHARE, no advisory lock, no quay, no credit)
  c_runs  constant text[] := array['public.npc_compact_houses(uuid[],timestamptz)', 'public.npc_compact_orders(timestamptz)',
                                   'public.assert_ledger_reconciles(uuid)', 'public.ledger_sum(uuid)',
                                   'public.forbid_mutation()', 'public.tg_reconcile_from_ledger()',
                                   'public.npc_traders_on()', 'public.standing_routes_on()', 'public.wc(text)',
                                   'public.wc_int(text)', 'public.wc_num(text)', 'world.game_day(timestamptz)'];
begin
  select * into v_before from before_0265;

  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved; nothing else moved
  for v_d in select * from defs_before_0265 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0265 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0265(v_def, v_h.new) <> 1 then
        raise exception '0265 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0265 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0265 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn)) from kept_0265 k)
     <> v_before.kept_md5 then
    raise exception '0265 self-assert FAIL: the rules (npc_compact_houses), npc_compact, the house step, the orders step, the purse invariant, credit, the quay lock, the scope, the beat, the arrivals run or a trigger moved';
  end if;

  -- (b) THE HOURLY RUN NO LONGER COMPACTS; THE QUAY IS TAKEN BY THE BEAT AND THE HOUR'S TWO WRITE STEPS ONLY
  v_def := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0265(v_def, 'public.npc_compact(') + pg_temp.occurs_0265(v_def, 'public.npc_compact_house(')
     + pg_temp.occurs_0265(v_def, 'public.npc_compact_houses(') + pg_temp.occurs_0265(v_def, 'public.npc_compact_orders(') <> 0
     or pg_temp.occurs_0265(v_def, 'if p_commit then perform public.hold_the_quay(); end if;') <> 2
     or pg_temp.occurs_0265(v_def, 'if p_commit then commit; end if;') <> 2
     or pg_temp.occurs_0265(v_def, 'public.npc_tend_houses(v_now)') <> 1
     or pg_temp.occurs_0265(v_def, 'public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k)') <> 1 then
    raise exception '0265 self-assert FAIL: tick_reconcile still compacts, or its tend and companies steps are not each under the quay';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%'
         and p.oid not in ('public.tick_reconcile(boolean)'::regprocedure, 'public.tick_arrivals_each_second(int)'::regprocedure,
                           'public.hold_the_quay()'::regprocedure)) <> 0 then
    raise exception '0265 self-assert FAIL: another function takes the quay lock';
  end if;

  -- (c) NO DEADLOCK, BY CONSTRUCTION. The minute's compactor: no quay, no advisory lock, no lock clause of its
  -- own; one call of the locked transaction, which takes exactly ONE lock clause, on players, ascending, SKIP
  -- LOCKED (never waits); everything that transaction runs or fires takes no lock any other writer takes.
  -- (bodies read without their comments: a comment may say what the code must not do)
  v_def := lower(regexp_replace(replace(pg_get_functiondef('public.tick_compact(boolean,boolean)'::regprocedure), E'\r', ''), '--[^\n]*', '', 'g'));
  if pg_temp.occurs_0265(v_def, 'hold_the_quay') <> 0 or pg_temp.occurs_0265(v_def, 'advisory') <> 0
     or pg_temp.occurs_0265(v_def, ' for update') + pg_temp.occurs_0265(v_def, ' for share') + pg_temp.occurs_0265(v_def, ' for key share')
        + pg_temp.occurs_0265(v_def, ' for no key update') <> 0
     or pg_temp.occurs_0265(v_def, 'credit(') <> 0
     or pg_temp.occurs_0265(v_def, 'public.npc_compact_locked(v_batch, v_at)') <> 1
     or pg_temp.occurs_0265(v_def, 'public.npc_compact_houses(') <> 0
     or pg_temp.occurs_0265(v_def, 'public.npc_compact_orders(v_now)') <> 1
     or pg_temp.occurs_0265(v_def, 'perform set_config(''lock_timeout'', ''50ms'', true);') <> 2 then
    raise exception '0265 self-assert FAIL: tick_compact takes a lock of its own, the quay, or does not run each transaction through the locked call under a 50 ms lock_timeout';
  end if;
  v_def := lower(regexp_replace(replace(pg_get_functiondef('public.npc_compact_locked(uuid[],timestamptz)'::regprocedure), E'\r', ''), '--[^\n]*', '', 'g'));
  if pg_temp.occurs_0265(v_def, ' for ') <> 1 or pg_temp.occurs_0265(v_def, 'order by p.id
                    for no key update skip locked)') <> 1
     or pg_temp.occurs_0265(v_def, 'from public.players p') <> 2
     or pg_temp.occurs_0265(v_def, 'advisory') + pg_temp.occurs_0265(v_def, 'hold_the_quay') + pg_temp.occurs_0265(v_def, 'credit(') <> 0
     or pg_temp.occurs_0265(v_def, 'public.npc_compact_houses(v_got, p_at)') <> 1 then
    raise exception '0265 self-assert FAIL: the locked transaction does not take exactly one lock, on players, in id order, SKIP LOCKED';
  end if;
  foreach v_fn in array c_runs loop
    v_def := lower(regexp_replace(replace(pg_get_functiondef(v_fn::regprocedure), E'\r', ''), '--[^\n]*', '', 'g'));
    if v_def ~ '\mfor\s+(update|share|key\s+share|no\s+key\s+update)\M' or v_def like '%advisory%' or v_def like '%hold_the_quay%'
       or v_def like '%treasury_lock%' or v_def ~ '\mcredit\s*\(' or v_def like '%city_pays%' then
      raise exception '0265 self-assert FAIL: % (run by a compaction transaction) takes a lock another writer takes', v_fn;
    end if;
  end loop;
  -- the triggers a compaction transaction fires: exactly the ones above (no new trigger on the tables it writes)
  if exists (select 1 from pg_trigger t
              where not t.tgisinternal
                and t.tgrelid in ('public.ledger'::regclass, 'public.events'::regclass, 'public.voyages'::regclass,
                                  'public.voyage_events'::regclass, 'public.insured_voyages'::regclass,
                                  'public.trade_daily'::regclass, 'public.orders'::regclass)
                and ((t.tgtype::int & 8) <> 0                  -- fires on DELETE (what it does to all of them)
                     or (t.tgrelid = 'public.ledger'::regclass and (t.tgtype::int & 4) <> 0))   -- or INSERT (the carried row)
                and t.tgfoid not in ('public.forbid_mutation()'::regprocedure, 'public.tg_reconcile_from_ledger()'::regprocedure)) then
    raise exception '0265 self-assert FAIL: a trigger the compactor fires is not one this file checked';
  end if;
  -- and no other table names a row it deletes, except the two cascades the rules empty first and the ledger's
  -- own reference to events (the rules keep every event a ledger row names)
  if exists (select 1 from pg_constraint c
              where c.contype = 'f'
                and c.confrelid in ('public.ledger'::regclass, 'public.events'::regclass, 'public.voyages'::regclass,
                                    'public.voyage_events'::regclass, 'public.insured_voyages'::regclass,
                                    'public.trade_daily'::regclass, 'public.orders'::regclass)
                and (c.conrelid, c.confrelid) not in (('public.voyage_events'::regclass, 'public.voyages'::regclass),
                                                      ('public.insured_voyages'::regclass, 'public.voyages'::regclass),
                                                      ('public.ledger'::regclass, 'public.events'::regclass))) then
    raise exception '0265 self-assert FAIL: a table this file did not check names a row the compactor deletes';
  end if;
  if has_function_privilege('anon', 'public.npc_compact_locked(uuid[], timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_compact_locked(uuid[], timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.tick_compact(boolean, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.tick_compact(boolean, boolean)', 'execute')
     or has_table_privilege('anon', 'public.compact_runs', 'select')
     or has_table_privilege('authenticated', 'public.compact_runs', 'select') then
    raise exception '0265 self-assert FAIL: a client can reach the compactor or its receipt';
  end if;

  -- (d) FIVE WAYS, THE SAME ROWS (rolled back whole)
  begin
    declare
      v_a    uuid; v_b uuid; v_c uuid; v_p uuid;
      v_all4 uuid[];
      v_port uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1);
      v_port2 uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_port order by p.code limit 1);
      v_good uuid := (select g.id from public.goods g order by g.code limit 1);
      v_gd   int := world.game_day(c_now);
      v_two jsonb; v_batch jsonb; v_one jsonb; v_all jsonb; v_lock jsonb; v_pre jsonb := '{}'::jsonb;
      v_m   uuid; v_f uuid; v_k int;
      e1 uuid; e2 uuid; e3 uuid; e4 uuid; v0 uuid; v1 uuid; v2 uuid; v_sr uuid; v_lap uuid; v_lap0 uuid;
    begin
      if not public.npc_traders_on() then
        update public.world_config set value = 'true'::jsonb
         where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
        if not public.npc_traders_on() then
          raise exception '0265 self-assert FAIL: cannot light the merchants for the probe';
        end if;
      end if;
      v_a := public.new_house(null, 'Casa da Fila A 0265', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_b := public.new_house(null, 'Casa da Fila B 0265', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_c := public.new_house(null, 'Casa da Fila C 0265', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_p := public.new_house(null, 'Casa da Fila P 0265', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => false);
      v_all4 := array[v_a, v_b, v_c, v_p];
      v_k := 0;
      foreach v_m in array v_all4 loop
        v_k := v_k + 1;
        v_f := (select f.id from public.fleets f where f.player_id = v_m order by f.created_at limit 1);
        if v_f is null then
          insert into public.fleets (player_id, name, port_id) values (v_m, 'Fila 0265 ' || v_k, v_port) returning id into v_f;
        end if;
        e1 := gen_random_uuid(); e2 := gen_random_uuid(); e3 := gen_random_uuid(); e4 := gen_random_uuid();
        v0 := gen_random_uuid(); v1 := gen_random_uuid(); v2 := gen_random_uuid();
        -- E1, E2 old (both go), E3 named by a kept ledger row (stays), E4 FOUNDED (stays)
        insert into public.events (id, player_id, kind, payload, created_at) values
          (e1, v_m, 'PROBE_0265', '{}', c_old - interval '3 hours'), (e2, v_m, 'PROBE_0265', '{}', c_old),
          (e3, v_m, 'PROBE_0265', '{}', c_old), (e4, v_m, 'FOUNDED', '{}', c_old - interval '1 day');
        if v_m = v_b then
          -- B: ONE old ledger row (summing to 0 with the purse kept): nothing to roll; E2 is not named by it
          insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at) values
            (v_m, 'PROBE_0265', 0, 1000, null, c_old - interval '2 hours'),
            (v_m, 'PROBE_0265', 0, 1000, e3, c_now);
        else
          -- old rows summing to 0 (C's amounts differ from A's), one of them naming E2; E3 named by a new row
          insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at) values
            (v_m, 'PROBE_0265', 100 * v_k, 1000 + 100 * v_k, null, c_old - interval '3 hours'),
            (v_m, 'PROBE_0265', 300, 1300 + 100 * v_k, null, c_old - interval '2 hours'),
            (v_m, 'PROBE_0265', -300 - 100 * v_k + 50, 1050, null, c_old - interval '1 hour'),
            (v_m, 'PROBE_0265', -50, 1000, e2, c_old),
            (v_m, 'PROBE_0265', 0, 1000, e3, c_now);
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
          insert into public.standing_routes (id, player_id, name, fleet_id) values (v_sr, v_m, 'Fila 0265', null);
          insert into public.standing_route_laps (id, route_id, lap_no, started_at, closed_at) values
            (v_lap0, v_sr, 1, c_old - interval '1 day', c_old - interval '3 hours'),
            (v_lap, v_sr, 2, c_old - interval '2 hours', null);
          update public.standing_routes set lap_id = v_lap, lap_no = 2 where id = v_sr;
          insert into public.orders (fleet_id, player_id, seq, raw_text, verb, status, result, route_lap_id) values
            (v_f, v_m, 900001, 'SAIL probe 0265', 'SAIL', 'done', jsonb_build_object('voyage_id', v0), v_lap0),
            (v_f, v_m, 900002, 'SAIL probe 0265', 'SAIL', 'done', jsonb_build_object('voyage_id', v1), v_lap),
            (v_f, v_m, 900003, 'SAIL probe 0265', 'SAIL', 'done', '{}'::jsonb, v_lap);
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
        v_pre := v_pre || jsonb_build_object(v_m::text, pg_temp.digest_0265(v_m));
      end loop;

      v_two   := pg_temp.run_0265('twice',  v_all4, c_now);
      v_batch := pg_temp.run_0265('batch',  v_all4, c_now);
      v_one   := pg_temp.run_0265('one',    v_all4, c_now);
      v_all   := pg_temp.run_0265('all',    v_all4, c_now);
      v_lock  := pg_temp.run_0265('locked', v_all4, c_now);

      if v_two->'d' is distinct from v_batch->'d' or v_two->'d' is distinct from v_one->'d'
         or v_two->'d' is distinct from v_all->'d' or v_two->'d' is distinct from v_lock->'d' then
        raise exception '0265 self-assert FAIL: the five ways left other rows (two %, once %, house step %, whole world %, locked %)',
          v_two, v_batch, v_one, v_all, v_lock;
      end if;
      if v_batch->'a' is distinct from v_one->'a' or v_batch->'a' is distinct from v_all->'a' or v_batch->'a' is distinct from v_lock->'a' then
        raise exception '0265 self-assert FAIL: the ways answered otherwise (once %, house step %, whole world %, locked %)',
          v_batch->'a', v_one->'a', v_all->'a', v_lock->'a';
      end if;
      if v_two->'a' <> jsonb_build_object('voyages', 3, 'ledger_rolled', 10, 'events', 6, 'trade_daily', 6) then
        raise exception '0265 self-assert FAIL: the two slices did not split as the rules say: %', v_two->'a';
      end if;
      if v_batch->'a' <> jsonb_build_object('voyages', 3, 'ledger_rolled', 8, 'events', 6, 'trade_daily', 6) then
        raise exception '0265 self-assert FAIL: the probe did not compact as the rules say: %', v_batch->'a';
      end if;
      if v_lock->'d'->v_p::text is distinct from v_pre->v_p::text then
        raise exception '0265 self-assert FAIL: a player''s rows were touched (before %, after %)', v_pre->v_p::text, v_lock->'d'->v_p::text;
      end if;
      foreach v_m in array array[v_a, v_b, v_c] loop
        if (v_lock->'d'->v_m::text->>'voyages_n')::int <> (v_pre->v_m::text->>'voyages_n')::int - 1
           or (v_lock->'d'->v_m::text->>'voyage_events_n')::int <> (v_pre->v_m::text->>'voyage_events_n')::int - 2
           or (v_lock->'d'->v_m::text->>'insured_n')::int <> (v_pre->v_m::text->>'insured_n')::int - 1
           or (v_lock->'d'->v_m::text->>'insured_n')::int < 2
           or (v_lock->'d'->v_m::text->>'events_n')::int <> (v_pre->v_m::text->>'events_n')::int - 2 then
          raise exception '0265 self-assert FAIL: house % did not lose exactly her one unread old voyage and its rows (before %, after %)',
            v_m, v_pre->v_m::text, v_lock->'d'->v_m::text;
        end if;
      end loop;
      foreach v_m in array array[v_a, v_c] loop
        if (v_lock->'d'->v_m::text->>'carried')::int <> 1
           or (v_lock->'d'->v_m::text->>'ledger_n')::int <> (v_pre->v_m::text->>'ledger_n')::int - 3
           or (v_lock->'d'->v_m::text->>'ledger_sum')::bigint <> (v_pre->v_m::text->>'purse')::bigint
           or (v_lock->'d'->v_m::text->>'purse')::bigint <> (v_pre->v_m::text->>'purse')::bigint then
          raise exception '0265 self-assert FAIL: house % did not roll as the rules say (before %, after %)',
            v_m, v_pre->v_m::text, v_lock->'d'->v_m::text;
        end if;
      end loop;
      if (v_lock->'d'->v_b::text->>'carried')::int <> 0
         or (v_lock->'d'->v_b::text->>'ledger')::text <> (v_pre->v_b::text->>'ledger')::text then
        raise exception '0265 self-assert FAIL: the one-row house did not compact as the rules say (before %, after %)',
          v_pre->v_b::text, v_lock->'d'->v_b::text;
      end if;
      v_res := jsonb_build_object('once', v_batch->'a', 'twice', v_two->'a', 'locked', v_lock->'a', 'houses', 4);
      raise exception using errcode = 'ZY26H', message = v_res::text;
    end;
  exception when sqlstate 'ZY26H' then
    v_res := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.players where company_name like 'Casa da Fila % 0265') then
    raise exception '0265 self-assert FAIL: a probe house was left behind';
  end if;

  -- (e) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0265 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0265 self-assert FAIL: a wall moved';
  end if;

  raise notice '0265 self-assert ok: EACH HOUSE IS CUT UNDER HER OWN LOCK, EVERY MINUTE. public.tick_compact (byeharu-voyage:compact, every minute, inactive until the clock is wound) compacts the due houses oldest first, a few a transaction sized to 200 ms, 8 s a minute, each through public.npc_compact_locked (her players row, id order, FOR NO KEY UPDATE SKIP LOCKED: never waits; lock_timeout 50 ms) and THE rules, npc_compact_houses, unchanged; tick_reconcile no longer compacts (2 hunks, reverse to the pre-image, ACL / volatility / definer / config unmoved) and takes the quay for its tend and companies steps only; no other function takes it; the rules, npc_compact, the house and orders steps, ledger_sum, assert_ledger_reconciles, credit, the quay lock, the scope, the beat, tick_arrivals and the triggers unmoved; nothing a compaction transaction runs or fires takes a lock another writer takes. PROBE (3 merchants + 1 player, rows before a 2026-08-01 cut, an open lap keeping one old voyage, rolled back): two slices, one cut, the house step, npc_compact and the locked transaction left byte-identical rows; answers %. The player untouched. Registry unchanged; walls 0.',
    v_res;
end $$;
