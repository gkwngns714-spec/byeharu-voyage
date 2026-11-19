-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 162 — A TRIP IS QUOTED AS IT IS SAILED: ITS TIME, THE WEIGHT OF A GOOD BOUGHT ON THE WAY, AND NO STORES FROM AN ANCHORAGE  (migration 0459)
--
--   Three faults 0454 left (docs/dev-log/2026-11-18-stores-quote.md, "Not changed"), each built here on purpose and SAILED, the quote read
--   before she leaves and held against what the game then did. The sea is calmed for this transaction (hazard_p_max 0: no storm, calm or
--   raider moves a day) and the economy is open (no dock fee, no port time), so every figure can be held to the coin and to the rounding.
--
--   1. THE TIME. The Map's Send fleet (world.trip_cost) quoted a leg's days at her speed in port, before the leg's stores were aboard; the SAIL
--      freezes her speed after the top-up (voyage.depart), so she arrives later than quoted. A barca at Lisbon, casks empty, one long leg.
--   2. THE WEIGHT OF A GOOD BOUGHT ON THE WAY. Trade's board (world.good_board) walked the legs after the buy city with the cargo aboard NOW: a
--      full hold bought there was not in her speed (fill = cargo + stores over her hold, load_speed_penalty), so the days, the wages and the
--      stores after the buy were a lighter ship's. Two hulls at Lisbon, holds empty: sail to a near city, buy a full hold there, sail on.
--   3. AN ANCHORAGE. From her own anchor the walk topped her up for the way to the nearest harbour; cmd.do_sail buys stores only when docked.
--      A barca at anchor off Lisbon with a day and a half of casks, her cargo sold at Lisbon: the quote's supplies are what the SAIL buys (nothing).
--
-- @pass QUOTE_TIME_MAP        world.trip_cost's days for a leg are the days the SAIL then took (her speed laden with that leg's stores)
-- @pass QUOTE_BUY_WEIGHT      Trade's row for a good bought on the way: the stores, the wages and the days of the trip are what the SAILs charged and took
-- @pass QUOTE_ANCHOR_STORES   from an anchorage the row's supplies are what the SAIL bought (none), and its wages what was owed
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- @@block 1: the time
do $$
declare
  c_auth constant uuid := '00000000-0459-4000-8000-0000000000a1';
  v_pl    uuid;
  v_fl    uuid;
  v_sh    uuid;
  v_lis   uuid;
  v_a     text;
  v_c     jsonb;
  v_nm    numeric;
  v_port  numeric;
  v_trip  jsonb;
  v_r     jsonb;
  v_voy   record;
  v_tc    numeric := public.wc_num('time_compression');
  v_real  numeric;
  v_fail  text := '';
