-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0266 — A LAP STARTS IN ITS OWN JOB  (the merchant's re-plan leaves the per-second arrivals beat)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, 2026-10-28 ───────────────────────────────────────────────────────────────────────
-- "Move the merchant lap-start re-plan OUT of the per-second arrivals beat into its own job. Merchants keep
-- making the same decisions; a merchant may set sail a few seconds after her rest ends instead of on that
-- exact beat. Player-facing beats must stay fast."
--
-- ── THE ROOT, MEASURED ON PROD (docs/dev-log/2026-10-28-beat-splits.md) ─────────────────────────
-- The beat's `held` loop (0092: a route held for pacing wakes; for a merchant, her rest at home ends and
-- cmd.run_standing_route re-plans her loop through public.npc_plan, ~11 legs, ~150 quotes, up to 16
-- candidate loops) costs ~450-600 ms a lap start and is 44-47 % of beat time; the beats over 1 s are the
-- beats with one or more lap starts (p95 1.54 s after 0264).
-- Prod, read-only, head 0265, the 3 hours to 03:47 UTC: 4,227 lap starts, ALL merchants, ALL after her rest
-- (none at an arrival), 23.5 a minute (p50 24, p95 35, max 71 a minute). Every one is found by the held loop:
-- standing_routes.hold_until <= now (index standing_routes_hold_due), paused_reason null, fleet DOCKED.
-- Lag from rest end to lap start (started_at - (last close + rest)): p50 0.67 s, p95 2.77 s.
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- (1) THE BEAT NO LONGER WAKES A HELD ROUTE. public.tick_arrivals loses the held loop (1 hunk; its `held`
--     split goes with it). Nothing else in the beat moves. "Due" is the state that already marked it:
--     hold_until <= now. ONE authority for it: public.lap_starts_due() (the old loop's predicate, verbatim).
-- (2) THE JOB. public.tick_lap_starts() (pg_cron byeharu-voyage:lap-starts, every minute, CALL; 0248's one warm
--     session a minute): the due routes oldest first (hold_until), each lap start in two transactions of its own:
--     (A) public.lap_start_plan(fleet) — NOT under the quay. Her fleet and route (SKIP LOCKED), then her house
--         (0265's per-house lock: her players row, FOR NO KEY UPDATE SKIP LOCKED), re-checked due under them.
--         For a merchant with nothing queued, the old path's first statement and then cmd.run_standing_route
--         itself, with the transaction-local flag byeharu.lap_plan_only: the route runs every guard and the
--         lap-start re-plan exactly as before and stops (returns -1) BEFORE it opens the lap or writes an
--         order. Everything it wrote is her own: route, stops, lines, preset, a closed lap, a pause, an event.
--         It takes no harbour, no quay stock, no purse: no lock another writer waits on in the other order.
--         Her hold is put back, so she is still due. If the guards or the plan ended her turn (laid up,
--         paused, held again) that is final, as it was.
--     (B) public.lap_start_open(fleet) — UNDER THE QUAY (public.hold_the_quay, as the beat and the upkeep
--         steps), placed in the gap after the second's beat has committed: the quay, then fleet, route, house
--         (SKIP LOCKED), re-checked due; then THE OLD WAKE VERBATIM: hold_until := null, cmd.advance. The
--         route sees her lines written under a minute ago (0114's rule: "lines written in the last minute are
--         today's already and are not planned twice"), so she is not re-planned: the lap opens, her stop's
--         lines are written and her BUYs and SAIL run, as before. A player's route has no plan: (B) alone.
--     The two never double a lap: (B) re-checks due (hold_until <= now) under the fleet and route locks
--     and the quay, and the wake clears hold_until in the transaction that opens the lap.
--     The job stops at its minute's end, or at once when byeharu-voyage:lap-starts is switched off
--     (public.unwind_the_clock), as 0248's beat does. One receipt a minute: public.lap_start_runs.
--     p_commit = false: one pass over what is due now in the caller's transaction (no waits, the arrivals
--     budget as the beat's loop had) — a proof, and the browser's own clock (src/lib/rpc/localBackend.ts).
-- (3) cmd.run_standing_route: 2 hunks, each only `if the flag is on then return -1`: before the off-route
--     tail is enqueued, and before the lap row is inserted. The flag is unset everywhere else: inert.
--
-- ── WHAT CHANGES FOR A PLAYER ───────────────────────────────────────────────────────────────────
-- A merchant whose rest ends sets sail a moment later than the beat would have started her (the plan, ~0.5 s,
-- then the next gap). Her re-plan reads the prices of that moment, and her BUYs the prices of the gap after it
-- (about a second later). Same planner, same rules, same knobs.
--
-- ── THE PROOF (self-assert, every probe rolled back) ───────────────────────────────────────────
-- The hunks reverse to the live pre-images. cmd.advance, npc_plan, close_lap, credit, the quay and the beat
-- procedure unmoved (md5). OLD vs NEW for up to 4 merchants resting at her home stop, each made due alone, from
-- the same state at the same instant: the old held loop (a pg_temp copy built from this file's pre-image) against
-- the new job's pass, then the old again (the control): the same digest of her route, stops, lines, laps,
-- orders, fleet, ships, voyages, purse, this transaction's ledger rows and events, her port's market and
-- treasury. TWICE: the job's pass run twice, and A, A, B, B interleaved by hand: the same digest, one lap.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- Forward slice: the held loop's pre-image is verbatim below (hunks_0266). Switch off byeharu-voyage:lap-starts
-- first, then put the loop back in tick_arrivals; the flag hunks are inert left in place.
--
-- VERSION: 0266 (prod head 0265).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.tick_compact(boolean,boolean)') is null
     or to_regprocedure('public.hold_the_quay()') is null
     or to_regclass('public.arrivals_beats') is null then
    raise exception '0266 refuses: 0265 is not in this world';
  end if;
  if to_regclass('public.lap_start_runs') is not null or to_regprocedure('public.tick_lap_starts(boolean)') is not null then
    raise exception '0266 refuses: public.lap_start_runs already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0266(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table defs_before_0266 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_arrivals(timestamp with time zone)'),
               ('cmd.run_standing_route(uuid,timestamp with time zone)')) f(fn);

create temp table before_0266 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p
         where p.oid in ('cmd.advance(uuid,timestamptz)'::regprocedure, 'public.npc_plan(timestamptz,uuid)'::regprocedure,
                         'cmd.standing_route_close_lap(uuid,timestamptz)'::regprocedure,
                         'public.credit(uuid,text,bigint,uuid)'::regprocedure, 'public.hold_the_quay()'::regprocedure,
                         'public.tick_arrivals_each_second(integer)'::regprocedure,
                         'public.tick_compact(boolean,boolean)'::regprocedure)) as kept_md5;

-- ── 1. THE HUNKS ────────────────────────────────────────────────────────────────────────────────
create temp table hunks_0266 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0266 (fn, n, old, new) values
('public.tick_arrivals(timestamp with time zone)', 1,
$h$  -- 0092: A ROUTE HELD FOR PACING WAKES HERE — the same shape as the yard release above, on
  -- the same job. No new job, no new schedule (docs/TRADE_ROUTES.md §4.3).
  for r in select f.id from public.fleets f
             join public.standing_routes sr on sr.fleet_id = f.id
            where public.standing_routes_on()
              and sr.paused_reason is null and sr.hold_until is not null and sr.hold_until <= p_now
              and f.status = 'DOCKED'
              for update of f skip locked loop
    exit when clock_timestamp() >= v_t0 + v_budget;   -- 0125
    update public.standing_routes set hold_until = null where fleet_id = r.id;
    perform cmd.advance(r.id, p_now);
    v_fleets := v_fleets + 1;
  end loop;
  v_sp := v_sp || jsonb_build_object('held', public.beat_ms(clock_timestamp() - v_tp)); v_tp := clock_timestamp();   -- 0261
$h$,
$h$  -- 0266: A ROUTE HELD FOR PACING (0092) NO LONGER WAKES IN THIS BEAT. A merchant's lap start re-plans her loop
  -- (~0.5 s on prod: 44 % of beat time), so it runs in its own job, public.tick_lap_starts (pg_cron
  -- byeharu-voyage:lap-starts; due = public.lap_starts_due()), a moment after her rest ends.
$h$),
('cmd.run_standing_route(uuid,timestamp with time zone)', 1,
$h$        -- 0096: through THE ONE TAIL (cmd.standing_route_tail), so a crew-short fleet hires first.
        v_lines := cmd.standing_route_tail(sr.id, prv.ord, p_fleet);$h$,
$h$        -- 0096: through THE ONE TAIL (cmd.standing_route_tail), so a crew-short fleet hires first.
        -- 0266: the lap-start job's plan step (public.lap_start_plan) stops here: its open step writes this.
        if current_setting('byeharu.lap_plan_only', true) = 'on' then return -1; end if;
        v_lines := cmd.standing_route_tail(sr.id, prv.ord, p_fleet);$h$),
('cmd.run_standing_route(uuid,timestamp with time zone)', 2,
$h$    end if;
    if sr.lap_id is null then
      insert into public.standing_route_laps (route_id, lap_no, started_at)$h$,
$h$    end if;
    -- 0266: THE LAP-START JOB'S PLAN STEP STOPS HERE (public.lap_start_plan, flag set in its transaction only):
    -- every guard and the re-plan above have run; the lap, its orders and her BUYs / SAIL are its open step's,
    -- under the quay (public.lap_start_open), which finds these lines under a minute old and does not re-plan.
    if current_setting('byeharu.lap_plan_only', true) = 'on' then return -1; end if;
    if sr.lap_id is null then
      insert into public.standing_route_laps (route_id, lap_no, started_at)$h$);

-- THE OLD HELD LOOP, kept as a temp copy for the probe: built from hunk 1's pre-image, verbatim
do $$
declare
  v_old text := (select old from hunks_0266 where fn = 'public.tick_arrivals(timestamp with time zone)' and n = 1);
begin
  execute format($f$
create function pg_temp.held_old_0266(p_now timestamptz)
returns int
language plpgsql
as $b$
declare
  r         record;
  v_fleets  int := 0;
  v_t0      timestamptz := clock_timestamp();
  v_budget  interval := make_interval(secs => public.wc_int('arrivals_tick_budget_ms') / 1000.0);
  v_tp      timestamptz := clock_timestamp();
  v_sp      jsonb := '{}'::jsonb;
begin
%s
  return v_fleets;
end $b$;$f$, v_old);
end $$;

do $$
declare
  d   record;
  h   record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0266 loop
    v_def := d.def;
    for h in select * from hunks_0266 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0266(v_def, h.old);
      if v_n <> 1 then
        raise exception '0266 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 2. DUE, THE RECEIPT, THE TWO STEPS ──────────────────────────────────────────────────────────
create function public.lap_starts_due()
returns table (fleet_id uuid, route_id uuid, player_id uuid, hold_until timestamptz)
language sql
stable
set search_path = public, pg_temp
as $$
  -- 0266: THE routes whose hold has ended (0092's held loop's predicate, verbatim, as of now()): THE answer to
  -- "is her lap start due". Read by public.tick_lap_starts and its two steps.
  select f.id, sr.id, sr.player_id, sr.hold_until
    from public.fleets f
    join public.standing_routes sr on sr.fleet_id = f.id
   where public.standing_routes_on()
     and sr.paused_reason is null and sr.hold_until is not null and sr.hold_until <= now()
     and f.status = 'DOCKED'
$$;
comment on function public.lap_starts_due() is
  '0266: the routes whose hold has ended (hold_until <= now(), not paused, fleet DOCKED, routes on): THE due set of the lap-start job (public.tick_lap_starts). Server-only.';
revoke all on function public.lap_starts_due() from public, anon, authenticated;

create table public.lap_start_runs (
  slot    int         primary key check (slot between 0 and 1439),
  at      timestamptz not null,
  ms      numeric     not null check (ms >= 0),
  receipt jsonb       not null
);
comment on table public.lap_start_runs is
  '0266: one row a minute of the day (slot = floor(epoch / 60) mod 1440), overwritten a day later: what public.tick_lap_starts did in that minute (laps started, settled in the plan step, busy, failed, the lag from rest end to lap start, the plan / open / wait times). One writer: public.tick_lap_starts. Server-only.';
alter table public.lap_start_runs enable row level security;
revoke all on table public.lap_start_runs from public, anon, authenticated;

create function public.lap_start_plan(p_fleet uuid)
returns int
language plpgsql
set search_path = public, pg_temp
as $$
-- 0266: THE LAP-START JOB'S PLAN STEP (not under the quay). 1 = her lap is to be opened next (public.lap_start_open);
-- 0 = nothing to open (not due, or the guards / the plan ended her turn: final, as in the old path); -1 = busy
-- (her fleet, route or house is locked: SKIP LOCKED, never waits; try again). For a merchant with nothing queued
-- (cmd.advance would call the route at once): the old wake's first statement, then cmd.run_standing_route with
-- byeharu.lap_plan_only, which runs every guard and the re-plan and stops before the lap opens; her hold is put
-- back so she stays due. A player's route, or a queue with an order in it: nothing here, the open step does all.
declare
  d  record;
  v  int;
begin
  perform 1 from public.fleets f join public.standing_routes sr on sr.fleet_id = f.id
   where f.id = p_fleet for update of f, sr skip locked;
  if not found then return -1; end if;
  select x.* into d from public.lap_starts_due() x where x.fleet_id = p_fleet;   -- re-checked under the lock
  if d.fleet_id is null then return 0; end if;
  if not exists (select 1 from public.players p where p.id = d.player_id and p.is_npc)
     or exists (select 1 from public.orders o
                 where o.fleet_id = p_fleet
                   and (o.status = 'pending' or (o.status = 'failed' and o.route_lap_id is not null))) then
    return 1;
  end if;
  perform 1 from public.players p where p.id = d.player_id for no key update skip locked;   -- 0265's house lock
  if not found then return -1; end if;
  perform set_config('byeharu.lap_plan_only', 'on', true);
  update public.standing_routes set hold_until = null where fleet_id = p_fleet;   -- the old wake's first statement
  v := cmd.run_standing_route(p_fleet, now());
  perform set_config('byeharu.lap_plan_only', '', true);
  if v = -1 then
    update public.standing_routes set hold_until = d.hold_until where fleet_id = p_fleet;
    return 1;
  end if;
  if v <> 0 then
    raise exception '0266: the plan step of fleet % wrote % order(s): the route did not stop before the lap', p_fleet, v;
  end if;
  return 0;
end $$;
comment on function public.lap_start_plan(uuid) is
  '0266: the lap-start job''s plan step, outside the quay: her fleet, route, house (SKIP LOCKED), re-checked due; cmd.run_standing_route under byeharu.lap_plan_only (every guard and the re-plan, stopped before the lap opens). 1 = open her next, 0 = nothing to open, -1 = busy. Server-only.';
revoke all on function public.lap_start_plan(uuid) from public, anon, authenticated;

create function public.lap_start_open(p_fleet uuid)
returns int
language plpgsql
set search_path = public, pg_temp
as $$
-- 0266: THE LAP-START JOB'S OPEN STEP, under the quay. 1 = the wake ran; 0 = not due any more (another run
-- opened her, or she changed); -1 = busy (SKIP LOCKED). The quay first, then fleet, route, house; due re-checked
-- under them; then 0092's held wake, verbatim (it was the beat's held loop until 0266).
declare
  d  record;
