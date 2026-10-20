# 2026-10-20 — the seas have conditions, slice S1 (migration 0215 at writing, `osn-sea-s1`)

**The design:** docs/SEA_CONDITIONS_AND_REGIONS.md (PR #271, merged). The owner, 2026-10-20: *"lets start by applying the
design you've created first, then consider adding more."* Every default of its §7 is accepted (title = the lower of
Trading and Exploration capped at 11; the region gate retired with S2; merchants on wave only; 24 far traders later;
capital 20,000 d. weekly with the docked-fleet rule; six starting powers; the numbers as written). Ice-breaking,
breakthrough and rowing are NOT built (the stat seam is one base row in `world.ship_stats` and one column).

**Version.** 0215 at writing (0212 insurance and 0213 haul cap are open ahead; 0214 is the stats tab). Prod head
**0211** when the pre-images were read (every hunk occurs exactly once on the live bodies, LF-normalised). Renumber to the
prod head + 1 at push. Not deployed: this PR does not push, merge or flip anything. **Dark:** `sea_conditions_bite`
is false; `public.sea_gate` answers null; no gate is re-cut here (S2).

## 1. What landed (one authority per concept — the design's §1 table)

| Concept | Home | Note |
|---|---|---|
| Zone requirements | `public.sea_zones` (64) + `public.sea_zone_boxes` (67) + `public.title_names` (11) | data, `data/sea-zones.json`, held by the world guard both directions. The doc's prose says 61 zones; its table has 64 rows and the table is what is built. Boxes are a child table (NOR-MAC has three boxes, STH-OPEN spans two seas), half-open `[min, max)`, one REST box per raster sea (asserted). |
| Which zone is this water | `public.sea_zone_at(lat, lon)` reading `public.sea_zone_cells` | the 0040 raster answered as zones, one byte a cell, DERIVED from `sea_cells` + the boxes at apply (1,036,800 cells). Decided by default over "sea_at then the boxes per call": the leg-asks derivation samples ~4 million points and the merchant planner (S3) will sample ~100 a leg; a byte read is the only shape that keeps both cheap. `public.sea_cell_row/col` is the one cell address for the zone readers; the self-assert holds the two rasters to the same sea at every roadstead and on 2,000 sampled cells. |
| A harbour's zone | `public.harbour_zone(port)` at its roadstead | not `ports.sea_id` |
| A course's zones | `public.course_zones(course)` | every vertex + a sample every `sea_sample_nm` (30) per straight segment, lon the short way (`voyage.lon_lerp`). Positive control: a two-vertex Lisbon → Havana line — vertices name NOR-EU and GCO only, sampled it crosses NOR-MAC, NOR-MID, NOR-AM. **The design's Bristol → Cape Coast claim was wrong:** read on prod, that course hugs the coast (never west of 17.6° W) and its vertices already name every zone it crosses (NOR-EU, NOR-MAC, NOR-DOL, GUL); it is asserted for what it is. |
| A leg's ask without a course | `public.sea_leg_asks` (238² rows) by `public.sea_leg_asks_derive()` | straight line between roadsteads + the destination's zone; a 300-row re-derivation is asserted equal |
| The hull's stat | `ship_classes.wave`, derived `12 × size + rig + role` | asserted for all 103 classes (prod has 103, not the doc's 101); `scripts/lib/world-derive.mjs waveResistance` is the same rule for the data file and the guard; one base row in each branch of `world.ship_stats` |
| What gear adds | `item_effects` 'wave' rows (65) | `scripts/build-gear.mjs WAVE_BY_BASE` by (base type, grade), applied last so no ladder multiplies it; the three live G1s carry theirs in `data/fittings.json`, asserted against the table; `--sql-0215` pasted |
| The fleet's figure | `public.fleet_wave(fleet)` | floor(avg); nau + 2 barcas = 21 (probe) |
| The title | `public.title_level(player)`, `public.title_names` | derived; `players.title_level` DROPPED (stored 1 for every house; read only by `world.player()`, re-cut) |
| The rule | `public.sea_refusal(title, wave, zones[])` | the only comparison; `E_SEA_CLOSED` with figures `{zone, zone_name, needs_title, title, needs_wave, wave}` |
| The gatherer | `public.sea_gate(player, fleet, dest, course)` | null while dark, null for nobody; a merchant's title is null (wave only) |
| Served | `world.sea_conditions()` (registered + granted), `world.fleets().wave`, `world.ship_view().wave`, `world.player().title_level/title_name` | client: `worldSeaConditions` in the catalogue, types `SeaConditions`, `FleetShip.wave?`, `FleetView.wave?`, `PlayerHouse.title_name?` |
| Knobs | `sea_conditions_bite` false, `sea_sample_nm` 30, `title_max` 11 | `sea_conditions_bite_npc` comes with S3, the capital knobs with S6 |

