-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0012 — THE CLOCK IS WOUND: when the ticks run, and nothing else
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT THIS SECTION OWNS, AND WHAT IT MUST NEVER TOUCH ───────────────────────────────────────
-- 0010 owns the TICKS — what `tick_arrivals`, `tick_market_drift` and `tick_reconcile` do, that
-- each is idempotent, and the proof of it. This file owns exactly one other thing: WHEN THEY RUN.
--
-- It therefore defines no tick, redefines no tick, and changes no tick's body. If a cadence ever
-- needs a tick to behave differently, the tick changes in its own file and this one still only
-- says when. Two files, two questions, no overlap.
--
-- ── THE CADENCE IS DERIVED, NOT RESTATED ───────────────────────────────────────────────────────
-- `drift_slot_seconds` (0010) already answers "how often does the market step" — it is what makes
-- the Ornstein-Uhlenbeck walk idempotent, because a row already stepped in this slot is skipped.
-- Writing `*/10 * * * *` here would be a SECOND answer to that question, and the day somebody
-- retunes the knob the cron would keep the old rhythm and nobody would know why the market felt
-- wrong. So the cron expression is COMPUTED from the knob, and the self-assert below proves the
-- two agree.
--
-- ── IT SCHEDULES THE CLOCK; IT DOES NOT START IT (added by 0078) ───────────────────────────────
-- This file runs at the TWELFTH migration, and everything it schedules would tick for the rest of
-- the apply — including underneath 0041, which rewrites public.port_goods while tick_market_drift
-- is updating it. That deadlocked the apply-proof twice. So the three jobs are scheduled and then
-- left INACTIVE, and no migration ever activates them: public.wind_the_clock() (0078) is the one
-- deliberate call that starts a clock, on a database whose chain has finished applying.
--
-- The fix has to live HERE, in the file that winds the clock, because a guard written after 0041
-- could not have protected 0041. See 0078's header for the runs, the error and the argument.
--
-- Arrivals run every minute: a voyage-day is three real minutes (TIME_COMPRESSION 480), so a
-- minute is fine enough that a fleet nobody is watching is never more than a third of a day stale.
-- Reconciliation runs hourly and OFF the hour, so the read-only audit never lands on the same
-- second as the two writers.
--
-- ── IT IS STILL AN OPTIMISATION (DESIGN §D.2) ──────────────────────────────────────────────────
-- 0010's header states the rule this file must not quietly overturn: "the cron job is an
-- OPTIMISATION FOR LEADERBOARD FRESHNESS, NOT A CORRECTNESS REQUIREMENT." Every read settles the
-- fleets it reports (0009), so a missed cron run delays a statistic and never corrupts a game. A
-- world with no scheduler at all is still a correct world — which is what makes the graceful path
-- below honest rather than a shrug.
--
-- ── WHERE THERE IS NO pg_cron ──────────────────────────────────────────────────────────────────
-- The chain applies in a player's browser under PGlite, where pg_cron does not exist and cannot.
-- 0010 already prints that fact on every local apply. This file must therefore APPLY CLEANLY with
-- no scheduler, schedule nothing, and say so — never fail, and never pretend it scheduled anything.
--
-- Depends ONLY on: 0001-0011.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── The cadence, as one function, so the schedule and the assert read the SAME answer ──────────
create or replace function public.tick_cron_expression(p_seconds int)
returns text
language plpgsql
immutable
as $$
begin
  -- pg_cron's finest granularity is the minute. A slot shorter than that cannot be expressed, and
  -- one that does not divide the hour would drift against the wall clock every hour.
  if p_seconds < 60 or p_seconds % 60 <> 0 then
    raise exception 'a tick slot of % second(s) cannot be a cron schedule: it must be whole minutes', p_seconds;
  end if;
  if (p_seconds / 60) > 59 or 60 % (p_seconds / 60) <> 0 then
    raise exception 'a tick slot of % minute(s) does not divide the hour evenly', p_seconds / 60;
  end if;
  return case when p_seconds = 60 then '* * * * *'
              else '*/' || (p_seconds / 60)::text || ' * * * *' end;
