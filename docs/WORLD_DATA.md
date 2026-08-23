# World data — provenance280,378 schema, validation

The geographic dataset behind `byeharu-voyage`: 224 real port cities, the seas and regions
that connect them, the goods they traded in roughly 1500–1650, and the country outlines the
map is drawn from.

**The rule this dataset was built under: no coordinate was typed by hand.** Every `lat`/`lon`
in `data/ports.json` was fetched from Wikidata by a script and carries, in the record itself,
the Wikidata item it came from. What a human chose was *which port to include* and *what it
traded* — not where it is.

---

## 1. Files

| File | Bytes | What it is |
|---|---:|---|
| `data/ports.json` | 145,554 | 224 port cities, with coordinates, sea, region, tier, goods and a note |
| `data/seas.json` | 5,263 | 51 named seas and oceans, each with a label anchor |
| `data/regions.json` | 5,540 | 25 trading regions, each tied to a parent sea |
| `data/goods.json` | 16,891 | 70 tradeable commodities with category, value band and origin note |
| `data/world-110m.json` | 280,378 | Country outlines for the map (Natural Earth 1:110m, property bag slimmed) |
| `data/sea-routes.json` | 195,000 | **782 sea legs** — which ports are joined by water, and how far it is by sea. GENERATED; see §7 |

Build and check scripts live in `scripts/`. None of them are needed at runtime.

| Script | Network? | Purpose |
|---|---|---|
| `scripts/roster/*.mjs` | — | The editorial roster: which ports exist, and everything about them except position |
| `scripts/fetch-coords.mjs` | yes | Resolves every roster entry to a Wikidata item and pulls P625 + P17 |
| `scripts/build-world.mjs` | yes | Downloads Natural Earth, vendors `world-110m.json`, generates the country bbox table |
| `scripts/normalise-goods.mjs` | — | Folds the roster's free-hand goods terms onto the 70 canonical ids |
| `scripts/build-ports.mjs` | — | Composes `data/ports.json` from roster + coordinate cache |
| `scripts/check-ports.mjs` | **no** | The validator. Offline, self-contained, exits non-zero on failure |
| `scripts/check-coastal.mjs` | yes | Audits how far each port is from a coastline |
| `scripts/project.mjs` | — | Reference implementation of the recommended projection |
| `scripts/sea-grid.mjs` | **no** | THE routing rule: the sea as a 0.25° raster, and A* through water. §7 |
| `scripts/build-sea-routes.mjs` | **no** | Applies that rule to all 224 ports and writes `data/sea-routes.json` |
| `scripts/build-world-seed.mjs` | **no** | Writes migration 0003 from all of the above. The chain's world IS this data |

Regenerate everything with:

```
node scripts/fetch-coords.mjs      # refresh coordinates from Wikidata
node scripts/build-world.mjs       # refresh country outlines and bbox table
node scripts/build-ports.mjs       # compose data/ports.json
node scripts/check-ports.mjs       # validate
node scripts/build-sea-routes.mjs  # recompute the sea legs (about 10 minutes)
node scripts/build-world-seed.mjs  # rewrite migration 0003 from the data
npm run db:apply                   # and prove the result applies
```

---

## 2. Sources and licences

### Coordinates — Wikidata

- **Source:** <https://www.wikidata.org/> via the `wbgetentities` action of the MediaWiki API
  at `https://www.wikidata.org/w/api.php`.
- **Properties used:** `P625` (coordinate location) for latitude and longitude; `P17`
  (country) resolved through `P297` (ISO 3166-1 alpha-2) as an independent cross-check on the
  country each port was assigned to.
- **Licence:** Wikidata content is released under the **Creative Commons CC0 1.0 Universal
  public domain dedication**. <https://www.wikidata.org/wiki/Wikidata:Licensing>
- **Fetched:** see the `coordinateSource.fetchedAt` field at the top of `data/ports.json`.
- **Coverage:** 224 of 224 roster entries resolved to an item carrying a `P625` coordinate.
  Every port record stores the exact item in `source.wikidata` (for example
  `"source": { "wikidata": "Q597", "enwiki": "Lisbon" }`), so any single coordinate can be
  re-checked at `https://www.wikidata.org/wiki/Q597`.

The resolver refuses to guess. Where an English Wikipedia title turned out to be a
disambiguation page or lacked a coordinate, the script reported it as a problem rather than
picking something plausible, and the roster entry was pinned to an explicit QID by hand —
`hoi-an` to `Q36160` and `julfar` to `Q2126436` (Ras Al Khaimah, the modern town at the site
of medieval Julfar).

