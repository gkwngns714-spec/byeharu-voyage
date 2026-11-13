-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 72 — GEAR WEAR, LIT  (migration 0158's rules behind the switch gear_wear_bite, as a company plays them)
--
--   0158's own self-assert proved each function on probes on the day it was written (2026-10-18), dark. This proof PLAYS it with the switch lit, on the
--   chain as it stands today: a probe company fits a barca through the game's own core (public.mount_fitting), sails a real passage (cmd.issue, a SAIL
--   with the proofs' course, voyage.settle at the arrival's own instant), reads her wear, her figures, the yard's price, repairs through cmd.issue REPAIR,
--   takes a worn piece off, and then the same hull sails as a MERCHANT's and wears nothing. The proof lights the switch itself inside its own rolled-back
--   transaction, so it holds on a chain where the switch is still dark and on one where a later file has lit it.
--
--   THE SEA IS NOT ASKED TO BEHAVE. The passage is sailed on a quiet sea (hazard_p_max 0, as proof 12 sails), so its wear is the miles' and nothing a
--   world's dice decide; what a STORM day and a PIRATES day wear is proven on the probe's own voyage with a day of each written into it, through the one
--   writer. No marker depends on the outcome of a roll.
--
-- @pass WEAR_DARK_ACCRUES     dark: the passage wore her canvas by its miles and nothing else, and no read shows it (no wear card, no fittings bill, her figures whole)
-- @pass WEAR_BY_TRIGGER       a STORM day wears the piece that answers to storms, a PIRATES day the one that answers to pirates, by the knobs, held at 100
-- @pass WEAR_LIT_FIGURES      lit: a worn piece is served its wear and what it works at, and her figures count its buys at that factor and nothing above the whole figure
-- @pass WEAR_LIT_REPAIR       lit: the yard prices the worn fittings (public.unit_repair_cost, one by one), REPAIR charges exactly that with a whole hull, and nothing is worn after
-- @pass WEAR_LIT_UNFIT        lit: a worn piece is repaired on its way off, for its own price; a new piece comes off for nothing
-- @pass WEAR_MERCHANT_EXEMPT  the same hull sailing as a merchant's wears nothing over the same miles, lit
-- @pass WEAR_DARK_AGAIN       the switch off again: the wear stays on the units and no read, price or figure shows it (the rollback is the one knob)
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth constant uuid := '00000000-0158-4000-8000-0000000072aa';
  v_pl      uuid;
  v_fl      uuid;
  v_sh      uuid;
  v_lis     uuid;
  v_near    record;
  v_r       jsonb;
  v_voy     record;
  v_n       int;
  v_nm      numeric;
  v_whole   jsonb;   -- her figures with nothing worn
  v_worn    jsonb;
  v_k       text;
  v_miles   text;    -- the item of hers that answers to MILES, to STORM, to PIRATES
  v_storm   text;
  v_pirate  text;
  v_w       numeric;
  v_w2      numeric;
  v_card    jsonb;
  v_due     record;
  v_want    bigint;
  v_p0      bigint;
  v_p1      bigint;
  v_lower   int := 0;
