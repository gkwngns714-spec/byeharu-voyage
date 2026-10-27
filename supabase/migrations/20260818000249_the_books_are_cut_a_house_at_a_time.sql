-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0249 — THE BOOKS ARE CUT A HOUSE AT A TIME  (the hourly reconcile: the compactor in small steps,
--        and no upkeep step beside an arrivals beat)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, MEASURED (prod, read-only, 2026-10-27, head 0248) ───────────────────────────────
-- byeharu-voyage:reconcile (`call public.tick_reconcile()`, hourly at :07), cron.job_run_details:
--   10-25 05:07 → 10-25 23:07: 10-19 s a run.  10-26 00:07 on: 16 → 24 → 30 → … → 50 s (12:07) → 67-115 s
--   (19:07-23:07) → from 10-27 00:07 the 120 s statement_timeout in 10 of 13 runs, most in npc_compact's
--   events delete, some in its ledger roll, its foreign-key check, the append-only trigger, or the final
--   invariants pass the timeout reached.
-- THE COMPACTOR HAS COMMITTED NOTHING SINCE THE 10-25 23:07 RUN. The oldest merchant event awaiting it is
-- 10-25 17:07:00.98 — that run's cut (now − npc_retention_hours = 6) — and the newest NPC_CARRIED row is
-- 10-25 17:06:46. Every run since rolled the compactor back: it is one statement block under
-- `exception when others` (a lock wait over lock_timeout 2 s, a deadlock: swallowed, never stored —
-- the hour's receipt is a NOTICE nobody keeps), and since 10-27 00:07 under the whole CALL's 120 s
-- timeout, which no handler catches. Each failure left an hour more for the next run, so it never
-- recovered. Waiting for it, 10-27 ~12:30 UTC:
--   events 943,287 a merchant's, older than the cut (624,459 of them still named by a ledger row);
--   ledger 741,544 rows; voyages 186,759 ended (+ their voyage_events, ~7 each, and insurance rows);
--   trade_daily 122,486 rows of past game-days. A clean hour is ~25 k events, ~21 k ledger rows, ~5 k
--   voyages. One transaction for the whole world cannot do 43 hours of it in what is left of 120 s.
-- THE DEADLOCK (10-27 04:07:23): the arrivals run, updating a fleet's ships (FK KEY SHARE on her
-- players row), waited on the reconcile, which held that row FOR UPDATE (public.credit) and waited on a
-- row the arrivals run had written. Two writers that each hold rows the other wants.
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- (1) THE SAME RULES, A HOUSE AT A TIME. public.npc_compact_house(house, now) is npc_compact's per-house
--     work, moved verbatim: her ended voyages (her fleets'), her past game-days of trade_daily, her ledger
--     rolled into one NPC_CARRIED row (the balance computed, asserted), her events. public.npc_compact_orders(now)
--     is its orders delete, verbatim. public.npc_compact(now) keeps its signature, gate and answer and is
--     now those two composed (orders, then every house in id order): one authority for each rule.
--     A new partial index, voyages (fleet_id, eta) where status <> 'SAILING', finds a house's ended voyages.
-- (2) THE HOUR COMPACTS HOUSE BY HOUSE, ONE TRANSACTION EACH, UNDER ITS OWN 30 s BUDGET. tick_reconcile's
--     compact step runs the orders, then the houses — the house compacted longest ago first (the oldest
--     ledger row she has: her NPC_CARRIED row stands at her last cut) — each in its own transaction, until
--     30 s have gone; the rest wait for the next hour, first in line. A house that fails is rolled back
--     alone and counted. The backlog drains over a few hours; a clean hour is a few seconds.
-- (3) NO UPKEEP STEP BESIDE AN ARRIVALS BEAT. public.hold_the_quay() takes one transaction-level advisory
--     lock. Every arrivals beat (public.tick_arrivals_each_second, before public.tick_arrivals()) and every
--     write step of the hour (each merchant, the companies, the orders, each house) takes it first, before
--     any row lock, and holds it to its own commit. So an upkeep step and a beat never hold row locks at the
--     same time: the two cannot deadlock, and the compactor never waits on a beat's rows. A beat waits at
--     most one step (the steps are small); a step waits at most one beat.
-- (4) public.reconcile_runs: one row a run (7 days kept), the receipt the NOTICE carried plus each phase's
--     ms — so the next failure is read, not guessed.
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- Change a rule: which rows are deleted, what the carried row says, what a merchant's upkeep decides, what
-- an arrival does (public.tick_arrivals and everything under it are untouched: asserted byte for byte).
-- Change any knob, flag, schedule, grant or client read. The compactor deletes only what it deleted.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward slice reverses the hunks below (every OLD text is here verbatim). The new functions, the index
-- and the table are additive and harmless left in place.
--
-- VERSION: 0249 (prod head 0248). Hunks cut from the LIVE bodies on prod at head 0248, LF-normalised.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.tick_arrivals_each_second(int)') is null
     or to_regprocedure('public.tick_reconcile(boolean)') is null
     or to_regprocedure('public.npc_compact(timestamptz)') is null then
    raise exception '0249 refuses: 0097 / 0137 / 0248 is not in this world';
  end if;
  if to_regclass('public.reconcile_runs') is not null then
    raise exception '0249 refuses: public.reconcile_runs already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0249(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGE (LF-normalised) ────────────────────────────────────────────────────────────
create temp table defs_before_0249 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.npc_compact(timestamp with time zone)'),
               ('public.tick_reconcile(boolean)'),
               ('public.tick_arrivals_each_second(integer)')) f(fn);

