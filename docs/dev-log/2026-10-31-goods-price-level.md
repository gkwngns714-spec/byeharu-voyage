# 2026-10-31 — 0285: the WHOLE-SCALE re-base onto the design level (0208's inverse, after 0282's cash-out)

**The slice:** ONE migration — `supabase/migrations/20260818000285_goods_prices_at_design_level.sql` —
plus the data files its catalogue money lives in (`data/hulls.json`, `data/officers.json`,
`data/npc-houses.json`, `data/ships.generated.json`, `scripts/build-ships.mjs`), the two proof
literals its starting purse moved (`04_first_session.sql`, `10_manifest.sql`), the tests and client
copy that carried the old 8,000 (`rpc.firstSession`, `rpc.surface`, `found.ts`, the Gallery; and
`db.chain`/`db.image`, whose FROZEN-PREFIX boots now read that prefix's own `starting_ducats`
instead of any literal), the two spec fixes PR CI found (the port fee read from the knob, the
align row heuristic's inline chips — §9), the world-image certification (`scripts/db/build-image.mjs`),
and the live design docs
(`DESIGN`, `ECONOMY_LOOP`, `CLOSED_ECONOMY`, `NPC_TRADERS`, `FLEETS_AND_SLOTS`, `PIRATES_AND_HAVENS`,
`SHIPS_AND_SKILLS`, `SHIPS_AND_GEAR`, `CORP_STORAGE_FORGE`).

**State while this is written:** AUTHORED and GATED on the local cached chain (receipts below),
committed and pushed as PR #410 (`price-level`). **NOT deployed** — the main session deploys; the
prod head must read `20260818000284` and 0285 is the next number. **Do NOT merge from this branch.**

## 1. The instruction, and why the whole scale

The owner, 2026-10-30, verbatim:

> "the merchants and players holding the trade goods that are based before, convert them into
> cash first then do the work."

The first half is **LIVE**: 0282
(`20260818000282_the_old_hold_is_cashed_out_before_reprice.sql`) priced every held trade good at
the old `public.goods.base_value`, credited each house once (`LIQUIDATION`, a moved-wealth kind),
and emptied `ships.cargo` / `player_storage`.

The second half is the re-base. 0208 set `goods_price_level = 0.2` and applied it **once** to the
stored column; `public.item_recipe_value` is its only reader and returns
Σ(qty × base_value / wc_num('goods_price_level')) — the DESIGN value. 0285 is 0208's exact inverse
**at the whole scale**: the stored column × 5 and the knob 0.2 → 1.0, AND every absolute ducat
quantity × 5, so every RATIO in the world is kept. The coordinator's correction of 2026-10-31 made
that explicit: goods-only ×5 made PROOF 5's first-voyage return 22.3% (band 14.7–21.7) and PROOF 7's
first-session BUY need 24,371 d. against an 8,000 purse. Prices are real-world; the game is not
harder.

## 2. The measured state (prod, read-only, 2026-10-31, head `20260818000284`)

| fact | value |
|---|---|
| head | `20260818000284` |
| goods / type / min / max | **629** / **numeric(10,2)** / **0.80** / **660.00** |
| `goods_price_level` | **0.2** |
| design sheet `GOODS_SAVED.csv` | 584 goods with a band; live × 5 / midpoint = **1.000000 on 584/584** |
| named goods | black-pepper 30→**150**, cinnamon 120→**600**, saffron 390→**1950** |
| item recipe products | **222**; `item_recipe_value = 5 × Σ(qty × base)` exactly on 222/222 |
| knob readers (prosrc, public/cmd/world/voyage) | **only `public.item_recipe_value`** |
| `port_goods` | **154,734** rows (one per port+good), md5 `f627d4d00cd87f85c45c6df5870c09c3` |
| functions (public/cmd/world/voyage) | **663**, md5 `f19520b6eb631df8369548d33effe258` |
| goods md5 | `3adca72ea3155940baf8df76cafaa494` |
| **players** | **840** (821 merchants); purses **1,704,092,571 d.**, min 0, max 56,898,626 |
| **port_treasury** | 246; rolled **51,625,039 d.**, reserve **2,779,323**, invested **119,659,696** |
| **treasury_flows** | 12,041 rows / **−4,278,714 d.** unrolled; live city money **47,346,325 d.** |
| **city_shares** | 3,630; paid **137,085,286 d.**, accrued **273,323,914 d.** |
| **open contracts** | 260; premium **1,866,702 d.**, escrow **1,819,640 d.** (7 expired stay) |
| **fleet_wages / port_fee_debts** | 838 rows / **65,612.60 d.**; 191 rows / **159,208 d.** |
| **insured_voyages** | 29,755 rows; value **1,427,040,231 d.**, price **952,436 d.** |
| **hull_recipes / ship_classes** | 103 / 103: **2,000 … 839,500** (barca 3,000); **8,000 … 3,358,000** (barca 12,000) |
| **officers / npc_houses** | 105, wages 550 … 1,600; 821, capital 5,000 … 729,000 (sum 26,061,000) |
| **route lines / price_history / cargo basis** | 1,635; 12,870 points (mid 1.0449 … 2,062.9058); 530 ships |
| **switches / stamps** | economy **CLOSED**, city treasury **LIT**, `economy_closed_total` **1,986,693,521** |
| **stats_watch** | under_thin **187**, under_reserve **131**, broke **51** |

The design sheet is at design ÷ 5 today; the whole world is at the same ÷ 5. ×5 on everything
absolute restores it at every ratio.

## 3. The rule

**EVERY ABSOLUTE DUCAT QUANTITY × 5.** A quantity that is money — a purse, a stored price, a wage,
a fee, a premium, a cost basis, a price limit, a policy value, a city book — moves × 5.
**DIMENSIONLESS things DO NOT MOVE:** percentage rates, shares, spreads, multipliers, per-unit
ratios, counts and tonnes. The one knob/column pair from the first version stays exactly as it was:
`goods.base_value × 5` and `goods_price_level 0.2 → 1.0`.

## 4. What moves — table/column, and why

- **`public.players.ducats`** — every house, NPC merchants included (they are players rows). Written
  through `public.credit` (the ONE purse writer) as one `RESCALE` credit of 4 × the old purse per
  house, so each old purse becomes 5 × and the append-only ledger reconciles.
- **`public.port_treasury.ducats` / `reserve` / `invested`** — the city's rolled purse, reserve and
  stake × 5.
- **`public.treasury_daybook.ducats`** — the city's rolled day-book × 5. NECESSARY:
  `public.tick_city` asserts `ducats = Σ daybook`.
- **`public.treasury_flows.ducats`** — the unrolled half × 5; `treasury_balance` = ducats + flows.
- **`public.city_shares.paid` / `accrued`** — the shares' paid and unpaid coupons × 5 (the set-aside
  trigger follows).
