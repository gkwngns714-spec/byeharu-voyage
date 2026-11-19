-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 163 - EVERY RAW GOOD HAS A QUAY  (migration 0460; docs/dev-log/2026-11-19-quay-goods.md)
--   0280 added raw goods and no quay rows for them: 43 raw goods (Fresh Water among them) were sold on no quay, so 211 of the
--   287 recipes could not be made. 0460 puts each on the roster (data/ports.json, scripts/build-world-growth.mjs) of one harbour
--   of its own origin regions, inside the roster laws. Read through the live tables and the server's own cmd.do_buy.
--   Everything rolls back (proof.mjs).
--
-- @pass QUAY_EVERY_RAW    every raw good (tier 0) is on at least one roster, at a harbour of one of its origin regions
-- @pass QUAY_RECIPES      every recipe can be made: each ingredient is sold on a quay or made by a recipe whose ingredients can be got
-- @pass QUAY_LAWS         the roster laws hold: capital 10, middling 4-8, small 4; no good in four cities; every offer native or an entrepot
-- @pass QUAY_DEPTH        every market row's max stock and production are the rule's (0005 x market_depth x 0303's stock scale)
-- @pass QUAY_BUY          a company at Bilbao buys Fresh Water through cmd.do_buy; at Lisbon (not on its roster) the same buy is refused
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_uid   constant uuid := '00000000-0163-4000-8000-000000000001';
  v_n     int;
  v_list  text;
  v_ok    int;
  v_all   int;
  v_bil   uuid := (select p.id from public.ports p where p.code = 'BIL');
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_water uuid := (select g.id from public.goods g where g.code = 'fresh-water');
  v_pl    uuid;
  v_fl    uuid;
  v_r     jsonb;
  v_hold  numeric;
begin
  -- ── QUAY_EVERY_RAW ──
  select count(*), string_agg(g.code, ', ' order by g.code) into v_n, v_list
    from public.goods g
   where g.tier = 0
     and not exists (select 1 from public.port_specialties s
                       join public.ports p on p.id = s.port_id
                       join public.regions r on r.id = p.region_id
                      where s.good_id = g.id and r.code = any(g.origin_regions));
  if v_n <> 0 then
    raise exception 'PROOF 163 FAIL: % raw good(s) are sold on no quay of their own regions: %', v_n, v_list;
  end if;
  select count(*) into v_all from public.goods g where g.tier = 0;
  raise notice 'PASS: QUAY_EVERY_RAW — all % raw goods are on a roster of their own regions', v_all;

  -- ── QUAY_RECIPES: the closure of what can be got (a quay's roster, then whatever a recipe makes from what can be got) ──
  create temp table got_163 on commit drop as select distinct s.good_id from public.port_specialties s;
  loop
    insert into got_163
    select distinct r.product_id from public.goods_recipes r
     where r.product_id not in (select good_id from got_163)
       and not exists (select 1 from public.goods_recipes i
                        where i.product_id = r.product_id and i.ingredient_id not in (select good_id from got_163));
    get diagnostics v_n = row_count;
    exit when v_n = 0;
  end loop;
  select count(distinct r.product_id) into v_all from public.goods_recipes r;
  select count(*) into v_ok from (select distinct r.product_id from public.goods_recipes r) x
   where not exists (select 1 from public.goods_recipes i where i.product_id = x.product_id and i.ingredient_id not in (select good_id from got_163));
  if v_ok <> v_all then
    raise exception 'PROOF 163 FAIL: only % of % recipes can be made', v_ok, v_all;
  end if;
  raise notice 'PASS: QUAY_RECIPES — % of % recipes can be made from what the quays sell', v_ok, v_all;

  -- ── QUAY_LAWS ──
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
  raise notice 'PASS: QUAY_LAWS — capital 10, middling 4-8, small 4; no good in four cities; every offer native or an entrepot';

  -- ── QUAY_DEPTH ──
  with scale as (select g.id as good_id, public.good_stock_scale(g.id) as sc from public.goods g),
  rule as (
    select pg.port_id, pg.good_id, pg.stock_target, pg.production_rate,
           (world.market_depth_at(p.size_tier, pg.affinity, public.wc_num('market_depth'))).stock_target as dt,
           (world.market_depth_at(p.size_tier, pg.affinity, public.wc_num('market_depth'))).production_rate as dr,
           s.sc
      from public.port_goods pg
      join public.ports p on p.id = pg.port_id
      join scale s on s.good_id = pg.good_id),
  want as (
    select r.*, case when r.sc < 1 then greatest(public.wc_num('stock_floor_units'), round(r.dt * r.sc, 2)) else r.dt end as wt
      from rule r)
  select count(*) into v_n from want w
   where w.stock_target is distinct from w.wt or w.production_rate is distinct from round(w.dr * least(1, w.wt / w.dt), 2);
  if v_n <> 0 then
    raise exception 'PROOF 163 FAIL: % market row(s) hold a max stock or production that is not the rule''s', v_n;
  end if;
  select count(*) into v_all from public.port_goods;
  raise notice 'PASS: QUAY_DEPTH — all % market rows hold the rule''s max stock and production', v_all;

  -- ── QUAY_BUY ──
  if not public.port_offers(v_bil, v_water) or public.port_offers(v_lis, v_water) then
    raise exception 'PROOF 163 FAIL: Fresh Water is not on Bilbao''s roster alone of the two';
  end if;
  v_pl := public.new_house(c_uid, 'Casa da Agua 163', 'PRT', p_ducats => 200000);
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  update public.fleets set port_id = v_bil where id = v_fl;
  v_r := cmd.do_buy(v_fl, jsonb_build_object('good', v_water, 'qty', 5));
  if v_r ? 'error_code' or coalesce((v_r ->> 'total')::numeric, 0) <= 0 then
    raise exception 'PROOF 163 FAIL: buying Fresh Water at Bilbao was refused: %', v_r;
  end if;
  v_hold := public.fleet_cargo_qty(v_fl, 'fresh-water');
  if v_hold <> 5 then
    raise exception 'PROOF 163 FAIL: the hold has % Fresh Water after buying 5 (%)', v_hold, v_r;
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
  raise notice 'PASS: QUAY_BUY — 5 Fresh Water bought at Bilbao through cmd.do_buy; the same buy at Lisbon refused (%)', v_r ->> 'error_code';
end
$p$;
