-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0285 — GOODS PRICES ARE RE-BASED ONTO THE DESIGN LEVEL
--        (0208's exact inverse, after 0282 cashed the holds out: the stored goods.base_value × 5
--         and the knob goods_price_level 0.2 → 1.0; no persistent function is re-cut or created)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S INSTRUCTION ────────────────────────────────────────────────────────────────────
--   "the merchants and players holding the trade goods that are based before, convert them into
--    cash first then do the work." (2026-10-30)
--   The first half is LIVE: 0282 (20260818000282_the_old_hold_is_cashed_out_before_reprice.sql)
--   priced every held trade good at the old goods.base_value, credited each house once, and emptied
--   the holds. This file is the second half: the re-base itself.
--
-- ── THE MEASURED STATE (prod, read-only, 2026-10-31, head 20260818000284) ──────────────────────
--   goods: 629; base_value numeric(10,2); min 0.80, max 660.00; knob goods_price_level 0.2.
--   The design sheet docs/design/raw-materials-economy/GOODS_SAVED.csv carries a price band per
--   good; its MIDPOINT equals the live goods.base_value × 5 for 584 of 584 sheet goods, exactly
--   (live × 5 / midpoint = 1.000000 on every one; the reciprocal, midpoint / live, is 5.000000).
--   Three named goods: black-pepper 30.00 → 150 (band [110,190]), cinnamon 120.00 → 600
--   ([400,800]), saffron 390.00 → 1950 ([1300,2600]). The catalogue is therefore at design ÷ 5.
--   The 45 goods not on the sheet are the raw inputs 0280 added; their bands are [v,v], so the
--   same × 5 rule restores their authored value too.
--   ONLY public.item_recipe_value(text) reads goods_price_level (prod scan of every function body
--   in public/cmd/world/voyage): it returns Σ(qty × base_value / wc_num('goods_price_level')), the
--   DESIGN value, so repair costs do not move. 222 item recipe products were measured on prod:
--   item_recipe_value = 5 × Σ(qty × base_value) exactly on every one (0 mismatches).
--   public.port_goods stores no price; quotes derive from goods.base_value at read time
--   (world.mid_terms → world.mid_from_terms). 154,734 market rows, one per (port, good).
--
-- ── WHY NOW ────────────────────────────────────────────────────────────────────────────────────
--   0282 cashed the holds out FIRST, so no house carries stock bought at the old basis across this
--   reprice. This file must follow it; from the commit that carries it, the game's prices are the
--   design's real-world values.
--
-- ── WHAT MOVES ─────────────────────────────────────────────────────────────────────────────────
--   Exactly two statements:
--     update public.goods set base_value = round(base_value * 5, 2);          -- 629 rows, exactly
--     update public.world_config set value = to_jsonb(1.0), updated_at = now()
--      where key = 'goods_price_level';
--   The column is numeric(10,2) (asserted), so × 5 is exact to its authored precision; round(...)
--   states that precision, it does not change a value. Every market mid / ask / bid / quote, the
--   next price-history point, the merchants' parcels and every price the client reads follow from
--   the column; nothing else needs a hunk.
--
-- ── WHAT DOES NOT MOVE ────────────────────────────────────────────────────────────────────────
--   No persistent function body is re-cut or created (the self-assert holds the md5 of every
--   function in public/cmd/world/voyage equal; the pg_temp helpers die with this transaction).
--   No ACL, volatility, definer or config moves. No column type. No market row: port_goods' stock /
--   affinity / stock_target / drift are asserted unchanged (154,734 rows, md5). No goods recipe
--   (goods_recipes), no item recipe (item_recipes), no player row, no purse, no ledger, no event,
--   no order, no standing route, no contract. public.item_recipe_value's answer is unchanged for
--   every item recipe product — the knob and the column cancel (× 5 on the column, ÷ 5 off the
--   knob) — which is the proof that the two moved together.
--
-- ── SUPERSEDE ─────────────────────────────────────────────────────────────────────────────────
--   This is 0208's exact inverse at the price level: 0208 set goods_price_level = 0.2 and applied
--   it once to the stored column; 0285 multiplies the stored column by 5 and sets the knob to 1.0.
--   It re-cuts NO function and supersedes NO body; 0208's world.haul_at / world.haul_rows /
--   public.item_recipe_value hunks stay exactly as they are. The knob's 0208 value is superseded.
--
-- ── SELF-ASSERT (all inside the applying transaction; the probe is rolled back) ───────────────
--   (a) goods count unchanged; every base_value exactly 5 × its as-found value (0 mismatches);
--       the column still numeric(10,2);
--   (b) goods_price_level reads 1.0 (stored jsonb and wc_num);
--   (c) min > 0, no NaN / Infinity; min and max exactly 5 × the as-found extremes;
--   (d) the invariant: public.item_recipe_value is UNCHANGED for every item recipe product (222
--       on prod; at least 10 asserted, every one checked, at least one non-zero);
--   (e) port_goods count and md5 unchanged; every function in public/cmd/world/voyage count and
--       md5 unchanged;
--   (f) a rolled-back probe on one harbour good: read world.price and world.quote, scale that one
--       good × 5 inside a subtransaction, read again, assert mid / ask / bid / avg_price / total
--       are ~5× (each ratio between 4.9 and 5.1), then the rollback restored the good's base_value
--       and no row was left behind. This proves the stored column is what the market prices from.
--   The closing receipt names every figure.
--
-- ── PROD CHECKS (read-only, one SELECT per file; run before the push) ─────────────────────────
--   Expected as found on 2026-10-31 (head 20260818000284):
--     head 20260818000284; 629 goods; goods_price_level 0.2; base_value numeric(10,2);
--     min 0.80, max 660.00; sheet goods 584/584 with live × 5 = midpoint exactly;
--     black-pepper 30, cinnamon 120, saffron 390; 222 item recipe products, item_recipe_value
--     = 5 × Σ(qty × base) exactly on every one; the only knob reader is public.item_recipe_value;
--     154,734 port_goods rows, md5 f627d4d00cd87f85c45c6df5870c09c3; 663 functions in
--     public/cmd/world/voyage, md5 f19520b6eb631df8369548d33effe258; goods md5
--     3adca72ea3155940baf8df76cafaa494.
--   After the push (read-only):
--     goods_price_level 1.0; 629 goods; min 4.00, max 3300.00; goods md5
--     4736510b504ab865a687ac614b56c690; black-pepper 150, cinnamon 600, saffron 1950;
--     the same 222 item recipe values unchanged; port_goods md5 and count unchanged;
--     the same 663 functions, md5 unchanged.
--   The exact SQL blocks are in docs/dev-log/2026-10-31-goods-price-level.md §PROD CHECKS and in
--   the PR body.
--
-- ── FORWARD ROLLBACK (a new migration, never an edit of this one) ─────────────────────────────
--   The inverse: update public.goods set base_value = round(base_value / 5, 2);
--                update public.world_config set value = to_jsonb(0.2), updated_at = now()
--                 where key = 'goods_price_level';
--   (the same two statements in the other direction; port_goods and every function stay untouched).
--   Prices × 5 means every live trade, merchant parcel and city purse moves against the new level;
--   the forward rollback is ready but only the owner may call for it.
--
-- VERSION: 0285 (prod head 0284).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
declare
  v_col     text;
  v_bad_n   int;
  v_bad     text;
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.goods') is null
     or to_regclass('public.port_goods') is null
     or to_regclass('public.world_config') is null
     or to_regclass('public.item_recipes') is null
     or to_regprocedure('public.wc_num(text)') is null
     or to_regprocedure('public.item_recipe_value(text)') is null
     or to_regprocedure('public.port_offers(uuid, uuid)') is null
     or to_regprocedure('world.price(uuid, uuid)') is null
     or to_regprocedure('world.quote(uuid, uuid, numeric, text, numeric, uuid)') is null then
    raise exception '0285 refuses: the tables or functions this file reads are not in this world';
  end if;
  select c.data_type || '|' || coalesce(c.numeric_precision::text, '') || '|' || coalesce(c.numeric_scale::text, '')
    into v_col
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'goods' and c.column_name = 'base_value';
  if v_col is distinct from 'numeric|10|2' then
    raise exception '0285 refuses: goods.base_value is %, not numeric(10,2) — this file keeps its authored precision', v_col;
  end if;
  if not exists (select 1 from public.world_config where key = 'goods_price_level') then
    raise exception '0285 refuses: goods_price_level is missing — 0208 is not in this world';
  end if;
  if public.wc_num('goods_price_level') = 1.0 then
    raise exception '0285 refuses: goods_price_level already reads 1.0 — this has been applied once';
  end if;
  if public.wc_num('goods_price_level') is distinct from 0.2 then
    raise exception '0285 refuses: goods_price_level reads %, not 0.2 — this is not the state 0208 wrote and 0285 inverts',
      public.wc_num('goods_price_level');
  end if;
  if (select count(*) from public.goods) = 0 then
    raise exception '0285 refuses: no goods to re-base';
  end if;
  select count(*), string_agg(g.code, ', ' order by g.code)
    into v_bad_n, v_bad
    from public.goods g
   where g.base_value is null
      or g.base_value <= 0
      or g.base_value = 'NaN'::numeric
      or g.base_value = 'Infinity'::numeric
      or g.base_value = '-Infinity'::numeric;
  if v_bad_n > 0 then
    raise exception '0285 refuses: % good(s) with a non-finite or <= 0 base_value: %', v_bad_n, v_bad;
  end if;
