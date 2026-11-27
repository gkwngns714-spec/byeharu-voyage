-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 221 - PREMIUM GOODS: ONE MADE GOOD, ONE CITY THAT PAYS 3 TO 5 TIMES  (migration 0517; owner-spec rows 18 and 24, answer 5, R7, R8)
--
--   The owner: "Each PREMIUM TRADE GOOD will be needed by one city only, and it will pay 300~500% more"; "3-5 times, with daily limits yes".
--   A company makes the good in the Forge and sells it at its city; the figure comes from the city's purse. The market rows and the purses are
--   written here, so no sign hangs on the market, the dice, the companies or the world's age. Rolled back by proof.mjs.
--
-- @pass PG_DARK      dark (as deployed): the plain price, no premium on the Forge's recipes
-- @pass PG_LIST      the default list: 67 made goods, one city each, none offered where it is wanted; near 3, far 5, straight between
-- @pass PG_FORGE     made in the Forge out of Storage (its recipe names the city and the pay) and sold there: 4 times at 6,250 miles, the quote to the coin
-- @pass PG_MADE      units bought at a quay are paid the normal price at the same city; the Forge counts what she makes, the premium sale takes it off
-- @pass PG_WORLD     the world's sum (players, cities, flows) is the same before and after the sale: no coin made
-- @pass PG_LIMIT     a day's 30 units are shared by two companies; the rest is the normal price; the next day 30 again
-- @pass PG_PURSE     a purse at its floor pays no premium; whatever it holds above, a sale takes at most its share at the premium and never empties it
-- @pass PG_COSTS     a premium good's price is 25 % more at every quay, buying and selling; another good's is not
-- @pass PG_JOBS      the never-lose rule, the run's quote and the day read it: a run that waits at the normal price sails when its city pays the premium
-- ══════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0221-4000-8000-0000000000a1';
  c_b    constant uuid := '00000000-0221-4000-8000-0000000000b2';
  v_lis  uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_pl   uuid;
  v_fl   uuid;
  v_pl2  uuid;
  v_fl2  uuid;
  v_g    uuid;
  v_code text;
  v_dest uuid;
  v_sell text;
  v_g2   uuid;
  v_c2   text;
  v_r    jsonb;
  v_p    jsonb;
  v_d    jsonb;
  v_x    numeric;
  v_y    numeric;
  v_z    numeric;
  v_sum  numeric;
  v_b0   bigint;
  i      int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'fleet_jobs_enabled', 'jobs_wait_enabled', 'sea_courses_enabled');
  v_pl := public.new_house(c_a, 'Casa da Prova 221', 'PRT');
  v_pl2 := public.new_house(c_b, 'Outra Casa 221', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  select f.id into v_fl2 from public.fleets f where f.player_id = v_pl2;
  update public.players set ducats = 5000000 where id in (v_pl, v_pl2);
  update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  -- the made good: not Lisbon's own, its recipe small enough for the shed
  select g.id, g.code into v_g, v_code from public.goods g join public.port_goods pg on pg.port_id = v_lis and pg.good_id = g.id
   where g.tier >= 1 and g.bulk <= 1 and g.base_value >= 100 and not public.port_offers(v_lis, g.id)
     and (select count(*) from public.goods_recipes r where r.product_id = g.id) >= 2
     and not public.culture_refuses((select h.culture from public.ports h where h.id = v_lis), g.culture_mask) order by g.code limit 1;
  update public.port_goods set stock_target = 1000000, stock = 1000000, affinity = 1, demand = 1, drift = 0, season_mod = 0, glut = 0, glut_at = now(), haul = 1, haul_nm = 6250, want_period = null
   where port_id = v_lis and good_id = v_g;
  perform cmd.assume_identity(c_a);

  -- ── DARK ──
  select q.total into v_x from world.quote(v_lis, v_g, 4, 'sell', null, v_fl) q;
  select q.total into v_y from world.quote(v_lis, v_g, 4, 'sell', null, null) q;
  if v_x <> v_y or world.goods_forge(v_lis)::text like '%"premium"%' then
    raise exception 'PROOF 221 FAIL: dark is not the plain price: % against %', v_x, v_y;
  end if;
  raise notice 'PASS: PG_DARK - 4 % at Lisbon: % d., the plain price', v_code, v_x;

  -- ── THE LIST ──
  if (select count(*) from public.goods where premium_port_id is not null) <> 67
     or (select count(distinct premium_port_id) from public.goods) <> 67
     or exists (select 1 from public.goods g where g.premium_port_id is not null
                 and (public.port_offers(g.premium_port_id, g.id) or not exists (select 1 from public.goods_recipes r where r.product_id = g.id)
                      or public.culture_refuses((select h.culture from public.ports h where h.id = g.premium_port_id), g.culture_mask)))
     or public.premium_mult(500) <> 3 or public.premium_mult(6250) <> 4 or public.premium_mult(12000) <> 5 or public.premium_mult(20000) <> 5 then
    raise exception 'PROOF 221 FAIL: the list or the pay by distance';
  end if;
  raise notice 'PASS: PG_LIST - 67 made goods, one city each; 3 times at 500 miles, 4 at 6,250, 5 from 12,000';

  -- ── LIT: made in the Forge, sold at its city ──
  update public.goods set premium_port_id = null where premium_port_id = v_lis or id = v_g;
  update public.goods set premium_port_id = v_lis where id = v_g;
  update public.world_config set value = 'true'::jsonb where key = 'premium_goods_enabled';
  update public.world_config set value = to_jsonb(1) where key = 'premium_price_lift';
  insert into public.player_storage (player_id, port_id, good_id, qty, basis)
  select v_pl, v_lis, r.ingredient_id, r.qty * 4, 5 from public.goods_recipes r where r.product_id = v_g;
  v_r := cmd.forge_good(v_lis, v_g, 4);
  v_p := (select e->'premium' from jsonb_array_elements(world.goods_forge(v_lis)->'recipes') e where e->>'product' = v_code);
  if v_r->>'ok' <> 'true' or v_p->>'port' <> 'LIS' or (v_p->>'mult')::numeric <> 4 or (v_p->>'left')::numeric <> 30 or (v_p->>'mine')::numeric <> 4 or (v_p->>'made')::numeric <> 4 then
    raise exception 'PROOF 221 FAIL: the Forge: % %', v_r, v_p;
  end if;
  perform cmd.do_take(v_fl, jsonb_build_object('good', v_g, 'qty', 4));
  v_x := (select q.total from world.quote(v_lis, v_g, 4, 'sell', null, v_fl) q);
  v_y := (select q.mid_total from world.quote(v_lis, v_g, 4, 'sell', null, v_fl) q) / (select q.mid_total from world.quote(v_lis, v_g, 4, 'sell', null, null) q);
  v_b0 := public.treasury_balance(v_lis);
  v_sum := (select sum(p.ducats) from public.players p) + (select sum(t.ducats) from public.port_treasury t) + (select coalesce(sum(t.ducats), 0) from public.treasury_flows t);
  v_r := cmd.do_sell(v_fl, jsonb_build_object('good', v_g, 'qty', 4));
  if round(v_y, 2) <> 4 or (v_r->>'total')::numeric <> v_x or (v_r->>'premium_units')::numeric <> 4
     or (select sum(t.ducats) from public.treasury_flows t where t.port_id = v_lis and t.player_id = v_pl and t.kind = 'SELL') <> -v_x then
    raise exception 'PROOF 221 FAIL: the sale: % times, quote %, %', v_y, v_x, v_r;
  end if;
  raise notice 'PASS: PG_FORGE - 4 % made in Lisbon''s Forge, sold there for % d., % times the price', v_code, v_x, round(v_y, 2);
  v_y := (select sum(p.ducats) from public.players p) + (select sum(t.ducats) from public.port_treasury t) + (select coalesce(sum(t.ducats), 0) from public.treasury_flows t) - v_sum;
  if v_y <> 0 then
    raise exception 'PROOF 221 FAIL: the sale moved the world''s sum by %', v_y;
  end if;
  raise notice 'PASS: PG_WORLD - Lisbon''s purse % -> %; the world''s sum moved by nothing', v_b0, public.treasury_balance(v_lis);

  -- ── ONLY WHAT SHE MADE ──
  v_x := (select q.mid_total from world.quote(v_lis, v_g, 5, 'sell', null, v_fl) q) / (select q.mid_total from world.quote(v_lis, v_g, 5, 'sell', null, null) q);
  perform cmd.assume_identity(c_b);
  perform public.fleet_load(v_fl2, v_code, 5, 5);   -- bought, not made
  v_y := (select q.mid_total from world.quote(v_lis, v_g, 5, 'sell', null, v_fl2) q) / (select q.mid_total from world.quote(v_lis, v_g, 5, 'sell', null, null) q);
  if public.premium_mine(v_pl, v_g) <> 0 or round(v_x, 2) <> 1 or round(v_y, 2) <> 1 then
    raise exception 'PROOF 221 FAIL: a unit not made was paid the premium: % % %', public.premium_mine(v_pl, v_g), v_x, v_y;
  end if;
  raise notice 'PASS: PG_MADE - her 4 made and sold: no more at a premium; 5 bought by another company: the price';
  perform public.premium_count(v_pl, v_g, 100);
  perform public.premium_count(v_pl2, v_g, 1000);

  -- ── THE DAILY LIMIT, SHARED ──
  perform public.premium_spend(v_pl, v_lis, v_g, 24);   -- 4 and 24 sold: two left
  v_x := (select q.mid_total from world.quote(v_lis, v_g, 5, 'sell', null, v_fl2) q) / (select q.mid_total from world.quote(v_lis, v_g, 5, 'sell', null, null) q);
  v_r := cmd.do_sell(v_fl2, jsonb_build_object('good', v_g, 'qty', 5));
  v_y := (select q.mid_total from world.quote(v_lis, v_g, 5, 'sell', null, v_fl) q) / (select q.mid_total from world.quote(v_lis, v_g, 5, 'sell', null, null) q);
  update public.port_goods set premium_day = premium_day - 1 where port_id = v_lis and good_id = v_g;
  v_z := (select u.left_units from public.premium_units(v_lis, v_g) u);
  if round(v_x, 2) <> 2.20 or (v_r->>'premium_units')::numeric <> 2 or round(v_y, 2) <> 1 or v_z <> 30 then
    raise exception 'PROOF 221 FAIL: the limit: % % % %', v_x, v_r->>'premium_units', v_y, v_z;
  end if;
  raise notice 'PASS: PG_LIMIT - 28 taken, the other company''s 5: 2 at 4 times, 3 at the price; then the first company''s at the price; tomorrow 30';

  -- ── THE PURSE ──
  update public.port_treasury t set ducats = public.city_floor(v_lis) - (public.treasury_balance(v_lis) - t.ducats) where t.port_id = v_lis;
  v_x := coalesce((select u.left_units from public.premium_units(v_lis, v_g) u), 0);
  update public.port_treasury t set reserve = 40000000, ducats = 30000000 - (public.treasury_balance(v_lis) - t.ducats) where t.port_id = v_lis;
  v_y := coalesce((select u.left_units from public.premium_units(v_lis, v_g) u), 0);
  -- a purse a little above its floor, sold to again and again, a unit at a time: the premium stops by itself, over the floor
  update public.world_config set value = to_jsonb(100000) where key = 'premium_day_units';
  update public.port_treasury t set reserve = 0, ducats = public.city_floor(v_lis) + 200000 - (public.treasury_balance(v_lis) - t.ducats) where t.port_id = v_lis;
  update public.port_goods set stock_target = 100000000 where port_id = v_lis and good_id = v_g;
  update public.port_goods set stock = 100000000 where port_id = v_lis and good_id = v_g;
  perform public.fleet_load(v_fl2, v_code, 30, 5);
  i := 0;
  loop
    v_r := null;
    exit when public.fleet_cargo_qty(v_fl2, v_code) < 1 or i >= 30;
    v_b0 := public.treasury_balance(v_lis);
    v_z := coalesce((select u.left_units * u.mult * world.mid_price(v_lis, v_g, 100000000) from public.premium_units(v_lis, v_g) u), 0);
    if v_z > (v_b0 - public.city_floor(v_lis)) * 0.05 + 1 then
      raise exception 'PROOF 221 FAIL: of % the premium may take %', v_b0, v_z;
    end if;
    v_r := cmd.do_sell(v_fl2, jsonb_build_object('good', v_g, 'qty', 1));
    i := i + 1;
  end loop;
  if v_x <> 0 or v_y <> 0 or i < 5 or public.treasury_balance(v_lis) <= public.city_floor(v_lis) then
    raise exception 'PROOF 221 FAIL: the purse: % % % sales, % left of a floor of %', v_x, v_y, i, public.treasury_balance(v_lis), public.city_floor(v_lis);
  end if;
  raise notice 'PASS: PG_PURSE - at the floor none, under its reserve none; % sales one after another left Lisbon % d., over its floor of %', i, public.treasury_balance(v_lis), public.city_floor(v_lis);
  update public.world_config set value = to_jsonb(30) where key = 'premium_day_units';
  update public.port_treasury set ducats = 500000000, reserve = 0;

  -- ── IT COSTS MORE ──
  select g.id, g.code into v_g2, v_c2 from public.goods g join public.port_goods pg on pg.port_id = v_lis and pg.good_id = g.id where g.premium_port_id is null order by g.code limit 1;
  select h.id into v_dest from public.ports h join public.port_goods pg on pg.port_id = h.id and pg.good_id = v_g where h.kind = 'HARBOUR' and h.id <> v_lis order by h.code limit 1;
  v_x := world.mid_price(v_dest, v_g, 1000);
  v_y := world.mid_price(v_dest, v_g2, 1000);
  update public.world_config set value = to_jsonb(1.25) where key = 'premium_price_lift';
  if abs(world.mid_price(v_dest, v_g, 1000) - v_x * 1.25) > 0.001 or world.mid_price(v_dest, v_g2, 1000) <> v_y
     or (select m.mid from world.good_mids(v_g) m where m.port_id = v_dest) <> (select world.mid_price(v_dest, v_g, pg.stock) from public.port_goods pg where pg.port_id = v_dest and pg.good_id = v_g)
     or ((world.price_why(v_dest, v_g))->>'base')::numeric <> (select g.base_value * 1.25 from public.goods g where g.id = v_g) then
    raise exception 'PROOF 221 FAIL: the lift at another quay';
  end if;
  raise notice 'PASS: PG_COSTS - % at another quay % -> %, % unmoved', v_code, v_x, world.mid_price(v_dest, v_g, 1000), v_c2;

  -- ── THE JOBS: the nearest remembered harbour for a good Lisbon offers and it does not; the sale under the buy, so a plain run loses ──
  update public.world_config set value = to_jsonb(1) where key = 'premium_price_lift';
  update public.world_config set value = 'false'::jsonb where key = 'premium_goods_enabled';
  select g.id, g.code, k.code, k.to_port into v_g, v_code, v_sell, v_dest
    from public.npc_known_legs(v_lis) k
    join public.port_goods ps on ps.port_id = k.to_port
    join public.goods g on g.id = ps.good_id
    join public.ports pd on pd.id = k.to_port and pd.kind = 'HARBOUR'
   where public.port_offers(v_lis, g.id) and not public.port_offers(k.to_port, g.id)
     and exists (select 1 from public.port_goods pl where pl.port_id = v_lis and pl.good_id = g.id)
     and not public.culture_refuses(pd.culture, g.culture_mask)
     and public.fleet_free_hold(v_fl) >= 20 * g.bulk
   order by k.nm, g.base_value desc, g.code limit 1;
  update public.port_goods set stock_target = 1000000, stock = 1000000, affinity = 1, demand = 1, drift = 0, season_mod = 0, glut = 0, glut_at = now(), haul = 1, haul_nm = 12000, want_period = null
   where good_id = v_g and port_id in (v_lis, v_dest);
  update public.port_goods set affinity = 0.8 where good_id = v_g and port_id = v_dest;
  update public.goods set premium_port_id = null where premium_port_id in (v_dest) or id = v_g;
  update public.goods set premium_port_id = v_dest where id = v_g;
  perform cmd.assume_identity(c_a);
  perform cmd.set_fleet_job(v_fl, 'fixed', jsonb_build_object('good', v_code, 'buy', 'LIS', 'sell', v_sell));
  v_p := public.fleet_job_plan(v_fl);
  v_r := public.fleet_run_quote(v_pl, v_fl, v_lis, v_code, v_sell, array[v_sell, 'LIS']);
  update public.world_config set value = 'true'::jsonb where key = 'premium_goods_enabled';
  if (public.fleet_job_plan(v_fl))->>'wait' is distinct from 'low' then
    raise exception 'PROOF 221 FAIL: a run of bought units sails for a premium she did not earn';
  end if;
  perform public.premium_count(v_pl, v_g, 1000);
  v_d := public.fleet_run_quote(v_pl, v_fl, v_lis, v_code, v_sell, array[v_sell, 'LIS']);
  if v_p->>'wait' is distinct from 'low' or (v_r->>'net')::numeric >= 0 or (v_d->>'net')::numeric <= 0
     or (v_d->>'gross')::numeric <> (select q.total from world.quote(v_dest, v_g, (v_d->>'units')::numeric, 'sell', null, v_fl) q)
     or not (public.fleet_job_plan(v_fl) ? 'lines') then
    raise exception 'PROOF 221 FAIL: the job: dark % % lit % %', v_p, v_r, v_d, public.fleet_job_plan(v_fl);
  end if;
  -- the day of three runs of 10 units: the 30 of the day at 5 times, as ONE sale of them brings
  v_x := (public.run_day(v_pl, v_fl, v_lis, v_dest, v_g, 10, floor(public.wc_num('game_day_seconds') / 3),
            (select q.total from world.quote(v_lis, v_g, 10, 'buy', null, v_fl) q), (select q.total from world.quote(v_dest, v_g, 10, 'sell', null, v_fl) q),
            (select s.total - b.total - public.profit_tax(v_dest, s.total - b.total, v_pl) from world.quote(v_lis, v_g, 10, 'buy', null, v_fl) b, world.quote(v_dest, v_g, 10, 'sell', null, v_fl) s))->>'coin')::numeric;
  v_y := (select s.total - b.total - public.profit_tax(v_dest, s.total - b.total, v_pl) from world.quote(v_lis, v_g, 30, 'buy', null, v_fl) b, world.quote(v_dest, v_g, 30, 'sell', null, v_fl) s);
  if abs(v_x - v_y) > greatest(10, v_y * 0.01) then
    raise exception 'PROOF 221 FAIL: the day % against one sale of its units %', v_x, v_y;
  end if;
  raise notice 'PASS: PG_JOBS - % to %: dark it would leave % and waits; lit it leaves % and sails; a day of three runs % (one sale of its 30 units %)', v_code, v_sell, v_r->>'net', v_d->>'net', v_x, v_y;
end $p$;
