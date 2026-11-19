# 2026-11-19 · Every raw good has a quay (migration 0460, proof 163)

The fault (recorded 2026-11-16 in `docs/WORK_QUEUE.md` and `docs/design/land-2026-11.md` 5.1 / 11): "43 raw goods (Fresh Water
among them) are sold on no quay, so 211 of 287 recipes cannot be made today." 0280 added 45 raw goods and 19 made goods and gave
them market rows but no roster rows; a quay sells only its roster (`public.port_offered_goods` reads `public.port_specialties`, 0136).

## Measured first (local chain, PGlite, head 0458, prefix cache)

- **43 raw goods are on no roster.** The note was right. Agave, Apple, Bamboo, Bark, Betel Leaf, Cabbage, Cacao Bean, Cassava Root,
  Cattle, Clay, Coffee Bean, Eel, Eggs, Feldspar, Fresh Water, Goose Feathers, Grapes, Gypsum, Honeybush Leaf, Lime, Lychee, Milk,
  Mint, Nipa Palm, Palm Fruit, Palm Leaf, Palm Sap, Pandanus, Pear, Plum, Quartz, Raffia, Ramie, Rose, Sand, Sesame, Shea Nut, Shrimp,
  Soybean, Stone, Sugar Cane, Tea Leaf, Witch Hazel Bark.
- **Recipes:** 73 of 287 have every ingredient on a quay; with what those make, **76 can be made, 211 cannot.**
- **The land:** 7 of the 43 have a Mining job (Clay, Feldspar, Gypsum, Lime, Quartz, Sand, Stone). The land is DARK
  (`land_enabled` false), so today they have no source either. With the land lit, 99 of 287 could be made (188 still blocked).
  The other 36 have no source at all, by sea or land.
- **Prod (one read-only statement, `scripts/ops/harness/quay-goods/before-0460.sql`):** head 0458; 43 raw goods on no roster;
  1,412 offers; 159,766 market rows; the five affinity knobs as the chain has them. Found: `depth_by_investment` is **true** on
  prod and every market row has a `base_target` (159,766), so prod's max stock is base x the harbour's multiple (0252). The local
  chain has it false. (The statement was sent twice: the first output was cut by my own `tail`. Same read, nothing else.)

## The fix: by data, in the roster's one home

- **Rule (no new list, no special case):** the roster is `data/ports.json` (each harbour's `goods`), turned into `port_specialties`
  and the market by `scripts/build-world-growth.mjs`, the generator that stocks every other good. 0062's law (d), which that
  generator already asserts, says every good is buyable at a producer (a harbour of its own `origin_regions`). 0280 broke it.
  Each of the 43 is now on the roster of **one harbour of its own origin regions**, inside the roster laws (capital 10, middling 4-8,
  small 4; no good in four cities; every offer native):
  - its producer (`public.city_production`, 0280) when that harbour has room: 12 goods (Fresh Water and Lime at Bilbao; Clay and
    Eggs at Porto; Milk and Sand at Banda Neira; Coffee Bean at Basra; Honeybush Leaf at Zanzibar; Nipa Palm at Banten; Shea Nut
    at Cape Town; Sugar Cane at Santo Domingo; Witch Hazel Bark at Boston);
  - else the nearest (great circle from the producer) middling harbour of its origin regions with room: 31 goods (the list: `git diff data/ports.json` or `offers_0460` in the harness files). Producers that
    are small harbours (exactly 4) or capitals (exactly 10) have no room under the law.
- **Made goods:** 17 of 0280's made goods (Bread, Planks, Leather, Iron Bars, the flours, Glass, Yarn ...) are also on no roster.
  The generator's law (d) now says a made good (tier 1-3) that a recipe makes is produced by its recipe and needs no quay; a raw
  good (tier 0) has no recipe, so it must have one. They can all be made now.
- **Rows:** +43 roster rows. **0 market rows added** (every harbour already had a row for every good). 36 harbours' `dev_commerce`
  (and some `dev_industry`) move with their roster, by the existing rule (`dev_*` restate the roster).

## The generator was stale; fixed in its one home

`scripts/build-world-growth.mjs` had not been run since 0280. Five faults, each found by running it:

1. Its baseline replayed 418 files from zero; it now restores the prefix cache (seconds).
2. It never read `goods.tier`, so it re-wrote all 629 goods every run. Fixed (an unchanged world now emits nothing).
3. Its market rule and assert were 0207's depth without 0303's stock scale, so no growth after 0303 could pass. It now composes
   `public.good_stock_scale` (tier / rare scale, floor), read once per good.
4. It knew nothing of 0252's base max. It now reads the rule on `coalesce(base_target, stock_target)`; a re-derived row with a base
   gets base := rule and max := base x the harbour's multiple (`public.depth_target`, `public.depth_mult`), as the regen keeps it.

5. It did not know 0173's haul (how far a good is carried from the nearest quay that sells it, `world.haul_rows()`). A new
   offer moves its good's haul at every harbour; world-guard caught it on the first proof run (10,922 rows = 43 goods x 254
   harbours). The file now re-derives `haul_nm` / `haul` from `world.haul_rows()` (read once) and asserts every row equals it.