create temp table before_0249 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(replace(pg_get_functiondef('public.tick_arrivals(timestamptz)'::regprocedure), E'\r', ''))) as arrivals_md5;

-- the old compactor, kept for the self-assert's comparison run
do $$
begin
  if pg_temp.occurs_0249((select def from defs_before_0249 where fn = 'public.npc_compact(timestamp with time zone)'),
                         'FUNCTION public.npc_compact(') <> 1 then
    raise exception '0249 self-assert FAIL: npc_compact''s definition does not name itself once';
  end if;
  execute replace((select def from defs_before_0249 where fn = 'public.npc_compact(timestamp with time zone)'),
                  'FUNCTION public.npc_compact(', 'FUNCTION pg_temp.npc_compact_old_0249(');
end $$;

-- ── 1. THE QUAY LOCK ────────────────────────────────────────────────────────────────────────────
create function public.hold_the_quay()
returns void
language sql
volatile
as $$ select pg_advisory_xact_lock(hashtextextended('byeharu.quay_or_upkeep', 249)) $$;
comment on function public.hold_the_quay() is
  '0249: THE one lock an arrivals beat and an hourly upkeep step both take first and hold to their commit, so the two never hold row locks at once (no deadlock, no lock wait between them). Taken by public.tick_arrivals_each_second (each beat) and public.tick_reconcile (each write step). Server-only.';
revoke all on function public.hold_the_quay() from public, anon, authenticated;

-- ── 2. THE RULES, A HOUSE AT A TIME ─────────────────────────────────────────────────────────────
create index voyages_fleet_ended_0249 on public.voyages (fleet_id, eta) where status <> 'SAILING';

create function public.npc_compact_orders(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0249: npc_compact's orders delete, moved verbatim (a merchant's finished orders past the window, not
-- read by a route's open lap). Called by public.npc_compact and by public.tick_reconcile's compact step.
declare
  v_cut     timestamptz := p_now - make_interval(hours => public.wc_int('npc_retention_hours'));
  v_ord     int := 0;
begin
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false);
  end if;
  delete from public.orders o
   using public.players p
   where o.player_id = p.id and p.is_npc
     and o.status in ('done', 'skipped', 'cancelled') and coalesce(o.executed_at, o.issued_at) < v_cut
     and not exists (select 1 from public.standing_routes sr where sr.lap_id = o.route_lap_id);
  get diagnostics v_ord = row_count;
  return jsonb_build_object('orders', v_ord);
end $$;
comment on function public.npc_compact_orders(timestamptz) is
  '0249: public.npc_compact''s orders delete, verbatim: a merchant''s done / skipped / cancelled orders past the window, not read by an open lap. Server-only.';
revoke all on function public.npc_compact_orders(timestamptz) from public, anon, authenticated;

