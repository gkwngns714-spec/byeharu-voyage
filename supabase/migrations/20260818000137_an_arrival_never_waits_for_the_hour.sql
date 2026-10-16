-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0137 — AN ARRIVAL NEVER WAITS FOR THE HOUR  (the reconcile and the drift commit step by step —
--        nothing either decides moves)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- Prod, cron.job_run_details, 2026-10-15 12:00 → 2026-10-16 18:00 UTC (read-only). byeharu-voyage:arrivals
-- runs every 15 s on a 10 s budget (normal avg ≈ 3.5 s). Every arrivals run over 12 s in that window
-- ended within 0.5 s of another job's COMMIT:
--   * byeharu-voyage:reconcile (select public.tick_reconcile(), hourly at :07, 63–84 s, ONE transaction):
--     runs of 59.2 / 72.0 / 29.9 / 17.2 / 38.9 / 38.4 s ended 31 / 50 / 168 / 274 / 101 / 55 ms after it
--     committed (e.g. 2026-10-16: arrivals 13:07:24.634 → 13:08:03.082, reconcile commit 13:08:03.027).
--   * byeharu-voyage:drift (select public.tick_market_drift(), every 10 min, 12–26 s, ONE statement per
--     UPDATE over all 132,090 port_goods rows): eleven runs of 12.7–21.2 s ended 59–489 ms after it.
-- WHAT THE SWEEP WAITED ON (read off the function bodies on prod, pg_get_functiondef):
--   * public.npc_tend (called by tick_reconcile) takes, for EVERY merchant route on its walk,
--     `perform 1 from public.fleets where id = <her fleet> for update nowait` and the route row
--     FOR UPDATE NOWAIT — before the budget test, so the whole roster (837 fleets) is locked on every
--     pass — inside a subtransaction whose locks are kept until the TOP transaction commits, i.e. until
--     the compactor and the 838-player ledger check have also finished, 60–80 s later. voyage.settle,
--     the sweep's per-fleet step, opens with `select * from public.fleets where id = p_fleet for update`
--     (a waiting lock). So a merchant who arrives during the reconcile is held at that line until the
--     hour commits. The 13:07:24 run on 2026-10-16 is exactly that: everything it wrote (events at its
--     own now(), 13:07:24.634) is MERCHANT business — 10 VOYAGE_REPORTs, 8 DEPARTED, 3 ROUTE_LAPs, 3
--     BOUGHT, 3 SOLD — all of companies the reconcile had walked.
--   * tick_market_drift updates every port_goods row in two statements; a sale or purchase on arrival
--     (cmd.advance → the trade doors) updates the port_goods row it trades, and waits for the drift.
-- A live probe at 18:07 and 18:10 UTC on 2026-10-16 (pg_stat_activity + pg_locks, read-only, every
-- ~4 s) saw the reconcile run 65 s and no sweep waiting in that hour: no merchant of the walk came due.
-- The stall is the arrival that comes due while the hour holds her — which is why it is not every hour.
--
-- ── WHAT THIS FILE DOES (one authority each; nothing a pass decides moves — asserted) ──────────
-- (1) npc_tend is cut, VERBATIM, into its steps: public.npc_tend_roster (the walk: the route written
--     longest ago first, k = roster rank), public.npc_tend_route (one merchant — the per-route body,
--     run inside a one-row loop so its own `continue`s end her exactly as before), public.npc_tend_houses
--     (investment + refounds; the gate loses `and p_route is null` — the one hunk) and
--     public.npc_tend_sum (the receipt's one adder). npc_tend(p_now, p_route) is their one-transaction
--     composition: same signature, same receipt, same ACL / definer / path.
-- (2) public.tick_reconcile becomes a PROCEDURE (the job says CALL): every merchant in her own
--     transaction, then the companies, then the compactor — each under public.npc_upkeep_scope (0097's
--     lock_timeout 2 s and 0114's deadline, transaction-local, so set again for each transaction; the
--     deadline still runs from the start of the hour) — then the invariants unchanged, in a transaction
--     that takes no row lock. A merchant's locks now live for her step (ms; ≈ 1.3 s for a lap start
--     with its plan), not for the hour.
-- (3) public.tick_market_drift(p_now, p_port default null) — two hunks (`and (p_port is null or
--     pg.port_id = p_port)`, one per UPDATE); null is every harbour, as before. The drift job calls the
--     procedure public.tick_market_drift_each_port: every harbour (public.ports, in id order) in its own
--     transaction, all at the job's start time, so every harbour lands on the same slot and game-day.
-- (4) The two cron jobs are re-pointed in place (cron.alter_job command only — name, schedule, owner and
--     active flag untouched), so public.wind_the_clock() starts exactly these commands.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Change any rule, knob, budget, schedule, receipt key, the walk's order, the compactor, the
-- invariants, the arrivals sweep, voyage.settle, or any client grant / entry point. Run the upkeep in
-- parallel. Re-order a lock (each step keeps its own order: fleet, then route, NOWAIT).
-- WHAT CHANGES ONLY IN FAILURE: before, an error escaping the investment pass rolled back the whole
-- tend, and an invariant failure rolled back the hour's upkeep. Now a step's error is reported and
-- rolled back alone, and the invariants raise on a world whose upkeep has already committed.
-- A price snapshot taken during the drift may now read some harbours on the new slot and the rest on
-- the old one (each is a committed state of its own harbour).
--
-- ── THE PROOF (all in this file; old and new on the SAME snapshot) ──────────────────────────────
-- §3 cuts the pre-image of npc_tend at six anchors and requires each slice byte-equal in its new home,
-- the houses slice after its one hunk is reversed, and the text between slices to be exactly the
-- loop's own two lines. §4 runs old (pre-image copy) and new npc_tend, each in a rolled-back
-- subtransaction: the whole pass with the hour's budget spent, then 12 merchants one by one with no
-- budget (dear work first: unstarted, paused, a failed order at her head) — receipts must be equal,
-- and so must an END-STATE digest of every table in public / world / cmd / voyage (row count + md5 of
-- every row the run wrote, minted uuids blanked). The merchants are switched on inside the run where
-- the world has them off (PGlite / CI). §6 reverses tick_market_drift to its pre-image and runs old
-- (whole market) vs new (harbour by harbour) with drift_sigma = 0 inside the run — the drift draw is
-- random() by design (0010) — over every row: port_goods must be byte-equal. Timings: raise notice only.
-- The procedures COMMIT, so they cannot run inside a migration: they were driven, committed, on the
-- cached PGlite world (DEV_LOG 2026-10-16), and §7 asserts they are invoker, SET-free, owner-only.
--
-- ── WHAT IT BUYS ────────────────────────────────────────────────────────────────────────────────
-- EXPECTED on prod (not measurable before the push): an arrivals run overlapping the reconcile waits at
-- most for the one merchant step holding her (ms; ≈ 1.3 s at most, a lap start)
-- instead of up to 84 s; one overlapping the drift waits for one harbour's update (≈ 132,090 / 252 rows,
-- ~0.1 s) instead of 12–26 s. VERIFY after the push with the same cron.job_run_details query (arrivals
-- runs > 12 s ending within 1 s of a reconcile / drift end).
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- DROP / CREATE FUNCTION and PROCEDURE (catalog only); the proofs write inside rolled-back
-- subtransactions (row locks on rows they touch, released at each rollback); cron.alter_job. No LOCK
-- TABLE, no set role, no set local, no begin. Deploy with the clock unwound (DEPLOY_RUNBOOK):
-- unwind_the_clock() → db push → wind_the_clock().
--
-- ROLLBACK: a forward migration that drops the four steps and the two procedures, re-creates
-- tick_reconcile() and tick_market_drift(timestamptz) from their pre-images (verbatim in pg history and
-- reconstructible here: the hunks and slices are this file's text) and points the jobs back at `select`.
-- SUPERSEDES: public.npc_tend (0123), public.tick_reconcile (0114), public.tick_market_drift (0123).
-- VERSION: 0137. Applies on 0136 (PR #140; depends on #139 and #140). Prod head 0134 at writing.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════


do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0137(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- the text of p_hay from the start of p_from to the end of p_to; each anchor must occur exactly once
create or replace function pg_temp.slice_0137(p_hay text, p_from text, p_to text)
returns text
language plpgsql
immutable
as $$
begin
  if pg_temp.occurs_0137(p_hay, p_from) <> 1 or pg_temp.occurs_0137(p_hay, p_to) <> 1 then
    raise exception '0137 self-assert FAIL: an anchor does not occur exactly once (% × "%", % × "%")',
      pg_temp.occurs_0137(p_hay, p_from), left(p_from, 60), pg_temp.occurs_0137(p_hay, p_to), left(p_to, 60);
  end if;
  if strpos(p_hay, p_to) < strpos(p_hay, p_from) then
    raise exception '0137 self-assert FAIL: anchor "%" lies before "%"', left(p_to, 60), left(p_from, 60);
  end if;
  return substr(p_hay, strpos(p_hay, p_from), strpos(p_hay, p_to) + length(p_to) - strpos(p_hay, p_from));
end $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0137 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.npc_tend(timestamptz, uuid)'),
               ('public.tick_reconcile()'),
               ('public.tick_market_drift(timestamptz)')) f(fn);

-- THE OLD COPIES the proof runs against the new bodies. npc_tend's callees are untouched by this file
-- (npc_plan, npc_invest, the cmd doors, credit), so the copy calls the live ones; asserted below that
-- it calls none of the new steps.
do $$
declare
  v_def text;
begin
  select def into v_def from defs_before_0137 where fn = 'public.npc_tend(timestamptz, uuid)';
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION public.npc_tend(', 'CREATE OR REPLACE FUNCTION pg_temp.npc_tend_old_0137(');
  if strpos(v_def, 'FUNCTION pg_temp.npc_tend_old_0137(') = 0 or strpos(v_def, 'npc_tend_route') > 0
     or strpos(v_def, 'npc_tend_roster') > 0 or strpos(v_def, 'npc_tend_houses') > 0 then
    raise exception '0137 self-assert FAIL: the old copy of npc_tend was not made from the pre-image';
  end if;
  execute v_def;
  select def into v_def from defs_before_0137 where fn = 'public.tick_market_drift(timestamptz)';
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION public.tick_market_drift(', 'CREATE OR REPLACE FUNCTION pg_temp.tick_market_drift_old_0137(');
  if strpos(v_def, 'FUNCTION pg_temp.tick_market_drift_old_0137(') = 0 or strpos(v_def, 'market_drift_at') > 0 then
    raise exception '0137 self-assert FAIL: the old copy of tick_market_drift was not made from the pre-image';
  end if;
  execute v_def;
end $$;

-- ── 2. THE MERCHANT UPKEEP, CUT INTO ITS OWN STEPS (one authority each; npc_tend composes them) ──
-- The walk: npc_tend's roster query, verbatim (asserted in §3). The walk order and k (the ROSTER rank
-- npc_fleet_max is read against) are this query's and nobody else's.
create function public.npc_tend_roster()
returns table (fleet_id uuid, route_id uuid, player_id uuid, alt_loop jsonb, k bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0137: THE merchant upkeep's walk, moved verbatim out of public.npc_tend — the route written
-- longest ago first, k = the roster rank. Read by npc_tend and by the hourly public.tick_reconcile.
#variable_conflict use_column
begin
  return query select nf.fleet_id, nf.route_id, nf.player_id, nf.alt_loop,
                  row_number() over (order by nf.roster_ord) as k
             from public.npc_fleets nf
             join public.players p on p.id = nf.player_id and p.is_npc
             join public.standing_routes sr0 on sr0.id = nf.route_id
            where nf.route_id is not null
            order by sr0.updated_at, nf.roster_ord;
end $$;
comment on function public.npc_tend_roster() is
  '0137: THE merchant upkeep''s walk (npc_tend''s roster query, verbatim): route written longest ago '
  'first, k = roster rank. Read by public.npc_tend and public.tick_reconcile. Server-only.';
revoke all on function public.npc_tend_roster() from public, anon, authenticated;

-- One merchant: npc_tend's per-route body, verbatim (asserted in §3). It runs inside a one-row loop,
-- so its own `continue` statements end this merchant exactly as they ended her iteration before.
create function public.npc_tend_route(p_now timestamptz, p_fleet uuid, p_route uuid, p_k bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0137: ONE merchant's upkeep — public.npc_tend's per-route body, moved verbatim (fleet then route
-- locked NOWAIT in its own subtransaction; a busy route is skipped and counted). Returns this
-- merchant's counts; public.npc_tend_sum adds them up. Called by npc_tend (one transaction) and by
-- the hourly public.tick_reconcile (one transaction PER MERCHANT, so the locks she takes are held
-- for her step and no longer).
declare
  v_on      boolean := public.npc_traders_on();
  v_max     int     := public.wc_int('npc_fleet_max');
  r         record;
  sr        public.standing_routes%rowtype;
  f         public.fleets%rowtype;
  fo        public.orders%rowtype;
  v_res     jsonb;
  v_clears  int;
  v_dark    int := 0;
  v_started int := 0;
  v_resumed int := 0;
  v_cleared int := 0;
  v_laid_n  int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_notes   jsonb := '[]'::jsonb;
begin
  for r in select p_fleet as fleet_id, p_route as route_id, p_k as k loop   -- 0137: one row
    begin
      perform 1 from public.fleets where id = r.fleet_id for update nowait;
      select * into sr from public.standing_routes where id = r.route_id for update nowait;
      select * into f from public.fleets where id = r.fleet_id;

      if not v_on or r.k > v_max then
        if sr.fleet_id is not null and sr.paused_reason is distinct from 'dark' then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'dark', 'The merchants keep to port.');
          v_dark := v_dark + 1;
        end if;
        continue;
      end if;

      if f.status in ('ADRIFT', 'UNABLE_TO_SAIL') then
        -- 0115: NOT PARKED. No verb refloats a fleet that cannot sail — for anybody — so she is
        -- counted in the receipt and her route is left as it is; the executor waits for her.
        v_laid_n := v_laid_n + 1;
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'cannot_sail', f.status);
        continue;
      end if;

      -- A PAUSE THE WORLD MAY LIFT, and only when it may: dark/losing/reserve/edited at once;
      -- laid_up after npc_laid_up_hours; error after 6 h (updated_at dates the pause — the hourly
      -- plan skips error routes, so it cannot keep the date fresh). off_route re-assigns where she
      -- lies, if that is a stop. 'player' is never a merchant's.
      --
      -- updated_at DATES A PAUSE ONLY WHILE NOTHING HAS WRITTEN THE ROUTE SINCE. That holds for
      -- 'error' (the plan skips those) and it is what the ageing test below reads; it does NOT hold
      -- after the plan has saved — see the receipt test further down.
      if sr.paused_reason = 'off_route' then
        if f.status = 'DOCKED'
           and exists (select 1 from public.standing_route_stops s where s.route_id = sr.id and s.port_id = f.port_id) then
          v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
          v_resumed := v_resumed + 1;
        else
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'off_route', f.status);
        end if;
        continue;
      end if;
      if sr.paused_reason is not null
         and not (sr.paused_reason in ('dark', 'losing', 'reserve', 'edited', 'laid_up')   -- 0115: laid_up at once
                  or (sr.paused_reason = 'error' and sr.updated_at < p_now - interval '6 hours')) then
        continue;
      end if;

      -- 0114: THE BUDGET gates the dear work only — a plan and a start or a resume, and the halt
      -- law's release below. The dark and cannot-sail lay-ups above stay unconditional.
      if (sr.fleet_id is null or sr.paused_reason is not null) and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;
        continue;
      end if;

      -- NOT STARTED, OR A PAUSE TO LIFT: plan first (the lines are the market's NOW), then start
      -- her where she lies, or resume her. The plan may lay her up (nothing pays): then she waits.
      if sr.fleet_id is null or sr.paused_reason is not null then
        if sr.paused_reason = 'error' then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'resumed_after_error', true);
        end if;
        v_res := public.npc_plan(p_now, sr.id);
        select * into sr from public.standing_routes where id = r.route_id;
        -- DID THIS PLAN LAY HER UP? THE PLAN'S OWN RECEIPT SAYS SO — NEVER updated_at. The save
        -- door (cmd.standing_route_save_for) sets updated_at = now(), so after a SUCCESSFUL plan an
        -- `updated_at >= p_now - v_laid` test is always true at p_now = now(): it skipped every
        -- laid-up route it had just re-planned, the resume and start branches below were
        -- unreachable for that reason, and every merchant laid up for want of cargo stayed laid up
        -- for ever (found by the 2026-10-08 review; the ageing test above still gates WHEN she is
        -- re-planned at all). `planned` is this call's own count, and p_route pins the call to this
        -- one route, so planned = 0 means she was NOT re-planned — laid up again (nothing pays),
        -- busy, or failed — and she waits. Both arms are acceptable outcomes (NO_SPAGHETTI §7C):
        -- resume on fresh lines, or wait; she is never resumed on stale ones.
        --
        -- AND THAT HOLDS FOR EVERY PAUSE, not only 'laid_up' (the 2026-10-10 review): a dark or
        -- losing route whose plan RAISED would otherwise have been resumed on week-old lines, which
        -- is the very thing the sentence above claims never happens. Counted in the notes, so a
        -- route that is never planned is visible in the receipt rather than silently stuck.
        if coalesce((v_res->>'planned')::int, 0) = 0 then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'not_planned', coalesce(sr.paused_reason, 'unstarted'));
          continue;
        end if;
        if sr.fleet_id is null then
          if f.status = 'DOCKED' then
            v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
            if coalesce((v_res->>'ok')::boolean, false) then
              v_started := v_started + 1;
            else
              v_notes := v_notes || jsonb_build_object('route', sr.name, 'start', v_res->>'error_code');
            end if;
          end if;
        elsif sr.paused_reason is not null then
          v_res := cmd.standing_route_pause_for(sr.player_id, sr.id, false);
          v_resumed := v_resumed + 1;
        end if;
        continue;
      end if;

      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
      select * into fo from public.orders where fleet_id = r.fleet_id and status = 'failed' order by seq limit 1;
      if fo.id is not null and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;                               -- 0114
      elsif fo.id is not null then
        select count(*) + 1 into v_clears from public.events ev
         where ev.player_id = sr.player_id and ev.kind = 'NPC_CLEARED'
           and ev.payload->>'route_id' = sr.id::text and (ev.payload->>'lap_no')::int = sr.lap_no;
        perform public.emit_event(sr.player_id, 'NPC_CLEARED', jsonb_build_object(
          'route', sr.name, 'route_id', sr.id, 'lap_no', sr.lap_no, 'fleet', f.name,
          'code', fo.error_code, 'line', fo.raw_text, 'n', v_clears));
        -- 0115: NOT PARKED. The third clear in one lap re-plans her lines on today's market first;
        -- every clear then releases her queue and the executor goes on.
        if v_clears >= 3 then
          perform public.npc_plan(p_now, sr.id);
        end if;
        perform cmd.clear_for(sr.player_id, r.fleet_id, false);
        perform cmd.advance(r.fleet_id, p_now);
        v_cleared := v_cleared + 1;
      end if;
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('route', r.route_id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('dark', v_dark, 'started', v_started, 'resumed', v_resumed, 'cleared', v_cleared,
                            'laid_up', v_laid_n, 'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred,
                            'notes', v_notes);
end $$;
comment on function public.npc_tend_route(timestamptz, uuid, uuid, bigint) is
  '0137: ONE merchant''s upkeep (npc_tend''s per-route body, verbatim). Composed by public.npc_tend '
  '(one transaction) and public.tick_reconcile (one transaction per merchant). Server-only.';
revoke all on function public.npc_tend_route(timestamptz, uuid, uuid, bigint) from public, anon, authenticated;

-- The companies: npc_tend's investment and refound passes, verbatim (asserted in §3) but for the
-- gate, which loses `and p_route is null` — the caller decides whether the companies are tended.
create function public.npc_tend_houses(p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0137: THE companies' upkeep — public.npc_tend's investment (public.npc_invest) and refound passes,
-- moved verbatim. npc_tend runs it after the routes when no single route was asked for; the hourly
-- public.tick_reconcile runs it in its own transaction after the routes.
declare
  v_on      boolean := public.npc_traders_on();
  hh        record;
  v_last    timestamptz;
  v_week    int;
  v_refound int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_can      bigint;
  v_unfunded int := 0;
  v_inv      jsonb := '{}'::jsonb;
  v_notes   jsonb := '[]'::jsonb;
begin
  -- 0123: INVESTMENT — merchants put their surplus into the cities of their loop (public.npc_invest).
  if v_on then
    v_inv := public.npc_invest(p_now);
    v_deferred := v_deferred + coalesce((v_inv->>'deferred')::int, 0);
    v_failed := v_failed + coalesce((v_inv->>'failed')::int, 0);
    v_notes := v_notes || coalesce(v_inv->'notes', '[]'::jsonb);
  end if;

  -- REFOUNDS, per company, only while the switch is on.
  if v_on then
    for hh in select h.player_id, h.capital, pl.ducats, pl.company_name, h.home_port_id
                from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
               where pl.ducats < h.capital * public.wc_num('npc_purse_floor_pct')
               order by h.roster_ord loop
      begin
        select max(ev.created_at), count(*) filter (where ev.created_at > p_now - interval '7 days')
          into v_last, v_week
          from public.events ev where ev.player_id = hh.player_id and ev.kind = 'NPC_REFOUNDED';
        continue when v_last is not null
          and v_last > p_now - make_interval(secs => (public.wc_num('npc_refound_cooldown_game_days')
                                                       * public.wc_num('game_day_seconds'))::double precision);
        -- 0115: NO WEEKLY CAP THAT PARKS A COMPANY. A purse under the floor is refounded (the
        -- cooldown still spaces refounds); the cap's lay-up and loop swap are deleted.
        if not public.city_treasury_on() then
          perform public.credit(hh.player_id, 'NPC_REFOUND', hh.capital - hh.ducats,
            public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
              'company', hh.company_name, 'amount', hh.capital - hh.ducats, 'week', coalesce(v_week, 0) + 1)));
          v_refound := v_refound + 1;
        else
          -- 0122: lit, the HOME HARBOUR pays, from its surplus — partially, or not at all. A merchant
          -- whose home cannot pay sails on at her purse floor until it earns (never parked, 0115).
          v_can := greatest(0, least(hh.capital - hh.ducats, public.city_surplus(hh.home_port_id)));
          if v_can > 0 then
            perform public.city_pays(hh.home_port_id, hh.player_id, 'NPC_REFOUND', v_can,
              public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
                'company', hh.company_name, 'amount', v_can, 'week', coalesce(v_week, 0) + 1,
                'port', (select p.code from public.ports p where p.id = hh.home_port_id),
                'partial', v_can < hh.capital - hh.ducats)));
            v_refound := v_refound + 1;
          else
            v_unfunded := v_unfunded + 1;
          end if;
        end if;
      exception when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('company', hh.company_name, 'error', sqlerrm);
      end;
    end loop;
  end if;

  return jsonb_build_object('refounded', v_refound, 'refound_unfunded', v_unfunded,
                            'invested', coalesce((v_inv->>'invested')::int, 0),
                            'failed', v_failed, 'deferred', v_deferred, 'notes', v_notes);
end $$;
comment on function public.npc_tend_houses(timestamptz) is
  '0137: THE companies'' upkeep (npc_tend''s investment and refound passes, verbatim). Composed by '
  'public.npc_tend and public.tick_reconcile. Server-only.';
revoke all on function public.npc_tend_houses(timestamptz) from public, anon, authenticated;

-- The receipt's one adder: every count npc_tend has ever reported, summed; notes in order.
create function public.npc_tend_sum(p_a jsonb, p_b jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $$
-- 0137: THE one place npc_tend's receipt is added up — the counts of two steps summed (a missing
-- count is 0), their notes concatenated in order. npc_tend_sum(x, '{}') is x with every count present.
declare
  v_k text;
  v   jsonb := jsonb_build_object('notes', coalesce(p_a->'notes', '[]'::jsonb) || coalesce(p_b->'notes', '[]'::jsonb));
begin
  foreach v_k in array array['dark', 'started', 'resumed', 'cleared', 'laid_up', 'refounded', 'refound_unfunded',
                             'invested', 'busy', 'failed', 'deferred'] loop
    v := v || jsonb_build_object(v_k, coalesce((p_a->>v_k)::int, 0) + coalesce((p_b->>v_k)::int, 0));
  end loop;
  return v;
end $$;
comment on function public.npc_tend_sum(jsonb, jsonb) is
  '0137: THE adder of npc_tend''s receipt (counts summed, notes concatenated). Server-only.';
revoke all on function public.npc_tend_sum(jsonb, jsonb) from public, anon, authenticated;

-- The budget's scope: set here and nowhere else (0114's deadline and 0097's lock_timeout, both
-- transaction-local — so the hourly upkeep sets them again at the start of each of its transactions).
create function public.npc_upkeep_scope(p_deadline timestamptz)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
-- 0137: THE scope of one transaction of the hourly merchant upkeep: never wait on a lock longer than
-- 2 s (0097), and stop the dear work at the hour's deadline (0114; read by public.npc_upkeep_spent).
-- Both transaction-local. Called by public.tick_reconcile alone.
begin
  perform set_config('lock_timeout', '2s', true);
  perform set_config('byeharu.npc_upkeep_deadline', p_deadline::text, true);
