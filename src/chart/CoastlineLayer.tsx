import { memo, useId } from 'react'
import { CHART_WIDTH, type Point } from '../lib/geo'
import type { CoastlineData } from './coastlineBuild'
import { DaylightMask } from './DaylightMask'
import { DAY_LAND_BANDS, GLYPH } from './glyphs'
import type { RegionTint } from './regions'

// THE COAST — the shallows under it, one land body, its relief, and one stroke whose weight is the
// zoom's; then, where the Sun is up, the same four in the Earth's own colours. Two `d`s from one
// file: the BODY is every ring closed (`d`), the LINE is the outline with the inland borders
// dropped (`coastD`) — ./coastlineBuild.ts says how and why.
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
// ── 2026-10-14: THE DAY SIDE, AND THE SHEET THAT REPEATS ──────────────────────────────────────
// THE DAY (owner: *"sunlight based on real science. The sunlight touching the earth should have
// colors similar to daytime earth"*). After the four night steps, the SAME four again — shallows,
// body, relief, line — in the `chart-day-*` tokens (src/index.css), inside ONE group masked by the
// Sun's raster (./DaylightMask.tsx): where the Sun is up the day picture covers the night one,
// where it is down nothing is added, and the twilight is the mask's own gradient. The day body is
// filled with a GRADIENT DOWN THE SHEET keyed on latitude — ice at the poles, boreal green, temperate
// green, the arid belt tan at ±25°, the tropics green — which is what the Earth looks like from
// above at this chart's resolution; it is a tint of the one body and promises no terrain the data
// does not have. The night tokens did not move and the ink spec still measures them.
// THE COPIES (owner: *"the map is not continuous from left to right"*). The whole picture is drawn
// ONCE, into a group with an id, at the first copy of the sheet the paper touches; every other copy
// is a `<use>` of that group translated by 360°. The browser clones the subtree — the clipPath, the
// mask and the gradient go with it, in the clone's own user space — so the second copy costs no
// second path string and no second React tree. `copies` is `sheetCopies` of the paper
// (src/lib/geo): the one periodicity rule, composed.
//
// ── ROW 93 (2026-09-14): THE REGIONS' TINTS, in the same order ────────────────────────────────
//   0. THE WATER TINT  under everything: each region's water cells (./regions.ts, `waterD`) in
//                      that region's token at `WATER_TINT_ALPHA`, `crispEdges` so the cells tile
//                      without seams. Painted FIRST so the shallows, the body and the coast sit
//                      on it exactly as they sit on the flat sea.
//   2b. THE LAND TINT  after the body, before the relief: each region's countries (`landD`, the
//                      body's own rings) in the same token at `LAND_TINT_ALPHA`, inside the body
//                      clip — so the tint can never reach the water and the coast stroke and the
//                      relief stay on top of it, untouched.
// Both only while `regions` is handed in — the filter (./regionsFilter.ts) is the only thing that
// does — so with the filter off this file emits exactly the elements it emitted before row 93.
// By day the two tints are painted again inside the day group, over the day water and the day
// body, so the filter reads on both sides of the terminator.
//
// ── ROW 92 (2026-09-14): THE ISLETS, after the coast ──────────────────────────────────────────
// A speck of land under each harbour whose island the 110m file lacks (./landfall.ts): a circle
// of `GLYPH.isletRadius` in the land token with the coast's stroke, non-scaling, so it is the
// same speck at every zoom. Ground, not a mark: painted here with the land, under every port.
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
// one attribute, not the 78 KB path strings; the Sun's raster changes once a minute.

const SHALLOW_INK = ['stroke-chart-shallow/25', 'stroke-chart-shallow/35', 'stroke-chart-shallow/55'] as const
const DAY_SHALLOW_INK = ['stroke-chart-day-shallow/30', 'stroke-chart-day-shallow/40', 'stroke-chart-day-shallow/60'] as const

/** How strong a region's tint is on the water and on the land, as SVG fill-opacity. The water
 *  is the darker ground at night and the lighter by day, so the two are one number: the tokens
 *  were validated at full strength and the tint only ever thins them. */
export const WATER_TINT_ALPHA = 0.32
export const LAND_TINT_ALPHA = 0.42

/** One frozen empty list, so a chart with no islets does not allocate one per frame. */
const NO_ISLETS: readonly Point[] = []
const BASE_COPY: readonly number[] = [0]