- **`public.trade_contracts.mid_at_post` / `premium_per_unit` / `premium_ducats` / `escrow`** —
  open requests only; expired/fulfilled stay at the scale they paid at (the set-aside trigger
  follows the escrow).
- **`public.fleet_wages.owed` / `visit_net` / `visit_paid`**, **`public.port_fee_debts.ducats`** —
  live liabilities × 5.
- **`public.insured_voyages.value` / `price` / `lost_value` / `paid` / `short` / `basis`** — live
  policies × 5 (the per-unit basis included).
- **`public.hull_recipes.ducats` / `public.ship_classes.build_cost`** — set to the **re-derived data
  values**, not a blind old ×5: `build-ships.mjs` re-rounds every archetype's labour to 500 and
  re-fits the shed at the new scale, so 98 of the 103 prices land a few thousand ducats from
  5 × the old column. The 103 values are `data/hulls.json` (3 live) +
  `data/ships.generated.json` (100 generated), and 4 × the labour for each class.
- **`public.officers.wage_ducats`**, **`public.npc_houses.capital`** — every captain's wage and every
  merchant's capital × 5.
- **`public.ships.cargo_basis`**, **`public.player_storage.basis`** — the per-unit cost of cargo and
  goods × 5.
- **`public.standing_route_lines.price_limit`**, **`public.orders.args->'limit'` + `raw_text`** —
  forward price commitments × 5 (open/pending only).
