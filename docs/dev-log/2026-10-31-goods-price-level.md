# 2026-10-31 — 0285: goods prices re-based onto the design level (0208's inverse, after 0282's cash-out)

**The slice:** ONE migration — `supabase/migrations/20260818000285_goods_prices_at_design_level.sql`.
No client, no test, no other function. It is the second half of the owner's instruction; 0282 was
the first.

**State while this is written:** AUTHORED and GATED on the local cached chain (receipt below),
committed and pushed as a PR. **NOT deployed** — the main session deploys; the prod head must
read `20260818000284` and 0285 is the next number.

## 1. The instruction, and why now

The owner, 2026-10-30, verbatim:

> "the merchants and players holding the trade goods that are based before, convert them into
> cash first then do the work."

The first half is **LIVE**: 0282
(`20260818000282_the_old_hold_is_cashed_out_before_reprice.sql`) priced every held trade good at
the old `public.goods.base_value`, credited each house once (`LIQUIDATION`, a moved-wealth kind),
and emptied `ships.cargo` / `player_storage`. This file is the second half: the re-base itself.

0208 (`20260818000208_…`) set the knob `goods_price_level = 0.2` and applied it **once** to the
stored column:

```
update public.goods set base_value = base_value * public.wc_num('goods_price_level');
```

Its header says the knob has exactly one place it is applied. The one reader of the knob is
`public.item_recipe_value(text)`, which returns
`Σ(qty × goods.base_value / wc_num('goods_price_level'))` — the DESIGN value, so repair costs stay
at the design level. 0285 is the exact inverse: the stored column × 5 and the knob 0.2 → 1.0.

## 2. The measurement (prod, read-only, 2026-10-31, head `20260818000284`)

| fact | value |
|---|---|
| head | `20260818000284` |
| goods | **629** |
| `goods.base_value` type | **numeric(10,2)** |
| min / max base_value | **0.80 / 660.00** |
| `goods_price_level` | **0.2** |
| design sheet `GOODS_SAVED.csv` | **584 goods** with a band |
| sheet midpoint vs live | live × 5 / midpoint = **1.000000 on 584/584** (design ÷ live = **5.000000**) |
| black-pepper | band [110,190] → midpoint 150; live 30.00 → ×5 **150** |
| cinnamon | band [400,800] → midpoint 600; live 120.00 → ×5 **600** |
| saffron | band [1300,2600] → midpoint 1950; live 390.00 → ×5 **1950** |
| item recipe products (`item_recipes`) | **222**; `item_recipe_value = 5 × Σ(qty × base)` **exactly on 222/222**, 0 mismatches (min 173.5, max 18,597) |
| knob readers (`prosrc` scan, public/cmd/world/voyage) | **only `public.item_recipe_value`** |
| `port_goods` | **154,734** rows (one per port+good), md5 `f627d4d00cd87f85c45c6df5870c09c3` |
| functions in public/cmd/world/voyage | **663**, md5 `f19520b6eb631df8369548d33effe258` |
| goods md5 | `3adca72ea3155940baf8df76cafaa494` |
| probe pair | **AGA / gold**, base 660.00, stock 2898.13; `world.price` mid 521.1296 / ask 529.47 / bid 512.79; `world.quote` 10 buy avg 529.62, total 5297 |

The 45 goods not on the sheet are the raw inputs 0280 added; their bands are `[v,v]`, so the same
×5 rule restores their authored value too. The catalogue is therefore at design ÷ 5 today.

Expected after the re-base: knob **1.0**; min **4.00**, max **3300.00**; goods md5
**`4736510b504ab865a687ac614b56c690`**; the three named goods **150 / 600 / 1950**; the 222 item
recipe values unchanged; `port_goods` and the 663 function definitions unchanged (the migration's
self-assert holds before = after inside its own transaction).

## 3. The change — exactly two statements

```sql
update public.goods set base_value = round(base_value * 5, 2);          -- 629 rows, exactly

update public.world_config set value = to_jsonb(1.0), updated_at = now()
 where key = 'goods_price_level';
```