create function public.npc_compact_house(p_house uuid, p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0249: ONE merchant house's compaction — npc_compact's per-house rules, moved verbatim: her ended
-- voyages (her fleets', not read by a route's open lap; their voyage_events cascade), her past game-days
-- of trade_daily, her ledger before the cut rolled into ONE NPC_CARRIED row (the balance computed from the
-- purse, then asserted), her events (not of a kept kind, not named by a remaining ledger row). Small enough
-- for a transaction of its own: public.tick_reconcile runs one house a transaction. A player's house is
-- never touched (only a merchant's: here, and in public.forbid_mutation's exemption).
declare
  v_cut     timestamptz := p_now - make_interval(hours => public.wc_int('npc_retention_hours'));
  v_n       int;
  v_sum     bigint;
  v_bal     bigint;
  v_at      timestamptz;
  v_voy     int := 0;
  v_led     int := 0;
  v_ev      int := 0;
  v_td      int := 0;
begin
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false);
  end if;
  if not exists (select 1 from public.players p where p.id = p_house and p.is_npc) then
    return jsonb_build_object('voyages', 0, 'ledger_rolled', 0, 'events', 0, 'trade_daily', 0);
  end if;
  perform set_config('byeharu.npc_compact', 'on', true);

  delete from public.voyages v
   using public.fleets f
   where v.fleet_id = f.id and f.player_id = p_house
     and v.status <> 'SAILING' and v.eta < v_cut
     and not exists (select 1 from public.orders o
                       join public.standing_routes sr on sr.lap_id = o.route_lap_id
                      where o.verb = 'SAIL' and o.status = 'done'
                        and (o.result->>'voyage_id')::uuid = v.id);
  get diagnostics v_voy = row_count;

  delete from public.trade_daily td
   where td.player_id = p_house and td.game_day < world.game_day(p_now);
  get diagnostics v_td = row_count;

  select count(*), coalesce(sum(l.ducats_delta), 0), max(l.created_at)
    into v_n, v_sum, v_at
    from public.ledger l where l.player_id = p_house and l.created_at < v_cut;
  if v_n >= 2 then
    -- THE CARRIED ROW'S RUNNING BALANCE IS COMPUTED, NOT PICKED (0097): the purse now, less every delta
    -- booked after the cut — exact by construction, whatever the order inside a tick.
    select p.ducats - coalesce((select sum(l2.ducats_delta) from public.ledger l2
                                 where l2.player_id = p_house and l2.created_at >= v_cut), 0)
      into v_bal from public.players p where p.id = p_house;
    delete from public.ledger l where l.player_id = p_house and l.created_at < v_cut;
    insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at)
    values (p_house, 'NPC_CARRIED', v_sum, v_bal, null, v_at);
    perform public.assert_ledger_reconciles(p_house);
    v_led := v_n;
  end if;
  delete from public.events ev
   where ev.player_id = p_house and ev.created_at < v_cut
     and ev.kind not in ('FOUNDED', 'NPC_REFOUNDED', 'SIGNED_OFFICER', 'STUDIED')
     and not exists (select 1 from public.ledger l where l.ref_event_id = ev.id);
  get diagnostics v_ev = row_count;

  perform set_config('byeharu.npc_compact', 'off', true);
  return jsonb_build_object('voyages', v_voy, 'ledger_rolled', v_led, 'events', v_ev, 'trade_daily', v_td);
end $$;
comment on function public.npc_compact_house(uuid, timestamptz) is
  '0249: ONE merchant house''s compaction (public.npc_compact''s per-house rules, verbatim): her ended voyages, past trade_daily, ledger rolled into one NPC_CARRIED row (asserted), events. public.tick_reconcile runs one house a transaction. Server-only.';
revoke all on function public.npc_compact_house(uuid, timestamptz) from public, anon, authenticated;

-- ── 3. THE RECEIPTS ─────────────────────────────────────────────────────────────────────────────
create table public.reconcile_runs (
  at       timestamptz primary key,
  ms       bigint      not null check (ms >= 0),
  receipt  jsonb       not null
);
comment on table public.reconcile_runs is
  '0249: one row an hourly reconcile run that reached its end (7 days kept): its instant (the run''s now()), how long it took, and its receipt — the merchant upkeep''s counts, the compactor''s (houses done, left for the next hour, failed, rows), each phase''s ms. One writer: public.tick_reconcile. A run that raised writes none (pg_cron''s job_run_details has its error). Server-only.';
alter table public.reconcile_runs enable row level security;
revoke all on table public.reconcile_runs from public, anon, authenticated;

