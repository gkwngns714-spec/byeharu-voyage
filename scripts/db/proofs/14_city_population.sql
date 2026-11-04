-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 14 — A CITY'S PEOPLE GROW, HOLD OR SHRINK, AND PAY THEIR CITY A DAILY TAX  (migration 0304)
--
-- WHAT THIS PROOF IS FOR, AND WHY IT IS NOT THE MIGRATION'S SELF-ASSERT AGAIN
--   0304 proves in its own block the seed, the knobs, the rule on literals, the tax formula, the guard's one new exception and that
--   nothing else moved — without running a game step (docs/OPS_HEALTH.md section 4). This proof runs THE TICK itself,
--   public.population_tick, on the chain's world, with the economy closed and the purses lit (rolled back with proof.mjs's transaction):
--
--     1. THE TAX IS MINTED, AND THE BOOKS SAY SO. The first tick of a day pays every harbour public.city_population_income through
--        treasury_post, kind POPULATION_TAX: one flow each, exactly that sum; every purse moved by its own figure; the live Stats
--        'cities' figure moved by exactly the sum (money in = money posted). While the economy is closed, every other minted kind is
--        still refused after the tick, and the tick put its setting back to 'off'.
--     2. IDEMPOTENT. A second tick in the same 10-minute slot steps nothing and pays nothing; the next slot the same UTC day steps
--        every harbour and pays nothing; the next day pays again, once, at the CURRENT population.
--     3. THE STEP. Heavy investment GROWs (reason INVEST, x 1.0001 at score 1); a quiet harbour HOLDs (population unchanged, no
--        reason); empty staples SHRINK (reason FAMINE, x 0.9999); an enemy's influence SHRINKs (reason WAR); a harbour at its ceiling
--        HOLDs (reason CEILING), one at its floor HOLDs (reason FLOOR).
--     4. THE LOG is one row per harbour per step and is trimmed to population_log_slots; the hall serves the step and its reason.
--     5. OFF. population_step_base 0 holds every population; population_tax_per_1000 0 pays nothing.
--     6. THE COST: each tick over every harbour is timed and must stay under 5 s on this machine (printed).
--
-- Rows read are this proof's own (its harbours' flows by kind, its slots in 2030); nothing counts or sums a growing table beyond them.
--
-- @pass POP_TAX_MINTED      the first tick of a day posts one POPULATION_TAX flow per harbour, each its city_population_income, and each purse moved by it
-- @pass POP_BOOKS           the live Stats cities figure moved by exactly the tax: money in = money posted
-- @pass POP_GUARD           after the tick its setting is off and every other minted kind is still refused while closed
-- @pass POP_IDEMPOTENT      same slot: nothing stepped, nothing paid; next slot same day: every harbour stepped, nothing paid
-- @pass POP_STEP            invest GROWs (INVEST), quiet HOLDs, empty staples SHRINK (FAMINE), enemy influence SHRINKs (WAR), each by the rule
-- @pass POP_BOUNDS          at the ceiling the step HOLDs (CEILING), at the floor it HOLDs (FLOOR)
-- @pass POP_NEXT_DAY        the next day pays once more, at the CURRENT population
-- @pass POP_LOG             one log row per harbour per step; trimmed to population_log_slots; the hall serves kind, reason and the tax
-- @pass POP_OFF             step base 0 holds every population; tax 0 pays nothing
-- @pass POP_COST            every tick over all harbours took under 5 s
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_t0    constant timestamptz := '2030-01-01 00:03:00+00';
  v_n     int;
  v_h     int;
  v_r     jsonb;
  v_want  bigint;
  v_got   bigint;
  v_c0    bigint;
  v_c1    bigint;
  v_lon   uuid;
  v_ams   uuid;
  v_lis   uuid;
  v_war   uuid;
  v_enemy uuid;
  v_pl    uuid;
  v_p     numeric;
  v_bal   bigint;
  v_errm  text;
  v_ms    numeric := 0;
  v_hall  jsonb;
  r       record;