The column is `numeric(10,2)` (asserted in the guard), so ×5 is exact to its authored precision;
`round(...,2)` states that precision and changes no value. Every market mid / ask / bid / quote,
the next price-history point, the merchants' parcels and every price the client reads derive from
the column; no function needs a hunk.

**What does not move:** no persistent function body (the four-schema md5 is asserted unchanged),
no ACL / volatility / definer / config, no column type, no `port_goods` row (count + md5 asserted
unchanged inside the transaction), no goods recipe, no item recipe, no player row, no purse, no
ledger, no event, no order, no standing route, no contract. `public.item_recipe_value` is
unchanged for every item recipe product — ×5 on the column and ÷5 off the knob cancel — which is
the proof that the knob and the column moved together.

## 4. The self-assert and its rolled-back probe

- **As found**: goods count, goods md5, knob, `port_goods` count + md5, function count + md5,
  min/max base_value, and every good's base_value; every item recipe product's
  `item_recipe_value`.
- **The guard** refuses a missing knob, a knob already 1.0 (double apply), any knob other than 0.2,
  a non-`numeric(10,2)` column, a missing table/function, and any non-finite or ≤0 base_value.
- **After**: every good exactly 5 × its as-found value (0 mismatches); the knob reads 1.0; min > 0
  and no NaN/Infinity; min/max exactly 5 × the as-found extremes; `item_recipe_value` unchanged on
  every recipe product (≥10 asserted non-vacuously, at least one non-zero); `port_goods` count and
  md5 unchanged; every function in public/cmd/world/voyage count and md5 unchanged.
- **The probe** (subtransaction, `ZX285` sentinel, rolled back): pick the highest-base harbour good
  with stock ≥ 100, read `world.price` and `world.quote`, scale that one good ×5 inside the
  subtransaction, read again, assert mid / ask / bid / avg_price / total are each **between 4.9×
  and 5.1×**, then assert the rollback restored the good's base_value and no row was left behind.
  This proves the stored column is what the market prices from.

The receipt (verbatim, from the p0273 prefix-cache manifest):

> `0285 self-assert ok: GOODS PRICES ARE AT THE DESIGN LEVEL. 629 goods (md5 3adca72ea3155940baf8df76cafaa494 -> 4736510b504ab865a687ac614b56c690), every one exactly 5 x its as-found base_value; goods_price_level 0.2 -> 1.0; min 0.80 -> 4.00, max 660.00 -> 3300.00; 222 item recipe products unchanged (min 173.5000000000000000); port_goods 154734 rows, md5 8a03268648ce22510d72b31978176fe7; 663 functions, md5 b8d384eea49137b6f8860f28ca5e07b4; rolled-back probe AGA/gold base 3300.00 -> 16500.00 moved mid/ask/bid/avg_price/total by 5.000000/5.000003/5.000004/5.000003/4.999898, rollback restored 3300.00. Nothing else moved; no row left behind.`

**The local vs prod digests, stated plainly.** The goods md5s match prod exactly
(`3adca72… → 4736510b…`), because the catalogue is deterministic. The `port_goods` md5
(`8a0326…`) and the function md5 (`b8d384…`) in this local receipt are the **local PGlite world's**
state: its stock/drift were seeded, not prod's live market, and PGlite is PostgreSQL 18.3 while
prod formats some function definitions differently. The migration asserts **before = after inside
whichever world it runs**; the prod-specific absolute values are in §6.

## 5. The gate (local, cached chain — not a from-zero replay)

```bash
node scripts/db/check-versions.mjs
BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing
npx playwright test tests/duplication.spec.ts --reporter=line
```

`check-versions`:

```
OK: 273 migration(s) in C:\Users\gkwng\dev\wt-price-level\supabase\migrations
    273 distinct version(s), no collisions, all filenames well-formed.
    positive control: the probe DID detect a deliberately duplicated version.
```

`proof.mjs standing` (verbatim):