-- ── 4. THE RE-CUTS ──────────────────────────────────────────────────────────────────────────────
create temp table hunks_0249 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0249 (fn, n, old, new) values
-- npc_compact: its per-house body and its orders delete become the two functions above, composed
('public.npc_compact(timestamp with time zone)', 1,
$h$  v_ord     int := 0;
begin
$h$,
$h$  v_ord     int := 0;
  v_h       jsonb;   -- 0249: one house's answer
begin
$h$),
('public.npc_compact(timestamp with time zone)', 2,
$h$  delete from public.voyages v
   using public.fleets f, public.players p
   where v.fleet_id = f.id and f.player_id = p.id and p.is_npc
     and v.status <> 'SAILING' and v.eta < v_cut
     and not exists (select 1 from public.orders o
                       join public.standing_routes sr on sr.lap_id = o.route_lap_id
                      where o.verb = 'SAIL' and o.status = 'done'
                        and (o.result->>'voyage_id')::uuid = v.id);
  get diagnostics v_voy = row_count;

  delete from public.orders o
   using public.players p
   where o.player_id = p.id and p.is_npc
     and o.status in ('done', 'skipped', 'cancelled') and coalesce(o.executed_at, o.issued_at) < v_cut
     and not exists (select 1 from public.standing_routes sr where sr.lap_id = o.route_lap_id);
  get diagnostics v_ord = row_count;

  delete from public.trade_daily td
   using public.players p
   where td.player_id = p.id and p.is_npc and td.game_day < world.game_day(p_now);
  get diagnostics v_td = row_count;

  for hh in select p.id from public.players p where p.is_npc order by p.id loop
    select count(*), coalesce(sum(l.ducats_delta), 0), max(l.created_at)
      into v_n, v_sum, v_at
      from public.ledger l where l.player_id = hh.id and l.created_at < v_cut;
    if v_n >= 2 then
      -- THE CARRIED ROW'S RUNNING BALANCE IS COMPUTED, NOT PICKED. Every row written inside one
      -- tick shares created_at (= the transaction's now()), so `order by created_at desc` has no
      -- tie-break that means "last": picking the highest balance_after among the last tick's rows
      -- returned the wrong running balance (+500 then -700 in one transaction carried 104,500 on a
      -- purse of 103,800), and assert_ledger_reconciles checks only Σ delta, so nothing raised
      -- (found by the 2026-10-08 review). The balance after the LAST collapsed row is the purse
      -- now, less every delta booked after the cut — exact by construction, whatever the order
      -- inside a tick.
      select p.ducats - coalesce((select sum(l2.ducats_delta) from public.ledger l2
                                   where l2.player_id = hh.id and l2.created_at >= v_cut), 0)
        into v_bal from public.players p where p.id = hh.id;
      delete from public.ledger l where l.player_id = hh.id and l.created_at < v_cut;
      insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at)
      values (hh.id, 'NPC_CARRIED', v_sum, v_bal, null, v_at);
      perform public.assert_ledger_reconciles(hh.id);
      v_led := v_led + v_n;
    end if;
    delete from public.events ev
     where ev.player_id = hh.id and ev.created_at < v_cut
       and ev.kind not in ('FOUNDED', 'NPC_REFOUNDED', 'SIGNED_OFFICER', 'STUDIED')
       and not exists (select 1 from public.ledger l where l.ref_event_id = ev.id);
    get diagnostics v_n = row_count;
    v_ev := v_ev + v_n;
  end loop;

$h$,
$h$  -- 0249: THE SAME RULES, IN TWO PIECES: the orders (public.npc_compact_orders), then every house
  -- (public.npc_compact_house: her voyages, trade_daily, ledger, events), in id order. The hour runs the
  -- same pieces one house a transaction (public.tick_reconcile); this is the whole world in one.
  v_ord := coalesce((public.npc_compact_orders(p_now)->>'orders')::int, 0);
  for hh in select p.id from public.players p where p.is_npc order by p.id loop
    v_h := public.npc_compact_house(hh.id, p_now);
    v_voy := v_voy + coalesce((v_h->>'voyages')::int, 0);
    v_td  := v_td  + coalesce((v_h->>'trade_daily')::int, 0);
    v_led := v_led + coalesce((v_h->>'ledger_rolled')::int, 0);
    v_ev  := v_ev  + coalesce((v_h->>'events')::int, 0);
  end loop;

$h$),
-- tick_reconcile: the phases timed, the compactor house by house, every write step after the quay lock
('public.tick_reconcile(boolean)', 1,
$h$  v_wait     uuid[] := '{}';   -- 0182: the waiting merchants the sweep asks in turn (not overdue)
begin
$h$,
$h$  v_wait     uuid[] := '{}';   -- 0182: the waiting merchants the sweep asks in turn (not overdue)
  -- 0249: the phases' ms, and the compactor's step house by house
  v_t0       timestamptz := clock_timestamp();
  v_t        timestamptz := clock_timestamp();
  v_ms       jsonb := '{}'::jsonb;
  v_cby      timestamptz;          -- the compactor's own budget: 30 s from its start
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
begin
$h$),
('public.tick_reconcile(boolean)', 2,
$h$    perform public.npc_upkeep_scope(v_deadline);
    begin
      v_step := public.npc_tend_route($h$,
$h$    if p_commit then perform public.hold_the_quay(); end if;   -- 0249: never beside an arrivals beat
    perform public.npc_upkeep_scope(v_deadline);
    begin
      v_step := public.npc_tend_route($h$),
('public.tick_reconcile(boolean)', 3,
$h$  perform public.npc_upkeep_scope(clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds')));
  begin
    v_step := public.npc_tend_houses(v_now);
$h$,
$h$  v_ms := v_ms || jsonb_build_object('tend', round(extract(epoch from clock_timestamp() - v_t) * 1000)); v_t := clock_timestamp();   -- 0249
  if p_commit then perform public.hold_the_quay(); end if;   -- 0249: never beside an arrivals beat
  perform public.npc_upkeep_scope(clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds')));
  begin
    v_step := public.npc_tend_houses(v_now);
$h$),
('public.tick_reconcile(boolean)', 4,
$h$  perform public.npc_upkeep_scope(v_deadline);
  begin
    v_upkeep := v_upkeep || jsonb_build_object('compact', public.npc_compact(v_now));
  exception when others then
    v_upkeep := v_upkeep || jsonb_build_object('compact_error', sqlerrm);
  end;
  if p_commit then commit; end if;
$h$,
$h$  v_ms := v_ms || jsonb_build_object('companies', round(extract(epoch from clock_timestamp() - v_t) * 1000)); v_t := clock_timestamp();   -- 0249
  -- 0249: THE COMPACTOR, A HOUSE AT A TIME. One transaction for the whole world could not finish once its
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
    for h in select p.id from public.players p where p.is_npc
              order by (select min(l.created_at) from public.ledger l where l.player_id = p.id) nulls first, p.id loop
      if clock_timestamp() >= v_cby then
        v_cleft := v_cleft + 1;
        continue;
      end if;
      if p_commit then perform public.hold_the_quay(); end if;
      perform public.npc_upkeep_scope(v_deadline);
      begin
        v_ch := public.npc_compact_house(h.id, v_now);
        v_cvoy := v_cvoy + coalesce((v_ch->>'voyages')::int, 0);
        v_cled := v_cled + coalesce((v_ch->>'ledger_rolled')::int, 0);
        v_cev  := v_cev  + coalesce((v_ch->>'events')::int, 0);
        v_ctd  := v_ctd  + coalesce((v_ch->>'trade_daily')::int, 0);
        v_cdone := v_cdone + 1;
      exception when others then
        v_cfail := v_cfail + 1;
        v_cnote := coalesce(v_cnote, 'house ' || h.id || ': ' || sqlerrm);
      end;
      if p_commit then commit; end if;
    end loop;
  end if;
  v_upkeep := v_upkeep || jsonb_build_object('compact', jsonb_build_object(
    'enabled', v_on, 'houses', v_cdone, 'left', v_cleft, 'failed', v_cfail, 'note', v_cnote,
    'voyages', v_cvoy, 'ledger_rolled', v_cled, 'events', v_cev, 'trade_daily', v_ctd,
    'orders', coalesce((v_cx->>'orders')::int, 0),
    'before', v_now - make_interval(hours => public.wc_int('npc_retention_hours'))));
  v_ms := v_ms || jsonb_build_object('compact', round(extract(epoch from clock_timestamp() - v_t) * 1000)); v_t := clock_timestamp();
$h$),
('public.tick_reconcile(boolean)', 5,
$h$  raise notice 'tick_reconcile: %', jsonb_build_object('players_checked', v_n, 'sailing_invariant', 'ok',
                                                       'client_write_grants', 0, 'merchant_upkeep', v_upkeep);
$h$,
$h$  v_ms := v_ms || jsonb_build_object('check', round(extract(epoch from clock_timestamp() - v_t) * 1000));   -- 0249
  -- 0249: THE RECEIPT IS KEPT (public.reconcile_runs, 7 days), not only told.
  delete from public.reconcile_runs where at < v_now - interval '7 days';
  insert into public.reconcile_runs (at, ms, receipt)
  values (v_now, round(extract(epoch from clock_timestamp() - v_t0) * 1000)::bigint,
          jsonb_build_object('players_checked', v_n, 'merchant_upkeep', v_upkeep, 'ms', v_ms))
  on conflict (at) do update set ms = excluded.ms, receipt = excluded.receipt;
  raise notice 'tick_reconcile: %', jsonb_build_object('players_checked', v_n, 'sailing_invariant', 'ok',
                                                       'client_write_grants', 0, 'merchant_upkeep', v_upkeep);
$h$),
-- tick_arrivals_each_second: every beat takes the quay lock before its run (the run itself untouched)
('public.tick_arrivals_each_second(integer)', 1,
$h$      v_r := public.tick_arrivals();
$h$,
$h$      perform public.hold_the_quay();   -- 0249: never beside an hourly upkeep step (no deadlock between them)
      v_r := public.tick_arrivals();
$h$);

create or replace function pg_temp.recut_0249(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0249 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0249 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0249(v_def, h.old);
    if v_n <> 1 then
      raise exception '0249 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0249(fn) from defs_before_0249 order by fn;

-- ── 5. THE PROBE: one merchant house with rows from before the cut, compacted three ways ────────
-- p_now is 2026-08-01: its cut (six hours earlier) is before every real row in the world, so the old
-- compactor and the new touch the probe's rows alone. The probe house is made once (rolled back at the
-- end); each run starts from that same state inside a block of its own and is rolled back after its
-- digest is taken: (old) the 0248 compactor, kept in pg_temp; (all) the new public.npc_compact; (hour)
-- what the hour runs — public.npc_compact_orders, then public.npc_compact_house for the probe.
create or replace function pg_temp.digest_0249(p_house uuid)
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
    'voyage_events_n', (select count(*) from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
                          join public.fleets f on f.id = v.fleet_id where f.player_id = p_house),
    'orders', (select md5(coalesce(string_agg(o.id::text, ',' order by o.id), '')) from public.orders o where o.player_id = p_house),
    'orders_n', (select count(*) from public.orders o where o.player_id = p_house),
    'trade_daily', (select md5(coalesce(string_agg(concat_ws('|', td.port_id, td.good_id, td.game_day, td.qty), ',' order by td.game_day, td.port_id, td.good_id), ''))
                      from public.trade_daily td where td.player_id = p_house),
    'trade_daily_n', (select count(*) from public.trade_daily td where td.player_id = p_house),
    'purse', (select p.ducats from public.players p where p.id = p_house),
    'ledger_sum', public.ledger_sum(p_house))
$$;

create or replace function pg_temp.run_0249(p_how text, p_house uuid, p_now timestamptz)
returns jsonb
language plpgsql
as $$
declare
  v_ret jsonb;
  v_t0  timestamptz := clock_timestamp();
begin
  begin
    if p_how = 'old' then
      v_ret := pg_temp.npc_compact_old_0249(p_now);
    elsif p_how = 'all' then
      v_ret := public.npc_compact(p_now);
    else
      v_ret := jsonb_build_object('orders', public.npc_compact_orders(p_now), 'house', public.npc_compact_house(p_house, p_now));
    end if;
    raise exception using errcode = 'ZY249',
      message = jsonb_build_object('ret', v_ret, 'd', pg_temp.digest_0249(p_house),
                                   'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000))::text;
  exception when sqlstate 'ZY249' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 6. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before record;
  v_d record; v_h record; v_pp record; v_def text;
  c_now   constant timestamptz := '2026-08-01 00:00:00+00';
  c_old   constant timestamptz := '2026-07-31 12:00:00+00';   -- before the cut (2026-07-31 18:00)
  v_res   jsonb;
begin
  select * into v_before from before_0249;

  -- (a) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0249 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0249 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0249(v_def, v_h.new) <> 1 then
        raise exception '0249 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0249 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0249 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(replace(pg_get_functiondef('public.tick_arrivals(timestamptz)'::regprocedure), E'\r', ''))) <> v_before.arrivals_md5 then
    raise exception '0249 self-assert FAIL: public.tick_arrivals moved';
  end if;
  -- every write step of the hour and every beat takes the quay lock; nothing else does
  v_def := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  if pg_temp.occurs_0249(v_def, 'if p_commit then perform public.hold_the_quay(); end if;') <> 4 then
    raise exception '0249 self-assert FAIL: tick_reconcile takes the quay lock % time(s), not 4 (merchant, companies, orders, house)',
      pg_temp.occurs_0249(v_def, 'if p_commit then perform public.hold_the_quay(); end if;');
  end if;
  if pg_temp.occurs_0249(v_def, 'public.npc_compact(') <> 0 then
    raise exception '0249 self-assert FAIL: tick_reconcile still runs the whole-world compactor in one transaction';
  end if;
  if pg_temp.occurs_0249(replace(pg_get_functiondef('public.tick_arrivals_each_second(integer)'::regprocedure), E'\r', ''),
                         E'perform public.hold_the_quay();   -- 0249: never beside an hourly upkeep step (no deadlock between them)\n      v_r := public.tick_arrivals();') <> 1 then
    raise exception '0249 self-assert FAIL: a beat does not take the quay lock right before its run';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'voyage', 'world') and p.prokind in ('f', 'p')
                and p.oid not in ('public.tick_reconcile(boolean)'::regprocedure, 'public.tick_arrivals_each_second(integer)'::regprocedure,
                                  'public.hold_the_quay()'::regprocedure)
                and pg_get_functiondef(p.oid) like '%hold_the_quay%') then
    raise exception '0249 self-assert FAIL: something else takes the quay lock';
  end if;
  if has_function_privilege('anon', 'public.npc_compact_house(uuid,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_compact_house(uuid,timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.npc_compact_orders(timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_compact_orders(timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.hold_the_quay()', 'execute')
     or has_function_privilege('authenticated', 'public.hold_the_quay()', 'execute')
     or has_table_privilege('anon', 'public.reconcile_runs', 'select')
     or has_table_privilege('authenticated', 'public.reconcile_runs', 'select') then
    raise exception '0249 self-assert FAIL: a client role can reach a compactor piece, the quay lock or the receipts';
  end if;

  -- (b) THE SAME ROWS GO: one probe house, the three ways, from the same state (rolled back whole)
  begin
    declare
      v_m    uuid;
      v_f    uuid;
      v_port uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1);
      v_port2 uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_port order by p.code limit 1);
      v_good uuid := (select g.id from public.goods g order by g.code limit 1);
      v_gd   int := world.game_day(c_now);
      v_purse bigint;
      e1 uuid := gen_random_uuid(); e2 uuid := gen_random_uuid(); e3 uuid := gen_random_uuid();
      e4 uuid := gen_random_uuid(); e5 uuid := gen_random_uuid();
      v1 uuid := gen_random_uuid(); v2 uuid := gen_random_uuid();
      v_old jsonb; v_all jsonb; v_hour jsonb; v_pre jsonb;
    begin
      -- the compactor is gated on the merchants' switch: on prod it is on; a fresh chain may have it off,
      -- and only then is it lit, inside this rolled-back block
      if not public.npc_traders_on() then
        update public.world_config set value = 'true'::jsonb
         where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
        if not public.npc_traders_on() then
          raise exception '0249 self-assert FAIL: cannot light the merchants for the probe';
        end if;
      end if;
      v_m := public.new_house(null, 'Casa do Arquivo 0249', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
      v_f := (select f.id from public.fleets f where f.player_id = v_m order by f.created_at limit 1);
      if v_f is null then
        insert into public.fleets (player_id, name, port_id) values (v_m, 'Arquivo 0249', v_port) returning id into v_f;
      end if;
      -- events: E1 old (goes), E2 old and named by an old ledger row (goes once that row is rolled),
      -- E3 old and named by a kept ledger row (stays), E4 old FOUNDED (a kept kind: stays), E5 new (stays)
      insert into public.events (id, player_id, kind, payload, created_at) values
        (e1, v_m, 'PROBE_0249', '{}', c_old), (e2, v_m, 'PROBE_0249', '{}', c_old),
        (e3, v_m, 'PROBE_0249', '{}', c_old), (e4, v_m, 'FOUNDED', '{}', c_old - interval '1 day'),
        (e5, v_m, 'PROBE_0249', '{}', c_now);
      -- ledger: three old rows that sum to 0 (rolled into one NPC_CARRIED row) and one after the cut
      -- naming E3; the purse is untouched, so it still reconciles
      insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, created_at) values
        (v_m, 'PROBE_0249', 300, 1300, null, c_old - interval '2 hours'),
        (v_m, 'PROBE_0249', -250, 1050, null, c_old - interval '1 hour'),
        (v_m, 'PROBE_0249', -50, 1000, e2, c_old),
        (v_m, 'PROBE_0249', 0, 1000, e3, c_now);
      -- voyages: V1 ended before the cut (goes, its day row with it), V2 ended after it (stays)
      insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status,
                                  origin_port_id, dest_port_id, created_at) values
        (v1, v_f, v_m, '[]', 100, '{}', c_old - interval '1 day', c_old, 'ARRIVED', v_port, v_port2, c_old - interval '1 day'),
        (v2, v_f, v_m, '[]', 100, '{}', c_old, c_now, 'ARRIVED', v_port2, v_port, c_old);
      insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
      select v1, 1, k.code, '{}', c_old from public.voyage_event_kinds k order by k.code limit 1;
      -- orders: one done before the cut (goes), one pending (stays)
      insert into public.orders (fleet_id, player_id, seq, raw_text, verb, status, issued_at, executed_at) values
        (v_f, v_m, 900001, 'PROBE 0249', 'PROBE', 'done', c_old, c_old),
        (v_f, v_m, 900002, 'PROBE 0249', 'PROBE', 'pending', c_old, null);
      -- trade_daily: a past game-day (goes) and the probe's own (stays)
      insert into public.trade_daily (player_id, port_id, good_id, game_day, qty) values
        (v_m, v_port, v_good, v_gd - 1, 5), (v_m, v_port, v_good, v_gd, 7);
      v_purse := (select p.ducats from public.players p where p.id = v_m);
      v_pre := pg_temp.digest_0249(v_m);

      v_old  := pg_temp.run_0249('old', v_m, c_now);
      v_all  := pg_temp.run_0249('all', v_m, c_now);
      v_hour := pg_temp.run_0249('hour', v_m, c_now);

      if v_old->'d' is distinct from v_all->'d' or v_old->'d' is distinct from v_hour->'d' then
        raise exception '0249 self-assert FAIL: the three ways left different rows (old %, all %, hour %)', v_old, v_all, v_hour;
      end if;
      if (v_old->'ret') - 'before' is distinct from (v_all->'ret') - 'before' or v_old->'ret'->>'before' is distinct from v_all->'ret'->>'before' then
        raise exception '0249 self-assert FAIL: npc_compact answers otherwise than before (old %, new %)', v_old->'ret', v_all->'ret';
      end if;
      if (v_hour->'ret'->'house'->>'voyages')::int <> (v_old->'ret'->>'voyages')::int
         or (v_hour->'ret'->'house'->>'events')::int <> (v_old->'ret'->>'events')::int
         or (v_hour->'ret'->'house'->>'ledger_rolled')::int <> (v_old->'ret'->>'ledger_rolled')::int
         or (v_hour->'ret'->'house'->>'trade_daily')::int <> (v_old->'ret'->>'trade_daily')::int
         or (v_hour->'ret'->'orders'->>'orders')::int <> (v_old->'ret'->>'orders')::int then
        raise exception '0249 self-assert FAIL: the hour''s pieces counted otherwise than the old compactor (old %, hour %)', v_old->'ret', v_hour->'ret';
      end if;
      -- and what went is what should have gone
      if (v_old->'ret'->>'voyages')::int <> 1 or (v_old->'ret'->>'events')::int <> 2
         or (v_old->'ret'->>'ledger_rolled')::int <> 3 or (v_old->'ret'->>'trade_daily')::int <> 1
         or (v_old->'ret'->>'orders')::int <> 1
         or (v_old->'d'->>'events_n')::int <> (v_pre->>'events_n')::int - 2
         or (v_old->'d'->>'voyages_n')::int <> (v_pre->>'voyages_n')::int - 1
         or (v_old->'d'->>'voyage_events_n')::int <> (v_pre->>'voyage_events_n')::int - 1
         or (v_old->'d'->>'orders_n')::int <> (v_pre->>'orders_n')::int - 1
         or (v_old->'d'->>'trade_daily_n')::int <> (v_pre->>'trade_daily_n')::int - 1
         or (v_old->'d'->>'ledger_n')::int <> (v_pre->>'ledger_n')::int - 2
         or (v_old->'d'->>'carried')::int <> 1
         or (v_old->'d'->>'purse')::bigint <> v_purse or (v_old->'d'->>'ledger_sum')::bigint <> v_purse then
        raise exception '0249 self-assert FAIL: the probe did not compact as the rules say (before %, after %) — the comparison proved nothing', v_pre, v_old;
      end if;
      v_res := jsonb_build_object('old_ms', v_old->'ms', 'all_ms', v_all->'ms', 'hour_ms', v_hour->'ms', 'ret', (v_old->'ret') - 'before');
      raise exception using errcode = 'ZY24A', message = v_res::text;
    end;
  exception when sqlstate 'ZY24A' then
    v_res := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.players where company_name = 'Casa do Arquivo 0249') then
    raise exception '0249 self-assert FAIL: the probe house was left behind';
  end if;

  -- (c) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0249 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0249 self-assert FAIL: a wall moved';
  end if;

  raise notice '0249 self-assert ok: THE BOOKS ARE CUT A HOUSE AT A TIME. npc_compact = npc_compact_orders + npc_compact_house per house (2 hunks); tick_reconcile compacts one house a transaction under a 30 s budget, oldest-compacted first, and keeps its receipt in public.reconcile_runs (5 hunks); every hourly write step and every arrivals beat takes public.hold_the_quay() first (1 hunk in the beat); all reverse to their pre-images, ACL / volatility / definer / config unmoved; tick_arrivals untouched; registry unchanged; walls 0. PROBE (one merchant house, rows before a 2026-08-01 cut, rolled back): the 0248 compactor, the new one and the hour''s pieces left identical rows and counts: %. Nothing left behind.',
    v_res;
end $$;
