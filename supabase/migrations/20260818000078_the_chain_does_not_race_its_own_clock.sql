-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0078 — THE CHAIN DOES NOT RACE ITS OWN CLOCK
--        the clock is DEFINED by the chain and STARTED by a person; two functions and a runbook
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, MEASURED IN CI RATHER THAN ARGUED ──────────────────────────────────────────────
-- The apply-proof workflow has failed twice, both times with the same error, and neither time for
-- anything the branch under test had changed:
--
--   run 33691161924  (2026-09-02, on `main` itself)
--   run 33695216552  (2026-09-02, on osn-0075-one-authority-for-a-gun-slot)
--
--     ERROR: deadlock detected (SQLSTATE 40P01)
--     Process 214 waits for ShareLock on transaction 1391; blocked by process 265.
--     Process 265 waits for ShareLock on transaction 1372; blocked by process 214.
--     At statement: 15
--     -- ── 6. THE MARKET FOLLOWS THE WORLD: port_goods re-derived for every (harbour, good) pair
--
-- That statement is migration 0041's. The other process is OUR OWN CLOCK. 0012 winds pg_cron at
-- the twelfth migration, so from that moment tick_market_drift runs every drift slot for the whole
-- rest of the apply — and twenty-nine migrations later 0041 rewrites public.port_goods, the very
-- table that tick updates. Two writers, opposite lock orders, one deadlock.
--
-- ── WHY IT IS WORTH A SLICE AND NOT A RE-RUN ───────────────────────────────────────────────────
-- Two reasons, and the second is the one that matters.
--
-- 1. A gate that fails at random teaches people to re-run reds instead of reading them, and that
--    is exactly how the one red that DOES matter gets waved through. docs/WORK_PLAN.md §6 already
--    lists "a red that was dice" among the things that have cost this project real sessions.
--
-- 2. THE SAME RACE IS WAITING ON PRODUCTION, WHERE THE ROWS ARE REAL. Production's chain head is
--    behind main, and four of the migrations not yet pushed write the drift tick's own tables:
--
--      0062 a_good_comes_from_somewhere                         port_goods
--      0065 the_catalogue_grows_and_no_good_sits_in_four_cities port_goods
--      0066 a_region_wants_what_it_wants                        port_goods
--      0071 the_price_moves_like_a_stock_and_says_nothing_else  price_history
--
--    On production the clock has been running since 0012 was applied. `supabase db push` there is
--    the same collision on live data, and a deadlock aborts the push PART-WAY THROUGH THE CHAIN.
--
-- ── WHICH SIDE GIVES WAY, AND WHY IT IS NOT A JUDGEMENT CALL ───────────────────────────────────
-- 0010's own header settled this long before the defect existed:
--
--     "The cron job is an OPTIMISATION FOR LEADERBOARD FRESHNESS, NOT A CORRECTNESS REQUIREMENT."
--     "If the ticks were load-bearing, a missed cron run would be a bug in the game rather than a
--      delay in a statistic."
--
-- Every read settles the fleets it reports (0009), so a database with a stopped clock is a CORRECT
-- database — only a fleet nobody is looking at goes stale. A rewrite of the world is not optional.
-- The clock is. So the clock yields, and it yields by simply not having been started yet.
--
-- ── THE FIX, WHICH IS ONE LINE IN 0012 AND A RULE ──────────────────────────────────────────────
-- 0012 now schedules its three jobs and immediately leaves them INACTIVE, and NO MIGRATION EVER
-- ACTIVATES THEM. That is the whole mechanism, and it has three properties worth stating:
--
--   * It fixes the class, not the instance. 0041 is not special; any future migration that
--     rewrites a table a tick writes was going to hit this. With the chain never running a tick,
--     there is nothing to race, whatever gets added later.
--   * It needed to live in 0012 rather than here. A guard written after 0041 cannot protect 0041,
--     and this file applies sixty-six migrations too late to help.
--   * It leaves the jobs DEFINED. A fresh database still carries the right three names on the
--     right cadence; starting them is one call, not a crontab pasted out of a migration.
--
-- ── WHAT THIS FILE ADDS: THE TWO CALLS THAT MAKE IT OPERABLE ───────────────────────────────────
-- A clock you cannot start is not a fix, it is an outage; and until now the cadence lived ONLY
-- inside 0012's inline DO block, so re-winding by hand meant copying a crontab out of a migration —
-- a SECOND answer to "how often", which is the one thing 0012's header went out of its way to
-- forbid. So:
--
--   public.wind_the_clock()    starts it, deriving the cadence the way 0012 does — from
--                              tick_cron_expression(wc_int('drift_slot_seconds')), never a literal.
--   public.unwind_the_clock()  stops it, and answers how many it stopped.
--
-- ── THE RUNBOOK (docs/DEPLOY_RUNBOOK.md carries it in full) ────────────────────────────────────
-- Applying a chain to a database whose clock is ALREADY RUNNING — which is exactly the state
-- production is in today:
--
--     1.  select public.unwind_the_clock();   -- SQL editor, before pushing
--     2.  supabase db push --linked
--     3.  select public.wind_the_clock();     -- this file is in the push, so it exists by step 3
--
-- Step 3 is deliberately NOT done by this migration. A migration that started the clock would be
-- the same defect wearing a later number: it would be the thing that starts a tick in the middle
-- of an apply, for every migration that ever lands after it.
--
-- ── AND THE NEW COST, STATED PLAINLY ───────────────────────────────────────────────────────────
-- A database built from scratch now ends with its clock stopped, and somebody has to start it.
-- That is a real cost and it is the honest trade: the alternative is an apply that deadlocks at
-- random. It is loud rather than silent — 0012 prints it on every single apply, this file prints
-- it again, and the world is correct in the meantime.
--
-- Changes NO tick body, NO cadence, NO game behaviour, and touches no table.
--
-- Depends ONLY on: 0001-0012 (tick_cron_expression, wc_int, drift_slot_seconds).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── STOP ───────────────────────────────────────────────────────────────────────────────────────
create or replace function public.unwind_the_clock()
returns integer
language plpgsql
as $fn$
declare
  v_n int := 0;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'unwind_the_clock: pg_cron is not installed here, so there was no clock to stop.';
    return 0;
  end if;
  -- Counted BEFORE, so the answer is how many were actually running rather than how many rows
  -- happened to be deleted. By the same name prefix 0012 uses, so a job an older chain left behind
  -- under a name this project no longer schedules is stopped too instead of running for ever.
  select count(*) into v_n from cron.job where jobname like 'byeharu-voyage:%' and active;
  perform cron.alter_job(jobid, active := false)
    from cron.job where jobname like 'byeharu-voyage:%' and active;
  raise notice 'unwind_the_clock: % running job(s) stopped. The world stays CORRECT with the clock stopped — every read settles the fleets it reports (0009); only a fleet nobody is looking at goes stale.', v_n;
  return v_n;
