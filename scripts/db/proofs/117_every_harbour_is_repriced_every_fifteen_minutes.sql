-- ═════════════════════════════════════════════════════════════════════════════════════
-- PROOF 117 - EVERY HARBOUR IS REPRICED EVERY FIFTEEN MINUTES  (migration 0420; docs/dev-log/2026-11-15-drift-15.md)
--
--   On the world's own harbours, rolled back with proof.mjs's transaction. The drift slot is put at production's 300 s (this chain's is 4,500 s)
--   where a scene needs production's clock.
--
-- @pass DF_KNOB    drift_spread_runs is 15 and its description records the 50 it replaced and that the clock's door does not move it
-- @pass DF_TURN    fifteen consecutive runs give every harbour exactly once, 17 or 18 harbours a run; their port_goods rows add up to the whole table, about a fifteenth a run
-- @pass DF_NEXT    every harbour's turns in an hour and a half fall exactly fifteen minutes apart (six turns each)
-- @pass DF_LAW     on production's 300 s slot: with no noise, four 15-minute turns put a row where one turn after the hour puts it, theta^12 x drift; with the noise, rows from drift 0 after four turns have the spread of twelve one-slot steps
-- @pass DF_DOOR    the clock's door moves the slot's length and leaves the spread: public.clock_set(960) and back to 192, drift_spread_runs 15 throughout; the drift slot a fifth and back
-- ═════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  v_at    timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_n     int;
  v_m     int;
  v_ports int;
  v_rows  bigint;
  v_max   bigint;
  v_min   bigint;
  v_port  uuid;
  v_good  uuid;
  v_s0    bigint;
  v_da    numeric;
  v_db    numeric;
  v_sd    numeric;
  v_want  numeric;
  v_slot0 numeric;
  v_s     text;
  i       int;
