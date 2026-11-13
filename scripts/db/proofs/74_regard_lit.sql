-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 74 — A COMPANY STANDS WITH EACH COUNTRY, LIT  (migration 0373 lights regard_enabled; 0319 built it; 0360 / 0361 price a trip)
--
--   Proof 27 proves regard's rules in a world it lights itself. This proof does NOT set the switch: it reads it as the chain left it (0373), and asks the question the audit left
--   open: do the map's trip price (world.trip_cost, 0360) and Trade's board (world.good_board, 0361) carry the regard multiplier, and is that what the game then charges?
--   A probe company of Portugal, the closed economy, the city purses and the influence race on for this transaction (as on prod: world.tax_rate reads the stance only there).
--   "Dark" below is the same read with the switch set back for one statement.
--
-- @pass LIT_BY_0373        the chain left regard_enabled true, nobody holds earned regard, and 0373's news row is one row
-- @pass LIT_DAY_ONE        with no row written: at home Friendly and its factor, at war Wary and its factor, a free city and a merchant x1; the Town Hall's dues carry the line
-- @pass LIT_TRIP_FEES      world.trip_cost for Lisbon -> a harbour abroad -> Lisbon names, for each call, the dark dock fee times her factor there (to the ducat)
-- @pass LIT_TRIP_CHARGED   she sails that trip by the real commands, and each arrival charges exactly the dock fee the read named
-- @pass LIT_BOARD          Trade's board: for every sell row sailed in one leg, the dock fee is public.port_fee lit and the dark row's fee times her factor there; the row's tax is the dark tax scaled the same way
-- @pass LIT_GIFT_EARNS     a gift to her capital, through the real door, earns regard_per_100k a 100,000 d. with its holder: a row, an event, and the hall's score
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth constant uuid := '00000000-0373-4000-8000-0000000000aa';
  v_prt    uuid := (select n.id from public.nations n where n.code = 'PRT');
  v_lis    uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_pl     uuid;
  v_npc    uuid;
  v_fl     uuid;
  v_sh     uuid;
  v_war    uuid;
  v_free   uuid;
  v_near   record;
  v_out    jsonb;
  v_back   jsonb;
  v_lit    jsonb;
  v_dark   jsonb;
  v_r      jsonb;
  v_f_home numeric;
  v_f_near numeric;
  v_p1     bigint;
  v_p2     bigint;
  v_p3     bigint;
  v_p4     bigint;
  v_voy    record;
  v_ready  timestamptz;
  v_n      int;
  v_rows   int := 0;
  v_scaled int := 0;
  v_good   record;
  e        record;
  v_score0 numeric;
  v_gift   constant bigint := 100000;   -- a company gives a city at most this much a day
