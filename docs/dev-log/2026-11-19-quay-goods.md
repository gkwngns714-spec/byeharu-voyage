# 2026-11-19 · Every raw good has a source (migration 0460, proof 163)

The fault (recorded 2026-11-16 in `docs/WORK_QUEUE.md` and `docs/design/land-2026-11.md` 5.1 / 11): "43 raw goods (Fresh Water
among them) are sold on no quay, so 211 of 287 recipes cannot be made today." 0280 added raw and made goods with market rows but
no roster rows; a quay sells only its roster (`public.port_offered_goods` reads `public.port_specialties`, 0136).

**Narrowed (coordinator, same day, PR #771):** the first cut also re-stocked 0280's 64 goods (x10) and rewrote 17,468 market
rows. That was an economy change nobody asked for, and it would have loosened the land's market guard (0457). This version
places goods on quays and moves no other good's market row.

## Measured first (local chain, PGlite, head 0458, prefix cache)

- **43 raw goods are on no roster.** The note was right. Recipes: **76 of 287 can be made, 211 cannot.**
- **7 of the 43 are Mining goods** (Clay, Feldspar, Gypsum, Lime, Quartz, Sand, Stone). The land is **lit on prod since
  2026-11-19 09:32 UTC** (`land_enabled` true), so they have a source. They are left to the land, off the quays.
- **36 goods had no source at all**, by sea or land.
- **Prod (one read-only statement, `scripts/ops/harness/quay-goods/before-0460.sql` as it stood then):** head 0458; 43 raw goods
  on no roster; 1,412 offers; 159,766 market rows; the five affinity knobs as the chain has them. Found: `depth_by_investment` is
  **true** on prod and every market row has a `base_target` (159,766), so a row's max is base x its harbour's multiple (0252).
  The local chain has it false. (The statement was sent twice: my own `tail` cut the first output. Same read, nothing else.)

## The fix: by data, in the roster's one home

- **Rule:** the roster is `data/ports.json` (each harbour's `goods`), turned into `port_specialties` and the market by
  `scripts/build-world-growth.mjs`, the one generator that stocks every other good. 0062's law (d), which that generator asserts,
  says every good is got at a producer. Each of the 36 is now on the roster of **one harbour of its own origin regions**, inside
  the roster laws (capital 10, middling 4-8, small 4; no good in four cities; every offer native):
  - its producer (`public.city_production`, 0280) when that harbour has room: **9 goods** (Fresh Water at Bilbao, Eggs at Porto,
    Milk at Banda Neira, Coffee Bean at Basra, Honeybush Leaf at Zanzibar, Nipa Palm at Banten, Shea Nut at Cape Town, Sugar Cane
    at Santo Domingo, Witch Hazel Bark at Boston);
  - else the nearest (great circle from the producer) middling harbour of its origin regions with room: **27 goods** (the list:
    `git diff data/ports.json`, or `offers_0460` in the harness files). Small producers (exactly 4) and capitals (exactly 10)
    have no room under the law.
- **Law (d) in the generator now says:** a good has a source if a quay of its regions sells it, or (made goods, tier 1-3) a recipe
  makes it, or (raw goods) the land gathers it (`public.land_actions`). So the 7 minerals and 17 made goods of 0280 (Bread,
  Planks, Leather, Iron Bars, the flours ...) stay on no quay.
- **Recipes after:** **256 of 287 from the quays alone; all 287 with the land** (31 need a Mining good). Before: 76 from the
  quays, 99 with the land.

## The market: only the placed goods' rows move

- **Roster rows added: 36. Market rows added: 0** (every harbour already had a row for every good).
- **Market rows updated: 9,144, all of the 36 placed goods** (no other good's row is written):
  - 9,144 hauls (0173: how far a good is carried from the nearest quay that sells it; a new quay moves it everywhere);
  - 6,574 of them also an affinity (the new quay is nearer than 0280's producer was). Their max and production follow the
    new affinity **on the row's own footing**: the row keeps its ratio to the rule. 0280's goods sit at a tenth of the depth rule
    (0005's arithmetic without `market_depth`); they stay at a tenth (every row of the 36: ratio 0.1000 before and after). Stock
    := the new max on those rows (nobody could buy these goods anywhere, so no trade is undone). 4,802 base maxes move.
  - Rows whose affinity did not move keep everything but the haul (Fresh Water at Bilbao: base 402, unmoved).
- **Every other row:** the file pins, before writing, a digest of every row outside the 36 goods (affinity, base max, production,
  haul, demand) and asserts it unmoved after; and asserts by `xmin` that this transaction wrote no such row at all (stock and the
  day's max move under a live migration, so they are held by xmin, not by value).
- **Harbours:** 33 harbours' `dev_commerce` move, +1 an offer, by the existing rule (`dev_*` restate the roster; world-guard
  requires it): ALG, ARI (+2), ARK, BAN, BEI, BIL, BND, BNT, BOS, BSR, CHE, COL, CPT (+2), DUB, ISL, LAR, LPA, LUA, MLG, MOM, OPO,
  PAN, PRT, PTH, QUA, RIO, ROT, SAK, SGO, TAI, XIA, YEO (+2), ZAN. `dev_industry` unmoved everywhere.
- No knob moves, no coin minted.

## The generator, repaired in its one home (`scripts/build-world-growth.mjs`)

It had not been run since 0280. Repairs kept, each needed for this output:
1. Baseline from the prefix cache (was a from-zero replay of 418 files; output unchanged).
2. Reads `goods.tier` (it rewrote all 629 goods every run).
3. **Scoped re-derivation:** a growth re-derives only the market rows of the goods whose offers moved (and a new harbour's
   pairs), keeping each row's footing; every other row is pinned and asserted unmoved (digest + xmin). It used to re-derive and
   assert every row of the world against today's rule, which no growth after 0280 could pass without re-stocking.
4. 0252's base max: the footing is read on `coalesce(base_target, stock_target)`; a moved row with a base gets base := new base,
   max := base x the harbour's multiple (`public.depth_target`, `public.depth_mult`), as the daily regen keeps it.
5. 0173's hauls, for the scoped rows, from `world.haul_rows()` (read once); world-guard caught their absence.
6. Law (d) as above (recipes, land).
7. The market digest guard (5b): the file refuses unless the market's static columns are the baseline's
   (`0c17a5f4f96b6f1c3f9c22428291a3ef`). `statement_timeout` 15 min in the file.
8. 0303's stock scale is composed in the rule (used for a new pair and for a row's footing; scale 1 for the 36 tier-0 goods).

## Proof (local, PGlite)

- 0460 on the head chain: self-asserts PASS. **Applied in 24 s.** `after-0460.sql` on it: offers 1,448, offers_0460 36, raw on no
  quay 7 (the land's), market rows 159,766, knobs unchanged, Fresh Water base 402 at Bilbao, 554 at Lisbon (unmoved).
- **Prod-shaped apply** (every row given a base = its max, a multiple on every harbour, Bilbao x1.3144, Lisbon x0.9837): self-asserts
  PASS (digest refusal held, scoped rows the derivation, rows outside unmoved by digest and xmin), 22 s; 6,574 rows' affinity and
  footing moved, 4,802 bases moved, **every max = base x its harbour's multiple** (0 not).
- **Proof 163** (`scripts/db/proofs/163_every_raw_good_has_a_quay.sql`): red on the head chain (36 raw goods with no source);
  green on head + 0460. `node scripts/db/proof.mjs` with 158, 160, 161, 163 only: **26 of 26 markers PASS**, world-guard ok
  (the applied world equals data/*.json). 163: 342 raw goods with a source (7 by the land alone); 287 of 287 recipes with the
  land, 256 from the quays alone; all 9,144 rows of the 36 goods on 0280's footing; Fresh Water bought at Bilbao through
  `cmd.do_buy`, refused at Lisbon (`E_UNAVAILABLE`). Proof 160's GUARD_BITES reads 425.8x against a target of 30, as on 0457:
  the land's targets did not move.

## OWNER'S (decided by default; the owner may reverse)

1. **One quay per good.** The roster law allows up to 3; the smallest choice was one. Fresh Water, used in 107 recipes, is sold at
   Bilbao only. More quays per good = more rows in `data/ports.json` and a new growth file.
2. **The seven Mining goods are the land's only** (no quay), as the brief said; the land is lit.
3. **PROPOSAL, NOT DONE: 0280's 64 goods hold a tenth of the stock the depth rule gives every other good** (0280 seeded them
   with 0005's arithmetic and left out 0207's `market_depth` 10: Fresh Water at Lisbon 554 where the rule says 5,540; Iron Bars 36
   where it says 360). Bringing them to the rule is x10 stock for 64 goods (about 16,000 rows) and would let the land guard (0457,
   which timed Clay, Sand, Stone ... against the tenth) allow those jobs ten times faster. An economy decision; not in this file.
4. **A made good needs no quay** when a recipe makes it: 17 of 0280's made goods stay on no quay.

## Not verified

- Not deployed, not merged. Prod's `market_digest` must still read `0c17a5f4f96b6f1c3f9c22428291a3ef` (before-0460.sql) or the
  file refuses; prod's `untouched_digest` was not read (the column was added after the one prod read).
- Apply time on prod not measured.
- The browser was not run (this clone's local build is the live game). Full proof suite and the growth-house spec: CI.