```
prefix cache: restored 272/273 migration(s) from preamble-p0272-a59c12671216d70138cb3450 in 3.1 s (key a59c12671216d701 = this chain's first 272 file(s), names and content digest verified); applying 1
prefix cache: snapshot after 273 file(s) — 86.56 MB, round trip verified
chain: 273 migration(s) — 272 restored from the prefix cache (preamble-p0272-a59c12671216d70138cb3450), 1 applied here — 273 with a self-assert receipt (279 receipt line(s)); chain key a5e8974f93c76828, 11.0 s
world-guard ok: the applied world EQUALS data/*.json — 246 harbours, 629 goods, 1380 offers, 154734 market rows, … (positive control fired)
✓ 11_standing_route.sql  — 5/5 PASS markers in 0.6 s
PROOFS PASSED: 1 file(s), 5/5 PASS markers seen
```

`duplication`: **11/11 passed** (the migration-proves-itself rule, the supersede rule and every
other guard).

**Gate-found defect, fixed before commit.** The first run failed at 0285 with SQLSTATE 42702,
`column reference "v" is ambiguous`: the self-assert's PL/pgSQL record variable `v` collided with
the `recipe_0285.v` column in two unqualified references (`where v > 0` and `min(v)`). Both were
qualified (`r.v`). The failed run applied nothing at 0285 (the cache snapshot was after 272 files,
head 0284); the rerun above is green. This is the diagnostic rerun, not a blind re-run.

## 6. PROD CHECKS FOR THE MAIN SESSION

Run each block as one statement (`npx --yes supabase@2.120.0 db query --linked -f <file>`), read-only.
Every function called here is `stable` (`world.price`, `world.quote`, `public.item_recipe_value`,
`public.port_offers`). Expected as found on 2026-10-31 (head `20260818000284`).

```sql
select
  (select max(version) from supabase_migrations.schema_migrations) as head,          -- 20260818000284
  (select count(*) from public.goods) as goods,                                      -- 629
  (select value from public.world_config where key = 'goods_price_level') as knob,    -- 0.2
  (select jsonb_build_object('type', data_type, 'precision', numeric_precision, 'scale', numeric_scale)
     from information_schema.columns
    where table_schema = 'public' and table_name = 'goods' and column_name = 'base_value') as base_value_col,
                                                                                         -- {"type":"numeric","precision":10,"scale":2}
  (select min(base_value) from public.goods) as min_base,                            -- 0.80
  (select max(base_value) from public.goods) as max_base,                            -- 660.00
  (select jsonb_object_agg(code, base_value) from public.goods
    where code in ('black-pepper', 'cinnamon', 'saffron')) as named_goods;
                                                                                         -- black-pepper 30, cinnamon 120, saffron 390
```

```sql
with r as (
  select ir.item_code, sum(ir.qty * g.base_value) as sum_base
    from public.item_recipes ir join public.goods g on g.id = ir.good_id
   group by ir.item_code
)
select
  (select count(*) from r) as recipe_items,                                          -- 222
  (select count(*) from r where public.item_recipe_value(item_code) = sum_base * 5) as exact_5x,
                                                                                         -- 222
  (select count(*) from r where public.item_recipe_value(item_code) is distinct from sum_base * 5) as mismatch,
                                                                                         -- 0
  (select jsonb_agg(n.nspname || '.' || p.proname order by n.nspname, p.proname)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
      and p.prosrc like '%goods_price_level%') as knob_readers,
                                                                                         -- ["public.item_recipe_value"]
  (select md5(string_agg(g.code || '|' || g.base_value, E'\n' order by g.code)) from public.goods g) as goods_md5,
                                                                                         -- 3adca72ea3155940baf8df76cafaa494
  (select md5(string_agg(pg.port_id::text || '|' || pg.good_id::text || '|' || pg.stock || '|' ||
                         pg.affinity || '|' || pg.stock_target || '|' || pg.drift,
                         E'\n' order by pg.port_id, pg.good_id)) from public.port_goods pg) as port_goods_md5,
                                                                                         -- f627d4d00cd87f85c45c6df5870c09c3
  (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns_md5,
                                                                                         -- f19520b6eb631df8369548d33effe258
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns_n;
                                                                                         -- 663
```