end $guard$;

-- ── THE WINDOW ────────────────────────────────────────────────────────────────────────────────
-- port_goods is the one table the live game writes inside the reads below (a trade moves stock, the
-- drift job moves drift). SHARE conflicts with ROW EXCLUSIVE, so no trade or drift can move a row
-- between the as-found digest and the after digest. Reads are unaffected; the lock is held to the
-- end of this file's one transaction. (A top-level LOCK TABLE has no transaction under db push;
-- inside a DO block it lives in the statement's transaction, as 0282 established.)
do $lock$
begin
  perform set_config('lock_timeout', '5s', true);
  lock table public.port_goods in share mode;
end $lock$;

-- ── THE DIGEST HELPERS (pg_temp; gone at commit, never a deployed function) ───────────────────
create function pg_temp.goods_md5_0285()
returns text
language sql
stable
as $$
  select md5(string_agg(g.code || '|' || g.base_value, E'\n' order by g.code))
    from public.goods g
$$;

create function pg_temp.port_goods_md5_0285()
returns text
language sql
stable
as $$
  select md5(string_agg(pg.port_id::text || '|' || pg.good_id::text || '|' || pg.stock || '|' ||
                        pg.affinity || '|' || pg.stock_target || '|' || pg.drift,
                        E'\n' order by pg.port_id, pg.good_id))
    from public.port_goods pg
