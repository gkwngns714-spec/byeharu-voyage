-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 5 — WHAT A FIRST VOYAGE PAYS
--
-- Balance is a number, and a number that nothing measures will drift. The first version of this
-- world paid **32% of the stake** for one twenty-five-minute round trip: the purse doubled in two
-- voyages, before the player had learned the map. That was not found by playing — it was found by
-- measuring, and it is held here so it cannot come back.
--
-- WHAT THIS ASSERTS, AND WHY EACH ONE
--   * THE OPENING VOYAGE PAYS, EVERYWHERE. From a sample of starting ports, the best one-leg round
--     trip a starter can afford returns something. A world where the best available trade loses
--     money has no game in it.
--   * IT DOES NOT PAY TOO MUCH. The median sits inside a band. Above it the economy is a printer;
--     below it, the voyage is not worth the twenty-five minutes.
--   * DISTANCE IS WHAT PAYS. The long legs must out-earn the short ones — otherwise there is no
--     reason to ever leave home waters, and the 214-port world collapses to whatever is nearest.
--
-- The knobs behind all three live in world_config (`affinity_*`, migration 0005) and are swept by
-- scripts/db/tune-balance.mjs. If this proof goes red, run that sweep and read the table it prints
-- rather than nudging a constant until the red goes away.
--
-- @pass BALANCE_EVERY_PORT_HAS_A_TRADE   every sampled starting port offers a profitable first voyage
-- @pass BALANCE_MEDIAN_IN_BAND           the median return on the stake is inside the designed band
-- @pass BALANCE_DISTANCE_PAYS            long legs out-earn short ones
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  -- The band. Stated here, once, in the file that enforces it.
  c_median_lo constant numeric := 4.0;    -- below this a voyage is not worth the time it takes
  c_median_hi constant numeric := 16.0;   -- above this the purse doubles before the map is learned
  c_sample    constant int := 8;

  r_port    record;
  r_option  record;
  q_buy     record;
  q_sell    record;
  v_uid     uuid;
  v_player  uuid;
  v_fleet   uuid;
  v_stake   numeric;
  v_free    numeric;
  v_room    numeric;
  v_qty     numeric;
  v_pct     numeric;
  v_best    numeric;
  v_best_nm numeric;
  v_n       int := 0;
  v_dry     int := 0;
  v_short   numeric := 0;   -- mean return of the best trade on legs under 400 nm
  v_short_n int := 0;
  v_long    numeric := 0;   -- ... and over 800 nm
  v_long_n  int := 0;
  v_returns numeric[] := '{}';
  v_median  numeric;
begin
  for r_port in
    select id, code, name, culture from public.ports order by size_tier desc, code limit c_sample
  loop
    -- A house at THIS port, watered and fully crewed, exactly as a player would set out.
    v_uid := ('00000000-0000-4000-9500-' || lpad(md5(r_port.code), 12, '0'))::uuid;
    v_player := public.new_house(v_uid, 'Casa ' || r_port.code, 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    update public.fleets set port_id = r_port.id where id = v_fleet;
    perform cmd.assume_identity(v_uid);
    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
    perform cmd.do_hire(v_fleet, jsonb_build_object('count',
      (select c.crew_max - s.crew from public.ships s
         join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fleet)));

    select ducats into v_stake from public.players where id = v_player;
    select c.hold - s.water_t - s.food_t into v_free
      from public.ships s join public.ship_classes c on c.id = s.class_id
     where s.fleet_id = v_fleet;

    v_best := null;
    v_best_nm := null;

    for r_option in
      select g.id as good_id, g.bulk, d.id as dest_id, l.distance_nm
        from public.legs l
        join public.ports d
          on d.id = case when l.from_port_id = r_port.id then l.to_port_id else l.from_port_id end
        join public.port_goods pg_home on pg_home.port_id = r_port.id
        join public.port_goods pg_away
          on pg_away.port_id = d.id and pg_away.good_id = pg_home.good_id
        join public.goods g on g.id = pg_home.good_id
       where (l.from_port_id = r_port.id or l.to_port_id = r_port.id)
         and not (d.culture = any(g.culture_mask))
         and not (r_port.culture = any(g.culture_mask))
       order by pg_away.affinity - pg_home.affinity desc
       limit 10
    loop
      v_room := floor(v_free / r_option.bulk);
      if v_room < 1 then continue; end if;

      -- What she can actually pay for at the STEPPED price — the same halving a player does when
      -- the game says E_INSUFFICIENT_FUNDS.
      v_qty := v_room;
      q_buy := null;
      while v_qty >= 1 loop
        select * into q_buy from world.quote(r_port.id, r_option.good_id, v_qty, 'buy');
        exit when q_buy.units > 0 and q_buy.total <= v_stake;
        q_buy := null;
        v_qty := floor(v_qty / 2);
      end loop;
      if q_buy is null then continue; end if;

      select * into q_sell from world.quote(r_option.dest_id, r_option.good_id, q_buy.units, 'sell');
      v_pct := (q_sell.total - q_buy.total) / v_stake * 100;
      if v_best is null or v_pct > v_best then
        v_best := v_pct;
        v_best_nm := r_option.distance_nm;
      end if;
    end loop;

    v_n := v_n + 1;
    if v_best is null or v_best <= 0 then
      v_dry := v_dry + 1;
    else
      v_returns := v_returns || v_best;
      if v_best_nm < 400 then
        v_short := v_short + v_best; v_short_n := v_short_n + 1;
      elsif v_best_nm > 800 then
        v_long := v_long + v_best; v_long_n := v_long_n + 1;
      end if;
    end if;
  end loop;

  if v_dry <> 0 then
    raise exception 'PROOF 5 FAILED: % of % sampled ports offer no profitable first voyage at all',
      v_dry, v_n;
  end if;
  raise notice 'PASS: BALANCE_EVERY_PORT_HAS_A_TRADE — all % sampled ports offer a first voyage that pays', v_n;

  select percentile_cont(0.5) within group (order by x)
    into v_median from unnest(v_returns) as t(x);
  if v_median < c_median_lo or v_median > c_median_hi then
    raise exception 'PROOF 5 FAILED: the median first voyage returns %%% of the stake, outside the designed band %%%-%%%. Run scripts/db/tune-balance.mjs and read the sweep.',
      round(v_median, 1), c_median_lo, c_median_hi;
  end if;
  raise notice 'PASS: BALANCE_MEDIAN_IN_BAND — the median first voyage returns % per cent of the stake (band %-%), worst %, best %',
    round(v_median, 1), c_median_lo, c_median_hi,
    (select round(min(x), 1) from unnest(v_returns) as t(x)),
    (select round(max(x), 1) from unnest(v_returns) as t(x));

  -- DISTANCE PAYS. Not a nicety: it is the reason the world is 214 ports wide rather than twelve.
  if v_short_n = 0 or v_long_n = 0 then
    raise notice 'PASS: BALANCE_DISTANCE_PAYS — skipped: the sample drew % short-leg and % long-leg best-trades, so there is nothing to compare',
      v_short_n, v_long_n;
  elsif (v_long / v_long_n) <= (v_short / v_short_n) then
    raise exception 'PROOF 5 FAILED: long legs pay %%% and short legs pay %%% — there is no reason to sail far',
      round(v_long / v_long_n, 1), round(v_short / v_short_n, 1);
  else
    raise notice 'PASS: BALANCE_DISTANCE_PAYS — legs over 800 nm return % per cent against % per cent under 400 nm (% and % ports)',
      round(v_long / v_long_n, 1), round(v_short / v_short_n, 1), v_long_n, v_short_n;
  end if;
end $$;