begin
  perform public.hold_the_quay();
  perform 1 from public.fleets f join public.standing_routes sr on sr.fleet_id = f.id
   where f.id = p_fleet for update of f, sr skip locked;
  if not found then return -1; end if;
  select x.* into d from public.lap_starts_due() x where x.fleet_id = p_fleet;   -- re-checked under the lock
  if d.fleet_id is null then return 0; end if;
  perform 1 from public.players p where p.id = d.player_id for no key update skip locked;   -- 0265's house lock
  if not found then return -1; end if;
  update public.standing_routes set hold_until = null where fleet_id = p_fleet;
  perform cmd.advance(p_fleet, now());
  return 1;
end $$;
comment on function public.lap_start_open(uuid) is
  '0266: the lap-start job''s open step, under the quay: fleet, route, house (SKIP LOCKED), re-checked due, then the held wake (hold_until := null; cmd.advance). 1 = woken, 0 = not due, -1 = busy. Server-only.';
revoke all on function public.lap_start_open(uuid) from public, anon, authenticated;

-- ── 3. THE JOB ──────────────────────────────────────────────────────────────────────────────────
create procedure public.tick_lap_starts(p_commit boolean default true)
language plpgsql
as $$
-- 0266: THE lap-start job (pg_cron byeharu-voyage:lap-starts, every minute, CALL). One warm session a minute
-- (0248): the due routes (public.lap_starts_due) oldest first, each lap start its own two transactions — the plan
-- step (public.lap_start_plan, outside the quay) and the open step (public.lap_start_open, under the quay), the
-- open step placed in the gap after the second's beat has committed (public.arrivals_beats) when the gap holds it,
-- else the next gap (at most c_wait). A busy route is tried again when nothing else is due. Stops at c_end of its
-- minute, or at once when its job is switched off (public.clock_jobs). p_commit = false: one pass over what is due
-- now, in the caller's transaction, no waits, inside the arrivals budget (a proof; the browser's clock).
-- No SECURITY DEFINER, no SET: a procedure that commits may carry neither; it runs as the job's owner.
declare
  c_end    constant interval := interval '57 seconds';   -- no plan step starts after this point of its minute
  c_wait   constant interval := interval '1500 milliseconds';   -- the longest the open step waits for a gap
  c_margin constant numeric := 60;                        -- ms left before the next beat
  v_t0     timestamptz := clock_timestamp();
  v_now0   timestamptz := now();
  v_end    timestamptz := date_trunc('minute', clock_timestamp()) + c_end;
  v_by     timestamptz;
  v_cron   boolean := exists (select 1 from pg_extension where extname = 'pg_cron');
  v_skip   uuid[] := '{}';
  v_f      uuid;
  v_hold   timestamptz;
  v_a      int;
  v_b      int;
  v_t      timestamptz;
  v_tw     timestamptz;
  v_ms     numeric;
  v_est    numeric := 250;   -- ms an open step takes (measured as it runs)
  v_lag    numeric[] := '{}';
  v_started int := 0;
  v_settled int := 0;
  v_gone   int := 0;
  v_busy   int := 0;
  v_failed int := 0;
  v_note   text;
  v_plan_ms numeric := 0;
  v_plan_max numeric := 0;
  v_open_ms numeric := 0;
  v_open_max numeric := 0;
  v_wait_ms numeric := 0;
  v_wait_max numeric := 0;
  v_late   int := 0;
