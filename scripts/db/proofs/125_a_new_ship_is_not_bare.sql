-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 125 — A NEW SHIP IS NOT BARE  (migration 0424: starter gear sold at every harbour)
--
--   The owner, 2026-11-15: "and in port, there should be a beginner's gear for ships." The migration's self-assert holds the pieces
--   and the refusals on stubs. This proof plays it as a new player meets it: a company founded through public.new_house (its barca
--   docked at Lisbon, the founding purse) reads the Gear face, buys and fits through cmd.buy_starter, sees its ship read change
--   in world.fleets(), pays the city of Lisbon, sails 2,000 miles and finds the canvas worn, cannot stack a second piece, cannot
--   make one, and cannot turn one back into coin. A merchant founded the same way is refused. Rolled back by the runner.
--
-- @pass STARTER_FACE        a new company's face: three pieces with their prices, the barca has no Low place, the fleet is at a harbour
-- @pass STARTER_BUY_FIT     guns and sails bought: her purse falls by the two prices, Lisbon's purse rises by them, world.fleets() reads the ship's attack and speed up by the pieces
-- @pass STARTER_ONE_A_HULL  a second sails is refused (E_STARTER_ONE) with a free Mid place, and FIT from the store cannot stack one either
-- @pass STARTER_WEARS       2,000 miles wear the starter sails by gear_wear_per_1000nm a thousand miles, as any canvas
-- @pass STARTER_NO_PROFIT   UNFIT stores the piece for nothing, no workshop makes or lists one, and no hull recipe or promotion takes one
-- @pass STARTER_MERCHANT    a merchant is refused (E_NOT_IN_USE) and her founded hull carries no starter piece
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0424-4000-8000-0000000000a1';
  v_a     uuid;
  v_npc   uuid;
  v_fl    uuid;
  v_nfl   uuid;
  v_sh    uuid;
  v_lis   uuid;
  v_voy   uuid;
  v_r     jsonb;
  v_ship0 jsonb;
  v_ship1 jsonb;
  v_p0    bigint;
  v_c0    bigint;
  v_wear  numeric;
  v_err   text;
  v_price bigint := (select sum(price) from public.starter_gear where item_code in ('starter-guns', 'starter-sails'));