$$;

create function pg_temp.fns_n_0285()
returns int
language sql
stable
as $$
  select count(*)::int
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
$$;

create function pg_temp.fns_md5_0285()
returns text
language sql
stable
as $$
  select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')),
                        ',' order by p.oid::regprocedure::text))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
$$;

-- ── AS FOUND ──────────────────────────────────────────────────────────────────────────────────
create temp table snap_0285 on commit drop as
select
  (select count(*) from public.goods)               as goods_n,
  pg_temp.goods_md5_0285()                          as goods_md5,
  public.wc_num('goods_price_level')                as knob,
  (select count(*) from public.port_goods)          as port_goods_n,
  pg_temp.port_goods_md5_0285()                     as port_goods_md5,
  pg_temp.fns_n_0285()                              as fns_n,
  pg_temp.fns_md5_0285()                            as fns_md5,
  (select min(base_value) from public.goods)        as base_min,
  (select max(base_value) from public.goods)        as base_max;

create temp table goods_0285 on commit drop as
select g.id, g.code, g.base_value from public.goods g;

create temp table recipe_0285 on commit drop as
select distinct ir.item_code as code, public.item_recipe_value(ir.item_code) as v
  from public.item_recipes ir;

-- ── THE CHANGE — exactly two statements ───────────────────────────────────────────────────────
update public.goods set base_value = round(base_value * 5, 2);

update public.world_config set value = to_jsonb(1.0), updated_at = now() where key = 'goods_price_level';

-- ── SELF-ASSERT ───────────────────────────────────────────────────────────────────────────────
do $$
declare
  v        record;
  v_n      int;
  v_bad    int;
  v_min    numeric;
  v_max    numeric;
  v_gmd5   text;
  v_rc_n   int;
  v_rc_bad int;
  v_port   uuid;
  v_good   uuid;
  v_pcode  text;
  v_gcode  text;
  v_base   numeric;
  v_now    numeric;
  v_b      record;
  v_s      record;
  v_qb     record;
  v_qs     record;
  v_mid_x  numeric;
  v_ask_x  numeric;
  v_bid_x  numeric;
  v_avg_x  numeric;
  v_tot_x  numeric;
