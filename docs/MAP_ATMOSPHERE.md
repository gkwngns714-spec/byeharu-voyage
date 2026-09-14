# MAP — the picture (owner row 90)

**The owner, 2026-09-13:** *"map should be much more graphic... it is too blank."*

Audited 2026-09-13 against `main` at `060e943`, in a local-PGlite build served with `vite preview`
(no `.env.local`), driven with Playwright in one persistent Chrome profile at **390×844** and
**1440×900**, in the night sea and the day sea, at the opening frame and one press of `+` in. Every
count below is what the DOM held when the screenshot was taken, read off the `<svg>` with
`getComputedStyle`; the frame cost is `performance.now()` around twelve wheel-zoom steps with two
animation frames each, at 1440×900, twice.

This document is the audit (§1–§2), the design (§3–§6), and what was measured after (§7). It is
written in the voice of `docs/UI_DIRECTION.md` and under its §4 commitment — **an instrument over a
living sea** — and under the owner's map rules: the chart is the ground, chrome is summoned,
corners not centre, clean, no jargon. Nothing here adds a control, a word of chrome, or anything in
the centre of the glass.

---

## 1. What was on the paper — counted

The opening frame of a new house (one fleet at Lisbon), before:

| | 390×844 opening | 390×844 one zoom in | 1440×900 opening | 1440×900 one zoom in |
|---|---:|---:|---:|---:|
| span across the glass | 14.88° | 9.30° | 14.88° | 9.30° |
| **fills** (anything with a colour inside it) | **3** | 3 | **3** | 3 |
| strokes | 33 | 35 | 18 | 26 |
| port marks | 16 | 16 | 7 | 11 |
| names | 10 | 12 | 7 | 9 |
| roadstead lines | 8 | 9 | 5 | 7 |
| sea names · graticule · rings · ships | 0 · 0 · 0 · 0 | 0 · 0 · 0 · 0 | 0 · 0 · 0 · 0 | 0 · 0 · 0 · 0 |
| SVG elements | 73 | 78 | 43 | 59 |

The three fills were: the sea rectangle, the land body, and the one brass triangle of the port the
fleet lies in. Everything else on the sheet was a hairline — the coast at 0.9 px, sixteen hollow
triangles between 4 and 10 px across, dotted helper lines, and ten names in 10.5 px type.

Frame cost before, 1440×900, per zoom step: **33.6 ms · 33.3 ms**.

Screenshots: `before-390x844-dark-opening.png`, `before-1440x900-dark-opening.png`,
`before-390x844-light-opening.png`, `before-1440x900-light-zoom.png` (paths in the PR).

## 2. Why it was blank

Not by accident — by three rules that were each right on their own day and wrong together:

1. **DESIGN §E.5's austerity.** *"Three glyphs only… Coastlines are a single pale stroke… no
   terrain, no bathymetry, no borders, no relief."* Written for twelve invented Iberian harbours on
   a phone, when the danger was clutter. The world is 214 harbours now and the danger is the
   opposite: at 1440×900 the frame is one grey shape on one dark rectangle and seven small
   triangles, and the owner's word for that is *blank*.
2. **The ink spec's three tokens.** `tests/chart.ink.spec.ts` pins the land at 1.9–2.6 : 1 on the
   sea and the coast at ≥ 3 : 1 — correct, measured, and load-bearing. But a chart whose only
   three colours are pinned has nowhere to put a fourth thing, so nothing was added.
3. **The density rules did their job too well.** `PORT_TIER_BANDS` draws 35 great ports over the
   globe and names none of them (`LABEL_SPAN_LIMIT` = 70°): the world view was 35 identical
   triangles on a grey shape. The hierarchy the two ramps carry (1.75× in size, 1.72× in weight
   from tier 2 to tier 5) is a difference you can measure and not one you see across a room.

And two things that were not rules but showed: the coast stroked EVERY ring of a **countries**
file, so the Portugal–Spain and France–Spain borders were drawn as coasts; and a fleet at sea was
a dot, which has no heading.

## 3. The design — layers, all from data the chart already holds

