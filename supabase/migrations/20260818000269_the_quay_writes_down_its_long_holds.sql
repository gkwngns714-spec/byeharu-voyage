-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0269 — THE QUAY WRITES DOWN ITS LONG HOLDS  (a RECORDING-ONLY slice: the :07 lap-start lag is measured where
--        it is made; nothing a merchant, a company, a beat, a lap start or the count decides moves)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY (prod, read-only, head 0267, docs/dev-log/2026-10-28-lap-start-spike.md) ─────────────────
-- In the first 12-32 s of every hourly :07 the reconcile's TEND phase runs ~836 single-merchant quay transactions,
-- some holding the quay ~1-1.4 s (12:07: the longest hold 1,393.8 ms, the beat at 12:07:05 waited 1,391 ms). A long
-- hold makes that second's beat late; the lap-start open step then waits its full 1.5 s gap and queues; lap-start
-- lag p95 is 6-15 s in :07 (3.4 s in the one hour, 10:07, whose :06 count did not spill into :07).
-- NOT on record, so not fixable yet: WHICH tend steps hold ~1 s and what they did (receipt.quay.tend keeps only
-- n / held / longest / waited); the lap start's own parts per lap; the :07 beats once the hour's ring turns over;
-- and the :06 count's phases (public.tick_stats returns its total ms only; pg_cron logs "1 row").
--
-- ── WHAT THIS FILE RECORDS ─────────────────────────────────────────────────────────────────────
-- (1) reconcile_runs.receipt.tend_holds = {n, kept[]}: every tend step that HELD the quay over 100 ms, or WAITED
--     for it over 100 ms (the tend phase's waits are what grew when the count spilled: 16-18 s vs 5.4 s), one entry
--     each (public.quay_hold_note; at most 300 kept, n counts all): fleet, route, house; what she was when her step
--     began (fleet status / route pause, a plain read of her two rows); the quay asked / granted / committed
--     instants; wait, held, and the hold's three parts — her step (public.npc_tend_route), her purse check
--     (public.assert_ledger_reconciles), the commit; and what the step did (its non-zero counts: started,
--     resumed, cleared, laid_up, waiting, dark, deferred, busy, failed; and its notes: towed, tow_refused,
--     cannot_sail, off_route, not_planned, …), or "raised". tick_reconcile: 3 hunks.
-- (2) lap_start_runs.receipt.steps[]: every lap start of the minute: fleet, due (hold_until), the plan step's start /
--     ms / answer, the gap wait's start / ms / late, the open step's start, ITS OWN QUAY WAIT (the quay is asked
--     for first in the open step's transaction, timed, then public.lap_start_open asks again — the same lock in the
--     same transaction, granted at once), its ms and answer. tick_lap_starts: 6 hunks.
-- (3) public.arrivals_beats_kept: the beats of :06:30-:09:00 copied out of the one-hour ring at :10 every hour
--     (public.keep_reconcile_beats, pg_cron byeharu-voyage:keep-beats '10 * * * *'), 7 days kept. :09:00 not :08:00:
--     the 11:07 reconcile ran 110 s, to 11:08:50.
-- (4) public.stats_runs: the count's receipt (7 days): its instant, start, ms and the ms of each phase in its
--     order (prev, recent, period, world, goods, cities, city_goods, merchants, fold, day, live). tick_stats: 11
--     hunks; the return is the same object (its two last figures are computed just before it, in its order).
--     A count that raises (the 120 s statement timeout) writes none, as before; pg_cron's log has its error.
--
-- ── WHY NOTHING ELSE MOVES ─────────────────────────────────────────────────────────────────────
-- Every hunk reverses to the live pre-image (asserted). What the hunks add: clock readings and new locals; one plain
-- read of a merchant's route and fleet rows (no lock); the receipts' new keys; the quay asked for once more in the
-- lap open's own transaction, BEFORE lap_start_open asks for it, inside the same subtransaction (so an error there
-- is caught as before); and tick_stats' own receipt row. No hunk takes a row lock or a new lock, and none writes a
-- game table (asserted). The quay is still the first lock every holder takes; the lock graph of 0265/0267 is
-- unchanged (the extra ask is the same lock, already the first). PROBES (rolled back, from the same state, on the
-- world it is applied to): the OLD tend loop vs the NEW for up to 8 merchants (4 to re-plan, 4 running), the old
-- again as the control: the same rows (route, stops, lines, laps, orders, fleet, ships, voyages, purse, new ledger
-- and events, her port's market and treasury) and the same receipt; the OLD lap-start job vs the NEW for up to 3
-- merchants made due alone, old again as the control: the same rows and receipt; the OLD count vs the NEW two hours
-- ahead: the same five tables' rows and the same answer. Overhead: timed below, per step.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward slice reverses the 20 hunks (each OLD text is here verbatim) and unschedules byeharu-voyage:keep-beats;
-- the two tables and two functions are harmless left alone.
--
-- VERSION: 0269 (prod head 0267 when cut; 0268 is the switch lock, which touches none of these three bodies).
-- Hunks cut from the LIVE bodies on prod at head 0267, LF.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.quay_tally(jsonb,timestamptz,timestamptz)') is null
     or to_regprocedure('public.tick_lap_starts(boolean)') is null or to_regclass('public.lap_start_runs') is null
     or to_regclass('public.arrivals_beats') is null or to_regprocedure('public.beat_ms(interval)') is null
     or to_regprocedure('public.tick_stats(timestamptz)') is null then
    raise exception '0269 refuses: 0267 (and the lap-start job and beat clock it was cut against) is not in this world';
  end if;
  if to_regclass('public.stats_runs') is not null or to_regclass('public.arrivals_beats_kept') is not null
     or to_regprocedure('public.quay_hold_note(jsonb,uuid,uuid,uuid,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,jsonb)') is not null then
    raise exception '0269 refuses: it has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0269(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0269 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_reconcile(boolean)'), ('public.tick_lap_starts(boolean)'), ('public.tick_stats(timestamptz)')) f(fn);

-- the functions this file must leave byte for byte: what the three bodies call to decide, the quay and its holders
create temp table kept_0269 on commit drop as
select f.fn from (values ('public.npc_tend_route(timestamptz,uuid,uuid,bigint)'), ('public.npc_tend_roster()'),
                         ('public.npc_tend_sum(jsonb,jsonb)'), ('public.npc_step_failed(jsonb,text)'),
                         ('public.npc_upkeep_scope(timestamptz)'), ('public.npc_waiting_queue(timestamptz)'),
                         ('public.assert_ledger_reconciles(uuid)'), ('public.quay_tally(jsonb,timestamptz,timestamptz)'),
                         ('public.npc_invest_one(timestamptz,uuid)'), ('public.capital_gift_one(timestamptz,uuid)'),
                         ('public.hold_the_quay()'), ('public.lap_start_open(uuid)'), ('public.lap_start_plan(uuid)'),
                         ('public.lap_starts_due()'), ('public.tick_arrivals(timestamptz)'),
                         ('public.tick_arrivals_each_second(integer)'), ('public.tick_compact(boolean,boolean)'),
                         ('public.stats_compact(timestamptz)'), ('public.stats_fold_day(bigint)'),
                         ('public.stats_live_fold(timestamptz,boolean)'), ('public.beat_ms(interval)'),
                         ('cmd.advance(uuid,timestamptz)'), ('public.npc_plan(timestamptz,uuid)')) f(fn);

