-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 27 — A HOUSE HAS A REGARD  (migration 0318, slice W1 of docs/WORLD_POWERS.md)
--
--   0318's own self-assert reads the catalog only: a migration never runs a real game step (docs/OPS_HEALTH.md section 4). This proof runs the REAL quote, dock fee, gift, stake and fine on
--   probe companies, all rolled back. The pre-images are the live bodies with 0318's hunks taken out again, so "dark equals pre-image" is measured, not taken on trust.
--
-- @pass REGARD_DARK_QUOTE   dark, every stance × tax, fee and dues: byte-identical to the pre-images, for a human and a merchant, with a planted row ignored
-- @pass REGARD_DARK_WRITES  dark, regard_add, a gift and a stake write no row and no event; the fine door refuses E_NOT_IN_USE and moves nothing
-- @pass REGARD_BANDS        lit, each of the five bands, on its two edges: the tax and the dock fee carry exactly that band's factor
-- @pass REGARD_STANCE_BASE  lit, with no row, the base alone: home, ally, peace, rival, war read 200, 100, 0, -100, -200
-- @pass REGARD_CAP          lit, a Hostile company at war still meets tariff_rate_max, and never a refusal: she docks and pays
-- @pass REGARD_DECAY        one half-life halves the points exactly, two quarter them, and regard_add folds the fade in before adding
-- @pass REGARD_MERCHANT     lit, a merchant: no row, no event, no line, multiplier 1 even with a row planted under her
-- @pass REGARD_GIFT         lit, a gift and a stake earn regard_per_100k with the holder, and nothing in a free city
-- @pass REGARD_FINE         lit, a fine: house down, capital up by the same coin; points back; a fine stops at what is owed; it never buys the stance base; no influence
-- @pass REGARD_FINE_DOORS   every refusal of the fine: not a capital, not docked, none owed, too little
-- @pass REGARD_NOT_MINTED   FINE is a moved kind, the gold of the whole act is unchanged to the ducat, and the mint guard passes it with the economy closed
-- @pass REGARD_HALL         the hall's line: absent dark and in a free city; lit, {score, band, factor, fine}, the fine at the capital only, and `factor` is the factor she really pays
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_lis uuid := (select id from public.ports where code = 'LIS');
  v_prt uuid := (select id from public.nations where code = 'PRT');
  v_a   uuid;      -- a probe human company of Portugal, a fleet docked at Lisbon
  v_m   uuid;      -- a probe merchant
  v_fl  uuid;
  v_r   jsonb;
  v_x   jsonb;
  v_n   bigint;
  v_b   numeric;
  v_c   numeric;
  v_d   numeric;
  v_ev0 bigint;
  v_free uuid;
  v_city uuid;     -- a harbour Portugal holds that is not its capital
  v_cap numeric;
  v_gold0 numeric;
  v_gold1 numeric;
  s     record;
  v_def text;
  v_fee bigint;
  c_hunks constant jsonb := jsonb_build_array(
    jsonb_build_array('world.tax_rate(uuid,uuid)', ' * public.regard_factor(p_player, p_port)', ''),
    jsonb_build_array('public.port_fee(uuid,uuid,numeric)', E'\n                           * public.regard_factor(p_player, p_port)', ''),
    jsonb_build_array('public.port_dues(uuid,uuid,numeric)', ' * public.regard_factor(p_player, p_port)', ''),
    jsonb_build_array('public.port_dues(uuid,uuid,numeric)', ' || public.regard_line(p_port, p_player)', ''));
