-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0420 - EVERY HARBOUR IS REPRICED EVERY FIFTEEN MINUTES  (drift_spread_runs 50 -> 15; the clock's door no longer moves it)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none
--
-- THE OWNER'S ORDER (2026-11-15, verbatim): "market price rewritten - all 156,621 - every 15 minute would be good".
--   He was shown: before 0409 every one of the 156,621 port_goods rows was rewritten every minute; since 0409 + 0413 the drift job
--   (pg_cron byeharu-voyage:drift, every minute) steps one harbour in drift_spread_runs a run, and drift_spread_runs is 50 on production
--   (0409 set 10; 0413's door public.clock_set multiplied it by 5 at the switch to the one-hour day), so a harbour is repriced every 50 minutes.
--   DECIDED (the lead): every harbour every 15 REAL minutes, spread evenly, one fifteenth of the harbours a run; not all of them on the quarter
--   hour (a spike every 15 minutes is what docs/DATABASE_BUDGET.md forbids).
--
-- HOW OFTEN A HARBOUR IS REPRICED (read, not assumed): public.drift_ports_due(t) gives the harbours whose place in the port order k satisfies
--   k mod n = floor(epoch(t) / 60) mod n, n = drift_spread_runs. So a harbour's turn comes every n MINUTES of real time, whatever the slot length:
--   the job's cadence (one minute) times n. drift_slot_seconds (300 on production) decides only how far one turn steps the walk: a turn after k
--   slots takes ONE compounded step with the law of k one-slot steps (0409, public.tick_market_drift). At n = 15 on production's clock a turn is
--   exactly 900 / 300 = 3 slots on (any 15 real minutes hold 3 boundaries of a 300 s slot, anchored or not), so every visit writes every row
--   of that harbour.
--
-- WHAT THIS FILE DOES:
--   1. drift_spread_runs 50 -> 15 (only from 50: any other value refuses; its description records 50).
--   2. THE DOOR NO LONGER MOVES IT. public.clock_set (0413) multiplied drift_spread_runs by old / new so a harbour kept "the same number of slots"
--      between turns. That is no longer needed and is now wrong: the compounded step makes the walk's law per voyage-day the same at any spread
--      (0409), and the spread is the database's pace in REAL minutes (the owner's "every 15 minute", the budget's rows a real minute). Left in
--      the door, a rollback of the clock to 960 would set it to 3: 52,000 rows a minute. So the spread joins what "STAYS AS IT IS" (real time,
--      like every cron cadence). Two hunks in public.clock_set, each once and reversing: the comment and the one UPDATE of drift_spread_runs.
--
-- PRICES MOVE EXACTLY AS FAR PER VOYAGE-DAY AS NOW: drift_sigma, drift_theta, drift_clamp and drift_slot_seconds are not touched. A harbour
--   stepped at 15-minute turns takes theta^3 x drift + sigma x sqrt((1 - theta^6) / (1 - theta^2)) x N at each turn; three turns (45 minutes)
--   have the law of nine one-slot steps, as five 50-minute turns of ten slots have the law of fifty: the walk's position after a voyage-day
--   is distributed the same at any spread. The self-assert shows it with the noise put out (an hour of four turns equals one turn after the hour,
--   theta^12); proof 117 shows the spread of the noise statistically and through the door.
--
-- budget: the drift job (byeharu-voyage:drift, every minute, its schedule NOT changed) writes about 156,621 / 15 = ~10,400 port_goods rows per run
--   (17 or 18 harbours of 268), up from ~3,130 rows per run at 50: +7,300 rows a minute, every minute, evenly (the 0408 world wrote 156,621 rows
--   a minute). Over the budget's 5,000 rows a run by the owner's order of 2026-11-15; the gate is read before the deploy.
-- WHAT A PLAYER SEES: a harbour nobody is looking at moves its price every 15 minutes instead of every 50, in a step as large as the 3 slots it
--   stands for. A quay somebody opens is still stepped on that read (unchanged).
-- LOCKS: CREATE OR REPLACE of public.clock_set by hunks; one knob row. TIME: the probe steps one harbour's rows five times and twice reads the
--   due list over fifteen minutes, in rolled-back sub-transactions: expected under 3 s on prod. BUDGET: statement_timeout 60 s; fails above 30 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/drift-15/rollback-0420.sql, a draft. At once, with no file: drift_spread_runs 50.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; the knob 15; then
--   the probes: fifteen runs give every harbour once and a fifteenth each; a harbour's next turn is fifteen minutes on; the compounded step's law.
-- VERSION: 0420 = prod head 0418 + 2 (0419 is held by the Stats builder working now); it cuts no function 0419 cuts.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.clock_set(integer,timestamp with time zone)'];
  v_t0        timestamptz := clock_timestamp();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_m         int;
  v_ports     int;
  v_fn_before text;
  v_port      uuid;
  v_good      uuid;
  v_at        timestamptz := date_trunc('minute', now());
  v_s0        bigint;
  v_k         bigint;
  v_da        numeric;
  v_db        numeric;
  v_want      numeric;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if (select wc.description from public.world_config wc where wc.key = 'drift_spread_runs') like '0420:%' then
    raise exception '0420 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.clock_set(integer,timestamp with time zone)') is null or to_regprocedure('public.drift_ports_due(timestamp with time zone)') is null then
    raise exception '0420 refuses: the drift''s spread (0409) or the clock''s door (0413) is not in this world';
  end if;
  if public.wc_int('drift_spread_runs') is distinct from 50 then
    raise exception '0420 refuses: drift_spread_runs is %, not the 50 this file was written against (0409''s 10 x 0413''s 5)', public.wc_int('drift_spread_runs');
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0420 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0420
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE KNOB ──
  update public.world_config
     set value = to_jsonb(15), updated_at = now(),
         description = '0420: the drift job (pg_cron byeharu-voyage:drift, every minute) steps one harbour in this many a run, by its place in the port order (public.drift_ports_due), so EVERY HARBOUR IS REPRICED ONCE IN THIS MANY REAL MINUTES (the owner, 2026-11-15: "market price rewritten - all 156,621 - every 15 minute would be good"): about port_goods / this rows a run. A harbour stepped after k missed slots takes one compounded step with the law of k steps (public.tick_market_drift, 0409), so the walk per voyage-day does not depend on it. A pace in real time: public.clock_set does NOT move it (since 0420). 50 before 0420 (0409 set 10; 0413''s door made it 50); 1 = every harbour every run.'
   where key = 'drift_spread_runs' and value = to_jsonb(50);
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception '0420 self-assert FAIL: drift_spread_runs was not moved from 50 (% rows)', v_n;
  end if;

  -- ── 3. THE HUNKS: the door no longer moves the spread ──
  create temp table hunk_0420 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0420 values
  (1, c_cut[1],
$h$--   same way); the drift job's spread (x f); the economy's rates per real time (/ f) and its half-lives (x f); and the clock's anchor.
$h$,
$h$--   same way); the economy's rates per real time (/ f) and its half-lives (x f); and the clock's anchor.
-- 0420: NOT the drift job's spread (drift_spread_runs): it is a pace in real minutes (every harbour once in that many one-minute runs; the
--   owner's "every 15 minute") and the database's rows a real minute; the compounded step (0409) keeps the walk per voyage-day whatever it is.
$h$),
  (2, c_cut[1],
$h$  update public.world_config wc
     set value = to_jsonb(greatest(1, round((wc.value #>> '{}')::numeric * v_f))::int), updated_at = now()
   where wc.key = 'drift_spread_runs';
$h$,
$h$  -- 0420: drift_spread_runs is not moved here (a pace in real minutes; see the head of this body)
$h$);
  for h in select * from hunk_0420 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0420 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0420 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0420 p where p.fn = h.fn) then
      raise exception '0420 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0420 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0420 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0420 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0420 self-assert FAIL: another function moved';
  end if;
  if position('drift_spread_runs''' in replace(pg_get_functiondef('public.clock_set(integer,timestamp with time zone)'::regprocedure), E'\r', '')) > 0 then
    raise exception '0420 self-assert FAIL: public.clock_set still names the knob drift_spread_runs';
  end if;
  if public.wc_int('drift_spread_runs') <> 15 then
    raise exception '0420 self-assert FAIL: drift_spread_runs is %, not 15', public.wc_int('drift_spread_runs');
  end if;

  -- ── 4. THE PROBES ──
  -- 4a WHOSE TURN: over fifteen consecutive minutes every harbour is given exactly once, a fifteenth of them a run (the counts differ by one at most).
  select count(*) into v_ports from public.ports;
  select count(*), count(distinct d.id) into v_n, v_m
    from generate_series(0, 14) g cross join lateral public.drift_ports_due(v_at + make_interval(mins => g)) d;
  if v_n <> v_ports or v_m <> v_ports then
    raise exception '0420 self-assert FAIL: fifteen runs give % turns over % harbours; the world has %', v_n, v_m, v_ports;
  end if;
  select max(c), min(c) into v_n, v_m
    from (select count(*) as c from generate_series(0, 14) g cross join lateral public.drift_ports_due(v_at + make_interval(mins => g)) d group by g) x;
  if v_n - v_m > 1 or v_n > ceil(v_ports / 15.0) then
    raise exception '0420 self-assert FAIL: a run takes % harbours and another %: not a fifteenth each of %', v_n, v_m, v_ports;
  end if;
  v_note := format('the turn: %s harbours each once in 15 runs, %s to %s a run', v_ports, v_m, v_n);

  -- 4b THE NEXT TURN: the first port's turn comes at one minute of the next fifteen, then not for fourteen minutes, then again fifteen minutes on.
  select pg.port_id, pg.good_id into v_port, v_good from public.port_goods pg order by pg.port_id, pg.good_id limit 1;
  if v_port is not null then
    select array_agg(g order by g) into v_def
      from (select g from generate_series(0, 44) g where exists (select 1 from public.drift_ports_due(v_at + make_interval(mins => g)) d where d.id = v_port)) x;
    select g into v_n from generate_series(0, 14) g where exists (select 1 from public.drift_ports_due(v_at + make_interval(mins => g)) d where d.id = v_port);
    if v_def::int[] is distinct from array[v_n, v_n + 15, v_n + 30] then
      raise exception '0420 self-assert FAIL: in 45 minutes the harbour''s turns fall at minutes % (want %, %, %)', v_def, v_n, v_n + 15, v_n + 30;
    end if;
    v_note := v_note || format('; the next turn: one harbour at minutes %s of the next 45', v_def);

    -- 4c THE COMPOUNDED STEP'S LAW, with the noise put out (sigma 0, theta 0.9) so the figure is exact: one row at drift 0.1 stepped at four
    --    turns fifteen minutes apart ends where one step after the hour puts it: theta^(slots in the hour) x 0.1. On production's 300 s slot each
    --    turn is three slots and the hour twelve. Rolled back.
    begin
      update public.world_config set value = to_jsonb(0) where key = 'drift_sigma';
      update public.world_config set value = to_jsonb(0.9) where key = 'drift_theta';
      v_s0 := public.drift_slot_of(v_at);
      v_k  := public.drift_slot_of(v_at + interval '60 minutes') - v_s0;
      if mod(900, public.wc_num('drift_slot_seconds')) = 0
         and (public.drift_slot_of(v_at + interval '15 minutes') - v_s0) * public.wc_num('drift_slot_seconds') <> 900 then
        raise exception '0420 self-assert FAIL: fifteen minutes are % slots of % s', public.drift_slot_of(v_at + interval '15 minutes') - v_s0, public.wc_num('drift_slot_seconds');
      end if;
      update public.port_goods set drift = 0.1, drift_slot = v_s0, last_regen_day = world.game_day(v_at) where port_id = v_port and good_id = v_good;
      for v_n in 1 .. 4 loop
        perform public.tick_market_drift(v_at + make_interval(mins => 15 * v_n), v_port);
      end loop;
      select pg.drift into v_da from public.port_goods pg where pg.port_id = v_port and pg.good_id = v_good;
      update public.port_goods set drift = 0.1, drift_slot = v_s0, last_regen_day = world.game_day(v_at) where port_id = v_port and good_id = v_good;
      perform public.tick_market_drift(v_at + interval '60 minutes', v_port);
      select pg.drift into v_db from public.port_goods pg where pg.port_id = v_port and pg.good_id = v_good;
      v_want := 0.1 * power(0.9::numeric, v_k);
      if abs(v_da - v_want) > 0.0005 or abs(v_db - v_want) > 0.0005 then
        raise exception '0420 self-assert FAIL: an hour is % slots; four 15-minute turns give %, one turn after the hour %, the law %', v_k, v_da, v_db, round(v_want, 4);
      end if;
      v_note := v_note || format('; the step: an hour of %s slots, four turns %s, one turn %s, theta^%s x 0.1 = %s', v_k, v_da, v_db, v_k, round(v_want, 4));
      raise exception sqlstate 'BV420';
    exception when sqlstate 'BV420' then null;
    end;
    if v_note not like '%the step:%' then
      raise exception '0420 self-assert FAIL: the step''s probe did not run to its end';
    end if;
    if public.wc_num('drift_sigma') = 0 then
      raise exception '0420 self-assert FAIL: the step''s probe was not rolled back';
    end if;
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0420 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0420 self-assert ok: EVERY HARBOUR IS REPRICED EVERY FIFTEEN MINUTES. drift_spread_runs 50 -> 15; two hunks in public.clock_set, each once and reversing (the door no longer moves the spread); grants and volatility unmoved; no other function moved. Probes: %; % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