begin
  if not p_commit then
    v_by := clock_timestamp() + make_interval(secs => public.wc_int('arrivals_tick_budget_ms') / 1000.0);
  end if;
  loop
    if p_commit then
      exit when clock_timestamp() >= v_end;
      exit when v_cron and not exists (select 1 from public.clock_jobs() j
                                        where j.jobname = 'byeharu-voyage:lap-starts' and j.active);
    else
      exit when clock_timestamp() >= v_by;
    end if;
    v_f := null;
    select d.fleet_id, d.hold_until into v_f, v_hold
      from public.lap_starts_due() d
     where not (d.fleet_id = any(v_skip))
     order by d.hold_until, d.fleet_id
     limit 1;
    if v_f is null then
      exit when not p_commit;
      v_skip := '{}';   -- a busy one gets another try
      commit;
      perform pg_sleep(0.25);
      commit;
      continue;
    end if;

    -- (A) THE PLAN, outside the quay
    v_t := clock_timestamp();
    begin
      v_a := public.lap_start_plan(v_f);
    exception when others then
      v_a := -2;
      v_note := coalesce(v_note, 'plan ' || v_f || ': ' || sqlerrm);
    end;
    if p_commit then commit; end if;
    v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
    v_plan_ms := v_plan_ms + v_ms;
    v_plan_max := greatest(v_plan_max, v_ms);
    if v_a <> 1 then
      if v_a = 0 then v_settled := v_settled + 1;
      elsif v_a = -1 then v_busy := v_busy + 1;
      else v_failed := v_failed + 1;
      end if;
      v_skip := v_skip || v_f;
      continue;
    end if;

    -- (B) THE OPEN, under the quay, in the gap after this second's beat
    if p_commit then
      v_tw := clock_timestamp();
      loop
        exit when clock_timestamp() - v_tw >= c_wait;
        exit when exists (select 1 from public.arrivals_beats b
                           where b.slot = (floor(extract(epoch from clock_timestamp()))::bigint % 3600)::int
                             and b.at >= date_trunc('second', clock_timestamp()))
                  and mod((extract(epoch from clock_timestamp()) * 1000)::numeric, 1000) + v_est + c_margin <= 1000;
        perform pg_sleep(0.02);
      end loop;
      v_ms := extract(epoch from clock_timestamp() - v_tw) * 1000;
      if clock_timestamp() - v_tw >= c_wait then v_late := v_late + 1; end if;
      v_wait_ms := v_wait_ms + v_ms;
      v_wait_max := greatest(v_wait_max, v_ms);
      commit;   -- the open step's transaction starts here: its now() is the lap's instant
    end if;
    v_t := clock_timestamp();
    begin
      v_b := public.lap_start_open(v_f);
      if v_b = 1 then
        v_lag := v_lag || round(extract(epoch from now() - v_hold)::numeric * 1000);
      end if;
    exception when others then
      v_b := -2;
      v_note := coalesce(v_note, 'open ' || v_f || ': ' || sqlerrm);
    end;
    if p_commit then commit; end if;
    v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
    v_open_ms := v_open_ms + v_ms;
    v_open_max := greatest(v_open_max, v_ms);
    v_est := greatest(80, 0.7 * v_est + 0.3 * v_ms);
    if v_b = 1 then v_started := v_started + 1;
    elsif v_b = 0 then v_gone := v_gone + 1;
    elsif v_b = -1 then v_busy := v_busy + 1; v_skip := v_skip || v_f;
    else v_failed := v_failed + 1; v_skip := v_skip || v_f;
    end if;
  end loop;
  insert into public.lap_start_runs (slot, at, ms, receipt)
  values ((floor(extract(epoch from v_now0) / 60)::bigint % 1440)::int, v_now0,
          round(extract(epoch from clock_timestamp() - v_t0)::numeric * 1000, 1),
          jsonb_build_object(
            'enabled', public.standing_routes_on(), 'started', v_started, 'settled', v_settled, 'gone', v_gone,
            'busy', v_busy, 'failed', v_failed, 'note', v_note, 'late', v_late,
            'lag_ms', (select jsonb_build_object(
                         'p50', percentile_cont(0.5) within group (order by x),
                         'p95', percentile_cont(0.95) within group (order by x),
                         'max', max(x)) from unnest(v_lag) x),
            'lags', to_jsonb(v_lag),
            'plan_ms', round(v_plan_ms), 'plan_ms_max', round(v_plan_max),
            'open_ms', round(v_open_ms), 'open_ms_max', round(v_open_max),
            'wait_ms', round(v_wait_ms), 'wait_ms_max', round(v_wait_max), 'est_open_ms', round(v_est),
            'due_left', (select count(*) from public.lap_starts_due())))
  on conflict (slot) do update set at = excluded.at, ms = excluded.ms, receipt = excluded.receipt;
  if p_commit then commit; end if;
