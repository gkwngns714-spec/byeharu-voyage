-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0300 — THE HOUR ENDS IN TIME   (the hourly reconcile stops starting steps before its wall, so its invariants pass ALWAYS runs)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY (prod, read-only, head 0294, 2026-11-01 / 02) ──────────────────────────────────────────
-- `call public.tick_reconcile()` (pg_cron byeharu-voyage:reconcile, minute :07; a PROCEDURE that COMMITs between steps) FAILS in the busy
-- hours. cron.job_run_details keeps two days: 61 runs, 10-30 05:07 .. 11-01 18:07 UTC. 28 succeeded (42-110 s); 33 failed: 31 with
-- `canceling statement due to statement timeout` at 120.0-121.4 s (statement_timeout 120000 ms from postgresql.conf, no role override: the
-- database's wall for the WHOLE call) and 2 with `job canceled`. Of the 31, 29 sat inside `SELECT public.hold_the_quay()` (the merchants'
-- loop and the companies' loop), 1 right after a COMMIT and 1 inside the gift roster's query. It succeeds only in the quiet hours (01-09 UTC).
-- public.reconcile_runs (7 days of receipts) shows how it got there: healthy until 2026-10-29 19:07 (total median 19.0 s, p90 23.1 s);
-- from 10-29 20:07 the hours that finished took a median 71.4 s (tend 29-84 s, companies 4-41 s, check 0.2-1.3 s).
-- THE INVARIANTS PASS RUNS LAST (every player's ledger reconciles, voyage.assert_sailing_invariant, no client write grant), so in every
-- failing hour it never ran: the world went unchecked for about two days. That is the defect - the safety net reserves no room for itself.
--
-- ── THE MECHANISM (read in the live bodies, not assumed) ───────────────────────────────────────
--  * public.hold_the_quay() = pg_advisory_xact_lock(hashtextextended('byeharu.quay_or_upkeep', 249)), shared with the arrivals beat. It is
--    taken BEFORE public.npc_upkeep_scope(), which sets the 2 s lock_timeout, so the wait has no bound but the wall. The beat is I/O-bound now
--    (2-12 s, was 0.7 s): each step queues for the quay a whole beat (the kept receipts: 15-50 s of quay wait over ~800 steps; one wait up to 9 s).
--  * The hour's deadline (v_deadline = start + npc_upkeep_budget_seconds, 60 s) is read by public.npc_upkeep_spent() - from public.npc_tend_route,
--    public.npc_invest_one and public.npc_plan - that is, INSIDE a step, after its quay. So once the deadline has passed the loop still queues
--    for the quay for EVERY remaining merchant, only to defer her. The companies' step opens a second 60 s (v_cdl, 0143) on top:
--    60 + 60 + the check can exceed 120 s by construction.
--  * public.capital_gift_one never reads the deadline (no npc_upkeep_spent in it): the gift loop has NO budget, v_cdl does not end it.
--
-- ── THE FIX (three parts; nothing a step DECIDES moves) ────────────────────────────────────────
--  1. In the three loops, BEFORE the quay is asked for: past the loop's end the step is counted deferred - public.npc_tend_sum(v_tend,
--     {deferred 1}), the one place a receipt is added up, and exactly what public.npc_invest_one answers past the deadline - and skipped.
--     The end of the merchants' loop is v_deadline; of the investment loop v_cdl; of the gift loop only the hard end (it has no budget).
--  2. ONE hard end for the whole upkeep: v_stop = public.upkeep_hard_end(statement_timestamp(), statement_timeout from pg_settings) =
--     the statement's start + its wall - a 25 s reserve (95 s of 120). statement_timeout 0 (unlimited) = no hard end. Each loop ends at
--     least(its own deadline, v_stop), so the invariants pass always starts with room.
--  3. The receipt (public.reconcile_runs.receipt) gains `skipped` {tend, companies} - the steps skipped past an end - and `hard_end_s`
--     (the hard end, seconds after the start; null = none).
--  p_commit = false never takes the quay and is UNCHANGED: every new test is `p_commit and ...`. When there is time the new condition is
--  false and the loop is the old loop. The invariants pass, the phases and their order, the knobs, the cron job and the schedule are untouched.
--
-- ── WHAT A SKIPPED MERCHANT MISSES, SAID PLAINLY ───────────────────────────────────────────────
-- Past the end her step would have done only its UNCONDITIONAL light work (a tow, a dark pause, a laid-up note, the off-route re-assign) -
-- the dear work (plan, start, resume, clear) was already deferred by 0114. That light work now waits for the next hour, in which the roster
-- (the route written longest ago first) reaches her sooner than the merchants written since. `deferred` now counts every skipped step; it
-- counted only the steps with dear work left (0-54 an hour in the kept receipts), so it reads larger in a busy hour. `skipped` is the honest count.
--
-- ── ONE NEW FUNCTION, PURE ─────────────────────────────────────────────────────────────────────
-- public.upkeep_hard_end(start, timeout_ms, reserve_s = 25): the end-of-upkeep rule as a pure function of its arguments, so it is unit-tested
-- on its own (below) and its reserve is written once. Server-only (revoke from public, anon, authenticated).
--
-- ── WHAT DOES NOT MOVE ─────────────────────────────────────────────────────────────────────────
-- Every other function in public/cmd/world/voyage (md5, asserted), the registry, the walls (0 / 0 / 0), both owner switches
-- (economy_closed, city_treasury_enabled). No knob, no cron job, no schedule. tick_reconcile keeps its ACL, volatility and config.
--
-- ── THE BUDGET OF THIS FILE (its first push, when it was numbered 0296, died on it) ────────────
-- bv-deploy.sh unwinds the clock (every cron job paused) for the WHOLE push, so this file's run time IS the game's downtime. The first push,
-- 2026-11-01 19:25-19:35 UTC, ran its probes against REAL merchants - the old copy and the new copy of the hourly procedure, five variants, a second
-- attempt on any difference, each running the real npc_tend_route / npc_invest_one / assert_ledger_reconciles and a digest of the merchant's rows -
-- under a 10-minute statement_timeout. On CI's tiny world that took 0.9 s; on prod's real, I/O-bound one it took longer than the 10 minutes, the game
-- clock stood still for ten of them, and nothing was kept. So, for this file and every migration after it:
--   * statement_timeout 60 s and lock_timeout 5 s from the first statement: a slow file FAILS FAST and rolls back whole, it does not freeze the game;
--   * the self-assert reads the catalog and runs copies of the hourly procedure with every STEP STUBBED - no game row is read for a verdict, none is
--     written; its work does not depend on the size of any table (~1-3 s on prod; the dev-log has the measurements and the populated-world run).
--
-- ── PROD CHECKS (before the push; read-only; in the PR body) ───────────────────────────────────
--  * md5(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure)) = 3d91fee71b50f7e58b35617c3eb72ef3 (15011 chars; the chain's
--    own body has the same md5: restored from the cached 0294 prefix and compared 2026-11-01), md5(prosrc) = 12238b7715ba31e94178c911ff0fc4c2.
--  * to_regprocedure('public.upkeep_hard_end(timestamptz,numeric,numeric)') is null; pg_settings statement_timeout = 120000 ms.
--
-- ── SELF-ASSERT (nothing counts or sums a growing table; no real step runs) ────────────────────
--   (a) the live body is the one the hunks produce (md5), reverses hunk by hunk to the live pre-image (md5), each hunk once; ACL, volatility,
--       definer and config as found; the invariants block byte-identical; the phases in their old order; each skip stands before its quay;
--   (b) the helper: 120 s -> 95 s, 0 / null / negative -> no end, short walls -> the start, the reserve as asked; its ACL;
--   (c) the loops: pg_temp copies of the OLD (the pre-image) and NEW bodies, cut to a sample of 3 roster merchants, the traders on, the live waiting queue
--       replaced by an empty one, and every STEP (npc_tend_route, npc_invest_one, capital_gift_one, the purse checks) replaced by a stub that only writes a
--       line to a call log; the statement_timeout a copy reads is cut into it as a literal, so no probe SETs statement_timeout. The hunks touch nothing but the control flow around the steps, so that is what is proved, each case run ONCE (a difference
--       must reproduce on a second attempt): p_commit = false, in time: old = new (receipt and call log) and every step was REACHED; the same with the
--       skips cut to the BARE time test: nothing is skipped while there is time; p_commit = false with every deadline and the hard end PAST: old = new;
--       p_commit = true with the hard end past: no step reached (the log holds only the invariants pass's own walk; a COMMIT cannot succeed inside a probe, so
--       the call finishing proves it too), every step counted deferred and skipped; p_commit = true with only the phases' deadlines past and no hard end:
--       merchants and investment skip, the hard end is null; the bare-time copy of that: the gift steps ARE reached (the gift loop does not stop at v_cdl);
--       and the invariants pass, REAL, still BITES after a fully skipped upkeep (one ducat with no ledger row on a sampled house is caught).
--       The self-assert was also run against 22 deliberate breakages of this file (docs/dev-log): every one fails it, for the intended reason;
--   (d) every other function md5-unmoved, the registry, the walls and the two switches as found.
--   NOT PROVED IN THIS FILE, BY DESIGN - said here, in the dev-log and in the printed notice, in every environment alike (no switch skips anything):
--     * REAL steps: old = new on the rows a merchant's step writes. The hunks are pure insertions guarded by `p_commit and ...` (the pre- and post-image
--       md5 are pinned above) and every step function is md5-unmoved; the re-cut body runs REAL steps under p_commit = false in scripts/db/proofs 02, 10
--       and 12 (pglite-gate, every PR), which assert the upkeep's outcomes.
--     * the p_commit = true path WITH steps - the quay, the commits, the real beat: nothing rolled back can test a COMMIT (dev-log: UNVERIFIED).
-- ROLLBACK: none to run. Forward: a later file re-cutting tick_reconcile from this one; the helper may stay.
-- VERSION: 0300 - prod head 0299 today (the Stats period, live since 20:10 UTC 2026-11-01; 0297, the quiet disk, since 19:38); 0295, 0296 and 0298 stay unused
-- (db push refuses a number below the head).
-- This file re-cuts ONLY public.tick_reconcile(boolean).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. GUARD ────────────────────────────────────────────────────────────────────────────────────
-- The live body must be the pre-image these hunks were cut against - or, if an earlier push of this very file died after the re-cut, its
-- post-image (the file is then re-runnable: it skips the re-cut and runs its asserts). The timeouts come FIRST: a slow file fails fast.
do $guard$
declare
  v_md5 text;
