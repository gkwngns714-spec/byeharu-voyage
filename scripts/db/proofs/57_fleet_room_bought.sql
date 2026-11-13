-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 57 — ROOM IS BOUGHT, AND A FLEET READS ITS TOTALS  (migration 0354: F3 + F4 of docs/FLEETS_AND_SLOTS.md, and the rename door)
--
--   0354's own self-assert runs one small probe. This proof runs the REAL doors, caps, trigger and reads on probe companies and on every signed-in house of this world, all rolled back.
--   The pre-image of world.fleets() is the live body with 0354's two hunks taken out again, so "dark, nothing but the new key" is measured, not taken on trust.
--
-- @pass FLEETS_DARK_PARITY  for every signed-in house of this world and the probes: world.fleets() without `totals` is the pre-image's answer, to the byte; and it stays so lit
-- @pass TOTALS_ARE_SUMS     each fleet's totals are the sums of her ships' own reads (attack, hull, crew, bunks), the wage authority's figure, and the slowest ship by the speed authority; an empty fleet reads zeros
-- @pass ROOM_READ           world.house_room: dark it says so and offers nothing to buy that would work; lit, free + open rungs + bought steps is the ladder's figure for both kinds; a merchant and nobody read {company: false}
-- @pass BUY_DARK            dark, the door refuses E_NOT_IN_USE: no gold, no row, no event
-- @pass BUY_STEPS           lit, every price of both ladders in order: the purse falls by the knob price, one SLOT ledger row each, the cap rises by one, the caps trigger lets the new fleet and the new ship in
-- @pass BUY_IS_A_SINK       the gold reaches no purse: SLOT is a removed kind, no city book carries it, no other company's purse moved; a closed economy does not refuse it
-- @pass BUY_REFUSALS        short of gold with both figures, the top of each kind, every price used (by level), an unknown kind, a merchant, nobody: each refused whole
-- @pass RENAME              a fleet takes a new name docked, at sea and empty, dark and lit; her version stands; bad, taken, not hers and no such fleet are refused; one event a change
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_prt  uuid := (select id from public.nations where code = 'PRT');
  c_ua   constant uuid := '00000000-0057-4000-8000-00000000000a';
  c_ub   constant uuid := '00000000-0057-4000-8000-00000000000b';
  v_a    uuid;      -- a probe human company, rich
  v_b    uuid;      -- another, poor
  v_m    uuid;      -- a probe merchant
  v_f1   uuid;
  v_f2   uuid;
  v_f3   uuid;
  v_fb   uuid;
  v_s    uuid;
  v_def  text;
  v_r    jsonb;
  v_x    jsonb;
  v_old  jsonb;
  v_new  jsonb;
  v_n    bigint;
  v_gold bigint;
  v_cap  int;
  v_ver  int;
  v_others bigint;
  h      record;
  i      int;