create temp table before_0269 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn))
          from kept_0269 k) as kept_md5,
       (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
           and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%') as quay_takers;

-- THE OLD BODIES, kept as temp copies for the probes (renamed only; the reconcile's copies are cut in §5)
do $$
declare
  v text;
begin
  v := (select def from defs_before_0269 where fn = 'public.tick_lap_starts(boolean)');
  if pg_temp.occurs_0269(v, 'CREATE OR REPLACE PROCEDURE public.tick_lap_starts(') <> 1 then
    raise exception '0269 self-assert FAIL: the live tick_lap_starts does not open as this file expects';
  end if;
  execute replace(v, 'CREATE OR REPLACE PROCEDURE public.tick_lap_starts(', 'CREATE PROCEDURE pg_temp.lap_starts_old_0269(');
  v := (select def from defs_before_0269 where fn = 'public.tick_stats(timestamptz)');
  if pg_temp.occurs_0269(v, 'CREATE OR REPLACE FUNCTION public.tick_stats(') <> 1 then
    raise exception '0269 self-assert FAIL: the live tick_stats does not open as this file expects';
  end if;
  execute replace(v, 'CREATE OR REPLACE FUNCTION public.tick_stats(', 'CREATE FUNCTION pg_temp.stats_old_0269(');
end $$;

-- ── 1. THE NEW RECEIPTS ─────────────────────────────────────────────────────────────────────────
create function public.quay_hold_note(p_acc jsonb, p_fleet uuid, p_route uuid, p_house uuid, p_was text,
                                      p_asked timestamptz, p_got timestamptz, p_stepped timestamptz,
                                      p_checked timestamptz, p_done timestamptz, p_step jsonb)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $fn$
-- 0269: one tend step that held the quay over 100 ms (or waited for it over 100 ms) added to the hour's list
-- {n, kept[]} (receipt.tend_holds): n counts every one, kept holds the first 300. Times: the quay asked for
-- (p_asked), granted (p_got), her step done (p_stepped, null = it raised), her purse checked (p_checked, null =
-- the check raised or never ran), committed (p_done). `did` = the step's non-zero counts and its notes. Reads
-- nothing; called by public.tick_reconcile alone.
  select jsonb_build_object(
    'n', coalesce((p_acc->>'n')::int, 0) + 1,
    'kept', coalesce(p_acc->'kept', '[]'::jsonb)
            || case when jsonb_array_length(coalesce(p_acc->'kept', '[]'::jsonb)) >= 300 then '[]'::jsonb
                    else jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
                      'fleet', p_fleet, 'route', p_route, 'house', p_house, 'was', p_was,
                      'asked', p_asked, 'got', p_got, 'done', p_done,
                      'wait_ms', public.beat_ms(p_got - p_asked), 'held_ms', public.beat_ms(p_done - p_got),
                      'step_ms', public.beat_ms(p_stepped - p_got), 'check_ms', public.beat_ms(p_checked - p_stepped),
                      'commit_ms', public.beat_ms(p_done - coalesce(p_checked, p_stepped, p_got)),
                      'did', case when p_stepped is null then to_jsonb('raised'::text)
                                  else coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(p_step) e
                                                  where e.key <> 'notes' and e.value <> '0'::jsonb), '{}'::jsonb)
                                       || case when jsonb_array_length(coalesce(p_step->'notes', '[]'::jsonb)) > 0
                                               then jsonb_build_object('notes', p_step->'notes') else '{}'::jsonb end
                                       || case when p_checked is null then jsonb_build_object('purse_check', 'raised')
                                               else '{}'::jsonb end
                             end)))
               end)
$fn$;
comment on function public.quay_hold_note(jsonb, uuid, uuid, uuid, text, timestamptz, timestamptz, timestamptz, timestamptz, timestamptz, jsonb) is
  '0269: adds one long tend step (over 100 ms held or waited) to the hour''s list {n, kept[≤300]}: who, what she was, the quay asked / granted / committed, wait / held / step / check / commit ms, what the step did. Reads nothing. Server-only; called by public.tick_reconcile.';
revoke all on function public.quay_hold_note(jsonb, uuid, uuid, uuid, text, timestamptz, timestamptz, timestamptz, timestamptz, timestamptz, jsonb)
  from public, anon, authenticated;

create table public.stats_runs (
  at          timestamptz primary key,
  slot        bigint      not null,
  started_at  timestamptz not null,
  ms          numeric     not null check (ms >= 0),
  receipt     jsonb       not null
);
comment on table public.stats_runs is
  '0269: one row a count that reached its end (7 days kept): its instant (p_now), its slot, when it started, how long it took, and its receipt — the counts it returned (without day / live) and each phase''s ms in its order (phases: prev, recent, period, world, goods, cities, city_goods, merchants, fold, day, live). One writer: public.tick_stats. A count that raised writes none (pg_cron''s job_run_details has its error). Server-only.';
alter table public.stats_runs enable row level security;
revoke all on table public.stats_runs from public, anon, authenticated;

create table public.arrivals_beats_kept (
  at       timestamptz primary key,
  slot     int         not null,
  ms       numeric     not null,
  fleets   int,
  days     int,
  asked    int,
  error    text,
  splits   jsonb,
  kept_at  timestamptz not null default now()
);
comment on table public.arrivals_beats_kept is
  '0269: the arrivals beats of each hour''s :06:30-:09:00 (the reconcile minute and the count that may spill into it), copied out of the one-hour ring public.arrivals_beats at :10 (public.keep_reconcile_beats), 7 days kept. The beat''s own row, verbatim. Server-only.';
alter table public.arrivals_beats_kept enable row level security;
revoke all on table public.arrivals_beats_kept from public, anon, authenticated;

create function public.keep_reconcile_beats(p_now timestamptz default now())
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $fn$
-- 0269: THE :07 BEATS, KEPT PAST THE HOUR. Copies the ring's rows of this hour's :06:30-:09:00 (by their instant,
-- so a slot not yet overwritten this hour is not taken) into public.arrivals_beats_kept, once (on conflict nothing),
-- and forgets what is older than 7 days. Reads the ring (no lock a beat waits on: the beat upserts its own slot);
-- writes only its own table. pg_cron byeharu-voyage:keep-beats, '10 * * * *'.
declare
  v_from timestamptz := date_trunc('hour', p_now) + interval '6 minutes 30 seconds';
  v_to   timestamptz := date_trunc('hour', p_now) + interval '9 minutes';
  v_kept int;
  v_gone int;
begin
  insert into public.arrivals_beats_kept (at, slot, ms, fleets, days, asked, error, splits)
  select b.at, b.slot, b.ms, b.fleets, b.days, b.asked, b.error, b.splits
    from public.arrivals_beats b
   where b.at >= v_from and b.at < v_to
  on conflict (at) do nothing;
  get diagnostics v_kept = row_count;
  delete from public.arrivals_beats_kept where at < p_now - interval '7 days';
  get diagnostics v_gone = row_count;
  return jsonb_build_object('from', v_from, 'to', v_to, 'kept', v_kept, 'removed', v_gone);
end $fn$;
comment on function public.keep_reconcile_beats(timestamptz) is
  '0269: copies this hour''s :06:30-:09:00 beats out of the ring into public.arrivals_beats_kept (once) and keeps 7 days. pg_cron byeharu-voyage:keep-beats at :10. Server-only.';
