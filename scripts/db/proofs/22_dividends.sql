-- ═══════════════════════════════════════════════════════════
-- PROOF 22 — DIVIDENDS ARE PAID FROM PROFIT  (migration 0312)
--
--   0312's own self-assert runs public.city_coupons on a probe harbour alone (a migration never runs a real game step, docs/OPS_HEALTH.md section 4).
--   This proof runs the REAL public.tick_city over the WHOLE world, at both clocks, each pass rolled back: flows go in through public.treasury_post, the
--   roll adds the profit, step 6 pays.
--
-- @pass DIV_RECEIPT    a real tick_city answers no error in any step, and coupons_paid is what the DIVIDEND flows say
-- @pass DIV_PROFIT     a city that earned less than its coupon pays exactly what it earned
-- @pass DIV_RATE       a city that earned plenty pays exactly 9 % of what was paid, at either clock
-- @pass DIV_NO_LEAK    a city whose only money is crown aid, a crown call or a cargo ship pays nothing
-- @pass DIV_CAPITAL    share money is not profit: a city that took 5,000,000 d. of it still pays only what it earned; a donation is income
-- @pass DIV_LOSS       a city that lost pays nothing, owes nothing, and starts the next day at 0
-- @pass DIV_OLD_FLOW   a flow older than the daybook's window still counts: the roll adds it, not the daybook
-- @pass DIV_ONE_A_DAY  a later tick of the same real day pays nothing and keeps adding profit
-- ═══════════════════════════════════════════════════════════

do $$
declare
  c_day  constant int := 86400;
  v_rday int := public.real_day(now());
  v_mark bigint := coalesce((select max(id) from public.treasury_flows), 0);
  v_h    uuid[];
  v_p    uuid;
  v_r    jsonb;
  v_x    jsonb;
  v_all  jsonb := '{}'::jsonb;
  v_gds  int;
