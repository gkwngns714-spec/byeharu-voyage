-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 171 - EACH LEVEL OPENS SOMETHING  (migration 0468; docs/design/playable-2026-11-22.md P2; docs/LEVELS.md section 7;
--             docs/dev-log/2026-11-22-level-unlocks.md)
--
--   The migration's self-assert holds each figure to its pre-image on copies. This proof plays the doors a company meets them at, dark and
--   lit: the route cap's own trigger, the caps a fleet reads (public.earned_caps, lit room), the yard's order door, and the page's list
--   (world.levels). Her Trading level is the mark she was last paid for (public.house_level_marks), set here. Rolled back by proof.mjs.
--
-- @pass LU_DARK     dark: a company paid for Trading 20 keeps the knob's route cap (the trigger refuses one more), her ships a fleet and
--                   her order's fee are a new company's, and world.levels lists no Trading step
-- @pass LU_ROUTES   lit: at Trading 2 the trigger keeps one route past the dark cap and refuses the next; at 19 five past it
-- @pass LU_SHIPS    lit: at Trading 4 public.earned_caps gives one more ship a fleet (never above fleet_ship_top); at 3 none
-- @pass LU_FEE      lit: at Trading 20 the yard's order door charges labour + materials + a fee 80 % under the knob's
-- @pass LU_LISTED   lit: world.levels lists the 17 Trading steps with their running totals; each Trading level 2-20 gives one thing
-- @pass LU_MERCHANT a merchant's route cap and caps are the same dark and lit
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a   constant uuid := '00000000-0468-4000-8000-0000000000a1';
  c_b   constant uuid := '00000000-0468-4000-8000-0000000000b1';
  v_lis uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a   uuid;
  v_b   uuid;
  v_npc uuid;
  v_cap int;
  v_s0  int;
  v_s1  int;
  v_q0  jsonb;
  v_q1  jsonb;
  v_r   jsonb;
  v_p0  bigint;
  v_p1  bigint;
  v_on  text;
  v_off text;
  v_n   int;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('level_perks_on', 'fleet_room_bite', 'yard_order_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key = 'level_unlocks_enabled';
  v_a := public.new_house(c_a, 'Casa dos Degraus 171', 'PRT');
  v_b := public.new_house(c_b, 'Casa das Rotas 171', 'PRT');
  v_npc := public.new_house(null, 'Casa Mercante 171', 'PRT', 'LIS', 'Mercante', 'barca', 'Mercante', 5000000, true);
  insert into public.house_level_marks (player_id, track, level) values (v_a, 'trading', 20), (v_b, 'trading', 1)
    on conflict (player_id, track) do update set level = excluded.level;
  update public.players set ducats = 100000000 where id in (v_a, v_b);

  -- ── LU_DARK ──
  v_cap := public.standing_route_max_for(v_b);
  if public.standing_route_max_for(v_a) <> v_cap
     or (public.earned_caps(v_a) ->> 'fleet_ship_max') <> (public.earned_caps(v_b) ->> 'fleet_ship_max')
     or public.hull_order_price(v_a, v_lis, 'barca') is distinct from public.hull_order_price(v_b, v_lis, 'barca') then
    raise exception 'PROOF 171 FAILED: dark, Trading 20 moved a figure: routes % / %, caps % / %', public.standing_route_max_for(v_a), v_cap,
      public.earned_caps(v_a), public.earned_caps(v_b);
  end if;
  for i in 1 .. v_cap loop
    insert into public.standing_routes (player_id, name) values (v_a, 'Rota ' || i);
  end loop;
  begin
    insert into public.standing_routes (player_id, name) values (v_a, 'Rota a mais');
    raise exception 'PROOF 171 FAILED: dark, a route past the cap of % was kept at Trading 20', v_cap;
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'E_ROUTE_CAP%' then raise; end if;
  end;
  perform cmd.assume_identity(c_a);
  if exists (select 1 from jsonb_array_elements(world.levels() -> 'level_skills' -> 'skills') e cross join jsonb_array_elements(e -> 'benefits') b
              where e ->> 'code' = 'trading' and b ->> 'kind' = 'perk') then
    raise exception 'PROOF 171 FAILED: dark, world.levels lists a Trading step';
  end if;
  raise notice 'PASS: LU_DARK — at Trading 20, dark: route cap % (the trigger refused one more), ships a fleet %, the order''s fee a new company''s; no Trading step listed.',
    v_cap, public.earned_caps(v_a) ->> 'fleet_ship_max';

  update public.world_config set value = 'true'::jsonb where key = 'level_unlocks_enabled';

  -- ── LU_ROUTES ──
  update public.house_level_marks set level = 2 where player_id = v_b and track = 'trading';
  for i in 1 .. v_cap + 1 loop
    insert into public.standing_routes (player_id, name) values (v_b, 'Rota ' || i);
  end loop;
  begin
    insert into public.standing_routes (player_id, name) values (v_b, 'Rota a mais');
    raise exception 'PROOF 171 FAILED: lit, at Trading 2 two routes past the dark cap were kept';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'E_ROUTE_CAP%' then raise; end if;
  end;
  update public.house_level_marks set level = 19 where player_id = v_b and track = 'trading';
  if public.standing_route_max_for(v_b) <> v_cap + 5 then
    raise exception 'PROOF 171 FAILED: lit, at Trading 19 the cap is %, not % + 5', public.standing_route_max_for(v_b), v_cap;
  end if;
  raise notice 'PASS: LU_ROUTES — lit: Trading 2 kept % routes and refused the next; Trading 19: cap %.', v_cap + 1, v_cap + 5;

  -- ── LU_SHIPS ──
  update public.house_level_marks set level = 3 where player_id = v_b and track = 'trading';
  v_s0 := (public.earned_caps(v_b) ->> 'fleet_ship_max')::int;
  update public.house_level_marks set level = 4 where player_id = v_b and track = 'trading';
  v_s1 := (public.earned_caps(v_b) ->> 'fleet_ship_max')::int;
  if v_s1 <> least(public.wc_int('fleet_ship_top'), v_s0 + 1) or v_s0 > public.wc_int('fleet_ship_top') then
    raise exception 'PROOF 171 FAILED: lit, ships a fleet % at Trading 3 and % at Trading 4 (top %)', v_s0, v_s1, public.wc_int('fleet_ship_top');
  end if;
  raise notice 'PASS: LU_SHIPS — lit: ships a fleet % at Trading 3, % at Trading 4 (top %).', v_s0, v_s1, public.wc_int('fleet_ship_top');

  -- ── LU_FEE ──
  v_q0 := public.hull_order_price(v_b, v_lis, 'barca');   -- Trading 4: no fee step yet
  v_q1 := public.hull_order_price(v_a, v_lis, 'barca');   -- Trading 20: 80 % off the fee
  if v_q0 is null or v_q1 is null or (v_q1 ->> 'labour') <> (v_q0 ->> 'labour') or (v_q1 ->> 'materials') <> (v_q0 ->> 'materials')
     or (v_q0 ->> 'fee')::bigint <> round(((v_q0 ->> 'labour')::bigint + (v_q0 ->> 'materials')::bigint) * public.wc_num('yard_order_fee_pct') / 100.0)::bigint
     or (v_q1 ->> 'fee')::bigint <> round(((v_q1 ->> 'labour')::bigint + (v_q1 ->> 'materials')::bigint) * public.wc_num('yard_order_fee_pct') / 100.0 * 0.2)::bigint then
    raise exception 'PROOF 171 FAILED: lit, the order of a barca at Trading 4 is % and at Trading 20 %', v_q0, v_q1;
  end if;
  select p.ducats into v_p0 from public.players p where p.id = v_a;
  perform cmd.assume_identity(c_a);
  v_r := cmd.order_hull(v_lis, 'barca');
  select p.ducats into v_p1 from public.players p where p.id = v_a;
  if coalesce((v_r ->> 'ok')::boolean, false) is not true or (v_r ->> 'price')::bigint <> (v_q1 ->> 'price')::bigint or v_p0 - v_p1 <> (v_q1 ->> 'price')::bigint then
    raise exception 'PROOF 171 FAILED: lit, the order door at Trading 20 answered % and took % (the quote %)', v_r, v_p0 - v_p1, v_q1;
  end if;
  raise notice 'PASS: LU_FEE — a barca''s order: fee % at Trading 4, % at Trading 20; the door took exactly %.', v_q0 ->> 'fee', v_q1 ->> 'fee', v_q1 ->> 'price';

  -- ── LU_LISTED ──
  perform cmd.assume_identity(c_a);
  v_r := (select e -> 'benefits' from jsonb_array_elements(world.levels() -> 'level_skills' -> 'skills') e where e ->> 'code' = 'trading');
  select count(*) into v_n from jsonb_array_elements(v_r) b where b ->> 'kind' = 'perk';
  if v_n <> 17
     or exists (select 1 from jsonb_array_elements(v_r) b where b ->> 'kind' = 'perk'
                   and (b ->> 'total')::numeric <> (select sum(k.amount) from public.level_perks k where k.perk = b ->> 'perk' and k.level <= (b ->> 'level')::int))
     or exists (select 1 from generate_series(2, 20) g(l)
                 where (select count(*) from jsonb_array_elements(v_r) b where b ->> 'kind' in ('perk', 'fleet') and (b ->> 'level')::int = g.l) <> 1) then
    raise exception 'PROOF 171 FAILED: lit, world.levels lists % Trading step(s), or a level from 2 to 20 gives not exactly one thing: %', v_n, v_r;
  end if;
  raise notice 'PASS: LU_LISTED — world.levels lists the 17 Trading steps with their totals; every Trading level 2-20 gives one thing (a step or a fleet).';

  -- ── LU_MERCHANT ──
  v_on := public.standing_route_max_for(v_npc) || ':' || public.earned_caps(v_npc)::text || ':' || public.level_perk(v_npc, 'yard_fee');
  update public.world_config set value = 'false'::jsonb where key = 'level_unlocks_enabled';
  v_off := public.standing_route_max_for(v_npc) || ':' || public.earned_caps(v_npc)::text || ':' || public.level_perk(v_npc, 'yard_fee');
  if v_on <> v_off then
    raise exception 'PROOF 171 FAILED: a merchant''s caps moved with the switch: % against %', v_on, v_off;
  end if;
  raise notice 'PASS: LU_MERCHANT — a merchant reads % lit and dark.', v_on;
end $p$;