The picture is built AROUND the three pinned tokens, never on top of them: `chart-sea`,
`chart-land` and `chart-coast` did not move, and `tests/chart.ink.spec.ts` still measures them on
the running chart. Five tokens were added, in both schemes (`src/index.css`), and
`tests/map.atmosphere.spec.ts` refuses a chart token one scheme has and the other lacks.

| layer | what | where it lives | from |
|---|---|---|---|
| **sea, depth** | the flat ground (`chart-sea`), a radial vignette to `chart-deep` at the frame's edge (0 → 18 % → 62 % alpha), and a graticule every 15° as one hairline path in `chart-grid` | `src/chart/SeaLayer.tsx` (exported to nobody; `ChartCanvas` composes it first) | the viewBox |
| **shallows** | three non-scaling strokes of the coastline UNDER the land — 40, 22, 10 px in `chart-shallow` at 25/35/55 % — the half over land is covered by the body, what survives is paler water hugging every shore | `src/chart/CoastlineLayer.tsx` | the coast `d` |
| **land** | the body, filled, `chart-land`, `evenodd` — as before | `CoastlineLayer.tsx` | the coast `d` |
| **relief** | the coastline stroked 6 px in `chart-relief` at 70 %, INSIDE a `clipPath` of the land — an inner shadow along the coast with no filter | `CoastlineLayer.tsx` | the coast `d` |
| **coast** | the stroke, `chart-coast`, at `coastStrokeWidth(spanX)`: 0.9 px over the globe rising logarithmically to 1.7 px at a harbour approach | `CoastlineLayer.tsx`, `glyphs.ts` | the coast `d` |
| **no borders** | the builder now emits TWO paths from one file: the body (every ring) and the LINE — the outline with the 2,664 segments two rings share left out, simplified run by run so the line sits exactly on the body's edge | `src/chart/coastlineBuild.ts` (`coastD`) | `data/world-110m.json` |
| **sea names** | 51 waters from `data/seas.json`, each set on its hand-placed anchor, centred, in `chart-sea-name`; oceans at 14 px at every zoom, seas at 11.5 px inside 110° of span; 0.14 em of spacing | `src/chart/seaNames.ts` (the decision), `LabelsLayer.tsx` (the paint) | `data/seas.json`, read inside the same lazy chunk as the coast (`backdrop.ts`) |
| **collision** | the sea names are `LabelRequest`s at priority 5 — below the quietest harbour — placed LAST by the ONE planner, `centred`, with no glyph obstacle; a name that would touch a port's name or mark, or run off the glass, is dropped, never moved | `src/chart/labels.ts` (extended: `sizePx`, `spacingEm`, `placement`) | — |
| **port hierarchy** | a thin ring (r 9.5 px, faint ink) round every tier-5 harbour; a great harbour's name set at 12 px against 10.5; a great harbour ASKS for its name at every zoom, the globe included, still below every port of yours | `PortsLayer.tsx`, `labels.ts`, `chartView.ts` (`GREAT_PORT_TIER`) | `ports.size_tier` |
| **ships** | a fleet at sea is a HULL — `shipPath`, one path, 13 px bow to stern, turned to the heading of the served segment she is on (`FleetOnChart.heading`) inside the same sea-coloured halo; the minimap draws the same hull at 0.8×; a docked fleet is still its port's loud mark | `glyphs.ts`, `FleetsLayer.tsx`, `Minimap.tsx`, `chartModel.ts` | `voyage.course[segIndex → segIndex+1]` |
| **course** | the passage made SOLID (`accent/85`, 1.8 px); the water ahead a `5 4` dash (`accent/45`); an open chevron arrowhead at the course's last vertex, turned along its last segment (`TrackPaths.end`, `endHeading`); the destination ring and the roadstead ring and dotted helper line as before | `route.ts`, `FleetsLayer.tsx` | the served course |
| **both schemes** | `chart-deep #03060b` / `#7ea6c9`; `chart-shallow` = `info` 22 % into the sea / paper 30 % into the sea; `chart-relief`; `chart-grid`; `chart-sea-name` | `src/index.css`, `@theme` and `:root[data-theme='light']` | — |

Everything goes through the one projection (`src/lib/geo/projection.ts`). No new fetch: the seas
ride as text inside the chunk that already fetches the coast. Nothing new is in the centre of the
glass; the corners hold exactly what they held; no word of chrome was added.