begin
  if to_regprocedure('public.gear_wear_on()') is null or to_regprocedure('public.wear_units_for(uuid,uuid)') is null then
    raise exception 'PROOF 72 FAIL: 0158 (gear wears and is repaired) is not in this world';
  end if;
  -- a quiet sea (the passage's wear is its miles), the switch DARK to begin with, and no skill asked of the probe's fittings
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  update public.world_config set value = 'false'::jsonb where key in ('gear_wear_bite', 'skills_bite', 'levels_bite');
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (c_auth, 'Casa da Prova 72', (select n.id from public.nations n where n.code = 'PRT'), 200000, false)
  returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Prova', v_lis);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Prova 72', true, true);
  select s.id into v_sh from public.ships s where s.fleet_id = v_fl limit 1;
  perform cmd.assume_identity(c_auth);

  -- HER FITTINGS: one piece for each kind of wear, the cheapest of each that she can carry, through the core of FIT
  for v_k in select unnest(array['MILES', 'STORM', 'PIRATES']) loop
    for v_r in select to_jsonb(k.code) from public.item_kinds k join public.item_use iu on iu.item_code = k.code and iu.trigger = v_k
                 join public.item_profile ip on ip.item_code = k.code and ip.rack <> 'refit'
                where exists (select 1 from public.item_effects e where e.item_code = k.code and e.delta > 0)
                order by public.item_recipe_value(k.code), k.code loop
      begin
        perform public.mount_fitting(v_sh, v_r #>> '{}');
        if v_k = 'MILES' then v_miles := v_r #>> '{}'; elsif v_k = 'STORM' then v_storm := v_r #>> '{}'; else v_pirate := v_r #>> '{}'; end if;
        exit;
      exception when sqlstate 'P0001' then null;   -- no place or no room for this one: the next
      end;
    end loop;
  end loop;
  if v_miles is null or v_storm is null or v_pirate is null then
    raise exception 'PROOF 72 FAIL: the barca could not be fitted with a piece of each kind (miles %, storm %, pirates %)', v_miles, v_storm, v_pirate;
  end if;
  v_whole := world.ship_stats(v_sh);

  -- ── THE PASSAGE, DARK ──
  select r.port_id, r.code, r.nm into v_near
    from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id
   where p.kind = 'HARBOUR' and r.nm >= 150 and proof.course('LIS', r.code) is not null
     and voyage.leg_refusal(v_fl, r.port_id, r.nm, null) is null
   order by r.nm limit 1;
  if v_near.port_id is null then
    raise exception 'PROOF 72 FAIL: no harbour 150 nm or more from Lisbon is open to the probe';
  end if;
  v_r := proof.sail(v_fl, v_near.code);
  if (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
    raise exception 'PROOF 72 FAIL: she did not sail for %: %', v_near.code, v_r;
  end if;
  for v_n in 1 .. 30 loop
    exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
    select v.id, v.eta, v.total_nm into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
    perform voyage.settle(v_fl, v_voy.eta);
  end loop;
  if (select f.port_id from public.fleets f where f.id = v_fl) is distinct from v_near.port_id then
    raise exception 'PROOF 72 FAIL: she did not make % on a quiet sea', v_near.code;
  end if;
  v_nm := v_voy.total_nm;
  select u.wear into v_w from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_miles;
  if v_w <> round(v_nm / 1000 * public.wc_num('gear_wear_per_1000nm'), 2) or v_w <= 0
     or exists (select 1 from public.fitted_units u where u.ship_id = v_sh and u.item_code <> v_miles and u.wear <> 0) then
    raise exception 'PROOF 72 FAIL: % nm on a quiet sea wore her % by % (wanted %), or wore another piece: %', v_nm, v_miles, v_w,
      round(v_nm / 1000 * public.wc_num('gear_wear_per_1000nm'), 2), (select jsonb_agg(jsonb_build_array(u.item_code, u.wear)) from public.fitted_units u where u.ship_id = v_sh);
  end if;
  -- dark, nothing shows it
  if world.ship_stats(v_sh) - 'durability' <> v_whole - 'durability'
     or exists (select 1 from jsonb_array_elements(world.ship_racks(v_sh, null)) rk, jsonb_array_elements(rk.value -> 'fitted') u where u.value ? 'wear')
     or (select d.gear from public.fleet_repair_due(v_fl, 100) d) is not null then
    raise exception 'PROOF 72 FAIL: dark, a read shows her wear (figures %, racks %, due %)', world.ship_stats(v_sh), world.ship_racks(v_sh, null),
      (select d.gear from public.fleet_repair_due(v_fl, 100) d);
  end if;
  raise notice 'PASS: WEAR_DARK_ACCRUES — % nm to % wore her % by % and nothing else; dark, no card, no bill, her figures whole', round(v_nm), v_near.code, v_miles, v_w;

  -- ── A STORM DAY AND A PIRATES DAY, written into her own voyage, through the one writer ──
  update public.fitted_units set wear = 0 where ship_id = v_sh;
  delete from public.voyage_events ve where ve.voyage_id = v_voy.id;
  insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
  values (v_voy.id, 9001, 'STORM', '{}'::jsonb, now()), (v_voy.id, 9002, 'STORM', '{}'::jsonb, now()), (v_voy.id, 9003, 'PIRATES', '{}'::jsonb, now());
  perform public.wear_units_for(v_fl, v_voy.id);
  if (select u.wear from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_storm) <> 2 * public.wc_num('gear_wear_per_storm')
     or (select u.wear from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_pirate) <> public.wc_num('gear_wear_per_fight')
     or (select u.wear from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_miles) <> v_w then
    raise exception 'PROOF 72 FAIL: two STORM days and a PIRATES day wore her %', (select jsonb_agg(jsonb_build_array(u.item_code, u.wear)) from public.fitted_units u where u.ship_id = v_sh);
  end if;
  update public.fitted_units set wear = 99.5 where ship_id = v_sh and item_code = v_storm;
  perform public.wear_units_for(v_fl, v_voy.id);
  if (select u.wear from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_storm) <> 100 then
    raise exception 'PROOF 72 FAIL: wear is not held at 100';
  end if;
  raise notice 'PASS: WEAR_BY_TRIGGER — two STORM days wore her % by %, a PIRATES day her % by %, the miles her % again; held at 100',
    v_storm, 2 * public.wc_num('gear_wear_per_storm'), v_pirate, public.wc_num('gear_wear_per_fight'), v_miles;

  -- ── LIT: THE CARD AND THE FIGURES ──
  update public.fitted_units set wear = case item_code when v_storm then 50 else 0 end where ship_id = v_sh;
  update public.world_config set value = 'true'::jsonb where key = 'gear_wear_bite';
  select u.value into v_card
    from jsonb_array_elements(world.ship_racks(v_sh, null)) rk, jsonb_array_elements(rk.value -> 'fitted') u where u.value ->> 'code' = v_storm;
  if (v_card ->> 'wear')::numeric <> 50 or (v_card ->> 'works_pct')::numeric <> 75
     or (select count(*) from jsonb_array_elements(world.ship_racks(v_sh, null)) rk, jsonb_array_elements(rk.value -> 'fitted') u where u.value ? 'wear') <> 3 then
    raise exception 'PROOF 72 FAIL: lit, her racks do not serve the worn piece at 50 working at 75, or not a card for each of her three: %', world.ship_racks(v_sh, null);
  end if;
  v_worn := world.ship_stats(v_sh);
  for v_k in select jsonb_object_keys(v_whole) loop
    continue when v_k = 'durability';   -- her hull's own points, which the sea may have touched
    if (v_worn ->> v_k)::numeric > (v_whole ->> v_k)::numeric then
      raise exception 'PROOF 72 FAIL: worn, her % is % above the whole figure %', v_k, v_worn ->> v_k, v_whole ->> v_k;
    end if;
    if (v_worn ->> v_k)::numeric < (v_whole ->> v_k)::numeric then v_lower := v_lower + 1; end if;
  end loop;
  if v_lower = 0 then
    raise exception 'PROOF 72 FAIL: a piece at 50 lowers none of her figures (whole %, worn %)', v_whole, v_worn;
  end if;
  -- the factor itself, on the piece's own buys: every buy of the worn piece is counted at 0.75, to its own scale
  if exists (select 1 from public.item_effects e where e.item_code = v_storm and e.delta > 0 and public.worn_delta(e.delta, 50) <> round(e.delta * 0.75, scale(e.delta)))
     or exists (select 1 from public.item_effects e where e.item_code = v_storm and e.delta <= 0 and public.worn_delta(e.delta, 50) <> e.delta) then
    raise exception 'PROOF 72 FAIL: a buy of the worn piece is not counted at 0.75, or a spend is not counted whole';
  end if;
  raise notice 'PASS: WEAR_LIT_FIGURES — % at 50 is served "50 worn, works at 75"; % of her figures fall, none rises; its buys count at 0.75 and its spends whole', v_storm, v_lower;

  -- ── LIT: THE YARD ──  (she sails home first: Lisbon keeps a repair yard; the passage adds its miles to her canvas)
  v_r := proof.sail(v_fl, 'LIS');
  for v_n in 1 .. 30 loop
    exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
    select v.id, v.eta, v.total_nm into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
    perform voyage.settle(v_fl, v_voy.eta);
  end loop;
  if (select f.port_id from public.fleets f where f.id = v_fl) is distinct from v_lis or (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED' then
    raise exception 'PROOF 72 FAIL: she did not make Lisbon again';
  end if;
  update public.fleets set ready_at = null where id = v_fl;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.id = v_sh;   -- a whole hull: the bill is the fittings' alone
  select coalesce(sum(public.unit_repair_cost(u.item_code, u.wear)), 0), count(*) into v_want, v_n from public.fitted_units u where u.ship_id = v_sh and u.wear > 0;
  select d.points, d.gear into v_due from public.fleet_repair_due(v_fl, 100) d;
  if v_n < 2 or v_due.points <> 0 or (v_due.gear ->> 'units')::int <> v_n or (v_due.gear ->> 'cost')::bigint <> v_want then
    raise exception 'PROOF 72 FAIL: the yard does not price her % worn fittings at % with a whole hull: %', v_n, v_want, to_jsonb(v_due);
  end if;
  select ducats into v_p0 from public.players where id = v_pl;
  v_r := cmd.issue(v_fl, 'REPAIR');
  select ducats into v_p1 from public.players where id = v_pl;
  if coalesce(v_r -> 'order' ->> 'status', '') = 'failed' or v_p0 - v_p1 <> v_want
     or exists (select 1 from public.fitted_units u where u.ship_id = v_sh and u.wear <> 0)
     or (select d.gear from public.fleet_repair_due(v_fl, 100) d) is not null then
    raise exception 'PROOF 72 FAIL: REPAIR charged % (wanted %) or left a piece worn: %', v_p0 - v_p1, v_want, v_r;
  end if;
  if world.ship_stats(v_sh) - 'durability' <> v_whole - 'durability' then
    raise exception 'PROOF 72 FAIL: repaired, her figures are not the whole ones again';
  end if;
  raise notice 'PASS: WEAR_LIT_REPAIR — % worn fittings priced at % d. with a whole hull; REPAIR charged exactly that; nothing worn after, her figures whole again', v_n, v_want;

  -- ── LIT: A WORN PIECE COMES OFF REPAIRED ──
  update public.fleets set status = 'DOCKED', busy_until = null where id = v_fl;   -- the yard's hours are skipped
  update public.fitted_units set wear = 40 where ship_id = v_sh and item_code = v_storm;
  v_want := public.unit_repair_cost(v_storm, 40);
  select ducats into v_p0 from public.players where id = v_pl;
  perform public.unmount_fitting(v_sh, v_storm);
  select ducats into v_p1 from public.players where id = v_pl;
  if v_p0 - v_p1 <> v_want or exists (select 1 from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_storm) then
    raise exception 'PROOF 72 FAIL: the worn % came off for % (wanted %)', v_storm, v_p0 - v_p1, v_want;
  end if;
  perform public.unmount_fitting(v_sh, v_pirate);
  if (select ducats from public.players where id = v_pl) <> v_p1 then
    raise exception 'PROOF 72 FAIL: a new piece cost something to take off';
  end if;
  raise notice 'PASS: WEAR_LIT_UNFIT — % at 40 came off for its own price, % d.; the new % came off for nothing', v_storm, v_want, v_pirate;

  -- ── THE SAME HULL AS A MERCHANT'S: the same miles, lit, wear nothing ──
  -- (a merchant never signs in, so she sails as the probe and is a merchant's hull by the time she arrives: the arrival is what asks)
  select u.wear into v_w from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_miles;
  v_r := proof.sail(v_fl, v_near.code);
  if (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING' then
    raise exception 'PROOF 72 FAIL: she did not sail a third time: %', v_r;
  end if;
  update public.players set is_npc = true, auth_uid = null where id = v_pl;
  for v_n in 1 .. 30 loop
    exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
    select v.id, v.eta, v.total_nm into v_voy from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING' limit 1;
    perform voyage.settle(v_fl, v_voy.eta);
  end loop;
  select u.wear into v_w2 from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_miles;
  if (select v.status from public.voyages v where v.id = v_voy.id) = 'SAILING' or v_w2 <> v_w then
    raise exception 'PROOF 72 FAIL: as a merchant''s, % nm moved her wear from % to % (or she never arrived)', v_voy.total_nm, v_w, v_w2;
  end if;
  raise notice 'PASS: WEAR_MERCHANT_EXEMPT — % nm as a merchant''s hull, lit: her % stays at %', round(v_voy.total_nm), v_miles, v_w;
  update public.players set is_npc = false, auth_uid = c_auth where id = v_pl;

  -- ── THE SWITCH OFF AGAIN ──
  update public.fitted_units set wear = 50 where ship_id = v_sh and item_code = v_miles;
  v_worn := world.ship_stats(v_sh);
  update public.world_config set value = 'false'::jsonb where key = 'gear_wear_bite';
  v_whole := world.ship_stats(v_sh);
  if exists (select 1 from jsonb_array_elements(world.ship_racks(v_sh, null)) rk, jsonb_array_elements(rk.value -> 'fitted') u where u.value ? 'wear')
     or (select d.gear from public.fleet_repair_due(v_fl, 100) d) is not null
     or (select u.wear from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_miles) <> 50
     or v_whole = v_worn
     or exists (select 1 from public.item_effects e where e.item_code = v_miles and public.worn_delta(e.delta, 50) <> e.delta) then
    raise exception 'PROOF 72 FAIL: with the switch off again a read still shows her wear, or her figures did not come back (lit %, dark %)', v_worn, v_whole;
  end if;
  raise notice 'PASS: WEAR_DARK_AGAIN — the switch off: her % keeps its 50, no card, no bill, and her figures are the whole ones (they differ from the lit ones)', v_miles;
end
$$;