end $$;

comment on function public.tick_cron_expression(int) is
  'THE ONE translation from a tick slot in seconds to a cron expression. The schedule below and '
  'the self-assert both call it, so "how often" is answered once — by world_config, never by a '
  'literal in a crontab.';

revoke all on function public.tick_cron_expression(int) from public, anon, authenticated;

-- ── Wind it ────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_drift_expr text := public.tick_cron_expression(public.wc_int('drift_slot_seconds'));
  v_have_cron  boolean;
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_cron') into v_have_cron;

  if not v_have_cron then
    raise notice '0012: pg_cron is not available here, so NOTHING was scheduled — as expected under PGlite. Every read still settles the fleets it reports (0009), so the world stays correct; only a fleet nobody is looking at goes stale. The market would have drifted on "%".', v_drift_expr;
    return;
  end if;

  execute 'create extension if not exists pg_cron';

  -- Re-applying the chain must not leave two schedulers walking the same market. Unschedule by
  -- NAME first: cron.schedule() on an existing name replaces it, but an older chain may have left
  -- a job under a name this file no longer uses, and that one would keep running for ever.
  perform cron.unschedule(jobname) from cron.job where jobname like 'byeharu-voyage:%';

  perform cron.schedule('byeharu-voyage:arrivals',  '* * * * *',  'select public.tick_arrivals()');
  perform cron.schedule('byeharu-voyage:drift',     v_drift_expr, 'select public.tick_market_drift()');
  perform cron.schedule('byeharu-voyage:reconcile', '7 * * * *',  'select public.tick_reconcile()');

  -- 0078: DEFINED, BUT NOT RUNNING YET — and this is the whole of the deadlock fix.
  --
  -- This block runs at the TWELFTH migration. Everything scheduled here starts ticking
  -- immediately, and then fifty-eight more migrations apply underneath it — including 0041, which
  -- rewrites public.port_goods, the very table tick_market_drift updates. That is two writers in
  -- opposite lock orders, and it has killed the apply-proof twice with
  -- "ERROR: deadlock detected (SQLSTATE 40P01)" (runs 33691161924 on main, 33695216552 on a
  -- branch), neither time for anything the branch under test had changed.
  --
  -- 0010's header is what decides which side gives way, and it was written long before this
  -- defect: "The cron job is an OPTIMISATION FOR LEADERBOARD FRESHNESS, NOT A CORRECTNESS
  -- REQUIREMENT." Every read settles the fleets it reports (0009), so a database with a stopped
  -- clock is a CORRECT database. A rewrite of the world is not optional; the clock is.
  --
  -- So the chain leaves the clock DEFINED and INACTIVE, and no migration ever starts it. Starting
  -- it is public.wind_the_clock() (0078) — one deliberate call on a database whose chain has
  -- finished applying. That is why the fix lives here rather than in a later file: a guard added
  -- after 0041 could not protect 0041.
  perform cron.alter_job(jobid, active := false)
    from cron.job where jobname like 'byeharu-voyage:%';

  raise notice '0012: pg_cron present — arrivals every minute, drift on "%" (from drift_slot_seconds = %), reconcile hourly at :07 — all three SCHEDULED BUT INACTIVE, so the rest of the chain cannot deadlock against its own market tick (0078). The world is correct without them; start them with select public.wind_the_clock().',
    v_drift_expr, public.wc_int('drift_slot_seconds');
end $$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_have_cron boolean;
  v_expr      text := public.tick_cron_expression(public.wc_int('drift_slot_seconds'));
  v_n         int;
  v_drift     text;
  v_arrivals  text;
  v_grants    int;
  v_exposed   int;
  v_bad       boolean := false;
