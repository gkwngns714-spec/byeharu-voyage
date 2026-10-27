-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0248 — ONE WARM HAND KEEPS THE SECOND  (the arrivals job: one session a minute, one run a second)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, row 224 ──────────────────────────────────────────────────────────────────────────
--   "no i want every 1 second". 0242 put byeharu-voyage:arrivals on '1 seconds'.
--
-- ── THE DEFECT, MEASURED (prod, read-only, 2026-10-27) ──────────────────────────────────────────
-- cron.job_run_details, the hour to 07:40 UTC: 2,864 runs in 3,600 s (≈ 48 a minute, not 60), 1 failed,
-- p50 0.71 s, p95 2.31 s, max 9.85 s. pg_cron starts no run while the last is running, so every run over
-- 1 s costs the next second. The slow runs are NOT the neighbours' doing: in minutes no other job ran,
-- arrivals still made 46-55 runs, p50 0.6-0.9 s, p95 1.5-2.7 s. The neighbours (stats :06/:21/:36/:51,
-- reconcile :07, the game-day drift) push a minute down to 20-37 runs on top of that.
-- What a run costs follows what it does (30 min, 1,308 runs, joined to the rows each wrote at its instant):
--   runs writing ~0.6 events + ledger rows: 0.21 s; ~3: 0.41 s; ~8: 0.84 s; ~15: 2.4 s; ~43: 6.9 s.
--   Runs that wrote no event and no ledger row at all (sea-days only): p50 0.53 s.
-- The SAME world on PGlite (head 0247, prod's switches, 835 merchants at sea, 240 seconds of the clock run
-- second by second in one session): p50 62 ms, ~7 ms a fleet touched — wasm, an order slower than a server
-- per statement, yet ten times faster than prod per run. The difference is the session:
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- pg_cron (cron.use_background_workers = off on prod) opens a NEW connection — a new backend — for every
-- run. A new backend has nothing cached: every relation the run touches is loaded into its relcache, every
-- PL/pgSQL function on the path (voyage.settle, cmd.advance, the route core, the trade doors, the depart,
-- the insurance, the provisioning: ~600 functions, ~25,000 lines) is compiled again, and every statement in
-- them is planned again — every second, for a run whose own work is milliseconds. 0242 multiplied the
-- number of cold starts by fifteen (15 s → 1 s).
-- PGlite, the same world (15 samples, the same second's run from the same dumped state):
--   * a FRESH engine's first statement (a pg_cron run): 369-1,187 ms, 31-370 ms a fleet;
--   * the same run again in that engine (compiled once): 125-778 ms;
--   * an engine that has run the clock for minutes: ~7 ms a fleet (p50 62 ms a second).
--   An empty run (nothing due): 31 ms cold, 7 ms warm. The cost is the session, not the work.
--
-- ── WHAT THIS FILE DOES ────────────────────────────────────────────────────────────────────────
-- (1) public.tick_arrivals_each_second() — a PROCEDURE (it commits; no SECURITY DEFINER, no SET, as
--     tick_market_drift_each_port and tick_reconcile): ONE session that runs `public.tick_arrivals()` once a
--     second for the minute it was started in, each run its OWN transaction (commit before, commit after),
--     so now() — the run's p_now — is that second's, exactly as a pg_cron run's was. The run itself is not
--     touched: same function, same default argument, same budget (arrivals_tick_budget_ms), same SKIP LOCKED.
--     A beat waits for its whole second (pg_sleep, in a transaction of its own, holding nothing); a beat
--     that ran past the next second starts at once, the one after waits again — so a slow second costs no
--     second after it. A run that raises (a deadlock) is rolled back alone and warned, like a failed cron
--     run, and the next second runs. It stops at the end of its minute, or at once when the job is
--     switched off (public.unwind_the_clock(): cron.job.active, read every beat) — so a deploy waits a
--     second for it, not a minute.
-- (2) public.arrivals_beats — 3,600 rows at most, one a second of the hour (slot = epoch mod 3600),
--     overwritten an hour later: what each beat did and how long it took, the job's own record (pg_cron's
--     job_run_details now keeps one row a minute). One writer: the procedure. Server-only.
-- (3) Cron: byeharu-voyage:arrivals schedule '1 seconds' → '* * * * *', command
--     'select public.tick_arrivals()' → 'call public.tick_arrivals_each_second()'. Name, owner, active flag
--     kept (0078: wind_the_clock only flips `active`).
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- Touch public.tick_arrivals or anything it calls (asserted: its definition, ACL, volatility, definer and
-- config are byte-identical before and after). Change any knob or flag, any rule, any grant, any client read.
-- Touch the other jobs.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
--   select cron.alter_job((select jobid from cron.job where jobname = 'byeharu-voyage:arrivals'),
--                         schedule := '1 seconds', command := 'select public.tick_arrivals()');
-- One statement; the procedure and the beat table are additive and harmless left in place.
--
-- VERSION: 0248 (prod head 0247).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.tick_arrivals(timestamptz)') is null
     or to_regprocedure('public.clock_jobs()') is null
     or to_regprocedure('public.npc_ask_slot(timestamptz)') is null then
    raise exception '0248 refuses: 0078 / 0242 is not in this world';
  end if;
  if to_regclass('public.arrivals_beats') is not null then
    raise exception '0248 refuses: public.arrivals_beats already exists — this has been applied once';
  end if;