end $$;
comment on procedure public.tick_lap_starts(boolean) is
  '0266: THE lap-start job (pg_cron byeharu-voyage:lap-starts, every minute, CALL): the due routes (public.lap_starts_due) oldest first, each its plan step (public.lap_start_plan, outside the quay) and its open step (public.lap_start_open, under the quay, in the gap after the beat); stops at its minute''s end or when switched off. p_commit false: one pass in the caller''s transaction. Writes public.lap_start_runs. Server-only.';
revoke all on procedure public.tick_lap_starts(boolean) from public, anon, authenticated;

do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice '0266: pg_cron is not installed here (PGlite) — byeharu-voyage:lap-starts was NOT scheduled. Call public.tick_lap_starts(false) by hand.';
    return;
  end if;
  perform cron.schedule('byeharu-voyage:lap-starts', '* * * * *', 'call public.tick_lap_starts()');
  perform cron.alter_job(jobid, active := false) from cron.job where jobname = 'byeharu-voyage:lap-starts';
  raise notice '0266: pg_cron present — byeharu-voyage:lap-starts SCHEDULED BUT INACTIVE until wind_the_clock().';
end $cron$;

-- ── 4. THE PROBE ────────────────────────────────────────────────────────────────────────────────
-- her rows, after a run; uuids blanked (new rows carry new ones)
create function pg_temp.digest_0266(p_fleet uuid, p_house uuid, p_port uuid)
returns text
language sql
as $$
select regexp_replace(concat_ws(' # ',
  (select (to_jsonb(sr) - 'id')::text from public.standing_routes sr where sr.fleet_id = p_fleet),
  (select string_agg((to_jsonb(s) - 'id')::text, ',' order by s.ord) from public.standing_route_stops s
     join public.standing_routes sr on sr.id = s.route_id where sr.fleet_id = p_fleet),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(l) - 'id')::text as x from public.standing_route_lines l
     join public.standing_routes sr on sr.id = l.route_id where sr.fleet_id = p_fleet) a),
  (select string_agg((to_jsonb(x) - 'id')::text, ',' order by x.lap_no) from public.standing_route_laps x
     join public.standing_routes sr on sr.id = x.route_id where sr.fleet_id = p_fleet),
  (select string_agg((to_jsonb(o) - 'id')::text, ',' order by o.seq) from public.orders o where o.fleet_id = p_fleet),
  (select to_jsonb(f)::text from public.fleets f where f.id = p_fleet),
  (select string_agg(to_jsonb(s)::text, ',' order by s.id) from public.ships s where s.fleet_id = p_fleet),
  (select string_agg((to_jsonb(v) - 'id')::text, ',' order by v.departed_at) from public.voyages v where v.fleet_id = p_fleet),
  (select to_jsonb(p)::text from public.players p where p.id = p_house),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(l) - 'id')::text as x from public.ledger l
     where l.player_id = p_house and l.created_at >= now()) a),
  (select string_agg(x, ',' order by x) from (select (to_jsonb(e) - 'id')::text as x from public.events e
     where e.player_id = p_house and e.created_at >= now()) a),
  (select md5(string_agg(to_jsonb(g)::text, ',' order by g.good_id)) from public.port_goods g where g.port_id = p_port),
  (select to_jsonb(t)::text from public.port_treasury t where t.port_id = p_port)
  ), '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g')
