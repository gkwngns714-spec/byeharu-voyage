-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 159 — THE INVEST TRAY SAYS WHAT A SHARE PAYS  (migration 0456: public.invest_for answers coupon_day by public.coupon_day_of)
--
--   The fault (found in play 2026-11-18, docs/dev-log/2026-11-18-play-faults.md fault 2): the Invest tray showed a price and no return. 0456 puts
--   the coupon rule in one home (public.coupon_day_of: paid x works_coupon_day x public.influence_coupon_mult), public.city_coupons pays by it,
--   and public.invest_for (so cmd.invest and the tray's cmd.preview_invest) answers `coupon_day`: what the buy adds to the daily coupon.
--
--   A probe house sails for Portugal and lies docked at Lisbon (Portugal's city), the purses and the influence race lit for this transaction.
--   She asks the dry run, then buys; Lisbon's coupon is run a real day later, first with room enough to pay every due, then with a small profit.
--
-- @pass INVEST_RETURN_QUOTE    the dry run's coupon_day is round(cost x works_coupon_day x her multiplier), and the buy answers the same
-- @pass INVEST_RETURN_MULT     the holder of the city is quoted 1.5x: dark, the same buy is quoted at 1x
-- @pass INVEST_RETURN_PAID     a real day on, with surplus and profit to spare, city_coupons credits her row exactly the quoted coupon_day
-- @pass INVEST_RETURN_UP_TO    with a small profit the city pays no more than it, and her row is credited less than the quote: an "up to"
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth  constant uuid := '00000000-0456-4000-8000-0000000000aa';
  v_pl    uuid;
  v_fl    uuid;
  v_lis   uuid;
  v_kind  text;
  v_n     int;
  v_p     jsonb;
  v_dark  jsonb;
  v_b     jsonb;
  v_c     jsonb;
  v_rate  numeric := public.wc_num('works_coupon_day');
  v_want  bigint;
  v_rday  int := public.real_day(now());
  v_today int := world.game_day(now());
  v_a0    bigint;
  v_a1    bigint;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled');
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  if public.port_nation(v_lis) is distinct from (select n.id from public.nations n where n.code = 'PRT') then
    raise exception 'proof 159: Lisbon is not Portugal''s in this world, so the holder''s multiplier cannot be shown';
  end if;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (c_auth, 'Casa da Prova 159', (select n.id from public.nations n where n.code = 'PRT'), 100000000, false)
  returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Prova', v_lis);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova', true, true);
  perform cmd.assume_identity(c_auth);

  -- the first work at Lisbon with shares on offer; ten of them (or what is offered)
  select k.kind, least(public.city_offered(v_lis, k.kind), 10) into v_kind, v_n
    from unnest(array['docks', 'market', 'production', 'inn']) with ordinality k(kind, o)
   where public.city_offered(v_lis, k.kind) > 0 order by k.o limit 1;
  if v_kind is null then raise exception 'proof 159: Lisbon offers no shares'; end if;

  -- THE QUOTE
  v_p := cmd.preview_invest(v_lis, v_kind, v_n);
  if not coalesce((v_p ->> 'ok')::boolean, false) then raise exception 'proof 159: the dry run refused: %', v_p; end if;
  v_p := v_p -> 'estimate';
  v_want := round((v_p ->> 'cost')::numeric * v_rate * 1.5)::bigint;
  if public.influence_coupon_mult(v_lis, v_pl) <> 1.5 or (v_p ->> 'coupon_day')::bigint <> v_want or v_want <= 0 then
    raise exception 'proof 159: the dry run quotes coupon_day % for cost %; the rule says % (multiplier %)', v_p ->> 'coupon_day', v_p ->> 'cost', v_want,
      public.influence_coupon_mult(v_lis, v_pl);
  end if;

  -- DARK: the same buy at 1x
  update public.world_config set value = 'false'::jsonb where key = 'influence_enabled';
  v_dark := cmd.preview_invest(v_lis, v_kind, v_n) -> 'estimate';
  update public.world_config set value = 'true'::jsonb where key = 'influence_enabled';
  if (v_dark ->> 'coupon_day')::bigint <> round((v_dark ->> 'cost')::numeric * v_rate)::bigint or (v_dark ->> 'cost') <> (v_p ->> 'cost') then
    raise exception 'proof 159: dark, the quote is % for cost % (rate %)', v_dark ->> 'coupon_day', v_dark ->> 'cost', v_rate;
  end if;
  raise notice 'PASS: INVEST_RETURN_MULT — % shares of Lisbon''s % for %: the holder of the city is quoted %, dark %', v_n, v_kind, v_p ->> 'cost',
    v_p ->> 'coupon_day', v_dark ->> 'coupon_day';

  -- THE BUY answers the same figure
  v_b := cmd.invest(v_lis, v_kind, v_n);
  if not coalesce((v_b ->> 'ok')::boolean, false) or (v_b ->> 'coupon_day') <> (v_p ->> 'coupon_day') then
    raise exception 'proof 159: the buy answers % and the dry run said %', v_b, v_p ->> 'coupon_day';
  end if;
  raise notice 'PASS: INVEST_RETURN_QUOTE — cost % x works_coupon_day % x 1.5 = coupon_day %, in the dry run and the buy', v_p ->> 'cost', v_rate, v_want;

  -- A REAL DAY ON, ROOM TO PAY EVERY DUE: Lisbon's last coupon a day back, her stamp a day back, its profit and purse ample
  update public.port_treasury t set coupon_day = v_rday - 1, profit = 1000000000000 where t.port_id = v_lis;
  perform public.treasury_post(v_lis, 'GRANT', 1000000000000, null, null);
  update public.city_shares s set accrued_day = v_today - 1000 where s.port_id = v_lis and s.kind = v_kind and s.player_id = v_pl;
  select s.accrued into v_a0 from public.city_shares s where s.port_id = v_lis and s.kind = v_kind and s.player_id = v_pl;
  v_c := public.city_coupons(v_lis, now());
  select s.accrued into v_a1 from public.city_shares s where s.port_id = v_lis and s.kind = v_kind and s.player_id = v_pl;
  if v_a1 - v_a0 <> v_want or (v_c ->> 'paid') <> (v_c ->> 'due') then
    raise exception 'proof 159: with room to pay, her row was credited % against the quote % (city paid %, due %)', v_a1 - v_a0, v_want, v_c ->> 'paid', v_c ->> 'due';
  end if;
  raise notice 'PASS: INVEST_RETURN_PAID — a real day on, Lisbon paid every due (%), and her row was credited %, the quote', v_c ->> 'due', v_a1 - v_a0;

  -- THE NEXT DAY, A SMALL PROFIT: the city pays no more than it, and her row is credited less than the quote
  update public.port_treasury t set coupon_day = v_rday - 1, profit = 1 where t.port_id = v_lis;
  update public.city_shares s set accrued_day = v_today - 1000 where s.port_id = v_lis and s.kind = v_kind and s.player_id = v_pl;
  select s.accrued into v_a0 from public.city_shares s where s.port_id = v_lis and s.kind = v_kind and s.player_id = v_pl;
  v_c := public.city_coupons(v_lis, now());
  select s.accrued into v_a1 from public.city_shares s where s.port_id = v_lis and s.kind = v_kind and s.player_id = v_pl;
  if (v_c ->> 'paid')::bigint > 1 or v_a1 - v_a0 >= v_want or (v_c ->> 'due')::bigint < v_want then
    raise exception 'proof 159: with profit 1 the city paid % (due %), her row credited % against the quote %', v_c ->> 'paid', v_c ->> 'due', v_a1 - v_a0, v_want;
  end if;
  raise notice 'PASS: INVEST_RETURN_UP_TO — profit 1: due %, paid %, her row credited % of the quoted %', v_c ->> 'due', v_c ->> 'paid', v_a1 - v_a0, v_want;
end $$;
