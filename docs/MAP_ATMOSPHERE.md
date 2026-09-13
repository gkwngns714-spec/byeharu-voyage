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
