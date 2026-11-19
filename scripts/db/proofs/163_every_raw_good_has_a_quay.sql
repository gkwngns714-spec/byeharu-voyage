-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 163 - EVERY RAW GOOD HAS A SOURCE  (migration 0460; docs/dev-log/2026-11-19-quay-goods.md)
--   0280 added raw goods and no quay rows for them: 43 raw goods (Fresh Water among them) were sold on no quay, so 211 of the
--   287 recipes could not be made. Seven are Mining goods: the land is their source (lit on prod 2026-11-19). 0460 puts each of
--   the other 36 on the roster (data/ports.json, scripts/build-world-growth.mjs) of one harbour of its own origin regions, inside
--   the roster laws, and moves no other good's market row (the file's own self-assert pins those). Read through the live tables
--   and the server's own cmd.do_buy. Everything rolls back (proof.mjs).
--
-- @pass SOURCE_EVERY_RAW  every raw good (tier 0) is on a roster of one of its own origin regions, or gathered by the land (a Mining job)
-- @pass SOURCE_RECIPES    every recipe can be made from what the quays and the land give; the count from the quays alone is printed
-- @pass SOURCE_LAWS       the roster laws hold: capital 10, middling 4-8, small 4; no good in four cities; every offer native or an entrepot
-- @pass SOURCE_FOOTING    the 36 placed goods keep 0280's footing: every row's base max is 0005's arithmetic at its affinity (no market_depth)
-- @pass SOURCE_BUY        a company at Bilbao buys Fresh Water through cmd.do_buy; at Lisbon (not on its roster) the same buy is refused
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_uid   constant uuid := '00000000-0163-4000-8000-000000000001';
  c_placed constant text[] := array['agave', 'apple', 'bamboo', 'bark', 'betel-leaf', 'cabbage', 'cacao-bean', 'cassava-root', 'cattle',
    'coffee-bean', 'eel', 'eggs', 'fresh-water', 'goose-feathers', 'grapes', 'honeybush-leaf', 'lychee', 'milk', 'mint', 'nipa',
    'palm-fruit', 'palm-leaf', 'palm-sap', 'pandanus', 'pear', 'plum', 'raffia', 'ramie', 'rose', 'sesame', 'shea-nut', 'shrimp',
    'soybean', 'sugar-cane', 'tea-leaf', 'witch-hazel-bark'];
  v_n     int;
  v_list  text;
  v_ok    int;
  v_quay  int;
  v_all   int;
  v_bil   uuid := (select p.id from public.ports p where p.code = 'BIL');
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_water uuid := (select g.id from public.goods g where g.code = 'fresh-water');
  v_pl    uuid;
  v_fl    uuid;
  v_r     jsonb;