begin
  -- AS THE CHAIN LEFT IT
  if not public.regard_on() or (select c.value from public.world_config c where c.key = 'regard_enabled') is distinct from 'true'::jsonb
     or exists (select 1 from public.house_regard) or (select count(*) from public.world_news w where w.key = 'update:0373') <> 1 then
    raise exception 'PROOF 74 FAIL: the chain did not leave regard_enabled true, no earned regard and one news row of 0373';
  end if;
  raise notice 'PASS: LIT_BY_0373 — regard_enabled true, no earned regard, one news row "update:0373"';

  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled', 'influence_enabled');
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_auth, 'Casa da Prova 74', v_prt, 1000000, false) returning id into v_pl;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Mercador da Prova 74', v_prt, 1000000, true) returning id into v_npc;
  v_fl := public.form_fleet(v_pl, 'Prova', v_lis);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova', true, true);
  select s.id into v_sh from public.ships s where s.fleet_id = v_fl limit 1;
  update public.ships set crew = greatest(crew, 20), water_t = 0, food_t = 0 where id = v_sh;
  perform cmd.assume_identity(c_auth);

  -- ── DAY ONE ──
  select p.id into v_war from public.ports p where p.kind = 'HARBOUR' and public.power_stance(v_prt, public.port_nation(p.id)) = 'war' order by p.code limit 1;
  select p.id into v_free from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) is null order by p.code limit 1;
  v_f_home := public.regard_factor(v_pl, v_lis);
  v_r := public.port_dues(v_lis, v_pl, 100000);
  if v_war is null then
    raise exception 'PROOF 74 FAIL: this world has no harbour of a country at war with Portugal to read';
  end if;
  if v_f_home <> (public.regard_band(200) ->> 'factor')::numeric or public.regard_band(public.regard_of(v_pl, v_prt)) ->> 'band' <> 'friendly'
     or public.regard_factor(v_pl, v_war) <> (public.regard_band(-200) ->> 'factor')::numeric or public.regard_band(public.regard_of(v_pl, public.port_nation(v_war))) ->> 'band' <> 'wary'
     or (v_free is not null and public.regard_factor(v_pl, v_free) <> 1)
     or public.regard_factor(v_npc, v_lis) <> 1 or public.regard_factor(v_npc, v_war) <> 1
     or v_r -> 'dues' -> 'regard' ->> 'band' is distinct from 'friendly' or (v_r -> 'dues' -> 'regard' ->> 'factor')::numeric is distinct from v_f_home
     or (v_r -> 'dues' -> 'regard' ->> 'score')::numeric is distinct from 200 then
    raise exception 'PROOF 74 FAIL: day one: home x%, at war x%, the hall''s dues %', v_f_home, public.regard_factor(v_pl, v_war), v_r -> 'dues' -> 'regard';
  end if;
  raise notice 'PASS: LIT_DAY_ONE — at home Friendly x%, in % (at war) Wary x%, a free city and a merchant x1; Lisbon''s dues carry {score 200, band friendly, factor %}',
    v_f_home, (select p.code from public.ports p where p.id = v_war), public.regard_factor(v_pl, v_war), v_r -> 'dues' -> 'regard' ->> 'factor';

  -- ── THE TRIP'S DOCK FEES: Lisbon -> the nearest harbour abroad a day away -> Lisbon ──
  select r.port_id, r.code, r.nm into v_near
    from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id
   where p.kind = 'HARBOUR' and r.nm / greatest(voyage.fleet_speed(v_fl), 0.1) / 24 >= 1
     and voyage.leg_refusal(v_fl, r.port_id, r.nm, null) is null
     and public.port_nation(r.port_id) is distinct from v_prt
     and proof.course('LIS', r.code) is not null and proof.course(r.code, 'LIS') is not null
   order by (public.regard_factor(v_pl, r.port_id) <> 1) desc, r.nm limit 1;
  if v_near.port_id is null then
    raise exception 'PROOF 74 FAIL: no harbour abroad a day from Lisbon is open to the probe';
  end if;
  v_f_near := public.regard_factor(v_pl, v_near.port_id);
  v_out := proof.course('LIS', v_near.code);
  v_back := proof.course(v_near.code, 'LIS');
  v_lit := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code, 'course', v_out),
                                                   jsonb_build_object('from', v_near.code, 'to', 'LIS', 'course', v_back)));
  update public.world_config set value = 'false'::jsonb where key = 'regard_enabled';
  v_dark := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_near.code, 'course', v_out),
                                                    jsonb_build_object('from', v_near.code, 'to', 'LIS', 'course', v_back)));
  update public.world_config set value = 'true'::jsonb where key = 'regard_enabled';
  if (v_dark -> 'legs' -> 0 ->> 'dock_fee')::bigint <= 0 or (v_dark -> 'legs' -> 1 ->> 'dock_fee')::bigint <= 0
     or abs((v_lit -> 'legs' -> 0 ->> 'dock_fee')::numeric - (v_dark -> 'legs' -> 0 ->> 'dock_fee')::numeric * v_f_near) > 1
     or abs((v_lit -> 'legs' -> 1 ->> 'dock_fee')::numeric - (v_dark -> 'legs' -> 1 ->> 'dock_fee')::numeric * v_f_home) > 1
     or (v_lit -> 'legs' -> 1 ->> 'dock_fee')::bigint >= (v_dark -> 'legs' -> 1 ->> 'dock_fee')::bigint
     or (v_lit ->> 'dock_fee')::bigint <> (v_lit -> 'legs' -> 0 ->> 'dock_fee')::bigint + (v_lit -> 'legs' -> 1 ->> 'dock_fee')::bigint then
    raise exception 'PROOF 74 FAIL: the trip''s dock fees lit % against dark % with factors % at % and % at Lisbon', v_lit -> 'legs', v_dark -> 'legs', v_f_near, v_near.code, v_f_home;
  end if;
  raise notice 'PASS: LIT_TRIP_FEES — world.trip_cost: % (x%) dock fee % (dark %), Lisbon (x%) dock fee % (dark %)', v_near.code, v_f_near,
    v_lit -> 'legs' -> 0 ->> 'dock_fee', v_dark -> 'legs' -> 0 ->> 'dock_fee', v_f_home, v_lit -> 'legs' -> 1 ->> 'dock_fee', v_dark -> 'legs' -> 1 ->> 'dock_fee';

  -- ── THE SAME TRIP, SAILED: each arrival charges what the read named ──
  v_r := cmd.issue_lines(v_fl, jsonb_build_array(jsonb_build_object('text', 'SAIL ' || v_near.code, 'path', v_out),
                                                 jsonb_build_object('text', 'SAIL LIS', 'path', v_back)), null);
  if (v_r ->> 'ok')::boolean is not true or exists (select 1 from jsonb_array_elements(v_r -> 'orders') o where o ->> 'status' in ('failed', 'cancelled')) then
    raise exception 'PROOF 74 FAIL: the two SAILs were not queued: %', v_r;
  end if;
  select ducats into v_p1 from public.players where id = v_pl;
  for v_n in 1 .. 30 loop
    exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
    select v.id, v.eta into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
    perform voyage.settle(v_fl, v_voy.eta);
  end loop;
  if (select f.port_id from public.fleets f where f.id = v_fl) is distinct from v_near.port_id then
    raise exception 'PROOF 74 FAIL: she did not make %', v_near.code;
  end if;
  select ducats into v_p2 from public.players where id = v_pl;
  select f.ready_at into v_ready from public.fleets f where f.id = v_fl;
  perform public.port_time_wake(v_ready, clock_timestamp() + interval '20 seconds', v_fl);
  if (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
    raise exception 'PROOF 74 FAIL: the second SAIL did not leave %', v_near.code;
  end if;
  select ducats into v_p3 from public.players where id = v_pl;
  for v_n in 1 .. 30 loop
    exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
    select v.id, v.eta into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
    perform voyage.settle(v_fl, v_voy.eta);
  end loop;
  if (select f.port_id from public.fleets f where f.id = v_fl) is distinct from v_lis then
    raise exception 'PROOF 74 FAIL: she did not make Lisbon again';
  end if;
  select ducats into v_p4 from public.players where id = v_pl;
  if v_p1 - v_p2 <> (v_lit -> 'legs' -> 0 ->> 'dock_fee')::bigint or v_p3 - v_p4 <> (v_lit -> 'legs' -> 1 ->> 'dock_fee')::bigint then
    raise exception 'PROOF 74 FAIL: % charged % and Lisbon %, and the read named % and %', v_near.code, v_p1 - v_p2, v_p3 - v_p4,
      v_lit -> 'legs' -> 0 ->> 'dock_fee', v_lit -> 'legs' -> 1 ->> 'dock_fee';
  end if;
  raise notice 'PASS: LIT_TRIP_CHARGED — % charged % and Lisbon %: the dock fees the read named, each the dark fee times her factor', v_near.code, v_p1 - v_p2, v_p3 - v_p4;

  -- ── TRADE'S BOARD: every sell row sailed in one leg ──
  for v_good in select g.id, g.code from public.goods g order by g.code limit 12 loop
    update public.ships set cargo = jsonb_build_object(v_good.code, 5), cargo_basis = jsonb_build_object(v_good.code, 200) where id = v_sh;   -- written straight
    v_lit := world.good_board(v_good.id, v_fl, null, null) -> 'sell';
    update public.world_config set value = 'false'::jsonb where key = 'regard_enabled';
    v_dark := world.good_board(v_good.id, v_fl, null, null) -> 'sell';
    update public.world_config set value = 'true'::jsonb where key = 'regard_enabled';
    for e in select l.value as lit, d.value as dark, p.id as port_id, public.regard_factor(v_pl, p.id) as f
               from jsonb_array_elements(v_lit) l
               join jsonb_array_elements(v_dark) d on d.value ->> 'port' = l.value ->> 'port'
               join public.ports p on p.code = l.value ->> 'port' and p.kind = 'HARBOUR'
              where (l.value ->> 'quoted')::boolean and jsonb_array_length(coalesce(l.value -> 'stops', '[]'::jsonb)) = 0
                and jsonb_typeof(l.value -> 'dock_fee') = 'number' and jsonb_typeof(d.value -> 'dock_fee') = 'number' and l.value ->> 'port' <> 'LIS' loop
      v_rows := v_rows + 1;
      if abs((e.lit ->> 'dock_fee')::numeric - (e.dark ->> 'dock_fee')::numeric * e.f) > 1 then
        raise exception 'PROOF 74 FAIL: the board''s row for % at %: dock fee lit % against dark % with a factor of %', v_good.code, e.lit ->> 'port', e.lit ->> 'dock_fee', e.dark ->> 'dock_fee', e.f;
      end if;
      if e.f <> 1 then
        v_scaled := v_scaled + 1;
        if (e.dark ->> 'dock_fee')::numeric > 10 and (e.lit ->> 'dock_fee')::numeric = (e.dark ->> 'dock_fee')::numeric then
          raise exception 'PROOF 74 FAIL: the board''s row for % at % (factor %) names the dark dock fee %', v_good.code, e.lit ->> 'port', e.f, e.lit ->> 'dock_fee';
        end if;
        -- the tax: the rate she pays there is the dark rate times the factor, under the tariff's cap; a row's tax moves the same way
        if world.tax_rate(e.port_id, v_pl) > 0 and jsonb_typeof(e.lit -> 'profit_tax') = 'number' and (e.dark ->> 'profit_tax')::numeric > 20
           and sign((e.lit ->> 'profit_tax')::numeric - (e.dark ->> 'profit_tax')::numeric) not in (0, sign(e.f - 1)) then
          raise exception 'PROOF 74 FAIL: the board''s row for % at % (factor %): tax lit % against dark %', v_good.code, e.lit ->> 'port', e.f, e.lit ->> 'profit_tax', e.dark ->> 'profit_tax';
        end if;
      end if;
    end loop;
  end loop;
  if v_rows < 20 or v_scaled < 3 then
    raise exception 'PROOF 74 FAIL: the board gave only % one-leg sell row(s), % of them in a city where her factor is not 1', v_rows, v_scaled;
  end if;
  raise notice 'PASS: LIT_BOARD — % one-leg sell row(s) over 12 goods, % in a city where her factor is not 1: each dock fee is the dark row''s times her factor there (to the ducat), and no tax moved against it', v_rows, v_scaled;

  -- ── A GIFT EARNS ──
  v_score0 := public.regard_of(v_pl, v_prt);
  v_r := cmd.donate(v_lis, v_gift);
  if (v_r ->> 'ok')::boolean is not true
     or abs(public.regard_of(v_pl, v_prt) - v_score0 - v_gift / 100000.0 * public.wc_num('regard_per_100k')) > 0.01
     or (select count(*) from public.house_regard r where r.player_id = v_pl and r.nation_id = v_prt) <> 1
     or (select count(*) from public.events ev where ev.player_id = v_pl and ev.kind = 'REGARD_CHANGED') <> 1
     or (public.port_dues(v_lis, v_pl, 100000) -> 'dues' -> 'regard' ->> 'score')::numeric is distinct from round(public.regard_of(v_pl, v_prt)) then
    raise exception 'PROOF 74 FAIL: a gift of % at Lisbon: %, her regard % -> %', v_gift, v_r, v_score0, public.regard_of(v_pl, v_prt);
  end if;
  raise notice 'PASS: LIT_GIFT_EARNS — a gift of % at Lisbon through cmd.donate: regard with Portugal % -> %, one row, one event, the hall''s score follows', v_gift, round(v_score0), round(public.regard_of(v_pl, v_prt));
end
$$;
