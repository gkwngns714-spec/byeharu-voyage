# 2026-10-31 — the organic wall, and a busier town

Owner: *"the city is better than before, i want something like this. west edge is good, but the rest
edge is too rigid. maybe have something like a different shape / form. and more people if possible.
good"* (2026-10-31).

## What was asked

1. Keep the west edge exactly — the sea, harbour front, breakwater, piers, hulls, cranes.
2. Break the rigid rectangle on the other three sides into an organic form: a curved, segmented
   wall with angled bastions and bulges, the land edge folding in and out, a river mouth on one
   edge, the margin following the wall; blocks fill the irregular shape; nothing cropped.
3. More people: roughly double the crowd, keep the building-scale rule and the stipple, make the
   market and the quay visibly busy.

## The drawing

- The west edge is untouched: `coastX`, the sea hairlines, the harbour front's gates, and the whole
  port group (breakwater, lighthouse, piers, hulls, cranes, crates, quay lamps) are the same code.
- `CityScene.tsx` now builds the three landward sides as one wall of cubic segments — `WALL_N`,
  `WALL_E`, `WALL_S` — with bulges and folds (the east side swings between x ≈ 206 and 223, the
  north between y ≈ 16 and 31, the south between y ≈ 202 and 223). One bastion sits at every
  segment joint, rotated with the wall's tangent; road and lane gates get their own bastions; the
  harbour front's four towers stay axis-aligned exactly as before.
- The land is the wall path plus the coast; the dark margin outside is simply the plate's ground,
  so it follows the wall's shape.
- A river mouth crosses the south wall between the bottom blocks and opens into a small basin; the
  wall's own stroke over it is the water gate. The river is the plate's water colour painted over
  the land, with two bank lines.
- Blocks: the north row's top is computed per block from the north wall's most inward point
  (`yNorthMax`), the east row's right edge from the east wall's most inward point (`xEastMin`) —
  the thin rampart blocks — and the bottom row is fitted around the river. The town thus fills the
  irregular shape and steps with it.
- The wall is drawn as a low, wide (4.4) rampart band under the 2.2 line, so it reads as a real
  fortification at 200 px.
- Crowd: 70 at the market, 54 on the quay, 24 at the hall plaza, 100 along the streets, 28 in the
  outskirts, 24 strolling — 297 clustered (a few outskirts points are rejected where the wall folds
  in) plus the served tier's 36 walkers = 333, against 168 before. The stipple stays ~2,200 and is
  tested against the drawn land (point-in-polygon on the wall plus coast) and the river, so no
  speck is ever in the margin.

## Measured (headless chromium, local build, port 4205)

| glass | panel | whole plate | summary | page |
|---|---|---|---|---|
| 390×844 | 200×200 | corners exact | 437 | no scroll |
| 320×568 | 161×155 | corners 19,58 … 174,213 | 206 | no scroll |
| 1280×900 | 699×519 | corners 106,58 … 625,577 | 174 | no scroll |
| 1440×900 | 788×519 | corners 151,58 … 670,577 | 174 | no scroll |

Counts on the measured build: crowd 297, walkers 36, teeming 2,198, lights 292. The whole-city
proof maps the viewBox's four corners through the svg's own screen CTM; all land on the svg's
rectangle at every size (the meet contract from the previous slice holds).

## Gates

- `npx tsc -b`, `npx eslint src/features/city`, `npm run build` — clean.
- `tests/duplication.spec.ts` — 11/11.
- `tests/city.page.spec.ts` — PASS (42.6 s): no page scroll at 390/320/360/1280/1440; the
  whole-city and figures-card assertions green at the two wide sizes; the scene-in-frame,
  population, tile-face and walker proofs green.

## Screenshots (DPR 2, test-results/, gitignored)

`shape-panel-390x844`, `shape-panel-320x568`, `shape-panel-1280x900`, `shape-panel-1440x900`,
`shape-full-390x844`, `shape-full-1280x900`. Judged from above: the west edge unchanged; the north,
east and south walls read as one curved, bastioned rampart with a river inlet; the blocks step to
the wall and the town fills the shape; the market and quay are visibly busy; nothing is cut by the
plate or the panel.