### Country outlines and bounding boxes — Natural Earth

- **Vendored file:** `data/world-110m.json`
- **Downloaded from:**
  `https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson`
  (the official Natural Earth vector repository, maintained by Natural Earth's own author,
  Nathaniel Vaughn Kelso).
- **Source size:** 815,562 bytes, 177 features. **Vendored size:** 280,378 bytes.
- **Licence:** Natural Earth raster and vector map data is **public domain** — "no permission
  needed", per <https://www.naturalearthdata.com/about/terms-of-use/>.
- **Transform applied:** geometry copied through byte-for-byte; the ~90-field Natural Earth
  property bag was reduced to `NAME, NAME_LONG, ISO_A2, ISO_A2_EH, ISO_A3, ISO_A3_EH,
  CONTINENT, REGION_UN, SUBREGION`. That is the entire difference between the vendored file
  and the upstream one, and it is recorded inside the file under `_provenance`.

The country bounding boxes embedded in `scripts/check-ports.mjs` were generated from
**Natural Earth 1:10m** Admin 0 Countries
(`.../geojson/ne_10m_admin_0_countries.geojson`, 13,248,815 bytes), *not* from the 110m file.
The 110m sheet drops small islands and dependencies — the Azores, Madeira, the Canaries,
Okinawa, Rhodes, Jeju, Tsushima, Ceuta, Gibraltar, Macau — which would have made the
plausibility test reject twelve perfectly correct island ports. The 10m file is downloaded by
`scripts/build-world.mjs` to produce the table and is *not* vendored.

One documented adjustment: Natural Earth's default point of view excludes the Crimean
peninsula from Ukraine, which put Feodosia outside the `UA` box. The build script unions in
the bbox from Natural Earth's own Ukrainian point-of-view file
(`.../geojson/ne_10m_admin_0_countries_ukr.geojson`). The number comes from that file; it was
not hand-typed.

### Coastline audit — Natural Earth

`scripts/check-coastal.mjs` uses
`https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_coastline.geojson`
(4,133 lines, 410,957 vertices; public domain). Not vendored.

### Everything else

The names, historical names, tiers, sea and region assignments, goods lists and one-sentence
notes are **editorial** — written for this project, drawing on general historical knowledge of
the period. They are not transcribed from any single source and carry no third-party licence.
Section 6 says plainly which of them are claims of fact and which are game-design choices.

---

## 3. Schema

### `data/ports.json`

```jsonc
{
  "coordinateSource": { "dataset": "Wikidata", "property": "P625 ...", "licence": "CC0 1.0 Universal", "fetchedAt": "..." },
  "count": 224,
  "ports": [
    {
      "id": "lisbon",                  // stable kebab-case slug, unique, the join key everywhere else
      "name": "Lisbon",                // English name
      "localName": "Lisboa",           // endonym, in its own script where that is the living form
      "country": "PT",                 // ISO 3166-1 alpha-2 of the MODERN country
      "countryName": "Portugal",       // Natural Earth NAME_LONG, with a few house-style overrides
      "lat": 38.708042,                // decimal degrees, WGS 84, from Wikidata P625
      "lon": -9.139016,
      "sea": "north-atlantic",         // id from data/seas.json
      "region": "iberia",              // id from data/regions.json
      "tier": 1,                       // 1 major hub | 2 notable | 3 minor
      "historicalNames": ["Lisboa", "Olisipo", "al-Ushbuna"],
      "goods": ["wine", "salt", "olive-oil", "black-pepper", "porcelain"],  // ids from data/goods.json
      "notes": "Seat of the Casa da India; terminus of the Portuguese Carreira da India from 1501.",
      "source": { "wikidata": "Q597", "enwiki": "Lisbon" }   // where the coordinate came from
    }
  ]
}
```

### `data/seas.json`

```jsonc
{ "seas": [ { "id": "north-atlantic", "name": "North Atlantic Ocean",
              "centroid": { "lat": 35.0, "lon": -40.0 } } ] }
```

`centroid` is a **hand-placed label anchor**, not a measured centroid. See section 6.

### `data/regions.json`

```jsonc
{ "regions": [ { "id": "iberia", "name": "Iberia",
                 "parentSea": "north-atlantic",   // id from data/seas.json
                 "blurb": "Portugal and Spain, the twin crowns ..." } ] }
```

