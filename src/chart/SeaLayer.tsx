import { memo, useId } from 'react'
import type { ViewBox } from '../lib/geo'
import { GLYPH } from './glyphs'

// THE WATER — the ground everything else is measured against, with depth, the day's water where
// the Sun is up, and a graticule.
//
// ── §7B ────────────────────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: THE SEA AS A SURFACE — the flat ground `tests/chart.ink.spec.ts`
//              measures every other ink against, the vignette that makes open water read deeper
//              than the coast, the DAY SEA painted over it through the Sun's mask (2026-10-14),
//              and the hairline grid a chart is drawn on.
// WHERE        src/chart, painted first by `ChartCanvas` and by nothing else (a layer, exported
//              to nobody — tests/map.atmosphere.spec.ts holds that the way sections.spec.ts holds
//              it for the roadsteads).
// SECOND CALLER  none: the minimap paints its own flat sea because a 144 px locator has no room
//              for depth, and that is a decision, not an omission.
// WRONG SHAPE  the sea painted by the SCREEN under the chart (`.bv-sea`), which is what made the
//              coast's contrast a range instead of a number (ChartCanvas.tsx's header).
//
// ── THE GROUND STAYS FLAT, AND THAT IS LOAD-BEARING ────────────────────────────────────────────
// `[data-testid="map-sea"]` is ONE rect in ONE token, and every contrast the ink spec pins is
// measured against its computed fill. The depth is a SECOND rect over it — a radial gradient from
// nothing at the centre to `chart-deep` at the edges, at low alpha — so the pinned ground is still
// the ground the eye meets across most of the frame, and the vignette is a tone the frame's edge
// carries, not a colour the coast is measured on. `objectBoundingBox` units, so it is the SAME
// picture at every zoom and pan: the deep water is always at the edge of the glass, which is
// where the eye reads "away".
//
// ── THE DAY SEA (2026-10-14, owner: "sunlight based on real science… colors similar to daytime
//    earth") ──────────────────────────────────────────────────────────────────────────────────
// Over the night ground, a THIRD rect in `chart-day-sea` with its own deep vignette, painted
// through the Sun's raster (`DaylightSheet`, an HTML sheet of its own between the ground and the
// grid — ChartCanvas stacks the three) — so it is the water by day where the Sun is up,
// nothing where it is down, and the twilight between. The night tokens did not move, and the ink
// spec still measures them: it measures at night, which is now a fact about the clock (the spec
// pins it with Playwright's clock, not by hoping). The graticule is painted AFTER the day sea, so
// the grid is on the water by day as by night.
//
// ── THE GRATICULE ──────────────────────────────────────────────────────────────────────────────
// One hairline per `GLYPH.graticuleStepDeg` of latitude and longitude, only the ones inside the
// box, as ONE path — at the globe that is 36 lines in one element, at a harbour approach none.
// Non-scaling, so the grid is a hairline at every zoom, and quieter than the coast (its token is
// an alpha of the faint ink). It is furniture: it says "this is a chart", and nothing about the
// game. The old glyphs.ts header banned a grid; row 90 measured that austerity out. A box past
// ±180° (the continuous chart) draws its meridians at 195°, 210°… exactly as at 15°: there is no
// seam line, because there is no seam.

// ── THE SEA DOES NOT MOVE (2026-10-18, owner: "when i move map, it blinks too much") ───────────
// Both seas are the SAME PICTURE at every pan and zoom — a flat ground and a vignette keyed to the
// glass — so they are drawn in the GLASS's own unit square (`SEA_VIEWBOX`, stretched to the glass by
// `preserveAspectRatio="none"`), not in chart units. Keyed to the view's box, each re-rasterised a
// whole glass of identical pixels on every frame of a drag — the night one with the page itself,
// the day one on its layer under the Sun's mask — which is part of what ran the GPU out of tile
// memory (ChartCanvas's CoastSheet says what that looked like). The ellipse is unchanged: the
// gradient was already in the rect's bounding box, and the rect is still the whole glass. The svg
// whose viewBox IS the view is now the marks' (`map-view`), not the sea's.

