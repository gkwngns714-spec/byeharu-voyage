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
-- ── THE CLOCK IS FIVE JOBS, NOT THREE — AND THIS FILE'S OWN ASSERT IS WHAT FOUND THAT ─────────
-- The first cut of this migration guarded 0012 alone and asserted "3 jobs defined". It failed in
-- CI with `0078 self-assert FAIL: 5 byeharu job(s) defined at the end of the chain, expected 3`,
-- which is the assert doing precisely its job. Two more scheduling sites apply AFTER 0012:
--
--   0013 `byeharu-voyage:price-snapshot`  -> tick_price_snapshot, which writes price_history
--   0026 `byeharu-voyage:buff-calendar`   -> tick_buff_calendar
--
-- and `price_history` is rewritten by **0071**. So there was a SECOND live race, on a different
-- table, that guarding 0012 alone would have left open while looking fixed. Recorded here because
-- a fix that looks complete is more dangerous than one that is obviously partial.
--
-- There is also an OLDER naming scheme. 0010 schedules `voyage-tick-arrivals` and two siblings,
-- and 0012's cleanup matches only `byeharu-voyage:%` — so it cannot see them. On a from-scratch
-- chain they never exist (pg_cron is not installed until 0012, and 0010 checks `pg_extension`), but
-- on any database where pg_cron was ALREADY installed when 0010 applied, those three were scheduled
-- and NOTHING has ever removed them. 0012's own comment worries about exactly that case and then
-- cannot match it. public.clock_jobs() matches both schemes, so neither this file nor the runbook
-- can miss half the clock.
--
-- ── THE FIX, WHICH IS ONE STATEMENT PER SCHEDULING SITE AND A RULE ─────────────────────────────
-- 0012, 0013 and 0026 each now schedule their jobs and immediately leave them INACTIVE, and NO
-- MIGRATION EVER ACTIVATES THEM. That is the whole mechanism, and it has three properties worth
-- stating:
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
--   public.clock_jobs()        THE one answer to "which jobs are ours" — both naming schemes.
--   public.wind_the_clock()    starts them by ACTIVATING what the chain defined. It does NOT
--                              re-schedule: five jobs are owned by three different migrations, each
--                              deriving its own cadence from its own knob, and a wind that
--                              re-scheduled from literals here would be a second answer to "how
--                              often" AND would silently drop any job it had not been told about.
--   public.unwind_the_clock()  stops them, and answers how many were running.
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