### `data/goods.json`

```jsonc
{
  "valueBands": { "1": "bulk cargo ...", "5": "treasure ..." },
  "goods": [
    { "id": "cloves", "name": "Cloves",
      "category": "spice",        // spice | textile | metal | luxury | foodstuff | raw | naval-stores
      "valueBand": 5,             // 1..5, GAME BALANCE, not a historical price
      "baseValue": [700, 1400],   // [min, max] in game currency, GAME BALANCE
      "note": "Grew only on Ternate, Tidore and their neighbouring islets ..." }
  ]
}
```

### `data/world-110m.json`

A standard GeoJSON `FeatureCollection` of 177 country polygons, plus a non-standard
`_provenance` key at the top level recording source URL, licence and the transform applied.

---

## 4. Validator output

`node scripts/check-ports.mjs`, run against the committed data. It reads only the four JSON
files and its own embedded bbox table — no network:

```
byeharu-voyage world data check
==================================================================
ports 224   seas 51   regions 25   goods 70

[ ok ] unique kebab-case ids — 224 distinct
[ ok ] required fields, types, tier range
[ ok ] lat in [-90,90], lon in [-180,180], no (0,0)
[ ok ] no duplicate or near-duplicate coordinates (threshold 0.005°)
[ ok ] every sea, region, parentSea and good id resolves
[ ok ] every port inside its country bbox (tolerance 0.05°); worst margin 0.0000°
       note: RU, US span the antimeridian, so their longitude test is weak
[ ok ] vocabulary coverage — 51/51 seas, 25/25 regions, 70/70 goods in use
[ ok ] goods band — tier 1 offers 9, tier 2 offers 6, tier 3 offers 4 (min 4, max 9)
[ ok ] every region has ports — tier 1: 35, tier 2: 79, tier 3: 110
       countries represented: 93

RESULT: PASS — 224 ports, 51 seas, 25 regions, 70 goods, 0 failures, 0 warnings.
```

Exit code `0`.

Note the sixth line: **the worst bounding-box margin is 0.0000°**. Every one of the 224 ports
falls strictly inside its stated country's Natural Earth 10m outline; the 0.05° tolerance was
never needed. The `RU` and `US` boxes span the antimeridian (Russia's Chukotka and the
Aleutians cross ±180°), so for those two countries the longitude half of the test proves
nothing; their latitude test is still meaningful.

### Coastal audit

`node scripts/check-coastal.mjs` measures each port against the Natural Earth 1:10m coastline.
Because it measures to the nearest coastline *vertex* rather than the nearest point on the
line, every figure below is an over-estimate:

```
median distance 2.0 km; 215 of 224 ports within 25 km of a coastline vertex.

     83.1 km  hanoi (VN)       — Red River, Thang Long
     83.1 km  ayutthaya (TH)   — Chao Phraya
     72.2 km  hooghly (IN)     — the Hugli
     53.8 km  seville (ES)     — the Guadalquivir
     46.9 km  basra (IQ)       — the Shatt al-Arab
     36.0 km  london (GB)      — the Thames
     29.7 km  hoorn (NL)       — the Zuiderzee
     25.2 km  kaliningrad (RU) — the Pregel and the Vistula Lagoon
     25.0 km  rotterdam (NL)   — the Maas
```

All nine are navigable-river or lagoon ports, and each says so in its own `notes` field.
**No landlocked city is in the dataset.**

---

## 5. Map projection

### The choice

**Recommendation: cropped equirectangular (plate carrée).** Reference implementation and
round-trip test in `scripts/project.mjs`.

The three candidates, measured. This is the vertical stretch each projection applies at a
given latitude, relative to the equator, printed by `node scripts/project.mjs`:

```
  lat   equirect   miller   mercator
    0     1.00     1.00      1.00
   30     1.00     1.09      1.15
   45     1.00     1.24      1.41
   60     1.00     1.49      2.00
   70     1.00     1.79      2.92
   78     1.00     2.16      4.81
```

- **Web Mercator** is out. It is the right projection for a zoomable slippy map and the wrong
  one here: at Longyearbyen (78.2°N, the northernmost port in the set) it stretches the map
  nearly **five times**, and it cannot draw beyond ±85.05° at all. A game whose Arctic ports
  are a deliberate part of the world should not render Svalbard five times too tall.
- **Miller cylindrical** is the reasonable middle. It keeps mid-latitude Europe looking like
  the atlas people grew up with, at the cost of a logarithmic `y` axis.
