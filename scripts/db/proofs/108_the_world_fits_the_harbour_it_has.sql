-- ═════════════════════════════════════════════════════════════════════════════════════
-- PROOF 108 - THE WORLD FITS THE HARBOUR IT HAS  (migration 0414; docs/dev-log/2026-11-14-slim-db.md)
--
--   On the world's own harbours and merchants, rolled back with proof.mjs's transaction. Every row that goes is a probe row staged here, and
--   every one goes by the rule that lets real rows go: the compactor (public.tick_compact, public.npc_compact_houses) and the history trim.
--
-- @pass SD_TURN    whose turn it is: over ten runs in a row public.drift_ports_due gives every harbour exactly once, about a tenth a run; with drift_spread_runs 1 it gives every harbour every run
-- @pass SD_STEP    the compounded step has the law of the steps it stands for: rows 50 slots behind, from drift 0, come out with the spread of 50 one-slot steps (sigma x sqrt((1 - theta^100) / (1 - theta^2))), and rows one slot behind with the spread of one (sigma)
-- @pass SD_WANTS   the compactor deletes the city wants past the window, a bounded batch a run: of 5,000 probe rows in periods long past, 2,000 go a run until none is left; the wants of the current period and the one before stay; a delete outside the compactor is refused; with the knob at 0 nothing goes
-- @pass SD_LAPS    the compactor deletes a merchant's laps past the window, a bounded batch a visit: of 100 probe laps 75 are past both her newest 24 and the 26 hours; 40 go on the first visit (compact_trim_rows 40), 35 on the second, none on the third; her newest 24, the open lap and the lap closed 20 hours ago stay
-- @pass SD_CITYGOOD the history trim deletes stats_city_good past stats_city_good_keep_days (3): probe rows ten days old go, probe rows two days old stay
-- @pass SD_KNOBS   every amount is a knob with the value 0414 gave it, the compactor's three limits at the values its constants had
-- ═════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  v_n      int;
  v_m      int;
  v_ports  int;
  v_port   uuid;
  v_good   uuid;
  v_slot   bigint;
  v_sd     numeric;
  v_want   numeric;
  v_period bigint;
  v_live   bigint;
  v_s      text := '';
  v_house  uuid;
  v_route  uuid;
  v_at     timestamptz := now() - interval '3650 days';
