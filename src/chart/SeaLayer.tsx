import { memo, useId } from 'react'
import type { ViewBox } from '../lib/geo'
import { GLYPH } from './glyphs'

// THE WATER — the ground everything else is measured against, with depth, and a graticule.
//
// ── §7B ────────────────────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: THE SEA AS A SURFACE — the flat ground `tests/chart.ink.spec.ts`
//              measures every other ink against, the vignette that makes open water read deeper
//              than the coast, and the hairline grid a chart is drawn on.
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
// ── THE GRATICULE ──────────────────────────────────────────────────────────────────────────────
// One hairline per `GLYPH.graticuleStepDeg` of latitude and longitude, only the ones inside the
// box, as ONE path — at the globe that is 36 lines in one element, at a harbour approach none.
// Non-scaling, so the grid is a hairline at every zoom, and quieter than the coast (its token is
// an alpha of the faint ink). It is furniture: it says "this is a chart", and nothing about the
// game. The old glyphs.ts header banned a grid; row 90 measured that austerity out.

/** Memoised on the box: the grid is a pure function of the view, and the coast beside it changes
 *  never — nothing here has to re-render for a read. */
export const SeaLayer = memo(function SeaLayer({ box }: { box: ViewBox }) {
  const gradientId = useId()
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

  return (
    <g pointerEvents="none">
      <defs>
        <radialGradient id={gradientId} cx="50%" cy="50%" r="72%">
          <stop offset="0%" style={{ stopColor: 'var(--color-chart-deep)', stopOpacity: 0 }} />
          <stop offset="60%" style={{ stopColor: 'var(--color-chart-deep)', stopOpacity: 0.18 }} />
          <stop offset="100%" style={{ stopColor: 'var(--color-chart-deep)', stopOpacity: 0.62 }} />
        </radialGradient>
      </defs>
      {/* THE GROUND — the whole viewBox, so it moves with the paper and there is never an
          unpainted edge mid-pan. Flat, in the pinned token. */}
      <rect x={box.x} y={box.y} width={box.width} height={box.height} className="fill-chart-sea" data-testid="map-sea" />
      {/* THE DEPTH — open water darkens toward the frame's edge. */}
      <rect
        x={box.x}
        y={box.y}
        width={box.width}
        height={box.height}
        fill={`url(#${gradientId})`}
        data-testid="map-sea-depth"
      />
      {/* THE GRATICULE — one path, hairline, quieter than the coast. */}
      {grid !== '' && (
        <path
          d={grid}
          className="fill-none stroke-chart-grid"
          strokeWidth={GLYPH.graticuleStroke}
          vectorEffect="non-scaling-stroke"
          data-testid="map-graticule"
        />
      )}
    </g>
  )
})
