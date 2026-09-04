# 0076 — THE ROADSTEAD

**Design, decided 2026-09-04. Build option A.** Owner request row 72 (`docs/OWNER_REQUESTS.md:131`):

> "create a perpendicular helper line (dotted) that is the shortest point between the land city and
> nearby shore - sea. Then create a point there, and when the ship arrive at that point, consider it
> as the ship have landed on land"

---

## 0. THE MEASUREMENTS THAT DECIDED IT

Taken 2026-09-04 by building the live raster (`scripts/sea-grid.mjs` `buildSeaGrid()`) and running
the ONE pathfinder (`src/lib/sea/pathfind.ts` `floodFrom`/`floodPathTo`/`snapToNav` — the same code
`scripts/build-sea-migration.mjs:53,209` uses) over all 238 places (224 from `data/ports.json` + 14
from `data/sea-places.json`), coordinates rounded to 2 dp to match `ports.lat numeric(6,2)` /
`ports.lon numeric(7,2)`. 238 floods, 141.8 s.

### 0.1 How many ports have a roadstead

| | count |
|---|---|
| places in `sea_reaches` | 238 |
| own cell already water (snap = 0) | 77 |
| own cell is land → a real roadstead off the quay | **161** |
| snap > 10 nm | 139 |
| snap > 20 nm | 40 |
| snap > 30 nm | 13 |
| snap > 50 nm | 3 |
| worst | LNG 67.68 · HAN 58.68 · KHA 57.77 · TOK 47.69 · PAT 47.21 · TRO 45.98 · IZM 40.29 · AMS 35.47 |

Production holds `sea_reaches` as re-inserted by **0052** (`20260818000052_…sql:92-94` deletes and
re-inserts), not 0046.

### 0.2 Distance effect of each option, all 28,203 pairs

`today` = the straightened city→city polyline. `A` = straightened roadstead→roadstead. `B` = A plus
the two snaps.

| | OPTION A | OPTION B |
|---|---|---|
| mean Δ | −11.70 nm | +12.12 nm |
| median Δ | −11.88 nm | +7.87 nm |
| p10 … p90 | −33.49 … +6.09 nm | −3.90 … +30.01 nm |
| **median Δ%** | **−0.17 %** | +0.12 % |
| p01/p99 Δ% | −6.71 / +1.65 % | −1 / +6.8 % |
| pairs moving < 0.5 % | 74.3 % | — |
| pairs moving > 5 % | 1.86 % | — |
| **SHORT routes ≤ 600 nm (n=1,031)** | **mean −0.03 nm, +0.51 %** | **mean +24.05 nm, +14.04 %** |
| mid 600–3,000 nm | −9.19 nm, −0.59 % | +13.60 nm, +0.92 % |
| long > 3,000 nm | −13.04 nm, −0.17 % | +11.09 nm, +0.16 % |

**B is the repricing, not A.** Today's course leaves the CITY and the head allowance lets the
straightener cut a corner across the coast; forcing the line through the roadstead replaces that
corner-cut with a dogleg worth +12.12 nm mean, p99 +69 nm. A's removal of the two snaps cancels that
dogleg almost exactly. B can only be made exact by defining the approach as the residual
`today_nm − water_nm`, a number with no geometry — forbidden by `src/chart/route.ts:8-12`.

### 0.3 The only four pairs that move more than 500 nm under A

| pair | today | option A | Δ |
|---|---|---|---|
| Panama City → Veracruz | 1,449.3 | 11,746.4 | +10,297.1 |
| Panama City → Port Royal | **560.9** | 10,577.6 | +10,016.7 |
| Panama City → St. Augustine | 1,944.6 | 11,088.6 | +9,144.0 |
| Hamburg → Lübeck | **31.2** | 577.1 | +546.0 |

560.9 and 1,944.6 are `docs/RESUME.md:46-48`'s own figures to the tenth. Six ports involved (PAN,
POR, STA, VER, HAM, LUB), no others. **These are the documented live breaches of the never-touch-land
law. Repairing them IS the point, but it is a visible gameplay change.**

### 0.4 The land guard at the SQL rule's own sampling (half-cell ≤ 7.5 nm, head/tail exempt)

| passage | endpoints | head / tail | samples | on land | verdict |
|---|---|---|---|---|---|
| Panama City → Port Royal | cities | snap+25 = 35.82 / 44.02 | 65 | 0 | **ACCEPTED — the live defect** |
| Panama City → Port Royal | roadsteads | 25 / 25 | 66 | 2 | E_LAND at 29.9 nm |
| Hamburg → Lübeck | cities | 31.33 / 46.68 | **0** | 0 | **ACCEPTED — the guard checks NOTHING** |
| Hamburg → Lübeck | roadsteads | 25 / 25 | 1 | 1 | E_LAND at 26.7 nm |

The Hamburg row is the worst finding: the whole 31.2 nm line lies inside `head + tail = 78 nm`, so
`voyage.path_refusal` walks it and **checks zero samples**. The guard is not lenient there, it is off.

### 0.5 Precision

All 238 roadstead coordinates are exact multiples of 0.125° (fractional parts only
`.125 .375 .625 .875`), because a cell centre is `90 − (row+0.5)·0.25` / `−180 + (col+0.5)·0.25`.
**3 decimal places is exact and lossless. A 4th decimal would be a fiction about a 0.25° raster.**

### 0.6 Shared roadsteads

234 distinct cells for 238 places. Four cells shared by two places each: Bandar Abbas + Hormuz,
Cape Coast + Elmina, Ceuta + Gibraltar, Osaka + Sakai. **Do not assume uniqueness.**

---

## 1. THE §7B QUESTIONS, ANSWERED

### 1.1 The concept, in one noun phrase

> **The roadstead — the one point of open water a port is reached from.**

**The word matters, and `anchorage` IS ALREADY TAKEN.** `src/chart/chartModel.ts:52` defines
`PortRole = 'anchorage' | 'destination' | 'route'`, where `anchorage` means "one of your fleets lies
in this port"; `PortScreen.tsx` prints an "At anchor" card; `FleetView.anchor` on the wire is a
fleet's held sea point. Naming this concept `anchorage` puts a second meaning on that word inside the
same module — the exact defect `docs/NO_SPAGHETTI.md` §7B exists to prevent. `roadstead` appears in
this repository only as prose (`src/chart/glyphs.ts:10,151`, `src/chart/labels.ts:154`, all meaning
"a small port"), never as an identifier. Take it.

