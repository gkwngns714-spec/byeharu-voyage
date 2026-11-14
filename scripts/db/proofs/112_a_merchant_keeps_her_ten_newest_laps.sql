-- ═════════════════════════════════════════════════════════════════════════════════════
-- PROOF 112 - A MERCHANT KEEPS HER TEN NEWEST LAPS  (migration 0416; docs/dev-log/2026-11-14-slim-laps.md)
--
--   The same world, the same staged laps, read BEFORE and AFTER her lap rows are cut to the newest ten. The truth each figure is held to is
--   summed here from the staged rows themselves, not by any function under test. One merchant route is given 41 laps over 30 hours (one every
--   45 minutes, and one placed in the middle of the window's oldest part-hour, so that part-hour is never empty); one player's route the same.
--
-- @pass HB_EXACT    with every lap row there, the day is exact: route_earnings (day, day_laps, day_since, day_full) and the fleet card's day (laps, sold, bought, net, cargo in and out) equal the staged laps of the last 24 hours, lap for lap; the Stats window (net, laps, losing laps, lap 2 onwards) grew by exactly those laps
-- @pass HB_CUT      the compactor cuts her to her newest ten, with no hours' window; every figure then equals the truth LESS the laps of the oldest part-hour and nothing else: route_earnings' day, the card's day, the Stats window; day_full still true; the newest seven laps, their average and the card's lap list unmoved
-- @pass HB_SHORT    the Stats tab's "minutes since the count" (a window of 20 minutes, and one of 100) is exact after the cut
-- @pass HB_PLAYER   a player's route is not cut (41 laps stay) and its day is exact, lap for lap, as before
-- @pass HB_BUDGET   npc_share_budget keeps npc_invest_keep_laps x her dearest lap of the last npc_invest_lap_hours (8), read from the hour book after her lap rows are cut
-- @pass HB_WRITER   the book follows the lap rows: a closed lap moved to another hour leaves its old hour and joins the new; a lap un-closed leaves; a lap deleted stays in the book
-- @pass HB_TRIM     the compactor deletes the book's hours past route_hour_keep_hours (80): an hour 100 hours old goes, one 70 hours old stays
-- @pass HB_CITYGOOD the city-good statistics are kept 30 days: probe rows 40 days old go by the history trim, probe rows 10 days old stay
-- ═════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  v_house  uuid;
  v_route  uuid;
  v_fleet  uuid;
  v_pl     uuid;
  v_proute uuid;
  v_from   timestamptz := now() - interval '24 hours';
  v_lo     timestamptz := date_trunc('hour', now() - interval '24 hours') + interval '1 hour';
  v_mid    timestamptz;
  t        record;   -- the truth of 24 hours
  e        record;   -- the oldest part-hour's share of it
  v_e0     jsonb;
  v_e1     jsonb;
  v_c0     jsonb;
  v_c1     jsonb;
  v_wb     jsonb;
  v_w0     jsonb;
  v_w1     jsonb;
  v_n      int;
  v_m      int;
  v_x      bigint;
  v_b      bigint;
  v_port   uuid;
  v_good   uuid;
  v_pn     timestamptz;
begin
  -- ── THE SCENE ──
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
  if not public.npc_traders_on() then raise exception 'proof 112: the merchants cannot be lit in this world'; end if;
  if public.wc_int('npc_route_lap_keep') <> 10 or public.wc_int('npc_route_lap_keep_hours') <> 0 or public.wc_int('route_hour_keep_hours') <> 80
     or public.wc_int('npc_invest_lap_hours') <> 8 or public.wc_int('stats_city_good_keep_days') <> 30 or public.wc_int('stats_city_good_hour_days') <> 2 then
    raise exception 'proof 112: a knob is not at the value 0416 gave it';
  end if;
  v_mid := v_from + (v_lo - v_from) / 2;   -- the middle of the window's oldest part-hour
  select sr.player_id, sr.id, nf.fleet_id into v_house, v_route, v_fleet
    from public.standing_routes sr
    join public.players p on p.id = sr.player_id and p.is_npc
    join public.npc_fleets nf on nf.route_id = sr.id
   where (select count(*) from public.npc_fleets x where x.player_id = sr.player_id) = 1
   order by sr.id limit 1;
  if v_route is null then raise exception 'proof 112: no one-fleet merchant route in this world'; end if;
  v_wb := public.stats_merchants_window(v_from, now());
  delete from public.route_hour_laps where route_id = v_route;
  delete from public.standing_route_laps where route_id = v_route;
  update public.standing_routes set lap_id = null, lap_no = 41 where id = v_route;
  -- laps 1..40, one every 45 minutes, the newest 5 minutes ago; every fourth loses; lap 41 is numbered 0 in time: it stands mid part-hour
  create temp table hb112 on commit drop as
  select g as lap_no,
         case when g = 9 then v_mid else now() - make_interval(mins => 5 + 45 * (41 - g)) end as closed_at,
         (case when g % 4 = 0 then -500 - g else 2000 + 3 * g end)::bigint as net,
         (9000 + 7 * g)::bigint as sold, (6000 + 5 * g)::bigint as bought, (40 + g)::bigint as supplies, (10 + g)::bigint as repairs,
         (100 + g)::bigint as wages, (30 + g)::bigint as taxes, (5 + g)::bigint as insurance, (300 + 11 * g)::bigint as stock_out
    from generate_series(1, 41) g;
  insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, net, sold, bought, supplies, repairs, wages, taxes, insurance, stock_out)
  select v_route, s.lap_no, s.closed_at - interval '20 minutes', s.closed_at, s.net, s.sold, s.bought, s.supplies, s.repairs, s.wages, s.taxes, s.insurance, s.stock_out
    from hb112 s order by s.lap_no;
  -- the truth, from the staged rows alone (the cargo carried in is the lap before's stock_out, by lap number)
  create temp table hb112t on commit drop as
  select s.*, coalesce(lag(s.stock_out) over (order by s.lap_no), 0) as stock_in from hb112 s;
  select count(*) as laps, sum(x.net) as net, sum(x.sold) as sold, sum(x.bought) as bought, sum(x.stock_in) as stock_in, sum(x.stock_out) as stock_out,
         min(x.closed_at) as since, count(*) filter (where x.lap_no >= 2) as laps2, coalesce(sum(x.net) filter (where x.lap_no >= 2), 0) as net2,
         count(*) filter (where x.lap_no >= 2 and x.net <= 0) as neg2
    into t from hb112t x where x.closed_at > v_from;
  select count(*) as laps, coalesce(sum(x.net), 0) as net, coalesce(sum(x.sold), 0) as sold, coalesce(sum(x.bought), 0) as bought,
         coalesce(sum(x.stock_in), 0) as stock_in, coalesce(sum(x.stock_out), 0) as stock_out,
         count(*) filter (where x.net <= 0) as neg
    into e from hb112t x where x.closed_at > v_from and x.closed_at < v_lo;
  if e.laps < 1 or t.laps < 25 then raise exception 'proof 112: the scene holds % laps in 24 hours and % in the oldest part-hour', t.laps, e.laps; end if;

  -- ── HB_EXACT ──
  v_e0 := public.route_earnings(v_route);
  v_c0 := world.fleet_trades(v_fleet);
  v_w0 := public.stats_merchants_window(v_from, now());
  if (v_e0->>'day')::bigint <> t.net or (v_e0->>'day_laps')::bigint <> t.laps or (v_e0->>'day_since')::timestamptz <> t.since or not (v_e0->>'day_full')::boolean then
    raise exception 'HB_EXACT: route_earnings reads day % over % laps since %; the staged 24 hours are % over % since %', v_e0->>'day', v_e0->>'day_laps', v_e0->>'day_since', t.net, t.laps, t.since;
  end if;
  if (v_c0->'day'->>'net')::bigint <> t.net or (v_c0->'day'->>'laps')::bigint <> t.laps or (v_c0->'day'->>'sold')::bigint <> t.sold
     or (v_c0->'day'->>'bought')::bigint <> t.bought or (v_c0->'day'->>'stock_in')::bigint <> t.stock_in or (v_c0->'day'->>'stock_out')::bigint <> t.stock_out
     or not (v_c0->'day'->>'full')::boolean then
    raise exception 'HB_EXACT: the fleet card''s day is %; the staged 24 hours are net % laps % sold % bought % in % out %', v_c0->'day' - 'goods', t.net, t.laps, t.sold, t.bought, t.stock_in, t.stock_out;
  end if;
  if (v_w0->>'net')::bigint - (v_wb->>'net')::bigint <> t.net2 or (v_w0->>'n')::bigint - (v_wb->>'n')::bigint <> t.laps2
     or (v_w0->>'neg')::bigint - (v_wb->>'neg')::bigint <> t.neg2 then
    raise exception 'HB_EXACT: the Stats window grew by net % n % neg %; the staged laps 2 onwards are % / % / %',
      (v_w0->>'net')::bigint - (v_wb->>'net')::bigint, (v_w0->>'n')::bigint - (v_wb->>'n')::bigint, (v_w0->>'neg')::bigint - (v_wb->>'neg')::bigint, t.net2, t.laps2, t.neg2;
  end if;
  raise notice 'PASS: HB_EXACT 41 staged laps, % in the last 24 hours: route_earnings day % over % laps, the card''s day (sold %, bought %, cargo in %, out %) and the Stats window (+% net, +% laps, +% losing) all equal the staged rows',
    t.laps, t.net, t.laps, t.sold, t.bought, t.stock_in, t.stock_out, t.net2, t.laps2, t.neg2;

  -- ── HB_CUT ── (as of ten years ago: none of her books is before any cut; the lap rule reads no clock)
  perform public.npc_compact_houses(array[v_house], now() - interval '3650 days');
  select count(*), min(l.lap_no) into v_n, v_m from public.standing_route_laps l where l.route_id = v_route;
  if v_n <> 10 or v_m <> 32 then
    raise exception 'HB_CUT: the cut left % laps from lap % (her newest ten: 32 to 41)', v_n, v_m;
  end if;
  v_e1 := public.route_earnings(v_route);
  v_c1 := world.fleet_trades(v_fleet);
  v_w1 := public.stats_merchants_window(v_from, now());
  if (v_e1->>'day')::bigint <> t.net - e.net or (v_e1->>'day_laps')::bigint <> t.laps - e.laps or not (v_e1->>'day_full')::boolean then
    raise exception 'HB_CUT: after the cut route_earnings reads day % over % laps; the truth less the oldest part-hour is % over %', v_e1->>'day', v_e1->>'day_laps', t.net - e.net, t.laps - e.laps;
  end if;
  if (v_c1->'day'->>'net')::bigint <> t.net - e.net or (v_c1->'day'->>'laps')::bigint <> t.laps - e.laps or (v_c1->'day'->>'sold')::bigint <> t.sold - e.sold
     or (v_c1->'day'->>'bought')::bigint <> t.bought - e.bought or (v_c1->'day'->>'stock_in')::bigint <> t.stock_in - e.stock_in
     or (v_c1->'day'->>'stock_out')::bigint <> t.stock_out - e.stock_out or not (v_c1->'day'->>'full')::boolean then
    raise exception 'HB_CUT: after the cut the card''s day is %; the truth less the oldest part-hour is net % laps % sold % bought %', v_c1->'day' - 'goods', t.net - e.net, t.laps - e.laps, t.sold - e.sold, t.bought - e.bought;
  end if;
  if (v_w0->>'net')::bigint - (v_w1->>'net')::bigint <> e.net or (v_w0->>'n')::bigint - (v_w1->>'n')::bigint <> e.laps
     or (v_w0->>'neg')::bigint - (v_w1->>'neg')::bigint <> e.neg then
    raise exception 'HB_CUT: the Stats window lost net % n % neg % with the cut; the oldest part-hour holds % / % / %',
      (v_w0->>'net')::bigint - (v_w1->>'net')::bigint, (v_w0->>'n')::bigint - (v_w1->>'n')::bigint, (v_w0->>'neg')::bigint - (v_w1->>'neg')::bigint, e.net, e.laps, e.neg;
  end if;
  if (v_e1->'laps_recent') <> (v_e0->'laps_recent') or (v_e1->>'lap') is distinct from (v_e0->>'lap') or (v_e1->>'laps_done') <> (v_e0->>'laps_done')
     or jsonb_array_length(v_c1->'laps') <> 7 or (v_c1->'laps') <> (v_c0->'laps') then
    raise exception 'HB_CUT: the newest laps, their average, the count of laps done or the card''s lap list moved with the cut';
  end if;
  raise notice 'PASS: HB_CUT her lap rows cut from 41 to her newest 10 (laps 32 to 41), no hours'' window: the day reads % over % laps = the truth less the % lap(s) of the oldest part-hour (% net), in route_earnings, on the card and in the Stats window alike; the newest seven laps and their average unmoved',
    t.net - e.net, t.laps - e.laps, e.laps, e.net;

  -- ── HB_SHORT ── (lap 41 closed 5 minutes ago, lap 40 50 minutes ago, lap 39 95 minutes ago)
  v_w0 := public.stats_merchants_window(now() - interval '20 minutes', now());
  v_w1 := public.stats_merchants_window(now() - interval '100 minutes', now());
  select coalesce(sum(x.net), 0) into v_x from hb112t x where x.closed_at > now() - interval '20 minutes';
  select coalesce(sum(x.net), 0) into v_b from hb112t x where x.closed_at > now() - interval '100 minutes';
  if (select coalesce(sum((hh->>'day')::bigint), 0) from jsonb_array_elements(v_w0->'houses') hh
       where hh->>'name' = (select p.company_name from public.players p where p.id = v_house)) <> v_x
     or (select coalesce(sum((hh->>'day')::bigint), 0) from jsonb_array_elements(v_w1->'houses') hh
          where hh->>'name' = (select p.company_name from public.players p where p.id = v_house)) <> v_b then
    raise exception 'HB_SHORT: her house''s last 20 and 100 minutes read otherwise than the staged % and %', v_x, v_b;
  end if;
  raise notice 'PASS: HB_SHORT after the cut the Stats window of the last 20 minutes gives her house % and of the last 100 minutes %: the staged laps exactly', v_x, v_b;

  -- ── HB_BUDGET ── (asked in her hour of the day, no cap, nothing kept for capital: what is left of 1,000,000 is it less 2 x her dearest lap since 8 hours before the ask)
  update public.world_config set value = to_jsonb(2000000000) where key = 'npc_invest_day_cap';
  update public.world_config set value = to_jsonb(0) where key = 'npc_invest_keep';
  -- asked at the latest instant, now or before, that falls in HER hour of the day (roster_ord % 24, UTC): up to 23 hours back
  v_pn := now() - make_interval(hours => ((extract(hour from now() at time zone 'UTC')::int
                                           - (select h.roster_ord % 24 from public.npc_houses h where h.player_id = v_house) + 24) % 24));
  select max(x.bought + x.supplies + x.repairs + x.wages + x.taxes + x.insurance) into v_x
    from hb112t x where x.closed_at >= date_trunc('hour', v_pn - interval '8 hours');
  v_b := public.npc_share_budget(v_pn, v_house, 1000000);
  if v_b <> 1000000 - public.wc_num('npc_invest_keep_laps') * v_x then
    raise exception 'HB_BUDGET: the budget of 1,000,000 is %; it should keep % x her dearest lap of 8 hours (%)', v_b, public.wc_num('npc_invest_keep_laps'), v_x;
  end if;
  raise notice 'PASS: HB_BUDGET of 1,000,000 she may invest %: all but % x her dearest lap of the last 8 hours (%), read from the hour book', v_b, public.wc_num('npc_invest_keep_laps'), v_x;

  -- ── HB_PLAYER ── (the same 41 laps on a player's route; the compactor is given her house and must do nothing)
  select p.id into v_pl from public.players p where not p.is_npc order by p.created_at, p.id limit 1;
  if v_pl is null then raise exception 'proof 112: no player in this world'; end if;
  insert into public.standing_routes (player_id, name) values (v_pl, 'proof 112') returning id into v_proute;
  insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, net, sold, bought, supplies, repairs, wages, taxes, insurance, stock_out)
  select v_proute, s.lap_no, s.closed_at - interval '20 minutes', s.closed_at, s.net, s.sold, s.bought, s.supplies, s.repairs, s.wages, s.taxes, s.insurance, s.stock_out
    from hb112 s order by s.lap_no;
  update public.standing_routes set lap_no = 41 where id = v_proute;
  perform public.npc_compact_houses(array[v_pl], now() - interval '3650 days');
  v_e0 := public.route_earnings(v_proute);
  if (select count(*) from public.standing_route_laps l where l.route_id = v_proute) <> 41
     or (v_e0->>'day')::bigint <> t.net or (v_e0->>'day_laps')::bigint <> t.laps or (v_e0->>'day_since')::timestamptz <> t.since then
    raise exception 'HB_PLAYER: a player''s route holds % laps and reads day % over %; 41 laps, % over %',
      (select count(*) from public.standing_route_laps l where l.route_id = v_proute), v_e0->>'day', v_e0->>'day_laps', t.net, t.laps;
  end if;
  raise notice 'PASS: HB_PLAYER a player''s route keeps its 41 laps and its day is exact: % over % laps', t.net, t.laps;

  -- ── HB_WRITER ── (on the player's route: lap 41 closed 5 minutes ago)
  select b.laps into v_n from public.route_hour_laps b where b.route_id = v_proute and b.hour = date_trunc('hour', now() - interval '5 minutes');
  update public.standing_route_laps set closed_at = now() - interval '50 hours' where route_id = v_proute and lap_no = 41;
  if coalesce((select b.laps from public.route_hour_laps b where b.route_id = v_proute and b.hour = date_trunc('hour', now() - interval '5 minutes')), 0) <> v_n - 1
     or (select b.laps from public.route_hour_laps b where b.route_id = v_proute and b.hour = date_trunc('hour', now() - interval '50 hours')) is distinct from 1
     or (select b.net from public.route_hour_laps b where b.route_id = v_proute and b.hour = date_trunc('hour', now() - interval '50 hours')) <> (select s.net from hb112 s where s.lap_no = 41) then
    raise exception 'HB_WRITER: a closed lap moved 50 hours back did not leave its hour and join the other';
  end if;
  update public.standing_route_laps set closed_at = null where route_id = v_proute and lap_no = 41;
  if exists (select 1 from public.route_hour_laps b where b.route_id = v_proute and b.hour = date_trunc('hour', now() - interval '50 hours')) then
    raise exception 'HB_WRITER: a lap un-closed stayed in the book';
  end if;
  select sum(b.laps), sum(b.net) into v_m, v_x from public.route_hour_laps b where b.route_id = v_proute;
  delete from public.standing_route_laps where route_id = v_proute and lap_no <= 20;
  if (select sum(b.laps) from public.route_hour_laps b where b.route_id = v_proute) <> v_m or (select sum(b.net) from public.route_hour_laps b where b.route_id = v_proute) <> v_x
     or v_m <> 40 then
    raise exception 'HB_WRITER: deleting lap rows changed the book (% laps, 40 before)', (select sum(b.laps) from public.route_hour_laps b where b.route_id = v_proute);
  end if;
  raise notice 'PASS: HB_WRITER a closed lap moved to another hour left the first and joined the second; un-closed it left the book; 20 lap rows deleted and the book still holds its 40 laps';

  -- ── HB_TRIM ── (the compactor's budget at 1 ms: it cuts no house here)
  update public.world_config set value = to_jsonb(1) where key = 'compact_budget_ms';
  insert into public.route_hour_laps (route_id, hour, laps, first_at, last_at)
  values (v_proute, date_trunc('hour', now() - interval '100 hours'), 1, now() - interval '100 hours', now() - interval '100 hours'),
         (v_proute, date_trunc('hour', now() - interval '70 hours'), 1, now() - interval '70 hours', now() - interval '70 hours');
  call public.tick_compact(false, false);
  if exists (select 1 from public.route_hour_laps b where b.hour < now() - interval '81 hours')
     or not exists (select 1 from public.route_hour_laps b where b.route_id = v_proute and b.hour = date_trunc('hour', now() - interval '70 hours')) then
    raise exception 'HB_TRIM: the compactor left an hour past 80 hours, or took one inside them (%)', (select c.receipt->>'note' from public.compact_runs c order by c.at desc limit 1);
  end if;
  raise notice 'PASS: HB_TRIM the compactor took the hour 100 hours old and left the one 70 hours old (route_hour_keep_hours 80)';

  -- ── HB_CITYGOOD ──
  select pg.port_id, pg.good_id into v_port, v_good from public.port_goods pg order by pg.port_id, pg.good_id limit 1;
  insert into public.stats_city_good (port_id, good_id, slot, at, mid, stock, stock_target, sold, bought, sold_ducats, bought_ducats)
  select v_port, v_good, -g, now() - case when g <= 50 then interval '40 days' else interval '10 days' end, 1, 1, 1, 0, 0, 0, 0
    from generate_series(1, 100) g;
  perform public.history_trim(now());
  select count(*) filter (where s.slot >= -50), count(*) filter (where s.slot < -50) into v_n, v_m
    from public.stats_city_good s where s.port_id = v_port and s.good_id = v_good and s.slot < 0;
  if v_n <> 0 or v_m <> 50 then
    raise exception 'HB_CITYGOOD: of 50 probe rows 40 days old % are left, of 50 ten days old %', v_n, v_m;
  end if;
  raise notice 'PASS: HB_CITYGOOD the trim took the 50 probe rows 40 days old and left the 50 ten days old (stats_city_good_keep_days 30)';
end $p$;
