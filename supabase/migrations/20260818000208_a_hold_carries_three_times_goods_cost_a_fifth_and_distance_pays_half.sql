-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0208 — A HOLD CARRIES THREE TIMES, GOODS COST A FIFTH, AND DISTANCE PAYS HALF
--        (three knobs, each with one place it is applied: hold_scale 3, goods_price_level 0.2,
--         haul_premium_share 0.5)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, 2026-10-19, verbatim: "in addition to the 10x goods quantities, enlarge the ships cargo by
-- 3x. reduce the goods price by 5x. distance earning gold diminish by half".
-- Built on 0207 (every market ten times deeper, live). Supersedes and re-cuts: world.haul_at (0173:
-- dropped and recreated with a fifth argument, the share), world.haul_rows (0173: two hunks) and
-- public.item_recipe_value (0158: one hunk). Every re-cut body reverses to its pre-image (asserted).
--
-- ── 1. THE HOLD × 3 — knob hold_scale (3) ───────────────────────────────────────────────────────
--   Every server reading of "how much fits" goes through ONE chain: ship_classes.hold → world.ship_stats
--   (the class's rated hold + what is mounted: item_effects, unit perks, set bonuses; skills as a per
--   cent) → world.ship_stat(_, 'hold') → public.ship_hold_capacity (× the quartermasters' per cent) →
--   public.fleet_free_hold → cmd.do_buy / public.fleet_load / public.fleet_buy_capacity (the trade
--   tray's maximum) / world.good_board / world.trade_routes / the NPC planner (public.npc_plan →
--   npc_leg_lines, npc_loop_candidates: a parcel is sized under her free hold) / the stores
--   (public.stores_topup, npc_provision_for, cmd.do_provision: hold × store_ratio). A ship row stores
--   no hold of its own. So the hold is scaled where its QUANTITIES are written, and nowhere else:
--     * ship_classes.hold × 3 (every one of the hull classes; every existing ship, players' and
--       merchants', sails one of them);
--     * item_effects.delta × 3 where stat = 'hold' (a fitting that gives or spends hold space: a hold
--       fitting's +25 becomes +75, a battery's −20 becomes −60, so a fitted ship is ALSO exactly 3×);
--     * perks.per_rank × 3 where stat = 'hold' and mode = 'flat' (ROOMY, 2 → 6 tons a rank);
--     * gear_set_bonuses.flat × 3 where stat = 'hold' (none today; the per-cent set bonuses, skills and
--       quartermasters are proportions of the hold and need nothing).
--   route_probe_tuns 50 → 150: the cargo world.trade_routes assumes when no fleet is named is a HOLD
--   stand-in (0207's header), so it follows the hold.
--   The data files keep the design figures; scripts/db/world-guard.mjs holds the rows = data × hold_scale.
--   Like market_depth (0207), the knob is applied when rows are WRITTEN; changing it alone moves nothing.
--   DECIDED BY DEFAULT, kept: the warehouse (warehouse_tuns_per_tier, a flat 150 a tier, not a hold
--   multiple); the contract sizes (10–30, a city's request); the stores ratio (store_ratio stays a share
--   of the hold, so FULL stores grow with it — a bigger hold has bigger casks); voyage.ship_speed_at's
--   laden fraction (cargo ÷ the rated hold, which is now 3× — a ship laden 3× sails as before).
--
-- ── 2. GOODS PRICES ÷ 5 — knob goods_price_level (0.2) ─────────────────────────────────────────
--   THE price authority starts from goods.base_value (world.mid_terms → world.mid_from_terms; the band
--   is × base; world.market's range; world.snapshot serves it to the client). goods.base_value × 0.2
--   therefore moves every mid, ask, bid, quote, outlook, trade route, good board, contract premium (a
--   share of the mid at posting) and the merchants' parcels (npc_buy_ceiling is the ask × patience),
--   and nothing else needs a hunk. base_value is numeric(10,2) and every value is a half-ducat (a band's
--   midpoint), so × 0.2 is exact.
--   DECIDED BY DEFAULT (the owner may reverse each):
--     * ONLY goods prices change. Player and company cash, city purses, ship prices (hull_recipes.ducats,
--       build costs), crew wages, provisions (provision_food/water_price), the profit-tax rates — kept.
--     * REPAIR COSTS kept: public.item_recipe_value (the one reader of base_value outside the market,
--       read by unit_repair_cost) reckons a recipe at the DESIGN value, base_value ÷ goods_price_level —
--       one hunk, asserted equal to the pre-image for every item.
--     * price_history.mid (the chart) × 0.2 × (new haul ÷ old haul), so the line meets the new level
--       rather than falling off a cliff at this deploy (0207 scaled its stock the same way).
--     * PER-UNIT PRICES THAT ARE STORED — scaled × 0.2, because they are prices in the old unit:
--       - ships.cargo_basis and player_storage.basis (what a unit aboard / in store cost). Without it
--         every SELL "at profit" (every merchant's SELL lines; npc_buy_budget says "never below cost")
--         would refuse every unit loaded before this deploy for good, and 560 merchant hulls are laden.
--         The cost: the profit tax on those first sales is reckoned on the scaled basis.
--       - standing_route_lines.price_limit (a BUY ceiling / SELL floor a unit);
--       - an open order's limit (orders.args.limit, and its raw text "… AT n").
--     * KEPT, as money already moved or promised: trade_contracts (premium_ducats is escrowed from the
--       city's purse; they lapse in contract_deadline_days), standing_route_laps (books of real money).
--
-- ── 3. THE DISTANCE PREMIUM HALVED — knob haul_premium_share (0.5) ─────────────────────────────
--   0173's haul is the extra a good is worth the farther it sells from its maker. Its one arithmetic,
--   world.haul_at, takes the share:  haul = 1 + share × (max ^ ((min(nm, reach) / reach) ^ curve) − 1),
--   at 4 dp — so the PREMIUM (haul − 1) is exactly half (to the 4-dp rounding) at every distance, and
--   share 1 is 0173's figure to the digit (asserted on every row). world.haul_rows passes the knob;
--   port_goods.haul is refilled from it (the world guard compares the two on every apply).
--   DECIDED BY DEFAULT: affinity's own great-circle slope (at most 1.76×, 0005) is the market's
--   geography, not 0173's distance earning, and is kept.
--
-- ── WHAT IT SELF-ASSERTS ─────────────────────────────────────────────────────────────────────────
--   (a) knobs; every class's hold and every hold effect / flat hold perk exactly 3 × its pre-image;
--       every ship's rated hold (world.ship_stat) and capacity (public.ship_hold_capacity) exactly 3×
--       where no per-cent term applies, and within the per-cent's rounding (≤ 3 tons) where one does.
--   (b) every base_value exactly 0.2 ×; on a probe set (every 7th quay row, haul 1 there) mid / ask /
--       bid and the 1- and 10-unit quotes, buy and sell, are ÷ 5 within rounding while the stock is
--       unchanged; far rows' mids are × 0.2 × (new haul ÷ old haul) within rounding.
--   (c) every row's haul = world.haul_rows(); the premium half of the old one within the 4-dp rounding
--       on every row, EXACTLY half on a probe pair beyond the reach (600 → 300.5); share 1 = 0173.
--   (d) price_history, cargo basis, storage basis, line limits and open orders' limits × 0.2.
--   (e) item_recipe_value (repair costs) unchanged for every item; the re-cut bodies reverse to their
--       pre-images, ACL / volatility / definer / config kept; haul_at's ACL as 0173 left it; walls.
--   (f) timings: world.quote and world.price, 8 calls each in one session (notice only).
-- ROLLBACK (a forward migration): the inverse updates (hold ÷ 3, base_value × 5, history ÷ (0.2 × ratio),
--   basis / limits × 5), route_probe_tuns 50, haul_premium_share 1 and refill the hauls; the hunks reverse.
-- VERSION: 0208 at writing (prod head 0207, live). It RENUMBERS to the prod head + 1 at push.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if exists (select 1 from public.world_config where key in ('hold_scale', 'goods_price_level', 'haul_premium_share')) then
    raise exception '0208 refuses: hold_scale / goods_price_level / haul_premium_share already exist — this has been applied once';
  end if;
  if not exists (select 1 from public.world_config where key = 'market_depth') then
    raise exception '0208 refuses: 0207 (market_depth) is not in this world';
  end if;
  if to_regprocedure('world.haul_at(numeric, numeric, numeric, numeric)') is null
     or to_regprocedure('world.haul_rows()') is null
     or to_regprocedure('public.item_recipe_value(text)') is null then
    raise exception '0208 refuses: 0173''s haul or 0158''s recipe value is not in this world';
  end if;
  if public.wc_num('route_probe_tuns') is distinct from 50 then
    raise exception '0208 refuses: route_probe_tuns reads %, not 50', public.wc_num('route_probe_tuns');
  end if;
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0208(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE KNOBS ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('hold_scale', to_jsonb(3),
   '0208 (owner, 2026-10-19: "enlarge the ships cargo by 3x"): every hold quantity in the world as a multiple of the '
   'design figure in the data files — ship_classes.hold, item_effects.delta (stat hold), perks.per_rank (flat hold), '
   'gear_set_bonuses.flat (hold). Applied when those rows are WRITTEN (0208 wrote them at 3); the world guard holds '
   'them = data × this. Changing it alone moves nothing.'),
  ('goods_price_level', to_jsonb(0.2),
   '0208 (owner, 2026-10-19: "reduce the goods price by 5x"): every good''s base_value as a multiple of its design '
   'value (the data''s band midpoint). Applied when goods rows are WRITTEN (0208 wrote them at 0.2); the world guard '
   'holds base_value = data × this. public.item_recipe_value divides by it, so repair costs stay at the design value.'),
  ('haul_premium_share', to_jsonb(0.5),
   '0208 (owner, 2026-10-19: "distance earning gold diminish by half"): the share of 0173''s distance premium a far '
   'city pays — haul = 1 + share × (haul_max ^ ((min(nm, reach) / reach) ^ haul_curve) − 1), in world.haul_at. '
   'Read by world.haul_rows; port_goods.haul is refilled from it by a migration (the world guard compares them).');

update public.world_config
   set value = to_jsonb(50 * 3),
       description = coalesce(description, '') || ' 0208: × hold_scale (3) — it stands in for a hold, so it follows the hold.'
 where key = 'route_probe_tuns';

-- ── 2. LOCK, THEN THE PRE-IMAGES ────────────────────────────────────────────────────────────────
-- Every market row, every ship and every route line is locked FIRST, so no trade, tick or plan moves a
-- figure between the pre-image and the update (a trade waits the seconds this file takes).
do $lock$
begin
  perform 1 from public.port_goods for update;
  perform 1 from public.ships for update;
  perform 1 from public.standing_route_lines for update;
  perform 1 from public.player_storage for update;
  perform 1 from public.orders where status in ('pending', 'active') for update;
end $lock$;

create temp table defs_before_0208 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('world.haul_rows()'), ('public.item_recipe_value(text)')) f(fn);

create temp table haulat_before_0208 on commit drop as
select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, pg_get_userbyid(p.proowner) as owner
  from pg_proc p where p.oid = 'world.haul_at(numeric, numeric, numeric, numeric)'::regprocedure;

-- 0173's arithmetic, kept under a pg_temp name, so the new one can be compared to it on every row
create function pg_temp.haul_at_b0208(p_nm numeric, p_max numeric, p_reach_nm numeric, p_curve numeric)
returns numeric language sql immutable as $$
  select case when p_nm is null or p_nm <= 0 then 1::numeric
              else round(exp(ln(p_max) * power(least(1::numeric, p_nm / p_reach_nm), p_curve)), 4) end
$$;

create temp table goods_0208 on commit drop as select id, code, base_value from public.goods;
create temp table classes_0208 on commit drop as select id, code, hold from public.ship_classes;
create temp table effects_0208 on commit drop as select item_code, stat, delta from public.item_effects where stat = 'hold';
create temp table perks_0208 on commit drop as select code, per_rank from public.perks where stat = 'hold' and mode = 'flat';
create temp table sets_0208 on commit drop as select line_code, pieces, flat from public.gear_set_bonuses where stat = 'hold' and flat is not null;
create temp table recipe_0208 on commit drop as
select k.code, public.item_recipe_value(k.code) as v from public.item_kinds k;
create temp table hauls_0208 on commit drop as select port_id, good_id, haul_nm, haul from public.port_goods;
create temp table hist_0208 on commit drop as select port_id, good_id, slot, mid from public.price_history;
create temp table basis_0208 on commit drop as select id, cargo_basis from public.ships where cargo_basis <> '{}'::jsonb;
create temp table store_0208 on commit drop as select player_id, port_id, good_id, basis from public.player_storage where basis is not null;
create temp table lines_0208 on commit drop as select route_id, stop_ord, ord, price_limit from public.standing_route_lines where price_limit is not null;
create temp table orders_0208 on commit drop as
select id, args, raw_text from public.orders where status in ('pending', 'active') and jsonb_typeof(args->'limit') = 'number';

-- every ship's rated hold and capacity, before (the per-cent terms are flagged so the exact claim
-- is made only where it can be exact)
create temp table ships_0208 (phase text, ship_id uuid, rated numeric, cap numeric) on commit drop;
create function pg_temp.ships_0208(p_phase text) returns void language sql as $$
  insert into ships_0208
  select p_phase, s.id, world.ship_stat(s.id, 'hold'), public.ship_hold_capacity(s.id) from public.ships s;
$$;
select pg_temp.ships_0208('before');

-- THE PRICE PROBE SET — deterministic: every 7th row a quay offers (haul 1 there), by port then good
-- code; and the FAR set: every 211th row with a haul above 1, by port then good code.
create temp table probe_0208 on commit drop as
select x.port_id, x.good_id, x.port_code, x.good_code, 'quay'::text as kind
  from (select pg.port_id, pg.good_id, p.code as port_code, g.code as good_code,
               row_number() over (order by p.code, g.code) as rn
          from public.port_goods pg
          join public.ports p on p.id = pg.port_id
          join public.goods g on g.id = pg.good_id
         where public.port_offers(pg.port_id, pg.good_id)) x
 where x.rn % 7 = 1
union all
select x.port_id, x.good_id, x.port_code, x.good_code, 'far'
  from (select pg.port_id, pg.good_id, p.code as port_code, g.code as good_code,
               row_number() over (order by p.code, g.code) as rn
          from public.port_goods pg
          join public.ports p on p.id = pg.port_id
          join public.goods g on g.id = pg.good_id
         where pg.haul > 1) x
 where x.rn % 211 = 1;

create temp table quote_0208 (
  phase text, port_id uuid, good_id uuid, mid numeric, ask numeric, bid numeric,
  b1 numeric, b10 numeric, s1 numeric, s10 numeric, stock numeric
) on commit drop;

create function pg_temp.quote_0208(p_phase text) returns void language sql as $$
  insert into quote_0208
  select p_phase, pr.port_id, pr.good_id, wp.mid, wp.ask, wp.bid,
         qb1.avg_price, qb10.avg_price, qs1.avg_price, qs10.avg_price,
         (select pg.stock from public.port_goods pg where pg.port_id = pr.port_id and pg.good_id = pr.good_id)
    from probe_0208 pr
    cross join lateral world.price(pr.port_id, pr.good_id) wp
    cross join lateral world.quote(pr.port_id, pr.good_id, 1,  'buy',  null, null) qb1
    cross join lateral world.quote(pr.port_id, pr.good_id, 10, 'buy',  null, null) qb10
    cross join lateral world.quote(pr.port_id, pr.good_id, 1,  'sell', null, null) qs1
    cross join lateral world.quote(pr.port_id, pr.good_id, 10, 'sell', null, null) qs10;
$$;
select pg_temp.quote_0208('before');

-- ── 3. THE HAUL'S ONE ARITHMETIC TAKES THE SHARE (drop + recreate: a fifth argument) ───────────
drop function world.haul_at(numeric, numeric, numeric, numeric);

create function world.haul_at(p_nm numeric, p_max numeric, p_reach_nm numeric, p_curve numeric, p_share numeric)
returns numeric
language sql
immutable
parallel safe
as $$
  -- 0173: THE HAUL — what a good's price is multiplied by for the sea between this city and its nearest
  -- maker. 0208: 1 + share × (max ^ (min(1, nm / reach) ^ curve) − 1), at 4 dp — the share of the
  -- premium a far city pays (haul_premium_share; 1 is 0173's figure to the digit). 1 at a maker (nm 0)
  -- and where no sea lane reaches (nm null: what the sea cannot fetch earns no premium).
  select case when p_nm is null or p_nm <= 0 then 1::numeric
              else round(1 + p_share * (exp(ln(p_max) * power(least(1::numeric, p_nm / p_reach_nm), p_curve)) - 1), 4) end
$$;

comment on function world.haul_at(numeric, numeric, numeric, numeric, numeric) is
  '0173 / 0208: THE haul arithmetic — 1 + share × (max ^ (min(1, nm / reach) ^ curve) − 1), 4 dp. Argument-only and '
  'immutable; read by world.haul_rows with the haul_* knobs and haul_premium_share. Server-only.';

revoke all on function world.haul_at(numeric, numeric, numeric, numeric, numeric) from public;

-- ── 4. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0208 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0208 values
('world.haul_rows()', 1,
$h$    select public.wc_num('haul_max') as mx, public.wc_num('haul_reach_nm') as reach, public.wc_num('haul_curve') as c
$h$,
$h$    select public.wc_num('haul_max') as mx, public.wc_num('haul_reach_nm') as reach, public.wc_num('haul_curve') as c,
           public.wc_num('haul_premium_share') as share   -- 0208: the share of the premium a far city pays
$h$),
('world.haul_rows()', 2,
$h$world.haul_at(d.nm, k.mx, k.reach, k.c)
$h$,
$h$world.haul_at(d.nm, k.mx, k.reach, k.c, k.share)
$h$),
('public.item_recipe_value(text)', 1,
$h$  return (select coalesce(sum(ir.qty * g.base_value), 0)
$h$,
$h$  -- 0208: at the goods' DESIGN value — base_value ÷ goods_price_level — so the market's ÷ 5 leaves
  -- repair costs where they were (the owner's default: only goods prices change).
  return (select coalesce(sum(ir.qty * g.base_value / public.wc_num('goods_price_level')), 0)
$h$);

create or replace function pg_temp.recut_0208(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0208 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0208 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0208(v_def, h.old);
    if v_n <> 1 then
      raise exception '0208 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0208(fn) from defs_before_0208 order by fn;

-- ── 5. THE ROWS ─────────────────────────────────────────────────────────────────────────────────
-- (1) every hold quantity × hold_scale
update public.ship_classes set hold = hold * public.wc_int('hold_scale');
update public.item_effects set delta = delta * public.wc_num('hold_scale') where stat = 'hold';
update public.perks set per_rank = per_rank * public.wc_num('hold_scale') where stat = 'hold' and mode = 'flat';
update public.gear_set_bonuses set flat = flat * public.wc_num('hold_scale') where stat = 'hold' and flat is not null;

-- (2) every good's price level × goods_price_level
update public.goods set base_value = base_value * public.wc_num('goods_price_level');

-- (3) every market row's haul, refilled from the one derivation
update public.port_goods pg
   set haul_nm = h.haul_nm, haul = h.haul
  from world.haul_rows() h
 where h.port_id = pg.port_id and h.good_id = pg.good_id
   and (pg.haul is distinct from h.haul or pg.haul_nm is distinct from h.haul_nm);

-- (4) the stored per-unit prices, × goods_price_level (the chart × the haul's move as well)
update public.price_history ph
   set mid = round(ph.mid * public.wc_num('goods_price_level') * pg.haul / h.haul, 4)
  from hauls_0208 h, public.port_goods pg
 where h.port_id = ph.port_id and h.good_id = ph.good_id
   and pg.port_id = ph.port_id and pg.good_id = ph.good_id;

update public.ships s
   set cargo_basis = (select jsonb_object_agg(e.key, case when jsonb_typeof(e.value) = 'number'
                                                          then to_jsonb((e.value #>> '{}')::numeric * public.wc_num('goods_price_level'))
                                                          else e.value end)
                        from jsonb_each(s.cargo_basis) e)
 where s.cargo_basis <> '{}'::jsonb;

update public.player_storage set basis = basis * public.wc_num('goods_price_level') where basis is not null;

update public.standing_route_lines set price_limit = price_limit * public.wc_num('goods_price_level') where price_limit is not null;

update public.orders o
   set args = jsonb_set(o.args, '{limit}', to_jsonb((o.args->>'limit')::numeric * public.wc_num('goods_price_level'))),
       raw_text = case when o.raw_text ~* ' AT [0-9]+(\.[0-9]+)?$'
                       then regexp_replace(o.raw_text, ' AT [0-9]+(\.[0-9]+)?$',
                              ' AT ' || trim_scale((o.args->>'limit')::numeric * public.wc_num('goods_price_level'))::text, 'i')
                       else o.raw_text end
 where o.status in ('pending', 'active') and jsonb_typeof(o.args->'limit') = 'number';

select pg_temp.ships_0208('after');
select pg_temp.quote_0208('after');

-- ── 6. SELF-ASSERT ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_n       int;
  v_m       int;
  v_ships   int;
  v_exact   int;
  v_near    int;
  v_cap_x   int;
  v_quay    int;
  v_far     int;
  v_rows    int;
  v_moved   int;
  v_hist    int;
  v_pair    record;
  v_d       record;
  v_h       record;
  v_pp      record;
  v_def     text;
  v_t       timestamptz;
  v_ms      numeric[] := '{}';
  v_pms     numeric[] := '{}';
  v_port    uuid;
  v_good    uuid;
  v_maxdev  numeric;
  i         int;
begin
  -- (a) THE KNOBS
  if public.wc_num('hold_scale') is distinct from 3 or public.wc_num('goods_price_level') is distinct from 0.2
     or public.wc_num('haul_premium_share') is distinct from 0.5 or public.wc_num('route_probe_tuns') is distinct from 150 then
    raise exception '0208 self-assert FAIL: a knob reads wrong (hold_scale %, goods_price_level %, haul_premium_share %, route_probe_tuns %)',
      public.wc_num('hold_scale'), public.wc_num('goods_price_level'), public.wc_num('haul_premium_share'), public.wc_num('route_probe_tuns');
  end if;

  -- (a) HOLDS × 3, the rows
  select count(*) into v_n from classes_0208 c join public.ship_classes sc on sc.id = c.id where sc.hold <> c.hold * 3;
  if v_n <> 0 or (select count(*) from classes_0208) = 0 or (select count(*) from classes_0208) <> (select count(*) from public.ship_classes) then
    raise exception '0208 self-assert FAIL: % ship class(es) whose hold is not exactly 3 × its pre-image', v_n;
  end if;
  select count(*) into v_n from effects_0208 e join public.item_effects ie on ie.item_code = e.item_code and ie.stat = e.stat where ie.delta <> e.delta * 3;
  if v_n <> 0 or (select count(*) from effects_0208) = 0 then
    raise exception '0208 self-assert FAIL: % hold effect(s) not exactly 3 × (of %)', v_n, (select count(*) from effects_0208);
  end if;
  if exists (select 1 from perks_0208 x join public.perks p on p.code = x.code where p.per_rank <> x.per_rank * 3)
     or exists (select 1 from sets_0208 x join public.gear_set_bonuses b on b.line_code = x.line_code and b.pieces = x.pieces and b.stat = 'hold' where b.flat <> x.flat * 3) then
    raise exception '0208 self-assert FAIL: a flat hold perk or set bonus is not 3 ×';
  end if;

  -- (a) HOLDS × 3, every ship: rated and capacity
  select count(*),
         count(*) filter (where a.rated = 3 * b.rated and a.cap = 3 * b.cap),
         count(*) filter (where abs(a.rated - 3 * b.rated) <= 3 and abs(a.cap - 3 * b.cap) <= 3),
         count(*) filter (where a.cap = 3 * b.cap)
    into v_ships, v_exact, v_near, v_cap_x
    from ships_0208 b join ships_0208 a on a.ship_id = b.ship_id and a.phase = 'after'
   where b.phase = 'before';
  if v_ships = 0 or v_ships <> (select count(*) from public.ships) then
    raise exception '0208 self-assert FAIL: % ship(s) measured of %', v_ships, (select count(*) from public.ships);
  end if;
  if v_near <> v_ships or v_exact * 10 < v_ships * 9 then
    raise exception '0208 self-assert FAIL: of % ships, % hold exactly 3 × (rated and capacity) and % within the per-cent''s rounding', v_ships, v_exact, v_near;
  end if;

  -- (b) PRICES ÷ 5: the base, then the quotes at the same stock
  select count(*) into v_n from goods_0208 g join public.goods x on x.id = g.id where x.base_value <> g.base_value * 0.2;
  if v_n <> 0 or (select count(*) from goods_0208) = 0 then
    raise exception '0208 self-assert FAIL: % good(s) whose base_value is not exactly 0.2 × its pre-image', v_n;
  end if;
  select count(*) filter (where pr.kind = 'quay'), count(*) filter (where pr.kind = 'far') into v_quay, v_far from probe_0208 pr;
  if v_quay < 100 or v_far < 100 then
    raise exception '0208 self-assert FAIL: only % quay and % far probe rows — the price check would be thin', v_quay, v_far;
  end if;
  select count(*) into v_n
    from probe_0208 pr
    join quote_0208 b on b.port_id = pr.port_id and b.good_id = pr.good_id and b.phase = 'before'
    join quote_0208 a on a.port_id = pr.port_id and a.good_id = pr.good_id and a.phase = 'after'
   where pr.kind = 'quay'
     and b.mid is not null and b.b10 is not null and b.s10 is not null and a.stock = b.stock
     and abs(a.mid - b.mid * 0.2) <= 0.0002
     and abs(a.ask - b.ask * 0.2) <= 0.011 and abs(a.bid - b.bid * 0.2) <= 0.011
     and abs(a.b1 - b.b1 * 0.2) <= 0.011 and abs(a.b10 - b.b10 * 0.2) <= 0.011
     and abs(a.s1 - b.s1 * 0.2) <= 0.011 and abs(a.s10 - b.s10 * 0.2) <= 0.011;
  if v_n <> v_quay then
    raise exception '0208 self-assert FAIL: % of % quay probe rows quote ÷ 5 within rounding at the same stock (mid, ask, bid, 1 and 10 units buy and sell)', v_n, v_quay;
  end if;
  if exists (select 1 from probe_0208 pr join hauls_0208 h on h.port_id = pr.port_id and h.good_id = pr.good_id
              where pr.kind = 'quay' and h.haul <> 1) then
    raise exception '0208 self-assert FAIL: a quay probe row had a haul above 1 — the ÷ 5 claim there would carry the haul';
  end if;
  select count(*) into v_n
    from probe_0208 pr
    join quote_0208 b on b.port_id = pr.port_id and b.good_id = pr.good_id and b.phase = 'before'
    join quote_0208 a on a.port_id = pr.port_id and a.good_id = pr.good_id and a.phase = 'after'
    join hauls_0208 h on h.port_id = pr.port_id and h.good_id = pr.good_id
    join public.port_goods pg on pg.port_id = pr.port_id and pg.good_id = pr.good_id
   where pr.kind = 'far' and a.stock = b.stock and pg.haul <= h.haul
     and abs(a.mid - b.mid * 0.2 * pg.haul / h.haul) <= 0.0003 * greatest(1, pg.haul);
  select count(*) into v_m
    from probe_0208 pr join hauls_0208 h on h.port_id = pr.port_id and h.good_id = pr.good_id
    join public.port_goods pg on pg.port_id = pr.port_id and pg.good_id = pr.good_id
   where pr.kind = 'far' and pg.haul < h.haul;
  if v_n <> v_far or v_m * 10 < v_far * 9 then
    raise exception '0208 self-assert FAIL: % of % far probe rows price at 0.2 × (new haul ÷ old haul) of their old mid; % with a smaller haul', v_n, v_far, v_m;
  end if;

  -- (c) THE HAUL: the derivation; the premium half; exact on a probe pair; share 1 = 0173
  select count(*) into v_rows from hauls_0208;
  select count(*) filter (where pg.haul is distinct from h.haul or pg.haul_nm is distinct from h.haul_nm),
         count(*) filter (where pg.haul <> o.haul)
    into v_n, v_moved
    from public.port_goods pg
    join world.haul_rows() h on h.port_id = pg.port_id and h.good_id = pg.good_id
    join hauls_0208 o on o.port_id = pg.port_id and o.good_id = pg.good_id;
  if v_n <> 0 or v_moved = 0 then
    raise exception '0208 self-assert FAIL: % market row(s) differ from world.haul_rows(), % moved', v_n, v_moved;
  end if;
  select count(*), max(abs((pg.haul - 1) - (o.haul - 1) / 2)) into v_n, v_maxdev
    from public.port_goods pg join hauls_0208 o on o.port_id = pg.port_id and o.good_id = pg.good_id
   where o.haul_nm is distinct from pg.haul_nm or abs((pg.haul - 1) - (o.haul - 1) / 2) > 0.00005;
  if v_n <> 0 then
    raise exception '0208 self-assert FAIL: % row(s) whose distance premium is not half the old one within the 4-dp rounding (worst %)', v_n, v_maxdev;
  end if;
  select (select max(abs((pg.haul - 1) - (o.haul - 1) / 2)) from public.port_goods pg join hauls_0208 o on o.port_id = pg.port_id and o.good_id = pg.good_id)
    into v_maxdev;
  -- the probe pair: the first row beyond the reach (by port and good code) — old 600, new exactly 300.5
  select p.code as port, g.code as good, o.haul as old_h, pg.haul as new_h, pg.port_id, pg.good_id into v_pair
    from public.port_goods pg
    join hauls_0208 o on o.port_id = pg.port_id and o.good_id = pg.good_id
    join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id
   where o.haul_nm >= public.wc_num('haul_reach_nm')
   order by p.code, g.code limit 1;
  if v_pair.port is null or v_pair.old_h <> public.wc_num('haul_max') or (v_pair.new_h - 1) * 2 <> (v_pair.old_h - 1) then
    raise exception '0208 self-assert FAIL: the probe pair % / % beyond the reach reads % → %, not a premium exactly halved', v_pair.port, v_pair.good, v_pair.old_h, v_pair.new_h;
  end if;
  select count(*) into v_n
    from hauls_0208 o
   where world.haul_at(o.haul_nm, public.wc_num('haul_max'), public.wc_num('haul_reach_nm'), public.wc_num('haul_curve'), 1)
         is distinct from pg_temp.haul_at_b0208(o.haul_nm, public.wc_num('haul_max'), public.wc_num('haul_reach_nm'), public.wc_num('haul_curve'))
      or o.haul is distinct from pg_temp.haul_at_b0208(o.haul_nm, public.wc_num('haul_max'), public.wc_num('haul_reach_nm'), public.wc_num('haul_curve'));
  if v_n <> 0 then
    raise exception '0208 self-assert FAIL: % row(s) where the new arithmetic at share 1 is not 0173''s (or the old row was not)', v_n;
  end if;

  -- (d) THE STORED PER-UNIT PRICES
  select count(*) into v_hist from hist_0208;
  select count(*) into v_n
    from hist_0208 h0
    join hauls_0208 o on o.port_id = h0.port_id and o.good_id = h0.good_id
    join public.port_goods pg on pg.port_id = h0.port_id and pg.good_id = h0.good_id
    left join public.price_history ph on ph.port_id = h0.port_id and ph.good_id = h0.good_id and ph.slot = h0.slot
   where ph.port_id is null or ph.mid <> round(h0.mid * 0.2 * pg.haul / o.haul, 4);
  if v_n <> 0 then
    raise exception '0208 self-assert FAIL: % of % price_history row(s) are not 0.2 × (new haul ÷ old haul) of their mid', v_n, v_hist;
  end if;
  select count(*) into v_n
    from basis_0208 b0 join public.ships s on s.id = b0.id
   cross join lateral jsonb_each(b0.cargo_basis) e
   where jsonb_typeof(e.value) = 'number'
     and (s.cargo_basis->>e.key)::numeric <> (e.value #>> '{}')::numeric * 0.2;
  select count(*) into v_m from basis_0208 b0 cross join lateral jsonb_each(b0.cargo_basis) e where jsonb_typeof(e.value) = 'number';
  if v_n <> 0 then
    raise exception '0208 self-assert FAIL: % of % cargo cost basis entries are not 0.2 ×', v_n, v_m;
  end if;
  if exists (select 1 from store_0208 x join public.player_storage s using (player_id, port_id, good_id) where s.basis <> x.basis * 0.2)
     or exists (select 1 from lines_0208 x join public.standing_route_lines l using (route_id, stop_ord, ord) where l.price_limit <> x.price_limit * 0.2)
     or exists (select 1 from orders_0208 x join public.orders o on o.id = x.id where (o.args->>'limit')::numeric <> (x.args->>'limit')::numeric * 0.2
                   or (x.raw_text ~* ' AT [0-9]+(\.[0-9]+)?$' and o.raw_text !~ (' AT ' || trim_scale((x.args->>'limit')::numeric * 0.2)::text || '$'))) then
    raise exception '0208 self-assert FAIL: a storage basis, a route line''s limit or an open order''s limit is not 0.2 ×';
  end if;

  -- (e) REPAIR COSTS UNCHANGED (the recipe value of every item), with a positive control: an item with a
  --     recipe whose value is not 0, so a recipe read at base_value alone would show ÷ 5
  select count(*) into v_n from recipe_0208 r where public.item_recipe_value(r.code) <> r.v;
  if v_n <> 0 or not exists (select 1 from recipe_0208 where v > 0) then
    raise exception '0208 self-assert FAIL: % item(s) whose recipe value (repair cost) moved', v_n;
  end if;

  -- (e) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0208 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0208 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0208(v_def, v_h.new) <> 1 then
        raise exception '0208 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0208 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_pp from pg_proc pr where pr.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0208 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if to_regprocedure('world.haul_at(numeric, numeric, numeric, numeric)') is not null
     or (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.haul_at(numeric, numeric, numeric, numeric, numeric)'::regprocedure)
        <> (select acl from haulat_before_0208)
     or (select p.provolatile from pg_proc p where p.oid = 'world.haul_at(numeric, numeric, numeric, numeric, numeric)'::regprocedure) <> 'i' then
    raise exception '0208 self-assert FAIL: world.haul_at is not one immutable 5-argument form with 0173''s ACL';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or exists (select 1 from unnest(array['anon', 'authenticated']) rl(role)
                 where has_function_privilege(rl.role, 'world.haul_at(numeric, numeric, numeric, numeric, numeric)', 'execute')) then
    raise exception '0208 self-assert FAIL: a wall moved, or a client can reach world.haul_at';
  end if;

  -- (f) TIMINGS (notice only): the quote path's bodies are unchanged; 8 calls each in this session
  select pr.port_id, pr.good_id into v_port, v_good from probe_0208 pr where pr.kind = 'quay' order by pr.port_code, pr.good_code limit 1;
  for i in 1..8 loop
    v_t := clock_timestamp();
    perform * from world.quote(v_port, v_good, 50, 'buy', null, null);
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
    v_t := clock_timestamp();
    perform * from world.price(v_port, v_good);
    v_pms := v_pms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
  end loop;

  raise notice '0208 self-assert ok: A HOLD CARRIES THREE TIMES, GOODS COST A FIFTH, AND DISTANCE PAYS HALF. HOLDS: % classes (% → % t … % → % t), % hold effects, % flat hold perk(s) × 3; % ships: % exactly 3 × rated and capacity, % within the per-cent''s rounding (capacity exactly 3 × on %); route_probe_tuns 150. PRICES: % goods × 0.2 (base % → %); % quay probes ÷ 5 within rounding (mid, ask, bid, 1/10 units both sides) at the same stock; % far probes at 0.2 × the haul''s move. HAUL: % rows = world.haul_rows(), % moved, every premium half within % (pair %/% %→%, exact); share 1 = 0173 on every row. STORED: % price_history rows, % cargo basis entries, % storage, % route-line limits, % open order limit(s) × 0.2. Repair costs: % items'' recipe value unchanged. 2 bodies reverse; haul_at 5 args, ACL kept. world.quote(50) ms %, world.price ms %.',
    (select count(*) from classes_0208), (select min(hold) from classes_0208), (select min(hold) from public.ship_classes),
    (select max(hold) from classes_0208), (select max(hold) from public.ship_classes),
    (select count(*) from effects_0208), (select count(*) from perks_0208),
    v_ships, v_exact, v_near, v_cap_x,
    (select count(*) from goods_0208), (select min(base_value) from goods_0208), (select min(base_value) from public.goods),
    v_quay, v_far,
    v_rows, v_moved, v_maxdev, v_pair.port, v_pair.good, v_pair.old_h, v_pair.new_h,
    v_hist, v_m, (select count(*) from store_0208), (select count(*) from lines_0208), (select count(*) from orders_0208),
    (select count(*) from recipe_0208), v_ms, v_pms;
end $$;