begin
  -- the world: closed and lit (rolled back with the proof); every harbour has a purse
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  insert into public.port_treasury (port_id) select id from public.ports where kind = 'HARBOUR' on conflict (port_id) do nothing;
  select count(*) into v_h from public.port_population;
  select id into v_lon from public.ports where code = 'LON';
  select id into v_ams from public.ports where code = 'AMS';
  select id into v_lis from public.ports where code = 'LIS';
  -- a held harbour whose holder is at war, and the enemy nation
  select a.port_id, case when r2.a = a.nation_id then r2.b else r2.a end into v_war, v_enemy
    from public.port_allegiance a join public.power_relations r2 on r2.stance = 'war' and a.nation_id in (r2.a, r2.b)
    join public.port_population pp on pp.port_id = a.port_id
   where a.port_id not in (v_lon, v_ams, v_lis) order by a.port_id limit 1;
  select id into v_pl from public.players order by id limit 1;
  if v_lon is null or v_ams is null or v_lis is null or v_war is null or v_enemy is null or v_pl is null or v_h <> (select count(*) from public.ports where kind = 'HARBOUR') then
    raise exception 'PROOF 14 setup: probe harbours, a war or a player missing (% % % % % %)', v_lon, v_ams, v_lis, v_war, v_enemy, v_pl;
  end if;
  -- the signals the probe controls: no investment, staples full, no influence, anywhere among the probe harbours
  update public.port_treasury set invested = 0 where port_id in (v_lon, v_ams, v_lis, v_war);
  update public.port_goods pg set stock = greatest(pg.stock, pg.stock_target)
    from public.goods g where g.id = pg.good_id and g.category in ('food', 'grain') and pg.port_id in (v_lon, v_ams, v_lis, v_war);
  delete from public.port_influence where port_id in (v_lon, v_ams, v_lis, v_war);

  -- ── 1. THE FIRST TICK OF THE DAY ──
  select coalesce(sum(public.city_population_income(port_id)), 0) into v_want from public.port_population;
  select coalesce((select cities from public.stats_live), 0) + coalesce((select sum(cities) from public.stats_live_deltas), 0) into v_c0;
  create temp table p14_bal on commit drop as select port_id, public.treasury_balance(port_id) as bal, public.city_population_income(port_id) as inc from public.port_population;
  v_r := public.population_tick(c_t0);
  v_ms := greatest(v_ms, (v_r->'ms'->>'total')::numeric);
  if (v_r->>'stepped')::int <> v_h or (v_r->>'paid')::int <> (select count(*) from p14_bal where inc > 0) or (v_r->>'tax')::bigint <> v_want then
    raise exception 'PROOF 14 FAIL: the first tick %, want % stepped, % paid, tax %', v_r, v_h, (select count(*) from p14_bal where inc > 0), v_want;
  end if;
  select count(*), coalesce(sum(ducats), 0) into v_n, v_got from public.treasury_flows where kind = 'POPULATION_TAX';
  if v_n <> (select count(*) from p14_bal where inc > 0) or v_got <> v_want
     or exists (select 1 from p14_bal b where public.treasury_balance(b.port_id) <> b.bal + b.inc)
     or exists (select 1 from p14_bal b where b.inc > 0 and (select count(*) from public.treasury_flows f where f.port_id = b.port_id and f.kind = 'POPULATION_TAX' and f.ducats = b.inc) <> 1) then
    raise exception 'PROOF 14 FAIL: % POPULATION_TAX flows summing %, want one per harbour summing %', v_n, v_got, v_want;
  end if;
  raise notice 'PASS: POP_TAX_MINTED — % harbours paid, % d. (London %)', v_n, v_got, (select inc from p14_bal where port_id = v_lon);
  select coalesce((select cities from public.stats_live), 0) + coalesce((select sum(cities) from public.stats_live_deltas), 0) into v_c1;
  if v_c1 - v_c0 <> v_want then
    raise exception 'PROOF 14 FAIL: the live cities figure moved by %, the tax is %', v_c1 - v_c0, v_want;
  end if;
  raise notice 'PASS: POP_BOOKS — live cities figure +% = tax % (ratio 1.0000)', v_c1 - v_c0, v_want;
  if coalesce(current_setting('byeharu.population_tax', true), '') <> 'off' then
    raise exception 'PROOF 14 FAIL: the tick left byeharu.population_tax %', current_setting('byeharu.population_tax', true);
  end if;
  for r in select kind from public.stats_flow_words where side = 'minted' loop
    begin
      perform public.treasury_post(v_lon, r.kind, 1, null, null);
      raise exception 'PROOF 14 FAIL: minted kind % was posted after the tick, the economy closed', r.kind;
    exception when others then
      get stacked diagnostics v_errm = message_text;
      if v_errm not like 'E_NO_NEW_GOLD:%' then raise; end if;
    end;
  end loop;
  raise notice 'PASS: POP_GUARD — setting off after the tick; every minted kind (POPULATION_TAX included) refused outside it';

  -- ── 2. IDEMPOTENT ──
  v_r := public.population_tick(c_t0 + interval '5 minutes');
  if (v_r->>'stepped')::int <> 0 or (v_r->>'paid')::int <> 0 or (select count(*) from public.treasury_flows where kind = 'POPULATION_TAX') <> v_n then
    raise exception 'PROOF 14 FAIL: a second tick in the slot did %', v_r;
  end if;
  v_r := public.population_tick(c_t0 + interval '10 minutes');
  v_ms := greatest(v_ms, (v_r->'ms'->>'total')::numeric);
  if (v_r->>'stepped')::int <> v_h or (v_r->>'paid')::int <> 0 or (select count(*) from public.treasury_flows where kind = 'POPULATION_TAX') <> v_n then
    raise exception 'PROOF 14 FAIL: the next slot the same day did %', v_r;
  end if;
  raise notice 'PASS: POP_IDEMPOTENT — same slot 0 stepped 0 paid; next slot % stepped 0 paid', v_h;

  -- ── 3. THE STEP ──
  update public.port_treasury set invested = 10000000000000 where port_id = v_lon;                       -- heavy investment: INVEST 1
  update public.port_goods pg set stock = 0
    from public.goods g where g.id = pg.good_id and g.category in ('food', 'grain') and pg.port_id = v_lis;   -- empty staples: FAMINE 1
  insert into public.port_influence (port_id, nation_id, player_id, points) values (v_war, v_enemy, v_pl, 1000);   -- all influence an enemy's: WAR 1
  create temp table p14_pop on commit drop as select port_id, population from public.port_population;
  v_r := public.population_tick(c_t0 + interval '20 minutes');
  v_ms := greatest(v_ms, (v_r->'ms'->>'total')::numeric);
  for r in select * from (values (v_lon, 'GROW', 'INVEST', 1.0001), (v_ams, 'HOLD', null, 1), (v_lis, 'SHRINK', 'FAMINE', 0.9999), (v_war, 'SHRINK', 'WAR', 0.9999))
             t(port, kind, reason, mult) loop
    select pp.population into v_p from public.port_population pp where pp.port_id = r.port;
    if (select kind from public.port_population where port_id = r.port) <> r.kind
       or (select reason from public.port_population where port_id = r.port) is distinct from r.reason
       or v_p <> round((select population from p14_pop where port_id = r.port) * r.mult, 3) then
      raise exception 'PROOF 14 FAIL: % stepped % (%) to %, want % (%) x %', (select code from public.ports where id = r.port),
        (select kind from public.port_population where port_id = r.port), (select reason from public.port_population where port_id = r.port), v_p, r.kind, r.reason, r.mult;
    end if;
  end loop;
  raise notice 'PASS: POP_STEP — London GROW (INVEST) %, Amsterdam HOLD, Lisbon SHRINK (FAMINE), % SHRINK (WAR)',
    (select population from public.port_population where port_id = v_lon), (select code from public.ports where id = v_war);

  -- ── 3b. THE BOUNDS ──
  update public.port_population set population = baseline * 2 where port_id = v_lon;
  update public.port_population set population = baseline * 0.5 where port_id = v_lis;
  v_r := public.population_tick(c_t0 + interval '30 minutes');
  if (select kind || '/' || reason || '/' || (population = baseline * 2)::text from public.port_population where port_id = v_lon) <> 'HOLD/CEILING/true'
     or (select kind || '/' || reason || '/' || (population = baseline * 0.5)::text from public.port_population where port_id = v_lis) <> 'HOLD/FLOOR/true' then
    raise exception 'PROOF 14 FAIL: the bounds: London %, Lisbon %',
      (select kind || '/' || coalesce(reason, '-') || '/' || population from public.port_population where port_id = v_lon),
      (select kind || '/' || coalesce(reason, '-') || '/' || population from public.port_population where port_id = v_lis);
  end if;
  raise notice 'PASS: POP_BOUNDS — London held at 2 x baseline (CEILING), Lisbon at 0.5 x (FLOOR)';

  -- ── 4. THE NEXT DAY, at the current population ──
  v_want := public.city_population_income(v_lon);
  if v_want <> round(4000 * power(800.0, 0.75))::bigint or v_want = (select inc from p14_bal where port_id = v_lon) then
    raise exception 'PROOF 14 FAIL: London''s tax at the ceiling is %', v_want;
  end if;
  v_bal := public.treasury_balance(v_lon);
  v_r := public.population_tick(c_t0 + interval '1 day');
  v_ms := greatest(v_ms, (v_r->'ms'->>'total')::numeric);
  if (v_r->>'paid')::int <> (select count(*) from p14_bal where inc > 0) or public.treasury_balance(v_lon) <> v_bal + v_want
     or (select count(*) from public.treasury_flows where kind = 'POPULATION_TAX') <> 2 * v_n then
    raise exception 'PROOF 14 FAIL: the next day did %, London % -> % (want +%)', v_r, v_bal, public.treasury_balance(v_lon), v_want;
  end if;
  v_r := public.population_tick(c_t0 + interval '1 day 10 minutes');
  if (v_r->>'paid')::int <> 0 then
    raise exception 'PROOF 14 FAIL: the next day paid twice: %', v_r;
  end if;
  raise notice 'PASS: POP_NEXT_DAY — paid % harbours again, London % (at 800,000 people, was %)', (select count(*) from p14_bal where inc > 0), v_want, (select inc from p14_bal where port_id = v_lon);

  -- ── 5. THE LOG and THE HALL ──
  -- six stepping ticks (t0, +10 m, +20 m, +30 m, +1 d, +1 d 10 m); each tick trims what is 144 slots back, so +1 d drops t0 and +1 d 10 m drops +10 m: four rows each
  if exists (select 1 from public.population_log group by port_id having count(*) <> 4) or (select count(distinct port_id) from public.population_log) <> v_h then
    raise exception 'PROOF 14 FAIL: the log is not four rows per harbour (six steps, the first two trimmed a day later)';
  end if;
  update public.world_config set value = to_jsonb(2) where key = 'population_log_slots';
  v_r := public.population_tick(c_t0 + interval '1 day 20 minutes');
  if exists (select 1 from public.population_log group by port_id having count(*) > 2) then
    raise exception 'PROOF 14 FAIL: the log was not trimmed to 2 slots (%)', v_r;
  end if;
  v_hall := world.town_hall(v_war) -> 'people';
  if v_hall ->> 'kind' <> 'SHRINK' or v_hall ->> 'reason' <> 'WAR' or (v_hall ->> 'per_day')::bigint <> public.city_population_income(v_war)
     or (v_hall ->> 'day_change')::bigint > 0 then
    raise exception 'PROOF 14 FAIL: the hall serves %', v_hall;
  end if;
  raise notice 'PASS: POP_LOG — 4 rows per harbour after 6 steps (a day kept), trimmed to 2; the hall serves %', v_hall;

  -- ── 6. OFF ──
  update public.world_config set value = to_jsonb(0) where key = 'population_step_base';
  delete from p14_pop;
  insert into p14_pop select port_id, population from public.port_population;
  v_r := public.population_tick(c_t0 + interval '1 day 30 minutes');
  if (v_r->>'grew')::int <> 0 or (v_r->>'shrank')::int <> 0
     or exists (select 1 from public.port_population pp join p14_pop p using (port_id) where pp.population <> p.population) then
    raise exception 'PROOF 14 FAIL: step base 0 still moved a population (%)', v_r;
  end if;
  update public.world_config set value = to_jsonb(0) where key = 'population_tax_per_1000';
  v_r := public.population_tick(c_t0 + interval '2 days');
  if (v_r->>'paid')::int <> 0 or (v_r->>'tax')::bigint <> 0 or (select count(*) from public.treasury_flows where kind = 'POPULATION_TAX') <> 2 * v_n then
    raise exception 'PROOF 14 FAIL: tax 0 still paid (%)', v_r;
  end if;
  raise notice 'PASS: POP_OFF — step base 0: no harbour moved; tax 0: nothing paid';

  if v_ms >= 5000 then
    raise exception 'PROOF 14 FAIL: a tick took % ms', v_ms;
  end if;
  raise notice 'PASS: POP_COST — the slowest tick over % harbours took % ms', v_h, v_ms;
end
$$;