end $guard$;

-- ── 0. THE RUN, AS FOUND (it must leave this file as it came in) ────────────────────────────────
create temp table before_0248 on commit drop as
select md5(replace(pg_get_functiondef(p.oid), E'\r', '')) as def_md5,
       coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef,
       coalesce(p.proconfig::text, '') as cfg,
       (select count(*) from public.client_rpc_entry_points()) as entry_points
  from pg_proc p where p.oid = 'public.tick_arrivals(timestamptz)'::regprocedure;

-- ── 1. THE BEATS ────────────────────────────────────────────────────────────────────────────────
create table public.arrivals_beats (
  slot      int         primary key check (slot between 0 and 3599),
  at        timestamptz not null,
  ms        numeric     not null check (ms >= 0),
  fleets    int,
  days      int,
  asked     int,
  error     text
);
comment on table public.arrivals_beats is
  '0248: one row a second of the hour (slot = floor(epoch) mod 3600), overwritten an hour later: the arrivals beat that ran in that second — its instant (the run''s now()), how long it took, what public.tick_arrivals answered (fleets_touched, days_resolved, asked), or the error it was rolled back on. One writer: public.tick_arrivals_each_second. Server-only.';
alter table public.arrivals_beats enable row level security;
revoke all on table public.arrivals_beats from public, anon, authenticated;

-- ── 2. THE WARM HAND ────────────────────────────────────────────────────────────────────────────
create procedure public.tick_arrivals_each_second(p_beats int default null)
language plpgsql
as $$
-- 0248: THE arrivals job (pg_cron byeharu-voyage:arrivals, '* * * * *', CALL). One session runs
-- public.tick_arrivals() once a second until its minute ends (p_beats: that many beats instead — a probe),
-- each run in its own transaction, so its now() is that second's. A new session a second compiled and
-- planned the whole arrival path again every second (prod 2026-10-27: p50 0.71 s, ~48 runs a minute); one
-- a minute pays that once. No SECURITY DEFINER, no SET: a procedure that commits may carry neither; it runs
-- as the job's owner. A run that raises is rolled back alone and warned, and the next second runs. Stops at
-- once when the job is switched off (cron.job.active, public.clock_jobs()).
declare
  v_start  timestamptz := clock_timestamp();
  v_end    timestamptz := date_trunc('minute', v_start) + interval '1 minute';
  v_at     timestamptz := date_trunc('second', v_start);   -- the beat's second: the first is now
  v_cron   boolean := exists (select 1 from pg_extension where extname = 'pg_cron');
  v_n      int := 0;
  v_fail   int := 0;
  v_t      timestamptz;
  v_r      jsonb;
  v_err    text;
begin
  loop
    exit when p_beats is null and v_at >= v_end;
    exit when p_beats is not null and v_n >= p_beats;
    exit when v_cron and not exists (select 1 from public.clock_jobs() j
                                      where j.jobname = 'byeharu-voyage:arrivals' and j.active);
    if clock_timestamp() < v_at then
      perform pg_sleep(extract(epoch from v_at - clock_timestamp()));
    end if;
    commit;   -- the run's transaction starts here: its now() is this second's

    v_t := clock_timestamp();
    v_err := null;
    begin
      v_r := public.tick_arrivals();
    exception when others then
      v_fail := v_fail + 1;
      v_err := sqlstate || ': ' || sqlerrm;
      v_r := null;
      raise warning 'tick_arrivals_each_second: the run at % was rolled back (SQLSTATE %: %); the next second runs',
        now(), sqlstate, sqlerrm;
    end;
    insert into public.arrivals_beats (slot, at, ms, fleets, days, asked, error)
    values ((floor(extract(epoch from now()))::bigint % 3600)::int, now(),
            round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1),
            (v_r->>'fleets_touched')::int, (v_r->>'days_resolved')::int, (v_r->>'asked')::int, v_err)
    on conflict (slot) do update
      set at = excluded.at, ms = excluded.ms, fleets = excluded.fleets, days = excluded.days,
          asked = excluded.asked, error = excluded.error;
    commit;
    v_n := v_n + 1;

    -- the next beat: the next whole second, or at once if this one ran past it
    v_at := greatest(v_at + interval '1 second', date_trunc('second', clock_timestamp()));
  end loop;
  raise notice 'tick_arrivals_each_second: % run(s), % rolled back, % s', v_n, v_fail,
    round(extract(epoch from clock_timestamp() - v_start)::numeric, 1);