begin
  perform set_config('statement_timeout', '60s', false);
  perform set_config('lock_timeout', '5s', false);
  if to_regprocedure('public.tick_reconcile(boolean)') is null
     or to_regprocedure('public.hold_the_quay()') is null
     or to_regprocedure('public.npc_tend_sum(jsonb,jsonb)') is null
     or to_regprocedure('public.npc_upkeep_scope(timestamptz)') is null
     or to_regprocedure('public.npc_invest_one(timestamptz,uuid)') is null
     or to_regprocedure('public.capital_gift_one(timestamptz,uuid)') is null then
    raise exception '0300 refuses: the hourly reconcile as 0274 left it is not in this world';
  end if;
  v_md5 := md5(replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', ''));
  if v_md5 not in ('3d91fee71b50f7e58b35617c3eb72ef3', '61b15323b59e20e0f793ffc70ef152da') then
    raise exception '0300 refuses: the live public.tick_reconcile is not the body these hunks were cut against (md5 %)', v_md5;
  end if;
end $guard$;

-- ── 1. AS FOUND (session-lived scratch: the deploy runner is not a transaction block) ───────────
create temp table before_0300 as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid is distinct from to_regprocedure('public.upkeep_hard_end(timestamptz,numeric,numeric)')::oid) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid <> 'public.tick_reconcile(boolean)'::regprocedure
           and p.oid is distinct from to_regprocedure('public.upkeep_hard_end(timestamptz,numeric,numeric)')::oid) as others_md5,
       (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.tick_reconcile(boolean)'::regprocedure) as rec_acl,
       (select p.provolatile from pg_proc p where p.oid = 'public.tick_reconcile(boolean)'::regprocedure) as rec_vol,
       (select p.prosecdef from pg_proc p where p.oid = 'public.tick_reconcile(boolean)'::regprocedure) as rec_secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'public.tick_reconcile(boolean)'::regprocedure) as rec_cfg,
       (select value from public.world_config where key = 'economy_closed') as economy_closed,
       (select value from public.world_config where key = 'city_treasury_enabled') as city_treasury_enabled;

-- ── 2. THE HELPER: THE END-OF-UPKEEP RULE, PURE ─────────────────────────────────────────────────
create or replace function public.upkeep_hard_end(p_start timestamptz, p_timeout_ms numeric, p_reserve_s numeric default 25)
returns timestamptz
language sql
stable
set search_path = public, pg_temp
as $fn$
-- 0300: THE HARD END OF THE HOURLY UPKEEP (read by public.tick_reconcile alone): the statement's own wall less a reserve for what runs after the
-- upkeep. p_start = when the statement began (statement_timestamp()); p_timeout_ms = the statement_timeout in force (pg_settings, ms);
-- 0 or null or negative = unlimited = NULL, no hard end (least(deadline, NULL) is the deadline). p_reserve_s = what the invariants pass needs:
-- 25 s (it measured 0.2-5.2 s on prod, 0.2-1.3 s since 2026-10-29) leaves room for a whole quay wait (9 s at worst in the kept receipts) on top.
-- Never earlier than p_start. A pure function of its arguments.
  select case when coalesce(p_timeout_ms, 0) <= 0 then null
              else p_start + make_interval(secs => greatest(p_timeout_ms / 1000 - coalesce(p_reserve_s, 0), 0))
         end
$fn$;
comment on function public.upkeep_hard_end(timestamptz, numeric, numeric) is
  '0300: the hourly upkeep''s hard end = the statement''s start + its statement_timeout (ms; 0 = unlimited -> NULL) - a reserve (default 25 s) for the invariants pass; never before the start. Pure. Server-only; read by public.tick_reconcile.';
