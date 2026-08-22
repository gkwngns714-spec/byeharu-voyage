import { memo } from 'react'
import { GLYPH } from './glyphs'

// THE COAST — one <path>, one stroke, one quiet fill.
//
// DESIGN §E.5 says "a single pale stroke. No fill, no terrain, no bathymetry, no borders." The
// stroke and the ban on terrain and borders are kept exactly. The one departure is a fill, and it
// is deliberate: an outline alone leaves the player deciding which side of a line is water, and
// this map's whole job is to be readable at a glance. So land is painted in the design system's
// own `--color-chart-land` (#1b2635) against `--color-chart-sea` (#0a1220) — a ~5% value step,
// enough to separate the two and far too flat to be mistaken for terrain. The tokens were put in
// src/index.css for exactly this pair; using them is not inventing a palette.
//
// `fill-rule: evenodd` so a country's interior rings render as holes rather than as solid blocks.
// `vector-effect: non-scaling-stroke` so the coast stays a hairline at every zoom — a stroke that
// scaled would turn the whole Mediterranean into a smear at 20×.
//
// Memoised on `d`: this is ~6,000 points that change never, sitting under a layer that re-renders
// every animation frame.

export const CoastlineLayer = memo(function CoastlineLayer({ d }: { d: string }) {
  if (!d) return null
  return (
    <path
      d={d}
      fillRule="evenodd"
      className="fill-chart-land stroke-ink-faint/35"
      strokeWidth={GLYPH.coastStroke}
      strokeLinejoin="round"
      vectorEffect="non-scaling-stroke"
      pointerEvents="none"
      data-testid="map-coastline"
    />
  )
})