end $$;
comment on procedure public.tick_arrivals_each_second(int) is
  '0248: THE arrivals job (pg_cron byeharu-voyage:arrivals, every minute, CALL): public.tick_arrivals() once a second in one session until the minute ends, each run its own transaction; a raised run rolled back alone and warned; stops when the job is switched off. Writes public.arrivals_beats. Server-only.';
revoke all on procedure public.tick_arrivals_each_second(int) from public, anon, authenticated;

-- ── 3. THE JOB ──────────────────────────────────────────────────────────────────────────────────
do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice '0248: pg_cron is not installed here (PGlite) — the job is not re-pointed in this database';
    return;
  end if;
  perform cron.alter_job(j.jobid, schedule := '* * * * *', command := 'call public.tick_arrivals_each_second()')
     from cron.job j where j.jobname = 'byeharu-voyage:arrivals';
end $cron$;

-- ── 4. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_b    record;
  v_pp   record;
  v_def  text;
  v_sched text;
  v_cmd   text;
begin
  select * into v_b from before_0248;

  -- (a) THE RUN IS UNTOUCHED: tick_arrivals' definition, ACL, volatility, definer, config — byte for byte
  select md5(replace(pg_get_functiondef(p.oid), E'\r', '')) as def_md5, coalesce(p.proacl::text, '') as acl,
         p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
    into v_pp from pg_proc p where p.oid = 'public.tick_arrivals(timestamptz)'::regprocedure;
  if v_pp.def_md5 <> v_b.def_md5 or v_pp.acl <> v_b.acl or v_pp.vol <> v_b.vol or v_pp.secdef <> v_b.secdef
     or v_pp.cfg <> v_b.cfg then
    raise exception '0248 self-assert FAIL: public.tick_arrivals moved';
  end if;

  -- (b) THE HAND calls the run exactly once, with its default argument, between two commits; it carries no
  -- definer and no SET (a committing procedure may not); nobody but the server can call it or read its beats
  v_def := replace(pg_get_functiondef('public.tick_arrivals_each_second(int)'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, 'v_r := public.tick_arrivals();', ''))) / length('v_r := public.tick_arrivals();') <> 1
     or (length(v_def) - length(replace(v_def, 'tick_arrivals(', ''))) / length('tick_arrivals(') <> 2   -- the call, and the comment naming it
     or (length(v_def) - length(replace(v_def, E'\n    commit;', ''))) / length(E'\n    commit;') <> 2 then
    raise exception '0248 self-assert FAIL: tick_arrivals_each_second does not run public.tick_arrivals() once between two commits';
  end if;
  if (select p.prosecdef or p.proconfig is not null or p.prokind <> 'p'
        from pg_proc p where p.oid = 'public.tick_arrivals_each_second(int)'::regprocedure) then
    raise exception '0248 self-assert FAIL: tick_arrivals_each_second is not a plain procedure';
  end if;
  if has_function_privilege('anon', 'public.tick_arrivals_each_second(int)', 'execute')
     or has_function_privilege('authenticated', 'public.tick_arrivals_each_second(int)', 'execute')
     or has_table_privilege('anon', 'public.arrivals_beats', 'select')
     or has_table_privilege('authenticated', 'public.arrivals_beats', 'select') then
    raise exception '0248 self-assert FAIL: a client role can call the hand or read its beats';
  end if;

  -- (c) THE JOB, where there is a scheduler
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute 'select schedule, command from cron.job where jobname = ''byeharu-voyage:arrivals''' into v_sched, v_cmd;
    if v_sched is distinct from '* * * * *' or v_cmd is distinct from 'call public.tick_arrivals_each_second()' then
      raise exception '0248 self-assert FAIL: arrivals on "%" running "%"', v_sched, v_cmd;
    end if;
  end if;

  -- (d) POSTURE
  if (select count(*) from public.client_rpc_entry_points()) <> v_b.entry_points then
    raise exception '0248 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0248 self-assert FAIL: a wall moved';
  end if;

  raise notice '0248 self-assert ok: ONE WARM HAND KEEPS THE SECOND. public.tick_arrivals untouched (definition md5, ACL, volatility, definer, config byte-identical); public.tick_arrivals_each_second (a plain procedure, server-only) runs it once a second between two commits for its minute, a raised run rolled back alone, stops when the job is off; public.arrivals_beats (≤ 3,600 rows, server-only) keeps each beat; arrivals %; registry unchanged; walls 0.',
    case when v_sched is null then 'not scheduled here (no pg_cron)' else format('on "%s" running "%s"', v_sched, v_cmd) end;
end $$;