$$;

-- one run from the state as it stands, rolled back: she alone is due; then the mode's path; then her digest
-- (old = the beat's held loop as it was; new = the job's pass; twice = the pass twice, then A, B by hand;
--  interleave = A, A, B, B by hand)
create function pg_temp.case_0266(p_mode text, p_fleet uuid)
returns text
language plpgsql
as $$
declare
  v_house uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_port  uuid := (select f.port_id from public.fleets f where f.id = p_fleet);
  v_laps0 int;
  v_got   text := '';
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
    select count(*) into v_laps0 from public.standing_route_laps x join public.standing_routes sr on sr.id = x.route_id
     where sr.fleet_id = p_fleet;
    if p_mode = 'old' then
      perform pg_temp.held_old_0266(now());
    elsif p_mode = 'new' then
      call public.tick_lap_starts(false);
      v_r := (select receipt from public.lap_start_runs where at = now());
      if (v_r->>'started')::int is distinct from (select count(*)::int from public.standing_route_laps x
            join public.standing_routes sr on sr.id = x.route_id where sr.fleet_id = p_fleet) - v_laps0
         or (v_r->>'failed')::int <> 0 then
        raise exception '0266 self-assert FAIL: the job''s receipt % does not match fleet %''s laps', v_r, p_fleet;
      end if;
    elsif p_mode = 'twice' then
      call public.tick_lap_starts(false);
      call public.tick_lap_starts(false);
      v_got := public.lap_start_plan(p_fleet)::text || public.lap_start_open(p_fleet)::text;
      if v_got <> '00' then
        raise exception '0266 self-assert FAIL: after two passes fleet % was still due (steps answered %)', p_fleet, v_got;
      end if;
    elsif p_mode = 'interleave' then
      v_got := concat_ws(',', public.lap_start_plan(p_fleet), public.lap_start_plan(p_fleet),
                         public.lap_start_open(p_fleet), public.lap_start_open(p_fleet));
      if v_got not in ('1,1,1,0', '0,0,0,0') then
        raise exception '0266 self-assert FAIL: A, A, B, B on fleet % answered %, not 1,1,1,0', p_fleet, v_got;
      end if;
    end if;
    if (select count(*) from public.standing_route_laps x join public.standing_routes sr on sr.id = x.route_id
         where sr.fleet_id = p_fleet) - v_laps0 > 1 then
      raise exception '0266 self-assert FAIL: fleet % opened more than one lap (%)', p_fleet, p_mode;
    end if;
    raise exception using errcode = 'ZY266', message = concat_ws(' @ ',
      (select count(*) from public.standing_route_laps x join public.standing_routes sr on sr.id = x.route_id
        where sr.fleet_id = p_fleet) - v_laps0,
      pg_temp.digest_0266(p_fleet, v_house, v_port));
  exception when sqlstate 'ZY266' then
    return sqlerrm;
  end;
