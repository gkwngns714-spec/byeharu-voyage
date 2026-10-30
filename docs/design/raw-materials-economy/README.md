# Raw-Material Trade Economy — Design Document

This document re-casts the trade economy of **byeharu-voyage** (Age of Sail, c. 1500–1650) as a **multi-tier production chain**:

- **Tier 0 — raw materials:** individual real-world commodities produced by cities and sold directly (wheat, grapes, olives, milk, eggs, iron ore, timber, clay, sand, …).
- **Tier 1+ — production:** every crafted good is built on the Forge in successive tiers from 1–6 inputs. A product's tier is **1 + the highest tier among its ingredients**, so every ingredient is strictly lower tier than its product.
- **Recipe rule:** a recipe uses raw materials, or an intermediate the Forge itself produced (flour, oil, sugar, molasses).

**Nothing in the current catalogue is deleted.** All 565 goods in `data/goods.json` appear in `GOODS_SAVED`, classified as raw material or crafted. **19 NEW goods** are added on top and marked NEW; they were not in `goods.json`. Total `GOODS_SAVED` rows: 584 (565 original + 19 NEW).

Current build: **305 raw materials (tier 0)**, **180 tier-1 recipes**, **96 tier-2 recipes**, **11 tier-3+ recipes**, **287 recipes** in all.

## How to read each sheet

### 1. RAW_MATERIALS (305 rows)
The granular raw-material set. Columns: `code`, `name`, `category`, `tier` (all 0), `real_region`, `providing_cities`, `notes`.
- `code` — stable slug; uses the `goods.json` id wherever the commodity already exists there.
- `real_region` — real-world producing regions, taken from the good's `origin` field.
- `providing_cities` — every port id whose region historically supplied this material; regional availability, not a per-port offer list (see `CITY_RAW`).

### 2. CITY_RAW (246 rows)
Every one of the 246 ports and the raw materials it provides. Columns: `port_id`, `port_name`, `region`, `region_name`, `raw_materials` (comma-separated `RAW_MATERIALS.code`).
The set is drawn from the port's real region production, with the port's own catalogue goods prioritised. Major hubs (tier 1) list up to 30, middling ports (tier 2) up to 12, small ports/outposts (tier 3) up to 4. Fresh water is available at every port.

### 3. RECIPES (287 rows)
One recipe for every crafted good. Columns: `good_id`, `good_name`, `name_ko`, `good_category`, `tier`, `recipe` (human-readable), `ingredient_1..6` (codes), `qty_1..6`, `notes` (historical grounding). Ingredients follow the recipe rule above; every recipe uses 2–6 distinct inputs. Tiers run 1–3 in this build. Where the original sheet had a single-input process (the six flours, cream, planks, malt, yarn), one `fresh-water` process input was added so the build's 2–6 rule holds — the same convention 97 other recipes already use.

### 4. GOODS_SAVED (584 rows)
The complete catalogue, preserved plus the 19 NEW goods. Columns: `id`, `name`, `name_ko`, `category`, `tier`, `valueBand`, `baseValue`, `origin`, `entrepots`, `new_role`, `raw_material_code`, `recipe`, `source`. `source` is `goods.json` for the original 565; `NEW — milling/baking gap, owner 2026-10-30` for the milling/baking goods; and `NEW — multi-tier chain gap, owner 2026-10-30` for the dairy/intermediate goods.

### 5. CHAINS (76 rows)
For each deepest (tier-3) final good, the full dependency map, one row per step: `chain_id`, `step`, `product_id`, `product`, `tier`, `ingredients`. Raw materials appear as tier-0 steps; the final good is the last step.

### 6. README
This page.

## Classification and tier rule

A good is a **raw material** (tier 0) when it is a natural, unprocessed commodity that a region produces and that can enter a recipe unchanged:
- agricultural produce (individual grains, fruits, nuts, spices, fibres, tobacco leaf, sugar cane, tea/coffee/cacao);
- marine catch and shells (individual fish, shellfish, whale products, seaweed);
- minerals and ores (individual iron/copper/tin/lead ores, silver, gold, coal, saltpetre, sulphur, clay, sand, stone, individual gems);
- individual timbers and resins;
- animal products (hides, furs, ivory, feathers, tallow, wax, honey, milk, eggs).

A good is **crafted** (tier 1+) when it is a manufactured or processed article: cloth and clothing, leather, metalware, weapons, armour, firearms, gunpowder, glass, porcelain, beer/wine/spirits, preserved foods, dyes and pigments, medicines, books, art, ships' gear. Its tier is 1 + the highest tier among its ingredients; every ingredient is strictly lower tier.

**Regional variants of the same commodity share one code** (Swedish iron / bar iron → `iron`; Potosí / Zacatecas silver → `silver`; Ceylon sapphires → `sapphires`; Virginia / Maryland / Cuban leaf → `tobacco`). **Different commodities never share a code** (millet and sorghum are separate; cod and herring are separate; madder and indigo are separate).

## Chains and NEW goods (owner 2026-10-30)

- **Canonical chain:** wheat (0) → wheat-flour (1) → bread (2, flour + milk + water) → cake (3, bread + figs + cream).
- **New raw inputs (2):** `milk` (tier 0), `eggs` (tier 0).
- **New tier-1 intermediates (7):** `cream` (milk), `iron-bars` (iron + coal), `leather` (hides + tannin), `planks` (timber), `malt` (barley), `yarn` (wool), `glass` (sand + potash + lime).
- **Milling/baking (9 NEW):** `wheat-flour`, `rye-flour`, `barley-flour`, `oat-flour`, `maize-flour`, `rice-flour`, `bread`, `ships-biscuit`, `rye-bread`.
- **New tier-3 good (1):** `cake` (bread + fruit + cream).
- **Existing goods, not duplicated:** `butter` and `cheese` were already in the catalogue and are now re-recipe to milk; `wool-cloth` and `linen` already were woollen/linen cloth and are re-tiered as tier-1 intermediates. Total NEW goods: 19.
- **Existing recipes split into real chains:** iron ore → iron bars → weapons/armour; hides → leather → leather goods; fibre → cloth/yarn → garments; barley → malt → beer; wheat → flour → bread; grapes → wine → brandy → port; sugar cane → molasses → rum; sand → glass → glassware; timber → planks → wood/art goods; flax/hemp → paper → books.
- **Deepest chains are tier 3** (cake, port-wine, milanese-armour, steel blades, kvass). The same rule supports tier 4+ when deeper goods are added.
- Each NEW good carries the NEW marker in `GOODS_SAVED.source`; they are design additions, not recovered catalogue rows.

## Files

- Excel: `C:\Users\디폴리스\Desktop\raw-materials-economy.xlsx`
- CSV mirror: `docs/design/raw-materials-economy/` (`RAW_MATERIALS.csv`, `CITY_RAW.csv`, `RECIPES.csv`, `GOODS_SAVED.csv`, `CHAINS.csv`, `README.md`)