- **`public.price_history.mid` / `ask` / `bid`** — the live chart × 5 (the 0208 precedent).
- **`public.world_config` (21 absolute ducat knobs) × 5** — `starting_ducats`, the two provision
  prices, `wage_per_crew_day`, `repair_rate_per_point`, `hire_crew_rate`, `tow_fee_per_nm`,
  `port_fee_base`, `port_fee_per_ship`, `invest_min_ducats`, `donate_min_ducats`,
  `skill_study_base_cost`, `works_cost_base`, `restock_i_half`, `stats_thin_purse`,
  `city_purse_city`, `city_purse_capital`, `city_seed_min`, `city_earnings_per_dev`,
  `fame_ducats_per_point`, `influence_day_cap`.
- **`world_config.economy_closed_total`** — the closed economy's stamp × 5 when numeric.
- **`public.stats_live` players/merchants/cities/set_aside** — brought to exactly 5 × the actual
  purses/city money/set-aside through `public.stats_live_add`.

## 5. What does not move

- **No persistent function body is re-cut or created.** `new_house` reads `starting_ducats`;
  `founding_credit`/`credit` compose it; `treasury_post`/`tick_city` read the city rows; every fee,
  wage and premium is a knob or a stored row. The self-assert holds the 663-function md5 equal.
- No ACL/volatility/definer/config, no column type, no `port_goods` row (count + md5), no goods or
  item recipe, no cargo/hold/stock/count/tonne, no rate/percentage/share/spread/multiplier.
- **History is not rewritten:** `ledger` (append-only), `events`, `capital_gifts`, `city_month_book`,
  `route_month_laps`, `standing_route_laps`, `stats_*` history, `voyages.wages_paid`, and every
  expired/fulfilled contract stay at the scale their money actually moved at. The player ledger
  reconciles through the RESCALE rows; the city live purse reconciles through its two live halves
  and the day-book. `price_history` IS scaled because it is the live chart (0208 scaled it too).
- The two switches are OWNER-ONLY and untouched: `economy_closed` and `city_treasury_enabled` read
  back exactly as found (true on prod, false in a fresh local chain). The RESCALE kind is `moved`,
  so the closed economy's no-new-gold guard passes it by design.

## 6. The city purse and the live Stats, said once

`treasury_balance(port) = port_treasury.ducats + Σ treasury_flows.ducats` — both halves ×5.
`tick_city`'s ROLL folds the flows into `ducats` and deletes them, and its ASSERT requires
`ducats = Σ treasury_daybook`; the day-book is scaled too, and the next ROLL adds the scaled flows.
The `stats_live` cities counter has no trigger on a bare purse update, so one final
`stats_live_add` brings all four state figures to exactly 5 × the actual before. The credit RESCALE
rows move players/merchants; the `city_shares.accrued` and `trade_contracts.escrow` triggers move
set-aside.

## 7. The data move

The 0285's catalogue updates are the growth of the design files themselves:

- `data/hulls.json` — 3 live `ducats` × 5.
- `scripts/build-ships.mjs` — the 19 archetype `labour` values × 5, then the generator re-run:
  `data/ships.generated.json` — 100 `ducats`/`buildCost` × 5 (the live anchors still hold).
- `data/officers.json` — 105 `wage` × 5.
- `data/npc-houses.json` — the 12 `lesser_officers` wages × 5 (the 821 houses carry no capital).
- The ship tables in `docs/SHIPS_AND_SKILLS.md` (103 rows) and `docs/SHIPS_AND_GEAR.md` (8 rows) × 5.

The world-guard now says the applied world EQUALS `data/*.json` (the 98 ship-class `build_cost`
diffs from a blind ×5 are zero; 103 ship classes + 225 items, 105 captains, 821 merchant companies).

## 8. The self-assert

- **As found:** goods count/md5/knob/extremes; every good; every recipe product's
  `item_recipe_value`; `port_goods` count + md5; 663-function count + md5; every house's purse;
  every city purse/day-book/flow; every share/contract/wage/debt/policy; every hull/class/officer/
  capital; every cost basis/route/order; every price-history row; every knob; the live Stats; the
  watch; the 103 hull/class data values.
- **The guard** refuses a missing table/function, a wrong `goods.base_value` type, a missing/
  double-applied/wrong knob, an existing RESCALE kind, and any non-finite/≤0 good.
- **The probe** (subtransaction, `ZX285`, rolled back): the highest-base harbour good with stock
  ≥100, `world.price`/`world.quote` before/after that one good ×5, mid/ask/bid/avg_price/total each
  between 4.9× and 5.1×, then the rollback restores the base_value.
