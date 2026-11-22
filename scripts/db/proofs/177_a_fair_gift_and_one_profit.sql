-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 177 - A FAIR GIFT AND ONE PROFIT  (migration 0474; docs/design/playable-2026-11-22.md section 6, findings 2, 28 and 1)
--
--   The migration's self-assert holds every hunk to its pre-image and probes the worth, the Week and the wages rule. This proof plays the
--   doors with the economy closed and the city purses lit (as production runs): the capital's gift roster (public.capital_gift_roster)
--   with a hull on order, the Trade cards (world.best_sales) against the trip board a card opens (world.good_board), a call and a sale
--   (public.port_call, cmd.do_sell) against her purse, and the Week (world.houses_week) settled and live. Rolled back by proof.mjs.
--
-- @pass GP_GIFT_DARK  dark: a company with 5,000 coins and a 48,557 hull on order is on the gift's roster (the order made her "broke")
-- @pass GP_GIFT_LIT   lit: with the hull on order, or launched within the cooldown and hers, she is not; launched before the cooldown,
--                     or with no order, she is again (the line itself unmoved)
-- @pass GP_CARD       closed economy, first hour lit: every Lisbon card is the trip board's row for its units to the coin, dock fee and
--                     all (at least one with a dock fee above 0)
-- @pass GP_SALE       a call and a sale: the SOLD event's trip_net is profit - tax - wages - dock_fee, its wages are what the crew was
--                     paid, its dock fee the call's, and her purse moved exactly trip_net + the goods' cost; a second sale there carries no fee
-- @pass GP_WEEK       the Week, dark and lit: lit it counts a sale and not a gift or a hull order, read live and after the history job
--                     adds the day (not_trade), the same figure; dark both are as before
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0474-4000-8000-0000000000a1';
  c_b    constant uuid := '00000000-0474-4000-8000-0000000000b1';
  c_c    constant uuid := '00000000-0474-4000-8000-0000000000c1';
  c_d    constant uuid := '00000000-0474-4000-8000-0000000000d1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a    uuid;
  v_b    uuid;
  v_c    uuid;
  v_d    uuid;
  v_fa   uuid;
  v_fb   uuid;
  v_fc   uuid;
  v_sh   uuid;
  v_s    jsonb;
  v_r    jsonb;
  v_row  jsonb;
  v_ev   jsonb;
  v_ev2  jsonb;
  v_call jsonb;
  v_r0   jsonb;
  v_r1   jsonb;
  v_on   boolean;
  v_n    int := 0;
  v_m    int := 0;
  v_k    int := 0;
  v_p0   bigint;
  v_p1   bigint;
  v_wg   bigint;
  v_cool int := public.wc_int('gift_cooldown_hours');
  v_g1   record;
  v_g2   record;
  v_day  record;
  x      record;