-- ── THE ONE PREDICATE FOR "A JOB OF OURS" ──────────────────────────────────────────────────────
-- Two naming schemes exist, and both are ours. 0010 scheduled `voyage-tick-arrivals` and two
-- siblings; 0012 replaced them with the `byeharu-voyage:` prefix but its cleanup matches only that
-- prefix — so on any database where pg_cron was ALREADY installed when 0010 applied, 0010's three
-- jobs were scheduled and nothing has ever removed them. 0012's own comment worries about exactly
-- this ("an older chain may have left a job under a name this file no longer uses, and that one
-- would keep running for ever") and then cannot see them. On a from-scratch chain they never exist,
-- because pg_cron is not installed until 0012 — which is why this went unnoticed.
--
-- plpgsql AND DYNAMIC, deliberately. A `language sql` body is parsed and its relations resolved at
-- CREATE time, so naming cron.job directly makes this file fail to apply under PGlite — where the
-- cron schema does not exist at all — with `relation "cron.job" does not exist`. Observed on the
-- first run, not predicted. plpgsql defers the plan to first execution, and the extension check
-- means that execution never happens where the table is absent: no scheduler, no jobs, empty set.
create or replace function public.clock_jobs()
returns table (jobid bigint, jobname text, schedule text, active boolean)
language plpgsql
stable
as $fn$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return;  -- no scheduler here, so the game owns no jobs. An empty set, never an error.
  end if;
  return query execute
    'select j.jobid, j.jobname, j.schedule, j.active from cron.job j
      where j.jobname like ''byeharu-voyage:%'' or j.jobname like ''voyage-tick-%''';
end $fn$;

comment on function public.clock_jobs() is
  'THE one answer to "which cron jobs are this game''s". Matches BOTH naming schemes: 0012''s '
  '''byeharu-voyage:'' prefix and 0010''s older ''voyage-tick-'' one, which 0012''s cleanup cannot '
  'see and which survives on any database where pg_cron was installed before 0010 applied.';

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
  -- Counted BEFORE, so the answer is how many were actually RUNNING rather than how many rows
  -- happened to be touched.
  select count(*) into v_n from public.clock_jobs() where active;
  perform cron.alter_job(j.jobid, active := false) from public.clock_jobs() j where j.active;
  raise notice 'unwind_the_clock: % running job(s) stopped. The world stays CORRECT with the clock stopped — every read settles the fleets it reports (0009); only a fleet nobody is looking at goes stale.', v_n;
  return v_n;
end $fn$;

comment on function public.unwind_the_clock() is
  'Stops every job public.clock_jobs() names and answers how many were running. Idempotent, and '
  'safe where pg_cron does not exist. Step 1 of the deploy runbook: a chain that rewrites '
  'port_goods or price_history must not race the ticks that also write them (0078).';

-- ── START ──────────────────────────────────────────────────────────────────────────────────────
create or replace function public.wind_the_clock()
returns text
language plpgsql
as $fn$
declare
  v_n int;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron is not installed here, so there is no clock to start — as expected under PGlite.';
  end if;

  -- IT ACTIVATES WHAT IS DEFINED; IT DOES NOT RE-SCHEDULE.
  --
  -- This is the whole reason the cadences are not repeated in this file. Five jobs exist and three
  -- different migrations own them — 0012 (arrivals, drift, reconcile), 0013 (price-snapshot) and
  -- 0026 (buff-calendar) — and each derives its own expression from its own knob. A wind_the_clock
  -- that re-scheduled from literals here would be a SECOND answer to "how often", which is the one
  -- thing 0012's header went out of its way to forbid, and it would silently drop any job it had
  -- not been told about. Activating what the chain defined keeps every migration the single
  -- authority for its own job, and covers jobs added after this file without touching it.
  perform cron.alter_job(j.jobid, active := true) from public.clock_jobs() j where not j.active;
  select count(*) into v_n from public.clock_jobs() where active;
  return format('%s job(s) running: %s.', v_n,
                (select string_agg(j.jobname || ' on "' || j.schedule || '"', ', ' order by j.jobname)
                   from public.clock_jobs() j where j.active));
end $fn$;

comment on function public.wind_the_clock() is
  'Starts every job public.clock_jobs() names, by ACTIVATING what the chain defined rather than '
  're-scheduling it — so the cadence stays owned by the migration that authored each job and this '
  'function is not a second answer to "how often". Call it by hand on a database whose chain has '
  'finished applying: NO MIGRATION CALLS IT, because a migration that started the clock would be '
  'the very defect 0078 exists to remove. Step 3 of the deploy runbook.';

revoke all on function public.clock_jobs()       from public, anon, authenticated;
revoke all on function public.wind_the_clock()   from public, anon, authenticated;
revoke all on function public.unwind_the_clock() from public, anon, authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_have_cron boolean;
  v_n         int;
  v_active    int;
  v_names     text;
  v_grants    int;
  v_said      text;
  -- The clock, named. Asserting a COUNT alone would have passed the day a sixth job was added and
  -- a fifth forgotten; and it was a count that first said "5, expected 3" and found 0013's and
  -- 0026's jobs, which this file had missed. So the names are the assert.
  c_expected constant text := 'byeharu-voyage:arrivals, byeharu-voyage:buff-calendar, byeharu-voyage:drift, byeharu-voyage:price-snapshot, byeharu-voyage:reconcile';
begin
  select exists (select 1 from pg_extension where extname = 'pg_cron') into v_have_cron;

  if not v_have_cron then
    -- (a) UNDER PGlite it must apply cleanly, do nothing, and SAY it did nothing — never fail, and
    --     never claim a clock it has not got. The same discipline 0012 already holds itself to.
    v_said := public.wind_the_clock();
    if position('not installed' in v_said) = 0 then
      raise exception '0078 self-assert FAIL: with no pg_cron, wind_the_clock said "%" instead of saying there was no clock to start', v_said;
    end if;
    if public.unwind_the_clock() <> 0 then
      raise exception '0078 self-assert FAIL: with no pg_cron, unwind_the_clock claimed it stopped something';
    end if;
    raise notice '0078 self-assert ok: THE CHAIN DOES NOT RACE ITS OWN CLOCK. No scheduler here, so the two runbook calls were exercised for their HONESTY rather than their effect: neither claims a clock it has not got. The fix itself lives in the three files that SCHEDULE — 0012, 0013 and 0026 — each of which now leaves its job INACTIVE, so the migrations that follow cannot deadlock against a tick; nothing in this chain ever starts one. 0 client write grants: %',
      (select count(*) from public.client_write_grants());
    return;
  end if;

  -- (b) THE STATE THE CHAIN MUST BE IN RIGHT NOW. This is the fix itself, asserted at the end of
  --     the whole chain rather than beside the lines that make it true — the only place it means
  --     anything. BY NAME, not by count: the first version of this assert counted 3 and the real
  --     answer was 5, which is how 0013's price-snapshot and 0026's buff-calendar were found. A
  --     count would go green again the day someone adds a sixth job and forgets the rule.
  select count(*), count(*) filter (where active),
         string_agg(jobname, ', ' order by jobname)
    into v_n, v_active, v_names
    from public.clock_jobs();

  if v_names is distinct from c_expected then
    raise exception '0078 self-assert FAIL: the clock is [%] but this file was written against [%] — a job was added, renamed or lost, and whoever did it must decide whether it may run during an apply', v_names, c_expected;
  end if;
  if v_active <> 0 then
    raise exception '0078 self-assert FAIL: % of the % job(s) were RUNNING during this apply — the chain is racing its own clock again', v_active, v_n;
  end if;

  -- (c) STARTING REALLY STARTS — all five, not the three this file happens to remember.
  perform public.wind_the_clock();
  select count(*) filter (where active) into v_active from public.clock_jobs();
  if v_active <> v_n then
    raise exception '0078 self-assert FAIL: wind_the_clock left % of % job(s) running', v_active, v_n;
  end if;

  -- (d) STOPPING REALLY STOPS. Checked on the TABLE as well as on the return value, because a
  --     function that answers 5 and leaves 5 running is precisely the failure this must not have.
  if public.unwind_the_clock() <> v_n then
    raise exception '0078 self-assert FAIL: unwind_the_clock did not report stopping the % jobs it stopped', v_n;
  end if;
  select count(*) filter (where active) into v_active from public.clock_jobs();
  if v_active <> 0 then
    raise exception '0078 self-assert FAIL: % job(s) still running after unwind_the_clock', v_active;
  end if;
  -- and it did not DELETE them: a stopped clock must still be a defined clock, or step 3 of the
  -- runbook would be recreating jobs rather than restarting them — and the cadences would be lost.
  select count(*) into v_active from public.clock_jobs();
  if v_active <> v_n then
    raise exception '0078 self-assert FAIL: unwind_the_clock left % job(s) defined, expected % — it unscheduled instead of stopping', v_active, v_n;
  end if;

  -- (e) IDEMPOTENT BOTH WAYS. A runbook gets run twice by a careful person and half-run by an
  --     interrupted one, so neither call may depend on being the first.
  if public.unwind_the_clock() <> 0 then
    raise exception '0078 self-assert FAIL: a second unwind claimed to stop jobs that were already stopped';
  end if;
  perform public.wind_the_clock();
  perform public.wind_the_clock();
  select count(*), count(*) filter (where active) into v_n, v_active from public.clock_jobs();
  if v_active <> v_n then
    raise exception '0078 self-assert FAIL: winding twice left % of % running', v_active, v_n;
  end if;

  -- LEAVE THE CHAIN AS IT FOUND IT. The asserts above are the only thing that has ever run this
  -- clock, and a migration that finished with it started would hand the same defect to whatever
  -- lands after it.
  perform public.unwind_the_clock();
  select count(*) filter (where active) into v_active from public.clock_jobs();
  if v_active <> 0 then
    raise exception '0078 self-assert FAIL: this migration left % job(s) running', v_active;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0078 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0078 self-assert ok: THE CHAIN DOES NOT RACE ITS OWN CLOCK. The apply-proof died twice on "ERROR: deadlock detected" inside 0041''s port_goods re-derive (runs 33691161924 on main and 33695216552 on a branch) — not a defect in either branch, but our OWN ticks, wound mid-chain and then racing the migrations that follow. THE CLOCK IS FIVE JOBS, NOT THREE: 0012 winds arrivals, drift and reconcile, and 0013 and 0026 then add price-snapshot and buff-calendar AFTER it — and tick_price_snapshot writes price_history, which 0071 rewrites, so that was a second live race. This file''s own first assert is what found them, by counting 5 where it expected 3; it now asserts the NAMES, so a sixth job cannot go green by arithmetic. All three scheduling files leave their jobs INACTIVE and nothing in the chain starts one. PROVEN at the end of the whole chain on a real scheduler: % jobs defined, [%], 0 running. wind_the_clock then starts every one — by ACTIVATING what the chain defined, never re-scheduling, so each migration stays the single authority for its own cadence — and unwind_the_clock answers %, leaves 0 running and still leaves % DEFINED (it stops a clock, it does not delete one); both idempotent. Start it with select public.wind_the_clock(). 0 client write grants: %',
    v_n, v_names, v_n, v_n, v_grants;
end $$;