- The receipt is the chain's own (the 0285 self-assert is green; see §9).

## 9. The gate (local, cached chain — not a from-zero replay)

```
node scripts/db/check-versions.mjs                       # 273 migrations / 273 distinct
BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing
node scripts/db/proof.mjs 05   # PROOF 5 — first-voyage balance
node scripts/db/proof.mjs 07   # PROOF 7 — supplies at sail
node scripts/db/proof.mjs 02   # PROOF 2 — ledger reconciliation
node scripts/db/proof.mjs 12   # PROOF 12 — merchant companies
node scripts/db/proof.mjs 04   # PROOF 4 — first session
node scripts/db/proof.mjs 10   # PROOF 10 — manifest
```

- `standing`: **273/273 chain receipts, world-guard ok, 11_standing 5/5** (the route proof opens
  at 40,000; purse 40,000 → 40,337 over 4 laps).
- **PROOF 5: 5/5** — median first voyage **18.0%** of the stake (band 14.7–21.7), 8 ports / 3
  markets, worst 10.6, best 23.8; every port has a paying first voyage; distance pays.
- **PROOF 7: 4/4** — BUY coriander 310 / SAIL LIS / SELL ALL in one queue; sold 22,838 d.; stores
  bought; the queue clear.
- **PROOF 2: 6/6** — 500 orders; 346 succeeded / 154 refused; 4,350 ledger rows; every purse equals
  Σ ledger (38,092 / 38,388 / 38,460); 853 fleets and 0 SAILING agree; the check bites.
- **PROOF 12: 6/6** — 22 merchant laps; the probe merchant nets 23,620/day; every merchant reconciles;
  the rank/earnings/dark checks pass.
- **PROOF 4: 9/9** — opens at **40,000**; silk-cloth → Funchal → wine; the purse 39,737 → 49,486,
  a **24.53%** return; the oversized order refused E_HOLD_FULL; the queue completes unattended.
- **PROOF 10: 10/10** — the 40,000 refill; the manifest sells-funds-buys, is atomic, the receipt is
  the ledger, XP honest, the client path closed.
- `duplication`: 11/11 (the migration-proves-itself, supersede and every other guard).

**Gate-found defects, fixed:** the first 0285 had unqualified `recipe_0285.v` references
(SQLSTATE 42702); the world-guard then found the 98 hull/class rounding diffs (the data values now
written, not a blind ×5); the world-guard's history tables did not exist as named (the month books,
not the week books); the client build's image certification still expected 8,000 (`build-image.mjs`
now reads `starting_ducats`); the live-world specs (`rpc.firstSession`, `rpc.surface`) and the
client copy carried 8,000 (now 40,000), while the two FROZEN-PREFIX boots (`db.chain`, `db.image`)
read that prefix's own knob. Each was a diagnostic failure, not a re-run.