- **Equirectangular wins on the properties that matter for *this* game.** The map is a
  read-only view showing fleets moving along their routes. That means the projection is asked
  to do one thing over and over: turn a lat/lon that changes smoothly into a screen position
  that changes smoothly, thousands of times a second, and back again for hit-testing. With a
  linear `y`, a fleet sailing due north at a constant speed moves down the screen at a
  constant speed; latitude is directly readable off the vertical axis; and the inverse is one
  subtraction and one divide, with no logarithms. The round-trip is exact to floating-point
  precision — measured at **5.68e-14 degrees worst case across all 224 ports**.

The cost is real and worth naming: at 60–78°N the far north looks laterally squashed compared
with a familiar atlas. Given that only ten of the 224 ports sit above 60°N, that is the
right trade. If a later art pass decides atlas familiarity matters more, Miller is a two-line change
— both formulas are below, and `scripts/project.mjs` implements both.

### The formula

With a view defined as `lonMin, lonMax, latMin, latMax` and an SVG canvas of `width × height`:

```
x = (lon - lonMin) / (lonMax - lonMin) * width
y = (latMax - lat) / (latMax - latMin) * height
```

and the inverse:

```
lon = x / width  * (lonMax - lonMin) + lonMin
lat = latMax - y / height * (latMax - latMin)
```

**Recommended view for this dataset:**

```
lonMin = -180   lonMax = 180
latMin =  -58   latMax =  82
```

which gives an aspect ratio of `360 : 140 = 2.571 : 1` — so, for example, an SVG
`viewBox="0 0 3600 1400"`. The crop is set by the data plus headroom for the sea room fleets
need around it: the extreme ports are Buenos Aires at 34.60°S and Longyearbyen at 78.22°N,
Honolulu at 157.86°W and Sydney at 151.21°E. `scripts/project.mjs` asserts that no port falls
outside the crop.

Worked example, Lisbon at (38.708042, −9.139016) on a 3600 × 1400 canvas:

```
x = (-9.139016 - (-180)) / 360 * 3600 = 1708.6
y = (82 - 38.708042)     / 140  * 1400 =  432.9
```

### If you switch to Miller later

```
yMiller(lat) = 1.25 * ln( tan( PI/4 + 0.4 * lat * PI/180 ) )
lat(yMiller) = ( 2.5 * ( atan( e^(0.8 * yMiller) ) - PI/4 ) ) * 180/PI
```

`x` is unchanged. Normalise `y` between `yMiller(latMax)` and `yMiller(latMin)` in place of
the linear term. Note that Miller's aspect ratio is not 360:140 — it must be recomputed from
those two bounds.

---

## 6. What is NOT verified

Read this section before treating any of the following as fact.

**Sea centroids in `data/seas.json` are hand-placed label anchors, not measured.** They were
chosen so a sea's name lands in open water on the map. They are not IHO-defined centroids and
are not sourced from anywhere. They are safe to use for placing a label and unsafe to use for
anything geographic.

**`valueBand` and `baseValue` in `data/goods.json` are game-balance numbers, not historical
prices.** No price series was consulted. The *relative* ordering reflects the well-attested
fact that cloves, nutmeg, cochineal and silver commanded far more per pound than grain, salt
or timber — but the numbers themselves are invented for gameplay and should not be cited as
economic history.

**`sea` and `region` assignments are editorial classification.** Where a port sits at the
boundary of two named waters, one was picked. Cebu is filed under the Visayan Sea though the
city faces the Bohol Strait; Tangier is filed under the Mediterranean though it sits at the
Atlantic end of the strait; Kupang is filed under the Timor Sea though Kupang Bay opens onto
the Savu Sea. The 25 regions are a game-design grouping invented for this project, not an
official geographic taxonomy.

**`tier` is a game-design judgement**, not a measured ranking of historical trade volume.

**The goods a port is tagged with are historically plausible associations, not an inventory.**
They say "this place was known for these things in roughly this period" — they are not
transcribed from a customs ledger, and no port's list is exhaustive.

**The 70 goods are a deliberately consolidated vocabulary.** Real distinct commodities were
folded together to keep the list inside a workable size, and the fold is lossy. `diamonds`
covers Golconda diamonds, Pegu rubies, New Granada emeralds and Gujarati carnelian.
`sandalwood` covers Timor sandalwood, Borneo camphor, Sumatran benzoin and Cochinchinese
aloeswood. `wine` covers brandy, gin, rum and sake. `alum` covers Baltic potash. The full
mapping from the roster's original free-hand terms to the canonical 70 is in
`scripts/normalise-goods.mjs` and is the authoritative record of what was merged into what.