### 1.2 Where it lives

**Two columns on `public.sea_reaches` — `roadstead_lat numeric(6,3)`, `roadstead_lon numeric(7,3)`.
Not a new table, and NOT on `public.ports`.**

- **Not on `ports`.** `ports` is the AUTHORED world (`data/ports.json` → 0003/0041/0058) and since
  0041 every `db:apply`/`db:proof` runs `scripts/db/world-guard.mjs`, which fails unless the applied
  world EQUALS `data/*.json` (`supabase/migrations/CHAIN.md:12-15`). A raster-derived column on
  `ports` either breaks that guard or forces the roadstead into `data/ports.json`, where a hand edit
  could put it on land. A port's coordinate is a fact about a **city**; the roadstead is a fact about
  the **raster**.
- **Not its own table.** `sea_reaches` is already one row per place keyed on `port_id`, and its entire
  content is "what the raster says about this place's relation to the water". `snap_nm` (0046:79) IS
  literally the distance to this point. The point and its distance are one measurement taken in one
  pass by one function; splitting them across two tables makes it possible for them to disagree. A new
  table buys no new key, no new cardinality, no new lifetime — `sea_reaches` is already
  deleted-and-rebuilt wholesale when the raster moves (0052:92-94).
- **Computation module:** nothing new. Where `snap_nm` already lives — `snapToNav`
  (`src/lib/sea/pathfind.ts:149-174`) under Node via `scripts/build-sea-migration.mjs:53,209-211`.

### 1.3 The second caller — there are FOUR, all on day one

1. **`cmd.do_sail`** (0047:549) — the course endpoint (`:602`) and the tail allowance (`:606`).
2. **`world.snapshot()` → the chart** (`liveWorld.ts:mapPortsOf` → `PortsLayer` + the new layer).
3. **`src/domain/passage/index.ts`** (`sailOrigin:44`, `proposeCourse:73`) — the client's order-time
   search. If it keeps searching city→city while the server verifies roadstead→roadstead, **every
   order is refused `E_OFF_COURSE`.**
4. **`voyage.assert_paths_water()`** (0047:1154, allowances `:1185-1188`) and
   `scripts/db/proofs/09_the_fleet_never_touches_land.sql`.

Four callers of one number is why it is persisted and served once, never derived per read.

### 1.4 What would make this design wrong

**If a client could compute a roadstead.** Then the line drawn, the course proposed and the endpoint
verified become three answers and drift silently. The guard cannot be "delete `snapToNav` from the
client", because the client legitimately needs it for a TAPPED sea point (`snapSeaPoint`,
`domain/passage/index.ts:92`). So the guard is a TEST: `tests/duplication.spec.ts` gains a rule that
`snapToNav` has exactly one importing file in `src/` (`src/domain/passage/index.ts`) and **zero** under
`src/chart/**` or `src/features/**`. Watch it red by adding the import to `PortsLayer.tsx` first.

Second: **if the drawn line's length were not `snap_nm`.** Made a schema-level invariant in §6.4(b).

---

## 2. THE ROADSTEAD ITSELF

### 2.1 Computation, and the three snap implementations

**No SQL function returns the snapped CELL.** Grepped 0046 and 0047 for `sea_at`, `sea_near`,
`sea_cell`, `water_snap`:

- `voyage.sea_at(lat,lon)` (0040) → a sea uuid.
- `voyage.sea_near(lat,lon)` (0047:166-191) → a sea uuid.
- `voyage.water_snap_nm(lat,lon)` (0047:199-237) → **numeric only.** It computes the best cell's
  `rr`/`cc` at 0047:225-228 and **throws the coordinates away.**

**Three snap implementations, and two of them are not the same rule — measured, not asserted:**

| | rings | picks | returns |
|---|---|---|---|
| `snapToWater` `scripts/sea-grid.mjs:246-262` | **8** | the **first** water cell in scan order at the first non-empty ring | cell, no distance |
| `snapToNav` `src/lib/sea/pathfind.ts:149-174` | **12** | the **minimum-distance** cell within that ring | cell + nm |
| `voyage.water_snap_nm` 0047:199-237 | **12** | the **minimum-distance** cell | nm only |

`snapToNav` and `water_snap_nm` agree. `snapToWater` is a **different answer** and can return a
different cell. **Say it plainly: that is spaghetti, and the one authority is `snapToNav`.** Its whole
reachable graph is `snapToWater` ← `findSeaRoute` (`sea-grid.mjs:274-277`) ←
`scripts/build-sea-places.mjs:157`, and nothing else. The honest fold is to delete both and repoint
`build-sea-places.mjs` at `findPath` — **but that regenerates `data/sea-places.json` and is a different
slice.** 0076 does NOT touch it; it NAMES it in its header as a known second authority with exactly one
build-time caller, and `tests/duplication.spec.ts` gains a rule pinning that caller count at 1 so it
cannot grow a second while it waits.

**What 0076 DOES fold, and it is the important one:** `voyage.water_snap_nm`'s body moves down into

```sql
voyage.water_roadstead(p_lat numeric, p_lon numeric)
  returns table (nm numeric, lat numeric, lon numeric)
```

and `voyage.water_snap_nm` is re-cut to `select nm from voyage.water_roadstead($1, $2)`. **No signature
moves, no function is dropped, three existing callers untouched** (0047:594, 0047:612, 0047:1186-1189),
and there is now exactly ONE body answering "where is the water nearest this point, and how far". That
fold is what makes the headline self-assert possible: the JS-generated column can be checked against
the SQL rule for all 238 rows.

### 2.2 Persisted, not derived

1. Four day-one callers, two on the hot path of every order.
2. **Cost.** `voyage.water_snap_nm` is a 12-ring PL/pgSQL loop over `get_bit` on a 259 KB `bytea`.
   Deriving it inside `world.snapshot()` runs it 238 times per snapshot, and that read is the one the
   client "caches hard" (0009:19).
3. It is generated data exactly like `snap_nm` and `reaches` beside it, from the same pass.

### 2.3 Precision — exact types

