-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 209 - A TAX WHEN BUYING, 0 TO 3 %  (migration 0507; owner-spec-plan-2026-11-25.md section 6, row 56 and Q7)
--
--   The owner: "TAX is only payed when only a profit is made, or when buying", and "0-3% is okay". The rate is a tenth of the rate the
--   city asks the buyer, read in one place by every quote, the day's figure and the never-lose rule.
--   The run is BUILT (0498's way: two market rows written here), so no sign hangs on the market. Rolled back by proof.mjs.
--
-- @pass BT_DARK      dark (as deployed): a purchase pays its plain price
-- @pass BT_RATE      lit, a mayor's 30 %: a stranger pays 3 % more and never above it; a foreign company whose home this is pays 1.5 % (0505's half)
-- @pass BT_PAID      the door charges exactly the quote, in one BUY payment to the city's purse; tax_total itemises it; a merchant pays none
-- @pass BT_QUOTES    the Max, the never-lose quote (fleet_run_quote) and the day (run_day) all carry it: the same coin, from the one place
-- @pass BT_WAIT      a run whose profit is smaller than the tax is planned dark and WAITS lit (jobs never lose): nothing bought
-- @pass BT_BARGAIN   with a bargain (0506) the tax is on what she pays after it
-- ══════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0209-4000-8000-0000000000a1';
  c_b    constant uuid := '00000000-0209-4000-8000-0000000000b2';
  v_lis  uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_pl   uuid;
  v_fl   uuid;
  v_pl2  uuid;
  v_fl2  uuid;
  v_g    uuid;
  v_good text;
  v_sell text;
  v_dest uuid;
  v_oth  uuid;   -- their country
  v_q0   numeric;
  v_q1   numeric;
  v_c0   bigint;
  v_r    jsonb;
  v_r1   jsonb;
  v_d0   numeric;
  v_d1   numeric;
  v_p    jsonb;
  v_x    numeric;
  v_tax  numeric;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled', 'fleet_jobs_enabled', 'jobs_wait_enabled', 'sea_courses_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('economy_closed', 'pirate_ports_free');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000;
  v_pl := public.new_house(c_a, 'Casa da Prova 209', 'PRT');
  v_pl2 := public.new_house(c_b, 'Outra Casa 209', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  select f.id into v_fl2 from public.fleets f where f.player_id = v_pl2;
  update public.players set ducats = 5000000 where id in (v_pl, v_pl2);
  -- two companies of a country that Lisbon is not a home or an ally to; its mayor's rate 30 %
  insert into public.port_mayor (port_id, player_id, tax_rate) values (v_lis, v_pl, 0.30) on conflict (port_id) do update set tax_rate = 0.30;
  for v_oth in select g.nation_id from public.great_powers g where not g.pirate order by g.nation_id loop
    update public.players set nation_id = v_oth where id in (v_pl, v_pl2);
    exit when world.tax_rate(v_lis, v_pl2) >= 0.30;
  end loop;
  -- the run, built (0498): the nearest remembered harbour for a good Lisbon offers; Lisbon at the band's floor, the harbour at its ceiling
  select g.code, g.id, k.code, k.to_port into v_good, v_g, v_sell, v_dest
    from public.npc_known_legs(v_lis) k
    join public.port_goods ps on ps.port_id = k.to_port
    join public.goods g on g.id = ps.good_id
    join public.ports pd on pd.id = k.to_port and pd.kind = 'HARBOUR'
   where public.port_offers(v_lis, g.id)
     and exists (select 1 from public.port_goods pl where pl.port_id = v_lis and pl.good_id = g.id)
     and not public.culture_refuses(pd.culture, g.culture_mask)
     and public.fleet_free_hold(v_fl) >= 20 * g.bulk
   order by k.nm, g.base_value desc, g.code limit 1;
  update public.port_goods pg set stock_target = 1000000, stock = 1000000000, affinity = 0.25, demand = 1, drift = 0, season_mod = 0, glut = 0.5, glut_at = now(), haul = 1, want_period = null
   where pg.port_id = v_lis and pg.good_id = v_g;
  update public.port_goods pg set stock_target = 1000000, stock = 0, affinity = 3, demand = 1, drift = 0, season_mod = 0, glut = -0.5, glut_at = now(), want_period = null
   where pg.port_id = v_dest and pg.good_id = v_g;
  perform cmd.assume_identity(c_a);

  -- ── DARK ──
  select q.total into v_q0 from world.quote(v_lis, v_g, 20, 'buy', null, v_fl2) q;
  select q.total into v_x from world.quote(v_lis, v_g, 20, 'buy', null, null) q;
  if v_q0 <> v_x or public.buy_tax_rate(v_fl2, v_lis) <> 0 then
    raise exception 'PROOF 209 FAIL: dark, a purchase pays a tax: % against %', v_q0, v_x;
  end if;
  raise notice 'PASS: BT_DARK - 20 units at Lisbon: % d., the plain price', v_q0;

  -- the same instant's figures without the tax, for BT_QUOTES
  v_r := public.fleet_run_quote(v_pl, v_fl, v_lis, v_good, v_sell, array[v_sell, 'LIS']);
  v_d0 := (public.run_day(v_pl, v_fl, v_lis, v_dest, v_g, 10, floor(public.wc_num('game_day_seconds') / 3),
             (select q.total from world.quote(v_lis, v_g, 10, 'buy', null, v_fl) q), (select q.total from world.quote(v_dest, v_g, 10, 'sell', null, v_fl) q),
             (select s.total - b.total - public.profit_tax(v_dest, s.total - b.total, v_pl) from world.quote(v_lis, v_g, 10, 'buy', null, v_fl) b, world.quote(v_dest, v_g, 10, 'sell', null, v_fl) s))->>'coin')::numeric;

  -- ── LIT ──
  update public.world_config set value = 'true'::jsonb where key = 'buy_tax_enabled';
  v_x := public.buy_tax_rate(v_fl2, v_lis);
  update public.world_config set value = 'true'::jsonb where key = 'tax_thirty_enabled';
  if v_x <> 0.03 or public.buy_tax_rate(v_fl2, v_lis) <> 0.015 or public.home_port_of(v_pl2) is distinct from v_lis then
    raise exception 'PROOF 209 FAIL: at a 30 %% city she pays % (3 %% expected), at home % (1.5 %%)', v_x, public.buy_tax_rate(v_fl2, v_lis);
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'tax_thirty_enabled';
  update public.world_config set value = to_jsonb(0.5) where key = 'buy_tax_share';
  if public.buy_tax_rate(v_fl2, v_lis) <> 0.03 then
    raise exception 'PROOF 209 FAIL: the tax went over 3 %%: %', public.buy_tax_rate(v_fl2, v_lis);
  end if;
  update public.world_config set value = to_jsonb(0.1) where key = 'buy_tax_share';
  raise notice 'PASS: BT_RATE - a mayor''s 30 %%: 3 %% on a purchase, never more; at home with 0505 lit 1.5 %%';

  select q.total into v_q1 from world.quote(v_lis, v_g, 20, 'buy', null, v_fl2) q;
  update public.players set is_npc = true, auth_uid = null where id = v_pl2;
  select q.total into v_x from world.quote(v_lis, v_g, 20, 'buy', null, v_fl2) q;
  update public.players set is_npc = false, auth_uid = c_b where id = v_pl2;
  v_c0 := public.treasury_balance(v_lis);
  v_p := cmd.do_buy(v_fl2, jsonb_build_object('good', v_g, 'qty', 20));
  if v_q1 not between v_q0 * 1.03 - 1.04 and v_q0 * 1.03 + 1 or v_x <> v_q0 or (v_p->>'total')::numeric <> v_q1 or public.treasury_balance(v_lis) - v_c0 <> v_q1
     or abs((v_p->>'tax_total')::numeric - v_q0 * 0.03) > 0.1
     or (select count(*) from public.treasury_flows t where t.player_id = v_pl2 and t.port_id = v_lis and t.kind = 'BUY') <> 1 then
    raise exception 'PROOF 209 FAIL: plain %, lit %, paid %, the purse rose %, a merchant''s %', v_q0, v_q1, v_p, public.treasury_balance(v_lis) - v_c0, v_x;
  end if;
  raise notice 'PASS: BT_PAID - 20 units: % plain, % with the tax (% itemised), paid in one BUY to Lisbon''s purse; a merchant %', v_q0, v_q1, v_p->>'tax_total', v_x;

  -- ── EVERY FIGURE, FROM THE ONE PLACE ──
  -- (her purchase above moved no price of this built row: its quay is a thousand million units deep)
  v_r1 := public.fleet_run_quote(v_pl, v_fl, v_lis, v_good, v_sell, array[v_sell, 'LIS']);
  v_d1 := (public.run_day(v_pl, v_fl, v_lis, v_dest, v_g, 10, floor(public.wc_num('game_day_seconds') / 3),
             (select q.total from world.quote(v_lis, v_g, 10, 'buy', null, v_fl) q), (select q.total from world.quote(v_dest, v_g, 10, 'sell', null, v_fl) q),
             (select s.total - b.total - public.profit_tax(v_dest, s.total - b.total, v_pl) from world.quote(v_lis, v_g, 10, 'buy', null, v_fl) b, world.quote(v_dest, v_g, 10, 'sell', null, v_fl) s))->>'coin')::numeric;
  v_p := public.fleet_buy_capacity(v_fl, v_g);
  v_tax := world.tax_rate(v_dest, v_pl);
  v_x := (v_r1->>'cost')::numeric - (v_r->>'cost')::numeric;   -- the tax on her run's buy
  if v_r1->'units' is distinct from v_r->'units' or v_x not between (v_r->>'cost')::numeric * 0.03 - 2 and (v_r->>'cost')::numeric * 0.03 + 2
     or abs((v_r->>'net')::numeric - (v_r1->>'net')::numeric - v_x * (1 - v_tax)) > 3
     or (v_p->>'est_total')::numeric <> (select q.total from world.quote(v_lis, v_g, (v_p->>'max_qty')::numeric, 'buy', null, v_fl) q)
     or abs((v_d0 - v_d1) - 3 * 0.03 * (1 - v_tax) * (select q.total from world.quote(v_lis, v_g, 10, 'buy', null, null) q)) > 8 then
    raise exception 'PROOF 209 FAIL: the run''s quote % -> %, the day % -> %, the Max %', v_r, v_r1, v_d0, v_d1, v_p;
  end if;
  raise notice 'PASS: BT_QUOTES - the run''s cost % -> %, its net % -> % (the tax is off the taxed gain); a day of three runs % -> %; the Max % d. is the quote',
    v_r->>'cost', v_r1->>'cost', v_r->>'net', v_r1->>'net', v_d0, v_d1, v_p->>'est_total';

  -- ── THE NEVER-LOSE RULE: the sale's mark is raised until the run's profit is under the tax ──
  -- (the tax is made as large as its own knobs need, so the case is built whatever the pair's margin)
  perform cmd.set_fleet_job(v_fl, 'fixed', jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', v_sell));
  update public.world_config set value = 'false'::jsonb where key = 'buy_tax_enabled';
  v_p := public.fleet_job_plan(v_fl);
  update public.world_config set value = 'true'::jsonb where key = 'buy_tax_enabled';
  v_x := ceil((v_r->>'gross')::numeric / (v_r->>'cost')::numeric);
  update public.world_config set value = to_jsonb(v_x) where key = 'buy_tax_max';
  update public.world_config set value = to_jsonb(v_x * 10) where key = 'buy_tax_share';
  v_r1 := public.fleet_job_plan(v_fl);
  update public.world_config set value = to_jsonb(0.03) where key = 'buy_tax_max';
  update public.world_config set value = to_jsonb(0.1) where key = 'buy_tax_share';
  if not (v_p ? 'lines') or v_r1->>'wait' is distinct from 'low' or v_r1 ? 'lines' then
    raise exception 'PROOF 209 FAIL: the never-lose rule does not read the tax: dark % lit %', left(v_p::text, 300), left(v_r1::text, 300);
  end if;
  raise notice 'PASS: BT_WAIT - the same run is planned dark and waits (%) when the tax is more than its profit', v_r1->>'sentence';

  -- ── A BARGAIN, THEN THE TAX ──
  delete from public.fleet_jobs where fleet_id = v_fl;
  update public.world_config set value = 'true'::jsonb where key = 'bargain_total_enabled';
  update public.world_config set value = 'false'::jsonb where key = 'level_skills_on';
  update public.world_config set value = to_jsonb(1) where key in ('bargain_p1_base', 'bargain_p1_max', 'bargain_decay');
  perform cmd.haggle(v_fl, v_g, 'buy');
  perform cmd.haggle(v_fl, v_g, 'buy');
  select q.total into v_q1 from world.quote(v_lis, v_g, 20, 'buy', null, v_fl) q;
  select q.total into v_q0 from world.quote(v_lis, v_g, 20, 'buy', null, null) q;
  if v_q1 not between v_q0 * 0.90 * 1.03 - 2 and v_q0 * 0.90 * 1.03 + 2 then
    raise exception 'PROOF 209 FAIL: two won bargains and the tax: % for % plain', v_q1, v_q0;
  end if;
  raise notice 'PASS: BT_BARGAIN - two won bargains (10 %%) and the 3 %% tax: % d. for % plain', v_q1, v_q0;
end
$p$;