**Enslaved people are deliberately excluded from the goods list.** The Atlantic slave trade
was the largest single item of commerce on several of the coasts represented here, and several
of the ports in this dataset — Elmina, Ouidah, Gorée, Luanda, Cidade Velha, Bridgetown,
Cartagena — were central to it. That is a fact of the period; it is not being made a tradeable
commodity in a game. Where a port's history is inseparable from it, the `notes` field says what
the place was without turning it into a mechanic.

**Country assignment follows the modern ISO 3166-1 alpha-2 code, which sometimes disagrees
with Wikidata's `P17`.** The resolver cross-checks all 224 on every run and currently reports **nine** disagreements.
Each was decided deliberately:

| Port | This dataset | Wikidata `P17` | Why |
|---|---|---|---|
| `gibraltar` | `GI` | GB (United Kingdom) | `GI` is Gibraltar's own ISO 3166-1 code; `P17` names the sovereign state |
| `macau` | `MO` | CN | `MO` is Macau's own ISO code |
| `hong-kong` | `HK` | CN | `HK` is Hong Kong's own ISO code |
| `hagatna` | `GU` | US | `GU` is Guam's own ISO code |
| `san-juan` | `PR` | US | `PR` is Puerto Rico's own ISO code |
| `kingston-upon-hull` | `GB` | *(Kingdom of England — no ISO code)* | Wikidata's `P17` here is a historical statement |
| `tripoli-ly` | `LY` | *(Italian Tripolitania — no ISO code)* | as above |
| `suakin` | `SD` | *(Anglo-Egyptian Sudan — no ISO code)* | as above |
| `famagusta` | `CY` | *(Northern Cyprus — no ISO code)* | `CY` is the internationally recognised state; the city is under Turkish Cypriot administration in fact |

One further case was *resolved* rather than kept as a disagreement: `longyearbyen` was
originally coded `SJ` (Svalbard and Jan Mayen, which has its own ISO code) and was changed to
`NO`, matching both Wikidata and Natural Earth, which folds Svalbard into Norway. It no longer
appears in the cross-check.

A second resolver detail worth recording: Wikidata marks `P297 = NL` on Q55 (Netherlands) as
*deprecated*, because the code formally belongs to the Kingdom of the Netherlands. The
resolver prefers a live statement but falls back to a deprecated one rather than reporting no
code, so the four Dutch ports do not show up as false disagreements.

**Three ports sit outside the 1500–1650 window and say so in their own `notes`.** Honolulu
(no European contact until 1778), Sydney (settled 1788) and Longyearbyen (founded 1906) are
present because the coverage brief asked for Australia, the Pacific and the Arctic, and there
were no European-frequented harbours on those exact sites in the period. Their notes state the
real dates rather than implying otherwise. Several other ports are late within the window
rather than outside it — Cape Town (1652), Port Royal (1655), Gothenburg (1621), Saint-Louis
(1659) — and their notes give the founding year. `port-louis` is the same honest compromise
for Mauritius: the Dutch worked the island's ebony from 1598, inside the window, but the
harbour town itself is French and later, and its note says so.

**Historical names are the common forms, not a philological apparatus.** `historicalNames`
lists the names a European or Asian merchant of the period would have used, plus the classical
name where it is well known. Transliterations follow common English usage; no single
romanisation standard is applied throughout.

**`localName` uses the modern endonym.** For a port whose modern city has a different name
from its 16th-century one — Tokyo for Edo, Mumbai for Bombaim, Kozhikode for Calicut — the
`localName` is the modern form and the period name is in `historicalNames`.

**Nine coordinates describe an island or a site rather than a town centre.** Every port's
Wikidata item was checked for its `P31` type. Five resolve to islands — `hormuz` to Hormuz
Island, `banda-neira` to Neira Island, and, from the 2026-08-23 island additions, `chios`,
`zakynthos` and `tidore` to their islands — one to an archaeological site (`sofala`) and one
to an unincorporated community that is the preserved historic site (`jamestown`). In each case
that *is* the right place for the period, and the islands are small enough that the difference
from the harbour town (Chios town, Zakynthos town, Soasio) is a few kilometres at most. The
remaining two (`banten`, `pattani`) are ordinary settlements under local administrative types. No port resolved to a province, a region or a
same-named place elsewhere: a separate audit compared all 214 (now 224) Wikidata labels against the
roster names and historical names and found one difference, `banda-neira` against the label
"Neira Island", which is the island the town stands on.

