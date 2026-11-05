-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 25 — GRAPHS BY DAY, WEEK AND MONTH  (migration 0316)
--
--   0316's own self-assert runs on probe rows on days no real row has (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof runs the REAL
--   public.tick_history over the WHOLE world: the mark, the backfill, the ledger read, and what the job does NOT touch.
--
-- @pass HIST_BACKFILL   a first run starts at the oldest count and closes one past day a run until it reaches today
-- @pass HIST_ONCE       a ledger row counts once however many runs pass over it, and a row inside the lag waits for a later run
-- @pass HIST_REPORT     a company's days add up to what world.report('all') says it made
-- @pass HIST_CARRIED    a merchant's rolled-up NPC_CARRIED row is never counted a second time
-- @pass HIST_LEDGER     the job leaves public.ledger exactly as it found it
-- @pass HIST_TRIM_OFF   at knob 0 the job deletes nothing from stats_city_good
-- @pass HIST_RECEIPT    a run leaves its receipt with its phases and its cost
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_p     uuid;
  v_uid   constant uuid := '00000000-0316-4000-8000-0000000000c5';
  v_r     jsonb;
  v_x     jsonb;
  v_runs  int := 0;
  v_led   bigint;
  v_cg    bigint;
  v_s    bigint := 9100000000000;
begin
  -- a world with counts on three past days, as the job finds it on the day it is deployed
  insert into public.stats_world (slot, at, game_day, players, merchants, cities, set_aside, minted, removed, moved, sold, bought, units, trades, period, recent, n)
  select v_s + d, (v_today - d)::timestamp at time zone 'UTC' + interval '6 hours', 1, 10 * d, 20 * d, 30 * d, 40 * d, d, 0, 0, 0, 0, 0, 0, '{}', '{}', 4
    from generate_series(1, 3) d;
  update public.history_mark set open_day = null, ledger_through = '2000-01-01 00:00:00+00';
  delete from public.history_world_day;

  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (v_uid, 'Proof 25 house', (select g.nation_id from public.great_powers g order by g.nation_id limit 1), 0, false) returning id into v_p;
  perform public.credit(v_p, 'FOUNDING', 1000);
  perform public.credit(v_p, 'SELL', 700);
  perform public.credit(v_p, 'WAGES', -250);
  perform public.credit(v_p, 'NPC_CARRIED', 33);
  select count(*) into v_led from public.ledger;
  select count(*) into v_cg from public.stats_city_good;

  -- the rows above stand at now(): a run at now() must leave them for later (the lag)
  v_r := public.tick_history(now());
  if exists (select 1 from public.history_company_day h where h.player_id = v_p) then
    raise exception 'PROOF 25 FAIL: a run read a ledger row inside the lag: %', v_r;
  end if;
  if not exists (select 1 from public.history_world_day h where h.day = (select min((w.at at time zone 'UTC')::date) from public.stats_world w)) then
    raise exception 'PROOF 25 FAIL: a first run did not start at the oldest count: %', v_r;
  end if;
  while (select h.open_day from public.history_mark h) < v_today loop
    v_runs := v_runs + 1;
    if v_runs > 400 then
      raise exception 'PROOF 25 FAIL: the backfill does not end';
    end if;
    perform public.tick_history(now());
  end loop;
  if not exists (select 1 from public.history_world_day h where h.day = v_today - 1 and h.players = 10) or not exists (select 1 from public.history_world_day h where h.day = v_today - 3 and h.players = 30) then
    raise exception 'PROOF 25 FAIL: the backfill missed a day';
  end if;
  raise notice 'PASS: HIST_BACKFILL — from the oldest count to today in % more run(s), % day rows', v_runs, (select count(*) from public.history_world_day);

  -- an hour on, the rows stand behind the lag: the run takes them; a second run must not take them again
  perform public.tick_history(now() + interval '1 hour');
  perform public.tick_history(now() + interval '2 hours');
  perform public.tick_history(now() + interval '2 hours');
  v_x := (select to_jsonb(h) from public.history_company_day h where h.player_id = v_p);
  if (v_x ->> 'earned')::bigint <> 700 or (v_x ->> 'lost')::bigint <> 250 then
    raise exception 'PROOF 25 FAIL: a ledger row did not count exactly once: %', v_x;
  end if;
  raise notice 'PASS: HIST_ONCE — three runs, earned % and lost % once; a row in the lag waited', v_x ->> 'earned', v_x ->> 'lost';
  raise notice 'PASS: HIST_CARRIED — 33 d. of NPC_CARRIED counted nowhere: earned %', v_x ->> 'earned';

  perform cmd.assume_identity(v_uid);
  if (world.report('all') ->> 'total')::bigint - 33
     <> (select sum(h.earned - h.lost) from public.history_company_day h where h.player_id = v_p) then
    raise exception 'PROOF 25 FAIL: the days do not add up to the report: % against %', world.report('all') ->> 'total', v_x;
  end if;
  raise notice 'PASS: HIST_REPORT — the report''s total less the carried row is the days'' net, %', (v_x ->> 'earned')::bigint - (v_x ->> 'lost')::bigint;

  if (select count(*) from public.ledger) <> v_led then
    raise exception 'PROOF 25 FAIL: the job moved the ledger';
  end if;
  raise notice 'PASS: HIST_LEDGER — % ledger rows before and after', v_led;

  if (select count(*) from public.stats_city_good) <> v_cg then
    raise exception 'PROOF 25 FAIL: the trim ran at knob 0';
  end if;
  raise notice 'PASS: HIST_TRIM_OFF — stats_city_good untouched at knob 0, % rows', v_cg;

  select r.receipt into v_x from public.history_runs r order by r.at desc limit 1;
  if v_x -> 'phases' ->> 'ledger' is null or v_x -> 'phases' ->> 'today' is null or v_x ->> 'ms' is null or (select count(*) from public.history_runs) < 2 then
    raise exception 'PROOF 25 FAIL: a run left no receipt: %', v_x;
  end if;
  raise notice 'PASS: HIST_RECEIPT — newest run % ms', v_x ->> 'ms';
end
$$;
