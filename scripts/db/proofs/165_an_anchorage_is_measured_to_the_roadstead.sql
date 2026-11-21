-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 165 — AN ANCHORAGE IS MEASURED TO THE ROADSTEAD  (migration 0462)
--
--   For a ship at an anchorage Trade's board measured the first leg as the way in to the harbour's quay (world.board_origin, 42 nm in proof 162's
--   scene); the SAIL goes to the roadstead (18.8 nm). A barca at anchor 0.4 degrees west of Lisbon's roadstead, a day and a half of casks: the
--   board's way in, and the days, stores and wages of its Lisbon row, are held against the SAIL to Lisbon on the same scene (the sea calmed, the
--   economy open). Run on the chain before 0462 this fails on the miles.
--
-- @pass QUOTE_ANCHOR_ROADSTEAD  the board's way in from an anchorage is the miles the SAIL then sails, and its row's days, stores and wages are the SAIL's
-- ══════════════════════════════════════════════════════════════════════════════════

-- @@block 1: an anchorage
do $$
declare
  c_auth constant uuid := '00000000-0462-4000-8000-0000000000a5';
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
  values (c_auth, 'Casa da Prova 165', (select n.id from public.nations n where n.code = 'PRT'), 1000000, false)
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

  if abs(round(v_voy.total_nm) - (v_board->'fleet'->'where'->>'miles_left')::numeric) > 0.5 then
    v_fail := v_fail || format(' miles: the SAIL is %s nm, the board said %s;', round(v_voy.total_nm, 1), v_board->'fleet'->'where'->>'miles_left');
  end if;
  if abs(v_voy.total_nm / v_voy.speed / 24 - (v_row->>'sail_days')::numeric) > 0.006 then
    v_fail := v_fail || format(' days: the SAIL takes %s voyage-days at %s kn, the row said %s;', round(v_voy.total_nm / v_voy.speed / 24, 3), v_voy.speed, v_row->>'sail_days');
  end if;
  if v_p0 - v_p1 <> (v_row->'supplies'->>'cost')::bigint then
    v_fail := v_fail || format(' stores: the SAIL bought %s, the row said %s;', v_p0 - v_p1, v_row->'supplies'->>'cost');
  end if;
  if round(v_owed1 - v_owed0) <> (v_row->>'wages')::numeric then
    v_fail := v_fail || format(' wages: owed %s, the row said %s;', round(v_owed1 - v_owed0), v_row->>'wages');
  end if;
  if v_fail <> '' then
    raise exception 'PROOF 165 FAIL (anchorage):%', v_fail;
  end if;
  raise notice 'PASS: QUOTE_ANCHOR_ROADSTEAD — at anchor off Lisbon: board % nm in, the SAIL % nm (% kn); row % d, the SAIL % d; stores % and %, wages % and %',
    v_board->'fleet'->'where'->>'miles_left', round(v_voy.total_nm, 1), v_voy.speed, v_row->>'sail_days', round(v_voy.total_nm / v_voy.speed / 24, 3),
    v_row->'supplies'->>'cost', v_p0 - v_p1, v_row->>'wages', round(v_owed1 - v_owed0);
end
$$;