begin
  if public.fleet_room_on() then
    raise exception 'PROOF 57 FAIL: the room is not dark in this world';
  end if;
  execute $f$
    create function pg_temp.as_house(p_uid uuid) returns void language sql as $b$
      select set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true),
             set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid)::text end, true);
    $b$
  $f$;

  -- ── THE PRE-IMAGE: the live world.fleets() with 0354's hunks taken out ──
  v_def := replace(pg_get_functiondef('world.fleets()'::regprocedure), E'\r', '');
  if position('public.fleet_totals(f.id, sv.ships)' in v_def) = 0 then
    raise exception 'PROOF 57 FAIL: world.fleets does not carry its hunk';
  end if;
  v_def := regexp_replace(v_def, E'    ''ships'', sv\\.ships,[^\n]*\n    ''totals'', public\\.fleet_totals\\(f\\.id, sv\\.ships\\),[^\n]*\n',
    E'    ''ships'', (select coalesce(jsonb_agg(world.ship_view(s.id) order by s.is_flagship desc, s.name), ''[]''::jsonb) from public.ships s where s.fleet_id = f.id),\n');
  v_def := regexp_replace(v_def, E'    from public\\.fleets f\n   cross join lateral \\(select coalesce\\(jsonb_agg\\(world\\.ship_view\\(s\\.id\\)[^\n]*\n[^\n]*\n[^\n]*\n[^\n]*offset 0\\) sv[^\n]*\n   where f\\.player_id = v_player\\);',
    E'    from public.fleets f where f.player_id = v_player);');
  if position('sv.ships' in v_def) > 0 or position('fleet_totals' in v_def) > 0 then
    raise exception 'PROOF 57 FAIL: the pre-image still carries 0354';
  end if;
  execute replace(replace(v_def, 'CREATE OR REPLACE FUNCTION world.fleets()', 'CREATE OR REPLACE FUNCTION pg_temp.pre_fleets()'), 'SECURITY DEFINER', '');

  -- ── THE PROBES ──
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_ua, 'Casa Rica 0f57', v_prt, 5000000, false) returning id into v_a;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_ub, 'Casa Pobre 0f57', v_prt, 70000, false) returning id into v_b;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Merchant 0f57', v_prt, 5000000, true) returning id into v_m;
  v_f1 := public.form_fleet(v_a, 'First 0f57', v_lis);
  v_f2 := public.form_fleet(v_a, 'Second 0f57', v_lis);
  v_fb := public.form_fleet(v_b, 'Other 0f57', v_lis);
  perform public.commission_ship(v_a, v_f1, 'barca', 'Uno 0f57', true, true);
  perform public.commission_ship(v_a, v_f1, 'nau', 'Dos 0f57', false, false);     -- no hands aboard: short of crew
  perform public.commission_ship(v_a, v_f2, 'barca', 'Tres 0f57', true, true);
  perform public.commission_ship(v_b, v_fb, 'barca', 'Otra 0f57', true, true);

  -- ── FLEETS_DARK_PARITY ── every signed-in house: the old read first (it settles what has landed), then the new one, in one statement clock
  v_n := 0;
  for h in select p.id, p.auth_uid from public.players p where p.auth_uid is not null order by p.created_at, p.id loop
    perform pg_temp.as_house(h.auth_uid);
    v_old := pg_temp.pre_fleets();
    v_new := world.fleets();
    if (select coalesce(jsonb_agg(e.value - 'totals' order by e.ord), '[]'::jsonb) from jsonb_array_elements(v_new) with ordinality e(value, ord)) is distinct from v_old then
      raise exception 'PROOF 57 FAIL: dark, world.fleets() without totals is not the pre-image for house %', h.id;
    end if;
    if exists (select 1 from jsonb_array_elements(v_new) e where jsonb_typeof(e.value -> 'totals') is distinct from 'object') then
      raise exception 'PROOF 57 FAIL: a fleet of house % carries no totals', h.id;
    end if;
    v_n := v_n + jsonb_array_length(v_new);
  end loop;
  if v_n < 3 then
    raise exception 'PROOF 57 FAIL: the parity loop read only % fleet(s)', v_n;
  end if;
  raise notice 'PASS: FLEETS_DARK_PARITY — % fleets of every signed-in house: the pre-image to the byte, plus totals (lit is checked below)', v_n;

  -- ── TOTALS_ARE_SUMS ──
  perform pg_temp.as_house(c_ua);
  v_new := world.fleets();
  for h in select f.id, f.name, e.value -> 'totals' as t
             from public.fleets f join jsonb_array_elements(v_new) e on (e.value ->> 'id')::uuid = f.id where f.player_id = v_a loop
    select jsonb_build_object(
             'ships', count(*)::int,
             'attack', coalesce(sum(world.ship_stat(s.id, 'attack')), 0),
             'hull', coalesce(sum(s.durability), 0),
             'hull_max', coalesce(sum((world.ship_view(s.id) ->> 'max_durability')::numeric), 0),
             'crew', coalesce(sum(s.crew), 0),
             'crew_required', coalesce(sum(c.crew_required), 0),
             'crew_max', coalesce(sum((world.ship_view(s.id) ->> 'crew_max')::numeric), 0),
             'short_crew', coalesce(jsonb_agg(s.name order by s.name) filter (where s.crew < c.crew_required), '[]'::jsonb),
             'wages_day', public.fleet_wage(h.id, false),
             'slowest', (select jsonb_build_object('id', y.id, 'name', y.name, 'speed', voyage.ship_speed(y.id))
                           from public.ships y where y.fleet_id = h.id order by voyage.ship_speed(y.id), y.name limit 1))
      into v_x
      from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = h.id;
    if h.t is distinct from v_x then
      raise exception 'PROOF 57 FAIL: the totals of % are not the sums of her ships: % against %', h.name, h.t, v_x;
    end if;
  end loop;
  select e.value -> 'totals' into v_x from jsonb_array_elements(v_new) e where (e.value ->> 'id')::uuid = v_f1;
  if (v_x ->> 'ships')::int <> 2 or v_x -> 'short_crew' <> '["Dos 0f57"]'::jsonb or (v_x ->> 'attack')::numeric <= 0 or (v_x ->> 'hull_max')::numeric < (v_x ->> 'hull')::numeric
     or (v_x ->> 'wages_day')::numeric <= 0 or (v_x -> 'slowest' ->> 'speed')::numeric <= 0 then
    raise exception 'PROOF 57 FAIL: the first fleet''s totals are empty or wrong: %', v_x;
  end if;
  raise notice 'PASS: TOTALS_ARE_SUMS — the ship reads, the wage authority, the speed authority (an empty fleet is checked below)';

  -- ── ROOM_READ, dark ── ── BUY_DARK ──
  v_r := world.house_room();
  if (v_r ->> 'on')::boolean or not (v_r ->> 'company')::boolean or (v_r ->> 'purse')::bigint <> 5000000
     or (v_r -> 'fleets' ->> 'have')::int <> (public.earned_caps(v_a) ->> 'fleet_max')::int or (v_r -> 'ships' ->> 'have')::int <> (public.earned_caps(v_a) ->> 'fleet_ship_max')::int
     or (v_r -> 'fleets' ->> 'used')::int <> 2 or (v_r -> 'ships' ->> 'used')::int <> 2 or (v_r -> 'hulls' ->> 'used')::int <> 3 or (v_r -> 'hulls' ->> 'have')::int <> public.house_ship_max(v_a) then
    raise exception 'PROOF 57 FAIL: dark, the room read is wrong: %', v_r;
  end if;
  select count(*) into v_n from public.events e where e.player_id = v_a;
  v_r := cmd.buy_room('FLEET');
  v_x := cmd.buy_room('SHIP');
  if v_r ->> 'error_code' is distinct from 'E_NOT_IN_USE' or v_x ->> 'error_code' is distinct from 'E_NOT_IN_USE'
     or (select ducats from public.players where id = v_a) <> 5000000 or exists (select 1 from public.house_room)
     or exists (select 1 from public.ledger l where l.player_id = v_a) or (select count(*) from public.events e where e.player_id = v_a) <> v_n then
    raise exception 'PROOF 57 FAIL: dark, the buying door is not shut: % %', v_r, v_x;
  end if;
  raise notice 'PASS: BUY_DARK — E_NOT_IN_USE, no gold, no row, no event';

  -- a rename, dark, docked
  select version into v_ver from public.fleets where id = v_f1;
  v_r := cmd.rename_fleet(v_f1, '  Primeira 0f57  ');
  if not (v_r ->> 'ok')::boolean or (select name from public.fleets where id = v_f1) <> 'Primeira 0f57' or (select version from public.fleets where id = v_f1) <> v_ver then
    raise exception 'PROOF 57 FAIL: dark, a docked fleet did not take her name, or her version moved: %', v_r;
  end if;

  -- ── LIT ──
  update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite';
  v_old := pg_temp.pre_fleets();
  v_new := world.fleets();
  if (select jsonb_agg(e.value - 'totals' order by e.ord) from jsonb_array_elements(v_new) with ordinality e(value, ord)) is distinct from v_old then
    raise exception 'PROOF 57 FAIL: lit, world.fleets() without totals is not the pre-image';
  end if;

  -- ROOM_READ, lit: the rows add up to the ladder, with rungs and bought steps planted
  update public.world_config set value = '[1, 99]'::jsonb where key = 'fleet_room_levels';   -- every company is at Trading 1 or more: one rung reached, one not
  insert into public.player_skills (player_id, skill_id, level) select v_a, k.id, 2 from public.skills k where k.code = 'COMMAND';
  insert into public.house_room (player_id, kind, steps) values (v_a, 'FLEET', 1), (v_a, 'SHIP', 2);
  v_r := world.house_room();
  for h in select * from (values ('fleets', 'fleet_max'), ('ships', 'fleet_ship_max')) t(k, cap) loop
    if (v_r -> h.k ->> 'ladder')::int <> (public.fleet_room_caps(v_a) ->> h.cap)::int or (v_r -> h.k ->> 'have')::int <> (public.earned_caps(v_a) ->> h.cap)::int
       or least((v_r -> h.k ->> 'top')::int,
                (v_r -> h.k ->> 'free')::int + (select count(*) from jsonb_array_elements(v_r -> h.k -> 'steps') s where (s.value ->> 'open')::boolean))
          <> (v_r -> h.k ->> 'ladder')::int
       or (select count(*) from jsonb_array_elements(v_r -> h.k -> 'steps') s where (s.value ->> 'next')::boolean) <> 1
       or (select (s.value ->> 'price')::bigint from jsonb_array_elements(v_r -> h.k -> 'steps') s where (s.value ->> 'next')::boolean) is distinct from (v_r -> h.k ->> 'price')::bigint then
      raise exception 'PROOF 57 FAIL: lit, the % rows do not add up to the ladder: %', h.k, v_r -> h.k;
    end if;
  end loop;
  if (v_r -> 'fleets' ->> 'ladder')::int <> 4 or (v_r -> 'ships' ->> 'ladder')::int <> 6 or (v_r -> 'fleets' ->> 'price')::bigint <> 1000000 or (v_r -> 'ships' ->> 'price')::bigint <> 40000
     or (v_r -> 'hulls' ->> 'have')::int <> 24
     or (select count(*) from jsonb_array_elements(v_r -> 'ships' -> 'steps') s where s.value ->> 'how' = 'level' and s.value -> 'tracks' = '["seamanship", "command"]'::jsonb) <> 5
     or (select string_agg(s.value ->> 'level', ',' order by s.ord) from jsonb_array_elements(v_r -> 'fleets' -> 'steps') with ordinality s(value, ord) where s.value ->> 'how' = 'level') <> '1,99' then
    raise exception 'PROOF 57 FAIL: lit, a rung and bought steps planted do not read 4 fleets of 6: %', v_r;
  end if;
  delete from public.house_room where player_id = v_a;
  delete from public.player_skills where player_id = v_a;
  update public.world_config set value = '[3, 6]'::jsonb where key = 'fleet_room_levels';
  perform pg_temp.as_house(null);
  if world.house_room() <> jsonb_build_object('company', false, 'on', true) then
    raise exception 'PROOF 57 FAIL: nobody signed in reads a room: %', world.house_room();
  end if;
  perform pg_temp.as_house(c_ua);
  raise notice 'PASS: ROOM_READ — dark it says so; lit, free + open rungs + bought is the ladder for both kinds; nobody reads none';

  -- ── BUY_STEPS ── a new company: 2 fleets of 2. A third fleet and a third ship are refused by the trigger first.
  begin
    perform public.form_fleet(v_a, 'Third 0f57', v_lis);
    raise exception 'PROOF 57 FAIL: lit, a third fleet formed with no room bought';
  exception when others then
    if sqlerrm not like 'E_FLEET_MAX%' then raise; end if;
  end;
  select coalesce(sum(p.ducats), 0) into v_others from public.players p where p.id <> v_a;
  select count(*) into v_n from public.treasury_flows;
  v_gold := 5000000;
  -- with the economy closed and the city purses lit, as on prod: a payment is not a mint, so nothing refuses it
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  for h in select * from (values ('FLEET', 'fleet_room_prices', 'fleet_max'), ('SHIP', 'ship_room_prices', 'fleet_ship_max')) t(kind, knob, cap) loop
    for i in 0 .. jsonb_array_length(public.wc(h.knob)) - 1 loop
      v_cap := (public.earned_caps(v_a) ->> h.cap)::int;
      v_r := cmd.buy_room(h.kind);
      v_gold := v_gold - (public.wc(h.knob) ->> i)::bigint;
      if not coalesce((v_r ->> 'ok')::boolean, false) or (v_r ->> 'step')::int <> i + 1 or (v_r ->> 'price')::bigint <> (public.wc(h.knob) ->> i)::bigint
         or (v_r ->> 'purse')::bigint <> v_gold or (select ducats from public.players where id = v_a) <> v_gold
         or (public.earned_caps(v_a) ->> h.cap)::int <> v_cap + 1 or (v_r ->> h.cap)::int <> v_cap + 1
         or (select count(*) from public.ledger l where l.player_id = v_a and l.kind = 'SLOT' and l.ducats_delta = -(public.wc(h.knob) ->> i)::bigint and l.balance_after = v_gold
                and l.ref_event_id = (select e.id from public.events e where e.player_id = v_a and e.kind = 'ROOM_OPENED'
                                         and e.payload = jsonb_build_object('kind', h.kind, 'step', i + 1, 'price', (public.wc(h.knob) ->> i)::bigint, 'room', v_cap + 1))) <> 1 then
        raise exception 'PROOF 57 FAIL: lit, % step % did not cost the knob price, book one SLOT row under its event and raise the cap by one: %', h.kind, i + 1, v_r;
      end if;
    end loop;
  end loop;
  update public.world_config set value = 'false'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  if (public.earned_caps(v_a) ->> 'fleet_max')::int <> 4 or (public.earned_caps(v_a) ->> 'fleet_ship_max')::int <> 7 or public.house_ship_max(v_a) <> 28
     or (select count(*) from public.ledger l where l.player_id = v_a) <> 7 or v_gold <> 5000000 - 1060000 - 310000
     or (select string_agg(x.kind || x.steps, ',' order by x.kind) from public.house_room x where x.player_id = v_a) <> 'FLEET2,SHIP5' then
    raise exception 'PROOF 57 FAIL: lit, every price bought does not leave 4 fleets of 7 for 1,370,000: % purse %', public.earned_caps(v_a), v_gold;
  end if;
  -- the trigger reads what was bought: the third fleet forms, and the first fleet takes ships up to seven
  v_f3 := public.form_fleet(v_a, 'Third 0f57', v_lis);
  for i in 3 .. 7 loop
    perform public.commission_ship(v_a, v_f1, 'barca', 'Mais ' || i || ' 0f57', false, true);
  end loop;
  begin
    perform public.commission_ship(v_a, v_f1, 'barca', 'Oito 0f57', false, true);
    raise exception 'PROOF 57 FAIL: lit, an eighth ship joined a fleet';
  exception when others then
    if sqlerrm not like 'E_FLEET_SHIP_MAX%' then raise; end if;
  end;
  raise notice 'PASS: BUY_STEPS — 2 + 5 prices in order, each one SLOT row under its event, each cap +1, the trigger lets the room be used; the closed economy does not refuse';

  -- ── BUY_IS_A_SINK ──
  if (select w.side from public.stats_flow_words w where w.kind = 'SLOT') <> 'removed'
     or (select coalesce(sum(p.ducats), 0) from public.players p where p.id <> v_a) <> v_others
     or (select count(*) from public.treasury_flows) <> v_n
     or exists (select 1 from public.ledger l where l.kind = 'SLOT' and l.player_id <> v_a)
     or (select r.removed from public.stats_sides(jsonb_build_object('SLOT', -1370000)) r) <> 1370000 then
    raise exception 'PROOF 57 FAIL: the gold paid for room reached a purse, or is not counted as removed';
  end if;
  raise notice 'PASS: BUY_IS_A_SINK — removed: no company, no city book, and Stats counts it as removed';

  -- ── BUY_REFUSALS ──
  -- every price used and one fleet still to open: by level
  select count(*) into v_n from public.events e where e.player_id = v_a;
  v_r := cmd.buy_room('FLEET');
  if v_r ->> 'error_code' is distinct from 'E_ROOM_BY_LEVEL' then
    raise exception 'PROOF 57 FAIL: every fleet price used: %', v_r;
  end if;
  v_r := cmd.buy_room('SHIP');
  if v_r ->> 'error_code' is distinct from 'E_ROOM_TOP' then
    raise exception 'PROOF 57 FAIL: seven ships a fleet: %', v_r;
  end if;
  update public.world_config set value = '[1, 99]'::jsonb where key = 'fleet_room_levels';   -- a rung reached: 2 + 1 + 2 = 5, the top
  v_r := cmd.buy_room('FLEET');
  if v_r ->> 'error_code' is distinct from 'E_ROOM_TOP' or (public.earned_caps(v_a) ->> 'fleet_max')::int <> public.wc_int('fleet_hard_max') then
    raise exception 'PROOF 57 FAIL: five fleets: %', v_r;
  end if;
  update public.world_config set value = '[3, 6]'::jsonb where key = 'fleet_room_levels';
  v_r := cmd.buy_room('CABIN');
  v_x := cmd.buy_room(null);
  if v_r ->> 'error_code' is distinct from 'E_PARSE' or v_x ->> 'error_code' is distinct from 'E_PARSE' then
    raise exception 'PROOF 57 FAIL: an unknown kind: % %', v_r, v_x;
  end if;
  if (select ducats from public.players where id = v_a) <> v_gold or (select count(*) from public.events e where e.player_id = v_a) <> v_n
     or (select count(*) from public.ledger l where l.player_id = v_a) <> 7 then
    raise exception 'PROOF 57 FAIL: a refusal moved gold or wrote a row';
  end if;
  -- short of gold: 70,000 buys the first fleet step (60,000), then 10,000 buys one ship step, then nothing is left for the next
  perform pg_temp.as_house(c_ub);
  if not (cmd.buy_room('FLEET') ->> 'ok')::boolean or not (cmd.buy_room('SHIP') ->> 'ok')::boolean then
    raise exception 'PROOF 57 FAIL: the poor house could not buy what she can pay for';
  end if;
  v_r := cmd.buy_room('SHIP');
  if v_r ->> 'error_code' is distinct from 'E_INSUFFICIENT_FUNDS' or (v_r -> 'figures' ->> 'have')::numeric <> 0 or (v_r -> 'figures' ->> 'need')::numeric <> 20000
     or v_r -> 'figures' ->> 'unit' <> 'ducats' or (select ducats from public.players where id = v_b) <> 0
     or (select h2.steps from public.house_room h2 where h2.player_id = v_b and h2.kind = 'SHIP') <> 1 or (select count(*) from public.ledger l where l.player_id = v_b) <> 2 then
    raise exception 'PROOF 57 FAIL: short of gold: %', v_r;
  end if;
  v_r := world.house_room();
  if (v_r -> 'ships' ->> 'price')::bigint <> 20000
     or (select (s.value ->> 'can_pay')::boolean from jsonb_array_elements(v_r -> 'ships' -> 'steps') s where (s.value ->> 'next')::boolean) is not false then
    raise exception 'PROOF 57 FAIL: the read does not say she cannot pay the next step: %', v_r -> 'ships';
  end if;
  begin
    perform public.buy_room_for(v_m, 'FLEET');
    raise exception 'PROOF 57 FAIL: a merchant bought room';
  exception when others then
    if sqlerrm not like 'E_NOT_IN_USE%' then raise; end if;
  end;
  perform pg_temp.as_house(null);
  if cmd.buy_room('FLEET') ->> 'error_code' is distinct from 'E_NO_HOUSE' or cmd.rename_fleet(v_f1, 'Ninguem 0f57') ->> 'error_code' is distinct from 'E_NO_HOUSE' then
    raise exception 'PROOF 57 FAIL: nobody signed in passed a door';
  end if;
  if (select ducats from public.players where id = v_m) <> 5000000 or exists (select 1 from public.house_room x where x.player_id = v_m) then
    raise exception 'PROOF 57 FAIL: the merchant paid';
  end if;
  raise notice 'PASS: BUY_REFUSALS — short of gold with figures, both tops, by level, unknown kind, a merchant, nobody';

  -- ── RENAME ── at sea, empty, lit; and every refusal
  perform pg_temp.as_house(c_ua);
  select count(*) into v_n from public.events e where e.player_id = v_a and e.kind = 'FLEET_RENAMED';
  if v_n <> 1 then
    raise exception 'PROOF 57 FAIL: the dark rename wrote % events, not one', v_n;
  end if;
  update public.fleets set status = 'SAILING', port_id = null where id = v_f2;
  v_r := cmd.rename_fleet(v_f2, 'Ao Largo 0f57');
  if not (v_r ->> 'ok')::boolean or (select name || ':' || status from public.fleets where id = v_f2) <> 'Ao Largo 0f57:SAILING' then
    raise exception 'PROOF 57 FAIL: a fleet at sea did not take her name: %', v_r;
  end if;
  update public.fleets set status = 'DOCKED', port_id = v_lis where id = v_f2;
  update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_f3;   -- the third fleet holds no ship: an empty fleet, as 0321 leaves one
  v_r := cmd.rename_fleet(v_f3, 'Vazia 0f57');
  if not (v_r ->> 'ok')::boolean or (select name from public.fleets where id = v_f3) <> 'Vazia 0f57' then
    raise exception 'PROOF 57 FAIL: an empty fleet did not take her name: %', v_r;
  end if;
  v_new := world.fleets();
  select e.value -> 'totals' into v_x from jsonb_array_elements(v_new) e where (e.value ->> 'id')::uuid = v_f3;
  if v_x is distinct from jsonb_build_object('ships', 0, 'attack', 0, 'hull', 0, 'hull_max', 0, 'crew', 0, 'crew_required', 0, 'crew_max', 0, 'short_crew', '[]'::jsonb,
                                             'wages_day', public.fleet_wage(v_f3, false), 'slowest', null) then
    raise exception 'PROOF 57 FAIL: an empty fleet''s totals are not zeros: %', v_x;
  end if;
  if (select (e.value -> 'totals' ->> 'ships')::int from jsonb_array_elements(v_new) e where (e.value ->> 'id')::uuid = v_f1) <> 7 then
    raise exception 'PROOF 57 FAIL: seven ships do not count seven';
  end if;
  v_r := cmd.rename_fleet(v_f3, 'Vazia 0f57');
  if not (v_r ->> 'ok')::boolean or (v_r ->> 'changed')::boolean then
    raise exception 'PROOF 57 FAIL: the same name again: %', v_r;
  end if;
  for h in select * from (values (v_f1, 'ab', 'E_BAD_NAME'), (v_f1, '    ', 'E_BAD_NAME'), (v_f1, repeat('n', 25), 'E_BAD_NAME'), (v_f1, null, 'E_BAD_NAME'),
                                 (v_f1, 'ao largo 0F57', 'E_NAME_TAKEN'), (v_fb, 'Roubada 0f57', 'E_NO_SUCH_FLEET'), (null::uuid, 'Nenhuma 0f57', 'E_NO_SUCH_FLEET')) t(fl, nm, want) loop
    v_r := cmd.rename_fleet(h.fl, h.nm);
    if v_r ->> 'error_code' is distinct from h.want then
      raise exception 'PROOF 57 FAIL: renaming to "%" answered % and not %', h.nm, v_r, h.want;
    end if;
  end loop;
  if (select count(*) from public.events e where e.player_id = v_a and e.kind = 'FLEET_RENAMED') <> 3
     or (select name from public.fleets where id = v_f1) <> 'Primeira 0f57' or (select name from public.fleets where id = v_fb) <> 'Other 0f57'
     or not exists (select 1 from public.events e where e.player_id = v_a and e.kind = 'FLEET_RENAMED' and e.payload = jsonb_build_object('from', 'Second 0f57', 'to', 'Ao Largo 0f57')) then
    raise exception 'PROOF 57 FAIL: the renames did not leave three events and the refused ones no mark';
  end if;
  perform pg_temp.as_house(null);
  raise notice 'PASS: RENAME — docked, at sea, empty, dark and lit; version unmoved; bad, taken, not hers, none: refused; one event a change';
end
$$;