```sql
roadstead_lat numeric(6,3) not null,   -- ±90,  exact: a cell centre is a multiple of 0.125°
roadstead_lon numeric(7,3) not null    -- ±180, same
```

3 dp is lossless (§0.5). `numeric(6,3)` holds ±999.999, `numeric(7,3)` ±9999.999. Mirrors the
`(6,·)/(7,·)` shape `ports.lat/lon` already use so the pair reads as the same kind of thing. Joining is
not an issue: `voyage.segments_from_course` rounds path vertices to 4 dp (0047:302) and
`course_join_nm` is 15 nm (0047:106); 3 dp ≈ 0.06 nm.

### 2.4 A port already ON water — the rule

**The roadstead of a port whose own cell is sailable water IS THE PORT'S OWN COORDINATE, `snap_nm = 0`,
and the helper line has zero length.**

Forced by `src/chart/route.ts:8-12`. The alternative (roadstead = the containing cell's CENTRE) would
put the roadstead **up to 10.6 nm** from a port whose `snap_nm` is 0 — a drawn line whose length is not
the measured distance. Forbidden.

Under this rule the invariant `gc(port, roadstead) == snap_nm` holds for **all 238 rows**.

**§7C.** The chart's conditional is "draw the line and the mark iff the two points differ". Both
branches are ACCEPTABLE: for the 77 places that ARE their own roadstead, drawing nothing is the
**correct** picture, not a degraded one — there is no line because the distance is zero. It is decided
from a SERVED number (`roadstead.nm`), never from a client comparison of two floats.

**Consequence for the generator, easy to miss:** `scripts/build-sea-migration.mjs` must emit
`p.lat/p.lon` when `flood.source.snapNm === 0`, NOT `cellLat/cellLon`. And `voyage.water_roadstead` must
implement the same rule (return the point itself when the point's own cell is water) or the cross-check
in §6.4(e) fires on 77 rows. It is also the right runtime answer for a fleet's own anchor.

---

## 3. WHAT THE WIRE CARRIES

**`world.snapshot()`** — the static world, one call, cached hard, already the chart's only source of
ports (`src/chart/liveWorld.ts:mapPortsOf` ← `SnapshotPort`). Its live cut is
`20260818000032_a_good_is_as_rare_as_the_ports_that_make_it.sql:115`, sliced since by 0036 (`ports[]`
gained `kind`, `approach`), 0067:146 (`buildings`) and 0071:160 (config). **Not** `world.reach(p_from)`
(0047:1087) — per-port, the chart would need 238 calls.

`ports[]` gains ONE key, using the correlated-subselect shape 0067 used for `buildings` so no change to
the FROM clause is needed and the slice is a single hunk:

```sql
'roadstead', (select jsonb_build_object(
                'lat', sr.roadstead_lat, 'lon', sr.roadstead_lon, 'nm', sr.snap_nm)
               from public.sea_reaches sr where sr.port_id = p.id),
```

```jsonc
"roadstead": { "lat": 52.875, "lon": 4.375, "nm": 35.47 }   // Amsterdam
"roadstead": { "lat": 36.53,  "lon": -6.30, "nm": 0     }   // a port on its own water
```

**Never null.** Every port has a `sea_reaches` row — 0049:85 already asserts
`count(sea_reaches) = count(ports)` and 0065:4329 re-asserts it. 0076 asserts it again BEFORE relying on
it, and asserts the port count is non-zero first so the check is not vacuous. So there is no null arm on
the client and no §7C fallback to reason about.

**Deliberately NOT on the wire:** the raster row/col. The client has the raster (`world.sea_raster()`);
serving cell indices beside coordinates would be a second spelling of the same fact.

---

## 4. WHAT THE CLIENT DRAWS

### 4.1 The dotted helper line

- **File:** new `src/chart/RoadsteadsLayer.tsx`. **Not** exported from `src/chart/index.ts` —
  `docs/SECTIONS.md:108` is explicit that the SVG layers are "exported to nobody" and `ChartCanvas` is
  the only composer, "which is what makes the paint order a rule rather than a habit".
  `tests/sections.spec.ts` enforces it.
- **Paint order:** inserted in `src/chart/ChartCanvas.tsx` between `<TracksLayer/>` (`:146`) and
  `<PortsLayer/>` (`:166`) — coastline → tracks → **roadsteads** → ports → fleets → labels.
  `src/chart/FleetsLayer.tsx:6-9` states the rule: "a dotted line crossing a port should pass behind
  it". A city mark sitting on a roadstead wins, which is right.
- **Dash:** reuse **`strokeDasharray="1 5"`** — the "water ahead of the fleet" pattern at
  `FleetsLayer.tsx:40`. Sparsest dot already in the vocabulary and it already means "line not yet made
  good". Do NOT reuse `"1 3"` (the SAILED half of a track) or `"3 3"` (the destination ring).
- **Ink:** `stroke-ink-faint/70`, `strokeWidth={GLYPH.trackStroke}`, `vectorEffect="non-scaling-stroke"`.
  **Not `stroke-accent`** — accent is reserved for YOUR fleets; a roadstead is true of every port
  whether you use it or not. It is chart furniture, like the coastline.
- **Geometry:** `project(port)` → `project(port.roadstead)` through `toPolylineD`
  (`src/chart/svgPath.ts`), i.e. lat/lon-linear, which is what route.ts's geometry rule requires.

### 4.2 The roadstead point

A small **hollow circle**, `r = GLYPH.roadsteadRadius * unitsPerPx` with `roadsteadRadius: 2.6`,
`className="fill-none stroke-ink-faint/85"`, `strokeWidth={GLYPH.glyphStroke}`.

| mark | shape | why different |
|---|---|---|
| harbour (`PortsLayer`) | triangle | shape |
| sea place (`PortsLayer`) | lozenge | shape |
| destination ring (`FleetsLayer:68,85`) | circle **r 11**, dashed `3 3`, accent | 4× radius, dashed, brass |
| fleet at sea (`FleetsLayer:113`) | circle r 4.4, **filled** accent, haloed | filled, brass, haloed |
| **roadstead** | circle **r 2.6, hollow**, faint ink, solid stroke | smallest, hollow, ink not brass |

`GLYPH.roadsteadRadius` goes in `src/chart/glyphs.ts` beside the others, with the derivation in its
comment (2.6 ≈ the quiet mark's 3.6 half-width less the stroke, so it reads as smaller than the smallest
port).

### 4.3 Low zoom

Draw the pair **iff** the projected separation is ≥ `GLYPH.roadsteadMinPx = 6` (twice the quiet mark's
`quietPortHalfWidth: 3.6`). Below that the line is shorter than the mark it leaves and is noise.

Measured, not guessed: `glyphs.ts:97` records 38 CSS px covers **70 nm** on the opening frame and 9 nm
four steps in. So 6 px ≈ **11 nm** at the opening frame: at first sight the ~40 harbours snapping over
20 nm all show their line, the ~100 under 11 nm do not, and zooming reveals them — the same "zoom is the
precision control" answer `glyphs.ts:96-99` already gives.

The set drawn is **`chartModel.visiblePorts(...)`, the same list `PortsLayer` is handed** — not the whole
port table. `chartModel.ts`'s header: "a port you can tap but cannot see, or a name floating over a mark
that was never drawn, are both the same bug".

**The hit test is deliberately NOT touched.** `hitTest.ts` keeps its three subjects (port, fleet, sea). A
tap near a roadstead selects the nearest port or open sea, as today. Adding a fourth subject inside a
38 px radius would make "which port is this" ambiguous — `glyphs.ts:72` and `docs/OWNER_REQUESTS.md:102`
both name that as worse than no button. Stated as an omission, not missed.

### 4.4 `MapPort` / `chartModel.ts`

`src/chart/mapTypes.ts` `MapPort` gains:

```ts
/** 0076 — THE ROADSTEAD: the one point of open water this port is reached from, and how far off
 *  the quay it lies. Both SERVED (`world.snapshot().ports[].roadstead`), copied field-for-field.
 *  For a port whose own cell is sailable water this IS the port's coordinate and `roadsteadNm` is
 *  0 — the helper line has zero length and is not drawn, which is the correct picture of a port
 *  that is its own roadstead, not a fallback. The chart never computes one: a client-side snap
 *  would be a second answer to "where is this port reached from" (tests/duplication.spec.ts). */
readonly roadstead: LatLon
readonly roadsteadNm: number
```

`liveWorld.ts:mapPortsOf` copies them; nothing is derived.

**It does not break the D33 "takes no clock" property.** The model is a pure function of the last read,
and `Drift` (0075) is the only time-dependent input. The roadstead is a STATIC served fact of the world,
in the same class as `lat`, `sizeTier` and `kind`. **`buildChartModel`'s signature does not change at
all** — the roadstead is read by the layer straight off `MapPort`, exactly as `PortsLayer` reads
`sizeTier` and `kind`. `driftedPoint`, `Drift` and `segNm` are untouched.

**`tests/mapWorld.fixture.ts` needs the two fields on its 214 rows** — it writes the port table out by
hand precisely because `tsconfig.test.json` withholds Node globals from specs. Real work, in the plan.

---

## 5. ARRIVAL — "consider it as the ship have landed on land"

### 5.1 NOTHING changes in `voyage.settle`. Say it plainly.

`voyage.settle(p_fleet, p_now)` — `20260818000027:237`, arrival arm `:409-416` — today:

```sql
if p_now >= v.eta then
  update public.voyages set status = 'ARRIVED', ... where id = v.id;
  update public.fleets set status = ..., port_id = v.dest_port_id, ... where id = p_fleet;
```

Arrival is **the end of the course**, and it docks her at `v.dest_port_id` — the port, not the course's
last coordinate. So the moment the course's last point becomes the roadstead, the owner's sentence is
**already true, by the mechanism that has been shipping since 0007.** No geometric arrival test is
needed, none should be invented, and adding one would be a second authority for "has she arrived" beside
the ETA.

**The owner's sentence is satisfied by moving ONE thing: the endpoint, in `cmd.do_sail`. That is the
whole of the arrival work. Do not write more.**

### 5.2 What changes in `cmd.do_sail` (0047:549) — four hunks, all inside the one mover

| line | today | 0076 |
|---|---|---|
| `:588` origin at a quay, allowance | `coalesce((select snap_nm ...), 0) + 25` | `25` |
| `:589-590` origin at a quay, point | `p.lat, p.lon` | `sr.roadstead_lat, sr.roadstead_lon` |
| `:602` destination port, point | `select p.lat, p.lon into v_dlat, v_dlon` | `select sr.roadstead_lat, sr.roadstead_lon into v_dlat, v_dlon from public.sea_reaches sr where sr.port_id = v_dest` |
| `:606` destination port, allowance | `coalesce((select snap_nm ...), 0) + 25` | `25` |

**Why 25 and not 0.** `src/lib/sea/pathfind.ts:330` gives every path end a `cellDiagNm` =
`0.25 × 60 × √2` = **21.21 nm** of sampling slack, unconditionally. A server allowance below that would
refuse courses the client's own straightener legitimately produced — the exact failure 0047:195-198
records finding "the expensive way". 25 is the constant already in the file and the smallest number
≥ 21.21 that is already there; inventing a knob would be new machinery for no new decision. **Stated
honestly: after 0076 a course still enjoys a flat ~21 nm (client) / 25 nm (server) land-crossing
exemption at each end.** Shrinking THAT is the never-touch-land slice (`docs/RESUME.md:44-52`), not this
one. §0.4 measures that 25/25 closes both known breaches.

`cmd.divert` (0047:902) needs **no change**: it composes the onward passage through `cmd.issue` →
`cmd.do_sail`, which is the whole point of THE ONE MOVER.

`voyage.assert_paths_water()` (0047:1154, allowances `:1185-1188`) takes the same `+ 25` → `25` change,
or the guard keeps the hole 0076 just closed.

### 5.3 `sea_reaches.reaches` MUST be regenerated — not optional

Under A the mover measures roadstead→roadstead while `voyage.reach_from` (0047:338) still serves
city→city out of `sea_reaches.reaches`. For 99 % of pairs the divergence is under 1.7 % — but for four
pairs it is a lie the player can SEE: `src/features/port/PortScreen.tsx:186-190` prints the reach table
as "the sailed legs out", so **Port Royal would be advertised at 560.9 nm from Panama City and a SAIL
there would be refused `E_NO_COURSE`.** A screen offering a passage the mover refuses is precisely §7C's
"choosing between an acceptable outcome and an unacceptable one", and 0047:445-448 already states the
standing law: "`world.trade_routes` refuses to recommend what this refuses."

**So 0076 regenerates `sea_reaches` WHOLE — roadstead columns, `snap_nm`, and roads-to-roads `reaches` —
in one `delete` + `insert`, exactly the shape 0052:92-94 used. This makes 0076 a GENERATED migration in
the 0046/0052 family (emitted by `scripts/build-sea-migration.mjs`), not a hand-typed slice.** It is one
concept — a harbour is reached from its roads — and splitting it would ship a half-state in which the
quay and the mover disagree.

### 5.4 The sentence the player reads

1. **Port screen**, in the harbour header block of `src/features/port/PortScreen.tsx` (beside the reach
   list at `:181-190`), for a port with `roadstead.nm > 0`:

   > "The roads lie 35.5 nm off the quay. Ships anchor there; the pilot takes her the rest of the way in."

   The number is `port.roadstead.nm`, served, printed. It must NOT reuse the `ports.approach` column,
   which is a SEA_PLACE-only text remark (0036:183-186,
   `check ((kind = 'SEA_PLACE') = (approach is not null))`) and would be a second meaning for that word.

2. **The map's send-fleet panel** (`src/features/map/SendFleet.tsx`), one line under the destination
   name, so the player understands BEFORE ordering why the track will start off the quay:

   > "She sails from the roads, 35.5 nm out."

**Why the sentence must exist:** at departure the marker moves from the city triangle to the roadstead —
median 13 nm, max 67.7 nm — and without a sentence that reads as a bug.

---

## 6. MIGRATION 0076

### 6.1 Filename

```
supabase/migrations/20260818000076_a_harbour_is_reached_from_its_roads.sql
```

0076 is confirmed free (highest file is `…000075_the_leg_she_is_on_has_a_length.sql`); **0060 is
RESERVED** by the blocked `osn-0060-harbour-snaps` branch (`supabase/migrations/CHAIN.md:8-9`). **LF
only** — `.gitattributes` forces it on `*.sql`, and a CRLF body can never match `pg_get_functiondef`,
which this file depends on twice.

### 6.2 The 5-part header (per `supabase/migrations/README.md` §2)

1. **Number + title.** `0076 — A HARBOUR IS REACHED FROM ITS ROADS` *(the roadstead becomes a place:
   seeded, served, drawn — and the course ends there)*.
2. **Why now — the owner, verbatim** (`docs/OWNER_REQUESTS.md:131`, row 72), quoted whole.
3. **What says the opposite, named with `file:line`:**
   - `cmd.do_sail` takes the port's raw coordinate as the course endpoint (0047:602) and grants
     `snap_nm + 25` nm of land-crossing allowance at each end (0047:588,606).
   - `voyage.path_refusal` skips every sample inside that allowance; the client mirror is
     `src/lib/sea/pathfind.ts:317`.
   - `sea_reaches` records the snap DISTANCE and discards the point (0046:79); `voyage.water_snap_nm`
     computes the cell at 0047:225-228 and returns only the number.
   - `snapToWater` (`scripts/sea-grid.mjs:246`) is a THIRD, DIFFERENT snap rule (first-in-scan-order,
     8 rings) with one build-time caller; named, pinned by a duplication test, left for its own slice.
4. **What this does and deliberately does not.** Does: two columns, a regenerated 238-row `sea_reaches`,
   the `water_roadstead` fold, four `do_sail` hunks, one `snapshot` hunk, one guard hunk. **Does not:**
   touch `voyage.settle` (arrival is already right); shrink `cellDiagNm`; open or close a single CHANNEL;
   move any price knob.
5. **Evidence — measured, with where.** §0's tables: 161 places carry a roadstead; median distance change
   −0.17 %, 74.3 % of pairs under 0.5 %; 4 of 28,203 pairs move over 500 nm and all four are the
   documented live breach; Panama City→Port Royal city→city is ACCEPTED today with 65 samples and 0 on
   land, roads→roads is refused E_LAND at 29.9 nm; Hamburg→Lübeck city→city has ZERO samples checked.

### 6.3 What it creates / alters, in order

```sql
alter table public.sea_reaches
  add column if not exists roadstead_lat numeric(6,3),
  add column if not exists roadstead_lon numeric(7,3);

create or replace function voyage.water_roadstead(p_lat numeric, p_lon numeric)
returns table (nm numeric, lat numeric, lon numeric) ...        -- 0047:199's body, moved down;
                                                                -- returns the POINT ITSELF at ring 0
create or replace function voyage.water_snap_nm(p_lat numeric, p_lon numeric)
returns numeric language sql stable security definer set search_path = public, pg_temp
as $$ select nm from voyage.water_roadstead(p_lat, p_lon) $$;   -- same signature, one line

delete from public.sea_reaches;                                 -- the 0052 precedent, exactly
insert into public.sea_reaches (port_id, code, snap_nm, roadstead_lat, roadstead_lon, reaches) ...

alter table public.sea_reaches
  alter column roadstead_lat set not null,
  alter column roadstead_lon set not null;

select pg_temp.recut('cmd.do_sail(uuid, jsonb)'::regprocedure, false, ...4 hunks...);
select pg_temp.recut('voyage.assert_paths_water()'::regprocedure, false, ...1 hunk...);
select pg_temp.recut('world.snapshot()'::regprocedure, false, ...1 hunk...);
revoke all on function world.snapshot() from public, anon;
grant execute on function world.snapshot() to authenticated;
-- + the same revoke/grant for water_roadstead (server-only) and water_snap_nm
```

`pg_temp.recut` is 0075's helper (0075:66-88), verbatim, with the `0076` slice id: it refuses unless each
hunk occurs **exactly once** in the deployed body, so a drifted production body fails the apply instead
of silently landing.

**`world.snapshot()`'s hunk anchor**, chosen for uniqueness against the DEPLOYED body (0032:115 as sliced
by 0036 and 0067):

```sql
$s0$        'kind', p.kind, 'approach', p.approach,$s1$
```

`p.kind` and `p.approach` appear nowhere else in that function.

### 6.4 The self-assert (write it out in full in the migration; this is the contract)

```sql
do $$
declare
  v_places  int; v_missing int; v_bad int; v_far int; v_grants int;
  v_pan_lat numeric; v_pan_lon numeric; v_por_lat numeric; v_por_lon numeric;
  v_pan_snap numeric; v_por_snap numeric;
  v_pan_rlat numeric; v_pan_rlon numeric; v_por_rlat numeric; v_por_rlon numeric;
  v_city_line jsonb; v_road_line jsonb; v_ref text; v_road jsonb;
begin
  -- (a) NOT VACUOUS: the table is populated, and every port has a row.
  select count(*) into v_places from public.sea_reaches;
  if v_places < 200 then
    raise exception '0076 self-assert FAIL: sea_reaches holds only % row(s) — every check below would pass over nothing', v_places;
  end if;
  select count(*) into v_missing from public.ports p
   where not exists (select 1 from public.sea_reaches sr where sr.port_id = p.id);
  if v_missing <> 0 then
    raise exception '0076 self-assert FAIL: % port(s) carry no sea_reaches row, so world.snapshot would serve them a null roadstead', v_missing;
  end if;

  -- (b) THE LINE DRAWN IS THE DISTANCE MEASURED (src/chart/route.ts:8-12).
  select count(*) into v_bad
    from public.sea_reaches sr join public.ports p on p.id = sr.port_id
   where abs(voyage.gc_distance_nm(p.lat::float8, p.lon::float8,
              sr.roadstead_lat::float8, sr.roadstead_lon::float8)::numeric - sr.snap_nm) > 0.01;
  if v_bad <> 0 then
    raise exception '0076 self-assert FAIL: % place(s) whose helper line is not snap_nm long — the line drawn would not be the distance measured', v_bad;
  end if;

  -- (c) A PORT ON ITS OWN WATER IS ITS OWN ROADSTEAD — and it is not the whole table.
  select count(*) into v_bad
    from public.sea_reaches sr join public.ports p on p.id = sr.port_id
   where sr.snap_nm = 0 and (sr.roadstead_lat <> p.lat or sr.roadstead_lon <> p.lon);
  if v_bad <> 0 then
    raise exception '0076 self-assert FAIL: % place(s) snap 0 nm and yet hold a roadstead off the quay', v_bad;
  end if;
  select count(*) into v_far from public.sea_reaches where snap_nm > 0;
  if v_far < 100 then
    raise exception '0076 self-assert FAIL: only % place(s) hold a roadstead off the quay — 161 were measured, and a table of quay-coordinates would pass (b) and (c) vacuously', v_far;
  end if;

  -- (d) EVERY ROADSTEAD STANDS ON SAILABLE WATER, asked of the raster itself.
  select count(*) into v_bad from public.sea_reaches sr
   where voyage.water_snap_nm(sr.roadstead_lat, sr.roadstead_lon) <> 0;
  if v_bad <> 0 then
    raise exception '0076 self-assert FAIL: % roadstead(s) do not stand on sailable water', v_bad;
  end if;

  -- (e) THE GENERATOR AND THE SQL ARE ONE RULE — why water_snap_nm's body was folded down.
  select count(*) into v_bad
    from public.sea_reaches sr join public.ports p on p.id = sr.port_id
   cross join lateral voyage.water_roadstead(p.lat, p.lon) w
   where w.lat <> sr.roadstead_lat or w.lon <> sr.roadstead_lon;
  if v_bad <> 0 then
    raise exception '0076 self-assert FAIL: % row(s) where the seeded roadstead is not what voyage.water_roadstead answers — the Node generator and the SQL rule have drifted', v_bad;
  end if;

  -- (f) POSITIVE CONTROL #1: collapse ONE roadstead back onto its quay and require (b) to find it,
  --     exactly once. Rolled back.
  begin
    update public.sea_reaches sr
       set roadstead_lat = p.lat, roadstead_lon = p.lon
      from public.ports p
     where p.id = sr.port_id
       and sr.code = (select code from public.sea_reaches order by snap_nm desc, code limit 1);
    select count(*) into v_bad
      from public.sea_reaches sr join public.ports p on p.id = sr.port_id
     where abs(voyage.gc_distance_nm(p.lat::float8, p.lon::float8,
                sr.roadstead_lat::float8, sr.roadstead_lon::float8)::numeric - sr.snap_nm) > 0.01;
    if v_bad <> 1 then
      raise exception '0076 self-assert FAIL: a roadstead collapsed onto its own quay was found % time(s), expected exactly 1 — check (b) cannot bite and every green above is vacuous', v_bad;
    end if;
    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  -- (g) THE HEADLINE AND ITS POSITIVE CONTROL — the isthmus of Panama.
  --     Read PAN and POR lat/lon/snap_nm/roadstead into the declared vars first.
  --     CONTROL (must stay GREEN): the OLD quay->quay line must still be ACCEPTED under the OLD
  --     allowance, or this file did not close what it claims to.
  v_city_line := jsonb_build_array(jsonb_build_array(v_pan_lat, v_pan_lon),
                                   jsonb_build_array(v_por_lat, v_por_lon));
  if voyage.path_refusal(v_city_line, v_pan_lat, v_pan_lon, v_por_lat, v_por_lon,
                         public.wc_num('course_join_nm'),
                         v_pan_snap + 25, v_por_snap + 25) is not null then
    raise exception '0076 self-assert FAIL: the quay-to-quay isthmus line is ALREADY refused under the old allowance — the defect this file claims to close is not there, and the repair below proves nothing';
  end if;
  -- THE REPAIR: the same passage between the two ROADSTEADS, under the flat allowance.
  v_road_line := jsonb_build_array(jsonb_build_array(v_pan_rlat, v_pan_rlon),
                                   jsonb_build_array(v_por_rlat, v_por_rlon));
  v_ref := voyage.path_refusal(v_road_line, v_pan_rlat, v_pan_rlon, v_por_rlat, v_por_rlon,
                               public.wc_num('course_join_nm'), 25, 25);
  if v_ref is null or v_ref not like 'E_LAND%' then
    raise exception '0076 self-assert FAIL: the line from the Panama roads to the Port Royal roads is not refused as E_LAND (got %) — the isthmus is open and 560.9 nm across it is still purchasable', coalesce(v_ref, 'ACCEPTED');
  end if;

  -- (h) THE WIRE CARRIES IT, FOR EVERY PORT.
  select count(*) into v_bad
    from jsonb_array_elements(world.snapshot()->'ports') p
   where p->'roadstead' is null or p->'roadstead'->>'lat' is null
      or p->'roadstead'->>'lon' is null or p->'roadstead'->>'nm'  is null;
  if v_bad <> 0 then
    raise exception '0076 self-assert FAIL: % served port(s) carry no roadstead — a client would have to compute one', v_bad;
  end if;
  select p->'roadstead' into v_road from jsonb_array_elements(world.snapshot()->'ports') p
   where p->>'code' = 'AMS';
  if (v_road->>'nm')::numeric <= 20 then
    raise exception '0076 self-assert FAIL: Amsterdam is served a roadstead % nm off the quay — 35.47 was measured, and a table of zeroes serves fine and draws nothing', v_road->>'nm';
  end if;

  -- (i) A REAL HOUSE SAILS, AND HER COURSE STARTS AT THE ROADS, NOT AT THE QUAY.
  --     (the 0075/0063 probe shape: new_house, provision, cmd.issue, read world.fleets, roll back)
  --     asserts: course[0] = the origin port's roadstead to the digit; total_nm > 0;
  --              at the ETA voyage.settle docks her at dest_port_id — THE OWNER'S SENTENCE,
  --              proven rather than argued, with voyage.settle unchanged.

  -- (j) POSTURE.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then raise exception '0076 self-assert FAIL: % client write grant(s)', v_grants; end if;
  select count(*) into v_grants from public.client_executable_writers();
  if v_grants <> 0 then raise exception '0076 self-assert FAIL: % client-executable writer(s)', v_grants; end if;

  raise notice '0076 self-assert ok: ...';
end $$;
```

**The two positive controls, and why each has been reasoned to go red:**

- **(f)** collapses one roadstead onto its quay — the precise regression this design fears — and requires
  check (b) to find it **exactly once**. If (b) were ever weakened to a tolerance that swallows a
  67.68 nm error, (f) goes red.
- **(g)**'s first half is a control that must stay **green**: the quay-to-quay isthmus line must still be
  accepted under the old allowance (measured: 65 samples, 0 on land). If it ever stops passing, the
  header's claim of a repair is false and the file says so instead of shipping a boast. Its second half
  must go **red-if-broken**: if `roadstead_lat/lon` ever regressed to `p.lat/p.lon`, the line and the
  allowance would both revert, `path_refusal` would return null, and the migration would refuse to apply.

**It touches no applied migration.**

---

## 7. RISK AND BLAST RADIUS

- **Distance/time on a voyage:** median −0.17 %, 74.3 % of pairs under 0.5 %, 98.1 % under 5 %. **Not a
  repricing** — 0048's tuning moved PRICES; this moves DISTANCES by a fifth of a percent at the median.
  `world.mid_price`, `world.quote`, `world.spread`, every knob and stock target untouched.
- **Four passages become impossible:** Panama City ↔ Port Royal / Veracruz / St. Augustine, and Hamburg ↔
  Lübeck. Six ports involved, nothing else. Any player running a Panama↔Caribbean loop loses a route that
  was a Panama Canal three and a half centuries early. **This is the repair, not the damage — but it is a
  visible gameplay change and the owner has been told in those words.**
- **In-flight voyages are safe.** `voyages.path`, `total_nm` and `speed_profile` are frozen at departure
  (0047:453-500), `voyage.position` reads that frozen row, and `voyage.settle` arrives on the frozen
  `eta`. A fleet at sea when 0076 applies finishes the voyage she bought.
  **HOWEVER:** `voyage.assert_paths_water()` gains the tighter allowance in the same file, so a legacy
  in-flight course that crossed the isthmus would fail the guard. It must keep skipping `legacy: true`
  segments (it already does — proof 09 counts `legacy_skipped`) AND **0076 must grandfather pre-0076
  SAILING voyages: the allowance change applies at ORDER time (`cmd.do_sail`), and `assert_paths_water`
  gets the new allowance only for voyages whose `departed_at >=` this migration's timestamp.** Anything
  else fails a proof over a voyage a player legitimately bought.
- **What breaks if this is wrong:** a wrong roadstead (on land, or the wrong side of a headland) makes
  every voyage to that port either refused `E_NO_COURSE` or routed absurdly. Checks (d) and (e) exist for
  exactly that, and (e) is a genuine cross-implementation check, not a re-read of what was just written.

### The nine proofs

| proof | effect |
|---|---|
| **09 `the_fleet_never_touches_land`** | **Materially affected.** Its `@pass INLAND_APPROACH_HONEST` (`:23`, `:136`) asserts "the river ports' water approach is measured and served … approach included". Under A that claim becomes **false as written**: the approach is no longer sailed. **Re-cut the marker, do not delete it** — its new law is "the approach is measured, served and drawn, and the course does not enter it": assert `roadstead_lat/lon` non-null and `gc(quay, roadstead) = snap_nm` for Suez, Bristol and Hanoi (the same three ports it names), plus that a fresh course to each STARTS at the roadstead. Its two other markers (`NEVER_TOUCH_LAND_WALKED`, `NEVER_TOUCH_LAND_BITES`) are unaffected, and `ARCTIC_IS_CLOSED`'s Lisbon→Nagasaki figure moves well under its 12,000 nm floor. |
| **08 `the_sea_answers`** | Reads reach/route figures; every asserted number needs re-baselining against the regenerated table. Mechanical, but must be done. |
| **04 / 05** | Both sail. Pinned figures shift by the voyage's own delta (sub-1 % for the routes they use). `proof.pin_market` (`scripts/db/market-fixture.mjs`) untouched — the market does not move — but any hard-coded ducat total that depends on days at sea must be re-taken. |
| **01, 02, 03, 06, 07** | Untouched. |
| `scripts/db/proof-courses.mjs` | Regenerates its proposals from `findPath`; must be re-run against roadstead endpoints in the same change. |

### The reserved 0060 branch — no collision, but a hard ordering

`osn-0060-harbour-snaps` (PR #5) opens CHANNELS so all 40 harbours snapping over 20 nm snap to ZERO
(Longyearbyen 67.68 → 0.00). It is a RASTER change; 0076 is a SHAPE change. Orthogonal. Under 0076 a port
that 0060 brings to snap 0 simply becomes its own roadstead and stops drawing a helper line — the correct
outcome, already handled by §2.4.

1. **0076 lands first.** Smaller, self-proving, and it makes 0060's own red honest to read.
2. **0060 is then REGENERATED, not merged as drafted** — it is a `build-sea-migration.mjs` output, and
   after 0076 that script emits the roadstead columns. A 0060 built before 0076 would
   `delete from sea_reaches` and re-insert WITHOUT them, silently NULLing columns 0076 declared
   `not null`. The apply would fail, which is the good case, but nobody should discover that in CI.
3. The CHANNELS repair (`docs/RESUME.md:49-53`, "moves 50,868 of 56,406 readings and DISCONNECTS 10
   ports") is a THIRD, separate slice. 0076 does not attempt it, does not block it, and shrinks its
   remaining surface by removing the `snap_nm` term from the allowance.

---

## 8. THE TEST PLAN — every spec names the control you delete to watch it go red

### 8.1 Migration-level

| proves | control |
|---|---|
| The whole chain applies with 0076 and every self-assert passes (`npm run db:apply` → `tests/db.chain.spec.ts`) | Blank one row's `roadstead_lat` before the assert block; §6.4(a)/(b) must raise. |
| `world.snapshot().ports[]` carries `roadstead` for all 238 (`tests/rpc.surface.spec.ts`) | Remove the `roadstead` key from the recut hunk; the shape assertion goes red. |
| `tests/db.image.spec.ts` — the pre-built world tarball still restores and certifies | Its fingerprint changes; watch the guard reject a stale image. |

### 8.2 Server behaviour (inside 0076's own assert + proof 09)

| proves | control |
|---|---|
| A SAIL to a snapping port produces a course whose first and last points are roadsteads | Revert the 0047:602 hunk; `course[0]` becomes the quay and the assert names the difference. |
| The Panama isthmus is refused roads→roads and accepted quay→quay-with-old-allowance | §6.4(g), both halves, on every apply. |
| Arrival still docks her at the port (`voyage.settle` untouched) | Point `dest_port_id` at the wrong port in the probe; the docked-port assert bites. |

### 8.3 Client

| spec | proves | control |
|---|---|---|
| **`tests/map.roadsteads.spec.ts`** (new) | For a fixture port with `roadsteadNm > 0`, `RoadsteadsLayer` renders ONE `<path>` whose `d` is exactly `project(port) → project(port.roadstead)` and whose `strokeDasharray` is `"1 5"`, plus ONE `<circle>` at `project(port.roadstead)`. | Set the fixture's `roadstead` equal to its `lat/lon`; both must disappear. |
| same | For a port with `roadsteadNm === 0`, NOTHING is rendered — the §2.4 / §7C rule. | Make the layer draw unconditionally; the zero-length case renders a degenerate path and the spec bites. |
| same | Below `GLYPH.roadsteadMinPx` of projected separation nothing is rendered; above it, both are. Assert at two named zooms with the real 38 px ≈ 70 nm scale. | Remove the threshold; the low-zoom case renders. |
| same | The set drawn is a subset of `visiblePorts(...)` — a culled port draws no roadstead. | Hand the layer the full port table; the count goes over. |
| **`tests/map.voyage.spec.ts`** (extend) | `buildChartModel` is byte-identical with and without `roadstead` on `MapPort` — the D33 clock-free property intact. | Make `buildChartModel` read `roadstead`; the equality assertion fails. |
| **`tests/map.sendfleet.spec.ts`** (extend) | `proposeCourse` for a port destination is called with the ROADSTEAD, not `p.lat/p.lon`. | Revert `SendFleet.tsx:165`'s `target`; the recorded argument changes. |
| **`tests/duplication.spec.ts`** (extend) | (i) `snapToNav` has exactly one importer in `src/` and zero under `src/chart/**` and `src/features/**`; (ii) `snapToWater` has exactly one caller in `scripts/`. | (i) import `snapToNav` into `PortsLayer.tsx`; (ii) add a second `snapToWater` call. Both must be WATCHED RED before being trusted. |
| **`tests/sections.spec.ts`** | `RoadsteadsLayer` is not exported from `src/chart/index.ts` and is imported only by `ChartCanvas`. | Add it to `index.ts`; "the chart has one entrance" bites. |
| **`tests/chart.ink.spec.ts`** (extend) | The roadstead circle is measurably distinguishable from the destination ring and the fleet dot (radius, fill, dash). | Set `roadsteadRadius` to `destinationRingRadius`; the separation assertion bites. |

### 8.4 The acceptance drive (a real browser, `docs/WORK_PLAN.md` §3.3)

Open the map on Amsterdam at a zoom where the roads are separated; screenshot the dotted line and the
circle; order a SAIL and watch the track **begin at the circle**, not at the triangle; let her arrive and
confirm she docks at Amsterdam. That fourth step is the owner's sentence, seen. Re-measure
`proposeCourse`'s in-browser cost against the 166 ms budget `src/lib/sea/pathfind.ts:17-21` set, because
the search now starts from a water cell rather than a land one and the A* fan-out changes.

---

## WHY NOT B OR C

| the owner said | A | B | C |
|---|---|---|---|
| "a perpendicular helper line (dotted)" | yes | yes | yes |
| "the shortest point between the land city and nearby shore - sea" | yes | yes | yes |
| "create a point there" | yes | yes | yes |
| "when the ship arrive at that point, consider it as the ship have landed on land" | **yes — the course ends there and `voyage.settle` already docks her** | yes | **NO — the course still ends at the inland city; the point is decoration** |
| the reason the request exists (the snap is silent, the track crosses land) | **fixed** | fixed | **not fixed — the fleet still sails over Panama** |
| cost | −0.17 % median distance; 4 pairs repaired | **+14 % on short routes** | zero |

**C is §7C's forbidden shape**: it draws a picture ABOUT a rule while leaving the rule broken, and every
check downstream stays green. **B is the repricing**, cannot be made exact without a drawn line whose
length is not a measured quantity, breaks `Σ path[].nm = total_nm` which 0075's own self-assert relies on,
and leaves `voyage.position` with no answer for where the ship is during an approach that is not in
`path`.

**BUILD A.**
