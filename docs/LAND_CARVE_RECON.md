# RECON — the canal that was never dug

**Measured 2026-09-06 against `main` at `728da87` (chain head 0076).** Every number here was
produced by running the repo's own `scripts/sea-grid.mjs` — the same module that builds the raster
the game sails on — not read out of a previous document. The throwaway harnesses are not committed;
the method is written out below so any number can be reproduced.

---

## 0. The finding, in one line

> **309 real port pairs are sold a sea route across the Malay peninsula.** The worst is
> **Thanlyin → Ayutthaya at 323 nm, against 1,977 nm of actual sea — 84% short.**

This is a live breach of the owner's absolute law, `OWNER_REQUESTS.md` row 41:
*"i don't want the fleet to ever touch land."*

---

## 1. The cause is one malformed record, not the model

`scripts/sea-grid.mjs` carries `CHANNELS` — named narrow waters forced open because the 0.25° raster
is too coarse to see them. The carve is at `sea-grid.mjs:222-234`, and the load-bearing line is:

```js
// The channels: force their cells — and the cells between consecutive points — open.
```

**Cells between CONSECUTIVE points.** So a channel's points must all lie along ONE water, in order.
Six entries name **two** waters in a single record, and the jump from the last point of the first
water to the first point of the second is carved as open sea.

The worst is:

```js
{ id: 'irrawaddy-sittaung', name: 'the Yangon and Chao Phraya rivers',
  points: [[16.3, 96.3], [16.6, 96.2], [16.8, 96.2],   // the Yangon river
           [13.3, 100.6], [13.6, 100.6], [14.4, 100.6]] } // the Chao Phraya, 330 nm away
```

The third point is Yangon. The fourth is the mouth of the Chao Phraya. Between them lie the
Tenasserim mountains, and the carve opens **29 cells that were land**, the deepest **89.3 nm from
any real water, at 14.34°N 99.29°E** — inland Thailand.

**The model is fine. One record breaks its rule.** Every other entry — Malacca, Hormuz, the
Bab-el-Mandeb, the Severn, the St Lawrence — is a single real water, and the header beside several
of them argues the case with a measurement. Those are not this.

---

## 2. Who buys it — 309 pairs, measured

Every port west of the isthmus (Bay of Bengal / Andaman, 11 ports) crossed with every port east of
it (Gulf of Thailand / South China Sea, 40 ports), routed on the current raster and again with the
one entry split in two. **309 pairs get a shorter answer than the sea allows. Mean cheat: 415 nm.**

| from | to | served today | real sea | short by |
|---|---|---|---|---|
| thanlyin | ayutthaya | **323 nm** | 1,977 nm | **1,654 nm (84%)** |
| chittagong | ayutthaya | 841 nm | 2,378 nm | 1,536 nm (65%) |
| hooghly | ayutthaya | 987 nm | 2,513 nm | 1,527 nm (61%) |
| machilipatnam | ayutthaya | 1,174 nm | 2,503 nm | 1,329 nm (53%) |
| myeik | ayutthaya | 431 nm | 1,712 nm | 1,281 nm (75%) |
| chennai | ayutthaya | 1,242 nm | 2,464 nm | 1,223 nm (50%) |
| colombo | ayutthaya | 1,465 nm | 2,459 nm | 994 nm (40%) |
| thanlyin | guangzhou | 1,791 nm | 2,562 nm | 771 nm (30%) |
| thanlyin | hong-kong | 1,740 nm | 2,512 nm | 771 nm (31%) |
| thanlyin | nampo | 2,956 nm | 3,723 nm | 767 nm (21%) |

It is not a curiosity at one port. **Every Bay-of-Bengal harbour reaches the whole of East Asia
through the mountains** — Guangzhou, Macau, Hong Kong, Fuzhou, Xiamen, Ningbo, Hanoi, Hoi An, and
every Korean port in the catalogue.

**Control:** Thanlyin → Singapore is **1,092.8 nm on both rasters**, unchanged to the digit. The
split closes the canal and touches nothing else.

---

## 3. The other five are NOT the same size, and that matters

`docs/RESUME.md` recorded "six `CHANNELS` entries draw a canal through land" and left them as one
lump. Measured separately, between the real ports each one joins, they are not one problem:

| entry | pair measured | served | real sea | verdict |
|---|---|---|---|---|
| **irrawaddy-sittaung** | thanlyin → ayutthaya | 323 nm | 1,977 nm | **1,654 nm — the defect** |
| **baltic-gulfs** | tallinn → riga | 160 nm | 201 nm | 41 nm (20%) — real but small |
| **gironde** | bordeaux → nantes | 170 nm | 180 nm | 11 nm (6%) — marginal |
| thames-scheldt | london → antwerp | 172 nm | 172 nm | **no effect** — the carve is not what connects them |
| elbe-weser | hamburg → lubeck | 31 nm | 31 nm | **no effect** |
| gambia-senegal | goree → saint-louis | 103 nm | 103 nm | **no effect** |

Three of the six shorten no route between the ports they join: the open sea already connects those
pairs, so the carved land is inert — still wrong in principle, still worth splitting, but **not
something a player has ever been sold.**

**So the repair is one entry, not six**, and the repricing that follows is confined to routes that
crossed a mountain range. That is a much smaller and much easier decision than the one
`RESUME.md` was carrying.

---

## 4. What the repair costs

Splitting `irrawaddy-sittaung` into `yangon` and `chao-phraya` closes **29 land cells** and makes
309 pairs longer — mostly *much* longer. That is a **world repricing**, and it is the owner's call,
not an agent's:

* Distances feed `sea_reaches`, and `0048` tuned the affinity knobs against honest distances. A
  Bay-of-Bengal to Gulf-of-Thailand run becomes 2–6× longer, so its stores, its risk and its margin
  all move together.
* `0076` derives every roadstead from the same raster and declares `roadstead_lat/lon` **NOT NULL**,
  so the migration that carries this must **regenerate** those columns rather than assume them —
  which is exactly why `docs/WORK_PLAN.md` says draft migration 0060 must be regenerated and never
  merged as drafted.
* Nothing should be hand-edited: `scripts/build-sea-migration.mjs` is the generator, and a
  regenerated migration is the only honest way to carry a raster change.

**No port is orphaned by this split** — every affected pair still has a route, just a real one. (The
separate "sound repair" that `RESUME.md` describes, which moves 50,868 of 56,406 readings and
disconnects 10 ports, is a **different** change and is not proposed here.)

---

## 5. The guard did not catch this, and that is the second finding

`scripts/db/proofs/09_the_fleet_never_touches_land.sql` is **green**, and its non-vacuity control
genuinely bites — a planted straight-across-Iberia course is refused as `E_LAND` on every run. It is
not a vacuous guard. It is an **under-scoped** one:

* it walks the courses **it sails itself** — a coastal hop and Lisbon → Nagasaki;
* it plants **one** course it knows should fail;
* it never asks about the courses **the game actually serves**.

A course over the carved canal is water *by the raster's own account*, so `assert_paths_water`
passes it and always would. **The raster is the thing that is wrong, and the guard only ever asks
the raster.** Any check that closes this class has to compare the raster against the land data it
was built from, on the generator side — not on the SQL side.

That is a separate slice from the repair, and it is the one that stops the class coming back.

---

## 6. How to reproduce any number here

1. `import { CHANNELS, buildSeaGrid, findSeaRoute } from './scripts/sea-grid.mjs'`.
2. `buildSeaGrid()` is the carved raster the game uses.
3. Rebuild the pre-channel truth by recomputing the cells the channel pass opens (same loop as
   `sea-grid.mjs:222-234`) and clearing them — that is the land the carve overwrote.
4. To measure one entry, close only the cells its **inter-water jump** opens, then route the same
   pair on both rasters with `findSeaRoute(grid, {lat, lon}, {lat, lon})` and compare `.nm`.
5. Ports come from `data/ports.json` (`raw.ports`), 224 records with `id`, `lat`, `lon`.

**One trap, since it cost a wrong answer here first:** `findSeaRoute` takes `{lat, lon}` objects and
does its **own** snapping, and it answers `{ nm, path }`. Passing it the output of `snapToWater`
returns `NO ROUTE` for every pair — including the controls, which is what gave it away. If a
measurement says a well-known sea lane does not exist, suspect the harness before the world.