end $fn$;

comment on function public.unwind_the_clock() is
  'Stops every byeharu-voyage cron job and answers how many were running. Idempotent, and safe '
  'where pg_cron does not exist. Step 1 of the deploy runbook: a chain that rewrites port_goods '
  'must not race the drift tick that also writes it (0078).';

-- ── START ──────────────────────────────────────────────────────────────────────────────────────
create or replace function public.wind_the_clock()
returns text
language plpgsql
as $fn$
declare
  v_drift_expr text := public.tick_cron_expression(public.wc_int('drift_slot_seconds'));
  v_n          int;
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    return format('pg_cron is not available here, so there is no clock to start — as expected under PGlite. The market would have drifted on "%s".', v_drift_expr);
  end if;

  execute 'create extension if not exists pg_cron';

  -- Re-scheduled by NAME rather than merely re-activated, so this is also the repair for a
  -- database whose jobs were never created or whose cadence was left behind by an older knob:
  -- cron.schedule() on an existing name replaces it, and the expression is DERIVED every time.
  perform cron.schedule('byeharu-voyage:arrivals',  '* * * * *',  'select public.tick_arrivals()');
  perform cron.schedule('byeharu-voyage:drift',     v_drift_expr, 'select public.tick_market_drift()');
  perform cron.schedule('byeharu-voyage:reconcile', '7 * * * *',  'select public.tick_reconcile()');
  perform cron.alter_job(jobid, active := true)
    from cron.job where jobname like 'byeharu-voyage:%' and not active;

  select count(*) into v_n from cron.job where jobname like 'byeharu-voyage:%' and active;
  return format('%s job(s) running: arrivals every minute, drift on "%s" (from drift_slot_seconds = %s), reconcile hourly at :07.',
                v_n, v_drift_expr, public.wc_int('drift_slot_seconds'));