**Nothing here has been checked against a gazetteer of historical port locations.** The
coordinates locate the *modern settlement of that name* as Wikidata records it. For a port
whose site has shifted — Panamá Viejo was destroyed in 1671 and the city rebuilt some
kilometres west; Old Goa was abandoned for Panjim; Sofala's harbour has silted — the
coordinate is the modern place, which may be several kilometres from where a ship of 1600
would actually have anchored. For a game map at world scale this is immaterial; for anything
claiming historical precision it is not.


---

## 7. The sea legs — how 782 routes were derived rather than authored

`data/sea-routes.json` is **generated**. Do not hand-edit it: change the rule or the port list and
run `node scripts/build-sea-routes.mjs` again.

### The rule, in one line

> A leg is the shortest path **through water** between two harbours, and its distance is the length
> of that path.

Not the straight line. `scripts/sea-grid.mjs` scan-fills the Natural Earth land polygons into a
**0.25° raster** (1440 × 720 cells, ~715k of them water) and runs **A*** * over the water cells,
then straightens the result by line-of-sight so the route is what a ship would sail rather than a
staircase of grid steps.

### Why the straight line was not good enough

The first version of this generator asked whether the great circle between two ports stayed at sea.
It produced a world in which **Lisbon and Cádiz had no leg at all**, because the straight line
between them clips the Algarve. Ships round Cape St Vincent; so does the game now.

| Pair | Straight line | By sea | Why |
|---|---:|---:|---|
| Lisbon → Cádiz | 188 nm | **248 nm** | Cape St Vincent |
| Quebec → Boston | 268 nm | **1,153 nm** | the straight line is Maine |
| Cape Town → Sofala | 1,198 nm | **1,611 nm** | round the Cape and up the channel |
| Alexandria → Aden | 1,386 nm | **10,944 nm** | **there is no Suez until 1869** |
| Veracruz → Acapulco | 255 nm | **10,860 nm** | **there is no Panama until 1914** |

Nothing in the generator knows about canals, isthmuses or trade routes. Those numbers are what the
water says. The last two are printed as **negative controls on every run**, because a generator
that quietly starts digging Suez is worse than one that fails outright.

### The channels — the only thing authored

A 0.25° cell is about 15 nm. The Øresund is 2 nm wide and the Bosphorus half of one: at this
resolution they are simply land, and refusing them would delete the Baltic grain trade, Istanbul,
the Red Sea and the Gulf from a game about the age of sail. So `CHANNELS` in `scripts/sea-grid.mjs`
lists **fifteen named straits and river approaches** whose cells are forced open before the search
runs — the Danish Straits, the Dardanelles and the Bosphorus, Kerch, Bab-el-Mandeb, Hormuz, the
Shatt al-Arab, Khambhat, the Hooghly, Malacca, Sunda, the Seto Inland Sea, the White Sea, the
St Lawrence, the Gironde and Loire, the Thames and Scheldt, the Elbe and Weser, the Guadalquivir,
the Pearl River, the Yangtze, the Río de la Plata, the Pará, and the Gambia and Senegal mouths.

**That list is the whole of the game's "you may pass here" authority.** There is deliberately no
Suez and no Panama in it.

### How the graph is assembled

1. **The coastal chain** — each port keeps its 6 nearest neighbours *by sea*, so the graph reads as
   a coast you sail down port by port rather than a spiderweb.
2. **Connectivity** — the shortest water link between separated halves is added until the world is
   one piece. Five did it, and every one is a real ocean crossing: Gorée→Elmina, Luanda→Cape Town,
   Banda Neira→Sydney, and Guam→Honolulu→Acapulco — **the Manila galleon, which the generator
   found rather than being told.**
3. **The trade roads** — where the chain forces a detour of more than 2.5× the actual sea distance,
   that leg is opened.

### The result

```
214 ports · 782 legs · ONE connected world · no isolated port
degree           min 1, mean 7.3, max 16
sailed/straight  mean 1.16x
longest leg      3,309 nm (Honolulu — Acapulco)
```

Migration 0003 re-asserts the invariant against the coordinates it stored: **every leg is at least
the great circle between its two ports**, and every port is reachable from Lisbon by walking the
leg table. A leg may detour round land; it may never be a shortcut through the Earth.