## 4. What was rejected

* **A blur filter for the shallows or the relief.** `feGaussianBlur` over a 6,000-point path
  re-rasterises it every frame of a pinch. Three strokes and one clipped stroke cost four more
  path draws and no filter, and measured level with the old chart (§7).
* **A second text layer for the sea names.** Two planners disagree about which names fit — the
  defect `labels.ts` exists to end. The seas are requests to the one planner.
* **Sea-name extents.** The data has anchors, not polygons; a name centred on the authored anchor
  is what the file says it is for. If the file ever grows a rank column, `seaNames.ts` is the one
  place to read it instead of the name's word "Ocean".
* **Dissolving the countries into continents.** A polygon union is a library or a day; dropping
  the shared segments from the STROKE is forty lines, exact (the file shares vertices exactly), and
  it is only the line that ever showed the border.
* **Any new mark that needs a legend.** No wind, no hazard, no compass rose. The picture is the
  world's own furniture — depth, shore, relief, grid, the names of the waters — and the game's
  own three glyphs, made legible.

## 5. What did not change, and is still binding

* The chart is the ground and nothing sits in the centre; the corners hold the same three things.
* The three pinned tokens and their contrasts: the ink spec's assertions are unchanged, only the
  element the coast STROKE is measured on moved (`map-coast`), because the stroke and the body are
  two elements now.
* The hit test, the reach, the roadstead rule and its `1 5` dot, the tracks' geometry (the served
  polyline, split at the served position), `visiblePorts`, the tier bands, the keep-out rule.
* No screen prints a new word; the sea names are the data's own.

## 6. The one exception to §4.1, stated

`docs/UI_DIRECTION.md` §4.1 says no letter-spacing and no uppercase. The seas' names are set with
**0.14 em of spacing** — a cartographic convention for water, not UI copy: a spaced name reads as a
region, an unspaced one as a place. It is the only spaced type in the game, it is on the chart only,
and it is quieter than every port's name (`chart-sea-name` is the faint ink thinned into the sea).
No uppercase.

## 7. What was on the paper after — counted the same way

| | 390×844 opening | 390×844 one zoom in | 1440×900 opening | 1440×900 one zoom in |
|---|---:|---:|---:|---:|
| **fills** | **4** | 4 | **4** | 4 |
| strokes | 41 | 43 | 26 | 33 |
| port marks | 16 | 16 | 7 | 11 |
| rings on great harbours | 3 | 3 | 3 | 3 |
| names | 10 | 12 | 7 | 9 |
| sea names | 1 (Bay of Biscay) | 0 | 0 | 0 |
| graticule | 1 path | 1 | 1 | 0 |
| roadstead lines | 8 | 9 | 5 | 7 |
| SVG elements | 96 | 100 | 65 | 80 |

The count of FILLS is the honest measure of "blank" and it is nearly the same number — the
picture is made of strokes and gradients on the same three bodies, which is the point: the land
did not become terrain and the marks are still the subject. With a fleet at sea (driven on the
canary world, Lisbon → Amsterdam): 1 hull, 3 track paths (solid made, dashed ahead, arrowhead),
and at the phone's frame of that voyage 2 sea names and 10 rings.

Frame cost after, 1440×900, per zoom step, two runs: **41.0 ms · 44.3 ms**, then **31.1 ms ·
33.3 ms** on the rebuilt bundle with the border pass — against 33.6 · 33.3 before. Inside the
noise of one machine; not doubled, so nothing was simplified away.

`buildCoastline` over the real file: 36.6 ms once per open (8.3 ms before the border pass);
body 286 rings / 6,111 points / 78.9 KB; line 3,251 points in 271 runs / 42.8 KB.

Screenshots: `after-390x844-{dark,light}-{opening,zoom}.png`, `after-1440x900-{dark,light}-{opening,zoom}.png`,
`after-ship-1440x900-dark.png`, `after-ship-1440x900-dark-zoom.png`, `after-ship-390x844-{dark,light}.png`.

## 8. Proofs