end $$;

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b    record;
  v_d    record;
  v_h    record;
  v_pp   record;
  v_def  text;
  r      record;
  v_o    text;
  v_n    text;
  v_c    text;
  v_t    text;
  v_i    text;
  v_probed int := 0;
  v_opened int := 0;
begin
  select * into v_b from before_0266;

  -- (a) the hunks reverse; ACL / volatility / definer / config kept; the rest unmoved
  for v_d in select * from defs_before_0266 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0266 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0266(v_def, v_h.new) <> 1 then
        raise exception '0266 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0266 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0266 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p
       where p.oid in ('cmd.advance(uuid,timestamptz)'::regprocedure, 'public.npc_plan(timestamptz,uuid)'::regprocedure,
                       'cmd.standing_route_close_lap(uuid,timestamptz)'::regprocedure,
                       'public.credit(uuid,text,bigint,uuid)'::regprocedure, 'public.hold_the_quay()'::regprocedure,
                       'public.tick_arrivals_each_second(integer)'::regprocedure,
                       'public.tick_compact(boolean,boolean)'::regprocedure)) <> v_b.kept_md5 then
    raise exception '0266 self-assert FAIL: the queue runner, the planner, the lap close, the money door, the quay, the beat or the compactor moved';
  end if;

  -- (b) ONE PATH: nothing in the beat wakes a held route; the due predicate lives in one function; the flag is
  -- set by the plan step alone and read by the route alone
  if position('hold_until' in replace(pg_get_functiondef('public.tick_arrivals(timestamptz)'::regprocedure), E'\r', '')) > 0 then
    raise exception '0266 self-assert FAIL: tick_arrivals still reads hold_until';
  end if;
  if (select string_agg(p.oid::regprocedure::text, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and (case when p.prokind in ('f', 'p') then pg_get_functiondef(p.oid) end) like '%sr.hold_until <= %')
     is distinct from 'lap_starts_due()' then
    raise exception '0266 self-assert FAIL: "hold_until <= now" is decided in (%), not in public.lap_starts_due alone',
      (select string_agg(p.oid::regprocedure::text, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
          and (case when p.prokind in ('f', 'p') then pg_get_functiondef(p.oid) end) like '%sr.hold_until <= %');
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and (case when p.prokind in ('f', 'p') then pg_get_functiondef(p.oid) end) like '%byeharu.lap_plan_only%') <> 2
     or pg_temp.occurs_0266(pg_get_functiondef('cmd.run_standing_route(uuid,timestamptz)'::regprocedure),
                            'current_setting(''byeharu.lap_plan_only'', true) = ''on'' then return -1;') <> 2
     or pg_temp.occurs_0266(pg_get_functiondef('public.lap_start_plan(uuid)'::regprocedure), 'byeharu.lap_plan_only') <> 3 then
    raise exception '0266 self-assert FAIL: the plan flag is not set by public.lap_start_plan alone and read by the route alone';
  end if;
  -- the open step takes the quay before any row, and re-checks due under its locks; the plan step never takes the quay
  v_def := pg_get_functiondef('public.lap_start_open(uuid)'::regprocedure);
  if position('perform public.hold_the_quay();' in v_def) = 0
     or position('perform public.hold_the_quay();' in v_def) > position('for update of f, sr skip locked' in v_def)
     or position('for update of f, sr skip locked' in v_def) > position('from public.lap_starts_due() x where x.fleet_id = p_fleet' in v_def)
     or position('hold_the_quay' in pg_get_functiondef('public.lap_start_plan(uuid)'::regprocedure)) > 0 then
    raise exception '0266 self-assert FAIL: the open step does not take the quay, then lock, then re-check; or the plan step takes the quay';
  end if;

  -- (c) POSTURE: everything new is server-only; the job is a plain procedure
  if has_function_privilege('anon', 'public.lap_starts_due()', 'execute') or has_function_privilege('authenticated', 'public.lap_starts_due()', 'execute')
     or has_function_privilege('anon', 'public.lap_start_plan(uuid)', 'execute') or has_function_privilege('authenticated', 'public.lap_start_plan(uuid)', 'execute')
     or has_function_privilege('anon', 'public.lap_start_open(uuid)', 'execute') or has_function_privilege('authenticated', 'public.lap_start_open(uuid)', 'execute')
     or has_function_privilege('anon', 'public.tick_lap_starts(boolean)', 'execute') or has_function_privilege('authenticated', 'public.tick_lap_starts(boolean)', 'execute')
     or has_table_privilege('anon', 'public.lap_start_runs', 'select') or has_table_privilege('authenticated', 'public.lap_start_runs', 'select') then
    raise exception '0266 self-assert FAIL: a client role can reach the lap-start job or its receipt';
  end if;
  if (select p.prosecdef or p.proconfig is not null or p.prokind <> 'p' from pg_proc p where p.oid = 'public.tick_lap_starts(boolean)'::regprocedure) then
    raise exception '0266 self-assert FAIL: tick_lap_starts is not a plain procedure';
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if (select count(*) from cron.job where jobname = 'byeharu-voyage:lap-starts' and schedule = '* * * * *'
                                       and command = 'call public.tick_lap_starts()') <> 1 then
      raise exception '0266 self-assert FAIL: byeharu-voyage:lap-starts is not scheduled every minute';
    end if;
  end if;

  -- (d) OLD vs NEW, TWICE, INTERLEAVED: up to 4 merchants resting at her home stop, nothing queued, her rest over
  for r in select sr.fleet_id as fid
             from public.standing_routes sr
             join public.players p on p.id = sr.player_id and p.is_npc
             join public.fleets f on f.id = sr.fleet_id and f.status = 'DOCKED'
             join public.standing_route_stops st on st.route_id = sr.id and st.ord = 0 and st.port_id = f.port_id
            where sr.lap_id is null and sr.stop_cursor = 0
              and not exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'failed'))
              and (select count(*) from public.standing_route_stops s2 where s2.route_id = sr.id) >= 2
              -- her rest is over (0101's floor, as cmd.run_standing_route reads it), so the old path would open a lap
              and coalesce((select max(x.closed_at) from public.standing_route_laps x where x.route_id = sr.id), '-infinity')
                  + make_interval(secs => (public.wc_num('route_rest_voyage_days') * 86400
                                           / public.wc_num('time_compression'))::double precision) < now()
            order by sr.id limit 4 loop
    v_o := pg_temp.case_0266('old', r.fid);
    v_n := pg_temp.case_0266('new', r.fid);
    v_c := pg_temp.case_0266('old', r.fid);
    v_t := pg_temp.case_0266('twice', r.fid);
    v_i := pg_temp.case_0266('interleave', r.fid);
    if v_o is distinct from v_c then
      raise exception '0266 self-assert FAIL: the CONTROL differs (old against old) for fleet % — % / %', r.fid, left(v_o, 1500), left(v_c, 1500);
    end if;
    if v_o is distinct from v_n then
      raise exception '0266 self-assert FAIL: the lap start differs for fleet % — old % / new %', r.fid, left(v_o, 1500), left(v_n, 1500);
    end if;
    if v_t is distinct from v_n or v_i is distinct from v_n then
      raise exception '0266 self-assert FAIL: run twice / interleaved, fleet % ends otherwise — once % / twice % / interleaved %',
        r.fid, left(v_n, 600), left(v_t, 600), left(v_i, 600);
    end if;
    v_probed := v_probed + 1;
    if split_part(v_o, ' @ ', 1) = '1' then v_opened := v_opened + 1; end if;
  end loop;

  -- (e) POSTURE, the walls
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points then
    raise exception '0266 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0266 self-assert FAIL: a wall moved';
  end if;

  raise notice '0266 self-assert ok: A LAP STARTS IN ITS OWN JOB. tick_arrivals no longer wakes a held route (1 hunk; due = public.lap_starts_due, one function); cmd.run_standing_route stops before the lap under byeharu.lap_plan_only (2 hunks, inert unset); hunks reversed; advance, npc_plan, close_lap, credit, the quay, the beat and the compactor unmoved (md5). public.tick_lap_starts (plan step outside the quay, open step under it, in the beat''s gap; byeharu-voyage:lap-starts every minute, inactive until wind_the_clock), receipt public.lap_start_runs, all server-only. OLD vs NEW: % merchant(s) made due alone (% opened a lap): the old held loop and the job leave the same rows, old against old alike; the pass twice and A, A, B, B by hand leave the same rows and one lap. Registry unchanged; walls 0.',
    v_probed, v_opened;
end $$;