begin
  select array_agg(x.id order by x.code) into v_h
    from (select p.id, p.code from public.ports p where p.kind = 'HARBOUR' order by p.code limit 5) x;

  foreach v_gds in array array[60, 2880] loop
    begin
      update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
      update public.world_config set value = to_jsonb(v_gds) where key = 'game_day_seconds';
      update public.world_config set value = '0'::jsonb where key = 'works_level_max';   -- no city builds: its surplus stays whole
      insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;

      -- the books as the paying tick finds them: every purse rolled, each of the five with money, no flow waiting, no period open, the day's earnings done
      update public.port_treasury set coupon_day = v_rday, earned_day = world.game_day() - 1;
      for i in 1 .. 5 loop
        perform public.treasury_post(v_h[i], 'BUY', 10000000, null, null);
      end loop;
      perform public.tick_city(now());
      perform public.tick_city(now());

      insert into public.players (company_name, nation_id, ducats, is_npc)
      values ('Proof 22 house', (select g.nation_id from public.great_powers g order by g.nation_id limit 1), 0, true) returning id into v_p;
      insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day)
      select h, 'docks', v_p, 10, 1000000, 0, world.game_day() - c_day / v_gds from unnest(v_h) h;   -- 90,000 d. due a day each

      update public.port_treasury set coupon_day = v_rday - 1, profit = 0, earned_day = world.game_day() - 1;
      perform public.treasury_post(v_h[1], 'BUY', 30000, null, null);                -- earned less than its coupon
      perform public.treasury_post(v_h[1], 'SHARE', 5000000, null, null);            -- capital: it pays out none of this
      perform public.treasury_post(v_h[2], 'BUY', 500000, null, null);               -- earned plenty
      perform public.treasury_post(v_h[3], 'CROWN_AID', 5000000, null, null);        -- crown money, nothing earned
      perform public.treasury_post(v_h[3], 'CROWN_CALL', 1000000, null, null);
      perform public.treasury_post(v_h[3], 'CONVOY_DELIVER', 1000000, null, null);
      perform public.treasury_post(v_h[4], 'BUY', 1000, null, null);                 -- a loss
      perform public.treasury_post(v_h[4], 'SELL', -5000, null, null);
      insert into public.treasury_flows (port_id, kind, ducats, created_at)          -- 50 minutes old: past the daybook's 30 game days at the 60 s clock
      values (v_h[5], 'BUY', 40000, now() - interval '50 minutes');
      perform public.treasury_post(v_h[5], 'DONATION', 10000, null, null);           -- income

      v_r := public.tick_city(now());
      v_x := jsonb_build_object(
        'errors', v_r -> 'errors', 'paid', v_r -> 'coupons_paid',
        'flows', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'DIVIDEND'),
        'p1', (select sum(f.ducats) from public.treasury_flows f where f.id > v_mark and f.kind = 'DIVIDEND' and f.port_id = v_h[1]),
        'p2', (select sum(f.ducats) from public.treasury_flows f where f.id > v_mark and f.kind = 'DIVIDEND' and f.port_id = v_h[2]),
        'p3', (select sum(f.ducats) from public.treasury_flows f where f.id > v_mark and f.kind = 'DIVIDEND' and f.port_id = v_h[3]),
        'p4', (select sum(f.ducats) from public.treasury_flows f where f.id > v_mark and f.kind = 'DIVIDEND' and f.port_id = v_h[4]),
        'p5', (select sum(f.ducats) from public.treasury_flows f where f.id > v_mark and f.kind = 'DIVIDEND' and f.port_id = v_h[5]),
        'owed', (select jsonb_object_agg(array_position(v_h, s.port_id)::text, s.accrued) from public.city_shares s where s.player_id = v_p),
        'open', (select count(*) from public.port_treasury t where t.coupon_day <> v_rday or t.profit <> 0));

      perform public.treasury_post(v_h[2], 'BUY', 7000, null, null);
      v_r := public.tick_city(now());
      v_x := v_x || jsonb_build_object(
        'errors2', v_r -> 'errors', 'paid2', v_r -> 'coupons_paid',
        'profit2', (select t.profit from public.port_treasury t where t.port_id = v_h[2]));

      raise exception using errcode = 'ZX322', message = v_x::text;
    exception when sqlstate 'ZX322' then
      v_all := v_all || jsonb_build_object(v_gds::text, sqlerrm::jsonb);
    end;
  end loop;

  foreach v_gds in array array[60, 2880] loop
    v_x := v_all -> v_gds::text;
    if v_x -> 'errors' <> '{}'::jsonb or v_x -> 'errors2' <> '{}'::jsonb or (v_x ->> 'paid')::bigint <> -(v_x ->> 'flows')::bigint then
      raise exception 'PROOF 22 FAIL: the tick''s receipt at % s: %', v_gds, v_x;
    end if;
    if (v_x ->> 'p1')::bigint is distinct from -30000 then
      raise exception 'PROOF 22 FAIL: a city did not pay exactly what it earned at % s: %', v_gds, v_x;
    end if;
    if (v_x ->> 'p2')::bigint is distinct from -90000 then
      raise exception 'PROOF 22 FAIL: a rich city did not pay exactly 9 %% at % s: %', v_gds, v_x;
    end if;
    if v_x ->> 'p3' is not null then
      raise exception 'PROOF 22 FAIL: aid leaked out as a dividend at % s: %', v_gds, v_x;
    end if;
    if v_x ->> 'p4' is not null or (v_x #>> '{owed,4}')::bigint <> 0 or (v_x ->> 'open')::bigint <> 0 then
      raise exception 'PROOF 22 FAIL: a loss paid, was owed, or a period stayed open at % s: %', v_gds, v_x;
    end if;
    if (v_x ->> 'p5')::bigint is distinct from -50000 then
      raise exception 'PROOF 22 FAIL: the old flow and the donation were not counted at % s: %', v_gds, v_x;
    end if;
    if (v_x ->> 'paid2')::bigint <> 0 or (v_x ->> 'profit2')::bigint <> 7000 then
      raise exception 'PROOF 22 FAIL: the second tick of the day at % s: %', v_gds, v_x;
    end if;
  end loop;

  v_x := v_all -> '60';
  raise notice 'PASS: DIV_RECEIPT — no error in either tick, % d. paid', v_x ->> 'paid';
  raise notice 'PASS: DIV_PROFIT — earned 30,000 d., paid %', v_x ->> 'p1';
  raise notice 'PASS: DIV_RATE — due 90,000 d., paid % at 60 s, % at 2880 s', v_x ->> 'p2', v_all -> '2880' ->> 'p2';
  raise notice 'PASS: DIV_NO_LEAK — 7,000,000 d. of crown money, nothing paid';
  raise notice 'PASS: DIV_CAPITAL — 5,000,000 d. of shares, paid %; 10,000 d. of donation counted', v_x ->> 'p1';
  raise notice 'PASS: DIV_LOSS — no dividend, owed %, no period left open', v_x #>> '{owed,4}';
  raise notice 'PASS: DIV_OLD_FLOW — a 50-minute-old 40,000 d. flow and a 10,000 d. donation, paid %', v_x ->> 'p5';
  raise notice 'PASS: DIV_ONE_A_DAY — second tick paid %, profit %', v_x ->> 'paid2', v_x ->> 'profit2';
end
$$;