* `tests/map.atmosphere.spec.ts` — pure: the seas are read not invented; an ocean at every zoom, a
  sea inside the limit; at both opening frames no sea name touches a port's name or mark and no
  place is dropped for a sea; a sea name is dropped not moved; the land is filled and the coast
  stroked in tokens; the border pass drops the shared edge and keeps every ring; the coast weight
  rises with zoom; the ring is the top tier; one hull for every surface; heading arithmetic;
  every `--color-chart-*` in both schemes and every one of them drawn; `SeaLayer` is furniture.
* `tests/chart.ink.spec.ts` — unchanged assertions; the stroke measured on `map-coast`.
* `tests/map.labels.spec.ts` — one pin moved deliberately: a great harbour asks at every zoom.
* `tests/map.roadsteads.spec.ts`, `tests/map.coastline.spec.ts`, `tests/map.voyage.spec.ts`,
  `tests/map.sendfleet.spec.ts`, `tests/waters.panel.spec.ts`, `tests/layout.spec.ts` — green,
  untouched.

---

## 9. The regions layer, the landfall, and every harbour (rows 91–93, 2026-09-14)

Three instructions in one day, all about the same sheet, all measured before they were built.
The full measurements are in `docs/DEV_LOG.md` (2026-09-14); this section is what the picture
gained and the rules it kept.

### 9.1 The landfall (row 91: *"some cities are in the ocean"*)

79 of the 224 harbours stood in the water the chart DRAWS — the 110m countries decimated at
0.2° — because a city's coordinate is true and the 110m polygon is coarse. Now a harbour's mark
is set on the drawn shore: `src/chart/landfall.ts` (pure), applied ONCE in `useBackdrop` the
frame the coast arrives, so the mark, the name, the tap target, the roadstead's dotted line and a
docked fleet's hull all read one moved coordinate off `MapPort`. The cap is 10 nm, chosen in the
gap the measurement found (widest coarseness move 8.6 nm; nearest island-with-no-polygon 14.3 nm).
The 28 harbours beyond it are islands the file has no polygon for; each wears an **islet** — a
speck of land, `GLYPH.isletRadius` (4 px) in `chart-land` with the coast's stroke, painted by
`CoastlineLayer` after the coast and under every port. `ports.lat/lon` on the server is untouched.

### 9.2 Every harbour, at every zoom (row 93)

The tier bands are unchanged and mean something new: they are the ladder a DOT climbs to become
the marker. `portMarks` (`chartModel.ts`) puts every port on the glass on the sheet, FULL (the
triangle or lozenge, its ring if great, its roads, its name) when its tier clears the band or it
is yours, else a DOT — `GLYPH.portDotRadius` (1.6 px), quiet ink, nameless, roadless, and NOT a
tap target: measured, a tappable dot 5 px north of Cádiz stole the tap on the word *Cadiz*
(`tests/map.sendfleet.spec.ts`), so the hit test reads the full half; zoom in and the dot is the
marker, tap and all.
`visiblePorts` is the full half and keeps its pins. The countries were never culled: the body is
every kept ring of the file at every zoom, and the spec now pins that (175 coded countries, all
in the one body path).

### 9.3 The regions (row 92) — a layer that is OFF by default, and off is §7's sheet exactly

| layer | what | where it lives | from |
|---|---|---|---|
| **water tint** | one path per region of axis-aligned 0.25° cell rectangles, `crispEdges`, in the region's token at `WATER_TINT_ALPHA` (0.32), painted FIRST under the shallows | `CoastlineLayer.tsx` step 0 | `data/region-tint.json` (derived) |
| **land tint** | one path per region of the BODY'S OWN rings for the countries it holds, `evenodd`, in the same token at `LAND_TINT_ALPHA` (0.42), inside the body clip, after the body and under the relief and the coast | `CoastlineLayer.tsx` step 2b | `CoastlineData.countries` (the same rings as `d`, grouped by `ISO_A2_EH`) |
| **region names** | 25 `LabelRequest`s at `LABEL_PRIORITY.region` (7 — above the seas' 5, below the quietest harbour's 11), centred on the mean of the region's harbours, 13 px, spaced like water, in `chart-sea-name` | `regions.ts` (the decision), `LabelsLayer.tsx` (the paint, in the ground group) | `data/region-tint.json` |
| **the filter** | a fourth button under +/−/find: the `regions` globe glyph and the one word *Regions*, `aria-pressed`, accent border and ink when on; one `useSyncExternalStore` store in `regionsFilter.ts`, key `byeharu-voyage.map.regions.v1`, read and written in try/catch | `ViewControls.tsx` | — |
| **the 25 tokens** | `--color-chart-region-<id>`, both schemes, `oklch` at one chroma and two lightness steps; classes written out in `REGION_FILL` so the JIT sees them | `src/index.css`, `regions.ts` | measured (below) |

