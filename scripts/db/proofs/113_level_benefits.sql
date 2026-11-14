-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 113 — A LEVEL GIVES SOMETHING AS IT RISES  (migration 0417, docs/LEVELS.md)
--
--   The migration's self-assert holds every benefit to its figure on stubs. This proof plays the doors a player meets them at:
--   she resupplies through cmd.issue and pays the discounted price the quote names; the route cap's own trigger lets her keep
--   one more route at Routes level 8 and not before; a real share earns her more regard; and a merchant pays what she paid.
--   Her levels are set by rows of public.level_xp written here (the levels themselves are proof 107's subject). Rolled back.
--
-- @pass PERK_MERCHANT_SAME   a merchant's supplies and repair prices and her route cap are the same with level_perks_on true and false, and public.level_perk answers her 0
-- @pass PERK_SUPPLIES_DOOR   a company at Supplies level 20 resupplies through cmd.issue: the purse falls by public.stores_cost's figure, which is the knob-off price less the steps' sum
-- @pass PERK_ROUTE_ROOM      the route cap's trigger refuses one route past the cap at Routes level 7 and accepts it at level 8; at level 16 one more
-- @pass PERK_SHARE_REGARD    a real share bought at Investment level 20 earns the regard of the same share at level 1 times (1 + the steps' sum %)
-- @pass PERK_LISTED          world.levels() lists every step at its level with its running total, and none while level_perks_on is false
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a    constant uuid := '00000000-0417-4000-8000-0000000000a1';
  c_b    constant uuid := '00000000-0417-4000-8000-0000000000b1';
  v_npc  uuid;
  v_nfl  uuid;
  v_a    uuid;
  v_b    uuid;
  v_fl   uuid;
  v_lis  uuid;
  v_top  int := public.level_from_points(1000000000000);
  v_sum  numeric;
  v_on   text;
  v_off  text;
  v_cap  int;
  v_n    int;
  v_p0   bigint;
  v_p1   bigint;
  v_cost bigint;
  v_full bigint;
  v_r    jsonb;
  v_ra   numeric;
  v_rb   numeric;
  v_nat  uuid;
begin
  select id into v_lis from public.ports where code = 'LIS';
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'regard_enabled', 'level_perks_on', 'level_skills_on') and value is distinct from 'true'::jsonb;

  -- ── PERK_MERCHANT_SAME ──
  v_npc := public.new_house(null, 'Casa Mercante 113', 'PRT', 'LIS', 'Mercante', 'barca', 'Mercante', 5000000, true);
  select id into v_nfl from public.fleets where player_id = v_npc;
  v_on := public.stores_cost(v_npc, 40, 10) || ':' || public.fleet_repair_cost(v_nfl, 500, null) || ':' || public.standing_route_max_for(v_npc);
  update public.world_config set value = 'false'::jsonb where key = 'level_perks_on';
  v_off := public.stores_cost(v_npc, 40, 10) || ':' || public.fleet_repair_cost(v_nfl, 500, null) || ':' || public.standing_route_max_for(v_npc);
  update public.world_config set value = 'true'::jsonb where key = 'level_perks_on';
  if v_on <> v_off or exists (select 1 from public.level_perks k where public.level_perk(v_npc, k.perk) <> 0)
     or exists (select 1 from public.level_xp x where x.player_id = v_npc) then
    raise exception 'PROOF 113 FAILED: a merchant''s prices or cap moved with the knob (% against %), or a benefit answers her', v_on, v_off;
  end if;
  raise notice 'PASS: PERK_MERCHANT_SAME — a merchant: supplies : hull repair : route cap = % with the knob on and off; every benefit answers her 0; she has no experience row.', v_on;

  -- ── PERK_SUPPLIES_DOOR ──
  v_a := public.new_house(c_a, 'Casa dos Passos 113', 'PRT');
  select id into v_fl from public.fleets where player_id = v_a;
  -- her levels, as rows the book agrees with (one book row a level, then the experience row that names it): a real grant after this must chain
  insert into public.level_book (player_id, skill, seq, activity, xp, xp_after)
  select v_a, s.code, 1, (select min(a.code) from public.level_activities a where a.skill = s.code), public.level_points(v_top)::int, public.level_points(v_top)::int
    from public.level_skills s where s.kept = 'book';
  insert into public.level_xp (player_id, skill, xp, seq) select v_a, s.code, public.level_points(v_top)::int, 1 from public.level_skills s where s.kept = 'book';
  perform cmd.assume_identity(c_a);
  select sum(k.amount) into v_sum from public.level_perks k where k.perk = 'supplies_price';
  update public.ships set water_t = 0, food_t = 0 where fleet_id = v_fl;
  select ducats into v_p0 from public.players where id = v_a;
  v_r := cmd.issue(v_fl, 'PROVISION FULL');
  select ducats into v_p1 from public.players where id = v_a;
  select (e.payload ->> 'cost')::bigint, public.stores_cost(v_a, (e.payload ->> 'water_t')::numeric, (e.payload ->> 'food_t')::numeric)
    into v_cost, v_n from public.events e where e.player_id = v_a and e.kind = 'PROVISIONED' order by e.created_at desc, e.id desc limit 1;
  update public.world_config set value = 'false'::jsonb where key = 'level_perks_on';
  select public.stores_cost(v_a, (e.payload ->> 'water_t')::numeric, (e.payload ->> 'food_t')::numeric)
    into v_full from public.events e where e.player_id = v_a and e.kind = 'PROVISIONED' order by e.created_at desc, e.id desc limit 1;
  update public.world_config set value = 'true'::jsonb where key = 'level_perks_on';
  if v_cost is null or v_cost <= 0 or v_p0 - v_p1 <> v_cost or v_cost <> v_n or v_cost >= v_full or abs(v_cost - v_full * (1 - v_sum / 100)) > 1 then
    raise exception 'PROOF 113 FAILED: she paid % for supplies (purse % -> %); the quote is %, the knob-off price %, the steps'' sum % %%: %', v_cost, v_p0, v_p1, v_n, v_full, v_sum, v_r;
  end if;
  raise notice 'PASS: PERK_SUPPLIES_DOOR — at Supplies level % she resupplied through the door for % d. (her purse fell by exactly that; public.stores_cost quotes the same); with the knob off the same supplies are % d.: % %% less.', v_top, v_cost, v_full, v_sum;

  -- ── PERK_ROUTE_ROOM ──
  v_b := public.new_house(c_b, 'Casa das Rotas 113', 'PRT');
  insert into public.level_xp (player_id, skill, xp) values (v_b, 'routes', public.level_points(8)::int - 1);
  v_cap := public.standing_route_max_for(v_b);
  for i in 1 .. v_cap loop
    insert into public.standing_routes (player_id, name) values (v_b, 'Rota ' || i);
  end loop;
  begin
    insert into public.standing_routes (player_id, name) values (v_b, 'Rota a mais');
    raise exception 'PROOF 113 FAILED: at Routes level 7 a route past the cap of % was kept', v_cap;
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'E_ROUTE_CAP%' then raise; end if;
  end;
  update public.level_xp set xp = public.level_points(8)::int where player_id = v_b and skill = 'routes';
  insert into public.standing_routes (player_id, name) values (v_b, 'Rota do nivel 8');
  begin
    insert into public.standing_routes (player_id, name) values (v_b, 'Rota a mais');
    raise exception 'PROOF 113 FAILED: at Routes level 8 two routes past the old cap were kept';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'E_ROUTE_CAP%' then raise; end if;
  end;
  update public.level_xp set xp = public.level_points(16)::int where player_id = v_b and skill = 'routes';
  insert into public.standing_routes (player_id, name) values (v_b, 'Rota do nivel 16');
  if public.standing_route_max_for(v_b) <> v_cap + 2 or (select count(*) from public.standing_routes r where r.player_id = v_b) <> v_cap + 2 then
    raise exception 'PROOF 113 FAILED: at Routes level 16 the cap is %, not % + 2', public.standing_route_max_for(v_b), v_cap;
  end if;
  raise notice 'PASS: PERK_ROUTE_ROOM — the cap is % at Routes level 7 and the trigger refused one more (E_ROUTE_CAP); at level 8 it kept one more and refused the next; at level 16 one more again: % routes.', v_cap, v_cap + 2;

  -- ── PERK_SHARE_REGARD ──
  select sum(k.amount) into v_sum from public.level_perks k where k.perk = 'share_regard';
  v_nat := public.port_nation(v_lis);
  update public.players set ducats = ducats + 10000000 where id in (v_a, v_b);
  delete from public.house_regard where player_id in (v_a, v_b);
  perform public.invest_for(v_b, v_lis, 'docks', 10);   -- Investment level 1
  perform public.invest_for(v_a, v_lis, 'docks', 10);   -- Investment at the top level
  select (e.payload ->> 'delta')::numeric into v_rb from public.events e where e.player_id = v_b and e.kind = 'REGARD_CHANGED' and e.payload ->> 'reason' = 'SHARE' order by e.created_at desc, e.id desc limit 1;
  select (e.payload ->> 'delta')::numeric into v_ra from public.events e where e.player_id = v_a and e.kind = 'REGARD_CHANGED' and e.payload ->> 'reason' = 'SHARE' order by e.created_at desc, e.id desc limit 1;
  if v_rb is null or v_rb <= 0 or v_ra is null or abs(v_ra - v_rb * (1 + v_sum / 100)) > 0.02 then
    raise exception 'PROOF 113 FAILED: the same ten shares earned % regard at level 1 and % at the top level (the steps'' sum is % %%)', v_rb, v_ra, v_sum;
  end if;
  raise notice 'PASS: PERK_SHARE_REGARD — ten shares of Lisbon''s docks earned % regard at Investment level 1 and % at level %: % %% more.', v_rb, v_ra, v_top, v_sum;

  -- ── PERK_LISTED ──
  perform cmd.assume_identity(c_a);
  v_r := world.levels() -> 'level_skills' -> 'skills';
  select count(*) into v_n from jsonb_array_elements(v_r) e cross join jsonb_array_elements(e -> 'benefits') b where b ->> 'kind' = 'perk';
  if v_n <> (select count(*) from public.level_perks)
     or exists (select 1 from jsonb_array_elements(v_r) e cross join jsonb_array_elements(e -> 'benefits') b
                 where b ->> 'kind' = 'perk'
                   and not exists (select 1 from public.level_perks k where k.skill = e ->> 'code' and k.perk = b ->> 'perk' and k.level = (b ->> 'level')::int
                                      and k.amount = (b ->> 'amount')::numeric and k.unit = b ->> 'unit'
                                      and (b ->> 'total')::numeric = (select sum(k2.amount) from public.level_perks k2 where k2.perk = k.perk and k2.level <= k.level))) then
    raise exception 'PROOF 113 FAILED: the page lists % step(s), or one that is not the table''s', v_n;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'level_perks_on';
  if exists (select 1 from jsonb_array_elements(world.levels() -> 'level_skills' -> 'skills') e cross join jsonb_array_elements(e -> 'benefits') b where b ->> 'kind' = 'perk') then
    raise exception 'PROOF 113 FAILED: with level_perks_on false the page still lists a step';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'level_perks_on';
  raise notice 'PASS: PERK_LISTED — world.levels() lists % steps, each at its level with its amount, unit and running total as public.level_perks holds them; with the knob off it lists none.', v_n;
end
$p$;