end $fn$;

comment on function public.wind_the_clock() is
  'THE authority for starting the clock, and the only place outside 0012''s scheduling block that '
  'names the three jobs. The cadence is DERIVED — tick_cron_expression(wc_int('
  '''drift_slot_seconds'')) — so the crontab and the knob cannot drift apart, which is the rule '
  '0012''s header set and this function inherits. Call it by hand on a database whose chain has '
  'finished applying: NO MIGRATION CALLS IT, because a migration that started the clock would be '
  'the very defect 0078 exists to remove. Step 3 of the deploy runbook.';

revoke all on function public.wind_the_clock()   from public, anon, authenticated;
revoke all on function public.unwind_the_clock() from public, anon, authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $blk$
declare
  v_have_cron boolean;
  v_expr      text := public.tick_cron_expression(public.wc_int('drift_slot_seconds'));
  v_n         int;
  v_active    int;
  v_drift     text;
  v_grants    int;
  v_said      text;
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_cron') into v_have_cron;

  if not v_have_cron then
    -- (a) UNDER PGlite it must apply cleanly, do nothing, and SAY it did nothing — never fail, and
    --     never claim a clock it has not got. The same discipline 0012 already holds itself to.
    v_said := public.wind_the_clock();
    if position('not available' in v_said) = 0 then
      raise exception '0078 self-assert FAIL: with no pg_cron, wind_the_clock said "%" instead of saying there was no clock to start', v_said;
    end if;
    if public.unwind_the_clock() <> 0 then
      raise exception '0078 self-assert FAIL: with no pg_cron, unwind_the_clock claimed it stopped something';
    end if;
    raise notice '0078 self-assert ok: THE CHAIN DOES NOT RACE ITS OWN CLOCK. No scheduler here, so the two runbook calls were exercised for their HONESTY rather than their effect: wind_the_clock refuses to claim a clock it has not got and unwind_the_clock stops 0 of them. The cadence is still derived and never literal — drift would be "%". The fix itself lives in 0012, which now leaves its three jobs INACTIVE so the fifty-eight migrations after it cannot deadlock against the market tick; nothing in this chain ever starts them. 0 client write grants: %',
      v_expr, (select count(*) from public.client_write_grants());
    return;
  end if;

  -- (b) THE STATE THE CHAIN MUST BE IN RIGHT NOW — this is the assert that is the actual fix.
  --     Three jobs defined by 0012, and NONE of them running, sixty-six migrations later.
  select count(*) into v_n      from cron.job where jobname like 'byeharu-voyage:%';
  select count(*) into v_active from cron.job where jobname like 'byeharu-voyage:%' and active;
  if v_n <> 3 then
    raise exception '0078 self-assert FAIL: % byeharu job(s) defined at the end of the chain, expected 3', v_n;
  end if;
  if v_active <> 0 then
    raise exception '0078 self-assert FAIL: % byeharu job(s) were RUNNING during this apply — the chain is racing its own clock again', v_active;
  end if;

  -- (c) STARTING REALLY STARTS, on the cadence the KNOB says rather than a literal.
  perform public.wind_the_clock();
  select count(*) into v_active from cron.job where jobname like 'byeharu-voyage:%' and active;
  if v_active <> 3 then
    raise exception '0078 self-assert FAIL: wind_the_clock left % job(s) running, expected 3', v_active;
  end if;
  select schedule into v_drift from cron.job where jobname = 'byeharu-voyage:drift';
  if v_drift is distinct from v_expr then
    raise exception '0078 self-assert FAIL: the market is scheduled on "%" but drift_slot_seconds says "%" — the crontab and the knob disagree', v_drift, v_expr;
  end if;

  -- (d) STOPPING REALLY STOPS. Checked on the TABLE as well as on the return value, because a
  --     function that answers 3 and leaves 3 running is precisely the failure this must not have.
  if public.unwind_the_clock() <> 3 then
    raise exception '0078 self-assert FAIL: unwind_the_clock did not report stopping the 3 jobs it stopped';
  end if;
  select count(*) into v_active from cron.job where jobname like 'byeharu-voyage:%' and active;
  if v_active <> 0 then
    raise exception '0078 self-assert FAIL: % job(s) still running after unwind_the_clock', v_active;
  end if;
  -- and it did not DELETE them: a stopped clock must still be a defined clock, or step 3 of the
  -- runbook would be recreating jobs rather than restarting them.
  select count(*) into v_n from cron.job where jobname like 'byeharu-voyage:%';
  if v_n <> 3 then
    raise exception '0078 self-assert FAIL: unwind_the_clock left % job(s) defined, expected 3 — it unscheduled instead of stopping', v_n;
  end if;

  -- (e) IDEMPOTENT BOTH WAYS. The runbook gets run twice by a careful person and half-run by an
  --     interrupted one, so neither call may depend on being the first.
  if public.unwind_the_clock() <> 0 then
    raise exception '0078 self-assert FAIL: a second unwind claimed to stop jobs that were already stopped';
  end if;
  perform public.wind_the_clock();
  perform public.wind_the_clock();
  select count(*) into v_n      from cron.job where jobname like 'byeharu-voyage:%';
  select count(*) into v_active from cron.job where jobname like 'byeharu-voyage:%' and active;
  if v_n <> 3 or v_active <> 3 then
    raise exception '0078 self-assert FAIL: winding twice left % job(s), % running — expected 3 and 3', v_n, v_active;
  end if;

  -- LEAVE THE CHAIN AS IT FOUND IT. The asserts above are the only thing that has run this clock,
  -- and a migration that finished with the clock started would hand the same defect to whatever
  -- lands after it.
  perform public.unwind_the_clock();
  select count(*) into v_active from cron.job where jobname like 'byeharu-voyage:%' and active;
  if v_active <> 0 then
    raise exception '0078 self-assert FAIL: this migration left % job(s) running', v_active;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0078 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0078 self-assert ok: THE CHAIN DOES NOT RACE ITS OWN CLOCK. The apply-proof died twice on "ERROR: deadlock detected" inside 0041''s port_goods re-derive (runs 33691161924 on main and 33695216552 on a branch) — not a defect in either branch, but our OWN drift tick, wound by 0012 at the twelfth migration and then racing the fifty-eight that follow it; the same race was waiting on production, where 0062/0065/0066/0071 are unpushed and every one writes the tick''s own tables. The clock yields because 0010''s header says it is the optional one. PROVEN ON A REAL SCHEDULER, at the end of the whole chain: 3 jobs are DEFINED and 0 are RUNNING — which is the fix itself, asserted where it matters rather than beside the line that makes it true. wind_the_clock then starts exactly 3 and the drift job''s cadence EQUALS tick_cron_expression(drift_slot_seconds) rather than a literal; unwind_the_clock answers 3, leaves 0 running and still leaves 3 DEFINED (it stops a clock, it does not delete one); and both are idempotent — a second unwind stops 0, a second wind still leaves 3. This file leaves the clock STOPPED on purpose: no migration may start it, or it becomes the very thing it fixes. Start it with select public.wind_the_clock(). 0 client write grants: %',
    v_grants;
end $blk$;