begin
  -- ── DF_KNOB ──
  if public.wc_int('drift_spread_runs') <> 15
     or (select wc.description from public.world_config wc where wc.key = 'drift_spread_runs') not like '0420:%50 before 0420%'
     or (select wc.description from public.world_config wc where wc.key = 'drift_spread_runs') not like '%does NOT move it%' then
    raise exception 'DF_KNOB: drift_spread_runs is %, described %', public.wc_int('drift_spread_runs'),
      (select wc.description from public.world_config wc where wc.key = 'drift_spread_runs');
  end if;
  raise notice 'PASS: DF_KNOB drift_spread_runs 15 (50 before 0420), not moved by the clock''s door';

  -- ── DF_TURN ──
  select count(*) into v_ports from public.ports;
  select count(*), count(distinct d.id) into v_n, v_m
    from generate_series(0, 14) g cross join lateral public.drift_ports_due(v_at + make_interval(mins => g)) d;
  if v_n <> v_ports or v_m <> v_ports then
    raise exception 'DF_TURN: fifteen runs give % turns over % harbours; the world has %', v_n, v_m, v_ports;
  end if;
  select max(c), min(c) into v_n, v_m
    from (select count(*) as c from generate_series(0, 14) g cross join lateral public.drift_ports_due(v_at + make_interval(mins => g)) d group by g) x;
  if v_n - v_m > 1 then
    raise exception 'DF_TURN: a run takes % harbours and another %: not a fifteenth each', v_n, v_m;
  end if;
  select sum(r), max(r), min(r) into v_rows, v_max, v_min
    from (select g, count(*) as r from generate_series(0, 14) g cross join lateral public.drift_ports_due(v_at + make_interval(mins => g)) d
            join public.port_goods pg on pg.port_id = d.id group by g) x;
  if v_rows <> (select count(*) from public.port_goods) or v_max > 1.5 * v_rows / 15.0 then
    raise exception 'DF_TURN: fifteen runs reach % rows of % (largest run %, a fifteenth %)', v_rows, (select count(*) from public.port_goods), v_max, round(v_rows / 15.0);
  end if;
  raise notice 'PASS: DF_TURN % harbours, each once in fifteen runs, % to % a run; % port_goods rows in all, % to % a run (a fifteenth: %)',
    v_ports, v_m, v_n, v_rows, v_min, v_max, round(v_rows / 15.0);

  -- ── DF_NEXT ──
  if exists (select 1
               from (select d.id, array_agg(g order by g) as turns
                       from generate_series(0, 89) g cross join lateral public.drift_ports_due(v_at + make_interval(mins => g)) d group by d.id) x
              where cardinality(x.turns) <> 6
                 or exists (select 1 from generate_subscripts(x.turns, 1) s where s > 1 and x.turns[s] - x.turns[s - 1] <> 15))
     or (select count(distinct d.id) from generate_series(0, 89) g cross join lateral public.drift_ports_due(v_at + make_interval(mins => g)) d) <> v_ports then
    raise exception 'DF_NEXT: a harbour''s turns in ninety minutes are not six, fifteen minutes apart';
  end if;
  raise notice 'PASS: DF_NEXT every one of % harbours has six turns in ninety minutes, each fifteen minutes after the last', v_ports;

  -- ── DF_LAW ── (production's slot: 300 s; theta 0.9, the clamp out of the way)
  update public.world_config set value = to_jsonb(300) where key = 'drift_slot_seconds';
  update public.world_config set value = '{}'::jsonb where key = 'market_clock_anchor';   -- the slot counted from the epoch at 300 s, as before any move
  update public.world_config set value = to_jsonb(0.9) where key = 'drift_theta';
  update public.world_config set value = to_jsonb(10.0) where key = 'drift_clamp';
  update public.world_config set value = to_jsonb(0) where key = 'drift_sigma';
  v_s0 := public.drift_slot_of(v_at);
  if public.drift_slot_of(v_at + interval '15 minutes') - v_s0 <> 3 or public.drift_slot_of(v_at + interval '60 minutes') - v_s0 <> 12 then
    raise exception 'DF_LAW: at 300 s fifteen minutes are % slots and an hour %', public.drift_slot_of(v_at + interval '15 minutes') - v_s0, public.drift_slot_of(v_at + interval '60 minutes') - v_s0;
  end if;
  select pg.port_id, pg.good_id into v_port, v_good from public.port_goods pg order by pg.port_id, pg.good_id limit 1;
  update public.port_goods set drift = 0.1, drift_slot = v_s0, last_regen_day = world.game_day(v_at) where port_id = v_port;   -- the whole harbour on the slot (the clock was re-counted above)
  for i in 1 .. 4 loop perform public.tick_market_drift(v_at + make_interval(mins => 15 * i), v_port); end loop;
  select pg.drift into v_da from public.port_goods pg where pg.port_id = v_port and pg.good_id = v_good;
  update public.port_goods set drift = 0.1, drift_slot = v_s0, last_regen_day = world.game_day(v_at) where port_id = v_port;   -- the whole harbour on the slot (the clock was re-counted above)
  perform public.tick_market_drift(v_at + interval '60 minutes', v_port);
  select pg.drift into v_db from public.port_goods pg where pg.port_id = v_port and pg.good_id = v_good;
  if abs(v_da - 0.0282) > 0.0002 or abs(v_db - 0.0282) > 0.0002 then
    raise exception 'DF_LAW: four 15-minute turns give %, one turn after the hour %; theta^12 x 0.1 = 0.0282', v_da, v_db;
  end if;
  v_s := format('no noise: four turns %s, one turn %s, theta^12 x 0.1 = 0.0282', v_da, v_db);
  update public.world_config set value = to_jsonb(0.02) where key = 'drift_sigma';
  create temp table df116 on commit drop as
  select pg.port_id from public.port_goods pg group by pg.port_id order by count(*) desc, pg.port_id limit 3;
  update public.port_goods pg set drift = 0, drift_slot = v_s0, last_regen_day = world.game_day(v_at) from df116 s where s.port_id = pg.port_id;
  for i in 1 .. 4 loop perform public.tick_market_drift(v_at + make_interval(mins => 15 * i), s.port_id) from df116 s; end loop;
  select count(*), stddev_pop(pg.drift) into v_n, v_sd from public.port_goods pg join df116 s on s.port_id = pg.port_id;
  v_want := 0.02 * sqrt((1 - power(0.9, 24)) / (1 - 0.81));
  if v_n < 300 or v_sd not between v_want * 0.8 and v_want * 1.2 then
    raise exception 'DF_LAW: % rows from drift 0 after four 15-minute turns spread %, not within a fifth of the twelve-step law %', v_n, round(v_sd, 4), round(v_want, 4);
  end if;
  raise notice 'PASS: DF_LAW %; with noise: % rows from drift 0, four turns, spread % (twelve one-slot steps: %)', v_s, v_n, round(v_sd, 4), round(v_want, 4);

  -- ── DF_DOOR ── (the slot back at this chain's own length, then the clock moved through its door and back)
  update public.world_config set value = to_jsonb(4500) where key = 'drift_slot_seconds';
  v_slot0 := public.wc_num('drift_slot_seconds');
  perform public.clock_set(960, v_at);
  if public.wc_int('drift_spread_runs') <> 15 or public.wc_num('drift_slot_seconds') * 5 <> v_slot0 then
    raise exception 'DF_DOOR: at 960 drift_spread_runs is % and the slot %', public.wc_int('drift_spread_runs'), public.wc_num('drift_slot_seconds');
  end if;
  perform public.clock_set(192, v_at + interval '1 hour');
  if public.wc_int('drift_spread_runs') <> 15 or public.wc_num('drift_slot_seconds') <> v_slot0 then
    raise exception 'DF_DOOR: back at 192 drift_spread_runs is % and the slot %', public.wc_int('drift_spread_runs'), public.wc_num('drift_slot_seconds');
  end if;
  raise notice 'PASS: DF_DOOR the door to 960 and back: the slot % s -> % s -> % s, drift_spread_runs 15 throughout', v_slot0, trim_scale(v_slot0 / 5), public.wc_num('drift_slot_seconds');
end $p$;