revoke all on function public.upkeep_hard_end(timestamptz, numeric, numeric) from public, anon, authenticated;

-- ── 3. THE HUNKS, each once, against the live body ──────────────────────────────────────────────
create function pg_temp.occurs_0300(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table hunks_0300 (n int primary key, old text not null, new text not null);
insert into hunks_0300 (n, old, new) values
-- the variables: the hard end, and the steps skipped past an end
(1,
$h$  v_clear_ms numeric := 0;
begin
$h$,
$h$  v_clear_ms numeric := 0;
  -- 0300: THE HOUR ENDS IN TIME. ONE hard end for the whole upkeep: the statement's start + its own wall (statement_timeout, read from
  -- pg_settings) less the reserve the invariants below need (public.upkeep_hard_end); and the steps skipped past an end, for the receipt
  v_stop     timestamptz := public.upkeep_hard_end(statement_timestamp(),
                              (select s.setting::numeric from pg_settings s where s.name = 'statement_timeout'));
  v_sk_t     int := 0;
  v_sk_c     int := 0;
begin
$h$),
-- the merchants' loop: before her passes and her quay
(2,
$h$      v_tend := public.npc_tend_sum(v_tend, jsonb_build_object('waiting', 1));
      continue;
    end if;
$h$,
$h$      v_tend := public.npc_tend_sum(v_tend, jsonb_build_object('waiting', 1));
      continue;
    end if;
    -- 0300: PAST THE END SHE IS NOT QUEUED FOR THE QUAY JUST TO BE DEFERRED. Her step honours the hour's deadline (v_deadline, 0114) only
    -- inside public.npc_tend_route, which runs AFTER the quay is granted - and with the arrivals beat I/O-bound each of ~840 steps queued a
    -- whole beat for the quay even to defer (prod 2026-10-29 20:07 on: the CALL died at the 120 s wall inside hold_the_quay() every busy
    -- hour, and the invariants below never ran). Past the deadline - or past the one hard end of the whole upkeep (v_stop) - she is counted
    -- deferred the way her step counts a route left to the next hour (public.npc_tend_sum) and skipped: no pass, no quay, no transaction.
    -- p_commit = false never takes the quay and is unchanged.
    if p_commit and clock_timestamp() > least(v_deadline, v_stop) then
      v_tend := public.npc_tend_sum(v_tend, jsonb_build_object('deferred', 1));
      v_sk_t := v_sk_t + 1;
      continue;
    end if;
$h$),
-- the companies' investment loop
(3,
$h$    for h in select ir.player_id from public.npc_invest_roster() ir loop
      v_tq := clock_timestamp();
$h$,
$h$    for h in select ir.player_id from public.npc_invest_roster() ir loop
      -- 0300: the companies' step has its own budget (v_cdl, 0143), read by public.npc_invest_one only AFTER the quay. Past it - or past the
      -- hard end - she is counted deferred, exactly as npc_invest_one answers {deferred 1} past the deadline, and skipped before the quay.
      if p_commit and clock_timestamp() > least(v_cdl, v_stop) then
        v_tend := public.npc_tend_sum(v_tend, jsonb_build_object('deferred', 1));
        v_sk_c := v_sk_c + 1;
        continue;
      end if;
      v_tq := clock_timestamp();
$h$),
-- the capital's gift loop: no budget of its own, so only the hard end
(4,
$h$    for h in select gr.player_id from public.capital_gift_roster(v_now) gr loop
      v_tq := clock_timestamp();
$h$,
$h$    for h in select gr.player_id from public.capital_gift_roster(v_now) gr loop
      -- 0300: public.capital_gift_one reads no deadline, so v_cdl does not end this loop; only the hard end does, so the invariants below
      -- always have their room. A gift left to the next hour is counted deferred; the roster is read again then (its cool-down is hours).
      if p_commit and clock_timestamp() > v_stop then
        v_tend := public.npc_tend_sum(v_tend, jsonb_build_object('deferred', 1));
        v_sk_c := v_sk_c + 1;
        continue;
      end if;
      v_tq := clock_timestamp();
$h$),
-- the receipt
(5,
$h$                             'tend_clear', jsonb_build_object('n', v_cleared, 'ms', round(v_clear_ms))))   -- 0274
$h$,
$h$                             'tend_clear', jsonb_build_object('n', v_cleared, 'ms', round(v_clear_ms)),   -- 0274
                             'skipped', jsonb_build_object('tend', v_sk_t, 'companies', v_sk_c),   -- 0300: the steps skipped past an end
                             'hard_end_s', round(extract(epoch from v_stop - statement_timestamp()))))   -- 0300: the hard end, s after the start (null: none)
$h$);

do $apply$
declare
  v_def text;
  h     record;
  v_n   int;
begin
  v_def := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  if md5(v_def) = '61b15323b59e20e0f793ffc70ef152da' then
    raise notice '0300: public.tick_reconcile already carries these hunks (an earlier push of this file got this far) - not re-cut';
    return;
  end if;
  if md5(v_def) <> '3d91fee71b50f7e58b35617c3eb72ef3' then
    raise exception '0300 self-assert FAIL: the live public.tick_reconcile is not the body these hunks were cut against (md5 %)', md5(v_def);
  end if;
  for h in select * from hunks_0300 order by n loop
    v_n := pg_temp.occurs_0300(v_def, h.old);
    if v_n <> 1 then
      raise exception '0300 self-assert FAIL: hunk % occurs % time(s) in the live body, not once - the body is not what this file was cut against', h.n, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  if md5(v_def) <> '61b15323b59e20e0f793ffc70ef152da' then
    raise exception '0300 self-assert FAIL: the re-cut body is not the one this file was proved on (md5 %)', md5(v_def);
  end if;
  execute v_def;
end $apply$;

-- ── 4. THE PROBES' EYES ─────────────────────────────────────────────────────────────────────────
-- the live body with every hunk reversed: the pre-image, exactly
create function pg_temp.pre_image_0300()
returns text
language plpgsql
as $$
declare
  v text := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  h record;
begin
  for h in select * from pg_temp.hunks_0300 order by n desc loop
    if pg_temp.occurs_0300(v, h.new) <> 1 then
      raise exception '0300 self-assert FAIL: hunk % is not in the live body exactly once', h.n;
    end if;
    v := replace(v, h.new, h.old);
  end loop;
  return v;
end $$;

-- the nth place a needle stands in a text (0 = fewer than n)
create function pg_temp.nth_0300(p_hay text, p_needle text, p_n int)
returns int
language plpgsql
immutable
as $$
declare
  v_at int := 0;
  v_from int := 1;
  i int;
  p int;
begin
  for i in 1 .. p_n loop
    p := position(p_needle in substr(p_hay, v_from));
    if p = 0 then return 0; end if;
    v_at := v_from + p - 1;
    v_from := v_at + length(p_needle);
  end loop;
  return v_at;
end $$;

-- THE STEPS, STUBBED. A stub writes one line to the call log and answers a fixed, countable receipt; it reads and writes no game row. The hourly
-- procedure's steps are unchanged by this file (every function but tick_reconcile is md5-pinned), so what the copies below prove is the control flow
-- AROUND them: which steps are reached, in which order, and what the receipt counts.
create temp sequence seq_0300;
create temp table calls_0300 (n bigint not null, kind text not null, who text not null);