begin
  -- the switches a closed world runs on; nothing here is regard's
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled', 'economy_closed');
  update public.world_config set value = '0'::jsonb where key = 'invest_min_ducats';   -- one share is the smallest probe stake
  if public.regard_on() then
    raise exception 'PROOF 27 FAIL: regard is not dark in this world';
  end if;

  -- ── THE PROBES ──
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Casa Regard 0f27', v_prt, 5000000, false) returning id into v_a;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Merchant Regard 0f27', v_prt, 5000000, true) returning id into v_m;
  v_fl := public.form_fleet(v_a, 'Probe 0f27', v_lis);
  if not exists (select 1 from public.fleets f where f.id = v_fl and f.status = 'DOCKED' and f.port_id = v_lis) then
    raise exception 'PROOF 27 FAIL: the probe fleet does not lie at Lisbon';
  end if;
  select pa.port_id into v_city from public.port_allegiance pa where pa.nation_id = v_prt and pa.port_id <> v_lis order by pa.port_id limit 1;
  select p.id into v_free from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) is null order by p.code limit 1;
  if v_city is null or v_free is null then
    raise exception 'PROOF 27 FAIL: this world has no second Portuguese harbour (%) or no free city (%)', v_city, v_free;
  end if;

  -- ── THE PRE-IMAGES: the live bodies, each with 0318's terms taken out ──
  for s in select distinct e ->> 0 as fn from jsonb_array_elements(c_hunks) e loop
    v_def := replace(pg_get_functiondef(s.fn::regprocedure), E'\r', '');
    declare e jsonb;
    begin
      for e in select x from jsonb_array_elements(c_hunks) x where x ->> 0 = s.fn loop
        if position(e ->> 1 in v_def) = 0 then
          raise exception 'PROOF 27 FAIL: % does not carry its 0318 term %', s.fn, e ->> 1;
        end if;
        v_def := replace(v_def, e ->> 1, e ->> 2);
      end loop;
    end;
    v_def := regexp_replace(v_def, 'CREATE OR REPLACE FUNCTION (world|public)\.(\w+)\(', 'CREATE OR REPLACE FUNCTION pg_temp.pre_\2(');
    execute v_def;
  end loop;

  -- ── DARK: every stance, three readers, human and merchant, with a planted row that must change nothing ──
  insert into public.house_regard (player_id, nation_id, points) select v_a, n.id, -9000 from public.nations n;
  insert into public.house_regard (player_id, nation_id, points) select v_m, n.id, -9000 from public.nations n;
  for s in select p.id as port, pl.id as who
             from (select distinct on (public.power_stance(v_prt, x.id2)) x.port_id as id, x.id2
                     from (select pa.port_id, pa.nation_id as id2 from public.port_allegiance pa) x order by public.power_stance(v_prt, x.id2), x.port_id) p
             cross join (values (v_a), (v_m)) pl(id) loop
    if world.tax_rate(s.port, s.who)::text is distinct from pg_temp.pre_tax_rate(s.port, s.who)::text
       or public.port_fee(s.port, s.who, 12345) is distinct from pg_temp.pre_port_fee(s.port, s.who, 12345)
       or public.port_dues(s.port, s.who, 12345)::text is distinct from pg_temp.pre_port_dues(s.port, s.who, 12345)::text then
      raise exception 'PROOF 27 FAIL: dark, a quote moved at % for %: tax % vs %, dues % vs %', s.port, s.who,
        world.tax_rate(s.port, s.who), pg_temp.pre_tax_rate(s.port, s.who), public.port_dues(s.port, s.who, 12345), pg_temp.pre_port_dues(s.port, s.who, 12345);
    end if;
  end loop;
  if world.tax_rate(v_lis, v_a) <> least(world.tax_rate(v_lis) * public.country_factor('home'), greatest(world.tax_rate(v_lis), public.wc_num('tariff_rate_max'))) then
    raise exception 'PROOF 27 FAIL: the dark quote is not the country factor''s';
  end if;
  raise notice 'PASS: REGARD_DARK_QUOTE — tax, fee and dues byte-identical to the pre-images over every stance, human and merchant, with -9000 planted';
  delete from public.house_regard;

  v_ev0 := (select count(*) from public.events e where e.player_id = v_a);
  v_n := (select count(*) from public.treasury_flows);
  if public.regard_add(v_a, v_prt, 50, 'PROBE') is not null then
    raise exception 'PROOF 27 FAIL: dark, regard_add answered';
  end if;
  perform public.donate_for(v_a, v_lis, 1000);
  perform public.invest_for(v_a, v_lis, 'docks', 1);
  if exists (select 1 from public.house_regard) or exists (select 1 from public.events e where e.player_id = v_a and e.kind = 'REGARD_CHANGED') then
    raise exception 'PROOF 27 FAIL: dark, a row or an event was written';
  end if;
  begin
    v_r := public.fine_for(v_a, v_lis, 1000);
    raise exception 'PROOF 27 FAIL: dark, the fine door answered %', v_r;
  exception when others then
    if sqlerrm !~ '^E_NOT_IN_USE:' then raise; end if;
  end;
  raise notice 'PASS: REGARD_DARK_WRITES — no row, no event, the door refuses E_NOT_IN_USE';

  -- ── LIT ──
  update public.world_config set value = 'true'::jsonb where key = 'regard_enabled';
  update public.players set ducats = 5000000 where id = v_a;
  delete from public.house_regard;

  -- the stance base alone, no row
  for s in select * from (values ('home', 200), ('ally', 100), ('peace', 0), ('rival', -100), ('war', -200)) t(stance, score) loop
    if not exists (select 1 from public.nations n where public.power_stance(v_prt, n.id) = s.stance) then
      raise exception 'PROOF 27 FAIL: no country stands % with Portugal in this world', s.stance;
    end if;
    if (select public.regard_of(v_a, n.id) from public.nations n where public.power_stance(v_prt, n.id) = s.stance limit 1) <> s.score then
      raise exception 'PROOF 27 FAIL: the base of % is not %', s.stance, s.score;
    end if;
  end loop;
  raise notice 'PASS: REGARD_STANCE_BASE — the stance base alone, read through regard_of';

  -- each band, on both its edges, on a peace-priced dock fee and an uncapped tax. Home's base is +200, so the points are the score - 200.
  update public.ports set tax_rate = 0.01 where id = v_lis;
  update public.port_mayor set tax_rate = null where port_id = v_lis;
  for s in select * from (values (500, 'honoured', 0.8::numeric), (100000, 'honoured', 0.8), (150, 'friendly', 0.9), (499, 'friendly', 0.9), (-149, 'neutral', 1), (149, 'neutral', 1),
                                 (-299, 'wary', 1.25), (-150, 'wary', 1.25), (-300, 'hostile', 2), (-100000, 'hostile', 2)) t(score, band, factor) loop
    insert into public.house_regard (player_id, nation_id, points, as_of) values (v_a, v_prt, s.score - 200, now())
    on conflict (player_id, nation_id) do update set points = excluded.points, as_of = excluded.as_of;
    if public.regard_of(v_a, v_prt) <> s.score then
      raise exception 'PROOF 27 FAIL: the probe reads % not %', public.regard_of(v_a, v_prt), s.score;
    end if;
    if public.regard_factor(v_a, v_lis) <> s.factor or public.regard_band(public.regard_of(v_a, v_prt)) ->> 'band' <> s.band then
      raise exception 'PROOF 27 FAIL: score % is band % factor %', s.score, public.regard_band(s.score), public.regard_factor(v_a, v_lis);
    end if;
    if world.tax_rate(v_lis, v_a) <> least(pg_temp.pre_tax_rate(v_lis, v_a) * s.factor, greatest(world.tax_rate(v_lis), public.wc_num('tariff_rate_max'))) then
      raise exception 'PROOF 27 FAIL: score %: tax % against the pre-image % × %', s.score, world.tax_rate(v_lis, v_a), pg_temp.pre_tax_rate(v_lis, v_a), s.factor;
    end if;
    if public.port_fee(v_lis, v_a, 1000000) <> greatest(0, round((public.wc_num('port_fee_base') + public.wc_num('port_fee_pct') * 1000000) * public.country_factor('home') * s.factor))::bigint then
      raise exception 'PROOF 27 FAIL: score %: fee % is not the factor''s', s.score, public.port_fee(v_lis, v_a, 1000000);
    end if;
  end loop;
  raise notice 'PASS: REGARD_BANDS — five bands on ten edges: tax and fee carry exactly the factor';

  -- the cap still stands, and a Hostile company at war still docks and pays
  v_cap := greatest(world.tax_rate(v_lis), public.wc_num('tariff_rate_max'));
  update public.ports set tax_rate = 0.05 where id = v_lis;
  update public.players set nation_id = (select n.id from public.nations n where public.power_stance(n.id, v_prt) = 'war' limit 1) where id = v_a;
  update public.house_regard set points = -1000, as_of = now() where player_id = v_a and nation_id = v_prt;
  if public.regard_band(public.regard_of(v_a, v_prt)) ->> 'band' <> 'hostile' then
    raise exception 'PROOF 27 FAIL: the probe is not Hostile';
  end if;
  v_cap := greatest(world.tax_rate(v_lis), public.wc_num('tariff_rate_max'));
  if world.tax_rate(v_lis, v_a) <> v_cap then
    raise exception 'PROOF 27 FAIL: a Hostile company at war pays % against the cap %', world.tax_rate(v_lis, v_a), v_cap;
  end if;
  v_fee := public.port_fee(v_lis, v_a, 0);
  if v_fee <> round(public.wc_num('port_fee_base') * public.country_factor('war') * 2)::bigint then
    raise exception 'PROOF 27 FAIL: a Hostile dock fee is %', v_fee;
  end if;
  v_r := public.port_call(v_fl, v_lis, v_a, now(), now(), null);
  if (v_r ->> 'fee')::bigint <> v_fee or (v_r ->> 'paid')::bigint <> v_fee then
    raise exception 'PROOF 27 FAIL: the port call of a Hostile company read %', v_r;
  end if;
  update public.players set nation_id = v_prt, ducats = 5000000 where id = v_a;
  update public.fleets set ready_at = null where id = v_fl;
  raise notice 'PASS: REGARD_CAP — tax at the cap %, dock fee doubled to %, she docked', v_cap, v_fee;

  -- ── THE FADE ──
  delete from public.house_regard;
  insert into public.house_regard (player_id, nation_id, points, as_of) values (v_a, v_prt, 400, now() - make_interval(hours => public.wc_int('regard_half_life_hours')));
  if public.regard_of(v_a, v_prt) - 200 <> 200 then
    raise exception 'PROOF 27 FAIL: one half-life leaves %', public.regard_of(v_a, v_prt) - 200;
  end if;
  update public.house_regard set as_of = now() - make_interval(hours => 2 * public.wc_int('regard_half_life_hours'));
  if public.regard_of(v_a, v_prt) - 200 <> 100 then
    raise exception 'PROOF 27 FAIL: two half-lives leave %', public.regard_of(v_a, v_prt) - 200;
  end if;
  update public.house_regard set as_of = now() - interval '200 years';
  if abs(public.regard_of(v_a, v_prt) - 200) > 0.000001 then
    raise exception 'PROOF 27 FAIL: a very old row reads %', public.regard_of(v_a, v_prt);
  end if;
  update public.house_regard set points = 400, as_of = now() + interval '30 days';
  if public.regard_of(v_a, v_prt) - 200 <> 400 then
    raise exception 'PROOF 27 FAIL: a row from the future grew to %', public.regard_of(v_a, v_prt) - 200;
  end if;
  update public.house_regard set as_of = now() - make_interval(hours => public.wc_int('regard_half_life_hours'));
  v_b := public.regard_add(v_a, v_prt, 30, 'PROBE');
  if v_b <> 200 + 230 or (select r.points from public.house_regard r where r.player_id = v_a and r.nation_id = v_prt) <> 230
     or (select r.as_of from public.house_regard r where r.player_id = v_a and r.nation_id = v_prt) <> now() then
    raise exception 'PROOF 27 FAIL: regard_add did not fold the fade in: %', v_b;
  end if;
  if not exists (select 1 from public.events e where e.player_id = v_a and e.kind = 'REGARD_CHANGED'
                  and e.payload ->> 'nation' = 'PRT' and (e.payload ->> 'delta')::numeric = 30 and e.payload ->> 'reason' = 'PROBE' and (e.payload ->> 'score')::numeric = 430 and e.payload ->> 'band' = 'friendly') then
    raise exception 'PROOF 27 FAIL: no REGARD_CHANGED event says what happened';
  end if;
  raise notice 'PASS: REGARD_DECAY — 400 to 200 to 100, a 200-year-old row reads nothing, a future row does not grow, and 200 + 30 = 230 stored at now()';

  -- ── A MERCHANT ──
  v_ev0 := (select count(*) from public.events e where e.player_id = v_m);
  if public.regard_add(v_m, v_prt, 50, 'PROBE') is not null or exists (select 1 from public.house_regard r where r.player_id = v_m) then
    raise exception 'PROOF 27 FAIL: a merchant has regard';
  end if;
  perform public.donate_for(v_m, v_lis, 1000);
  perform public.invest_for(v_m, v_city, 'docks', 1);
  if exists (select 1 from public.house_regard r where r.player_id = v_m)
     or exists (select 1 from public.events e where e.player_id = v_m and e.kind = 'REGARD_CHANGED') then
    raise exception 'PROOF 27 FAIL: a merchant''s gift wrote regard';
  end if;
  insert into public.house_regard (player_id, nation_id, points) values (v_m, v_prt, -9000);
  if public.regard_factor(v_m, v_lis) <> 1 or public.regard_line(v_lis, v_m) <> '{}'::jsonb
     or world.tax_rate(v_lis, v_m) <> pg_temp.pre_tax_rate(v_lis, v_m) or public.port_fee(v_lis, v_m, 1000) <> pg_temp.pre_port_fee(v_lis, v_m, 1000) then
    raise exception 'PROOF 27 FAIL: a merchant reads a row: factor %, line %', public.regard_factor(v_m, v_lis), public.regard_line(v_lis, v_m);
  end if;
  raise notice 'PASS: REGARD_MERCHANT — no row, no event, no line, multiplier 1 with -9000 planted under her';

  -- ── A GIFT AND A STAKE ──
  delete from public.house_regard where player_id = v_a;
  update public.players set ducats = 5000000 where id = v_a;
  update public.world_config set value = '1000000'::jsonb where key = 'influence_day_cap';
  perform public.donate_for(v_a, v_lis, 100000);
  if (select r.points from public.house_regard r where r.player_id = v_a and r.nation_id = v_prt) <> public.wc_num('regard_per_100k') then
    raise exception 'PROOF 27 FAIL: 100,000 d. given earned %', (select r.points from public.house_regard r where r.player_id = v_a);
  end if;
  v_b := (select r.points from public.house_regard r where r.player_id = v_a and r.nation_id = v_prt);
  v_r := public.invest_for(v_a, v_lis, 'docks', 1);
  if (select r.points from public.house_regard r where r.player_id = v_a and r.nation_id = v_prt) <> v_b + (v_r ->> 'cost')::numeric * public.wc_num('regard_per_100k') / 100000 then
    raise exception 'PROOF 27 FAIL: a stake of % earned the wrong regard', v_r ->> 'cost';
  end if;
  update public.house_regard set points = 0 where player_id = v_a;
  perform public.donate_for(v_a, v_free, 1000);
  if (select count(*) from public.house_regard r where r.player_id = v_a) <> 1 then
    raise exception 'PROOF 27 FAIL: a gift to a free city earned regard';
  end if;
  raise notice 'PASS: REGARD_GIFT — 100,000 d. earns the knob, a stake its share, a free city nothing';

  -- ── A FINE ──
  delete from public.house_regard where player_id = v_a;
  insert into public.house_regard (player_id, nation_id, points, as_of) values (v_a, v_prt, -1000, now());
  update public.players set ducats = 5000000 where id = v_a;
  if public.fine_owed(v_a, v_prt) <> 200000 then
    raise exception 'PROOF 27 FAIL: -1000 points owe %', public.fine_owed(v_a, v_prt);
  end if;
  select coalesce(sum(p.ducats), 0) into v_gold0 from public.players p;
  v_gold0 := v_gold0 + public.treasury_balance(v_lis);
  v_c := (select coalesce(sum(i.points), 0) from public.port_influence i where i.port_id = v_lis);
  v_d := public.treasury_balance(v_lis);
  v_r := public.fine_for(v_a, v_lis, 20000);
  if (v_r ->> 'amount')::bigint <> 20000 or (v_r ->> 'purse')::bigint <> 4980000 or (v_r ->> 'owed')::bigint <> 180000 or (v_r ->> 'score')::numeric <> -700 then
    raise exception 'PROOF 27 FAIL: the receipt reads %', v_r;
  end if;
  if (select pl.ducats from public.players pl where pl.id = v_a) <> 4980000 or public.treasury_balance(v_lis) <> v_d + 20000
     or (select r.points from public.house_regard r where r.player_id = v_a and r.nation_id = v_prt) <> -900 then
    raise exception 'PROOF 27 FAIL: the fine did not move: purse %, capital % from %', (select pl.ducats from public.players pl where pl.id = v_a), public.treasury_balance(v_lis), v_d;
  end if;
  if (select coalesce(sum(i.points), 0) from public.port_influence i where i.port_id = v_lis) <> v_c then
    raise exception 'PROOF 27 FAIL: a fine bought influence';
  end if;
  if not exists (select 1 from public.ledger l join public.events e on e.id = l.ref_event_id
                  where l.player_id = v_a and l.kind = 'FINE' and l.ducats_delta = -20000 and e.kind = 'FINE_PAID' and e.payload ->> 'nation' = 'PRT')
     or not exists (select 1 from public.treasury_flows f where f.port_id = v_lis and f.kind = 'FINE' and f.ducats = 20000 and f.player_id = v_a) then
    raise exception 'PROOF 27 FAIL: the ledger and the city''s book do not both say FINE';
  end if;
  -- it stops at what is owed, and the rest of her purse stays hers
  v_r := public.fine_for(v_a, v_lis, 4000000);
  if (v_r ->> 'amount')::bigint <> 180000 or (v_r ->> 'owed')::bigint <> 0 or (v_r ->> 'score')::numeric <> 200 then
    raise exception 'PROOF 27 FAIL: asked for 4,000,000 with 180,000 owed, the receipt reads %', v_r;
  end if;
  -- held to her purse
  update public.house_regard set points = -1000 where player_id = v_a;
  update public.players set ducats = 1000 where id = v_a;
  v_r := public.fine_for(v_a, v_lis, 200000);
  if (v_r ->> 'amount')::bigint <> 1000 or (select pl.ducats from public.players pl where pl.id = v_a) <> 0 then
    raise exception 'PROOF 27 FAIL: a fine is not held to her purse: %', v_r;
  end if;
  raise notice 'PASS: REGARD_FINE — 20,000 d. left the house and reached the capital, 100 points back; stopped at 180,000 owed; held to a purse of 1,000; no influence';

  -- the fine's refusals. Each one moves nothing.
  update public.players set ducats = 5000000 where id = v_a;
  update public.house_regard set points = -1000 where player_id = v_a;
  for s in select * from (values ('E_NOT_A_CAPITAL', v_city), ('E_NOT_A_CAPITAL', v_free), ('E_NOT_FOUND', '00000000-0000-0000-0000-00000000f027'::uuid)) t(code, port) loop
    begin
      v_r := public.fine_for(v_a, s.port, 20000);
      raise exception 'PROOF 27 FAIL: expected % and got %', s.code, v_r;
    exception when others then
      if sqlerrm !~ ('^' || s.code || ':') then raise; end if;
    end;
  end loop;
  begin   -- a real capital, where she has no fleet
    v_r := public.fine_for(v_a, (select p.id from public.ports p join public.nations n on n.capital_port_code = p.code where p.code <> 'LIS' and public.city_capital(p.id) = p.id order by p.code limit 1), 20000);
    raise exception 'PROOF 27 FAIL: expected E_NOT_DOCKED and got %', v_r;
  exception when others then
    if sqlerrm !~ '^E_NOT_DOCKED:' then raise; end if;
  end;
  begin
    v_r := public.fine_for(v_a, v_lis, 199);
    raise exception 'PROOF 27 FAIL: expected E_FINE_MIN and got %', v_r;
  exception when others then
    if sqlerrm !~ '^E_FINE_MIN:' then raise; end if;
  end;
  update public.house_regard set points = 50 where player_id = v_a;
  begin
    v_r := public.fine_for(v_a, v_lis, 20000);
    raise exception 'PROOF 27 FAIL: a good name paid a fine: %', v_r;
  exception when others then
    if sqlerrm !~ '^E_NO_FINE:' then raise; end if;
  end;
  delete from public.house_regard where player_id = v_a;
  begin
    v_r := public.fine_for(v_a, v_lis, 20000);
    raise exception 'PROOF 27 FAIL: a stance base was bought back: %', v_r;
  exception when others then
    if sqlerrm !~ '^E_NO_FINE:' then raise; end if;
  end;
  if (select pl.ducats from public.players pl where pl.id = v_a) <> 5000000 then
    raise exception 'PROOF 27 FAIL: a refusal moved money';
  end if;
  raise notice 'PASS: REGARD_FINE_DOORS — not a capital, a free city, no harbour, not docked, too little, none owed, a base';

  -- FINE is moved: the whole act, purse and city together, is unchanged to the ducat, with the economy closed
  insert into public.house_regard (player_id, nation_id, points, as_of) values (v_a, v_prt, -1000, now());
  select coalesce(sum(p.ducats), 0) + public.treasury_balance(v_lis) into v_gold0 from public.players p;
  v_n := (select count(*) from public.treasury_flows f where f.kind = 'FINE');
  perform public.fine_for(v_a, v_lis, 200000);
  select coalesce(sum(p.ducats), 0) + public.treasury_balance(v_lis) into v_gold1 from public.players p;
  if v_gold1 <> v_gold0 then
    raise exception 'PROOF 27 FAIL: a fine made % d.', v_gold1 - v_gold0;
  end if;
  if (select w.side from public.stats_flow_words w where w.kind = 'FINE') <> 'moved' then
    raise exception 'PROOF 27 FAIL: FINE is not moved';
  end if;
  if not public.economy_closed() or not public.city_treasury_on() then
    raise exception 'PROOF 27 FAIL: this was not the closed economy';
  end if;
  perform public.mint_guard('FINE', 1);
  raise notice 'PASS: REGARD_NOT_MINTED — 200,000 d. moved, every purse and the city summed move 0, with the economy closed';

  -- ── THE HALL'S LINE ──
  delete from public.house_regard where player_id = v_a;
  if public.regard_line(v_free, v_a) <> '{}'::jsonb then
    raise exception 'PROOF 27 FAIL: a free city serves a line: %', public.regard_line(v_free, v_a);
  end if;
  if public.port_dues(v_free, v_a, null) -> 'dues' ? 'regard' then
    raise exception 'PROOF 27 FAIL: a free city''s dues carry a regard';
  end if;
  insert into public.house_regard (player_id, nation_id, points, as_of) values (v_a, v_prt, -700, now());
  v_x := public.port_dues(v_lis, v_a, null) -> 'dues';
  if v_x -> 'regard' is distinct from jsonb_build_object('score', -500, 'band', 'hostile', 'factor', 2, 'fine', 140000) then
    raise exception 'PROOF 27 FAIL: the hall''s line at the capital reads %', v_x -> 'regard';
  end if;
  if (v_x ->> 'factor')::numeric <> public.country_factor('home') * 2 then
    raise exception 'PROOF 27 FAIL: dues.factor % is not the factor she pays', v_x ->> 'factor';
  end if;
  if (public.port_dues(v_city, v_a, null) -> 'dues' -> 'regard' ->> 'fine')::bigint <> 0 then
    raise exception 'PROOF 27 FAIL: a fine is offered away from the capital';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'regard_enabled';
  if public.port_dues(v_lis, v_a, null) -> 'dues' ? 'regard' then
    raise exception 'PROOF 27 FAIL: dark, the hall serves a line';
  end if;
  raise notice 'PASS: REGARD_HALL — absent dark and in a free city; the fine at the capital only; factor is 0.25 × 2';
end
$$;