export const CoastlineLayer = memo(function CoastlineLayer({
  coast,
  strokeWidth = GLYPH.coastStroke,
  relief = true,
  regions = null,
  islets = NO_ISLETS,
  unitsPerPx = 0,
  copies = BASE_COPY,
  rasterUrl = null,
}: {
  /** The built backdrop, or null while it is still being fetched — which draws nothing. */
  coast: Pick<CoastlineData, 'd' | 'coastD'> | null
  /** The coast's weight for this zoom — `coastStrokeWidth(spanX)`, the caller's to compute. */
  strokeWidth?: number
  /** The shallows, the inner shadow and the day picture. Off for the minimap; on for every chart
   *  a player reads. */
  relief?: boolean
  /** The regions' tints (row 93), or null — which is the filter OFF and the map as it was. */
  regions?: readonly RegionTint[] | null
  /** Harbours with no drawn land (row 92): a speck of land is painted under each. */
  islets?: readonly Point[]
  /** Chart units per CSS pixel — only the islets' radius needs it; 0 draws no islets. */
  unitsPerPx?: number
  /** The copies of the sheet this layer is painted over (`sheetCopies` of the paper). */
  copies?: readonly number[]
  /** The Sun's raster (./useSunlight.ts), or null for the night picture alone. */
  rasterUrl?: string | null
}) {
  const clipId = useId()
  const maskId = useId()
  const gradientId = useId()
  const baseId = useId()
  if (!coast || !coast.d) return null
  const { d, coastD } = coast
  const day = relief && rasterUrl !== null
  const base = copies[0] ?? 0
  return (
    <g pointerEvents="none">
      <g transform={`translate(${base * CHART_WIDTH} 0)`} data-sheet-copy={base}>
        <g id={baseId}>
          {regions && (
            /* 0. THE WATER TINT (row 93) — under the shallows and the body, one path per region. */
            <g data-testid="map-regions-water" fillOpacity={WATER_TINT_ALPHA} shapeRendering="crispEdges">
              {regions.map(
                (region) =>
                  region.waterD !== '' &&
                  region.fill !== '' && <path key={region.id} d={region.waterD} className={region.fill} data-region-id={region.id} />,
              )}
            </g>
          )}
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
          {regions && relief && (
            /* 2b. THE LAND TINT (row 93) — on the body, clipped to it, under the relief and the coast. */
            <g clipPath={`url(#${clipId})`} data-testid="map-regions-land" fillOpacity={LAND_TINT_ALPHA}>
              {regions.map(
                (region) =>
                  region.landD !== '' &&
                  region.fill !== '' && (
                    <path key={region.id} d={region.landD} fillRule="evenodd" className={region.fill} data-region-id={region.id} />
                  ),
              )}
            </g>
          )}
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
          {/* 5. THE ISLETS (row 92) — land the file lacks, under the harbours that stand on it. */}
          {unitsPerPx > 0 && islets.length > 0 && (
            <g data-testid="map-islets">
              {islets.map((at) => (
                <circle
                  key={`${at.x},${at.y}`}
                  cx={at.x}
                  cy={at.y}
                  r={GLYPH.isletRadius * unitsPerPx}
                  className="fill-chart-land stroke-chart-coast"
                  strokeWidth={strokeWidth}
                  vectorEffect="non-scaling-stroke"
                />
              ))}
            </g>
          )}
          {/* 6. THE DAY — the same picture in the Earth's colours, through the Sun's mask. One image
              in the mask, at the base copy: a <use> copy translates its mask with it. */}
          {day && (
            <>
              <defs>
                <DaylightMask id={maskId} rasterUrl={rasterUrl} copies={BASE_COPY} />
                <linearGradient id={gradientId} gradientUnits="userSpaceOnUse" x1={0} y1={-90} x2={0} y2={90}>
                  {DAY_LAND_BANDS.map((band, i) => (
                    <stop
                      key={i}
                      offset={`${((90 - band.lat) / 180) * 100}%`}
                      style={{ stopColor: band.token }}
                    />
                  ))}
                </linearGradient>
              </defs>
              <g mask={`url(#${maskId})`} data-testid="map-coast-day">
                {regions && (
                  <g fillOpacity={WATER_TINT_ALPHA} shapeRendering="crispEdges">
                    {regions.map(
                      (region) =>
                        region.waterD !== '' &&
                        region.fill !== '' && <path key={region.id} d={region.waterD} className={region.fill} />,
                    )}
                  </g>
                )}
                {GLYPH.shallowHaloPx.map((width, i) => (
                  <path
                    key={width}
                    d={coastD}
                    className={`fill-none ${DAY_SHALLOW_INK[i]}`}
                    strokeWidth={width}
                    strokeLinejoin="round"
                    strokeLinecap="round"
                    vectorEffect="non-scaling-stroke"
                  />
                ))}
                <path d={d} fillRule="evenodd" fill={`url(#${gradientId})`} data-testid="map-coastline-day" />
                {regions && (
                  <g clipPath={`url(#${clipId})`} fillOpacity={LAND_TINT_ALPHA}>
                    {regions.map(
                      (region) =>
                        region.landD !== '' &&
                        region.fill !== '' && <path key={region.id} d={region.landD} fillRule="evenodd" className={region.fill} />,
                    )}
                  </g>
                )}
                <g clipPath={`url(#${clipId})`}>
                  <path
                    d={coastD}
                    className="fill-none stroke-chart-day-relief/60"
                    strokeWidth={GLYPH.reliefPx}
                    strokeLinejoin="round"
                    strokeLinecap="round"
                    vectorEffect="non-scaling-stroke"
                  />
                </g>
                <path
                  d={coastD}
                  className="fill-none stroke-chart-day-coast"
                  strokeWidth={strokeWidth}
                  strokeLinejoin="round"
                  strokeLinecap="round"
                  vectorEffect="non-scaling-stroke"
                  data-testid="map-coast-day-line"
                />
                {unitsPerPx > 0 && islets.length > 0 && (
                  <g>
                    {islets.map((at) => (
                      <circle
                        key={`${at.x},${at.y}`}
                        cx={at.x}
                        cy={at.y}
                        r={GLYPH.isletRadius * unitsPerPx}
                        className="fill-chart-day-temperate stroke-chart-day-coast"
                        strokeWidth={strokeWidth}
                        vectorEffect="non-scaling-stroke"
                      />
                    ))}
                  </g>
                )}
              </g>
            </>
          )}
        </g>
      </g>
      {/* THE OTHER COPIES OF THE SHEET — the picture above, cloned and translated by whole turns. */}
      {copies.slice(1).map((k) => (
        <use key={k} href={`#${baseId}`} transform={`translate(${k * CHART_WIDTH} 0)`} data-sheet-copy={k} />
      ))}
    </g>
  )
})