begin
  -- The cadence function is provable with or without a scheduler, so it is asserted either way.
  if public.tick_cron_expression(60)  <> '* * * * *'    then raise exception '0012 self-assert FAIL: 60s should be every minute, got %', public.tick_cron_expression(60); end if;
  if public.tick_cron_expression(600) <> '*/10 * * * *' then raise exception '0012 self-assert FAIL: 600s should be */10, got %', public.tick_cron_expression(600); end if;
  -- POSITIVE CONTROLS: a slot that cannot be a schedule must be REFUSED, not rounded.
  begin perform public.tick_cron_expression(30);   exception when others then v_bad := true; end;
  if not v_bad then raise exception '0012 self-assert FAIL: a 30-second slot was accepted as a cron schedule'; end if;
  v_bad := false;
  begin perform public.tick_cron_expression(2100); exception when others then v_bad := true; end;
  if not v_bad then raise exception '0012 self-assert FAIL: a 35-minute slot does not divide the hour and was accepted'; end if;

  select exists (select 1 from pg_available_extensions where name = 'pg_cron') into v_have_cron;

  if not v_have_cron then
    raise notice '0012 self-assert ok: no scheduler here — tick_cron_expression maps 60s -> "* * * * *" and 600s -> "*/10 * * * *", and REFUSED both a 30-second slot and a 35-minute one; pg_cron is absent so no job was scheduled and none was claimed. 0 client write grants: %',
      (select count(*) from public.client_write_grants());
    return;
  end if;

  select count(*) into v_n from cron.job where jobname like 'byeharu-voyage:%';
  if v_n <> 3 then raise exception '0012 self-assert FAIL: % scheduled job(s), expected 3', v_n; end if;

  select schedule into v_drift    from cron.job where jobname = 'byeharu-voyage:drift';
  select schedule into v_arrivals from cron.job where jobname = 'byeharu-voyage:arrivals';
  if v_drift is distinct from v_expr then
    raise exception '0012 self-assert FAIL: the market is scheduled on "%" but drift_slot_seconds says "%" — the crontab and the knob disagree', v_drift, v_expr;
  end if;
  if v_arrivals <> '* * * * *' then
    raise exception '0012 self-assert FAIL: arrivals are scheduled on "%", expected every minute', v_arrivals;
  end if;

  -- 0078: AND NONE OF THEM IS RUNNING. Without this the deactivation above could silently stop
  -- working — a renamed pg_cron column, a changed alter_job signature — and the only symptom would
  -- be a deadlock in CI once every twenty runs, which is the symptom that gets blamed on a branch.
  select count(*) into v_n from cron.job where jobname like 'byeharu-voyage:%' and active;
  if v_n <> 0 then
    raise exception '0012 self-assert FAIL: % byeharu job(s) are ACTIVE during the chain — the rest of the apply can now deadlock against the market tick', v_n;
  end if;

  -- The scheduler is the SERVER's. A client that could read or write cron.job could read the
  -- world's rhythm, or stop it.
  select count(*) into v_exposed from information_schema.role_table_grants
   where table_schema = 'cron' and grantee in ('anon', 'authenticated');
  if v_exposed > 0 then
    raise exception '0012 self-assert FAIL: % grant(s) on the cron schema reach a client role', v_exposed;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then raise exception '0012 self-assert FAIL: % client write grant(s)', v_grants; end if;

  raise notice '0012 self-assert ok: 3 jobs DEFINED and 0 of them RUNNING — arrivals on "%", drift on "%" which MATCHES drift_slot_seconds, reconcile hourly, all three left INACTIVE so the fifty-eight migrations that apply after this one cannot deadlock against our own market tick (0078; it killed the apply-proof twice on 0041''s port_goods re-derive). The world is CORRECT with the clock stopped — every read settles the fleets it reports (0009) — and select public.wind_the_clock() is the one deliberate call that starts it. tick_cron_expression REFUSED a 30-second slot and a 35-minute one; no client role holds a grant in the cron schema; 0 client write grants',
    v_arrivals, v_drift;
end $$;