Plus a guard (section 5b): the file refuses unless every market row's affinity, base max and production are the baseline's, by
one md5 (`0c17a5f4...`). On prod the update would otherwise touch rows nobody measured. `statement_timeout` 15 min in the file.

## What the market re-derivation does (the existing rule, applied)

17,468 of 159,766 rows are re-derived (local chain; stock := the new max on each, as the generator always does):

- **0280's 64 goods were seeded at a tenth of the rule** (0005's arithmetic without 0207's `market_depth` 10): e.g. Fresh Water at
  Lisbon max 554 where the rule says 5,540; Iron Bars 36 where it says 360. All their rows now take the rule (x10).
- The 43 goods' affinity moves where the new quay is nearer than 0280's producer.
- About 15 older goods had rows whose stored affinity was not the formula's (rows of the harbours 0338 / 0414 added by hand).
- Prices: a re-derived row's stock equals its max, so it prices at the normal price. No coin is minted; no knob moves (the five
  affinity knobs equal the file's values on prod: read).

## Proof

- 0460 applied to the head chain (PGlite): self-asserts PASS. After: 0 raw goods on no roster; **287 of 287 recipes can be made**;
  roster laws hold; every market row holds the rule's max and production; `after-0460.sql` run on it: offers 1,455, offers_0460
  43, market rows 159,766 (none added), knobs unchanged, Fresh Water base at Bilbao 402 -> 4,020, Lisbon 554 -> 5,540. Applied in
  150 s in PGlite on a quiet machine, 700 s with two other builders running; native Postgres is faster (time not measured).
- A prod-shaped run (every row given a base, Bilbao x1.3144 and Lisbon x0.9837 multiples): self-asserts PASS, the 5b digest held (`coalesce(base, max)`
  is the same figure), 17,468 rows re-derived, 16,969 bases moved, **every re-derived max = base x its harbour's multiple** (0 not).
  Fresh Water at Bilbao: base 402 -> 4,020, max 528.39 -> 5,283.89 (x1.3144), stock := max; Lisbon 544.97 -> 5,449.70 (x0.9837).
- Proof 163 (`scripts/db/proofs/163_every_raw_good_has_a_quay.sql`): red on the head chain (43 raw goods on no quay), green
  on it + 0460: `node scripts/db/proof.mjs` with 158, 160, 161, 163 only: **all 26 markers PASS**, world-guard ok (the applied world
  equals data/*.json: 1,455 offers, 159,766 market rows). Fresh Water bought at Bilbao through `cmd.do_buy`; at Lisbon refused
  `E_UNAVAILABLE`. The two applies above (plain and prod-shaped) ran on the file before its haul step was added; the proof run
  is on the final file.

## OWNER'S (decided by default; the owner may reverse)

1. **One quay per good.** The roster law allows up to 3; the smallest choice was one. Fresh Water, used in 107 recipes, is sold at
   Bilbao only. More quays per good = more rows in `data/ports.json` and a new growth file.
2. **The seven minerals are on a quay too.** No document says they are the land's only. With the land lit they have two sources.
3. **The depth of 0280's 64 goods goes up x10** (to the rule). L1b's land guard (0457) timed Clay, Sand, Stone etc. against the
   tenth; with the true depth the guard would allow those jobs ten times faster. The land rows are not touched (they stay slow).
4. **A made good needs no quay** when a recipe makes it (the 17 above stay on no quay; the Forge makes them).

## Not done / not verified

- Not deployed, not merged. Prod's `market_digest` must equal `0c17a5f4f96b6f1c3f9c22428291a3ef` (before-0460.sql) or the file
  refuses (nothing written). Not read: it was written after the one prod read.
- The browser was not run (this clone's local build is the live game).
- Full proof suite and the growth-house spec: CI.