/** The viewBox of a sea's svg: the glass as a unit square, with `preserveAspectRatio="none"`. */
export const SEA_VIEWBOX = '0 0 1 1'

/** THE GROUND AND ITS DEPTH — the night sea. */
export const SeaLayer = memo(function SeaLayer() {
  const gradientId = useId()
  return (
    <g pointerEvents="none">
      <defs>
        <radialGradient id={gradientId} cx="50%" cy="50%" r="72%">
          <stop offset="0%" style={{ stopColor: 'var(--color-chart-deep)', stopOpacity: 0 }} />
          <stop offset="60%" style={{ stopColor: 'var(--color-chart-deep)', stopOpacity: 0.18 }} />
          <stop offset="100%" style={{ stopColor: 'var(--color-chart-deep)', stopOpacity: 0.62 }} />
        </radialGradient>
      </defs>
      {/* THE GROUND — the whole glass, so there is never an unpainted edge mid-pan. Flat, in the
          pinned token. */}
      <rect x={0} y={0} width={1} height={1} className="fill-chart-sea" data-testid="map-sea" />
      {/* THE DEPTH — open water darkens toward the frame's edge. */}
      <rect x={0} y={0} width={1} height={1} fill={`url(#${gradientId})`} data-testid="map-sea-depth" />
    </g>
  )
})

/** THE DAY SEA — the water by day, with its own deep vignette. Painted whole: ChartCanvas lays it
 *  in a `DaylightSheet`, which is what shows it only where the Sun is up. */
export const DaySeaLayer = memo(function DaySeaLayer() {
  const dayGradientId = useId()
  return (
    <g pointerEvents="none" data-testid="map-sea-day">
      <defs>
        {/* The day's depth: open ocean goes deeper toward the frame's edge, as the night's does. */}
        <radialGradient id={dayGradientId} cx="50%" cy="50%" r="72%">
          <stop offset="0%" style={{ stopColor: 'var(--color-chart-day-deep)', stopOpacity: 0 }} />
          <stop offset="60%" style={{ stopColor: 'var(--color-chart-day-deep)', stopOpacity: 0.25 }} />
          <stop offset="100%" style={{ stopColor: 'var(--color-chart-day-deep)', stopOpacity: 0.7 }} />
        </radialGradient>
      </defs>
      <rect x={0} y={0} width={1} height={1} className="fill-chart-day-sea" />
      <rect x={0} y={0} width={1} height={1} fill={`url(#${dayGradientId})`} />
    </g>
  )
})

/** THE GRATICULE — one path, hairline, quieter than the coast; over the day sea, under the coast.
 *  A pure function of the box it is drawn over — the coast's PAPER (ChartCanvas's CoastSheet), so a
 *  pan moves it with the coast instead of redrawing it. */
export const GraticuleLayer = memo(function GraticuleLayer({ box }: { box: ViewBox }) {
  const step = GLYPH.graticuleStepDeg
  let grid = ''
  // Meridians and parallels are straight and evenly spaced on this projection (lib/geo), so a
  // graticule is a set of chart-unit lines at multiples of the step, clipped to the box.
  for (let x = Math.ceil(box.x / step) * step; x <= box.x + box.width; x += step) {
    grid += `M${x} ${box.y}L${x} ${box.y + box.height}`
  }
  for (let y = Math.ceil(box.y / step) * step; y <= box.y + box.height; y += step) {
    grid += `M${box.x} ${y}L${box.x + box.width} ${y}`
  }
  if (grid === '') return null
  return (
    <path
      d={grid}
      pointerEvents="none"
      className="fill-none stroke-chart-grid"
      strokeWidth={GLYPH.graticuleStroke}
      vectorEffect="non-scaling-stroke"
      data-testid="map-graticule"
    />
  )
})