**Re-cut by hunks** (each asserted to occur once and to reverse, ACL/volatility/definer/config unmoved):
`world.ship_stats` (2), `world.ship_view` (1), `world.fleets` (1), `world.player` (1), `public.client_rpc_entry_points` (1).

## 2. What changes while dark (honest list)

- `world.player().title_level` now serves the DERIVED title: on prod every house read 1; JOOHOON HA (trading 3,
  exploration 4) will read **3**; the other 16 stay 1. No screen reads it (only `src/lib/rpc/types.ts` names it).
  `title_name` is new.
- `world.fleets()` / `world.ship_view()` gain the additive key `wave`; `world.ship_stats()` gains `wave`. The ten old
  stats are asserted unchanged to the digit on every hull of the world.
- No SAIL, plan, route-save or desk answer changes: no gate is touched in S1.

## 3. Read-only on prod before the PR (2026-10-20, head 0211)

- 103 classes, every one with a profile; the derivation gives 6 8 12 13 14 15 18 24 25 26 27 30 36 39 42 48 49 51 53 54
  60 61 63 66 72 73 75 (barca 12, carlat 26, nau 39, galeao 51, indiaman 63, carraca 75, sjb 53, goldenhind 27).
- The nine families hold 65 items (Anchor 8, Sheet Anchor 7, Storm Canvas 7, Planking 12, Sheathing 9, Bilge Pumps 8,
  Ballast 10, Doubled Frames 2, Raised Forecastle 2); 68 hulls carry a wave piece (all copper sheathing, +2).
- All 238 harbours' roadsteads resolve a sea in the raster; classified with the authored boxes they fall exactly into the
  design's §2 table (every zone's harbour list matches, e.g. NOR-MAC = ANG CID GOR LPA PON SAI TEN; NOR-ICE = NUU REY;
  HNL = NRT-OPEN; HAG = PHI).
- Bristol → Cape Coast exists in `npc_courses` (10 points, 3,756 nm) and in three merchant loops.
- The 17 humans: `min(trading, exploration)` is 1 for 16 and 3 for JOOHOON HA; every stored `title_level` is 1.
- The straight line Lisbon → Havana samples 123 cells of NOR, 3 of GCO and 1 land cell (the Bahamas).
- Knobs for the probe: `fleet_ship_max` 8, `ship_max` 8, `fleet_ship_base` 2 (+ SEAMANSHIP 5 → room for 3 hulls).
- `item_effects_stat_check` is the constraint's name; `world_config` is keyed on `key`.

## 4. Measured (local PGlite, the chain restored from the prefix cache and 0215 applied on it)

- **First cut: 787 s** for 0215 in PGlite. The zone raster took 10.6 s; the rest was `sea_leg_asks_derive()` — a
  per-sample join to `sea_zone_cells` and to `sea_zones`, run TWICE (the self-assert re-derived every pair to compare
  300 rows). **Second cut: 105 s** (raster 16 s, the derivation ~80 s): the whole raster is read once as one 1 MB
  bytea and a sample is one `get_byte`; the distinct zone bytes per pair are joined to `sea_zones` once; the
  re-derivation check takes `p_from` and re-derives Lisbon's 238 legs only. PGlite is wasm; native PostgreSQL is
  expected several times faster (measured at push).
- The receipt (PGlite world: 908 hulls, 13 humans): 647,214 water cells of 1,036,800, every one zoned; 56,644 leg
  asks; 65 wave rows; the ten old stats unchanged on every hull; 238 harbours resolve; Lisbon → Havana sampled
  crosses {GCO, NOR-AM, NOR-EU, NOR-MAC, NOR-MID}, its vertices alone {GCO, NOR-EU}; the prod course Bristol → Cape
  Coast (10 vertices) crosses {ENG, GUL, NOR-DOL, NOR-EU, NOR-MAC}; the rule, the probe (21), the dark/lit gate, the
  walls — all as the header promises.
- Hot readers, 8 calls each in one session (PGlite's clock is coarse; prod's receipt is the measurement that counts):
  `world.ship_stats` old vs new within noise (0.1–0.7 ms); `course_zones` of the Lisbon → Havana line 5.1 ms (first 3
  5.7, last 3 4.3 — no generic-plan cliff); `fleet_wave` 1.6 ms; `title_level` 0.6 ms.
- `node scripts/db/proof.mjs 03_grant`: 12/12 PASS (RLS on all 111 tables, 0 client write grants, the registry
  executable). World guard: equal, with the positive controls seen. `tsc -b` clean. `tests/duplication.spec.ts`
  10/10.

## 5. Not verified here

- The migration has not run on prod (no db push by order): the self-assert's probe (new house, three hulls, the switch
  flipped inside a rolled-back sub-transaction) runs at push.
- CI's disposable-Supabase job is the first real PostgreSQL to run the raster derivation; PGlite's timing is the only
  measurement until then.
- No browser build: no screen changed (the catalogue, types and a wrapper only). `tsc -b` passes.
