import { memo, useId } from 'react'
import type { CoastlineData } from './coastlineBuild'
import { GLYPH } from './glyphs'

// THE COAST — the shallows under it, one land body, its relief, and one stroke whose weight is the
// zoom's. Two `d`s from one file: the BODY is every ring closed (`d`), the LINE is the outline with
// the inland borders dropped (`coastD`) — ./coastlineBuild.ts says how and why.
//
// ── THE DEFECT THIS FILE CARRIED, MEASURED ─────────────────────────────────────────────────────
// This header used to admit its own bug and ship it anyway: land `#1b2635` against sea `#0a1220`,
// "a ~5% value step". That is a contrast ratio of 1.23 : 1 — and on screen it was 1.03 : 1, because
// the chart painted no sea at all and the land sat on the `.bv-sea` gradient, whose top stop
// (`--color-sky`, #142438) was very nearly the same value the land was. At 390 px, at arm's length,
// Iberia and the Atlantic were one object. A chart whose whole job is "where is this place" cannot
// afford that, so two numbers moved: the body to 2.09 : 1 and the stroke to 3.12 : 1, which is WCAG
// 1.4.11's floor for a graphic that carries meaning. The arithmetic and the reason for each figure
// live with the tokens, in src/index.css — and NONE of those three tokens moved for row 90.
//
// ── ROW 90 (2026-09-13): "map should be much more graphic... it is too blank" ──────────────────
// The audit (docs/MAP_ATMOSPHERE.md) counted what the old picture was: one fill and one hairline.
// Now, in paint order, and the order is the picture:
//   1. THE SHALLOWS  three non-scaling strokes of the LINE, under the body, widest first, in
//                    `chart-shallow` at rising alpha — the half of each band that falls over land is
//                    covered by the body painted next, so what survives is paler water hugging
//                    every coast.
//   2. THE BODY      the land fill (`d`), in the pinned token, `evenodd` so lakes stay water. This
//                    is `map-coastline`, the element whose fill the ink spec measures.
//   3. THE RELIEF    the LINE stroked wide in `chart-relief`, INSIDE a clipPath of the body, so only
//                    the inland half shows: an inner shadow along the coast, with no filter (a blur
//                    re-rasterises 6,000 points per frame; a clipped stroke is one more path draw).
//   4. THE COAST     the LINE in the pinned token at `coastStrokeWidth(spanX)` — a hairline over
//                    the globe, a firm line at a harbour approach. `map-coast`, the element whose
//                    stroke the ink spec measures.
// The minimap passes `relief={false}` and gets 2 and 4 only: at 144 px a 40 px halo is a smear, and
// a locator wants a coast, not a picture. That is a choice between two acceptable pictures.
//
// WHY THE LINE IS NOT THE BODY'S OWN STROKE. The file is countries, and neighbours share their
// border's vertices exactly, so stroking the closed rings draws every inland border as a coast —
// a thin one before row 90, and with the relief a shadowed one. The stroke is the outline with
// those 2,664 shared segments left out, which is also §E.5's "no borders" made true at last.
//
// `vector-effect: non-scaling-stroke` on every stroke so none of them fattens on zoom — a stroke
// that scaled would turn the whole Mediterranean into a smear at 20×.
//
// Memoised: `coast` is one object per fetch; `strokeWidth` changes on zoom, and React then touches
// one attribute, not the 78 KB path strings.

const SHALLOW_INK = ['stroke-chart-shallow/25', 'stroke-chart-shallow/35', 'stroke-chart-shallow/55'] as const

export const CoastlineLayer = memo(function CoastlineLayer({
  coast,
  strokeWidth = GLYPH.coastStroke,
  relief = true,
}: {
  /** The built backdrop, or null while it is still being fetched — which draws nothing. */
  coast: Pick<CoastlineData, 'd' | 'coastD'> | null
  /** The coast's weight for this zoom — `coastStrokeWidth(spanX)`, the caller's to compute. */
  strokeWidth?: number
  /** The shallows and the inner shadow. Off for the minimap; on for every chart a player reads. */
  relief?: boolean
}) {
  const clipId = useId()
  if (!coast || !coast.d) return null
  const { d, coastD } = coast
  return (
    <g pointerEvents="none">
      {relief && (
        <>
          <defs>
            <clipPath id={clipId} clipPathUnits="userSpaceOnUse">
              <path d={d} fillRule="evenodd" />
            </clipPath>
          </defs>
          {/* 1. THE SHALLOWS — widest first, so each narrower band paints over the one before it
              and the water is palest right at the shore. */}
          {GLYPH.shallowHaloPx.map((width, i) => (
            <path
              key={width}
              d={coastD}
              className={`fill-none ${SHALLOW_INK[i]}`}
              strokeWidth={width}
              strokeLinejoin="round"
              strokeLinecap="round"
              vectorEffect="non-scaling-stroke"
              data-testid={i === GLYPH.shallowHaloPx.length - 1 ? 'map-shallows' : undefined}
            />
          ))}
        </>
      )}
      {/* 2. THE BODY. Full opacity, in the pinned token. */}
      <path d={d} fillRule="evenodd" className="fill-chart-land" data-testid="map-coastline" />
      {relief && (
        /* 3. THE RELIEF — on the body, clipped to it so it never reaches the water. */
        <g clipPath={`url(#${clipId})`}>
          <path
            d={coastD}
            className="fill-none stroke-chart-relief/70"
            strokeWidth={GLYPH.reliefPx}
            strokeLinejoin="round"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
            data-testid="map-relief"
          />
        </g>
      )}
      {/* 4. THE COAST. Full opacity, in the pinned token, at this zoom's weight — and that is the
          point: "how pale is the coast" is a token whose value IS its contrast ratio, never an
          alpha struck at the point of use. */}
      <path
        d={coastD}
        className="fill-none stroke-chart-coast"
        strokeWidth={strokeWidth}
        strokeLinejoin="round"
        strokeLinecap="round"
        vectorEffect="non-scaling-stroke"
        data-testid="map-coast"
      />
    </g>
  )
})