begin
  select * into v from snap_0285;

  -- (a) SAME ROWS, SAME COLUMN, EVERY VALUE EXACTLY × 5 ITS AS-FOUND VALUE
  if (select count(*) from public.goods) <> v.goods_n or v.goods_n = 0 then
    raise exception '0285 self-assert FAIL: goods count % -> %', v.goods_n, (select count(*) from public.goods);
  end if;
  if (select count(*)
        from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'goods' and c.column_name = 'base_value'
         and c.data_type = 'numeric' and c.numeric_precision = 10 and c.numeric_scale = 2) <> 1 then
    raise exception '0285 self-assert FAIL: goods.base_value is no longer numeric(10,2)';
  end if;
  select count(*) into v_n
    from goods_0285 b join public.goods g on g.id = b.id
   where g.base_value is distinct from b.base_value * 5;
  if v_n <> 0 then
    raise exception '0285 self-assert FAIL: % good(s) whose new base_value is not exactly 5 x its as-found value', v_n;
  end if;
  if exists (select 1 from goods_0285 b where not exists (select 1 from public.goods g where g.id = b.id)) then
    raise exception '0285 self-assert FAIL: a good vanished during the re-base';
  end if;

  -- (b) THE KNOB READS 1.0
  if v.knob is distinct from 0.2 then
    raise exception '0285 self-assert FAIL: the as-found knob reads %, not 0.2', v.knob;
  end if;
  if public.wc_num('goods_price_level') is distinct from 1.0 then
    raise exception '0285 self-assert FAIL: goods_price_level reads %, not 1.0', public.wc_num('goods_price_level');
  end if;
  if (select count(*) from public.world_config where key = 'goods_price_level' and value = to_jsonb(1.0::numeric)) <> 1 then
    raise exception '0285 self-assert FAIL: world_config''s goods_price_level row is not the jsonb 1.0';
  end if;

  -- (c) POSITIVE, FINITE, AND THE EXTREMES FOLLOW THE MULTIPLICATION
  select count(*) into v_bad
    from public.goods
   where base_value <= 0
      or base_value = 'NaN'::numeric
      or base_value = 'Infinity'::numeric
      or base_value = '-Infinity'::numeric;
  if v_bad <> 0 then
    raise exception '0285 self-assert FAIL: % good(s) with a non-finite or <= 0 base_value after the re-base', v_bad;
  end if;
  select min(base_value), max(base_value) into v_min, v_max from public.goods;
  if v_min is null or v_min <= 0 or v_min <> v.base_min * 5 or v_max <> v.base_max * 5 then
    raise exception '0285 self-assert FAIL: the extremes moved wrong: min % -> % (expected %), max % -> % (expected %)',
      v.base_min, v_min, v.base_min * 5, v.base_max, v_max, v.base_max * 5;
  end if;

  -- (d) THE INVARIANT: item_recipe_value (the knob's ONE reader) UNCHANGED ON EVERY RECIPE PRODUCT
  select count(*), count(*) filter (where public.item_recipe_value(r.code) is distinct from r.v)
    into v_rc_n, v_rc_bad
    from recipe_0285 r;
  if v_rc_n < 10 then
    raise exception '0285 self-assert FAIL: only % item recipe product(s) measured — the invariant would be thin', v_rc_n;
  end if;
  if v_rc_bad <> 0 then
    raise exception '0285 self-assert FAIL: % of % item recipe value(s) moved', v_rc_bad, v_rc_n;
  end if;
  if v_rc_n <> (select count(distinct item_code) from public.item_recipes) then
    raise exception '0285 self-assert FAIL: % recipe product(s) measured of %',
      v_rc_n, (select count(distinct item_code) from public.item_recipes);
  end if;
  if not exists (select 1 from recipe_0285 r where r.v > 0) then
    raise exception '0285 self-assert FAIL: every measured recipe value is zero — the invariant is vacuous';
  end if;

  -- (e) NOTHING ELSE MOVED: the market rows and every function
  if (select count(*) from public.port_goods) <> v.port_goods_n then
    raise exception '0285 self-assert FAIL: port_goods count % -> %', v.port_goods_n, (select count(*) from public.port_goods);
  end if;
  if pg_temp.port_goods_md5_0285() is distinct from v.port_goods_md5 then
    raise exception '0285 self-assert FAIL: port_goods moved (md5 % -> %)', v.port_goods_md5, pg_temp.port_goods_md5_0285();
  end if;
  if pg_temp.fns_n_0285() <> v.fns_n or pg_temp.fns_md5_0285() is distinct from v.fns_md5 then
    raise exception '0285 self-assert FAIL: a function in public/cmd/world/voyage moved (% -> %, md5 % -> %)',
      v.fns_n, pg_temp.fns_n_0285(), v.fns_md5, pg_temp.fns_md5_0285();
  end if;

  -- (f) THE MARKET PRICES FROM THE STORED COLUMN — a rolled-back probe on one harbour good
  select pg.port_id, pg.good_id, p.code, g.code, g.base_value
    into v_port, v_good, v_pcode, v_gcode, v_base
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
    join public.goods g on g.id = pg.good_id
   where public.port_offers(pg.port_id, pg.good_id)
     and pg.stock >= 100
   order by g.base_value desc, p.code, g.code
   limit 1;
  if v_port is null then
    raise exception '0285 self-assert FAIL: no harbour good with stock >= 100 to probe';
  end if;
  select * into v_b from world.price(v_port, v_good);
  select * into v_qb from world.quote(v_port, v_good, 10, 'buy', null, null);
  if v_b.mid is null or v_b.ask is null or v_b.bid is null
     or v_b.mid <= 0 or v_b.ask <= 0 or v_b.bid <= 0
     or v_qb.avg_price is null or v_qb.avg_price <= 0 or v_qb.total is null or v_qb.total <= 0 then
    raise exception '0285 self-assert FAIL: the probe pair %/% has no live quote', v_pcode, v_gcode;
  end if;
  begin
    update public.goods set base_value = round(base_value * 5, 2) where id = v_good;
    select * into v_s from world.price(v_port, v_good);
    select * into v_qs from world.quote(v_port, v_good, 10, 'buy', null, null);
    raise exception using errcode = 'ZX285', message = 'probe ok';
  exception when sqlstate 'ZX285' then
    null;
  end;
  select base_value into v_now from public.goods where id = v_good;
  if v_now is distinct from v_base then
    raise exception '0285 self-assert FAIL: the rolled-back probe did not restore %/% base_value: % -> %',
      v_pcode, v_gcode, v_base, v_now;
  end if;
  if (select count(*) from public.goods) <> v.goods_n then
    raise exception '0285 self-assert FAIL: the probe left a good behind';
  end if;
  v_mid_x := v_s.mid / v_b.mid;
  v_ask_x := v_s.ask / v_b.ask;
  v_bid_x := v_s.bid / v_b.bid;
  v_avg_x := v_qs.avg_price / v_qb.avg_price;
  v_tot_x := v_qs.total::numeric / v_qb.total::numeric;
  if v_mid_x not between 4.9 and 5.1
     or v_ask_x not between 4.9 and 5.1
     or v_bid_x not between 4.9 and 5.1
     or v_avg_x not between 4.9 and 5.1
     or v_tot_x not between 4.9 and 5.1 then
    raise exception '0285 self-assert FAIL: %/% scaled x5 moved mid/ask/bid/avg_price/total by %/%/%/%/%, not ~5',
      v_pcode, v_gcode, v_mid_x, v_ask_x, v_bid_x, v_avg_x, v_tot_x;
  end if;

  -- (g) THE RECEIPT
  v_gmd5 := pg_temp.goods_md5_0285();
  raise notice '0285 self-assert ok: GOODS PRICES ARE AT THE DESIGN LEVEL. % goods (md5 % -> %), every one exactly 5 x its as-found base_value; goods_price_level % -> %; min % -> %, max % -> %; % item recipe products unchanged (min %); port_goods % rows, md5 %; % functions, md5 %; rolled-back probe %/% base % -> % moved mid/ask/bid/avg_price/total by %/%/%/%/%, rollback restored %. Nothing else moved; no row left behind.',
    v.goods_n, v.goods_md5, v_gmd5,
    v.knob, public.wc_num('goods_price_level'),
    v.base_min, v_min, v.base_max, v_max,
    v_rc_n, (select min(r.v) from recipe_0285 r),
    v.port_goods_n, v.port_goods_md5,
    v.fns_n, v.fns_md5,
    v_pcode, v_gcode, v_base, round(v_base * 5, 2),
    round(v_mid_x, 6), round(v_ask_x, 6), round(v_bid_x, 6), round(v_avg_x, 6), round(v_tot_x, 6),
    v_now;
end $$;