begin
  -- ── SD_KNOBS ──
  if public.wc_int('drift_spread_runs') <> 10 or public.wc_int('city_wants_keep_periods') <> 10 or public.wc_int('npc_route_lap_keep') <> 24
     or public.wc_int('npc_route_lap_keep_hours') <> 26 or public.wc_int('compact_trim_rows') <> 2000 or public.wc_int('compact_budget_ms') <> 8000
     or public.wc_int('compact_hold_ms') <> 200 or public.wc_int('compact_batch_max') <> 25 or public.wc_int('stats_city_good_keep_days') <> 3
     or public.wc_int('stats_city_good_fine_hours') <> 26 or public.wc_int('npc_retention_hours') <> 3 then
    raise exception 'SD_KNOBS: a knob is not at the value 0414 gave it';
  end if;
  raise notice 'PASS: SD_KNOBS drift_spread_runs 10, city_wants_keep_periods 10, npc_route_lap_keep 24 / 26 h, compact_trim_rows 2000, compact_budget_ms 8000, compact_hold_ms 200, compact_batch_max 25, stats_city_good_keep_days 3, stats_city_good_fine_hours 26, npc_retention_hours 3';

  -- ── SD_TURN ──
  select count(*) into v_ports from public.ports;
  select count(*), count(distinct d.id) into v_n, v_m
    from generate_series(0, 9) g cross join lateral public.drift_ports_due(now() + make_interval(mins => g)) d;
  if v_n <> v_ports or v_m <> v_ports then
    raise exception 'SD_TURN: ten runs give % rows over % harbours; the world has %', v_n, v_m, v_ports;
  end if;
  select max(c), min(c) into v_n, v_m
    from (select count(*) as c from generate_series(0, 9) g cross join lateral public.drift_ports_due(now() + make_interval(mins => g)) d group by g) x;
  if v_n - v_m > 1 then
    raise exception 'SD_TURN: a run takes % harbours and another %: not a tenth each', v_n, v_m;
  end if;
  update public.world_config set value = to_jsonb(1) where key = 'drift_spread_runs';
  if (select count(*) from public.drift_ports_due(now())) <> v_ports then
    raise exception 'SD_TURN: with drift_spread_runs 1 a run does not give every harbour';
  end if;
  update public.world_config set value = to_jsonb(10) where key = 'drift_spread_runs';
  raise notice 'PASS: SD_TURN % harbours, each given once in ten runs, % to % a run; all % at drift_spread_runs 1', v_ports, v_m, v_n, v_ports;

  -- ── SD_STEP ── (theta 0.9, sigma 0.02, the clamp out of the way; the three harbours with the most goods)
  update public.world_config set value = to_jsonb(0.9) where key = 'drift_theta';
  update public.world_config set value = to_jsonb(0.02) where key = 'drift_sigma';
  update public.world_config set value = to_jsonb(10.0) where key = 'drift_clamp';
  v_slot := floor(extract(epoch from now()) / public.wc_num('drift_slot_seconds'))::bigint;
  create temp table sd108 on commit drop as
  select pg.port_id from public.port_goods pg group by pg.port_id order by count(*) desc, pg.port_id limit 3;
  update public.port_goods pg set drift = 0, drift_slot = v_slot - 50, last_regen_day = world.game_day(now()) from sd108 s where s.port_id = pg.port_id;
  perform public.tick_market_drift(now(), s.port_id) from sd108 s;
  select count(*), stddev_pop(pg.drift) into v_n, v_sd from public.port_goods pg join sd108 s on s.port_id = pg.port_id;
  v_want := 0.02 * sqrt((1 - power(0.9, 100)) / (1 - 0.81));
  if v_n < 300 then
    raise exception 'SD_STEP: only % rows in the three largest harbours; 300 are wanted for the spread', v_n;
  end if;
  if v_sd not between v_want * 0.8 and v_want * 1.2 then
    raise exception 'SD_STEP: 50 slots behind, the spread of % rows is %, not within a fifth of %', v_n, round(v_sd, 4), round(v_want, 4);
  end if;
  v_s := format('%s rows 50 slots behind: spread %s (the law: %s)', v_n, round(v_sd, 4), round(v_want, 4));
  if exists (select 1 from public.port_goods pg join sd108 s on s.port_id = pg.port_id where pg.drift_slot <> v_slot) then
    raise exception 'SD_STEP: a stepped row is not on the current slot';
  end if;
  update public.port_goods pg set drift = 0, drift_slot = v_slot - 1 from sd108 s where s.port_id = pg.port_id;
  perform public.tick_market_drift(now(), s.port_id) from sd108 s;
  select stddev_pop(pg.drift) into v_sd from public.port_goods pg join sd108 s on s.port_id = pg.port_id;
  if v_sd not between 0.016 and 0.024 then
    raise exception 'SD_STEP: one slot behind, the spread is %, not within a fifth of 0.02', round(v_sd, 4);
  end if;
  raise notice 'PASS: SD_STEP %; one slot behind: spread % (the law: 0.0200)', v_s, round(v_sd, 4);

  -- ── SD_WANTS ── (the compactor's budget at 1 ms: it cuts no house here, only the wants)
  update public.world_config set value = to_jsonb(1) where key = 'compact_budget_ms';
  v_period := public.want_period(now());
  select pg.port_id, pg.good_id into v_port, v_good from public.port_goods pg order by pg.port_id, pg.good_id limit 1;
  insert into public.city_wants (port_id, good_id, period, mult, cap, nearest_nm, weight)
  select v_port, v_good, v_period - 1000000 - g, 2, 1, 1, 1 from generate_series(1, 5000) g;
  insert into public.city_wants (port_id, good_id, period, mult, cap, nearest_nm, weight)
  select v_port, v_good, v_period - g, 2, 1, 1, 1 from generate_series(0, 1) g
  on conflict do nothing;
  select count(*) into v_live from public.city_wants w where w.period >= v_period - 1;
  begin
    delete from public.city_wants where period = v_period - 1000001;
    raise exception 'SD_WANTS: city_wants let a delete through outside the compactor';
  exception when insufficient_privilege then null;
  end;
  begin
    perform set_config('byeharu.wants_trim', 'on', true);
    delete from public.city_wants where period = v_period - 1 and port_id = v_port and good_id = v_good;
    raise exception 'SD_WANTS: the guard let a want of the period before this one go';
  exception when insufficient_privilege then perform set_config('byeharu.wants_trim', 'off', true);
  end;
  update public.world_config set value = to_jsonb(0) where key = 'city_wants_keep_periods';
  call public.tick_compact(false, false);
  if (select count(*) from public.city_wants w where w.period < v_period - 1000000) <> 5000 then
    raise exception 'SD_WANTS: with city_wants_keep_periods 0 a want went';
  end if;
  update public.world_config set value = to_jsonb(10) where key = 'city_wants_keep_periods';
  v_s := '';
  for v_n in 1 .. 4 loop
    call public.tick_compact(false, false);
    v_s := v_s || (select count(*) from public.city_wants w where w.period < v_period - 1000000) || ' ';
  end loop;
  if v_s <> '3000 1000 0 0 ' then
    raise exception 'SD_WANTS: of 5,000 probe wants the runs left "%", not "3000 1000 0 0 " (%)', v_s,
      (select c.receipt->>'note' from public.compact_runs c order by c.at desc limit 1);
  end if;
  if (select count(*) from public.city_wants w where w.period >= v_period - 1) <> v_live then
    raise exception 'SD_WANTS: a want of the current period or the one before went';
  end if;
  raise notice 'PASS: SD_WANTS 5,000 probe wants in past periods: left after each run %; the % of now and the period before kept; a delete outside the compactor refused, and one of the period before refused even inside it; none at knob 0', v_s, v_live;

  -- ── SD_LAPS ── (one merchant route; compacted as of ten years ago, so only the probe laps are before any cut)
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
  if not public.npc_traders_on() then raise exception 'proof 108: the merchants cannot be lit in this world'; end if;
  select sr.player_id, sr.id into v_house, v_route
    from public.standing_routes sr join public.players p on p.id = sr.player_id and p.is_npc
   order by sr.id limit 1;
  if v_route is null then raise exception 'proof 108: no merchant route in this world'; end if;
  insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at)
  select v_route, 1000000 + g, v_at - interval '40 hours', v_at - case when g = 50 then interval '20 hours' else interval '30 hours' end
    from generate_series(1, 100) g;
  update public.standing_route_laps set closed_at = null where route_id = v_route and lap_no = 1000100;
  update public.standing_routes set lap_no = 1000100, lap_id = (select l.id from public.standing_route_laps l where l.route_id = v_route and l.lap_no = 1000100) where id = v_route;
  update public.world_config set value = to_jsonb(40) where key = 'compact_trim_rows';
  v_s := '';
  for v_n in 1 .. 3 loop
    perform public.npc_compact_houses(array[v_house], v_at);
    v_s := v_s || (select count(*) from public.standing_route_laps l where l.route_id = v_route and l.lap_no > 1000000) || ' ';
  end loop;
  if v_s <> '60 25 25 ' then
    raise exception 'SD_LAPS: of 100 probe laps the visits left "%", not "60 25 25 "', v_s;
  end if;
  if (select count(*) from public.standing_route_laps l where l.route_id = v_route and l.lap_no between 1000077 and 1000100) <> 24
     or not exists (select 1 from public.standing_route_laps l where l.route_id = v_route and l.lap_no = 1000050)
     or not exists (select 1 from public.standing_route_laps l where l.route_id = v_route and l.lap_no = 1000100 and l.closed_at is null) then
    raise exception 'SD_LAPS: the 25 left are not her newest 24 (the open lap among them) and the lap closed 20 hours ago';
  end if;
  raise notice 'PASS: SD_LAPS 100 probe laps of one merchant route, 40 a visit: left %; what stays is her newest 24 (the open lap among them) and the lap closed 20 hours before the cut', v_s;

  -- ── SD_CITYGOOD ──
  insert into public.stats_city_good (port_id, good_id, slot, at, mid, stock, stock_target, sold, bought, sold_ducats, bought_ducats)
  select v_port, v_good, -g, now() - case when g <= 50 then interval '10 days' else interval '2 days' end, 1, 1, 1, 0, 0, 0, 0
    from generate_series(1, 100) g;
  v_n := public.history_trim(now());
  select count(*) filter (where s.slot >= -50), count(*) filter (where s.slot < -50) into v_n, v_m
    from public.stats_city_good s where s.port_id = v_port and s.good_id = v_good and s.slot < 0;
  if v_n <> 0 or v_m <> 50 then
    raise exception 'SD_CITYGOOD: of 50 probe rows ten days old % are left, of 50 two days old %', v_n, v_m;
  end if;
  raise notice 'PASS: SD_CITYGOOD the trim took the 50 probe rows ten days old and left the 50 two days old (stats_city_good_keep_days 3)';
end $p$;