end $$;
comment on function public.npc_upkeep_scope(timestamptz) is
  '0137: THE scope of one transaction of the hourly merchant upkeep (lock_timeout 2 s, the 0114 '
  'deadline), transaction-local. Called by public.tick_reconcile alone. Server-only.';
revoke all on function public.npc_upkeep_scope(timestamptz) from public, anon, authenticated;

-- npc_tend: the same receipt, the same work, in one transaction — now the composition of the above.
create or replace function public.npc_tend(p_now timestamptz default now(), p_route uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- What the world does for a merchant that a player would do by hand — through the route cores,
-- cmd.clear_for + cmd.advance, and public.credit; nothing else. Per route, fleet then route locked
-- NOWAIT inside its own subtransaction (a busy route is skipped, counted, never waited for):
--   switch OFF, or beyond npc_fleet_max in roster order -> paused 'dark' (fleets at sea finish
--     their leg and lie in port).
--   ADRIFT / UNABLE_TO_SAIL -> counted and left (0115: never parked; there is no RECALL or salvage
--     verb for anybody, so the executor waits for her).
--   not started -> planned, then assigned where she lies (assigning starts the loop).
--   paused dark/losing/reserve/edited/laid_up -> planned, then resumed, at once (0115: a lay-up is
--     legacy — nothing writes one any more); whether THIS call re-planned her is read off the
--     plan's receipt, not off updated_at (the save bumps it). error -> the same after 6 h (the
--     pause is dated by updated_at). off_route -> re-assigned if she lies at a stop; otherwise
--     reported.
--   a FAILED order at the head of her queue (the halt law) -> cmd.clear_for, then cmd.advance —
--     COUNTED: the third clear with no lap closed between re-plans her lines first (0115).
-- Then per company: purse below capital × npc_purse_floor_pct -> refounded (NPC_REFOUND through
-- 0137: the steps live in their own functions — public.npc_tend_roster (the walk),
-- public.npc_tend_route (one merchant), public.npc_tend_houses (the companies), public.npc_tend_sum (the
-- receipt). This is their one-transaction composition; the hourly public.tick_reconcile composes the
-- same steps one transaction each.
declare
  v_on  boolean := public.npc_traders_on();
  r     record;
  v_acc jsonb := '{}'::jsonb;
begin
  for r in select * from public.npc_tend_roster() loop
    continue when p_route is not null and r.route_id <> p_route;
    v_acc := public.npc_tend_sum(v_acc, public.npc_tend_route(p_now, r.fleet_id, r.route_id, r.k));
  end loop;
  if p_route is null then
    v_acc := public.npc_tend_sum(v_acc, public.npc_tend_houses(p_now));
  end if;
  return jsonb_build_object('enabled', v_on) || public.npc_tend_sum(v_acc, '{}'::jsonb);
end $$;

-- ── 3. THE MOVED TEXT IS THE OLD TEXT (reverse-to-original, byte for byte) ──────────────────────
-- The pre-image is cut at six anchors into: [head] roster [glue] route [glue] houses [receipt]. The
-- roster, route and houses slices must be found, byte-equal, in the new functions (the houses slice
-- after its one hunk is reversed), and the two glues must be exactly the loop's own lines — so no
-- line of the old body was dropped between the slices. The head (declarations) and the receipt are
-- re-written in the new bodies; §4 proves them by behaviour.
do $$
declare
  v_old    text := (select def from defs_before_0137 where fn = 'public.npc_tend(timestamptz, uuid)');
  v_roster text := replace(pg_get_functiondef('public.npc_tend_roster()'::regprocedure), E'\r', '');
  v_route  text := replace(pg_get_functiondef('public.npc_tend_route(timestamptz, uuid, uuid, bigint)'::regprocedure), E'\r', '');
  v_houses text := replace(pg_get_functiondef('public.npc_tend_houses(timestamptz)'::regprocedure), E'\r', '');
  v_tend   text := replace(pg_get_functiondef('public.npc_tend(timestamptz, uuid)'::regprocedure), E'\r', '');
  a1 text := 'select nf.fleet_id, nf.route_id, nf.player_id, nf.alt_loop,';
  a2 text := 'order by sr0.updated_at, nf.roster_ord';
  a3 text := E'    begin\n      perform 1 from public.fleets where id = r.fleet_id for update nowait;';
  a4 text := E'        v_notes := v_notes || jsonb_build_object(''route'', r.route_id, ''error'', sqlerrm);\n    end;';
  a5 text := '  -- 0123: INVESTMENT';
  a6 text := E'        v_notes := v_notes || jsonb_build_object(''company'', hh.company_name, ''error'', sqlerrm);\n      end;\n    end loop;\n  end if;';
  s_roster text;
  s_route  text;
  s_houses text;
  v_new_h  text;
  v_glue1  text;
  v_glue2  text;
  b        record;
begin
  s_roster := pg_temp.slice_0137(v_old, a1, a2);
  s_route  := pg_temp.slice_0137(v_old, a3, a4);
  s_houses := pg_temp.slice_0137(v_old, a5, a6);
  if pg_temp.slice_0137(v_roster, a1, a2) <> s_roster then
    raise exception '0137 self-assert FAIL: npc_tend_roster''s query is not npc_tend''s walk, verbatim';
  end if;
  if pg_temp.slice_0137(v_route, a3, a4) <> s_route then
    raise exception '0137 self-assert FAIL: npc_tend_route''s body is not npc_tend''s per-route body, verbatim';
  end if;
  v_new_h := pg_temp.slice_0137(v_houses, a5, a6);
  if pg_temp.occurs_0137(v_new_h, E'\n  if v_on then\n') <> 2 or strpos(v_new_h, 'p_route') > 0 then
    raise exception '0137 self-assert FAIL: npc_tend_houses'' two gates are not the one hunk';
  end if;
  if replace(v_new_h, E'\n  if v_on then\n', E'\n  if v_on and p_route is null then\n') <> s_houses then
    raise exception '0137 self-assert FAIL: npc_tend_houses'' body does not reverse to npc_tend''s companies passes';
  end if;
  v_glue1 := substr(v_old, strpos(v_old, a2) + length(a2), strpos(v_old, a3) - strpos(v_old, a2) - length(a2));
  v_glue2 := substr(v_old, strpos(v_old, a4) + length(a4), strpos(v_old, a5) - strpos(v_old, a4) - length(a4));
  if v_glue1 <> E' loop\n    continue when p_route is not null and r.route_id <> p_route;\n'
     or v_glue2 <> E'\n  end loop;\n\n'
     or right(substr(v_old, 1, strpos(v_old, a1) - 1), 11) <> '  for r in '
     or strpos(substr(v_old, strpos(v_old, a6) + length(a6)), E'\n\n  return jsonb_build_object(''enabled'', v_on, ') <> 1 then
    raise exception '0137 self-assert FAIL: the pre-image has text between its slices that this file did not account for';
  end if;
  -- the new npc_tend carries none of the moved text, and keeps its attributes and ACL
  if strpos(v_tend, a3) > 0 or strpos(v_tend, a5) > 0 or strpos(v_tend, a1) > 0 then
    raise exception '0137 self-assert FAIL: npc_tend still carries a moved step (a second copy)';
  end if;
  select * into b from defs_before_0137 where fn = 'public.npc_tend(timestamptz, uuid)';
  if (select p.prosecdef from pg_proc p where p.oid = 'public.npc_tend(timestamptz, uuid)'::regprocedure) <> b.secdef
     or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'public.npc_tend(timestamptz, uuid)'::regprocedure) <> b.cfg
     or (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.npc_tend(timestamptz, uuid)'::regprocedure) <> b.acl then
    raise exception '0137 self-assert FAIL: npc_tend''s security, settings or ACL moved';
  end if;
  -- the steps are server-only
  if exists (select 1 from unnest(array['public.npc_tend_roster()', 'public.npc_tend_route(timestamptz, uuid, uuid, bigint)',
                                        'public.npc_tend_houses(timestamptz)', 'public.npc_tend_sum(jsonb, jsonb)',
                                        'public.npc_upkeep_scope(timestamptz)']) f
              where has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')) then
    raise exception '0137 self-assert FAIL: a client can execute an upkeep step';
  end if;
end $$;

-- ── 4. OLD AND NEW TEND THE SAME WORLD (one snapshot, each run rolled back) ───────────────────
-- What is compared: npc_tend's receipt, and an END-STATE digest of every table in public / world /
-- cmd / voyage — its row count, and the md5 of every row the run wrote (xmin newer than this
-- file's transaction; uuids blanked, because the doors mint fresh ones). Two runs per variant:
--   (a) the WHOLE pass with the hour's budget already spent — every merchant walked (the dark and
--       cannot-sail lay-ups, off-route re-assigns, the halt law's deferral), the investment pass
--       deferred, every refound due;
--   (b) then, budget unset, 12 merchants one route at a time (p_route), those with dear work first
--       (unstarted, paused, or a failed order at the head of her queue): plans, starts, resumes, clears.
-- The merchants are switched on inside the run when the world has them off (PGlite / CI); prod has
-- them on, and the update then writes nothing.
create or replace function pg_temp.digest_0137(p_base bigint)
returns jsonb
language plpgsql
as $$
declare
  t     record;
  v     jsonb := '{}'::jsonb;
  v_n   bigint;
  v_md5 text;
begin
  for t in select n.nspname, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where c.relkind = 'r' and n.nspname in ('public', 'world', 'cmd', 'voyage')
            order by n.nspname, c.relname loop
    execute format($q$select count(*),
                             md5(coalesce(string_agg(regexp_replace(row_to_json(x)::text,
                                   '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g'), E'\n'
                                   order by regexp_replace(row_to_json(x)::text,
                                   '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g'))
                                   filter (where x.xmin::text::bigint > $1), ''))
                        from %I.%I x$q$, t.nspname, t.relname)
      into v_n, v_md5 using p_base;
    v := v || jsonb_build_object(t.nspname || '.' || t.relname, v_n::text || ':' || v_md5);
  end loop;
  return v;
end $$;

create temp table tend_sample_0137 on commit drop as
select nf.route_id
  from public.npc_fleets nf
  join public.players p on p.id = nf.player_id and p.is_npc
  join public.standing_routes sr on sr.id = nf.route_id
 order by (sr.fleet_id is null or sr.paused_reason is not null
           or exists (select 1 from public.orders o where o.fleet_id = nf.fleet_id and o.status = 'failed')) desc,
          md5(nf.route_id::text), nf.route_id
 limit 12;

create or replace function pg_temp.tend_run_0137(p_old boolean, p_now timestamptz, p_base bigint)
returns jsonb
language plpgsql
as $$
declare
  s      record;
  v_t0   timestamptz;
  v_full jsonb;
  v_one  jsonb := '[]'::jsonb;
  v_ms   jsonb := '{}'::jsonb;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
  -- (a) the whole pass, the hour's budget spent
  perform set_config('byeharu.npc_upkeep_deadline', '2000-01-01 00:00:00+00', true);
  v_t0 := clock_timestamp();
  if p_old then v_full := pg_temp.npc_tend_old_0137(p_now); else v_full := public.npc_tend(p_now); end if;
  v_ms := v_ms || jsonb_build_object('whole', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  raise notice '0137 probe: the whole pass (old body: %) % ms', p_old, v_ms->>'whole';
  -- (b) twelve merchants, one route at a time, no budget
  perform set_config('byeharu.npc_upkeep_deadline', '', true);
  v_t0 := clock_timestamp();
  for s in select route_id from tend_sample_0137 order by route_id loop
    if p_old then
      v_one := v_one || jsonb_build_array(pg_temp.npc_tend_old_0137(p_now, s.route_id));
    else
      v_one := v_one || jsonb_build_array(public.npc_tend(p_now, s.route_id));
    end if;
  end loop;
  v_ms := v_ms || jsonb_build_object('sample', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  raise notice '0137 probe: twelve merchants (old body: %) % ms', p_old, v_ms->>'sample';
  return jsonb_build_object('whole', v_full, 'sample', v_one, 'digest', pg_temp.digest_0137(p_base), 'ms', v_ms);
end $$;

do $$
declare
  v_base bigint := (pg_current_xact_id()::text::bigint % 4294967296);
  v_now  timestamptz := now();
  v_old  jsonb;
  v_new  jsonb;
  v_k    text;
begin
  begin
    v_old := pg_temp.tend_run_0137(true, v_now, v_base);
    raise exception using errcode = 'ZX137', message = v_old::text;
  exception when sqlstate 'ZX137' then
    v_old := sqlerrm::jsonb;
  end;
  begin
    v_new := pg_temp.tend_run_0137(false, v_now, v_base);
    raise exception using errcode = 'ZX137', message = v_new::text;
  exception when sqlstate 'ZX137' then
    v_new := sqlerrm::jsonb;
  end;
  if v_old->'whole' is distinct from v_new->'whole' then
    raise exception '0137 self-assert FAIL: the whole tend''s receipt moved: old % / new %', v_old->'whole', v_new->'whole';
  end if;
  if v_old->'sample' is distinct from v_new->'sample' then
    raise exception '0137 self-assert FAIL: a merchant''s tend moved: old % / new %', v_old->'sample', v_new->'sample';
  end if;
  for v_k in select jsonb_object_keys(v_old->'digest') loop
    if v_old->'digest'->v_k is distinct from v_new->'digest'->v_k then
      raise exception '0137 self-assert FAIL: % ends in a different state (old % / new %)', v_k,
        v_old->'digest'->>v_k, v_new->'digest'->>v_k;
    end if;
  end loop;
  if (select count(*) from jsonb_object_keys(v_new->'digest')) <> (select count(*) from jsonb_object_keys(v_old->'digest')) then
    raise exception '0137 self-assert FAIL: the digests cover different tables';
  end if;
  raise notice '0137: the tend, old = new on one snapshot — whole pass % (budget spent; old % ms / new % ms), % merchants one by one (old % ms / new % ms), % tables, % written',
    (v_new->'whole') - 'notes', v_old->'ms'->>'whole', v_new->'ms'->>'whole',
    jsonb_array_length(v_new->'sample'), v_old->'ms'->>'sample', v_new->'ms'->>'sample',
    (select count(*) from jsonb_object_keys(v_new->'digest')),
    (select count(*) from jsonb_each_text(v_new->'digest') e where e.value not like '%:d41d8cd98f00b204e9800998ecf8427e');
end $$;

-- ── 5. THE HOURLY RECONCILE, ONE TRANSACTION PER STEP ──────────────────────────────────────────
-- A PROCEDURE, so it can COMMIT between steps (pg_cron calls it with CALL, one statement, outside any
-- transaction block — prod runs cron.use_background_workers = off, i.e. a plain libpq session).
-- Transaction control forbids SECURITY DEFINER and a SET clause on the procedure itself: it runs as
-- the job's owner, every name schema-qualified; each step it calls keeps its own definer and path.
drop function public.tick_reconcile();

create procedure public.tick_reconcile(p_commit boolean default true)
language plpgsql
as $$
-- 0137: THE hourly reconcile. Merchant upkeep first — npc_tend's steps, ONE TRANSACTION EACH: every
-- merchant (public.npc_tend_route), then the companies (public.npc_tend_houses), then the compactor
-- (public.npc_compact) — each under the hour's scope (public.npc_upkeep_scope: lock_timeout 2 s and
-- 0114's deadline, which runs from the start of the hour's pass). A step's row locks are held for
-- that step and released at its COMMIT, so the arrivals sweep waits for one merchant at most, never
-- for the hour. A step that fails is reported in the receipt and rolled back alone (0097).
-- THEN the invariants, in their own transaction, which take no row lock (plain reads): every
-- player's ledger reconciles, the sailing invariant, no client write grant. A failure RAISES.
-- p_commit = false runs the SAME steps in the caller's transaction, committing nothing (a proof inside
-- BEGIN … ROLLBACK: `call public.tick_reconcile(false)`); the job runs the default, true. Either way
-- the steps, their order and what they decide are the same — only where the transaction ends moves.
-- What a whole pass decides is npc_tend's (asserted, 0137 §4): the same walk, the same per-merchant
-- body, the same companies' passes, the same compactor — only the commits between them are new.
declare
  v_now      timestamptz := now();
  v_deadline timestamptz := clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds'));
  v_on       boolean := public.npc_traders_on();
  r          record;
  v_tend     jsonb := '{}'::jsonb;
  v_upkeep   jsonb := '{}'::jsonb;
  v_n        int := 0;
  v_grants   int;
begin
  for r in select * from public.npc_tend_roster() loop
    perform public.npc_upkeep_scope(v_deadline);
    begin
      v_tend := public.npc_tend_sum(v_tend, public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k));
    exception when others then
      v_upkeep := v_upkeep || jsonb_build_object('tend_error', sqlerrm);
    end;
    if p_commit then commit; end if;
  end loop;
  perform public.npc_upkeep_scope(v_deadline);
  begin
    v_tend := public.npc_tend_sum(v_tend, public.npc_tend_houses(v_now));
  exception when others then
    v_upkeep := v_upkeep || jsonb_build_object('tend_error', sqlerrm);
  end;
  if p_commit then commit; end if;
  v_upkeep := v_upkeep || jsonb_build_object('tend', jsonb_build_object('enabled', v_on) || public.npc_tend_sum(v_tend, '{}'::jsonb));
  perform public.npc_upkeep_scope(v_deadline);
  begin
    v_upkeep := v_upkeep || jsonb_build_object('compact', public.npc_compact(v_now));
  exception when others then
    v_upkeep := v_upkeep || jsonb_build_object('compact_error', sqlerrm);
  end;
  if p_commit then commit; end if;
  -- THE INVARIANTS (0010/0097, unchanged), on the world the upkeep left.
  for r in select id from public.players loop
    perform public.assert_ledger_reconciles(r.id);   -- raises on a mismatch
    v_n := v_n + 1;
  end loop;
  perform voyage.assert_sailing_invariant();
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception 'RECONCILE FAIL: % client write grant(s) have appeared since deploy', v_grants
      using errcode = '42501';
  end if;
  raise notice 'tick_reconcile: %', jsonb_build_object('players_checked', v_n, 'sailing_invariant', 'ok',
                                                       'client_write_grants', 0, 'merchant_upkeep', v_upkeep);
end $$;
comment on procedure public.tick_reconcile(boolean) is
  '0137: THE hourly reconcile (pg_cron byeharu-voyage:reconcile, CALL): merchant upkeep one '
  'transaction per merchant / the companies / the compactor, then the invariants. Server-only.';
revoke all on procedure public.tick_reconcile(boolean) from public, anon, authenticated;

-- THE JOB SAYS CALL. The job keeps its name, schedule, owner and active flag (0012 defined it,
-- 0078's clock_jobs() owns its activation; wind_the_clock() activates exactly this command).
do $cron$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.alter_job(j.jobid, command := 'call public.tick_reconcile()')
       from cron.job j where j.jobname = 'byeharu-voyage:reconcile';
  end if;
end $cron$;

-- ── 6. THE MARKET DRIFTS ONE HARBOUR AT A TIME ─────────────────────────────────────────────────
-- public.tick_market_drift keeps its body; it gains p_port (default null = every harbour, exactly
-- as before) through two hunks, one per UPDATE. A new signature cannot be a CREATE OR REPLACE, so
-- the old one is dropped and the new one made from the pre-image's text; its ACL is the pre-image's
-- (asserted). The drift job then calls a procedure that drifts each harbour in its own transaction,
-- so a port_goods row the drift writes is held for one harbour's update, never for the whole market.
create temp table hunks_0137 (n int, old text, new text) on commit drop;
insert into hunks_0137 values
(0,
$h$CREATE OR REPLACE FUNCTION public.tick_market_drift(p_now timestamp with time zone DEFAULT now())$h$,
$h$CREATE OR REPLACE FUNCTION public.tick_market_drift(p_now timestamp with time zone DEFAULT now(), p_port uuid DEFAULT NULL::uuid)$h$),
(1,
$h$   where pg.drift_slot < v_slot;$h$,
$h$   where pg.drift_slot < v_slot
     and (p_port is null or pg.port_id = p_port);   -- 0137: one harbour, when one is asked for$h$),
(2,
$h$   where pg.last_regen_day < v_day;$h$,
$h$   where pg.last_regen_day < v_day
     and (p_port is null or pg.port_id = p_port);   -- 0137: one harbour, when one is asked for$h$);

do $$
declare
  b     record;
  h     record;
  v_def text;
  v_rev text;
begin
  select * into b from defs_before_0137 where fn = 'public.tick_market_drift(timestamptz)';
  v_def := b.def;
  for h in select * from hunks_0137 order by n loop
    if pg_temp.occurs_0137(v_def, h.old) <> 1 then
      raise exception '0137 self-assert FAIL: tick_market_drift hunk % occurs % time(s), not once', h.n, pg_temp.occurs_0137(v_def, h.old);
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  -- THE PRE-IMAGE'S GRANTS, carried over grantee by grantee (a new function starts from the
  -- default privileges, which are not the same on every database)
  create temp table drift_grants_0137 on commit drop as
  select case when a.grantee = 0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end as grantee
    from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where p.oid = 'public.tick_market_drift(timestamptz)'::regprocedure and a.grantee <> p.proowner
     and a.privilege_type = 'EXECUTE';
  drop function public.tick_market_drift(timestamptz);
  execute v_def;
  revoke all on function public.tick_market_drift(timestamptz, uuid) from public, anon, authenticated, service_role;
  for h in select grantee from drift_grants_0137 order by grantee loop
    execute format('grant execute on function public.tick_market_drift(timestamptz, uuid) to %s', h.grantee);
  end loop;
  -- REVERSE TO ORIGINAL: the live body, its hunks undone, is the pre-image byte for byte
  v_rev := replace(pg_get_functiondef('public.tick_market_drift(timestamptz, uuid)'::regprocedure), E'\r', '');
  for h in select * from hunks_0137 order by n desc loop
    if pg_temp.occurs_0137(v_rev, h.new) <> 1 then
      raise exception '0137 self-assert FAIL: tick_market_drift''s new hunk % is not in the live body once', h.n;
    end if;
    v_rev := replace(v_rev, h.new, h.old);
  end loop;
  if v_rev <> b.def then
    raise exception '0137 self-assert FAIL: tick_market_drift does not reverse to its pre-image';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.tick_market_drift(timestamptz, uuid)'::regprocedure), '') <> b.acl
     or (select p.prosecdef from pg_proc p where p.oid = 'public.tick_market_drift(timestamptz, uuid)'::regprocedure) <> b.secdef
     or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'public.tick_market_drift(timestamptz, uuid)'::regprocedure) <> b.cfg
     or (select p.provolatile from pg_proc p where p.oid = 'public.tick_market_drift(timestamptz, uuid)'::regprocedure) <> b.vol then
    raise exception '0137 self-assert FAIL: tick_market_drift''s ACL, security, settings or volatility moved';
  end if;
end $$;

create procedure public.tick_market_drift_each_port()
language plpgsql
as $$
-- 0137: THE drift job (pg_cron byeharu-voyage:drift, CALL). public.tick_market_drift, one harbour
-- per transaction, every harbour in order, all at the one moment the job started (so every harbour
-- lands on the same drift slot and game-day the whole-market call would have). No SECURITY DEFINER,
-- no SET: a procedure that commits may carry neither; it runs as the job's owner.
declare
  v_now timestamptz := now();
  p     record;
  v_n   int := 0;
  v_r   int := 0;
  v_j   jsonb;
begin
  for p in select po.id from public.ports po order by po.id loop
    v_j := public.tick_market_drift(v_now, p.id);
    v_n := v_n + (v_j->>'drifted')::int;
    v_r := v_r + (v_j->>'regenerated')::int;
    commit;
  end loop;
  raise notice 'tick_market_drift_each_port: % drifted, % regenerated, slot %, game-day %', v_n, v_r, v_j->>'slot', v_j->>'game_day';
end $$;
comment on procedure public.tick_market_drift_each_port() is
  '0137: THE drift job (CALL): public.tick_market_drift one harbour per transaction, all at the job''s '
  'start time. Server-only.';
revoke all on procedure public.tick_market_drift_each_port() from public, anon, authenticated;

-- OLD AND NEW DRIFT THE SAME MARKET (one snapshot, each run rolled back). The noise term is
-- random() by design (0010), so the runs set drift_sigma = 0 inside themselves: the drift is then
-- theta × drift, clamped — the same arithmetic minus the draw — and the whole of port_goods can be
-- compared row for row. The draw's own text is untouched (the reverse-to-original check above).
-- old: the pre-image, whole market. new: the new body one harbour at a time, as the procedure runs it.
-- The moment is one drift slot and one game-day ahead, so every row drifts AND regenerates.
create or replace function pg_temp.drift_run_0137(p_old boolean, p_at timestamptz)
returns jsonb
language plpgsql
as $$
declare
  p      record;
  v_t0   timestamptz := clock_timestamp();
  v_n    int := 0;
  v_r    int := 0;
  v_j    jsonb;
  v_md5  text;
begin
  update public.world_config set value = to_jsonb(0) where key = 'drift_sigma';
  if p_old then
    v_j := pg_temp.tick_market_drift_old_0137(p_at);
    v_n := (v_j->>'drifted')::int;
    v_r := (v_j->>'regenerated')::int;
  else
    for p in select po.id from public.ports po order by po.id loop
      v_j := public.tick_market_drift(p_at, p.id);
      v_n := v_n + (v_j->>'drifted')::int;
      v_r := v_r + (v_j->>'regenerated')::int;
    end loop;
  end if;
  select md5(string_agg(row_to_json(g)::text, E'\n' order by g.port_id, g.good_id)) into v_md5 from public.port_goods g;
  return jsonb_build_object('drifted', v_n, 'regenerated', v_r, 'slot', v_j->>'slot', 'game_day', v_j->>'game_day',
                            'md5', v_md5, 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $$;

do $$
declare
  -- past every row's drift slot (a fixture may have wound some ahead of the clock), then one slot and one day more
  v_at  timestamptz := greatest(now(), to_timestamp(((select max(drift_slot) from public.port_goods) + 1) * public.wc_num('drift_slot_seconds')))
                       + make_interval(secs => (public.wc_num('drift_slot_seconds') + public.wc_num('game_day_seconds'))::double precision);
  v_old jsonb;
  v_new jsonb;
  v_rows int := (select count(*) from public.port_goods);
begin
  if (select count(*) from public.world_config where key = 'drift_sigma') <> 1 then
    raise exception '0137 self-assert FAIL: world_config has no drift_sigma row';
  end if;
  begin
    v_old := pg_temp.drift_run_0137(true, v_at);
    raise exception using errcode = 'ZX137', message = v_old::text;
  exception when sqlstate 'ZX137' then
    v_old := sqlerrm::jsonb;
  end;
  begin
    v_new := pg_temp.drift_run_0137(false, v_at);
    raise exception using errcode = 'ZX137', message = v_new::text;
  exception when sqlstate 'ZX137' then
    v_new := sqlerrm::jsonb;
  end;
  if (v_old - 'ms') is distinct from (v_new - 'ms') then
    raise exception '0137 self-assert FAIL: the market drifted differently harbour by harbour: old % / new %', v_old, v_new;
  end if;
  if (v_new->>'drifted')::int <> v_rows or (v_new->>'regenerated')::int <> v_rows then
    raise exception '0137 self-assert FAIL: the probe moment did not move every row (% drifted, % regenerated of %)',
      v_new->>'drifted', v_new->>'regenerated', v_rows;
  end if;
  raise notice '0137: the drift, old = new on one snapshot — % rows drifted and regenerated, whole market % ms, harbour by harbour % ms',
    v_rows, v_old->>'ms', v_new->>'ms';
end $$;

do $cron$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.alter_job(j.jobid, command := 'call public.tick_market_drift_each_port()')
       from cron.job j where j.jobname = 'byeharu-voyage:drift';
  end if;
end $cron$;

-- ── 7. THE RECEIPT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_cron text := 'pg_cron is not installed here (PGlite): no job to re-point';
  v_n    int;
begin
  -- the two procedures may COMMIT: neither is SECURITY DEFINER nor carries a SET (transaction control
  -- refuses both), and nobody but the owner can run them
  select count(*) into v_n from pg_proc p
   where p.oid in ('public.tick_reconcile(boolean)'::regprocedure, 'public.tick_market_drift_each_port()'::regprocedure)
     and p.prokind = 'p' and not p.prosecdef and p.proconfig is null
     and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute');
  if v_n <> 2 then
    raise exception '0137 self-assert FAIL: % of the 2 procedures are owner-only, invoker, SET-free procedures', v_n;
  end if;
  if to_regprocedure('public.tick_market_drift(timestamptz)') is not null then
    raise exception '0137 self-assert FAIL: the one-argument tick_market_drift survived beside the new one';
  end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'tick_reconcile') <> 1 then
    raise exception '0137 self-assert FAIL: tick_reconcile is not exactly one procedure';
  end if;
  -- THE JOBS RUN THE PROCEDURES, by name, with the schedule and active flag they had
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select count(*) from cron.job
                where (jobname = 'byeharu-voyage:reconcile' and command = 'call public.tick_reconcile()')
                   or (jobname = 'byeharu-voyage:drift' and command = 'call public.tick_market_drift_each_port()')$q$
      into v_n;
    if v_n <> 2 then
      raise exception '0137 self-assert FAIL: % of the 2 jobs (reconcile, drift) call their procedure', v_n;
    end if;
    execute $q$select count(*) from cron.job where command like '%tick_reconcile%' or command like '%tick_market_drift%'$q$ into v_n;
    if v_n <> 2 then
      raise exception '0137 self-assert FAIL: % jobs name the reconcile or the drift, not 2', v_n;
    end if;
    v_cron := 'byeharu-voyage:reconcile = call public.tick_reconcile(), byeharu-voyage:drift = call public.tick_market_drift_each_port() (schedule and active flag untouched; wind_the_clock() starts exactly these)';
  end if;
  raise notice '0137 self-assert ok: AN ARRIVAL NEVER WAITS FOR THE HOUR — the hourly reconcile and the drift commit step by step, nothing either decides moved. TEND: npc_tend cut into its walk (npc_tend_roster), one merchant (npc_tend_route), the companies (npc_tend_houses) and the receipt''s adder (npc_tend_sum), each slice byte-equal to the pre-image (the houses gate the one hunk), no line between the slices unaccounted for; old = new on one snapshot (receipts and end-state digest of every table). RECONCILE: a procedure, one transaction per merchant / the companies / the compactor under npc_upkeep_scope, then the invariants (no row lock). DRIFT: tick_market_drift(p_now, p_port) reverses to its pre-image, ACL carried; tick_market_drift_each_port commits one harbour at a time; old = new on one snapshot (drift_sigma 0 in the run). CRON: %.', v_cron;
end $$;