```sql
with p as (
  select pg.port_id, pg.good_id, p.code as port_code, g.code as good_code, g.base_value, pg.stock
    from public.port_goods pg
    join public.goods g on g.id = pg.good_id
    join public.ports p on p.id = pg.port_id
   where public.port_offers(pg.port_id, pg.good_id) and pg.stock >= 100
   order by g.base_value desc, p.code, g.code
   limit 1
)
select p.port_code, p.good_code, p.base_value, p.stock,
       (select row_to_json(x) from world.price(p.port_id, p.good_id) x) as price,
       (select row_to_json(q) from world.quote(p.port_id, p.good_id, 10, 'buy', null, null) q) as quote
  from p;
-- 2026-10-31: AGA / gold, base 660.00; price mid 521.1296, ask 529.47, bid 512.79;
--             quote 10 buy avg_price 529.62, total 5297. Stock and quote move with live play.
```

**After the push** (read-only):

```sql
select
  (select value from public.world_config where key = 'goods_price_level') as knob,    -- 1.0
  (select count(*) from public.goods) as goods,                                      -- 629
  (select min(base_value) from public.goods) as min_base,                            -- 4.00
  (select max(base_value) from public.goods) as max_base,                            -- 3300.00
  (select jsonb_object_agg(code, base_value) from public.goods
    where code in ('black-pepper', 'cinnamon', 'saffron')) as named_goods,            -- 150 / 600 / 1950
  (select md5(string_agg(g.code || '|' || g.base_value, E'\n' order by g.code)) from public.goods g) as goods_md5,
                                                                                         -- 4736510b504ab865a687ac614b56c690
  (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns_md5,
                                                                                         -- f19520b6eb631df8369548d33effe258
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns_n;
                                                                                         -- 663
```

```sql
with r as (
  select ir.item_code, sum(ir.qty * g.base_value) as sum_base
    from public.item_recipes ir join public.goods g on g.id = ir.good_id
   group by ir.item_code
)
select count(*) as recipe_items,                                                         -- 222
       count(*) filter (where public.item_recipe_value(item_code) = sum_base) as exact_design_value,
                                                                                         -- 222
       count(*) filter (where public.item_recipe_value(item_code) is distinct from sum_base) as mismatch
  from r;                                                                                -- 0
```

**Do not expect the after-deploy `port_goods` md5 to equal `f627d4…`.** That md5 was taken before
the push; the live market keeps moving (stock, drift) between the pre-flight read and the deploy.
The migration's own self-assert holds `port_goods` count + md5 equal **inside its applying
transaction** (the receipt above is that proof); the pre-flight value is the baseline, not a
post-deploy expectation. The function and goods digests are stable and must match.

**After the deploy, report the economy** (never switch anything): `under_thin`, `broke`,
`debtors`, world `total`. Prices are ×5, so these counts are the watch; the economy switch remains
owner-only.

## 7. Forward rollback (ready, not applied)

One new migration, the exact inverse (never an edit of this file):

```sql
update public.goods set base_value = round(base_value / 5, 2);
update public.world_config set value = to_jsonb(0.2), updated_at = now()
 where key = 'goods_price_level';
```

Every holder was already cashed out by 0282, so the rollback is a pure re-denomination; there are
no holds to re-cash. `port_goods`, recipes and every function stay untouched. Only the owner may
call for it.

## 8. What is unproven

- The prod push itself: the main session runs `~/bin/bv-deploy.sh`; this file has not been applied
  to prod.
- The live market's real prices after the push, and the economy counts (`under_thin`, `broke`,
  `debtors`, `total`) — to be reported after the deploy.
- The local receipt's `port_goods` / function md5s are the local world's, as explained in §4; the
  prod-specific absolute values are the ones in §6.

## 9. Files

- `supabase/migrations/20260818000285_goods_prices_at_design_level.sql` — the one slice.
- `docs/dev-log/2026-10-31-goods-price-level.md` — this file.
- `docs/OWNER_REQUESTS.md` — owner row 240.
- `docs/WORK_QUEUE.md` — one line at the top.
- No client, no test, no other function.
