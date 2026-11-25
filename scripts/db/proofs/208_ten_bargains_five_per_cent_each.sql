-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 208 - TEN BARGAINS, FIVE PER CENT EACH  (migration 0506; owner-spec-plan-2026-11-25.md section 6, rows 50-53)
--
--   The owner: "You can bargain 10 times for price reduction or increase when selling. The success rate will decrease everytime you
--   attempt. Each time you attempt will create 5% of total price reduction. This will also be enhanced by captains, and
--   skills(level)". And: a failed bargain costs nothing; passive orders may bargain "with higher levels in skills".
--   Through the doors: a company founded by public.new_house, cmd.haggle, cmd.do_buy, cmd.do_sell, cmd.set_fleet_job, with the city
--   purses LIT (a bargain is paid by the city). No outcome hangs on the dice or on the market: the chance is set to 1 or 0 by the
--   rule's own knobs, the three market rows are stocked here, and every price is compared with the same quote without the bargain.
--   Rolled back by proof.mjs.
--
-- @pass B10_DARK     dark (as deployed): three tries, the fourth refused, and a win moves her price by a share of the spread only
-- @pass B10_CURVE    lit: the chance of try n is p1 x 0.5^(n-1): 0.25, 0.125, 0.0625 ...; Negotiation 20 makes p1 0.44; never above 0.50
-- @pass B10_FREE     ten lost tries cost nothing: her purse, her price and the city's purse are where they were; the eleventh is refused
-- @pass B10_WIN      a win is 5 % of HER total, three are 15 %; the published price and another company's quote do not move; the trade
--                    pays exactly the quoted total and the city's purse receives exactly it; a second trade gets no bargain
-- @pass B10_RESALE   the same day the other side is refused (E_BARGAIN_SIDE) and the city takes back what it gave: what she bought with a
--                    bargain sells there for no more than she paid
-- @pass B10_SELL     selling: two wins add 10 % to her total, paid by the city's purse (less the profit tax it takes back); buying it back costs 10 % more
-- @pass B10_BROKE    a bargained sale the city cannot pay is refused (E_CITY_BROKE): the purse does not go under nought
-- @pass B10_JOB      a standing job set through cmd.set_fleet_job: below Negotiation 8 no try; at 8 / 12 / 16: 3 / 6 / 10; its quote is the
--                    EXPECTED factor; its buy makes the tries through cmd.haggle once a day; {"bargain": false} at the door turns it off
-- @pass B10_DAY      the day's figure (public.run_day) counts the expected bargain on its FIRST run only, not on every run
-- @pass B10_LEVEL    her own tries earn Negotiation experience (5, and 15 more for a win); a job's earn none
-- ══════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0208-4000-8000-0000000000a1';
  c_b    constant uuid := '00000000-0208-4000-8000-0000000000b2';
  v_lis  uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_pl   uuid;
  v_fl   uuid;
  v_pl2  uuid;
  v_fl2  uuid;
  v_g    uuid[];
  v_r    jsonb;
  v_q0   bigint;
  v_q1   bigint;
  v_q3   bigint;
  v_oth  bigint;
  v_paid bigint;
  v_got  bigint;
  v_p0   bigint;
  v_c0   bigint;
  v_x    numeric;
  v_n    int;
  v_arr  jsonb := '[]'::jsonb;
  v_ev   bigint;
  i      int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'fleet_jobs_enabled', 'level_perks_on');
  update public.world_config set value = 'false'::jsonb where key = 'level_skills_on';   -- no experience booked until B10_LEVEL
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000 where port_id = v_lis;
  v_pl := public.new_house(c_a, 'Casa da Prova 208', 'PRT');
  v_pl2 := public.new_house(c_b, 'Outra Casa 208', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  select f.id into v_fl2 from public.fleets f where f.player_id = v_pl2;
  update public.players set ducats = 50000000 where id in (v_pl, v_pl2);
  select array_agg(q.id order by q.code) into v_g
    from (select g.id, g.code from public.port_goods pg join public.goods g on g.id = pg.good_id
           where pg.port_id = v_lis and public.port_offers(v_lis, g.id) and g.bulk > 0 and g.bulk <= 2
             and not public.culture_refuses((select h.culture from public.ports h where h.id = v_lis), g.culture_mask)
           order by coalesce((select t.total from world.quote(v_lis, g.id, 1, 'buy', null, null) t), 0) desc, g.code limit 3) q;
  if v_fl is null or coalesce(array_length(v_g, 1), 0) < 3 then
    raise exception 'PROOF 208 FAIL: no fleet, or fewer than three goods on Lisbon''s quay';
  end if;
  update public.port_goods pg set stock = greatest(pg.stock_target, 400) where pg.port_id = v_lis and pg.good_id = any (v_g);
  perform cmd.assume_identity(c_a);

  -- ── DARK ── (rolled back alone: the day's row it writes must not stand under the lit steps)
  begin
    update public.world_config set value = to_jsonb(1) where key in ('haggle_base_success', 'haggle_success_max');
    select q.total into v_q0 from world.quote(v_lis, v_g[1], 10, 'buy', null, v_fl) q;
    v_r := cmd.haggle(v_fl, v_g[1], 'buy');
    select q.total into v_q1 from world.quote(v_lis, v_g[1], 10, 'buy', null, v_fl) q;
    perform cmd.haggle(v_fl, v_g[1], 'buy');
    perform cmd.haggle(v_fl, v_g[1], 'buy');
    if (v_r->>'attempts_max')::int <> 3 or cmd.haggle(v_fl, v_g[1], 'buy')->>'error_code' is distinct from 'E_HAGGLE_SPENT'
       or v_q1 > v_q0 or v_q1 < v_q0 * 0.98 or world.haggle_state(v_fl, v_g[1]) ? 'bargain' then
      raise exception 'PROOF 208 FAIL: dark is not the deployed rule: % -> % (%)', v_q0, v_q1, v_r;
    end if;
    raise exception using errcode = 'ZX208', message = format('%s -> %s', v_q0, v_q1);
  exception when sqlstate 'ZX208' then
    raise notice 'PASS: B10_DARK - three tries, the fourth refused; a win moved 10 units from % d. (a share of the spread, under 2 %%)', sqlerrm;
  end;

  -- ── LIT ──
  update public.world_config set value = 'true'::jsonb where key = 'bargain_total_enabled';
  for i in 0 .. 3 loop
    insert into public.haggle_daily (player_id, port_id, good_id, day, attempts, wins, concession, last_side)
    values (v_pl2, v_lis, v_g[3], public.real_day(now()), i, 0, 0, 'buy')
    on conflict (player_id, port_id, good_id, day) do update set attempts = excluded.attempts;
    v_arr := v_arr || to_jsonb(public.haggle_odds(v_pl2, v_lis, v_g[3], null));
  end loop;
  delete from public.haggle_daily where player_id = v_pl2;
  insert into public.level_xp (player_id, skill, xp) values (v_pl2, 'negotiation', public.level_begins('negotiation', 20)::int);
  v_x := public.bargain_p1(v_pl2, v_lis, v_g[3], null);
  update public.world_config set value = to_jsonb(0.45) where key = 'bargain_p1_base';
  if v_arr <> '[0.25, 0.125, 0.0625, 0.0313]'::jsonb or v_x <> 0.44 or public.bargain_p1(v_pl2, v_lis, v_g[3], null) <> 0.50 or public.haggle_attempts_max() <> 10 then
    raise exception 'PROOF 208 FAIL: the curve: % level 20 % capped %', v_arr, v_x, public.bargain_p1(v_pl2, v_lis, v_g[3], null);
  end if;
  raise notice 'PASS: B10_CURVE - ten tries; the chance %; Negotiation 20: p1 %; with a base of 0.45 still 0.50', v_arr, v_x;

  -- TEN LOST TRIES COST NOTHING
  update public.world_config set value = to_jsonb(0) where key in ('bargain_p1_base', 'bargain_p1_max');
  v_p0 := (select pl.ducats from public.players pl where pl.id = v_pl);
  v_c0 := public.treasury_balance(v_lis);
  select q.total into v_q0 from world.quote(v_lis, v_g[2], 10, 'buy', null, v_fl) q;
  for i in 1 .. 10 loop
    v_r := cmd.haggle(v_fl, v_g[2], 'buy');
    if (v_r->>'won')::boolean is not false then
      raise exception 'PROOF 208 FAIL: a try at chance 0 was won: %', v_r;
    end if;
  end loop;
  select q.total into v_q1 from world.quote(v_lis, v_g[2], 10, 'buy', null, v_fl) q;
  if v_q1 <> v_q0 or (select pl.ducats from public.players pl where pl.id = v_pl) <> v_p0 or public.treasury_balance(v_lis) <> v_c0
     or cmd.haggle(v_fl, v_g[2], 'buy')->>'error_code' is distinct from 'E_HAGGLE_SPENT' then
    raise exception 'PROOF 208 FAIL: lost tries cost something, or an eleventh was heard';
  end if;
  raise notice 'PASS: B10_FREE - ten lost tries: her purse %, her price % and Lisbon''s purse % as they were; the eleventh refused (E_HAGGLE_SPENT)', v_p0, v_q0, v_c0;

  -- A WIN IS 5 % OF HER TOTAL
  update public.world_config set value = to_jsonb(1) where key in ('bargain_p1_base', 'bargain_p1_max', 'bargain_decay');
  select q.total into v_q0 from world.quote(v_lis, v_g[1], 10, 'buy', null, v_fl) q;
  select q.total into v_oth from world.quote(v_lis, v_g[1], 10, 'buy', null, v_fl2) q;
  v_x := (select q.total from world.quote(v_lis, v_g[1], 10, 'buy', null, null) q);
  v_r := cmd.haggle(v_fl, v_g[1], 'buy');
  select q.total into v_q1 from world.quote(v_lis, v_g[1], 10, 'buy', null, v_fl) q;
  perform cmd.haggle(v_fl, v_g[1], 'buy');
  perform cmd.haggle(v_fl, v_g[1], 'buy');
  select q.total into v_q3 from world.quote(v_lis, v_g[1], 10, 'buy', null, v_fl) q;
  if (v_r->>'won')::boolean is not true or v_q1 not between floor(v_q0 * 0.95) - 1 and ceil(v_q0 * 0.95) or v_q3 not between floor(v_q0 * 0.85) - 1 and ceil(v_q0 * 0.85)
     or (select q.total from world.quote(v_lis, v_g[1], 10, 'buy', null, v_fl2) q) <> v_oth or (select q.total from world.quote(v_lis, v_g[1], 10, 'buy', null, null) q) <> v_x then
    raise exception 'PROOF 208 FAIL: a win is not 5 %% of her total alone: % -> % -> %', v_q0, v_q1, v_q3;
  end if;
  v_p0 := (select pl.ducats from public.players pl where pl.id = v_pl);
  v_c0 := public.treasury_balance(v_lis);
  v_paid := (cmd.do_buy(v_fl, jsonb_build_object('good', v_g[1], 'qty', 10))->>'total')::bigint;
  if v_paid <> v_q3 or v_p0 - (select pl.ducats from public.players pl where pl.id = v_pl) <> v_q3 or public.treasury_balance(v_lis) - v_c0 <> v_q3
     or public.haggle_concession(v_pl, v_lis, v_g[1]) <> 0 or public.bargain_factor(v_fl, v_lis, v_g[1], 'buy') <> 1 then
    raise exception 'PROOF 208 FAIL: the trade did not pay the quoted total to the city, or did not spend the bargain: paid % quoted %', v_paid, v_q3;
  end if;
  raise notice 'PASS: B10_WIN - 10 units: % d.; one win % (5 %%); three wins % (15 %%); another company still quoted %; she paid % and Lisbon''s purse rose by it; the bargain is spent',
    v_q0, v_q1, v_q3, v_oth, v_paid;

  -- THE RESALE GUARD
  v_r := cmd.haggle(v_fl, v_g[1], 'sell');
  v_got := (cmd.do_sell(v_fl, jsonb_build_object('good', v_g[1], 'qty', 10))->>'total')::bigint;
  if v_r->>'error_code' is distinct from 'E_BARGAIN_SIDE' or v_got > v_paid then
    raise exception 'PROOF 208 FAIL: the same-day resale: the other side % and % back for % paid', v_r->>'error_code', v_got, v_paid;
  end if;
  raise notice 'PASS: B10_RESALE - a bargain to sell it there the same day is refused (E_BARGAIN_SIDE); sold back, the 10 units paid % d. for the % d. they cost', v_got, v_paid;

  -- SELLING
  perform cmd.do_buy(v_fl, jsonb_build_object('good', v_g[3], 'qty', 10));
  select q.total into v_q0 from world.quote(v_lis, v_g[3], 10, 'sell', null, v_fl) q;
  perform cmd.haggle(v_fl, v_g[3], 'sell');
  perform cmd.haggle(v_fl, v_g[3], 'sell');
  select q.total into v_q1 from world.quote(v_lis, v_g[3], 10, 'sell', null, v_fl) q;
  -- a city that cannot pay it refuses the sale (her cargo stays); the purse does not go under nought
  update public.port_treasury set ducats = 1 where port_id = v_lis;
  begin
    perform cmd.do_sell(v_fl, jsonb_build_object('good', v_g[3], 'qty', 10));
    if public.treasury_balance(v_lis) < 0 then
      raise exception 'PROOF 208 FAIL: a bargained sale took a city''s purse under nought';
    end if;
    v_n := 0;   -- the sale was cut to what the purse could pay (0174): also no overdraft
  exception when others then
    if sqlerrm !~ '^E_CITY_BROKE' then raise; end if;
    v_n := 1;
  end;
  if public.treasury_balance(v_lis) < 0 then
    raise exception 'PROOF 208 FAIL: Lisbon''s purse is under nought';
  end if;
  raise notice 'PASS: B10_BROKE - with 1 d. in Lisbon''s purse the bargained sale %; the purse stands at %',
    case when v_n = 1 then 'was refused (E_CITY_BROKE)' else 'was cut to what the purse could pay' end, public.treasury_balance(v_lis);
  update public.port_treasury set ducats = 50000000 where port_id = v_lis;
  if public.fleet_cargo_qty(v_fl, (select g.code from public.goods g where g.id = v_g[3])) >= 10 and public.haggle_concession(v_pl, v_lis, v_g[3]) > 0 then
    v_c0 := public.treasury_balance(v_lis);
    select q.total into v_q1 from world.quote(v_lis, v_g[3], 10, 'sell', null, v_fl) q;
    v_got := (cmd.do_sell(v_fl, jsonb_build_object('good', v_g[3], 'qty', 10))->>'total')::bigint;
    if v_q1 not between floor(v_q0 * 1.10) and ceil(v_q0 * 1.10) + 1 or v_got <> v_q1 or v_c0 - public.treasury_balance(v_lis) not between v_got * 0.7 and v_got
       or public.bargain_factor(v_fl, v_lis, v_g[3], 'buy') <> 1.10 then
      raise exception 'PROOF 208 FAIL: a selling bargain: % -> %, got %, the purse fell %', v_q0, v_q1, v_got, v_c0 - public.treasury_balance(v_lis);
    end if;
    raise notice 'PASS: B10_SELL - 10 units sold: % d. plain, % with two wins (10 %%), paid by Lisbon''s purse (which took its profit tax back); buying them back there today costs 10 %% more', v_q0, v_got;
  else
    raise exception 'PROOF 208 FAIL: the refused sale spent her cargo or her bargain';
  end if;

  -- A STANDING JOB, set through the door
  delete from public.haggle_daily where player_id = v_pl;
  v_r := cmd.set_fleet_job(v_fl, 'best', '{}'::jsonb);
  if (v_r->>'ok')::boolean is not true then
    raise exception 'PROOF 208 FAIL: the job door refused a Best job: %', v_r;
  end if;
  v_arr := '[]'::jsonb;
  for i in 1 .. 4 loop
    insert into public.level_xp (player_id, skill, xp) values (v_pl, 'negotiation', public.level_begins('negotiation', (array[7, 16, 12, 8])[i])::int)
    on conflict (player_id, skill) do update set xp = excluded.xp;
    v_arr := v_arr || to_jsonb(public.job_bargain_tries(v_fl));
  end loop;
  update public.world_config set value = to_jsonb(0.25) where key = 'bargain_p1_base';
  update public.world_config set value = to_jsonb(0.5) where key in ('bargain_p1_max', 'bargain_decay');
  v_x := public.bargain_factor(v_fl, v_lis, v_g[2], 'buy');
  if v_arr <> '[0, 10, 6, 3]'::jsonb or abs(v_x - (1 - 0.05 * public.bargain_p1(v_pl, v_lis, v_g[2], v_fl) * 1.75)) > 0.000000001 or v_x <= 0.85 or v_x >= 1 then
    raise exception 'PROOF 208 FAIL: a job''s tries % or its expected factor %', v_arr, v_x;
  end if;
  -- THE DAY: four runs of 5 units, bought and sold at Lisbon (a sale side the job may bargain too), no other cost
  select q.total into v_q0 from world.quote(v_lis, v_g[2], 5, 'buy', null, v_fl) q;
  select q.total into v_q1 from world.quote(v_lis, v_g[2], 5, 'sell', null, v_fl) q;
  v_got := (public.run_day(v_pl, v_fl, v_lis, v_lis, v_g[2], 5, floor(public.wc_num('game_day_seconds') / 4), v_q0, v_q1, v_q1 - v_q0)->>'coin')::bigint;
  update public.world_config set value = 'false'::jsonb where key = 'bargain_total_enabled';
  select q.total into v_paid from world.quote(v_lis, v_g[2], 5, 'buy', null, v_fl) q;
  select q.total into v_p0 from world.quote(v_lis, v_g[2], 5, 'sell', null, v_fl) q;
  v_r := public.run_day(v_pl, v_fl, v_lis, v_lis, v_g[2], 5, floor(public.wc_num('game_day_seconds') / 4), v_paid, v_p0, v_p0 - v_paid);
  update public.world_config set value = 'true'::jsonb where key = 'bargain_total_enabled';
  if (v_r->>'runs')::int <> 4 or (v_got - (v_r->>'coin')::bigint)
       not between ((v_paid - v_q0) + (v_q1 - v_p0)) * 0.8 - 4 and ((v_paid - v_q0) + (v_q1 - v_p0)) * 1.05 + 4 then
    raise exception 'PROOF 208 FAIL: the day of % runs gained % by the bargain, one run %', v_r->'runs', v_got - (v_r->>'coin')::bigint, (v_paid - v_q0) + (v_q1 - v_p0);
  end if;
  raise notice 'PASS: B10_DAY - 4 runs a day: the expected bargain moves the day by % d. (one run''s: %), not four times it', v_got - (v_r->>'coin')::bigint, (v_paid - v_q0) + (v_q1 - v_p0);
  update public.world_config set value = to_jsonb(1) where key in ('bargain_p1_base', 'bargain_p1_max', 'bargain_decay');
  v_r := cmd.set_fleet_job(v_fl, 'best', '{"bargain": false}'::jsonb);
  if v_r #>> '{params,bargain}' is distinct from 'false' or public.job_bargain_tries(v_fl) <> 0 or public.bargain_factor(v_fl, v_lis, v_g[2], 'buy') <> 1 then
    raise exception 'PROOF 208 FAIL: the job setting off still bargains: %', v_r;
  end if;
  select q.total into v_q0 from world.quote(v_lis, v_g[2], 10, 'buy', null, v_fl) q;
  perform cmd.set_fleet_job(v_fl, 'best', '{}'::jsonb);
  v_ev := (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'HAGGLED');
  v_paid := (cmd.do_buy(v_fl, jsonb_build_object('good', v_g[2], 'qty', 10))->>'total')::bigint;
  select q.total into v_q1 from world.quote(v_lis, v_g[2], 10, 'buy', null, v_fl) q;
  if v_paid not between floor(v_q0 * 0.85) - 1 and ceil(v_q0 * 0.85)
     or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'HAGGLED') - v_ev <> 3
     or (select h.attempts from public.haggle_daily h where h.player_id = v_pl and h.good_id = v_g[2]) <> 3
     or (cmd.do_buy(v_fl, jsonb_build_object('good', v_g[2], 'qty', 10))->>'total')::bigint <> v_q1
     or (select h.attempts from public.haggle_daily h where h.player_id = v_pl and h.good_id = v_g[2]) <> 3
     or (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'negotiation') <> public.level_begins('negotiation', 8) then
    raise exception 'PROOF 208 FAIL: the job''s buy: plain % paid % then %', v_q0, v_paid, v_q1;
  end if;
  raise notice 'PASS: B10_JOB - tries at Negotiation 7 / 16 / 12 / 8: %; at 8 its quote is x % (expected; the best would be 0.85); its buy made 3 tries through cmd.haggle and paid % for % plain; a second buy that day made none; {"bargain": false} at the door: none',
    v_arr, round(v_x, 4), v_paid, v_q0;

  -- HER OWN TRIES ARE EXPERIENCE (the second company: its level row was never written by hand... it was, so a third reading: reset first)
  delete from public.level_xp where player_id = v_pl2;
  update public.world_config set value = 'true'::jsonb where key = 'level_skills_on';
  perform cmd.assume_identity(c_b);
  v_r := cmd.haggle(v_fl2, v_g[1], 'buy');
  update public.world_config set value = to_jsonb(0) where key in ('bargain_p1_base', 'bargain_p1_max');
  perform cmd.haggle(v_fl2, v_g[1], 'buy');
  if (select x.xp from public.level_xp x where x.player_id = v_pl2 and x.skill = 'negotiation') is distinct from 25
     or (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'negotiation') <> public.level_begins('negotiation', 8) then
    raise exception 'PROOF 208 FAIL: experience: hers %, the job''s company %', (select x.xp from public.level_xp x where x.player_id = v_pl2 and x.skill = 'negotiation'),
      (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'negotiation');
  end if;
  raise notice 'PASS: B10_LEVEL - a won try and a lost try of her own: 25 experience in Negotiation (5 + 15, then 5); the job''s three tries: none';
end
$p$;