create function pg_temp.stub_tend_0300(p_now timestamptz, p_fleet uuid, p_route uuid, p_k bigint)
returns jsonb
language plpgsql
as $$
begin
  insert into pg_temp.calls_0300 values (nextval('pg_temp.seq_0300'), 'tend', p_route::text);
  return jsonb_build_object('started', 1);
end $$;

create function pg_temp.stub_invest_0300(p_now timestamptz, p_player uuid)
returns jsonb
language plpgsql
as $$
begin
  insert into pg_temp.calls_0300 values (nextval('pg_temp.seq_0300'), 'invest', p_player::text);
  return jsonb_build_object('invested', 1);
end $$;

create function pg_temp.stub_gift_0300(p_now timestamptz, p_player uuid)
returns jsonb
language plpgsql
as $$
begin
  insert into pg_temp.calls_0300 values (nextval('pg_temp.seq_0300'), 'gift', p_player::text);
  return '{}'::jsonb;
end $$;

create function pg_temp.stub_purse_0300(p_player uuid)
returns void
language plpgsql
as $$
begin
  insert into pg_temp.calls_0300 values (nextval('pg_temp.seq_0300'), 'purse', p_player::text);
end $$;

create function pg_temp.stub_check_0300(p_player uuid)
returns void
language plpgsql
as $$
begin
  insert into pg_temp.calls_0300 values (nextval('pg_temp.seq_0300'), 'check', p_player::text);
end $$;

-- a copy of the hourly procedure in pg_temp (the 0274 technique); every cut occurs as often as it should or the copy is refused.
--   p_late       : the phases' deadlines (v_deadline, v_cdl) are put an hour in the PAST
--   p_gifts      : the gift loop walks the sample (false: it walks nobody - for a case that has no hard end, where it would not stop)
--   p_gate       : the three new skips keep their `p_commit and` (false: cut to the bare test of the time, to try that test on its own)
--   p_real_check : the invariants pass keeps its REAL assert_ledger_reconciles (false: a stub that logs the player it would have checked)
--   p_wall       : the statement_timeout, in ms, the copy's hard end is computed from - cut in as a literal (null: the copy reads the real pg_settings, or is an OLD
--                  body that has no hard end). No probe SETs statement_timeout: nothing here can touch the file's own wall.
-- Always: the traders on, the rosters and the invariants pass walk the sample only, the live waiting queue is empty, every step is a stub.
create function pg_temp.copy_0300(p_def text, p_name text, p_late boolean, p_gifts boolean, p_gate boolean, p_real_check boolean, p_wall text default null)
returns void
language plpgsql
as $$
declare
  v text := p_def;
  c record;
begin
  for c in select * from (values
    (1, 'CREATE OR REPLACE PROCEDURE public.tick_reconcile(', 'CREATE PROCEDURE pg_temp.' || p_name || '(', true, 1),
    (2, 'for r in select * from public.npc_tend_roster() loop',
        'for r in select x.* from public.npc_tend_roster() x where x.route_id in (select s.route_id from pg_temp.sample_0300 s) loop', true, 1),
    (3, 'for h in select ir.player_id from public.npc_invest_roster() ir loop',
        'for h in select s.player_id from pg_temp.sample_0300 s loop', true, 1),
    (4, 'for h in select gr.player_id from public.capital_gift_roster(v_now) gr loop',
        case when p_gifts then 'for h in select s.player_id from pg_temp.sample_0300 s loop'
             else 'for h in select s.player_id from pg_temp.sample_0300 s where false loop' end, true, 1),
    (5, 'for r in select id from public.players loop',
        'for r in select id from public.players where id in (select s.player_id from pg_temp.sample_0300 s) loop', true, 1),
    (6, 'v_on       boolean := public.npc_traders_on();', 'v_on       boolean := true;', true, 1),
    (7, 'v_deadline timestamptz := clock_timestamp() + make_interval(', 'v_deadline timestamptz := clock_timestamp() - make_interval(', p_late, 1),
    (8, 'v_cdl := clock_timestamp() + make_interval(', 'v_cdl := clock_timestamp() - make_interval(', p_late, 1),
    (9, 'if p_commit and clock_timestamp() >', 'if clock_timestamp() >', not p_gate, 3),
    (10, 'v_wait := array(select q.route_id from public.npc_waiting_queue(v_now) q where not q.overdue);', 'v_wait := ''{}'';', true, 1),
    (11, 'public.npc_tend_route(v_now, r.fleet_id, r.route_id, r.k)', 'pg_temp.stub_tend_0300(v_now, r.fleet_id, r.route_id, r.k)', true, 3),
    (12, 'public.npc_invest_one(v_now, h.player_id)', 'pg_temp.stub_invest_0300(v_now, h.player_id)', true, 1),
    (13, 'public.capital_gift_one(v_now, h.player_id)', 'pg_temp.stub_gift_0300(v_now, h.player_id)', true, 1),
    (14, 'perform public.assert_ledger_reconciles(r.player_id);', 'perform pg_temp.stub_purse_0300(r.player_id);', true, 1),
    (15, 'perform public.assert_ledger_reconciles(h.player_id);', 'perform pg_temp.stub_purse_0300(h.player_id);', true, 2),
    (16, 'perform public.assert_ledger_reconciles(r.id);', 'perform pg_temp.stub_check_0300(r.id);', not p_real_check, 1),
    (17, '(select s.setting::numeric from pg_settings s where s.name = ''statement_timeout'')', p_wall || '::numeric', p_wall is not null, 1)
  ) t(n, a, b, applies, want) where applies loop
    if pg_temp.occurs_0300(v, c.a) <> c.want then
      raise exception '0300 self-assert FAIL: the probe''s cut % does not occur % time(s) in the % body', c.n, c.want, p_name;
    end if;
    v := replace(v, c.a, c.b);
  end loop;
  -- THE COPY CANNOT REACH A REAL STEP: asserted on its own text, so a later edit of the cuts cannot quietly bring a real step (or a ledger sum) back
  -- into the probes - the failure that made this file's first push run for ten minutes on prod
  if pg_temp.occurs_0300(v, 'public.npc_tend_route(v_now') <> 0 or pg_temp.occurs_0300(v, 'public.npc_invest_one(v_now') <> 0
     or pg_temp.occurs_0300(v, 'public.capital_gift_one(v_now') <> 0
     or pg_temp.occurs_0300(v, 'public.assert_ledger_reconciles(') <> (case when p_real_check then 1 else 0 end) then
    raise exception '0300 self-assert FAIL: the probe copy % can still reach a real step', p_name;
  end if;
  execute v;
end $$;

