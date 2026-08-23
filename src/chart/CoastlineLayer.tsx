import { memo } from 'react'
import { GLYPH } from './glyphs'

// THE COAST — one <path>, one pale stroke, one quiet body.
//
// ── THE DEFECT THIS FILE CARRIED, MEASURED ─────────────────────────────────────────────────────
// This header used to admit its own bug and ship it anyway: land `#1b2635` against sea `#0a1220`,
// "a ~5% value step". That is a contrast ratio of 1.23 : 1 — and on screen it was 1.03 : 1, because
// the chart painted no sea at all and the land sat on the `.bv-sea` gradient, whose top stop
// (`--color-sky`, #142438) is very nearly the same value the land was. At 390 px, at arm's length,
// Iberia and the Atlantic were one object. A chart whose whole job is "where is this place" cannot
// afford that, so two numbers moved: the body to 2.09 : 1 and the stroke to 3.12 : 1, which is WCAG
// 1.4.11's floor for a graphic that carries meaning. The arithmetic and the reason for each figure
// live with the tokens, in src/index.css.
//
// ── §E.5 SAYS "NO FILL", AND THE BODY IS STILL HERE ────────────────────────────────────────────
// Deliberately — and the doc now says so too: DESIGN §E.5 was amended in the same change rather
// than left to disagree with the code. An outline alone leaves the player deciding which side of a
// line is water, and on a sheet of 289 rings, some of them lakes, that is a puzzle rather than a
// picture. The half of the ban that MATTERS is kept exactly: no terrain, no bathymetry, no borders,
// no relief, no second land colour anywhere. One flat body, one stroke, two tokens.
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
      // Full opacity on both, and that is the point. The stroke used to be `ink-faint/35` — an
      // alpha struck at the point of use, which made "how pale is the coast" a number written into
      // a className instead of a token anyone could retune or measure. It is now one token whose
      // value IS its contrast ratio.
      className="fill-chart-land stroke-chart-coast"
      strokeWidth={GLYPH.coastStroke}
      strokeLinejoin="round"
      vectorEffect="non-scaling-stroke"
      pointerEvents="none"
      data-testid="map-coastline"
    />
  )
})