**PR CI round 1 (run 41092403249, head `635ea87c`) found four spec-side dependencies of the ×5, all
fixed in this branch:** (i) `rpc.portDues` pinned the old fee 100 — it now reads `port_fee_base`
from the knob and the fee the RPC serves (250 × 2 = 500); (ii) `align` read the gallery's seven
side-by-side `Figure`s as a hand-rolled row once the hero "40,000🪙" grew past the spec's 120px chip
floor — MEASURED 139.6px; a flex item blockifies (computed `flex`), so the guard now keys on the
primitive's own `inline-flex` class; (iii) `db.chain`/`db.image` pinned the K.1 purse at 40,000, but
those two boot the FROZEN PREFIX (ends at 000041, before 0285) — they now read that prefix's own
`starting_ducats`; (iv) `db.chain`'s growth test required the live house not to move, and 0282+0285
in the growth half move it by the owner's declared cut-over — the test now asserts exactly
`5 × (old purse + round(Σ qty × old base_value))`, the hold emptied, and every other field equal.
The `disposable-chain` failure was its Docker-network flake (the coordinator's call), not this
branch.

**Local acceptance after the fixes (cached chain, local-mode build):** `npm run build` exit 0 (the
emitted image certified at 40,000); `tsc --noEmit` and `eslint` clean; `align` **2 passed, 0 defects
at 1280 and 0 at 390, 0 skipped** (4.2 min); `db.chain` + `db.image` + `rpc.portDues` +
`rpc.firstSession` + `rpc.surface` **50 passed, 0 failed, 0 skipped** (1.2 h; `db.chain`'s growth
test the long pole). One diagnostic note: the first local `align` run loaded the earlier
computed-display guard and reported the same Gallery defect; the 139.6px measurement showed why
(blockification), the guard was changed to the class, and the 0-defect run is a changed file, not a
re-run of a red. The PR CI re-run is the remaining gate.

## 10. PROD CHECKS for the main session

Run each block as one statement (`npx --yes supabase@2.120.0 db query --linked -f <file>`), read-only;
every function called is stable. Expected as found on 2026-10-31 (head `20260818000284`).

```sql
select
  (select max(version) from supabase_migrations.schema_migrations) as head,          -- 20260818000284
  (select count(*) from public.goods) as goods,                                      -- 629
  (select value from public.world_config where key = 'goods_price_level') as knob,    -- 0.2
  (select count(*) from public.players) as houses,                                   -- 840
  (select sum(ducats) from public.players) as purses,                                -- 1704092571
  (select sum(ducats) from public.port_treasury) as rolled_city,                     -- 51625039
  (select sum(ducats) from public.treasury_flows) as unrolled_flows,                 -- -4278714
  (select sum(paid) from public.city_shares) as shares_paid,                         -- 137085286
  (select sum(accrued) from public.city_shares) as shares_accrued,                   -- 273323914
  (select sum(escrow) from public.trade_contracts where status = 'open') as open_escrow, -- 1819640
  (select sum(value) from public.insured_voyages) as insured_value,                  -- 1427040231
  (select sum(owed) from public.fleet_wages) as wages_owed,                          -- 65612.60
  (select sum(ducats) from public.port_fee_debts) as fee_debts,                      -- 159208
  (select sum(capital) from public.npc_houses) as npc_capital,                       -- 26061000
  (select sum(payed) from (select ducats::numeric as payed from public.hull_recipes) x) as hulls_d, -- 839500 max
  (select jsonb_object_agg(key, value) from public.world_config
    where key in ('starting_ducats', 'wage_per_crew_day', 'economy_closed', 'city_treasury_enabled',
                  'economy_closed_total')) as knobs;                                  -- 8000 / 1 / true / true / 1986693521
```

```sql
with r as (
  select ir.item_code, sum(ir.qty * g.base_value) as sum_base
    from public.item_recipes ir join public.goods g on g.id = ir.good_id group by 1
)
select count(*) as recipe_items,                                                       -- 222
       count(*) filter (where public.item_recipe_value(item_code) = sum_base * 5) as exact_5x, -- 222
       count(*) filter (where public.item_recipe_value(item_code) is distinct from sum_base * 5) as mismatch
  from r;                                                                              -- 0
```

```sql
select world.stats_now() as total,
       (select row_to_json(w) from public.stats_watch(now()) w) as watch;
-- total 2026362402; watch under_thin 187, under_reserve 131, broke 51
```

```sql
with p as (
  select pg.port_id, pg.good_id, p.code as port_code, g.code as good_code, g.base_value, pg.stock
    from public.port_goods pg
    join public.goods g on g.id = pg.good_id
    join public.ports p on p.id = pg.port_id
   where public.port_offers(pg.port_id, pg.good_id) and pg.stock >= 100
   order by g.base_value desc, p.code, g.code limit 1
)
select p.port_code, p.good_code, p.base_value, p.stock,
       (select row_to_json(x) from world.price(p.port_id, p.good_id) x) as price,
       (select row_to_json(q) from world.quote(p.port_id, p.good_id, 10, 'buy', null, null) q) as quote
  from p;
-- 2026-10-31: AGA / gold, base 660.00; price mid 521.1296, ask 529.47, bid 512.79;
--             quote 10 buy avg_price 529.62, total 5297.
```

**After the push** (read-only): every money figure above is × 5 — players 1,704,092,571 →
**8,520,462,855**; city live 47,346,325 → **236,731,625**; set-aside 275,143,554 → **1,375,717,770**;
world total 2,026,582,450 → **10,132,912,250**; economy_closed_total 1,986,693,521 →
**9,933,467,605**; starting_ducats 8,000 → **40,000**; wage_per_crew_day 1 → **5**; barca hull
3,000 → **15,000** and build_cost 12,000 → **60,000**; NPC capital 5,000 … 729,000 → 25,000 …
**3,645,000**; shares paid 137,085,286 → **685,426,430** and accrued → **1,366,619,570**; open
premium 1,866,702 → **9,333,510** and escrow → **9,098,200**; insured value 1,427,040,231 →
**7,135,201,155**; fleet owed 65,612.60 → **328,063.00**; fee debts 159,208 → **796,040**; the 103
hull/class prices are the re-derived data values (98 differ a few thousand from a blind ×5 by the
generator's 500-ducat rounding); route limits 1,635 rows ×5; price_history mid 1.0449 …
2,062.9058 → 5.2245 … 10,314.5290; watch thin 10,000 → 50,000, under_thin 187, under_reserve 131,
broke 51 (ratios kept), swing 0.0641/0.1669 unchanged; goods md5, 222 recipe values, port_goods md5
and the 663-function md5 unchanged. **Do not expect the after-deploy `port_goods` md5 to equal
`f627…`** — the live market keeps moving; the migration's self-assert holds it equal inside its
own transaction.

**After the deploy, report the economy** (never switch anything): `under_thin`, `broke`, `debtors`,
world `total`. Prices are ×5, so these counts are the watch; the economy switch remains owner-only.

## 11. Forward rollback (ready, not applied)

One new migration, the exact inverse (never an edit of this file): goods.base_value / 5 and
`goods_price_level` → 0.2; every table above's money ÷ 5; every knob ÷ 5; the city
purse/day-book/flows ÷ 5; the stats_live counters brought back through `stats_live_add`;
`economy_closed_total` ÷ 5; the RESCALE kind stays and the player purses are taken back with a
RESCALE credit of −4/5 of the current purse per house. The history books stay as recorded; the
103 hull/class prices return to their as-found values from the data. Only the owner may call for it.

## 12. What is unproven

- The prod push itself: the main session runs `~/bin/bv-deploy.sh`; this file has not been applied
  to prod.
- The PR CI re-run after the four spec fixes (the local acceptance is green: build exit 0, align
  2/2 with 0 defects at both widths and 0 skipped, the five node specs 50/50).
- The live market's real prices after the push and the economy counts (`under_thin`, `broke`,
  `debtors`, `total`) — to be reported after the deploy.

## 13. Files

- `supabase/migrations/20260818000285_goods_prices_at_design_level.sql` — the migration.
- `data/hulls.json`, `data/officers.json`, `data/npc-houses.json`, `data/ships.generated.json`,
  `scripts/build-ships.mjs` — the catalogue data move.
- `scripts/db/proofs/04_first_session.sql`, `10_manifest.sql` — the starting-purse literals.
- `tests/rpc.firstSession.spec.ts`, `tests/rpc.surface.spec.ts` — the live world's starting purse,
  40,000.
- `tests/db.chain.spec.ts`, `tests/db.image.spec.ts` — the frozen-prefix boots read the prefix's own
  `starting_ducats` (8,000 there: the prefix ends before 0285); the growth test encodes the declared
  0282 cash-out + 0285 ×5 cut-over.
- `tests/rpc.portDues.spec.ts` — the dock fee read from `port_fee_base` and the served figure.
- `tests/align.spec.ts` — the row heuristic no longer treats an inline-level primitive (the gallery's
  Figures) as a row: the hero "40,000🪙" measured 139.6 px (over the 120 px chip floor) and computes
  `flex` (a flex item blockifies), so the guard reads the primitive's own `inline-flex` class.
- `src/lib/i18n/dict/found.ts`, `src/features/gallery/GalleryScreen.tsx` and the sign-up/RPC/localDb/
  boot comments — 40,000.
- `scripts/db/build-image.mjs` — the image certification reads `starting_ducats`.
- `docs/DESIGN.md`, `docs/ECONOMY_LOOP.md`, `docs/CLOSED_ECONOMY.md`, `docs/NPC_TRADERS.md`,
  `docs/FLEETS_AND_SLOTS.md`, `docs/PIRATES_AND_HAVENS.md`, `docs/SHIPS_AND_SKILLS.md`,
  `docs/SHIPS_AND_GEAR.md`, `docs/CORP_STORAGE_FORGE.md` — the live docs' money.
- `docs/OWNER_REQUESTS.md` row 240, `docs/WORK_QUEUE.md` — the owner's record.
- PR #410 (`price-level`).