-- one case, rolled back: the call, the receipt it wrote, the call log it left
--   old / new           : the OLD / NEW copy, p_commit = false, in time
--   nogate              : the NEW copy with the skips cut to the bare test of the time, p_commit = false, in time (is there ever a skip while there is time?)
--   old_late / new_late : the phases' deadlines past (and, for new_late, the hard end past too), p_commit = false
--   nogate_dl           : the bare-time copy, p_commit = false, the phases' deadlines past, no hard end, the gift loop walking: it must NOT stop at v_cdl
--   new_end             : the NEW copy, p_commit = TRUE, the hard end past (its wall cut to 1000 ms): every step skipped
--   new_dl              : the NEW copy, p_commit = TRUE, the phases' deadlines past, its wall cut to 0 (no hard end), no gift walkers
--   new_bite            : the NEW copy with the REAL invariants pass, p_commit = TRUE, the hard end past, after one ducat with no ledger row on a sampled house
-- A COMMIT cannot succeed inside a probe, so a p_commit = true call that FINISHES reached no step at all.
create function pg_temp.case_0300(p_mode text)
returns jsonb
language plpgsql
as $$
declare
  v_rec    jsonb;
  v_err    text := null;
  v_proc   text;
  v_commit boolean := false;
  s        record;
begin
  begin
    select m.proc, m.do_commit into v_proc, v_commit from (values
      ('old',       'reconcile_old_0300',   false),
      ('new',       'reconcile_new_0300',   false),
      ('nogate',    'reconcile_newg_0300',  false),
      ('old_late',  'reconcile_oldl_0300',  false),
      ('new_late',  'reconcile_newl_0300',  false),
      ('nogate_dl', 'reconcile_newgl_0300', false),
      ('new_end',   'reconcile_newe_0300',  true),
      ('new_dl',    'reconcile_newd_0300',  true),
      ('new_bite',  'reconcile_newb_0300',  true)) m(k, proc, do_commit)
     where m.k = p_mode;
    if v_proc is null then raise exception '0300 self-assert FAIL: no such probe case %', p_mode; end if;
    if p_mode = 'new_bite' then
      select x.* into s from pg_temp.sample_0300 x order by x.route_id limit 1;
      update public.players set ducats = ducats + 1 where id = s.player_id;   -- one ducat, no ledger row behind it
    end if;
    begin
      execute format('call pg_temp.%I(%L)', v_proc, v_commit);
    exception when others then
      if p_mode <> 'new_bite' then raise; end if;
      v_err := sqlerrm;
    end;
    v_rec := (select r.receipt from public.reconcile_runs r where r.at = now());
    raise exception using errcode = 'ZY300', message = jsonb_build_object(
      'receipt', v_rec, 'err', v_err,
      'calls', (select coalesce(string_agg(c.kind || ':' || c.who, ',' order by c.n), '') from pg_temp.calls_0300 c),
      'counts', (select coalesce(jsonb_object_agg(k.kind, k.n), '{}'::jsonb)
                   from (select c.kind, count(*) as n from pg_temp.calls_0300 c group by c.kind) k))::text;
  exception when sqlstate 'ZY300' then
    return sqlerrm::jsonb;
  end;
end $$;

-- the receipt without what a clock or the new keys make differ, with the call log and the quay tallies' counts, for old-against-new
create function pg_temp.norm_0300(p_case jsonb)
returns jsonb
language sql
immutable
as $$
  select ((p_case->'receipt') - array['ms', 'quay', 'tend_holds', 'tend_plan', 'tend_clear', 'skipped', 'hard_end_s'])
         || jsonb_build_object('plan_n', p_case->'receipt'->'tend_plan'->'n', 'clear_n', p_case->'receipt'->'tend_clear'->'n',
                               'qt_n', p_case->'receipt'->'quay'->'tend'->'n', 'qc_n', p_case->'receipt'->'quay'->'companies'->'n',
                               'calls', p_case->'calls')
$$;

-- were all the steps REACHED (in time, nothing skipped)? one tend per sampled merchant at least (a failed order adds her passes), one invest and one gift per
-- sampled house, three purse checks per sampled merchant (her own, her house's investment turn, her house's gift turn), the invariants pass over each house
create function pg_temp.reached_0300(p_case jsonb, p_s int, p_ps int)
returns boolean
language sql
immutable
as $$
  select coalesce((p_case->'counts'->>'tend')::int, 0) >= p_s
     and coalesce((p_case->'counts'->>'invest')::int, 0) = p_s
     and coalesce((p_case->'counts'->>'gift')::int, 0) = p_s
     and coalesce((p_case->'counts'->>'purse')::int, 0) = 3 * p_s
     and coalesce((p_case->'counts'->>'check')::int, 0) = p_ps
$$;

