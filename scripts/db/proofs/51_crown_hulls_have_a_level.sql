-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 51 — CROWN AND PIRATE HULLS HAVE A LEVEL  (migration 0344, owner row 288; docs/WORLD_POWERS.md 2.3: "Crown and pirate hulls take a fixed level by knob, npc_ship_level 5")
--
--   0344's self-assert runs the writer narrowed to a probe house it made by hand (a migration never runs a real game step). This proof makes a cargo ship, a navy ship and a pirate ship by their REAL
--   makers (public.cargo_ships_commission, public.navy_commission, public.pirate_commission), beside a real merchant and a player who built a navy-class hull, runs the REAL writer over the WHOLE world as
--   its job does, and reads the level where the fight reads it (world.ship_stats, voyage.fleet_hulls). Everything rolls back with proof.mjs's transaction; the switches it needs are set here.
--
-- @pass CROWN_LVL_DARK     off: the writer over the world writes 0, no crown or pirate hull has a row, every hull of the three kinds is level 1 and her stats and fight side are as before the run
-- @pass CROWN_LVL_KINDS    lit: every hull of every crown house is written once (the answer is their count), the cargo, the navy and the pirate hull each read level 5 (her card's level too); a second run writes 0
-- @pass CROWN_LVL_OTHERS   lit and dark: every other row of ship_xp (merchants', players') is byte for byte the same; a merchant's hull and a player's navy-class hull are never written
-- @pass CROWN_LVL_STATS    lit, levels_bite on: handling, accuracy and sighting move by exactly 4 levels of their knobs on each kind, nothing else moves; the fight's side reads the same numbers; levels_bite off: no stat moves
-- @pass CROWN_LVL_KNOB     the knob turned to 3: every crown hull rewritten to level 3 (the answer is their count); back to 5: level 5 again
-- @pass CROWN_LVL_BACK     dark again: every row deleted (the answer is their count), every stat and fight side byte for byte as dark; the switch and knob end as the file shipped them
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_t      timestamptz := now();
  v_prt    uuid;
  v_lis    uuid;
  v_por    uuid;
  v_cargo  uuid;
  v_navy   uuid;
  v_pir    uuid;
  v_mer    uuid;
  v_hum    uuid;
  v_hfl    uuid;
  v_hsh    uuid;
  v_crown  int;
  v_n      int;
  v_others text;
  v_dark   jsonb;
  v_lit    jsonb;
  v_side0  jsonb;
  v_side1  jsonb;
  v_k      text;
  v_fl     uuid;
begin
  -- ── THE SCENE: the treasuries lit as on prod, one hull of each crown kind made by its real maker ──
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'navy_enabled', 'pirates_bite');
  update public.world_config set value = 'false'::jsonb where key in ('npc_ship_level_enabled', 'levels_bite');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  select g.nation_id, p.id into v_prt, v_lis
    from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code = 'PRT';
  v_por := public.pirate_capital();
  if v_prt is null or v_por is null then
    raise exception 'PROOF 51 FAIL: Portugal''s capital or the Brethren''s are not in this world';
  end if;
  update public.port_treasury t set reserve = 0 where t.port_id in (v_lis, v_por);
  perform public.treasury_post(v_lis, 'CROWN_CALL', 50000000, null, null, true);
  perform public.treasury_post(v_por, 'CROWN_CALL', 300000000, null, null, true);

  update public.cargo_fleet_sizes set ships = 1, read_at = v_t where nation_id = v_prt;
  if public.cargo_ships_commission(v_prt) < 1 then
    raise exception 'PROOF 51 FAIL: the real maker made no cargo ship';
  end if;
  v_cargo := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_prt order by c.ord limit 1);
  insert into public.navy_realms (nation_id, ships, read_at) values (v_prt, 25, v_t) on conflict (nation_id) do update set ships = 25, read_at = v_t;
  v_navy := public.navy_commission(v_prt, 1 + coalesce((select max(n.ord) from public.navy_ships n where n.nation_id = v_prt), 0), v_lis, public.refit_yard(v_lis), v_lis, v_t);
  v_pir := public.pirate_commission(1 + coalesce((select max(x.ord) from public.pirate_ships x), 0), v_por, public.refit_yard(v_por), v_t);
  if v_navy is null or v_pir is null then
    raise exception 'PROOF 51 FAIL: the real makers made no navy ship (%) or pirate ship (%)', v_navy, v_pir;
  end if;
  v_mer := (select nf.fleet_id from public.npc_fleets nf order by nf.roster_ord limit 1);
  insert into public.players (company_name, nation_id, ducats) values ('Proof 51 house', v_prt, 300000) returning id into v_hum;
  v_hfl := public.form_fleet(v_hum, 'Proof 51 fleet', v_lis);
  v_hsh := public.commission_ship(v_hum, v_hfl, public.wc_text('navy_ship_class'), 'Proof 51 galleon', true, true);
  insert into public.ship_xp (ship_id, xp) values (v_hsh, public.level_points(2));   -- a player's earned experience: never the writer's
  if v_mer is null or not exists (select 1 from public.ship_xp x join public.ships s on s.id = x.ship_id where s.fleet_id = v_mer) then
    raise exception 'PROOF 51 FAIL: no merchant with a fixed level in this world';
  end if;
  if public.crown_house(v_hum) or public.crown_house((select f.player_id from public.fleets f where f.id = v_mer))
     or not public.crown_house((select f.player_id from public.fleets f where f.id = v_cargo))
     or not public.crown_house((select f.player_id from public.fleets f where f.id = v_navy))
     or not public.crown_house((select f.player_id from public.fleets f where f.id = v_pir)) then
    raise exception 'PROOF 51 FAIL: public.crown_house does not answer the scene as the design says';
  end if;

  v_crown := (select count(*) from public.ships s where public.crown_house(s.player_id));
  create temp table hulls_51 on commit drop as
    select s.id, s.fleet_id, f.kind from public.ships s
      join (values (v_cargo, 'cargo'), (v_navy, 'navy'), (v_pir, 'pirate')) f(fleet, kind) on f.fleet = s.fleet_id;
  if (select count(*) from hulls_51) <> 3 then
    raise exception 'PROOF 51 FAIL: the three kinds are not one hull each: %', (select count(*) from hulls_51);
  end if;
  v_others := (select md5(coalesce(string_agg(x.ship_id::text || ':' || x.xp::text, ',' order by x.ship_id), '')) from public.ship_xp x join public.ships s on s.id = x.ship_id where not public.crown_house(s.player_id));
  v_dark := (select jsonb_object_agg(h.kind, world.ship_stats(h.id)) from hulls_51 h);
  v_side0 := (select jsonb_object_agg(h.kind, voyage.fleet_hulls(h.fleet_id)) from hulls_51 h);

  -- ── DARK ──
  v_n := public.crown_hull_level_fix();
  if v_n <> 0 or exists (select 1 from public.ship_xp x join public.ships s on s.id = x.ship_id where public.crown_house(s.player_id))
     or (select jsonb_object_agg(h.kind, world.ship_stats(h.id)) from hulls_51 h) <> v_dark
     or (select jsonb_object_agg(h.kind, voyage.fleet_hulls(h.fleet_id)) from hulls_51 h) <> v_side0
     or exists (select 1 from hulls_51 h where (world.ship_view(h.id) ->> 'level')::int is distinct from 1) then
    raise exception 'PROOF 51 FAIL: dark, the writer wrote % or a crown hull reads otherwise than before', v_n;
  end if;
  raise notice 'PASS: CROWN_LVL_DARK — 0 written, % crown hulls with no row, stats and fight sides byte for byte', v_crown;

  -- ── LIT ──
  update public.world_config set value = 'true'::jsonb where key = 'npc_ship_level_enabled';
  v_n := public.crown_hull_level_fix();
  if v_n <> v_crown then
    raise exception 'PROOF 51 FAIL: lit, the writer wrote % rows, not the % crown hulls', v_n, v_crown;
  end if;
  if exists (select 1 from hulls_51 h left join public.ship_xp x on x.ship_id = h.id where x.xp is distinct from public.level_points(5) or public.level_from_points(x.xp) <> 5)
     or exists (select 1 from public.ships s left join public.ship_xp x on x.ship_id = s.id where public.crown_house(s.player_id) and x.xp is distinct from public.level_points(5)) then
    raise exception 'PROOF 51 FAIL: lit, a crown hull is not at level 5';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'levels_bite';
  if exists (select 1 from hulls_51 h where (world.ship_view(h.id) ->> 'level')::int is distinct from 5) then
    raise exception 'PROOF 51 FAIL: her card does not read level 5: %', (select jsonb_object_agg(h.kind, world.ship_view(h.id) -> 'level') from hulls_51 h);
  end if;
  v_n := public.crown_hull_level_fix();
  if v_n <> 0 then
    raise exception 'PROOF 51 FAIL: a second run wrote again';
  end if;
  raise notice 'PASS: CROWN_LVL_KINDS — % written (every crown hull), cargo, navy and pirate at level 5, a second run 0', v_crown;

  if (select md5(coalesce(string_agg(x.ship_id::text || ':' || x.xp::text, ',' order by x.ship_id), '')) from public.ship_xp x join public.ships s on s.id = x.ship_id where not public.crown_house(s.player_id)) <> v_others
     or (select x.xp from public.ship_xp x where x.ship_id = v_hsh) <> public.level_points(2) then
    raise exception 'PROOF 51 FAIL: lit, a merchant''s or a player''s experience moved';
  end if;

  -- the stats, where the fight reads them
  v_lit := (select jsonb_object_agg(h.kind, world.ship_stats(h.id)) from hulls_51 h);
  v_side1 := (select jsonb_object_agg(h.kind, voyage.fleet_hulls(h.fleet_id)) from hulls_51 h);
  foreach v_k in array array['cargo', 'navy', 'pirate'] loop
    if (v_lit -> v_k ->> 'handling')::numeric - (v_dark -> v_k ->> 'handling')::numeric <> 4 * public.wc_num('ship_level_handling_per_level')
       or (v_lit -> v_k ->> 'accuracy')::numeric - (v_dark -> v_k ->> 'accuracy')::numeric <> 4 * public.wc_num('ship_level_accuracy_per_level')
       or (v_lit -> v_k ->> 'sighting')::numeric - (v_dark -> v_k ->> 'sighting')::numeric <> 4 * public.wc_num('ship_level_sighting_per_level')
       or (v_lit -> v_k) - 'handling' - 'accuracy' - 'sighting' <> (v_dark -> v_k) - 'handling' - 'accuracy' - 'sighting' then
      raise exception 'PROOF 51 FAIL: % does not move by exactly four levels of the knobs: dark %, lit %', v_k, v_dark -> v_k, v_lit -> v_k;
    end if;
    if (v_side1 -> v_k -> 0 ->> 'accuracy')::numeric <> (v_lit -> v_k ->> 'accuracy')::numeric
       or (v_side1 -> v_k -> 0 ->> 'sighting')::numeric <> (v_lit -> v_k ->> 'sighting')::numeric
       or (v_side1 -> v_k -> 0 ->> 'accuracy')::numeric - (v_side0 -> v_k -> 0 ->> 'accuracy')::numeric <> 4 * public.wc_num('ship_level_accuracy_per_level') then
      raise exception 'PROOF 51 FAIL: the fight''s side of % does not read the level: dark %, lit %', v_k, v_side0 -> v_k, v_side1 -> v_k;
    end if;
  end loop;
  update public.world_config set value = 'false'::jsonb where key = 'levels_bite';
  if (select jsonb_object_agg(h.kind, world.ship_stats(h.id)) from hulls_51 h) <> v_dark then
    raise exception 'PROOF 51 FAIL: levels_bite off, a crown hull''s stats moved';
  end if;
  raise notice 'PASS: CROWN_LVL_STATS — +% handling, +% accuracy, +% sighting on each kind, the fight side the same; levels_bite off nothing',
    4 * public.wc_num('ship_level_handling_per_level'), 4 * public.wc_num('ship_level_accuracy_per_level'), 4 * public.wc_num('ship_level_sighting_per_level');

  -- ── THE KNOB ──
  update public.world_config set value = to_jsonb(3) where key = 'npc_ship_level';
  v_n := public.crown_hull_level_fix();
  if v_n <> v_crown or exists (select 1 from public.ships s left join public.ship_xp x on x.ship_id = s.id where public.crown_house(s.player_id) and public.level_from_points(coalesce(x.xp, 0)) <> 3) then
    raise exception 'PROOF 51 FAIL: the knob at 3: % written, not every crown hull at level 3', v_n;
  end if;
  update public.world_config set value = to_jsonb(5) where key = 'npc_ship_level';
  v_n := public.crown_hull_level_fix();   -- its own statement: the operands of an OR have no order
  if v_n <> v_crown or exists (select 1 from hulls_51 h left join public.ship_xp x on x.ship_id = h.id where public.level_from_points(coalesce(x.xp, 0)) <> 5) then
    raise exception 'PROOF 51 FAIL: the knob back at 5 is not level 5 again';
  end if;
  raise notice 'PASS: CROWN_LVL_KNOB — 3: % rewritten at level 3; 5: level 5 again', v_n;

  -- ── DARK AGAIN ──
  update public.world_config set value = 'false'::jsonb where key = 'npc_ship_level_enabled';
  update public.world_config set value = 'true'::jsonb where key = 'levels_bite';
  v_n := public.crown_hull_level_fix();
  if v_n <> v_crown or exists (select 1 from public.ship_xp x join public.ships s on s.id = x.ship_id where public.crown_house(s.player_id)) then
    raise exception 'PROOF 51 FAIL: dark again, % deleted, not the % crown hulls', v_n, v_crown;
  end if;
  if (select jsonb_object_agg(h.kind, world.ship_stats(h.id)) from hulls_51 h) <> v_dark
     or (select jsonb_object_agg(h.kind, voyage.fleet_hulls(h.fleet_id)) from hulls_51 h) <> v_side0 then
    raise exception 'PROOF 51 FAIL: dark again, a crown hull does not read as before';
  end if;
  if (select md5(coalesce(string_agg(x.ship_id::text || ':' || x.xp::text, ',' order by x.ship_id), '')) from public.ship_xp x join public.ships s on s.id = x.ship_id where not public.crown_house(s.player_id)) <> v_others then
    raise exception 'PROOF 51 FAIL: dark again, a merchant''s or a player''s experience moved';
  end if;
  raise notice 'PASS: CROWN_LVL_OTHERS — every other ship_xp row the same lit and dark; the merchant and the player''s galleon never written';
  update public.world_config set value = 'false'::jsonb where key = 'levels_bite';
  if public.wc('npc_ship_level_enabled') <> 'false'::jsonb or public.wc_num('npc_ship_level') <> 5 then
    raise exception 'PROOF 51 FAIL: the switch and knob do not end as shipped';
  end if;
  raise notice 'PASS: CROWN_LVL_BACK — % deleted, stats and fight sides as dark; switch false, knob 5', v_n;
end
$$;