revoke all on function public.keep_reconcile_beats(timestamptz) from public, anon, authenticated;

-- ── 2. THE HUNKS ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0269 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0269 (fn, n, old, new) values
-- ── tick_reconcile ──
('public.tick_reconcile(boolean)', 1,
$h$  v_qc       jsonb := '{}'::jsonb;
$h$,
$h$  v_qc       jsonb := '{}'::jsonb;
  -- 0269: the tend steps that held the quay (or waited for it) over 100 ms, written down (receipt.tend_holds)
  v_ts       timestamptz;
  v_tk       timestamptz;
  v_tc       timestamptz;
  v_was      text;
  v_holds    jsonb := '{}'::jsonb;
$h$),
('public.tick_reconcile(boolean)', 2,
$h$    v_th := clock_timestamp();   -- 0267: the quay granted
    perform public.npc_upkeep_scope(v_deadline);
    begin
      v_step := public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k);
      perform public.assert_ledger_reconciles(r.player_id);   -- her purse, before her COMMIT
      v_tend := public.npc_tend_sum(v_tend, v_step);
    exception when others then
      v_tend := public.npc_tend_sum(v_tend, public.npc_step_failed(jsonb_build_object('route', r.route_id), sqlerrm));
    end;
    if p_commit then commit; end if;
    v_qt := public.quay_tally(v_qt, v_tq, v_th);   -- 0267
$h$,
$h$    v_th := clock_timestamp();   -- 0267: the quay granted
    -- 0269: what she was as her step began (a plain read of her route and fleet rows, no lock), and the step's clock
    v_was := (select concat_ws('/', f.status, coalesce(sr.paused_reason, case when sr.fleet_id is null then 'unassigned' else 'running' end))
                from public.standing_routes sr left join public.fleets f on f.id = r.fleet_id where sr.id = r.route_id);
    v_ts := null;
    v_tk := null;
    perform public.npc_upkeep_scope(v_deadline);
    begin
      v_step := public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k);
      v_ts := clock_timestamp();   -- 0269: her step done
      perform public.assert_ledger_reconciles(r.player_id);   -- her purse, before her COMMIT
      v_tk := clock_timestamp();   -- 0269: her purse checked
      v_tend := public.npc_tend_sum(v_tend, v_step);
    exception when others then
      v_tend := public.npc_tend_sum(v_tend, public.npc_step_failed(jsonb_build_object('route', r.route_id), sqlerrm));
    end;
    if p_commit then commit; end if;
    v_tc := clock_timestamp();   -- 0269: committed
    v_qt := public.quay_tally(v_qt, v_tq, v_th);   -- 0267
    -- 0269: A STEP THAT HELD THE QUAY OVER 100 ms, OR WAITED FOR IT OVER 100 ms, IS WRITTEN DOWN (public.quay_hold_note)
    if v_tc - v_th > interval '100 milliseconds' or v_th - v_tq > interval '100 milliseconds' then
      v_holds := public.quay_hold_note(v_holds, r.fleet_id, r.route_id, r.player_id, v_was, v_tq, v_th, v_ts, v_tk, v_tc,
                                       case when v_ts is null then null else v_step end);
    end if;
$h$),
('public.tick_reconcile(boolean)', 3,
$h$                             'quay', jsonb_build_object('tend', v_qt, 'companies', v_qc)))   -- 0267$h$,
$h$                             'quay', jsonb_build_object('tend', v_qt, 'companies', v_qc),   -- 0267
                             'tend_holds', v_holds))   -- 0269$h$),
-- ── tick_lap_starts ──
('public.tick_lap_starts(boolean)', 1,
$h$  v_late   int := 0;
$h$,
$h$  v_late   int := 0;
  -- 0269: each lap start's own times (receipt.steps)
  v_p0     timestamptz;
  v_pm     numeric;
  v_w0     timestamptz;
  v_wm     numeric;
  v_lt     boolean;
  v_q1     timestamptz;
  v_steps  jsonb := '[]'::jsonb;
$h$),
('public.tick_lap_starts(boolean)', 2,
$h$    v_plan_max := greatest(v_plan_max, v_ms);
    if v_a <> 1 then
$h$,
$h$    v_plan_max := greatest(v_plan_max, v_ms);
    v_p0 := v_t; v_pm := v_ms; v_w0 := null; v_wm := null; v_lt := false; v_q1 := null;   -- 0269: this lap start's plan
    if v_a <> 1 then
      v_steps := v_steps || jsonb_build_array(jsonb_build_object('fleet', v_f, 'due', v_hold, 'plan_at', v_p0,
                                                                 'plan_ms', round(v_pm, 1), 'plan', v_a));   -- 0269
$h$),
('public.tick_lap_starts(boolean)', 3,
$h$      if clock_timestamp() - v_tw >= c_wait then v_late := v_late + 1; end if;
      v_wait_ms := v_wait_ms + v_ms;
      v_wait_max := greatest(v_wait_max, v_ms);
$h$,
$h$      if clock_timestamp() - v_tw >= c_wait then v_late := v_late + 1; v_lt := true; end if;   -- 0269: v_lt
      v_wait_ms := v_wait_ms + v_ms;
      v_wait_max := greatest(v_wait_max, v_ms);
      v_w0 := v_tw; v_wm := v_ms;   -- 0269: this lap start's wait for a gap
$h$),
('public.tick_lap_starts(boolean)', 4,
$h$    v_t := clock_timestamp();
    begin
      v_b := public.lap_start_open(v_f);
$h$,
$h$    v_t := clock_timestamp();
    begin
      -- 0269: the quay asked for here, to time the open step's own wait for it; public.lap_start_open asks for it
      -- again first thing (the same lock in the same transaction: granted at once). Still the first lock it takes.
      perform public.hold_the_quay();
      v_q1 := clock_timestamp();
      v_b := public.lap_start_open(v_f);
$h$),
('public.tick_lap_starts(boolean)', 5,
$h$    v_open_max := greatest(v_open_max, v_ms);
$h$,
$h$    v_open_max := greatest(v_open_max, v_ms);
    v_steps := v_steps || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(   -- 0269
                 'fleet', v_f, 'due', v_hold, 'plan_at', v_p0, 'plan_ms', round(v_pm, 1), 'plan', v_a,
                 'wait_at', v_w0, 'wait_ms', round(v_wm, 1), 'late', v_lt,
                 'open_at', v_t, 'quay_ms', public.beat_ms(v_q1 - v_t), 'open_ms', round(v_ms, 1), 'open', v_b)));
$h$),
('public.tick_lap_starts(boolean)', 6,
$h$            'due_left', (select count(*) from public.lap_starts_due())))$h$,
$h$            'due_left', (select count(*) from public.lap_starts_due()),
            'steps', v_steps))   -- 0269: each lap start's own times$h$),