-- a pair of cases; a difference must REPRODUCE: the second attempt is the verdict (the loops read a merchant's failed orders, which a live world may change)
create function pg_temp.pair_0300(p_a text, p_b text)
returns jsonb
language plpgsql
as $$
declare
  v_a jsonb;
  v_b jsonb;
  i   int;
begin
  for i in 1 .. 2 loop
    v_a := pg_temp.case_0300(p_a);
    v_b := pg_temp.case_0300(p_b);
    exit when pg_temp.norm_0300(v_a) = pg_temp.norm_0300(v_b);
  end loop;
  return jsonb_build_object('a', v_a, 'b', v_b);
end $$;

create temp table sample_0300 (route_id uuid, fleet_id uuid, player_id uuid, k bigint);

-- ── 5. THE SELF-ASSERT (the last statement of the file) ─────────────────────────────────────────
do $assert$
declare
  f        record;
  h        record;
  v_def    text;
  v_old    text;
  v_a      jsonb;
  v_b      jsonb;
  v_pair   jsonb;
  v_t0     constant timestamptz := '2030-01-01 00:00:00+00';
  v_start  timestamptz := clock_timestamp();
  v_s      int;
  v_ps     int;
  v_cases  int := 0;
  v_skt    int;
  v_skc    int;
  i        int;
  v_pos    int[];
begin
  select * into f from before_0300;

  -- (a) THE HUNKS: the live body is the one they produce, reverses to the live pre-image hunk by hunk, each once
  v_def := replace(pg_get_functiondef('public.tick_reconcile(boolean)'::regprocedure), E'\r', '');
  if md5(v_def) <> '61b15323b59e20e0f793ffc70ef152da' then
    raise exception '0300 self-assert FAIL: the live public.tick_reconcile is not the re-cut body this file was proved on (md5 %)', md5(v_def);
  end if;
  v_old := pg_temp.pre_image_0300();
  if md5(v_old) <> '3d91fee71b50f7e58b35617c3eb72ef3' then
    raise exception '0300 self-assert FAIL: the hunks do not reverse to the live pre-image (md5 %)', md5(v_old);
  end if;
  for h in select * from hunks_0300 order by n loop
    if pg_temp.occurs_0300(v_old, h.old) <> 1 or pg_temp.occurs_0300(v_def, h.new) <> 1 then
      raise exception '0300 self-assert FAIL: hunk % does not stand exactly once in the pre-image and in the new body', h.n;
    end if;
  end loop;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.tick_reconcile(boolean)'::regprocedure) <> f.rec_acl
     or (select p.provolatile from pg_proc p where p.oid = 'public.tick_reconcile(boolean)'::regprocedure) <> f.rec_vol
     or (select p.prosecdef from pg_proc p where p.oid = 'public.tick_reconcile(boolean)'::regprocedure) <> f.rec_secdef
     or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'public.tick_reconcile(boolean)'::regprocedure) <> f.rec_cfg then
    raise exception '0300 self-assert FAIL: tick_reconcile changed its ACL, volatility, definer or config';
  end if;

  -- (a2) THE SHAPE OF THE FIX, in text: the invariants block is byte-identical; the phases keep their order; each skip stands before its quay
  --      (and the merchants' before her passes); the three ends are the three this file says; the receipt carries the two new keys once
  if substr(v_def, position('  -- THE INVARIANTS (0010/0097' in v_def),
            position('  v_ms := v_ms || jsonb_build_object(''check''' in v_def) - position('  -- THE INVARIANTS (0010/0097' in v_def))
     is distinct from
     substr(v_old, position('  -- THE INVARIANTS (0010/0097' in v_old),
            position('  v_ms := v_ms || jsonb_build_object(''check''' in v_old) - position('  -- THE INVARIANTS (0010/0097' in v_old))
     or position('voyage.assert_sailing_invariant' in substr(v_def, position('  -- THE INVARIANTS (0010/0097' in v_def))) = 0 then
    raise exception '0300 self-assert FAIL: the invariants pass is not byte-identical';
  end if;
  v_pos := array[position('npc_tend_roster() loop' in v_def), position('v_cdl := clock_timestamp()' in v_def),
                 position('npc_invest_roster() ir loop' in v_def), position('capital_gift_roster(v_now) gr loop' in v_def),
                 position('  -- THE INVARIANTS (0010/0097' in v_def), position('perform voyage.assert_sailing_invariant();' in v_def),
                 position('public.client_write_grants()' in v_def), position('insert into public.reconcile_runs' in v_def)];
  for i in 1 .. 8 loop
    if v_pos[i] = 0 or (i > 1 and v_pos[i] <= v_pos[i - 1]) then
      raise exception '0300 self-assert FAIL: the phases are not in their old order (landmark % at %)', i, v_pos[i];
    end if;
  end loop;
  if pg_temp.occurs_0300(v_def, 'perform public.hold_the_quay();') <> 3
     or pg_temp.occurs_0300(v_def, 'if p_commit and clock_timestamp() > least(v_deadline, v_stop) then') <> 1
     or pg_temp.occurs_0300(v_def, 'if p_commit and clock_timestamp() > least(v_cdl, v_stop) then') <> 1
     or pg_temp.occurs_0300(v_def, 'if p_commit and clock_timestamp() > v_stop then') <> 1
     or pg_temp.occurs_0300(v_def, 'v_tend := public.npc_tend_sum(v_tend, jsonb_build_object(''deferred'', 1));') <> 3
     or pg_temp.occurs_0300(v_def, '''skipped'', jsonb_build_object(''tend'', v_sk_t, ''companies'', v_sk_c)') <> 1
     or pg_temp.occurs_0300(v_def, '''hard_end_s'',') <> 1
     or pg_temp.occurs_0300(v_def, '(select s.setting::numeric from pg_settings s where s.name = ''statement_timeout'')') <> 1 then
    raise exception '0300 self-assert FAIL: the three skips, the quay, the wall read or the receipt are not as this file writes them';
  end if;
  if not (pg_temp.nth_0300(v_def, 'jsonb_build_object(''waiting'', 1)', 1)
            < position('if p_commit and clock_timestamp() > least(v_deadline, v_stop) then' in v_def)
          and position('if p_commit and clock_timestamp() > least(v_deadline, v_stop) then' in v_def)
            < position('byeharu.tend_plan_pass' in v_def)
          and position('byeharu.tend_plan_pass' in v_def) < pg_temp.nth_0300(v_def, 'perform public.hold_the_quay();', 1)
          and pg_temp.nth_0300(v_def, 'perform public.hold_the_quay();', 1)
            < position('if p_commit and clock_timestamp() > least(v_cdl, v_stop) then' in v_def)
          and position('if p_commit and clock_timestamp() > least(v_cdl, v_stop) then' in v_def)
            < pg_temp.nth_0300(v_def, 'perform public.hold_the_quay();', 2)
          and pg_temp.nth_0300(v_def, 'perform public.hold_the_quay();', 2)
            < position('if p_commit and clock_timestamp() > v_stop then' in v_def)
          and position('if p_commit and clock_timestamp() > v_stop then' in v_def)
            < pg_temp.nth_0300(v_def, 'perform public.hold_the_quay();', 3)) then
    raise exception '0300 self-assert FAIL: a skip does not stand before its quay (the merchants'' before her passes)';
  end if;

  -- (b) THE RULE, a pure function: the wall less the reserve; unlimited is no end; never before the start; the reserve as asked
  if public.upkeep_hard_end(v_t0, 120000) is distinct from v_t0 + interval '95 seconds'
     or public.upkeep_hard_end(v_t0, 120000, 25) is distinct from v_t0 + interval '95 seconds'
     or public.upkeep_hard_end(v_t0, 120000.5) is distinct from v_t0 + interval '95.0005 seconds'
     or public.upkeep_hard_end(v_t0, 600000) is distinct from v_t0 + interval '575 seconds'
     or public.upkeep_hard_end(v_t0, 30000) is distinct from v_t0 + interval '5 seconds'
     or public.upkeep_hard_end(v_t0, 120000, 0) is distinct from v_t0 + interval '120 seconds'
     or public.upkeep_hard_end(v_t0, 120000, 60) is distinct from v_t0 + interval '60 seconds'
     or public.upkeep_hard_end(v_t0, 120000, null) is distinct from v_t0 + interval '120 seconds' then
    raise exception '0300 self-assert FAIL: upkeep_hard_end does not give the wall less the reserve';
  end if;
  if public.upkeep_hard_end(v_t0, 0) is not null or public.upkeep_hard_end(v_t0, null) is not null
     or public.upkeep_hard_end(v_t0, -5) is not null or public.upkeep_hard_end(null, 120000) is not null then
    raise exception '0300 self-assert FAIL: an unlimited statement_timeout (0, null, negative) must give no hard end';
  end if;
  if public.upkeep_hard_end(v_t0, 25000) is distinct from v_t0 or public.upkeep_hard_end(v_t0, 1000) is distinct from v_t0
     or public.upkeep_hard_end(v_t0, 10000, 25) is distinct from v_t0 then
    raise exception '0300 self-assert FAIL: a wall shorter than the reserve must give the start, never an earlier time';
  end if;
  if least(v_t0 + interval '60 seconds', public.upkeep_hard_end(v_t0, 120000)) is distinct from v_t0 + interval '60 seconds'
     or least(v_t0 + interval '60 seconds', public.upkeep_hard_end(v_t0, 0)) is distinct from v_t0 + interval '60 seconds'
     or least(v_t0 + interval '120 seconds', public.upkeep_hard_end(v_t0, 120000)) is distinct from v_t0 + interval '95 seconds' then
    raise exception '0300 self-assert FAIL: least(phase deadline, hard end) is not the earlier of the two (a null hard end leaves the deadline)';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.upkeep_hard_end(timestamptz,numeric,numeric)'::regprocedure) <> 's'
     or (select p.prosecdef from pg_proc p where p.oid = 'public.upkeep_hard_end(timestamptz,numeric,numeric)'::regprocedure)
     or has_function_privilege('anon', 'public.upkeep_hard_end(timestamptz,numeric,numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.upkeep_hard_end(timestamptz,numeric,numeric)', 'execute') then
    raise exception '0300 self-assert FAIL: upkeep_hard_end must be stable, invoker-rights and server-only';
  end if;

  -- (c) THE LOOPS, on a sample of the roster (the tail, not waiting, at most 3), every step a stub. Nothing here runs a real step or reads a merchant's rows.
  insert into sample_0300
  select r.route_id, r.fleet_id, r.player_id, r.k
    from public.npc_tend_roster() r
   where r.route_id not in (select q.route_id from public.npc_waiting_queue(now()) q where not q.overdue and q.route_id is not null)
   order by r.k desc
   limit 3;
  select count(*) into v_s from sample_0300;
  select count(distinct player_id) into v_ps from sample_0300;
  if v_s < 1 then
    raise exception '0300 self-assert FAIL: no merchant to probe - the probe proves nothing';
  end if;

  -- the wall each NEW copy reads: the REAL pg_settings (null) in the one case that compares the receipt's hard end with it; a literal everywhere else - 600000 ms
  -- (a hard end 575 s out, whatever this statement's own timeout) where the case must be IN TIME, 1000 (the start itself) where it must be PAST, 0 where there is none
  perform pg_temp.copy_0300(v_old, 'reconcile_old_0300', false, true, true, false);
  perform pg_temp.copy_0300(v_def, 'reconcile_new_0300', false, true, true, false);
  perform pg_temp.copy_0300(v_def, 'reconcile_newg_0300', false, true, false, false, '600000');
  perform pg_temp.copy_0300(v_old, 'reconcile_oldl_0300', true, true, true, false);
  perform pg_temp.copy_0300(v_def, 'reconcile_newl_0300', true, true, true, false, '1000');
  perform pg_temp.copy_0300(v_def, 'reconcile_newgl_0300', true, true, false, false, '0');
  perform pg_temp.copy_0300(v_def, 'reconcile_newe_0300', false, true, true, false, '1000');
  perform pg_temp.copy_0300(v_def, 'reconcile_newd_0300', true, false, true, false, '0');
  perform pg_temp.copy_0300(v_def, 'reconcile_newb_0300', false, true, true, true, '1000');

  -- c1: p_commit = false, in time: the old loop and the new loop leave the same receipt and the same call log (a clock's keys and the new keys apart),
  --     and every step was reached
  v_pair := pg_temp.pair_0300('old', 'new');
  v_a := v_pair->'a';
  v_b := v_pair->'b';
  v_cases := v_cases + 1;
  if pg_temp.norm_0300(v_a) is distinct from pg_temp.norm_0300(v_b) then
    raise exception '0300 self-assert FAIL: p_commit = false in time - old and new differ: % / %', left(pg_temp.norm_0300(v_a)::text, 700), left(pg_temp.norm_0300(v_b)::text, 700);
  end if;
  if not pg_temp.reached_0300(v_b, v_s, v_ps) or not pg_temp.reached_0300(v_a, v_s, v_ps) then
    raise exception '0300 self-assert FAIL: in time, with p_commit = false, not every step was reached: % / %', v_a->'counts', v_b->'counts';
  end if;
  if (v_a->'receipt') ? 'skipped' or (v_b->'receipt'->'skipped') is distinct from jsonb_build_object('tend', 0, 'companies', 0)
     or (v_b->'receipt'->'hard_end_s') is distinct from
        coalesce(to_jsonb((select round(extract(epoch from public.upkeep_hard_end(statement_timestamp(), g.setting::numeric) - statement_timestamp()))
                             from pg_settings g where g.name = 'statement_timeout')), 'null'::jsonb) then
    raise exception '0300 self-assert FAIL: the new receipt does not carry skipped {0, 0} and the hard end as the wall says: %', v_b->'receipt';
  end if;

  -- c1b: the TIME TEST ON ITS OWN (the three skips cut to the bare `clock_timestamp() > end`, p_commit = false): while there is time it is false
  --      in all three loops - not one step is skipped, and the loop is the old loop
  v_pair := pg_temp.pair_0300('old', 'nogate');
  v_a := v_pair->'a';
  v_b := v_pair->'b';
  v_cases := v_cases + 1;
  if pg_temp.norm_0300(v_a) is distinct from pg_temp.norm_0300(v_b) or not pg_temp.reached_0300(v_b, v_s, v_ps)
     or (v_b->'receipt'->'skipped') is distinct from jsonb_build_object('tend', 0, 'companies', 0) then
    raise exception '0300 self-assert FAIL: the bare time test skipped a step while there was time, or the loop is not the old loop: % / %', left(pg_temp.norm_0300(v_a)::text, 700), left(v_b::text, 700);
  end if;

  -- c2: p_commit = false with every deadline AND the hard end past: still the old loop (it never takes the quay; the budget is read in her step as before)
  v_pair := pg_temp.pair_0300('old_late', 'new_late');
  v_a := v_pair->'a';
  v_b := v_pair->'b';
  v_cases := v_cases + 1;
  if pg_temp.norm_0300(v_a) is distinct from pg_temp.norm_0300(v_b) or not pg_temp.reached_0300(v_b, v_s, v_ps) then
    raise exception '0300 self-assert FAIL: p_commit = false past every end - old and new differ: % / %', left(pg_temp.norm_0300(v_a)::text, 700), left(pg_temp.norm_0300(v_b)::text, 700);
  end if;
  if (v_b->'receipt'->'skipped') is distinct from jsonb_build_object('tend', 0, 'companies', 0)
     or (v_b->'receipt'->'hard_end_s') is distinct from to_jsonb(0) then
    raise exception '0300 self-assert FAIL: p_commit = false skipped a step, or the hard end past was not read as 0 s: %', v_b->'receipt';
  end if;

  -- c3: p_commit = TRUE, the hard end past: every step skipped before its quay, none reached, the invariants pass walked the sample
  v_a := pg_temp.case_0300('new_end');
  v_cases := v_cases + 1;
  if v_a->'receipt' is null or (v_a->'counts') is distinct from jsonb_build_object('check', v_ps) then
    raise exception '0300 self-assert FAIL: a fully skipped upkeep reached a step, or wrote no receipt: %', left(v_a::text, 900);
  end if;
  if (v_a->'receipt'->'skipped') is distinct from jsonb_build_object('tend', v_s, 'companies', 2 * v_s)
     or (v_a->'receipt'->'merchant_upkeep'->'tend'->>'deferred')::int <> 3 * v_s
     or (v_a->'receipt'->>'players_checked')::int <> v_ps
     or (v_a->'receipt'->'hard_end_s') is distinct from to_jsonb(0)
     or (v_a->'receipt'->'quay') is distinct from jsonb_build_object('tend', '{}'::jsonb, 'companies', '{}'::jsonb)
     or (v_a->'receipt'->'tend_holds') is distinct from '{}'::jsonb then
    raise exception '0300 self-assert FAIL: the fully skipped upkeep is not counted as this file says: %', left((v_a->'receipt')::text, 1200);
  end if;
  if exists (select 1 from jsonb_each_text(v_a->'receipt'->'merchant_upkeep'->'tend') e
              where e.key in ('dark', 'started', 'resumed', 'cleared', 'laid_up', 'invested', 'donated', 'busy', 'failed', 'waiting') and e.value::int <> 0) then
    raise exception '0300 self-assert FAIL: a skipped step acted: %', v_a->'receipt'->'merchant_upkeep';
  end if;
  v_skt := (v_a->'receipt'->'skipped'->>'tend')::int;
  v_skc := (v_a->'receipt'->'skipped'->>'companies')::int;

  -- c4: p_commit = TRUE, only the phases' deadlines past, no hard end (the copy's wall is 0): the merchants' and the investment loops skip
  v_a := pg_temp.case_0300('new_dl');
  v_cases := v_cases + 1;
  if v_a->'receipt' is null or (v_a->'counts') is distinct from jsonb_build_object('check', v_ps)
     or (v_a->'receipt'->'skipped') is distinct from jsonb_build_object('tend', v_s, 'companies', v_s)
     or (v_a->'receipt'->'merchant_upkeep'->'tend'->>'deferred')::int <> 2 * v_s
     or (v_a->'receipt'->>'players_checked')::int <> v_ps
     or (v_a->'receipt'->'hard_end_s') is distinct from 'null'::jsonb then
    raise exception '0300 self-assert FAIL: past the phases'' deadlines with no hard end the loops are not skipped as this file says: %', left(v_a::text, 1200);
  end if;

  -- c4b: THE GIFT LOOP DOES NOT STOP AT v_cdl (public.capital_gift_one reads no deadline): the bare-time copy, the phases' deadlines past, no hard end,
  --      the gift loop walking the sample - the investment loop skips, and every gift step IS REACHED (the quay's tally counts them)
  v_a := pg_temp.case_0300('nogate_dl');
  v_cases := v_cases + 1;
  if v_a->'receipt' is null
     or (v_a->'counts') is distinct from jsonb_build_object('gift', v_s, 'purse', v_s, 'check', v_ps)
     or (v_a->'receipt'->'skipped') is distinct from jsonb_build_object('tend', v_s, 'companies', v_s)
     or (v_a->'receipt'->'quay'->'companies'->>'n')::int is distinct from v_s
     or (v_a->'receipt'->'merchant_upkeep'->'tend'->>'deferred')::int <> 2 * v_s
     or (v_a->'receipt'->'hard_end_s') is distinct from 'null'::jsonb then
    raise exception '0300 self-assert FAIL: the gift loop stopped at the companies'' deadline, or the investment loop did not: %', left(v_a::text, 1200);
  end if;

  -- c5: THE CHECK ALWAYS RUNS AND STILL BITES after a fully skipped upkeep (the REAL invariants pass, on the sample; no step was reached)
  v_a := pg_temp.case_0300('new_bite');
  v_cases := v_cases + 1;
  if v_a->>'err' is null or v_a->>'err' !~ 'LEDGER RECONCILIATION FAILED' or (v_a->'counts') is distinct from '{}'::jsonb then
    raise exception '0300 self-assert FAIL: after a fully skipped upkeep the invariants pass did not catch an unbacked ducat, or a step was reached (%)', left(v_a::text, 900);
  end if;

  -- (d) nothing else moved
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> f.fns + 1
     or (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
            and p.oid <> 'public.tick_reconcile(boolean)'::regprocedure
            and p.oid <> 'public.upkeep_hard_end(timestamptz,numeric,numeric)'::regprocedure) <> f.others_md5 then
    raise exception '0300 self-assert FAIL: a function in public/cmd/world/voyage other than tick_reconcile moved, or more than the one helper was added';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> f.entry_points
     or (select value from public.world_config where key = 'economy_closed') is distinct from f.economy_closed
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from f.city_treasury_enabled then
    raise exception '0300 self-assert FAIL: the registry or an owner switch moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0300 self-assert FAIL: a wall moved';
  end if;

  raise notice '0300 self-assert ok: THE HOUR ENDS IN TIME. public.tick_reconcile reverses hunk by hunk to its live pre-image (md5), ACL / volatility / definer / config unmoved, the invariants pass byte-identical, the phases in their old order, each skip before its quay. public.upkeep_hard_end: the wall less 25 s (120 s -> 95 s), unlimited -> no end, never before the start, server-only. Probes (copies of the OLD and NEW bodies, a sample of % merchant(s) / % house(s), EVERY STEP A STUB, each case run once): p_commit = false old = new (receipt and call log) in time and past every end, every step reached, and the bare time test skips nothing while there is time; p_commit = true past the hard end skipped every step (merchants % + companies %, none reached, the invariants pass walked the sample); past only the phases'' deadlines the merchants'' and investment loops skipped with no hard end while the gift steps were still reached; and the REAL invariants pass still BITES after a fully skipped upkeep. % case(s). Every other function in public/cmd/world/voyage unmoved by md5, the registry at % entry points, the walls 0 / 0 / 0, both owner switches as found. NOT PROVED IN THIS FILE, BY DESIGN, in any environment: REAL steps old = new (the hunks are pure insertions guarded by p_commit, pre- and post-image md5 pinned, every step function md5-unmoved; the re-cut body runs real steps under p_commit = false in scripts/db/proofs 02, 10 and 12 on every PR) and the p_commit = true path WITH steps (quay, commits, the real beat; nothing rolled back can test a COMMIT). Printed, never asserted: % s for this self-assert.',
    v_s, v_ps, v_skt, v_skc, v_cases, f.entry_points,
    round(extract(epoch from clock_timestamp() - v_start)::numeric, 2);

  drop procedure if exists pg_temp.reconcile_old_0300(boolean), pg_temp.reconcile_new_0300(boolean), pg_temp.reconcile_oldl_0300(boolean),
                           pg_temp.reconcile_newl_0300(boolean), pg_temp.reconcile_newd_0300(boolean), pg_temp.reconcile_newg_0300(boolean),
                           pg_temp.reconcile_newgl_0300(boolean), pg_temp.reconcile_newb_0300(boolean), pg_temp.reconcile_newe_0300(boolean);
  drop function if exists pg_temp.pair_0300(text, text), pg_temp.norm_0300(jsonb), pg_temp.reached_0300(jsonb, int, int), pg_temp.case_0300(text),
                          pg_temp.copy_0300(text, text, boolean, boolean, boolean, boolean, text), pg_temp.nth_0300(text, text, int),
                          pg_temp.pre_image_0300(), pg_temp.occurs_0300(text, text),
                          pg_temp.stub_tend_0300(timestamptz, uuid, uuid, bigint), pg_temp.stub_invest_0300(timestamptz, uuid),
                          pg_temp.stub_gift_0300(timestamptz, uuid), pg_temp.stub_purse_0300(uuid), pg_temp.stub_check_0300(uuid);
  drop table if exists pg_temp.before_0300, pg_temp.hunks_0300, pg_temp.sample_0300, pg_temp.calls_0300;
  drop sequence if exists pg_temp.seq_0300;
end $assert$;

reset statement_timeout;
reset lock_timeout;