begin
  -- ── SOURCE_EVERY_RAW ──
  select count(*), string_agg(g.code, ', ' order by g.code) into v_n, v_list
    from public.goods g
   where g.tier = 0
     and not exists (select 1 from public.port_specialties s
                       join public.ports p on p.id = s.port_id
                       join public.regions r on r.id = p.region_id
                      where s.good_id = g.id and r.code = any(g.origin_regions))
     and not exists (select 1 from public.land_actions a where a.good_id = g.id and a.kind = 'gather');
  if v_n <> 0 then
    raise exception 'PROOF 163 FAIL: % raw good(s) have no quay of their own regions and no land job: %', v_n, v_list;
  end if;
  select count(*) into v_n from public.goods g
   where g.tier = 0 and not exists (select 1 from public.port_specialties s where s.good_id = g.id);
  select count(*) into v_all from public.goods g where g.tier = 0;
  raise notice 'PASS: SOURCE_EVERY_RAW — all % raw goods have a source; % of them by the land alone', v_all, v_n;

  -- ── SOURCE_RECIPES: the closure of what can be got (a roster or a land job, then whatever a recipe makes of it) ──
  create temp table got_163 (good_id uuid, quay boolean) on commit drop;
  insert into got_163 select distinct s.good_id, true from public.port_specialties s;
  insert into got_163 select distinct a.good_id, false from public.land_actions a
   where a.kind = 'gather' and a.good_id not in (select good_id from got_163);
  for v_ok in 0..1 loop   -- 0: the quays alone, 1: the quays and the land
    create temp table reach_163 on commit drop as select good_id from got_163 where quay or v_ok = 1;
    loop
      insert into reach_163
      select distinct r.product_id from public.goods_recipes r
       where r.product_id not in (select good_id from reach_163)
         and not exists (select 1 from public.goods_recipes i
                          where i.product_id = r.product_id and i.ingredient_id not in (select good_id from reach_163));
      get diagnostics v_n = row_count;
      exit when v_n = 0;
    end loop;
    select count(*) into v_n from (select distinct r.product_id from public.goods_recipes r) x
     where not exists (select 1 from public.goods_recipes i where i.product_id = x.product_id and i.ingredient_id not in (select good_id from reach_163));
    if v_ok = 0 then v_quay := v_n; end if;
    drop table reach_163;
  end loop;
  select count(distinct r.product_id) into v_all from public.goods_recipes r;
  if v_n <> v_all then
    raise exception 'PROOF 163 FAIL: only % of % recipes can be made from the quays and the land', v_n, v_all;
  end if;
  raise notice 'PASS: SOURCE_RECIPES — % of % recipes can be made from the quays and the land; % from the quays alone', v_n, v_all, v_quay;

  -- ── SOURCE_LAWS ──
  select count(*), string_agg(p.code, ', ') into v_n, v_list
    from public.ports p
    join lateral (select count(*) as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.kind = 'HARBOUR'
     and ((p.size_tier = 5 and sc.c <> 10) or (p.size_tier = 3 and sc.c not between 4 and 8) or (p.size_tier = 2 and sc.c <> 4));
  if v_n <> 0 then
    raise exception 'PROOF 163 FAIL: % harbour(s) break the roster count law: %', v_n, v_list;
  end if;
  select count(*) into v_n from (select s.good_id from public.port_specialties s group by s.good_id having count(*) > 3) x;
  if v_n <> 0 then
    raise exception 'PROOF 163 FAIL: % good(s) sit in four or more cities', v_n;
  end if;
  select count(*) into v_n
    from public.port_specialties s
    join public.ports p on p.id = s.port_id
    join public.regions r on r.id = p.region_id
    join public.goods g on g.id = s.good_id
   where not (r.code = any(g.origin_regions)) and not (p.code = any(g.entrepot_ports));
  if v_n <> 0 then
    raise exception 'PROOF 163 FAIL: % offer(s) are neither native nor a named entrepot', v_n;
  end if;
  raise notice 'PASS: SOURCE_LAWS — capital 10, middling 4-8, small 4; no good in four cities; every offer native or an entrepot';

  -- ── SOURCE_FOOTING: 0280 seeded its goods with 0005's arithmetic and no market_depth; a placed good keeps that ──
  select count(*) into v_n
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
    join public.goods g on g.id = pg.good_id
   where g.code = any(c_placed)
     and coalesce(pg.base_target, pg.stock_target) is distinct from (world.market_depth_at(p.size_tier, pg.affinity, 1)).stock_target * public.good_stock_scale(g.id);
  select count(*) into v_all from public.port_goods pg join public.goods g on g.id = pg.good_id where g.code = any(c_placed);
  if v_n <> 0 then
    raise exception 'PROOF 163 FAIL: % of % market rows of the placed goods are off 0280''s footing', v_n, v_all;
  end if;
  raise notice 'PASS: SOURCE_FOOTING — all % market rows of the 36 placed goods on 0280''s footing', v_all;

  -- ── SOURCE_BUY ──
  if not public.port_offers(v_bil, v_water) or public.port_offers(v_lis, v_water) then
    raise exception 'PROOF 163 FAIL: Fresh Water is not on Bilbao''s roster alone of the two';
  end if;
  v_pl := public.new_house(c_uid, 'Casa da Agua 163', 'PRT', p_ducats => 200000);
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  update public.fleets set port_id = v_bil where id = v_fl;
  v_r := cmd.do_buy(v_fl, jsonb_build_object('good', v_water, 'qty', 5));
  if v_r ? 'error_code' or coalesce((v_r ->> 'total')::numeric, 0) <= 0 or public.fleet_cargo_qty(v_fl, 'fresh-water') <> 5 then
    raise exception 'PROOF 163 FAIL: buying 5 Fresh Water at Bilbao did not land in the hold: %', v_r;
  end if;
  update public.fleets set port_id = v_lis where id = v_fl;
  begin
    v_r := cmd.do_buy(v_fl, jsonb_build_object('good', v_water, 'qty', 5));
  exception when others then
    v_r := jsonb_build_object('error_code', sqlerrm);
  end;
  if not (v_r ? 'error_code') or public.fleet_cargo_qty(v_fl, 'fresh-water') <> 5 then
    raise exception 'PROOF 163 FAIL: Lisbon sold Fresh Water, which is not on its roster: %', v_r;
  end if;
  raise notice 'PASS: SOURCE_BUY — 5 Fresh Water bought at Bilbao through cmd.do_buy; the same buy at Lisbon refused (%)', v_r ->> 'error_code';
end
$p$;