begin
  update public.world_config set value = '0'::jsonb where key = 'hazard_p_max';
  update public.world_config set value = 'false'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (c_auth, 'Casa da Prova 162a', (select n.id from public.nations n where n.code = 'PRT'), 1000000, false)
  returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Prova', v_lis);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova', true, true);
  select s.id into v_sh from public.ships s where s.fleet_id = v_fl limit 1;
  update public.ships set crew = greatest(crew, 20), water_t = 0, food_t = 0, cargo = '{}'::jsonb where id = v_sh;
  -- no dice: each hull as her class is drawn (commission_ship rolls a new hull's stats), and whole
  update public.ships s set roll_speed = 1, roll_hold = 1, roll_stores = 1, roll_hull = 1, roll_crew = 1, roll_handling = 1 where s.fleet_id = v_fl;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_fl;
  perform cmd.assume_identity(c_auth);
  v_port := voyage.fleet_speed(v_fl);

  -- THE LEG: the longest from Lisbon with a course whose stores fit her (the more stores aboard, the slower she sails it than in port)
  select q.code, q.course, q.nm into v_a, v_c, v_nm
    from (select p.code, proof.course('LIS', p.code) as course from public.ports p where p.kind = 'HARBOUR' and p.code <> 'LIS') c
   cross join lateral (select c.code, c.course, (select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(c.course)) s) as nm) q
   where c.course is not null and (select n.fits from public.supply_need(v_fl, q.nm) n) and q.nm <= public.passage_reach_nm(v_pl)
   order by q.nm desc, q.code
   limit 1;
  if v_a is null then
    raise exception 'PROOF 162 FAIL: no leg from Lisbon with a course and stores that fit a barca';
  end if;

  v_trip := world.trip_cost(v_fl, jsonb_build_array(jsonb_build_object('from', 'LIS', 'to', v_a, 'course', v_c)));
  v_r := cmd.issue_lines(v_fl, jsonb_build_array(jsonb_build_object('text', 'SAIL ' || v_a, 'path', v_c)), null);
  if (v_r->>'ok')::boolean is not true or (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
    raise exception 'PROOF 162 FAIL: the SAIL to % did not leave: %', v_a, v_r;
  end if;
  select v.id, v.eta, v.departed_at, (v.speed_profile ->> 0)::numeric as speed into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
  v_real := extract(epoch from v_voy.eta - v_voy.departed_at) * v_tc / 86400;   -- the voyage-days she takes: real seconds at time_compression
  if abs((v_trip->>'sail_days')::numeric - v_real) > 0.0051 or abs((v_trip->'legs'->0->>'days')::numeric - v_real) > 0.0051
     or abs((v_trip->>'days')::numeric - v_real) > 0.0051 then
    v_fail := format('the quote says %s d (leg %s d, all %s d) and she takes %s d to %s (%s nm; in port %s kn, she sails at %s kn)',
                     v_trip->>'sail_days', v_trip->'legs'->0->>'days', v_trip->>'days', round(v_real, 4), v_a, round(v_nm, 1), v_port, v_voy.speed);
  end if;
  if v_fail <> '' then
    raise exception 'PROOF 162 FAIL (time): %', v_fail;
  end if;
  raise notice 'PASS: QUOTE_TIME_MAP — LIS to % (% nm): quoted % d, sailed % d (in port % kn, laden with the leg''s stores % kn)',
    v_a, round(v_nm, 1), v_trip->>'sail_days', round(v_real, 4), v_port, v_voy.speed;
end
$$;

-- @@block 2: the weight of a good bought on the way
do $$
declare
  c_auth constant uuid := '00000000-0459-4000-8000-0000000000a2';
  v_pl     uuid;
  v_fl     uuid;
  v_lis    uuid;
  v_y      text;
  v_cy     jsonb;
  v_good   record;
  v_board  jsonb;
  v_row    jsonb;
  v_brow   jsonb;
  v_codes  text[];
  v_lines  jsonb;
  v_r      jsonb;
  v_p0     bigint;
  v_p1     bigint;
  v_owed0  numeric;
  v_owed1  numeric;
  v_voy    record;
  v_tc     numeric := public.wc_num('time_compression');
  v_scaled numeric := 0;
  v_nm_c   numeric;
  v_nm_t   numeric;
  v_bought bigint;
  v_legs_t text := '';
  v_fail   text := '';
  v_n      int;
  k        int;
  i        int;
begin
  update public.world_config set value = '0'::jsonb where key = 'hazard_p_max';
  update public.world_config set value = 'false'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  -- for this transaction only: Trade prices in full the 40 nearest sales she can sail to (5 on the live board), so a sale two to six days on is priced
  update public.world_config set value = '40'::jsonb where key = 'good_board_quoted_near';
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (c_auth, 'Casa da Prova 162b', (select n.id from public.nations n where n.code = 'PRT'), 5000000, false)
  returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Prova', v_lis);
  -- two hulls of different holds, so the buy is stowed across them (largest first: public.fleet_load) and the slower decides
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova', true, true);
  perform public.commission_ship(v_pl, v_fl, 'caravelao', 'Prova II', false, true);
  update public.ships s set crew = greatest(s.crew, c.crew_required), water_t = 0, food_t = 0, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb
    from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fl;
  -- no dice: each hull as her class is drawn (commission_ship rolls a new hull's stats), and whole
  update public.ships s set roll_speed = 1, roll_hold = 1, roll_stores = 1, roll_hull = 1, roll_crew = 1, roll_handling = 1 where s.fleet_id = v_fl;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_fl;
  perform cmd.assume_identity(c_auth);

  -- THE BUY CITY: a harbour near Lisbon, straight from it, with a course; THE GOOD: the heaviest it sells for which Trade prices a sale on from
  -- there of two to six days at her speed in port (a full hold's slowing then carries the way on into more days, eaten and owed), with a
  -- course for every leg
  for v_y, v_cy in
    select p.code, proof.course('LIS', p.code)
      from public.ports p join public.sea_reaches sr on sr.code = 'LIS'
     where p.kind = 'HARBOUR' and p.code <> 'LIS' and proof.course('LIS', p.code) is not null and (sr.reaches->>p.code) is not null
     order by (sr.reaches->>p.code)::numeric, p.code
     limit 3
  loop
    for v_good in
      select g.id, g.code, g.bulk from public.goods g join public.ports p on p.code = v_y
       where public.port_offers(p.id, g.id) order by g.bulk desc, g.code limit 3
    loop
      v_board := world.good_board(v_good.id, v_fl, (select p.id from public.ports p where p.code = v_y and p.kind = 'HARBOUR'), null);
      select e into v_brow from jsonb_array_elements(v_board->'buy') e where e->>'port' = v_y;
      select e into v_row
        from jsonb_array_elements(v_board->'sell') e
       cross join lateral (select array[v_y] || array(select jsonb_array_elements_text(e->'stops')) || (e->>'port') as c) w
       where (e->>'sailable')::boolean and (e->>'quoted')::boolean and jsonb_typeof(e->'profit') = 'number' and e->>'port' not in ('LIS', v_y)
         and not exists (select 1 from generate_subscripts(w.c, 1) j where j > 1 and proof.course(w.c[j - 1], w.c[j]) is null)
         and (select sum((sr.reaches->>w.c[j])::numeric) from generate_subscripts(w.c, 1) j join public.sea_reaches sr on sr.code = w.c[j - 1] where j > 1)
             between 2 * 24 * (v_board->'fleet'->>'speed_kn')::numeric and 6 * 24 * (v_board->'fleet'->>'speed_kn')::numeric
       order by (e->>'miles')::numeric, e->>'port' limit 1;
      exit when v_row is not null and v_board->'qty'->>'bought_at' = v_y and jsonb_array_length(v_brow->'stops') = 0 and (v_board->'qty'->>'units')::numeric > 0;
      v_row := null;
    end loop;
    exit when v_row is not null;
  end loop;
  if v_row is null then
    raise exception 'PROOF 162 FAIL: no good is bought at a harbour near Lisbon and sold two days on from it, with a course for each leg';
  end if;
  v_codes := array[v_y] || array(select jsonb_array_elements_text(v_row->'stops')) || (v_row->>'port');
  v_n := cardinality(v_codes);
  v_lines := jsonb_build_array(jsonb_build_object('text', 'SAIL ' || v_y, 'path', v_cy),
                               jsonb_build_object('text', format('BUY %s %s', v_good.code, (v_board->'qty'->>'units')::numeric)));
  for k in 2 .. v_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('text', 'SAIL ' || v_codes[k], 'path', proof.course(v_codes[k - 1], v_codes[k])));
  end loop;
  select ducats into v_p0 from public.players where id = v_pl;
  select coalesce(sum(w.owed), 0) into v_owed0 from public.fleet_wages w where w.fleet_id = v_fl;

  v_r := cmd.issue_lines(v_fl, v_lines, null);
  if (v_r->>'ok')::boolean is not true or exists (select 1 from jsonb_array_elements(v_r->'orders') o where o->>'status' in ('failed', 'cancelled')) then
    raise exception 'PROOF 162 FAIL: the trip was not queued: %', v_r;
  end if;
  for k in 1 .. v_n loop
    if (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
      raise exception 'PROOF 162 FAIL: leg % did not leave', k;
    end if;
    select v.id, v.eta, v.departed_at, v.total_nm, (v.speed_profile ->> 0)::numeric as speed into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
    -- the sailing time, put on the board's miles (the sailed-distance table; the SAIL measures its own course): at one speed, time is miles over speed
    v_nm_c := v_voy.total_nm;
    select (sr.reaches->>v_codes[k])::numeric into v_nm_t from public.sea_reaches sr where sr.code = case when k = 1 then 'LIS' else v_codes[k - 1] end;
    v_scaled := v_scaled + extract(epoch from v_voy.eta - v_voy.departed_at) * v_tc / 86400 * v_nm_t / v_nm_c;
    v_legs_t := v_legs_t || format('%sleg %s to %s: %s nm sailed (%s on the board), %s kn, settles %s d', case when k > 1 then '; ' end, k, v_codes[k],
                                   round(v_nm_c, 1), round(v_nm_t, 1), v_voy.speed, voyage.total_days(v_voy.id));
    for i in 1 .. 30 loop
      exit when (select v.status from public.voyages v where v.id = v_voy.id) <> 'SAILING';
      perform voyage.settle(v_fl, (select v.eta from public.voyages v where v.id = v_voy.id));
    end loop;
    if (select coalesce(v.delay_hours, 0) from public.voyages v where v.id = v_voy.id) <> 0 then
      raise exception 'PROOF 162 FAIL: leg % did not end on a calm sea', k;
    end if;
  end loop;
  if (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fl) is distinct from v_codes[v_n] then
    raise exception 'PROOF 162 FAIL: she did not make %', v_codes[v_n];
  end if;
  select coalesce(sum(public.fleet_cargo_qty(v_fl, v_good.code)), 0) into v_bought;
  select ducats into v_p1 from public.players where id = v_pl;
  select coalesce(sum(w.owed), 0) into v_owed1 from public.fleet_wages w where w.fleet_id = v_fl;

  -- what she paid: the buy (the row's own cost: the same quote, the same market) and her stores at the two departures
  if v_p0 - v_p1 <> (v_row->>'cost')::bigint + (v_row->'supplies'->>'cost')::bigint then
    v_fail := v_fail || format(' stores: paid %s in all, the buy %s and the stores %s were quoted (so %s for stores);', v_p0 - v_p1, v_row->>'cost',
                               v_row->'supplies'->>'cost', v_p0 - v_p1 - (v_row->>'cost')::bigint);
  end if;
  if round(v_owed1 - v_owed0) <> (v_row->>'wages')::numeric then
    v_fail := v_fail || format(' wages: owed %s, quoted %s;', round(v_owed1 - v_owed0), v_row->>'wages');
  end if;
  if abs((v_row->>'sail_days')::numeric - v_scaled) > 0.0051 or abs((v_row->>'days')::numeric - v_scaled) > 0.0051 then
    v_fail := v_fail || format(' time: quoted %s d (all %s d), sailed %s d on the board''s miles;', v_row->>'sail_days', v_row->>'days', round(v_scaled, 4));
  end if;
  if v_fail <> '' then
    raise exception 'PROOF 162 FAIL (bought on the way): % % at % (% units, % t), sold at %: %. Row %',
      v_good.code, v_board->'qty'->>'units', v_y, v_bought, round(v_bought * v_good.bulk, 1), v_codes[v_n], v_fail, v_legs_t;
  end if;
  raise notice 'PASS: QUOTE_BUY_WEIGHT — % x % bought at % (% t aboard), sold at %: stores %, wages %, % d, as quoted (%)',
    v_bought, v_good.code, v_y, round(v_bought * v_good.bulk, 1), v_codes[v_n], v_row->'supplies'->>'cost', v_row->>'wages', v_row->>'sail_days', v_legs_t;
end
$$;

-- @@block 3: an anchorage
do $$
declare
  c_auth constant uuid := '00000000-0459-4000-8000-0000000000a3';
  v_pl     uuid;
  v_fl     uuid;
  v_sh     uuid;
  v_lis    uuid;
  v_good   record;
  v_board  jsonb;
  v_row    jsonb;
  v_r      jsonb;
  v_lat    numeric;
  v_lon    numeric;
  v_crew   numeric;
  v_p0     bigint;
  v_p1     bigint;
  v_owed0  numeric;
  v_owed1  numeric;
  v_voy    record;
  v_fail   text := '';
  i        int;
begin
  update public.world_config set value = '0'::jsonb where key = 'hazard_p_max';
  update public.world_config set value = 'false'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (c_auth, 'Casa da Prova 162c', (select n.id from public.nations n where n.code = 'PRT'), 1000000, false)
  returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Prova', v_lis);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova', true, true);
  select s.id into v_sh from public.ships s where s.fleet_id = v_fl limit 1;
  -- her cargo: the first good (by code) Lisbon has a market for and its culture buys; for this transaction Trade prices every sale she can sail to
  -- in full (good_board_quoted_near, 5 on the live board: the harbour she lies off is ranked last of the near ones), so the sale at Lisbon is
  -- priced whatever the market's draw. Her casks: a day and a half each, enough for the short way in, under the days a top-up would buy it to
  -- (npc_leg_days; a day and a half: at one day she ends the way on short rations)
  update public.world_config set value = '1000'::jsonb where key = 'good_board_quoted_near';
  select g.id, g.code into v_good from public.goods g
   where not public.culture_refuses((select p.culture from public.ports p where p.id = v_lis), g.culture_mask)
     and exists (select 1 from public.port_goods pg where pg.port_id = v_lis and pg.good_id = g.id)
   order by g.code limit 1;
  if v_good.id is null then
    raise exception 'PROOF 162 FAIL: Lisbon has a market for no good its culture buys';
  end if;
  update public.ships set crew = greatest(crew, 20) where id = v_sh;
  select s.crew into v_crew from public.ships s where s.id = v_sh;
  update public.ships set water_t = 1.5 * v_crew * public.wc_num('water_per_crew_day'), food_t = 1.5 * v_crew * public.wc_num('food_per_crew_day'),
         cargo = jsonb_build_object(v_good.code, 5), cargo_basis = jsonb_build_object(v_good.code, 200) where id = v_sh;   -- written straight
  -- AT ANCHOR off Lisbon: west of its roadstead, in open water
  select sr.roadstead_lat, sr.roadstead_lon - 0.4 into v_lat, v_lon from public.sea_reaches sr where sr.code = 'LIS';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = v_lat, lon = v_lon, busy_until = null, ready_at = null, version = f.version + 1 where f.id = v_fl;
  -- no dice: each hull as her class is drawn (commission_ship rolls a new hull's stats), and whole
  update public.ships s set roll_speed = 1, roll_hold = 1, roll_stores = 1, roll_hull = 1, roll_crew = 1, roll_handling = 1 where s.fleet_id = v_fl;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_fl;
  perform cmd.assume_identity(c_auth);

  v_board := world.good_board(v_good.id, v_fl, null, null);
  select e into v_row from jsonb_array_elements(v_board->'sell') e where e->>'port' = 'LIS';
  if v_board->'fleet'->'where'->>'kind' <> 'at_sea' or v_board->'fleet'->'where'->>'via' <> 'LIS' or v_row is null or (v_row->>'wages') is null then
    raise exception 'PROOF 162 FAIL: at anchor off Lisbon the board does not run through Lisbon, or prices no sale there: % / %', v_board->'fleet', v_row;
  end if;
  select ducats into v_p0 from public.players where id = v_pl;
  select coalesce(sum(w.owed), 0) into v_owed0 from public.fleet_wages w where w.fleet_id = v_fl;
  v_r := cmd.issue_lines(v_fl, jsonb_build_array(jsonb_build_object('text', 'SAIL LIS')), null);
  if (v_r->>'ok')::boolean is not true or (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
    raise exception 'PROOF 162 FAIL: from her anchor the SAIL to Lisbon did not leave: %', v_r;
  end if;
  select ducats into v_p1 from public.players where id = v_pl;
  select v.id, v.total_nm, (v.speed_profile ->> 0)::numeric as speed into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
  for i in 1 .. 30 loop
    exit when (select v.status from public.voyages v where v.id = v_voy.id) <> 'SAILING';
    perform voyage.settle(v_fl, (select v.eta from public.voyages v where v.id = v_voy.id));
  end loop;
  select coalesce(sum(w.owed), 0) into v_owed1 from public.fleet_wages w where w.fleet_id = v_fl;

  if v_p0 - v_p1 <> (v_row->'supplies'->>'cost')::bigint then
    v_fail := v_fail || format(' stores: the SAIL bought %s, the row said %s;', v_p0 - v_p1, v_row->'supplies'->>'cost');
  end if;
  if round(v_owed1 - v_owed0) <> (v_row->>'wages')::numeric then
    v_fail := v_fail || format(' wages: owed %s, the row said %s;', round(v_owed1 - v_owed0), v_row->>'wages');
  end if;
  if v_fail <> '' then
    raise exception 'PROOF 162 FAIL (anchorage): % nm in (% on the board) at % kn:%', round(v_voy.total_nm, 1), v_board->'fleet'->'where'->>'miles_left', v_voy.speed, v_fail;
  end if;
  raise notice 'PASS: QUOTE_ANCHOR_STORES — at anchor % nm off Lisbon: the SAIL bought % of stores and the row said %; wages %, as quoted',
    v_board->'fleet'->'where'->>'miles_left', v_p0 - v_p1, v_row->'supplies'->>'cost', v_row->>'wages';
end
$$;
