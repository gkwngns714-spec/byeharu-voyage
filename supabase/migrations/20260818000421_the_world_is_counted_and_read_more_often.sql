-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0421 - THE WORLD IS COUNTED AND READ MORE OFTEN  (the Stats count every 15 minutes again; request boards re-asked in 30 minutes; the pirates'
--        roster fills one fleet in 5 minutes; the client reads the world every 15 s: the headroom spent, with room left)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none
--
-- THE OWNER'S ORDER (2026-11-15, verbatim): "like market price rewritting, make everything as much as more often, faster, as possible, get it?"
--   and, the same day: "there should be a room of course, not just too tight". So: what players SEE is made fresher, and after this file, 0419,
--   0420 and the pirates' roster at full size the database still sits at about half of each limit in docs/DATABASE_BUDGET.md or under it
--   (the one exception, the size, was over half before this file and is retention's lever, not speed's: docs/dev-log/2026-11-15-pace-up.md).
--
-- MEASURED (prod, read-only, three reads, scripts/ops/harness/pace-up/measure-*.sql, at head 0418; the gate green: beat 74 ms mean / 247 ms
--   p95, 888 MB, 0 disk waits). Every one of the 23 pg_cron jobs and its last two hours is in the dev-log. The ones this file moves:
--     byeharu-voyage:stats   '6,36 * * * *'   4 runs, 24.9 s mean, 26.7 s max, 0 failed; ~2,450 rows written a run (its receipts' `wrote`).
--     contract_wind_retry_minutes 60          the wind job (every minute): 1.4 s mean, 3.2 s max, under its 4 s contract_wind_ms; 3 posts a run at most.
--     pirate_add_minutes 10                   the pirates' job (every minute): 0.47 s mean, 1.24 s max.
--
-- WHAT THIS FILE DOES (settings only: no function, no table, no index):
--   1. THE STATS COUNT EVERY 15 MINUTES (pg_cron byeharu-voyage:stats '6,36 * * * *' -> '6,21,36,51 * * * *', 0214's own cadence, which 0409
--      halved during the disk incident). The Stats tab's figures and its 1-day graphs get a point every 15 minutes, not 30. The history job
--      (12, 27, 42, 57: "six minutes after each Stats count", 0316) is NOT moved: it recounts today from the count, so it now finds a fresh count
--      at every run instead of every other one.
--   2. A REQUEST BOARD THAT COULD NOT POST IS ASKED AGAIN IN 30 MINUTES (contract_wind_retry_minutes 60 -> 30). The wind job's pace is still held
--      by contract_wind_posts (3 harbours a run) and contract_wind_ms (4 s of work a minute): it cannot cost more than it may today.
--   3. THE PIRATES' ROSTER FILLS ONE FLEET IN 5 MINUTES (pirate_add_minutes 10 -> 5). The roster reaches its full size in half the time; the
--      load of the full roster is the same, and is already counted in the margin below.
--   (4. In the same PR, not in this file: the client reads the world every 15 s instead of 30 s, src/domain/readClock.ts.)
--
-- NOT CHANGED, AND WHY (the dev-log has every job): time_compression 192 (the owner's); the retention windows (storage, not speed); the
--   autovacuum thresholds (0412: more passes cost disk for nothing a player sees); the 10 s beat budget; the price snapshot (*/10: it already
--   samples finer than 0420's 15-minute reprice; */5 would double the fine price rows and re-read port_goods while 0420 triples its churn);
--   the jobs already every minute (arrivals each second, lap-starts, waiting-asks, compact, cargo-ships, navy, pirates, battles, drift,
--   contract-wind), whose budget knobs are not binding (compact left 0 of 8 s; waiting-asks spent 0.7 of 12 s, none due); the hourly books
--   (city, reconcile, refits, keep-beats); population (its 3,000 s slot steps once; a faster job steps nothing); the calendar and the fix jobs.
--
-- WHAT IT COSTS (rows a minute, as the budget asks; the dev-log has the table and the margin):
--   the Stats count +2 runs an hour x ~2,450 rows = +82 rows a minute, +50 s of work an hour; its fine tier holds up to ~208,000 more rows
--   (72 h of goods and cities, 26 h of city goods) = up to ~42 MB more on disk after three days. The wind: at most +9 rows a minute (3 posts a
--   run, already its ceiling). The pirates: +3 rows a minute while the roster fills, none after. TOTAL about +95 rows a minute, against the
--   +7,300 of 0420. Expected after everything (0419, 0420, this, the full roster): the beat ~100 ms mean (limit 2,000, half 1,000); the jobs
--   ~33 s of work a minute on 2 cores (120 core-seconds a minute: ~28 %, half is 60 s); disk waits 0 (limit 5); ~930 MB (limit 1,500).
-- FIRST TO STEP BACK if the gate goes red: the Stats count, back to '6,36 * * * *' (the exact SQL is in the dev-log and in the rollback draft).
-- LOCKS: three world_config rows and one cron.job row (pg_cron only). TIME: milliseconds. BUDGET: statement_timeout 30 s, lock_timeout 5 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/pace-up/rollback-0421.sql, a draft: the three old values. At once, with no file: the
--   two knobs by their old values in their descriptions.
-- SELF-ASSERT: no function moved; the two knobs at their new values with the old ones written into their descriptions; the Stats job at its new
--   cadence and still active as it was (pg_cron only); a second run of this file refuses. Its behaviour: proof 118 (the roster at 5 minutes).
-- VERSION: 0421 = prod head 0418 + 3 (0419 the Stats builder's, 0420 the drift's; neither touches these settings).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0        timestamptz := clock_timestamp();
  v_fn_before text;
  v_n         int;
  v_active    boolean;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: once, and only over the values it was written against ──
  if (select wc.description from public.world_config wc where wc.key = 'pirate_add_minutes') like '0421:%' then
    raise exception '0421 refuses: it has been applied once';
  end if;
  if public.wc_int('pirate_add_minutes') is distinct from 10 or public.wc_int('contract_wind_retry_minutes') is distinct from 60 then
    raise exception '0421 refuses: pirate_add_minutes is % and contract_wind_retry_minutes is %, not the 10 and 60 this file was written against',
      public.wc_int('pirate_add_minutes'), public.wc_int('contract_wind_retry_minutes');
  end if;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');

  -- ── 1. THE KNOBS (each only from its old value) ──
  -- budget: the wind job (byeharu-voyage:contract-wind, every minute, schedule NOT changed) asks a harbour that could not post again after 30
  --   minutes, not 60: at most 3 posts a run as today (contract_wind_posts), about 9 rows a run at the most, inside its 4 s contract_wind_ms.
  update public.world_config
     set value = to_jsonb(30), updated_at = now(),
         description = '0421: how long the wind job leaves a harbour that could not post before asking it again, in real minutes (the owner, 2026-11-15: "make everything as much as more often, faster, as possible"). 60 before 0421 (0315). The job''s pace is held by contract_wind_posts and contract_wind_ms, not by this.'
   where key = 'contract_wind_retry_minutes' and value = to_jsonb(60);
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception '0421 self-assert FAIL: contract_wind_retry_minutes was not moved from 60 (% rows)', v_n;
  end if;

  -- budget: the pirates' job (byeharu-voyage:pirates, every minute, schedule NOT changed) adds one roster fleet in 5 minutes, not 10, while the
  --   roster fills: 20 to 30 rows an add (a company, a fleet, up to 8 ships, the roster row, two treasury posts), +3 rows a minute at most; none once the roster is full.
  update public.world_config
     set value = to_jsonb(5), updated_at = now(),
         description = '0421: the pirates add at most one fleet in this many real minutes (public.pirate_add), so the roster fills twice as fast (the owner, 2026-11-15: "make everything as much as more often, faster, as possible"). 10 before 0421 (0414); before 0414 it was navy_build_hours (24 hours), which stays the navy''s.'
   where key = 'pirate_add_minutes' and value = to_jsonb(10);
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception '0421 self-assert FAIL: pirate_add_minutes was not moved from 10 (% rows)', v_n;
  end if;

  -- ── 2. THE STATS COUNT EVERY 15 MINUTES (pg_cron only; the schedule alone, from 0409's value alone, its `active` unmoved) ──
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select j.active from cron.job j where j.jobname = 'byeharu-voyage:stats'$q$ into v_active;
    -- budget: the Stats count (byeharu-voyage:stats) runs 4 times an hour, not 2: about 2,450 rows written a run (its receipts' `wrote`), +82 rows
    --   a minute; 25 s of work a run; its fine tier holds up to ~208,000 more rows (~42 MB) after 72 hours. 0214's cadence; 0409 halved it.
    execute $q$select cron.alter_job(j.jobid, schedule := '6,21,36,51 * * * *') from cron.job j
                where j.jobname = 'byeharu-voyage:stats' and j.schedule = '6,36 * * * *'$q$;
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:stats' and j.schedule = '6,21,36,51 * * * *'$q$ into v_n;
    if v_n <> 1 then
      raise exception '0421 self-assert FAIL: byeharu-voyage:stats is not at 6,21,36,51 (it was not at 6,36 before this file?)';
    end if;
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:stats' and j.active is not distinct from $1$q$ into v_n using v_active;
    if v_n <> 1 then
      raise exception '0421 self-assert FAIL: the Stats job''s active flag moved';
    end if;
  else
    raise notice '0421: pg_cron is not installed here (PGlite): the Stats schedule is pg_cron''s alone; the knobs are set.';
  end if;

  -- ── 3. SELF-ASSERT ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fn_before then
    raise exception '0421 self-assert FAIL: a function moved';
  end if;
  if public.wc_int('pirate_add_minutes') <> 5 or public.wc_int('contract_wind_retry_minutes') <> 30
     or (select count(*) from public.world_config wc
          where (wc.key = 'pirate_add_minutes' and wc.description like '0421:%10 before 0421%')
             or (wc.key = 'contract_wind_retry_minutes' and wc.description like '0421:%60 before 0421%')) <> 2 then
    raise exception '0421 self-assert FAIL: the knobs are not this file''s, or their old values are not written down';
  end if;
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0421 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0421 self-assert ok: THE WORLD IS COUNTED AND READ MORE OFTEN. pirate_add_minutes 10 -> 5, contract_wind_retry_minutes 60 -> 30, the Stats count %; no function moved; % ms.',
    case when exists (select 1 from pg_extension where extname = 'pg_cron') then '6,36 -> 6,21,36,51' else 'not here (no pg_cron)' end,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