begin
  -- the four companies are founded first: a closed economy makes no new gold (E_NO_NEW_GOLD)
  v_a := public.new_house(c_a, 'Casa da Dadiva A 177', 'PRT');
  v_b := public.new_house(c_b, 'Casa da Dadiva B 177', 'PRT');
  v_c := public.new_house(c_c, 'Casa da Dadiva C 177', 'PRT');
  insert into auth.users (id) values (c_d) on conflict do nothing;   -- D has a login: she is on the board, and the settle writes her row
  v_d := public.new_house(c_d, 'Casa da Dadiva D 177', 'PRT');
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  update public.world_config set value = 'false'::jsonb where key = 'fair_gift_enabled';

  -- ── GP_GIFT_DARK ──
  select f.id into v_fa from public.fleets f where f.player_id = v_a limit 1;
  select s.id into v_sh from public.ships s where s.player_id = v_a limit 1;
  update public.players set ducats = 5000 where id = v_a;   -- written straight (rolled back): she ordered her second hull
  insert into public.hull_orders (player_id, port_id, class_code, labour, materials, fee, price, ordered_at, ready_at)
  values (v_a, v_lis, 'barca', 15000, 2566, 30991, 48557, now(), now() + interval '30 minutes');
  if not exists (select 1 from public.capital_gift_roster(now(), v_a)) then
    raise exception 'PROOF 177 FAILED: dark, the company with 5,000 and a hull on order is not on the gift''s roster (worth %)', public.player_worth(v_a);
  end if;
  raise notice 'PASS: GP_GIFT_DARK — dark: 5,000 coins and a 48,557 hull on order: worth %, on the roster (the line %).',
    public.player_worth(v_a), public.wc_int('starting_ducats') * public.wc_num('merchant_broke_pct');

  -- ── GP_GIFT_LIT ──
  update public.world_config set value = 'true'::jsonb where key = 'fair_gift_enabled';
  if exists (select 1 from public.capital_gift_roster(now(), v_a)) then
    raise exception 'PROOF 177 FAILED: lit, with the hull on order she is on the roster (worth %)', public.player_worth(v_a);
  end if;
  update public.hull_orders set launched_at = now() - interval '1 hour', ship_id = v_sh where player_id = v_a;
  if exists (select 1 from public.capital_gift_roster(now(), v_a)) then
    raise exception 'PROOF 177 FAILED: lit, launched an hour ago and hers, she is on the roster (worth %)', public.player_worth(v_a);
  end if;
  update public.hull_orders set launched_at = now() - make_interval(hours => v_cool + 1) where player_id = v_a;
  if not exists (select 1 from public.capital_gift_roster(now(), v_a)) then
    raise exception 'PROOF 177 FAILED: lit, launched % hours ago she is not on the roster (worth %)', v_cool + 1, public.player_worth(v_a);
  end if;
  delete from public.hull_orders where player_id = v_a;
  if not exists (select 1 from public.capital_gift_roster(now(), v_a)) then
    raise exception 'PROOF 177 FAILED: lit, with no hull ordered she is not on the roster (worth %)', public.player_worth(v_a);
  end if;
  raise notice 'PASS: GP_GIFT_LIT — lit: on order and launched within % h, off the roster; launched before it, or no order, on it (worth %).',
    v_cool, public.player_worth(v_a);
  update public.world_config set value = 'false'::jsonb where key = 'fair_gift_enabled';

  -- ── GP_CARD ── (first hour lit, as production runs; finding 1's card fix is not switched)
  update public.world_config set value = 'true'::jsonb where key = 'first_hour_enabled';
  select f.id into v_fb from public.fleets f where f.player_id = v_b limit 1;
  perform cmd.assume_identity(c_b);
  v_s := world.best_sales(v_fb, v_lis);
  if (v_s ->> 'cut')::boolean then
    raise exception 'PROOF 177 FAILED: the cards ran out of their budget (a cut answer cannot be compared)';
  end if;
  for x in
    select n.e as card, g.id as good
      from jsonb_array_elements(v_s -> 'goods') n(e)
      join public.goods g on g.code = n.e ->> 'good'
     where n.e ->> 'basis' <> 'on_board' and n.e ->> 'port' is not null
  loop
    v_n := v_n + 1;
    v_r := world.good_board(x.good, v_fb, v_lis, (x.card ->> 'units')::numeric);
    select e into v_row from jsonb_array_elements(v_r -> 'sell') e where e ->> 'port' = x.card ->> 'port';
    if v_row is not null and (v_row ->> 'units')::numeric = (x.card ->> 'units')::numeric then
      v_m := v_m + 1;
      if (v_row ->> 'profit')::numeric is distinct from (x.card ->> 'profit')::numeric
         or (v_row ->> 'cost')::numeric is distinct from (x.card ->> 'cost')::numeric then
        raise exception 'PROOF 177 FAILED: the card of % (% units to %, profit %, cost %) is not the board''s row (profit %, cost %, dock fee %)',
          x.card ->> 'good', x.card ->> 'units', x.card ->> 'port', x.card ->> 'profit', x.card ->> 'cost', v_row ->> 'profit', v_row ->> 'cost', v_row ->> 'dock_fee';
      end if;
      if coalesce((v_row ->> 'dock_fee')::numeric, 0) > 0 then
        v_k := v_k + 1;
      end if;
    end if;
  end loop;
  if v_m = 0 or v_k = 0 then
    raise exception 'PROOF 177 FAILED: % cards, % held to the board, % with a dock fee: nothing was proved', v_n, v_m, v_k;
  end if;
  raise notice 'PASS: GP_CARD — closed economy: % Lisbon cards, % held to the trip board''s row to the coin, % of them with a dock fee.', v_n, v_m, v_k;

  -- ── GP_SALE ──
  select f.id into v_fc from public.fleets f where f.player_id = v_c limit 1;
  -- two goods Lisbon buys, bought (written straight) at half her bid, five units each
  select g.id, g.code, g.name, q.avg_price as bid into v_g1
    from public.goods g cross join lateral world.quote(v_lis, g.id, 5, 'sell', null, v_fc) q
   where public.port_offers(v_lis, g.id) and q.units = 5 and q.avg_price > 50
   order by g.code limit 1;
  select g.id, g.code, g.name, q.avg_price as bid into v_g2
    from public.goods g cross join lateral world.quote(v_lis, g.id, 5, 'sell', null, v_fc) q
   where public.port_offers(v_lis, g.id) and q.units = 5 and q.avg_price > 50 and g.id <> v_g1.id
   order by g.code limit 1;
  if v_g1.id is null or v_g2.id is null then
    raise exception 'PROOF 177 FAILED: Lisbon bids for fewer than two goods';
  end if;
  update public.ships set cargo = jsonb_build_object(v_g1.code, 5, v_g2.code, 5),
                          cargo_basis = jsonb_build_object(v_g1.code, floor(v_g1.bid / 2), v_g2.code, floor(v_g2.bid / 2))
   where fleet_id = v_fc;
  insert into public.fleet_wages (fleet_id, owed, visit_net, visit_paid) values (v_fc, 40, 0, 0)
    on conflict (fleet_id) do update set owed = 40, visit_net = 0, visit_paid = 0;
  select p.ducats into v_p0 from public.players p where p.id = v_c;
  update public.port_treasury set ducats = 1000000000000 where port_id = v_lis;   -- this world's purses are thin (proof 105): Lisbon can pay
  v_call := public.port_call(v_fc, v_lis, v_c, now(), now(), null);
  if coalesce((v_call ->> 'fee')::bigint, 0) <= 0 or (v_call ->> 'owed')::bigint <> 0
     or (select f.call_fee from public.fleets f where f.id = v_fc) is distinct from (v_call ->> 'fee')::bigint then
    raise exception 'PROOF 177 FAILED: the call charged % and the fleet keeps %', v_call, (select f.call_fee from public.fleets f where f.id = v_fc);
  end if;
  v_r := cmd.do_sell(v_fc, jsonb_build_object('good', v_g1.id, 'qty_mode', 'ALL'));
  select e.payload into v_ev from public.events e where e.player_id = v_c and e.kind = 'SOLD' and e.payload ->> 'good' = v_g1.name;
  select coalesce(-sum(l.ducats_delta), 0) into v_wg from public.ledger l where l.player_id = v_c and l.kind = 'WAGES';
  select p.ducats into v_p1 from public.players p where p.id = v_c;
  if v_ev is null or (v_ev ->> 'trip_net')::bigint is distinct from (v_ev ->> 'profit')::bigint - (v_ev ->> 'tax')::bigint - (v_ev ->> 'wages')::bigint - (v_ev ->> 'dock_fee')::bigint
     or (v_ev ->> 'dock_fee')::bigint <> (v_call ->> 'fee')::bigint
     or (v_ev ->> 'wages')::bigint <> v_wg or (v_r ->> 'wages')::bigint <> v_wg or v_wg <= 0
     or v_p1 - v_p0 <> (v_ev ->> 'trip_net')::bigint + (v_ev ->> 'cost')::bigint
     or (select f.call_fee from public.fleets f where f.id = v_fc) is not null then
    raise exception 'PROOF 177 FAILED: the sale''s event % (call %, wages paid %, purse % -> %)', v_ev, v_call, v_wg, v_p0, v_p1;
  end if;
  perform cmd.do_sell(v_fc, jsonb_build_object('good', v_g2.id, 'qty_mode', 'ALL'));
  select e.payload into v_ev2 from public.events e where e.player_id = v_c and e.kind = 'SOLD' and e.payload ->> 'good' = v_g2.name;
  if (v_ev2 ->> 'dock_fee')::bigint <> 0
     or (v_ev2 ->> 'trip_net')::bigint is distinct from (v_ev2 ->> 'profit')::bigint - (v_ev2 ->> 'tax')::bigint - (v_ev2 ->> 'wages')::bigint then
    raise exception 'PROOF 177 FAILED: the second sale''s event %', v_ev2;
  end if;
  raise notice 'PASS: GP_SALE — % x5: profit %, tax %, wages %, dock fee % -> trip_net %; purse moved % (= trip_net + cost %); the second sale fee 0.',
    v_g1.code, v_ev ->> 'profit', v_ev ->> 'tax', v_ev ->> 'wages', v_ev ->> 'dock_fee', v_ev ->> 'trip_net', v_p1 - v_p0, v_ev ->> 'cost';

  -- ── GP_WEEK ──
  update public.world_config set value = 'true'::jsonb where key = 'houses_board_enabled';
  perform cmd.assume_identity(c_d);
  perform public.credit(v_d, 'SELL', 3000, null);
  perform public.credit(v_d, 'CAPITAL_GIFT', 40000, null);
  perform public.credit(v_d, 'BUILD', -20000, null);
  v_r0 := world.houses_week();
  update public.world_config set value = 'true'::jsonb where key = 'fair_gift_enabled';
  v_r1 := world.houses_week();
  if (v_r0 -> 'you' ->> 'net')::bigint - (v_r1 -> 'you' ->> 'net')::bigint <> 20000 then
    raise exception 'PROOF 177 FAILED: live, dark % and lit % differ by other than the gift less the order (20,000)', v_r0 -> 'you', v_r1 -> 'you';
  end if;
  -- the history job adds her day and moves its mark (as public.tick_history does, in one transaction)
  perform public.history_ledger_add(now() - interval '1 millisecond', now());
  update public.history_mark set ledger_through = now();
  select h.earned, h.lost, h.not_trade into v_day from public.history_company_day h where h.player_id = v_d and h.day = (now() at time zone 'UTC')::date;
  if v_day.not_trade is distinct from 20::bigint * 1000 then
    raise exception 'PROOF 177 FAILED: her day %, not_trade not 20,000', v_day;
  end if;
  if world.houses_week() -> 'you' is distinct from v_r1 -> 'you' then
    raise exception 'PROOF 177 FAILED: lit, settled % against live %', world.houses_week() -> 'you', v_r1 -> 'you';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'fair_gift_enabled';
  if world.houses_week() -> 'you' is distinct from v_r0 -> 'you' then
    raise exception 'PROOF 177 FAILED: dark, settled % against live %', world.houses_week() -> 'you', v_r0 -> 'you';
  end if;
  -- the settle: her row (she is on the board: a company with a login)
  v_on := exists (select 1 from public.players p join auth.users u on u.id = p.auth_uid where p.id = v_d);
  update public.world_config set value = 'true'::jsonb where key = 'fair_gift_enabled';
  perform public.houses_week_settle(now());
  if not v_on then
    raise exception 'PROOF 177 FAILED: the probe company D has no login, so the settle cannot be held';
  end if;
  if (select w.net from public.houses_week w where w.player_id = v_d
                  and w.week = public.history_bucket((now() at time zone 'UTC')::date, 'week')) is distinct from (v_r1 -> 'you' ->> 'net')::bigint then
    raise exception 'PROOF 177 FAILED: lit, the settle wrote % for her, live %', (select w.net from public.houses_week w where w.player_id = v_d), v_r1 -> 'you';
  end if;
  raise notice 'PASS: GP_WEEK — a sale 3,000, a gift 40,000, a hull order -20,000: dark %, lit % (live and settled the same; not_trade %; the settle wrote her row the same).',
    v_r0 -> 'you' ->> 'net', v_r1 -> 'you' ->> 'net', v_day.not_trade;
end $p$;