-- ── tick_stats ──
('public.tick_stats(timestamptz)', 1,
$h$  v_w int := 0; v_g int := 0; v_c int := 0; v_cg int := 0; v_m int := 0; v_x int := 0;
$h$,
$h$  v_w int := 0; v_g int := 0; v_c int := 0; v_cg int := 0; v_m int := 0; v_x int := 0;
  -- 0269: each phase's ms (public.stats_runs.receipt.phases), and the return kept to write it down
  v_tp        timestamptz := clock_timestamp();
  v_ph        jsonb := '{}'::jsonb;
  v_day       jsonb;
  v_live      jsonb;
  v_ret       jsonb;
$h$),
('public.tick_stats(timestamptz)', 2,
$h$  v_ph_slot := (select max(h.slot) from public.price_history h where h.slot <= v_slot);
$h$,
$h$  v_ph_slot := (select max(h.slot) from public.price_history h where h.slot <= v_slot);
  v_ph := v_ph || jsonb_build_object('prev', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$),
('public.tick_stats(timestamptz)', 3,
$h$           group by x.gd) d;
$h$,
$h$           group by x.gd) d;
  v_ph := v_ph || jsonb_build_object('recent', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$),
('public.tick_stats(timestamptz)', 4,
$h$    from public.stats_sides(v_period) s;   -- 0232: the words table's sides, one rule
$h$,
$h$    from public.stats_sides(v_period) s;   -- 0232: the words table's sides, one rule
  v_ph := v_ph || jsonb_build_object('period', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$),
('public.tick_stats(timestamptz)', 5,
$h$  if v_w = 1 then update public.stats_world set watch = public.stats_watch(p_now) where slot = v_slot; end if;   -- 0229: the closed economy's watch figures (docs/CLOSED_ECONOMY.md §7)
$h$,
$h$  if v_w = 1 then update public.stats_world set watch = public.stats_watch(p_now) where slot = v_slot; end if;   -- 0229: the closed economy's watch figures (docs/CLOSED_ECONOMY.md §7)
  v_ph := v_ph || jsonb_build_object('world', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$),
('public.tick_stats(timestamptz)', 6,
$h$  get diagnostics v_g = row_count;
$h$,
$h$  get diagnostics v_g = row_count;
  v_ph := v_ph || jsonb_build_object('goods', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$),
('public.tick_stats(timestamptz)', 7,
$h$  get diagnostics v_c = row_count;
$h$,
$h$  get diagnostics v_c = row_count;
  v_ph := v_ph || jsonb_build_object('cities', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$),
('public.tick_stats(timestamptz)', 8,
$h$  get diagnostics v_cg = row_count;
$h$,
$h$  get diagnostics v_cg = row_count;
  v_ph := v_ph || jsonb_build_object('city_goods', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$),
('public.tick_stats(timestamptz)', 9,
$h$  get diagnostics v_m = row_count;
$h$,
$h$  get diagnostics v_m = row_count;
  v_ph := v_ph || jsonb_build_object('merchants', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$),
('public.tick_stats(timestamptz)', 10,
$h$  v_x := (v_fold->>'removed')::int;
$h$,
$h$  v_x := (v_fold->>'removed')::int;
  v_ph := v_ph || jsonb_build_object('fold', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0269
$h$),
('public.tick_stats(timestamptz)', 11,
$h$  return jsonb_build_object('slot', v_slot, 'at', p_now, 'since', v_prev_at,
                            'wrote', v_w + v_g + v_c + v_cg + v_m, 'world', v_w, 'goods', v_g, 'cities', v_c,
                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x, 'fold', v_fold,
                            'day', public.stats_fold_day(v_slot),     -- 0232: the 24 h the live reads add their minutes to
                            'live', public.stats_live_fold(p_now),   -- 0224: the live figures reconciled on every count
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
$h$,
$h$  -- 0269: the return's two last figures computed here, in the return's own order, to time them
  v_day := public.stats_fold_day(v_slot);
  v_ph := v_ph || jsonb_build_object('day', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();
  v_live := public.stats_live_fold(p_now);
  v_ph := v_ph || jsonb_build_object('live', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();
  v_ret := jsonb_build_object('slot', v_slot, 'at', p_now, 'since', v_prev_at,
                            'wrote', v_w + v_g + v_c + v_cg + v_m, 'world', v_w, 'goods', v_g, 'cities', v_c,
                            'city_goods', v_cg, 'merchants', v_m, 'compacted', v_x, 'fold', v_fold,
                            'day', v_day,     -- 0232: the 24 h the live reads add their minutes to
                            'live', v_live,   -- 0224: the live figures reconciled on every count
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  -- 0269: THE COUNT'S RECEIPT IS KEPT (public.stats_runs, 7 days): its phases, not only pg_cron's "1 row"
  insert into public.stats_runs (at, slot, started_at, ms, receipt)
  values (p_now, v_slot, v_t0, (v_ret->>'ms')::numeric, (v_ret - 'day' - 'live') || jsonb_build_object('phases', v_ph))
  on conflict (at) do update set slot = excluded.slot, started_at = excluded.started_at, ms = excluded.ms, receipt = excluded.receipt;
  delete from public.stats_runs where at < p_now - interval '7 days';
  return v_ret;
$h$);

do $$
declare
  d   record;
  h   record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0269 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0269 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0269(v_def, h.old);
      if v_n <> 1 then
        raise exception '0269 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 3. THE :07 BEATS' JOB ───────────────────────────────────────────────────────────────────────
do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice '0269: pg_cron is not installed here (PGlite) — byeharu-voyage:keep-beats was NOT scheduled. Call public.keep_reconcile_beats() by hand.';
    return;
  end if;
  perform cron.schedule('byeharu-voyage:keep-beats', '10 * * * *', 'select public.keep_reconcile_beats()');
  perform cron.alter_job(jobid, active := false) from cron.job where jobname = 'byeharu-voyage:keep-beats';
  raise notice '0269: pg_cron present — byeharu-voyage:keep-beats SCHEDULED BUT INACTIVE until wind_the_clock().';
end $cron$;

-- ── 4. THE PROBES' EYES ─────────────────────────────────────────────────────────────────────────
-- a merchant's rows after a run (uuids blanked: new rows carry new ones)
create function pg_temp.digest_0269(p_fleet uuid, p_route uuid, p_house uuid)
returns text
language sql
as $$
select regexp_replace(concat_ws(' # ',
  (select (to_jsonb(sr) - 'id')::text from public.standing_routes sr where sr.id = p_route),
  (select string_agg((to_jsonb(s) - 'id')::text, ',' order by s.ord) from public.standing_route_stops s where s.route_id = p_route),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(l) - 'id')::text as x from public.standing_route_lines l
     where l.route_id = p_route) a),
  (select string_agg((to_jsonb(x) - 'id')::text, ',' order by x.lap_no) from public.standing_route_laps x where x.route_id = p_route),
  (select string_agg((to_jsonb(o) - 'id')::text, ',' order by o.seq) from public.orders o where o.fleet_id = p_fleet),
  (select to_jsonb(f)::text from public.fleets f where f.id = p_fleet),
  (select string_agg(to_jsonb(s)::text, ',' order by s.id) from public.ships s where s.fleet_id = p_fleet),
  (select string_agg((to_jsonb(v) - 'id')::text, ',' order by v.departed_at) from public.voyages v where v.fleet_id = p_fleet),
  (select to_jsonb(p)::text from public.players p where p.id = p_house),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(l) - 'id')::text as x from public.ledger l
     where l.player_id = p_house and l.created_at >= now()) a),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(e) - 'id')::text as x from public.events e
     where e.player_id = p_house and e.created_at >= now()) a),
  (select md5(string_agg(to_jsonb(g)::text, ',' order by g.good_id)) from public.port_goods g
     where g.port_id = (select f.port_id from public.fleets f where f.id = p_fleet)),
  (select to_jsonb(t)::text from public.port_treasury t where t.port_id = (select f.port_id from public.fleets f where f.id = p_fleet))
  ), '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g')
$$;

-- ── 5. PROBE 1: THE TEND STEPS, OLD vs NEW (rolled back) ─────────────────────────────────────────
-- Up to 8 merchants of the roster (4 that the hour re-plans: unstarted or paused; 4 running), none the sweep asks in
-- turn. The old and new tick_reconcile are copied into pg_temp with the same five cuts: the name; the roster to these
-- merchants; the two company loops to none (this file does not touch them); the whole-world purse check to their
-- houses. The NEW copy also writes down EVERY step (the 100 ms bar at 0), so its record is checked step by step.
create temp table sample_0269 on commit drop as
with w as materialized (select q.route_id from public.npc_waiting_queue(now()) q where not q.overdue and q.route_id is not null),
     t as materialized (select r.route_id, r.fleet_id, r.player_id, r.k,
                               (sr.paused_reason is not null or sr.fleet_id is null) as replan
                          from public.npc_tend_roster() r join public.standing_routes sr on sr.id = r.route_id
                         where r.route_id not in (select w.route_id from w))
select * from (
  (select t.route_id, t.fleet_id, t.player_id, 'replan'::text as kind from t where t.replan order by t.k limit 4)
  union all
  (select t.route_id, t.fleet_id, t.player_id, 'running' from t where not t.replan order by t.k limit 4)) s;

create function pg_temp.reconcile_copy_0269(p_def text, p_name text, p_every boolean)
returns void
language plpgsql
as $$
declare
  v text := p_def;
  s record;
begin
  for s in select * from (values
    (1, 'CREATE OR REPLACE PROCEDURE public.tick_reconcile(', 'CREATE PROCEDURE pg_temp.' || p_name || '('),
    (2, 'for r in select * from public.npc_tend_roster() loop',
        'for r in select x.* from public.npc_tend_roster() x where x.route_id in (select s.route_id from pg_temp.sample_0269 s) loop'),
    (3, 'for h in select ir.player_id from public.npc_invest_roster() ir loop',
        'for h in select ir.player_id from public.npc_invest_roster() ir where false loop'),
    (4, 'for h in select gr.player_id from public.capital_gift_roster(v_now) gr loop',
        'for h in select gr.player_id from public.capital_gift_roster(v_now) gr where false loop'),
    (5, 'for r in select id from public.players loop',
        'for r in select id from public.players where id in (select s.player_id from pg_temp.sample_0269 s) loop')) t(n, a, b) loop
    if pg_temp.occurs_0269(v, s.a) <> 1 then
      raise exception '0269 self-assert FAIL: the probe''s cut % does not occur once in the % body', s.n, p_name;
    end if;
    v := replace(v, s.a, s.b);
  end loop;
  if p_every then
    if pg_temp.occurs_0269(v, 'interval ''100 milliseconds''') <> 2 then
      raise exception '0269 self-assert FAIL: the new tend loop does not carry its 100 ms bar twice';
    end if;
    v := replace(v, 'interval ''100 milliseconds''', 'interval ''0 milliseconds''');
  end if;
  execute v;
end $$;

select pg_temp.reconcile_copy_0269((select def from defs_before_0269 where fn = 'public.tick_reconcile(boolean)'), 'reconcile_old_0269', false);
select pg_temp.reconcile_copy_0269(replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', ''), 'reconcile_new_0269', true);

create function pg_temp.reconcile_case_0269(p_mode text)
returns jsonb
language plpgsql
as $$
declare
  v_rec jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb
     where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
    if p_mode = 'new' then
      call pg_temp.reconcile_new_0269(false);
    else
      call pg_temp.reconcile_old_0269(false);
    end if;
    v_rec := (select receipt from public.reconcile_runs where at = now());
    raise exception using errcode = 'ZY269', message = jsonb_build_object(
      'receipt', v_rec,
      'digest', (select string_agg(pg_temp.digest_0269(s.fleet_id, s.route_id, s.player_id), ' ## ' order by s.route_id)
                   from pg_temp.sample_0269 s))::text;
  exception when sqlstate 'ZY269' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 6. PROBE 2: THE LAP STARTS, OLD vs NEW (rolled back) ────────────────────────────────────────
-- 0266's case: one merchant resting (her route held, nothing queued); she alone is made due; the job's pass in the
-- caller's transaction (p_commit false); her rows and the minute's receipt.
create function pg_temp.lap_case_0269(p_mode text, p_fleet uuid)
returns jsonb
language plpgsql
as $$
declare
  v_route uuid := (select sr.id from public.standing_routes sr where sr.fleet_id = p_fleet);
  v_house uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_r     jsonb;
begin
  begin
    update public.world_config set value = 'true'::jsonb
     where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
    update public.standing_routes set hold_until = now() + interval '1 day'
     where hold_until is not null and hold_until <= now() and fleet_id <> p_fleet;
    update public.standing_routes set hold_until = now() - interval '1 second', paused_reason = null,
                                      updated_at = now() - interval '1 hour'
     where fleet_id = p_fleet;
    if p_mode = 'new' then
      call public.tick_lap_starts(false);
    else
      call pg_temp.lap_starts_old_0269(false);
    end if;
    v_r := (select receipt from public.lap_start_runs where at = now());
    raise exception using errcode = 'ZY269', message = jsonb_build_object(
      'receipt', v_r - array['plan_ms', 'plan_ms_max', 'open_ms', 'open_ms_max', 'wait_ms', 'wait_ms_max', 'est_open_ms', 'steps'],
      'steps', v_r->'steps',
      'digest', pg_temp.digest_0269(p_fleet, v_route, v_house))::text;
  exception when sqlstate 'ZY269' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 7. PROBE 3: THE COUNT, OLD vs NEW (rolled back), two hours ahead (a slot the cron cannot reach meanwhile) ──
create function pg_temp.stats_case_0269(p_mode text, p_now timestamptz)
returns jsonb
language plpgsql
as $$
declare
  v_slot bigint := public.drift_slot_of(p_now);
  v      jsonb;
begin
  begin
    if p_mode = 'new' then
      v := public.tick_stats(p_now);
    else
      v := pg_temp.stats_old_0269(p_now);
    end if;
    raise exception using errcode = 'ZY269', message = jsonb_build_object(
      -- the answer without its clock readings: every "ms", and live.at (stats_live_fold's clock_timestamp())
      'answer', regexp_replace((v #- '{live,at}')::text, '"ms": [0-9.eE+-]+', '"ms": 0', 'g'),
      'run', (select to_jsonb(s) from public.stats_runs s where s.at = p_now),
      'rows', md5(concat_ws(' # ',
                (select string_agg(to_jsonb(w)::text, ',') from public.stats_world w where w.slot = v_slot),
                (select md5(string_agg(to_jsonb(g)::text, ',' order by g.good_id)) from public.stats_good g where g.slot = v_slot),
                (select md5(string_agg(to_jsonb(c)::text, ',' order by c.port_id)) from public.stats_city c where c.slot = v_slot),
                (select md5(string_agg(to_jsonb(c)::text, ',' order by c.port_id, c.good_id)) from public.stats_city_good c where c.slot = v_slot),
                (select string_agg(to_jsonb(m)::text, ',') from public.stats_merchants m where m.slot = v_slot))),
      'n', (select count(*) from public.stats_city_good c where c.slot = v_slot))::text;
  exception when sqlstate 'ZY269' then
    return sqlerrm::jsonb;
  end;
end $$;

-- ── 8. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b    record;
  v_d    record;
  v_h    record;
  v_pp   record;
  v_def  text;
  v_new  text;
  v_old  text;
  r      record;
  e      jsonb;
  v_o    jsonb;
  v_n    jsonb;
  v_c    jsonb;
  v_holds jsonb;
  v_steps int := 0;
  v_tended int := 0;
  v_laps int := 0;
  v_opened int := 0;
  v_now  timestamptz := now() + interval '2 hours';
  v_so   jsonb;
  v_sn   jsonb;
  v_t    timestamptz;
  v_us_step numeric;
  v_us_note numeric;
  v_us_lap  numeric;
  v_acc  jsonb := '{}'::jsonb;
  v_ls   jsonb := '[]'::jsonb;
  v_was  text;
  v_x1 timestamptz; v_x2 timestamptz; v_x3 timestamptz;
  v_any  record;
begin
  select * into v_b from before_0269;

  -- (a) THE HUNKS reverse to the live pre-images; ACL / volatility / definer / config unmoved; the rest unmoved
  for v_d in select * from defs_before_0269 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0269 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0269(v_def, v_h.new) <> 1 then
        raise exception '0269 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0269 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0269 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn)) from kept_0269 k)
     <> v_b.kept_md5 then
    raise exception '0269 self-assert FAIL: a function the three bodies decide with, the quay, or one of its holders moved';
  end if;

  -- (b) RECORDING ONLY: what the hunks add takes no lock and writes no game table. Per hunk, outside comments:
  -- no row lock, no advisory lock, no LOCK; the same inserts / updates / deletes as the pre-image, except the
  -- count's own receipt (stats_runs: one insert, one retention delete); the quay asked for once more, by the lap
  -- open alone, before lap_start_open (which asks for it first, as before).
  for v_h in select * from hunks_0269 loop
    v_new := lower(regexp_replace(v_h.new, '--[^\n]*', '', 'g'));
    v_old := lower(regexp_replace(v_h.old, '--[^\n]*', '', 'g'));
    if pg_temp.occurs_0269(v_new, ' for update') + pg_temp.occurs_0269(v_new, ' for share') + pg_temp.occurs_0269(v_new, ' for no key update')
       + pg_temp.occurs_0269(v_new, ' for key share') + pg_temp.occurs_0269(v_new, 'advisory') + pg_temp.occurs_0269(v_new, 'lock table')
       <> pg_temp.occurs_0269(v_old, ' for update') + pg_temp.occurs_0269(v_old, ' for share') + pg_temp.occurs_0269(v_old, ' for no key update')
       + pg_temp.occurs_0269(v_old, ' for key share') + pg_temp.occurs_0269(v_old, 'advisory') + pg_temp.occurs_0269(v_old, 'lock table') then
      raise exception '0269 self-assert FAIL: hunk % of % takes a lock', v_h.n, v_h.fn;
    end if;
    if pg_temp.occurs_0269(v_new, 'insert into ') - pg_temp.occurs_0269(v_old, 'insert into ')
       <> (case when v_h.fn = 'public.tick_stats(timestamptz)' and v_h.n = 11 then 1 else 0 end)
       or pg_temp.occurs_0269(v_new, 'delete from ') - pg_temp.occurs_0269(v_old, 'delete from ')
       <> (case when v_h.fn = 'public.tick_stats(timestamptz)' and v_h.n = 11 then 1 else 0 end)
       or pg_temp.occurs_0269(v_new, 'update public.') <> pg_temp.occurs_0269(v_old, 'update public.')
       or pg_temp.occurs_0269(v_new, 'perform ') - pg_temp.occurs_0269(v_old, 'perform ')
          <> (case when v_h.fn = 'public.tick_lap_starts(boolean)' and v_h.n = 4 then 1 else 0 end)
       or pg_temp.occurs_0269(v_new, 'hold_the_quay') - pg_temp.occurs_0269(v_old, 'hold_the_quay')
          <> (case when v_h.fn = 'public.tick_lap_starts(boolean)' and v_h.n = 4 then 1 else 0 end) then
      raise exception '0269 self-assert FAIL: hunk % of % writes, performs or takes the quay beyond its record', v_h.n, v_h.fn;
    end if;
    if pg_temp.occurs_0269(v_new, 'insert into ') > pg_temp.occurs_0269(v_old, 'insert into ')
       and (pg_temp.occurs_0269(v_new, 'insert into public.stats_runs ') <> 1 or pg_temp.occurs_0269(v_new, 'delete from public.stats_runs ') <> 1) then
      raise exception '0269 self-assert FAIL: the count writes a table other than its own receipt';
    end if;
  end loop;
  -- the open step: the quay first (here, then again in lap_start_open), then her rows; lap_start_open unmoved (md5 above)
  v_def := regexp_replace(replace(pg_get_functiondef('public.tick_lap_starts(boolean)'::regprocedure), E'\r', ''), '--[^\n]*', '', 'g');
  if pg_temp.occurs_0269(v_def, 'perform public.hold_the_quay();') <> 1
     or position('perform public.hold_the_quay();' in v_def) > position('v_b := public.lap_start_open(v_f);' in v_def)
     or position('perform public.hold_the_quay();' in v_def) < position('v_a := public.lap_start_plan(v_f);' in v_def) then
    raise exception '0269 self-assert FAIL: the lap open does not ask for the quay right before lap_start_open, after the plan';
  end if;
  -- the tend steps: the quay, then the step, then her purse, then the commit, as 0267 left them
  v_def := regexp_replace(replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', ''), '--[^\n]*', '', 'g');
  if pg_temp.occurs_0269(v_def, 'if p_commit then perform public.hold_the_quay(); end if;') <> 3
     or pg_temp.occurs_0269(v_def, 'if p_commit then commit; end if;') <> 3
     or position('if p_commit then perform public.hold_the_quay(); end if;' in v_def) > position('public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k)' in v_def)
     or position('public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k)' in v_def) > position('perform public.assert_ledger_reconciles(r.player_id);' in v_def) then
    raise exception '0269 self-assert FAIL: the tend steps do not keep 0267''s order (the quay, her step, her purse, the commit)';
  end if;
  if (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and pg_get_functiondef(p.oid) like '%hold_the_quay()%')
     is distinct from (select string_agg(x, ',' order by x) from unnest(string_to_array(v_b.quay_takers, ',') || array['tick_lap_starts(boolean)']) x) then
    raise exception '0269 self-assert FAIL: the functions that take the quay are not the old ones and the lap-start job';
  end if;
  -- the note reads nothing and writes nothing
  v_def := lower(regexp_replace(pg_get_functiondef('public.quay_hold_note(jsonb,uuid,uuid,uuid,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,jsonb)'::regprocedure), '--[^\n]*', '', 'g'));
  if position(' from public.' in v_def) > 0 or position('insert ' in v_def) > 0 or position('update ' in v_def) > 0 or position('delete ' in v_def) > 0 then
    raise exception '0269 self-assert FAIL: quay_hold_note reads or writes a table';
  end if;

  -- (c) POSTURE: everything new is server-only; the beats' job every hour at :10
  if has_function_privilege('anon', 'public.keep_reconcile_beats(timestamptz)', 'execute') or has_function_privilege('authenticated', 'public.keep_reconcile_beats(timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.quay_hold_note(jsonb,uuid,uuid,uuid,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.quay_hold_note(jsonb,uuid,uuid,uuid,text,timestamptz,timestamptz,timestamptz,timestamptz,timestamptz,jsonb)', 'execute')
     or has_table_privilege('anon', 'public.stats_runs', 'select') or has_table_privilege('authenticated', 'public.stats_runs', 'select')
     or has_table_privilege('anon', 'public.arrivals_beats_kept', 'select') or has_table_privilege('authenticated', 'public.arrivals_beats_kept', 'select') then
    raise exception '0269 self-assert FAIL: a client role can reach a new receipt';
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if (select count(*) from cron.job where jobname = 'byeharu-voyage:keep-beats' and schedule = '10 * * * *'
                                       and command = 'select public.keep_reconcile_beats()') <> 1 then
      raise exception '0269 self-assert FAIL: byeharu-voyage:keep-beats is not scheduled at :10';
    end if;
  end if;

  -- (d) PROBE 1, THE TEND STEPS: old, new, old (the control); the same rows and the same receipt; the new one's
  -- record has one entry a step (its bar at 0), each in order: asked <= granted <= done, wait + held = the whole
  v_o := pg_temp.reconcile_case_0269('old');
  v_n := pg_temp.reconcile_case_0269('new');
  v_c := pg_temp.reconcile_case_0269('old');
  if v_o->'digest' is distinct from v_c->'digest' or (v_o->'receipt'->'merchant_upkeep') is distinct from (v_c->'receipt'->'merchant_upkeep') then
    raise exception '0269 self-assert FAIL: the tend CONTROL differs (old against old): % / %', left(v_o::text, 1500), left(v_c::text, 1500);
  end if;
  if v_o->'digest' is distinct from v_n->'digest' then
    raise exception '0269 self-assert FAIL: the tend steps left other rows — old % / new %', left(v_o->>'digest', 1500), left(v_n->>'digest', 1500);
  end if;
  if ((v_o->'receipt') - array['ms', 'quay']) is distinct from ((v_n->'receipt') - array['ms', 'quay', 'tend_holds'])
     or (v_o->'receipt'->'quay'->'tend'->'n') is distinct from (v_n->'receipt'->'quay'->'tend'->'n') then
    raise exception '0269 self-assert FAIL: the tend receipts differ — old % / new %', left((v_o->'receipt')::text, 1500), left((v_n->'receipt')::text, 1500);
  end if;
  v_holds := v_n->'receipt'->'tend_holds';
  v_tended := coalesce((v_n->'receipt'->'quay'->'tend'->>'n')::int, 0);
  if coalesce((v_holds->>'n')::int, 0) <> v_tended or jsonb_array_length(coalesce(v_holds->'kept', '[]'::jsonb)) <> v_tended
     or v_tended <> (select count(*) from pg_temp.sample_0269) then
    raise exception '0269 self-assert FAIL: the tend record has % entries for % step(s) of % sampled: %', v_holds->>'n', v_tended,
      (select count(*) from pg_temp.sample_0269), left(coalesce(v_holds::text, 'null'), 1500);
  end if;
  for e in select x from jsonb_array_elements(coalesce(v_holds->'kept', '[]'::jsonb)) x loop
    if not exists (select 1 from pg_temp.sample_0269 s where s.route_id = (e->>'route')::uuid and s.fleet_id = (e->>'fleet')::uuid
                                                         and s.player_id = (e->>'house')::uuid)
       or (e->>'asked')::timestamptz > (e->>'got')::timestamptz or (e->>'got')::timestamptz > (e->>'done')::timestamptz
       or e->'did' is null or e->>'was' is null or e->'step_ms' is null or e->'check_ms' is null or e->'commit_ms' is null
       or abs((e->>'step_ms')::numeric + (e->>'check_ms')::numeric + (e->>'commit_ms')::numeric - (e->>'held_ms')::numeric) > 0.3 then
      raise exception '0269 self-assert FAIL: a tend record entry is not whole or not in order: %', e;
    end if;
    v_steps := v_steps + 1;
  end loop;

  -- (e) PROBE 2, THE LAP STARTS: up to 3 resting merchants (the soonest due), each made due alone; old, new, old; the same rows and receipt; the new
  -- receipt's steps: one lap start, hers, its parts in order
  for r in select sr.fleet_id as fid
             from public.standing_routes sr
             join public.players p on p.id = sr.player_id and p.is_npc
             join public.fleets f on f.id = sr.fleet_id and f.status = 'DOCKED'
            where sr.paused_reason is null and sr.hold_until is not null   -- resting: the job will start her next lap
              and not exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'failed'))
            order by sr.hold_until, sr.id limit 3 loop
    v_o := pg_temp.lap_case_0269('old', r.fid);
    v_n := pg_temp.lap_case_0269('new', r.fid);
    v_c := pg_temp.lap_case_0269('old', r.fid);
    if v_o is distinct from v_c then
      raise exception '0269 self-assert FAIL: the lap-start CONTROL differs (old against old) for fleet % — % / %', r.fid, left(v_o::text, 1500), left(v_c::text, 1500);
    end if;
    if v_o->'digest' is distinct from v_n->'digest' or v_o->'receipt' is distinct from v_n->'receipt' then
      raise exception '0269 self-assert FAIL: the lap start differs for fleet % — old % / new %', r.fid, left(v_o::text, 1500), left(v_n::text, 1500);
    end if;
    e := v_n->'steps'->0;
    if jsonb_array_length(coalesce(v_n->'steps', '[]'::jsonb)) <> 1 or (e->>'fleet')::uuid <> r.fid or e->'due' is null
       or e->'plan_at' is null or e->'plan_ms' is null or e->'plan' is null
       or ((e->>'plan')::int = 1) is distinct from (e ? 'open')
       or ((v_n->'receipt'->>'started')::int = 1) is distinct from (coalesce((e->>'open')::int, 0) = 1)
       or (e ? 'open' and (e->'quay_ms' is null or e->'open_ms' is null or (e->>'open_at')::timestamptz < (e->>'plan_at')::timestamptz
                           or (e->>'quay_ms')::numeric > (e->>'open_ms')::numeric + 0.1)) then
      raise exception '0269 self-assert FAIL: the lap start''s own record for fleet % is not whole: % (receipt %)', r.fid, v_n->'steps', v_n->'receipt';
    end if;
    v_laps := v_laps + 1;
    if (v_n->'receipt'->>'started')::int = 1 then v_opened := v_opened + 1; end if;
  end loop;

  -- (f) PROBE 3, THE COUNT: old and new two hours ahead, the same rows and the same answer; the new one kept its receipt
  v_so := pg_temp.stats_case_0269('old', v_now);
  v_sn := pg_temp.stats_case_0269('new', v_now);
  if v_so->'rows' is distinct from v_sn->'rows' or v_so->'answer' is distinct from v_sn->'answer' then
    raise exception '0269 self-assert FAIL: the count differs — old % / new %', left(v_so::text, 1500), left(v_sn::text, 1500);
  end if;
  if v_so->'run' <> 'null'::jsonb or v_sn->'run' is null or v_sn->'run' = 'null'::jsonb
     or not ((v_sn->'run'->'receipt'->'phases') ?& array['prev', 'recent', 'period', 'world', 'goods', 'cities', 'city_goods',
                                                          'merchants', 'fold', 'day', 'live'])
     or (select count(*) from jsonb_object_keys(v_sn->'run'->'receipt'->'phases')) <> 11
     or (v_sn->'run'->'receipt') ? 'day' or (v_sn->'run'->'receipt') ? 'live'
     or (v_sn->'run'->>'slot')::bigint <> public.drift_slot_of(v_now) then
    raise exception '0269 self-assert FAIL: the new count did not keep its whole receipt: %', left(coalesce(v_sn->>'run', 'null'), 1500);
  end if;
  if exists (select 1 from public.stats_world where at > now() + interval '1 hour') or exists (select 1 from public.stats_runs) then
    raise exception '0269 self-assert FAIL: a probe count survived its rollback';
  end if;

  -- (g) PROBE 4, THE :07 BEATS: an hour two hours ahead (no real beat can be in it); five beats planted in the ring
  -- (:06:00, :06:30, :07:15, :08:59, :09:00); kept: the three inside :06:30-:09:00, once; a kept row 8 days old goes
  begin
    v_t := date_trunc('hour', now()) + interval '2 hours';
    insert into public.arrivals_beats (slot, at, ms, fleets, days, asked, error, splits)
    select (floor(extract(epoch from v_t + x.o)))::bigint % 3600, v_t + x.o, 1, 0, 0, 0, null, jsonb_build_object('probe', 269)
      from (values (interval '6 minutes'), (interval '6 minutes 30 seconds'), (interval '7 minutes 15 seconds'),
                   (interval '8 minutes 59 seconds'), (interval '9 minutes')) x(o)
    on conflict (slot) do update set at = excluded.at, ms = excluded.ms, fleets = excluded.fleets, days = excluded.days,
                                     asked = excluded.asked, error = excluded.error, splits = excluded.splits;
    insert into public.arrivals_beats_kept (at, slot, ms, splits) values (v_t - interval '8 days', 0, 1, jsonb_build_object('probe', 269));
    e := public.keep_reconcile_beats(v_t + interval '10 minutes');
    if (select count(*) from public.arrivals_beats_kept where splits = jsonb_build_object('probe', 269) and at >= v_t) <> 3
       or exists (select 1 from public.arrivals_beats_kept where at = v_t - interval '8 days')
       or exists (select 1 from public.arrivals_beats_kept where at in (v_t + interval '6 minutes', v_t + interval '9 minutes'))
       or (e->>'kept')::int <> 3 then
      raise exception '0269 self-assert FAIL: the :07 beats were not kept as asked: % (kept %)', e,
        (select string_agg(at::text, ', ' order by at) from public.arrivals_beats_kept where splits = jsonb_build_object('probe', 269));
    end if;
    e := public.keep_reconcile_beats(v_t + interval '10 minutes');
    if (e->>'kept')::int <> 0 then
      raise exception '0269 self-assert FAIL: the :07 beats were kept twice: %', e;
    end if;
    raise exception using errcode = 'ZY269', message = 'rolled back';
  exception when sqlstate 'ZY269' then
    null;
  end;
  if exists (select 1 from public.arrivals_beats where splits = jsonb_build_object('probe', 269))
     or exists (select 1 from public.arrivals_beats_kept) then
    raise exception '0269 self-assert FAIL: a planted beat survived its rollback';
  end if;

  -- (h) THE OVERHEAD, timed here: what every tend step now adds (the plain read of her two rows and four clock
  -- readings), what a written-down step adds (the note), and what every lap start adds (its entry)
  select s.route_id, s.fleet_id into v_any from pg_temp.sample_0269 s limit 1;
  if v_any.route_id is null then
    select sr.id as route_id, sr.fleet_id into v_any from public.standing_routes sr limit 1;
  end if;
  v_t := clock_timestamp();
  for i in 1..500 loop
    v_was := (select concat_ws('/', f.status, coalesce(sr.paused_reason, case when sr.fleet_id is null then 'unassigned' else 'running' end))
                from public.standing_routes sr left join public.fleets f on f.id = v_any.fleet_id where sr.id = v_any.route_id);
    v_x1 := clock_timestamp(); v_x2 := clock_timestamp(); v_x3 := clock_timestamp();
    if v_x3 - v_x1 > interval '100 milliseconds' then v_was := null; end if;
  end loop;
  v_us_step := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1e6 / 500, 1);
  v_t := clock_timestamp();
  for i in 1..500 loop
    v_acc := public.quay_hold_note(v_acc, v_any.fleet_id, v_any.route_id, v_any.fleet_id, v_was, v_x1, v_x2, v_x3, v_x3, clock_timestamp(),
                                   jsonb_build_object('started', 1, 'waiting', 0, 'notes', '[]'::jsonb));
  end loop;
  v_us_note := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1e6 / 500, 1);
  if (v_acc->>'n')::int <> 500 or jsonb_array_length(v_acc->'kept') <> 300 then
    raise exception '0269 self-assert FAIL: the tend record is not bounded at 300 kept (n %, kept %)', v_acc->>'n', jsonb_array_length(v_acc->'kept');
  end if;
  v_t := clock_timestamp();
  for i in 1..60 loop
    v_ls := v_ls || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
              'fleet', v_any.fleet_id, 'due', v_x1, 'plan_at', v_x1, 'plan_ms', 1.0, 'plan', 1, 'wait_at', v_x2, 'wait_ms', 1.0, 'late', false,
              'open_at', v_x3, 'quay_ms', public.beat_ms(v_x3 - v_x2), 'open_ms', 1.0, 'open', 1)));
  end loop;
  v_us_lap := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1e6 / 60, 1);

  -- (i) POSTURE, the walls
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points then
    raise exception '0269 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0269 self-assert FAIL: a wall moved';
  end if;

  raise notice '0269 self-assert ok: THE QUAY WRITES DOWN ITS LONG HOLDS (recording only). tick_reconcile (3 hunks: receipt.tend_holds, every tend step over 100 ms held or waited: who, what she was, asked / granted / committed, step / purse check / commit ms, what it did), tick_lap_starts (6 hunks: receipt.steps, every lap start''s plan / gap wait / open with its own quay wait) and tick_stats (11 hunks: public.stats_runs, each phase''s ms) reverse to their pre-images, ACL / volatility / definer / config unmoved; what they decide with, the quay and its holders unmoved (md5); no hunk locks or writes a game table; the quay taken by the old holders and the lap-start job (its open step, right before lap_start_open, which asks first as before). byeharu-voyage:keep-beats (:10) keeps :06:30-:09:00 of the ring 7 days. PROBES (rolled back, same state): tend old / new / old on % merchant(s): same rows, same receipt, % step(s) written down whole; lap starts old / new / old on % merchant(s) (% opened): same rows, same receipt, one whole step each; the count old / new two hours ahead: same rows (% city-goods), same answer, its receipt kept with 11 phases; the :07 beats: 3 of 5 kept, once, 8-day row gone. OVERHEAD: % µs a tend step always, % µs a written-down step, % µs a lap start. Registry unchanged; walls 0.',
    (select count(*) from pg_temp.sample_0269), v_steps, v_laps, v_opened, v_sn->>'n', v_us_step, v_us_note, v_us_lap;
end $$;
