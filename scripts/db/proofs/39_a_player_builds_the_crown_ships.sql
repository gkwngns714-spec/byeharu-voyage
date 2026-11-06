-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 39 — A PLAYER BUILDS THE CROWN'S SHIPS  (migration 0332, owner 2026-11-06)
--
--   0332's self-assert reads the catalog and stable reads only (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof lays down every crown class through the REAL cmd.do_build,
--   the one BUILD verb, and then asks the real readers what she is. The class list is public.crown_classes, never a list here, so a knob the owner turns is proved too.
--   The economy is CLOSED here, as on prod; one build runs OPEN, as CI's default world.
--
-- @pass CROWN_SERVED       the yard and the Codex read mark exactly the three knobs' classes, and no other hull carries the key
-- @pass CROWN_KNOB         the mark follows the knobs: turn one and the old class loses it; a class named twice is one row, the navy's
-- @pass CROWN_GATES        each crown class meets the existing gates, in order: another country's yard, her skills, her materials, the purse
-- @pass CROWN_BUILD        each crown class is laid down by the one verb: the ship joins the fleet that ordered her, of that class, uncrewed and unstored, and the materials are spent
-- @pass CROWN_MONEY        gold moves once, kind BUILD, company to the yard's city, at the yard's own price; nothing minted, closed
-- @pass CROWN_OPEN         the same build with the economy open, CI's default world: the same price, the same two sides
-- @pass CROWN_ORDINARY     she answers COMPANY, no origin, no row in cargo_ships or navy_ships, no crown house, no crown figure moved, nowhere on the crown's sea read
-- @pass CROWN_LAWS         she owes her own wages and dock fees, and her repair is paid from her own purse to the city
-- @pass CROWN_NO_PVP       the attack verb refuses her as another player's ship
-- @pass CROWN_NO_CLIENT    no client can call public.crown_classes
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_n     int := 0;
  v_k     text;
  v_c     record;
  v_b     record;
  v_ok    uuid;
  v_wrong uuid;
  v_uid   uuid;
  v_pl    uuid;
  v_fl    uuid;
  v_fl2   uuid;
  v_pl2   uuid;
  v_ship  uuid;
  v_price bigint;
  v_mark  bigint;
  v_led   bigint;
  v_t0    bigint;
  v_p0    bigint;
  v_figs  jsonb;
  v_r     jsonb;
  v_want  text;
  v_err   text;
  v_a     numeric;
  v_built uuid[] := '{}';
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite', 'skills_bite', 'attack_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('regard_enabled', 'navy_enabled', 'convoy_armed_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 1000000, reserve = 0;

  execute $f$
create function pg_temp.refused(p_fleet uuid, p_args jsonb)
returns text
language plpgsql
as $b$
begin
  perform cmd.do_build(p_fleet, p_args);
  return 'BUILT';
exception when others then
  return sqlerrm;
end
$b$
  $f$;

  execute $f$
create function pg_temp.house(p_n int, p_port uuid, p_ducats bigint)
returns uuid
language plpgsql
as $b$
declare
  v_p uuid := public.new_house(('00000000-0332-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid, 'Casa Proof ' || p_n, 'PRT', 'LIS', 'Proof ' || p_n, 'barca', 'Proof ' || p_n, null, false);
  v_f uuid;
begin
  select id into v_f from public.fleets where player_id = v_p;
  update public.fleets set port_id = p_port where id = v_f;
  update public.players set ducats = p_ducats where id = v_p;
  return v_f;
end
$b$
  $f$;

  execute $f$
create function pg_temp.equip(p_player uuid, p_port uuid, p_class text)
returns void
language plpgsql
as $b$
begin
  insert into public.player_skills (player_id, skill_id, level)
  select p_player, s.id, r.level from public.skill_requirements r join public.skills s on s.code = r.skill_code
   where r.subject_kind = 'hull' and r.subject_code = p_class
  on conflict (player_id, skill_id) do update set level = excluded.level;
  insert into public.player_storage (player_id, port_id, good_id, qty)
  select p_player, p_port, hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = p_class;
end
$b$
  $f$;

  -- ── THE MARK ──
  select string_agg(k.value #>> '{}', ',' order by k.value #>> '{}') into v_want
    from public.world_config k where k.key in ('convoy_ship_class', 'convoy_armed_class', 'navy_ship_class');
  if (select count(*) from (select distinct k.value #>> '{}' from public.world_config k where k.key in ('convoy_ship_class', 'convoy_armed_class', 'navy_ship_class')) x) <> 3 then
    raise exception 'PROOF 39 FAIL: this proof wants three distinct crown classes, the knobs name %', v_want;
  end if;
  if (select string_agg(s ->> 'code', ',' order by s ->> 'code') from jsonb_array_elements(world.snapshot() -> 'ship_classes') s where s ? 'crown') is distinct from v_want then
    raise exception 'PROOF 39 FAIL: the snapshot does not mark exactly the knobs'' classes %', v_want;
  end if;
  if (select string_agg(s ->> 'class', ',' order by s ->> 'class')
        from jsonb_array_elements(world.building_yard((select b.port_id from public.port_buildings b where b.kind = 'building_yard' order by b.port_id limit 1)) -> 'hulls') s where s ? 'crown') is distinct from v_want then
    raise exception 'PROOF 39 FAIL: the yard does not mark exactly the knobs'' classes %', v_want;
  end if;
  if (select string_agg(s ->> 'code' || '=' || (s ->> 'crown'), ',' order by s ->> 'code') from jsonb_array_elements(world.snapshot() -> 'ship_classes') s where s ? 'crown')
     is distinct from (select string_agg(x.code || '=' || x.crown, ',' order by x.code) from (values (public.wc_text('navy_ship_class'), 'NAVY'), (public.wc_text('convoy_ship_class'), 'CARGO'), (public.wc_text('convoy_armed_class'), 'CARGO')) x(code, crown)) then
    raise exception 'PROOF 39 FAIL: a crown class says the wrong kind of ship';
  end if;
  raise notice 'PASS: CROWN_SERVED — %, on both reads, and no other class', v_want;

  v_k := public.wc_text('navy_ship_class');
  update public.world_config set value = to_jsonb('galeon'::text) where key = 'navy_ship_class';
  if not exists (select 1 from jsonb_array_elements(world.snapshot() -> 'ship_classes') s where s ->> 'code' = 'galeon' and s ->> 'crown' = 'NAVY')
     or exists (select 1 from jsonb_array_elements(world.snapshot() -> 'ship_classes') s where s ->> 'code' = v_k and s ? 'crown') then
    raise exception 'PROOF 39 FAIL: the navy mark did not follow navy_ship_class';
  end if;
  update public.world_config set value = to_jsonb(public.wc_text('convoy_armed_class')) where key = 'navy_ship_class';
  if (select count(*) from public.crown_classes() c where c.class_code = public.wc_text('convoy_armed_class')) <> 1
     or (select c.crown from public.crown_classes() c where c.class_code = public.wc_text('convoy_armed_class')) <> 'NAVY' then
    raise exception 'PROOF 39 FAIL: a class named twice is not one row, the navy''s';
  end if;
  update public.world_config set value = to_jsonb(v_k) where key = 'navy_ship_class';
  raise notice 'PASS: CROWN_KNOB — the mark moved with the knob and came back, % again', v_k;

  -- ── EVERY CROWN CLASS, THROUGH THE ONE VERB, A HOUSE EACH ──
  for v_c in select cu.class_code, cu.crown, h.yard_tier, c.crew_required, c.id as class_id
               from public.crown_classes() cu join public.hull_recipes h on h.class_code = cu.class_code join public.ship_classes c on c.code = cu.class_code
              order by cu.class_code loop
    v_n := v_n + 1;
    select b.port_id into v_ok from public.port_buildings b
     where b.kind = 'building_yard' and b.tier >= v_c.yard_tier and public.yard_wrong_country(b.port_id, v_c.class_code) is null and public.port_has_shipyard(b.port_id)
     order by b.port_id limit 1;
    select b.port_id into v_wrong from public.port_buildings b
     where b.kind = 'building_yard' and b.tier >= v_c.yard_tier and public.yard_wrong_country(b.port_id, v_c.class_code) is not null
     order by b.port_id limit 1;
    if v_ok is null or v_wrong is null then
      raise exception 'PROOF 39 FAIL: % has no yard to prove on: right %, wrong %', v_c.class_code, v_ok, v_wrong;
    end if;

    -- the gates, in order
    v_fl := pg_temp.house(v_n, v_wrong, 100000000);
    select player_id into v_pl from public.fleets where id = v_fl;
    -- the price from the recipe, not from the function the build calls: what the ladder says she costs
    v_price := (select round(h.ducats * public.wc_num('hull_labour_mult'))::bigint from public.hull_recipes h where h.class_code = v_c.class_code);
    if (select (s ->> 'ducats')::bigint from jsonb_array_elements(world.building_yard(v_ok) -> 'hulls') s where s ->> 'class' = v_c.class_code) is distinct from v_price then
      raise exception 'PROOF 39 FAIL: the gold of %: the yard does not print the recipe''s price', v_c.class_code;
    end if;
    v_err := pg_temp.refused(v_fl, jsonb_build_object('class', v_c.class_code, 'name', 'Proof Hull'));
    if v_err not like '%E_WRONG_YARD%' then
      raise exception 'PROOF 39 FAIL: % at another country''s yard: %', v_c.class_code, v_err;
    end if;
    update public.fleets set port_id = v_ok where id = v_fl;
    v_err := pg_temp.refused(v_fl, jsonb_build_object('class', v_c.class_code, 'name', 'Proof Hull'));
    if v_err not like '%E_NEEDS_SKILL%' then
      raise exception 'PROOF 39 FAIL: % with no skills: %', v_c.class_code, v_err;
    end if;
    insert into public.player_skills (player_id, skill_id, level)
    select v_pl, s.id, r.level from public.skill_requirements r join public.skills s on s.code = r.skill_code
     where r.subject_kind = 'hull' and r.subject_code = v_c.class_code
    on conflict (player_id, skill_id) do update set level = excluded.level;
    v_err := pg_temp.refused(v_fl, jsonb_build_object('class', v_c.class_code, 'name', 'Proof Hull'));
    if v_err not like '%E_NO_TIMBER%' then
      raise exception 'PROOF 39 FAIL: % with an empty shed: %', v_c.class_code, v_err;
    end if;
    perform pg_temp.equip(v_pl, v_ok, v_c.class_code);
    update public.players set ducats = v_price - 1 where id = v_pl;
    v_err := pg_temp.refused(v_fl, jsonb_build_object('class', v_c.class_code, 'name', 'Proof Hull'));
    if v_err not like '%E_NO_FUNDS%' then
      raise exception 'PROOF 39 FAIL: % a ducat short: %', v_c.class_code, v_err;
    end if;

    -- the build
    update public.players set ducats = v_price + 500000 where id = v_pl;
    v_mark := (select coalesce(max(f.id), 0) from public.treasury_flows f);
    v_led := (select count(*) from public.ledger l where l.player_id = v_pl);
    v_t0 := public.treasury_balance(v_ok);
    v_figs := public.cargo_figures();
    v_r := cmd.do_build(v_fl, jsonb_build_object('class', v_c.class_code, 'name', 'Proof Hull'));
    v_ship := (v_r ->> 'ship')::uuid;

    if (select s.fleet_id from public.ships s where s.id = v_ship) is distinct from v_fl
       or (select s.player_id from public.ships s where s.id = v_ship) is distinct from v_pl
       or (select s.class_id from public.ships s where s.id = v_ship) is distinct from v_c.class_id
       or (select s.crew from public.ships s where s.id = v_ship) <> 0
       or (select s.water_t + s.food_t from public.ships s where s.id = v_ship) <> 0
       or exists (select 1 from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_ok) then
      raise exception 'PROOF 39 FAIL: % did not arrive as a laid-down hull: %', v_c.class_code, v_r;
    end if;
    if (select p.ducats from public.players p where p.id = v_pl) <> 500000
       or public.treasury_balance(v_ok) - v_t0 <> v_price
       or (v_r ->> 'ducats')::bigint <> v_price
       or (select count(*) from public.treasury_flows f where f.id > v_mark) <> 1
       or (select f.kind || ':' || f.ducats from public.treasury_flows f where f.id > v_mark) <> 'BUILD:' || v_price
       or (select count(*) from public.ledger l where l.player_id = v_pl) <> v_led + 1 then
      raise exception 'PROOF 39 FAIL: the gold of % moved wrong: purse %, city %, price %', v_c.class_code,
        (select p.ducats from public.players p where p.id = v_pl), public.treasury_balance(v_ok) - v_t0, v_price;
    end if;

    -- she is an ordinary ship of her house
    if public.fleet_kind(v_fl) <> 'COMPANY'
       or public.fleet_origin(v_fl) is not null
       or exists (select 1 from public.cargo_ships x where x.fleet_id = v_fl or x.player_id = v_pl)
       or exists (select 1 from public.navy_ships x where x.fleet_id = v_fl or x.player_id = v_pl)
       or public.crown_house(v_pl)
       or public.cargo_figures() is distinct from v_figs
       or exists (select 1 from public.sea_houses() s where s.player_id = v_pl) then
      raise exception 'PROOF 39 FAIL: % made her house a crown''s: kind %, origin %', v_c.class_code, public.fleet_kind(v_fl), public.fleet_origin(v_fl);
    end if;

    -- her laws
    update public.ships set crew = v_c.crew_required where id = v_ship;
    v_a := (select sum(s.crew) from public.ships s where s.fleet_id = v_fl);
    if public.fleet_wage(v_fl, false) <= 0
       or public.fleet_wage(v_fl, false) <> round(public.crew_wages(v_a::integer, false) * public.running_cost_mult(v_pl), 4)
       or public.port_fee(v_ok, v_pl, 1000) <= 0 then
      raise exception 'PROOF 39 FAIL: % does not owe what a company owes: wage %, fee %', v_c.class_code, public.fleet_wage(v_fl, false), public.port_fee(v_ok, v_pl, 1000);
    end if;
    update public.ships set durability = 1 where id = v_ship;
    v_t0 := public.treasury_balance(v_ok);
    v_p0 := (select p.ducats from public.players p where p.id = v_pl);
    perform cmd.do_repair(v_fl, '{}'::jsonb);
    if (select p.ducats from public.players p where p.id = v_pl) >= v_p0
       or v_p0 - (select p.ducats from public.players p where p.id = v_pl) <> public.treasury_balance(v_ok) - v_t0 then
      raise exception 'PROOF 39 FAIL: the repair of % was not paid from her purse to the city', v_c.class_code;
    end if;
    v_built := v_built || v_fl;
  end loop;
  if v_n <> 3 then
    raise exception 'PROOF 39 FAIL: % crown classes built, wanted the three', v_n;
  end if;
  raise notice 'PASS: CROWN_GATES — %, each refused by country, skill, materials and purse in turn', v_want;
  raise notice 'PASS: CROWN_BUILD — %, each by cmd.do_build, uncrewed, unstored, materials spent', v_want;
  raise notice 'PASS: CROWN_MONEY — one BUILD flow and one ledger row each, company to city, closed';
  raise notice 'PASS: CROWN_ORDINARY — COMPANY, no origin, no crown row, no crown figure moved';
  raise notice 'PASS: CROWN_LAWS — wages, dock fees and repairs are her own';

  -- ── OPEN, AS CI'S DEFAULT WORLD ──
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  select cu.class_code, h.yard_tier into v_k, v_n from public.crown_classes() cu join public.hull_recipes h on h.class_code = cu.class_code where cu.crown = 'NAVY';
  select b.port_id into v_ok from public.port_buildings b
   where b.kind = 'building_yard' and b.tier >= v_n and public.yard_wrong_country(b.port_id, v_k) is null order by b.port_id limit 1;
  v_fl2 := pg_temp.house(21, v_ok, 0);
  select player_id into v_pl2 from public.fleets where id = v_fl2;
  v_price := (select round(h.ducats * public.wc_num('hull_labour_mult'))::bigint from public.hull_recipes h where h.class_code = v_k);
  update public.players set ducats = v_price where id = v_pl2;
  insert into public.player_skills (player_id, skill_id, level)
  select v_pl2, s.id, r.level from public.skill_requirements r join public.skills s on s.code = r.skill_code where r.subject_kind = 'hull' and r.subject_code = v_k
  on conflict (player_id, skill_id) do update set level = excluded.level;
  perform pg_temp.equip(v_pl2, v_ok, v_k);
  v_t0 := public.treasury_balance(v_ok);
  v_r := cmd.do_build(v_fl2, jsonb_build_object('class', v_k, 'name', 'Proof Open'));
  if (select p.ducats from public.players p where p.id = v_pl2) <> 0 or public.treasury_balance(v_ok) - v_t0 <> v_price or public.fleet_kind(v_fl2) <> 'COMPANY' then
    raise exception 'PROOF 39 FAIL: open, the build differed: %', v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
  raise notice 'PASS: CROWN_OPEN — % d. company to city, open as closed', v_price;

  -- ── NO PLAYER ATTACKS ANOTHER PLAYER ──
  if not public.attack_on() then
    raise exception 'PROOF 39 FAIL: attacks are not lit, so the refusal below would prove nothing';
  end if;
  select f.player_id into v_pl from public.fleets f where f.id = v_built[1];
  begin
    perform public.attack_for(v_pl2, v_fl2, v_built[1], null);
    raise exception 'PROOF 39 FAIL: a player attacked a player''s crown hull';
  exception when others then
    if sqlerrm not like '%E_HUMAN_TARGET%' then
      raise exception 'PROOF 39 FAIL: the wrong refusal: %', sqlerrm;
    end if;
  end;
  raise notice 'PASS: CROWN_NO_PVP — E_HUMAN_TARGET';

  if has_function_privilege('anon', 'public.crown_classes()', 'execute') or has_function_privilege('authenticated', 'public.crown_classes()', 'execute') then
    raise exception 'PROOF 39 FAIL: a client can call public.crown_classes';
  end if;
  raise notice 'PASS: CROWN_NO_CLIENT — server only';
end
$$;