**What the water is.** Every navigable cell of the game's own raster (`public.sea_cells` —
0040, patched by 0052 and 0079), replayed from the chain's bytes by `scripts/build-region-tint.mjs`
and never re-rasterised, takes the region of the harbour it is nearest to BY WATER (a
multi-source breadth-first search through the water cells, the method 0040 itself attaches
unnamed water to a sea with). 6,015 rectangles, 647,194 of 647,208 cells tinted (the 14 are pools
no harbour reaches). *"Each sea takes its harbours' majority region"* was measured first and
rejected: on the North Atlantic it is a three-way tie (6 · 6 · 6) decided by file order, and it
paints the whole Mediterranean one region with four regions' harbours on its shore.
`tests/map.regions.spec.ts` rebuilds the file from the chain and demands the committed copy is
byte-identical.

**What the land is.** A country is tinted by the region most of its harbours belong to; a
country with none is not tinted. Twelve are split (Spain 7·2·1·1, France 6·2, Greece 4·3, India
10·4, Italy 6·2, Indonesia 9·1, Portugal 3·3, Egypt 1·1, Mexico 1·1, Panama 1·1, Russia 1·1, the
US 4·1) and take their majority — v1, and the Atlantic Isles therefore hold no drawn land (their
islands are Portugal's and Spain's, and Cape Verde has no 110m polygon).

**The palette, measured not eyeballed.** The 45 pairs of regions that touch on the water were
graph-coloured over eight hues × two lightness steps so no touching pair shares a class, then
every touching pair was run through the dataviz palette validator (OKLab ΔE under simulated
protanopia and deuteranopia): worst touching pair **ΔE 9.0 CVD · 15.7 normal at night, 8.1 · 16.0
by day**, both above the 8 / 15 floors. Within a class the members drift ±7° so all 25 stay
distinct, and every region is NAMED on its tint, so colour is never the only channel. The
validator's lightness band (0.48–0.67 dark) is exceeded by the L 0.80 step on purpose: the tint is
painted at a third strength over a dark sea, and a mark-band lightness would vanish into it.

### 9.4 What did not change

The three pinned inks and their contrasts (`tests/chart.ink.spec.ts` measures the same
elements); the five inks of row 90; the sea names and their rule; the hit test's nearest-wins;
the roadstead rule (the line now starts at the landfall-moved quay, which is where the mark is);
the minimap (no tint, no dots — a 144 px locator); nothing in the centre of the glass, no new word
but *Regions*, which the owner asked for by name.

### 9.5 Proofs

* `tests/map.landfall.spec.ts` — the table over the real file (79 · 51 · 28, cap in the gap);
  `landfallPorts` keeps identity, never moves a sea place or a roadstead; in the browser at both
  glasses, at the opening frame and the world view, every harbour mark is inside the land body
  (`isPointInFill`, the body's own `evenodd`) or on an islet. Red on `main` (79 in water).
* `tests/map.regions.spec.ts` — the derived file is the build; 25 regions, 25 tokens in both
  schemes, 25 classes; names through the one planner; the filter's reader; in the browser at both
  glasses and both schemes: off by default and the sheet as it was, on tints and names with the
  pinned inks unchanged, off again identical, kept across a reload; frame cost printed.
* `tests/map.marks.spec.ts` — `portMarks` and `visiblePorts` (35 · 114 · all), a port of yours
  full at every zoom, the countries all in the body; in the browser: 224 harbour marks at the
  world view (35 full, 189 dots), a dot zoomed in wears its marker; frame cost at the world view
  printed.