begin
  select id into v_lis from public.ports where code = 'LIS';
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'gear_wear_bite') and value is distinct from 'true'::jsonb;

  -- ── STARTER_FACE ──
  v_a := public.new_house(c_a, 'Casa Inicial 125', 'PRT');
  select id into v_fl from public.fleets where player_id = v_a;
  select id into v_sh from public.ships where fleet_id = v_fl order by is_flagship desc limit 1;
  perform cmd.assume_identity(c_a);
  v_r := world.starter_gear(v_fl);
  if jsonb_array_length(v_r -> 'items') <> 3 or not (v_r ->> 'here')::boolean or v_r ->> 'port' is null
     or (select jsonb_object_agg(i ->> 'code', (i ->> 'price')::bigint) from jsonb_array_elements(v_r -> 'items') i)
        <> (select jsonb_object_agg(item_code, price) from public.starter_gear)
     or (v_r -> 'ships' -> 0 -> 'pieces') <> '{"starter-guns": "open", "starter-sails": "open", "starter-planking": "no_place"}'::jsonb then
    raise exception 'PROOF 125 FAILED: a new company''s Gear face is %', v_r;
  end if;
  raise notice 'PASS: STARTER_FACE — at %, three pieces (%), her % has places for the guns and the sails and none for the planking.',
    v_r ->> 'port', (select string_agg((i ->> 'name') || ' ' || (i ->> 'price'), ', ') from jsonb_array_elements(v_r -> 'items') i), v_r -> 'ships' -> 0 ->> 'class';

  -- ── STARTER_BUY_FIT ──
  select p.ducats into v_p0 from public.players p where p.id = v_a;
  v_c0 := public.treasury_balance(v_lis);
  select s into v_ship0 from jsonb_array_elements(world.fleets()) f, jsonb_array_elements(f -> 'ships') s where s ->> 'id' = v_sh::text;
  v_r := cmd.buy_starter(v_fl, v_sh, 'starter-guns');
  if not coalesce((v_r ->> 'ok')::boolean, false) then raise exception 'PROOF 125 FAILED: the guns were refused: %', v_r; end if;
  v_r := cmd.buy_starter(v_fl, v_sh, 'starter-sails');
  if not coalesce((v_r ->> 'ok')::boolean, false) then raise exception 'PROOF 125 FAILED: the sails were refused: %', v_r; end if;
  select s into v_ship1 from jsonb_array_elements(world.fleets()) f, jsonb_array_elements(f -> 'ships') s where s ->> 'id' = v_sh::text;
  if (select p.ducats from public.players p where p.id = v_a) <> v_p0 - v_price
     or public.treasury_balance(v_lis) - v_c0 <> v_price
     or (v_ship1 ->> 'attack')::numeric - (v_ship0 ->> 'attack')::numeric <> (select delta from public.item_effects where item_code = 'starter-guns' and stat = 'attack')
     or abs((v_ship1 ->> 'speed')::numeric - (v_ship0 ->> 'speed')::numeric) < 0.01
     or not exists (select 1 from jsonb_array_elements(v_ship1 -> 'fittings') x where x ->> 'code' = 'starter-sails') then
    raise exception 'PROOF 125 FAILED: purse % -> %, Lisbon % -> %, attack % -> %, speed % -> %',
      v_p0, (select p.ducats from public.players p where p.id = v_a), v_c0, public.treasury_balance(v_lis),
      v_ship0 ->> 'attack', v_ship1 ->> 'attack', v_ship0 ->> 'speed', v_ship1 ->> 'speed';
  end if;
  raise notice 'PASS: STARTER_BUY_FIT — % ducats from her purse to Lisbon''s; her ship reads attack % -> %, speed % -> % kn.',
    v_price, v_ship0 ->> 'attack', v_ship1 ->> 'attack', v_ship0 ->> 'speed', v_ship1 ->> 'speed';

  -- ── STARTER_ONE_A_HULL ──
  v_r := cmd.buy_starter(v_fl, v_sh, 'starter-sails');
  if v_r ->> 'error_code' <> 'E_STARTER_ONE' then raise exception 'PROOF 125 FAILED: a second sails was not refused one-a-hull: %', v_r; end if;
  perform cmd.do_unfit(v_fl, jsonb_build_object('item', 'starter-sails'));
  v_r := cmd.buy_starter(v_fl, v_sh, 'starter-sails');
  begin
    perform cmd.do_fit(v_fl, jsonb_build_object('item', 'starter-sails'));
    v_err := 'stacked';
  exception when others then
    v_err := split_part(sqlerrm, ':', 1);
  end;
  if v_err <> 'E_STARTER_ONE' or (select count(*) from public.fitted_units u where u.ship_id = v_sh and u.item_code = 'starter-sails') <> 1 then
    raise exception 'PROOF 125 FAILED: FIT from the store gave % and the hull carries % starter sails', v_err,
      (select count(*) from public.fitted_units u where u.ship_id = v_sh and u.item_code = 'starter-sails');
  end if;
  raise notice 'PASS: STARTER_ONE_A_HULL — a second sails with a Mid place free: E_STARTER_ONE; FIT of the stored one: %.', v_err;

  -- ── STARTER_WEARS ──
  v_voy := gen_random_uuid();
  insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
  values (v_voy, v_fl, v_a, '[]', 2000, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_lis);
  perform public.wear_units_for(v_fl, v_voy);
  select u.wear into v_wear from public.fitted_units u where u.ship_id = v_sh and u.item_code = 'starter-sails';
  if v_wear is null or v_wear <> round(2 * public.wc_num('gear_wear_per_1000nm') * (1 - public.level_perk(v_a, 'gear_wear') / 100), 2) then
    raise exception 'PROOF 125 FAILED: 2,000 miles wore the starter sails %', v_wear;
  end if;
  raise notice 'PASS: STARTER_WEARS — 2,000 miles: the starter sails are % worn, as any canvas.', v_wear;

  -- ── STARTER_NO_PROFIT ──
  select p.ducats into v_p0 from public.players p where p.id = v_a;
  perform cmd.do_unfit(v_fl, jsonb_build_object('item', 'starter-guns'));
  begin
    perform cmd.do_make(v_fl, jsonb_build_object('item', 'starter-guns'));
    v_err := 'made';
  exception when others then
    v_err := split_part(sqlerrm, ':', 1);
  end;
  if (select p.ducats from public.players p where p.id = v_a) <> v_p0
     or (select qty from public.player_items where player_id = v_a and port_id = v_lis and item_code = 'starter-guns') <> 1
     or v_err !~ '^E_'
     or exists (select 1 from jsonb_array_elements(world.workstation(v_lis, v_fl) -> 'items') i where i ->> 'code' like 'starter-%')
     or exists (select 1 from public.hull_recipe_items where item_code like 'starter-%')
     or exists (select 1 from public.promotion_items where item_code like 'starter-%') then
    raise exception 'PROOF 125 FAILED: UNFIT moved her purse, or a starter piece is made (%), listed, a hull''s part or a promotion', v_err;
  end if;
  raise notice 'PASS: STARTER_NO_PROFIT — UNFIT put the guns in her Lisbon store and her purse stayed %; MAKE refused (%); no workshop lists one; no hull or promotion takes one.', v_p0, v_err;

  -- ── STARTER_MERCHANT ──
  v_npc := public.new_house(null, 'Casa Mercante 125', 'PRT', 'LIS', 'Mercante', 'barca', 'Mercante', 5000000, true);
  select id into v_nfl from public.fleets where player_id = v_npc;
  begin
    perform public.buy_starter_for(v_npc, v_nfl, (select id from public.ships where fleet_id = v_nfl limit 1), 'starter-guns');
    v_err := 'sold';
  exception when others then
    v_err := split_part(sqlerrm, ':', 1);
  end;
  if v_err <> 'E_NOT_IN_USE' or exists (select 1 from public.fitted_units u join public.ships s on s.id = u.ship_id where s.player_id = v_npc and u.item_code like 'starter-%') then
    raise exception 'PROOF 125 FAILED: a merchant was sold a starter piece (%), or her hull carries one', v_err;
  end if;
  raise notice 'PASS: STARTER_MERCHANT — a merchant: %; her founded hull carries no starter piece.', v_err;
end
$p$;
