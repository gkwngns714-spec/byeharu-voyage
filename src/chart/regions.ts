// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REGIONS ON THE CHART — 25 tints over the water and the land, and 25 names. PURE.
//
// The owner, 2026-09-14 (OWNER_REQUESTS row 92, the repeat of row 59): *"i told you to create
// regions on map, show it using different color of the sea and country, make filter so that i
// can choose to apply color, or return to the current state."*
//
// ── §7B, ANSWERED FIRST ────────────────────────────────────────────────────────────────────────
// WHAT IT IS   one concept: A REGION AS INK — for each of data/regions.json's 25 regions, the
//              land it holds (the 110m countries whose harbours are mostly its), the water it
//              holds (every navigable cell nearest to one of its harbours BY WATER), the token
//              it is tinted in, and the one place its name is set. ONE partition, the regions;
//              the seas keep their names on the water and are not a second colouring.
// WHERE        src/chart, beside ./seaNames.ts — the DECISION about what is on the paper is
//              data, read here from data/region-tint.json (DERIVED by scripts/build-region-tint.mjs
//              from the chain's own sea raster and data/ports.json; that file's header carries
//              the rules and what was measured and rejected) and from the coast's own rings
//              (`CoastlineData.countries`), so the land tint sits exactly on the body's edge.
// SECOND CALLER  `ChartCanvas` (through `CoastlineLayer` for the paint and `planLabels` for the
//              names), which both the Map tab and `SmallChart` compose — the small chart wears
//              the same `ViewControls`, so the same switch, and it cost nothing to honour it.
//              The minimap deliberately not: a 144 px locator has no room for 25 tints.
// WRONG SHAPE  tints painted from a hand-drawn set of blobs, or from a Voronoi over the seas'
//              unsurveyed anchors — a second answer to "which water is this" beside the raster
//              the game sails. Or: a fourth token per region invented at the point of use; the
//              25 classes below are the whole palette, each a token both schemes define.
//
// ── OFF IS THE CURRENT MAP, EXACTLY ────────────────────────────────────────────────────────────
// With the filter off `ChartCanvas` is handed `null` and nothing in this file is reached: no
// element, no class, no label request. tests/map.regions.spec.ts holds the DOM of the chart with
// the filter off equal to the chart as it was. The filter itself is ./regionsFilter.ts.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, type Point, type ViewBox } from '../lib/geo'
import type { CoastlineData } from './coastlineBuild'
import { GLYPH } from './glyphs'
import { LABEL_PRIORITY, type LabelRequest } from './labels'

/**
 * THE 25 CLASSES — one Tailwind utility per region, written out because the JIT scanner reads
 * source text (a class assembled at runtime never reaches the stylesheet, chartView.ts's
 * `CHART_CAPTION` note) and because tests/map.atmosphere.spec.ts demands every chart token be
 * spent. Keyed by data/regions.json's ids; a region the file adds without a token here is drawn
 * untinted and the spec names it.
 */
export const REGION_FILL: Readonly<Record<string, string>> = {
  iberia: 'fill-chart-region-iberia',
  'atlantic-isles': 'fill-chart-region-atlantic-isles',
  'british-isles': 'fill-chart-region-british-isles',
  'france-low-countries': 'fill-chart-region-france-low-countries',
  baltic: 'fill-chart-region-baltic',
  'scandinavia-arctic': 'fill-chart-region-scandinavia-arctic',
  'western-mediterranean': 'fill-chart-region-western-mediterranean',
  'adriatic-ionian': 'fill-chart-region-adriatic-ionian',
  'aegean-anatolia': 'fill-chart-region-aegean-anatolia',
  levant: 'fill-chart-region-levant',
  maghreb: 'fill-chart-region-maghreb',
  'west-africa': 'fill-chart-region-west-africa',
  'east-africa': 'fill-chart-region-east-africa',
  'arabia-gulf': 'fill-chart-region-arabia-gulf',
  'western-india': 'fill-chart-region-western-india',
  'eastern-india': 'fill-chart-region-eastern-india',
  'southeast-asia': 'fill-chart-region-southeast-asia',
  'china-coast': 'fill-chart-region-china-coast',
  korea: 'fill-chart-region-korea',
  japan: 'fill-chart-region-japan',
  caribbean: 'fill-chart-region-caribbean',
  'north-america-atlantic': 'fill-chart-region-north-america-atlantic',
  'south-america-atlantic': 'fill-chart-region-south-america-atlantic',
  'pacific-americas': 'fill-chart-region-pacific-americas',
  oceania: 'fill-chart-region-oceania',
}

/** One region, ready to paint and to name. */
export interface RegionTint {
  readonly id: string
  readonly name: string
  /** Where the name is set: the mean of the region's harbours (the file's `at`), projected. */
  readonly at: Point
  /** The land: the coast's own rings for the countries this region holds, closed. '' = none. */
  readonly landD: string
  /** The water: axis-aligned cell rectangles, closed. '' = none. */
  readonly waterD: string
  /** The Tailwind fill utility for this region's token (REGION_FILL), or '' with no token. */
  readonly fill: string
}

// The minimum of data/region-tint.json this module is willing to believe (the same tolerance
// ./coastlineBuild.ts and ./seaNames.ts keep: a malformed backdrop may not take the chart down).
interface TintSource {
  readonly cellDeg?: unknown
  readonly regions?: unknown
  readonly countries?: unknown
  readonly water?: unknown
}
interface RegionSource {
  readonly id?: unknown
  readonly name?: unknown
  readonly at?: { readonly lat?: unknown; readonly lon?: unknown }
}

const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)

/** A run of cell rectangles `[col, row, w, h]` as one `d` in chart units. Row 0 is the north
 *  edge (y = −90) and column 0 the antimeridian (x = −180), as the raster is laid out. */
function rectanglesD(rects: unknown, cellDeg: number): string {
  if (!Array.isArray(rects)) return ''
  let d = ''
  for (const r of rects) {
    if (!Array.isArray(r) || r.length !== 4 || !r.every(isNum)) continue
    const [c, row, w, h] = r as number[]
    const x = -180 + c * cellDeg
    const y = -90 + row * cellDeg
    d += `M${x} ${y}h${w * cellDeg}v${h * cellDeg}h${-w * cellDeg}Z`
  }
  return d
}

/**
 * Every well-formed region of a parsed data/region-tint.json, with its land taken from the coast
 * that was built — the two are joined ONCE here, when the backdrop arrives (./backdrop.ts).
 */
export function regionTintsOf(json: unknown, coast: Pick<CoastlineData, 'countries'>): RegionTint[] {
  const src = json as TintSource
  const cellDeg = isNum(src?.cellDeg) && src.cellDeg > 0 ? src.cellDeg : 0.25
  const rows = Array.isArray(src?.regions) ? (src.regions as RegionSource[]) : []
  const countries = (src?.countries ?? {}) as Record<string, unknown>
  const water = (src?.water ?? {}) as Record<string, unknown>

  // country iso → the coast's `d` for it
  const landByIso = new Map(coast.countries.map((c) => [c.iso, c.d]))
  const landByRegion = new Map<string, string>()
  for (const [iso, region] of Object.entries(countries)) {
    if (typeof region !== 'string') continue
    const d = landByIso.get(iso)
    if (!d) continue
    landByRegion.set(region, (landByRegion.get(region) ?? '') + d)
  }

  const out: RegionTint[] = []
  for (const row of rows) {
    if (typeof row?.id !== 'string' || typeof row?.name !== 'string') continue
    const lat = row.at?.lat
    const lon = row.at?.lon
    if (!isNum(lat) || !isNum(lon)) continue
    out.push({
      id: row.id,
      name: row.name,
      at: project({ lat, lon }),
      landD: landByRegion.get(row.id) ?? '',
      waterD: rectanglesD(water[row.id], cellDeg),
      fill: REGION_FILL[row.id] ?? '',
    })
  }
  return out
}

/**
 * The names the regions ask for — every region whose anchor is on the glass, CENTRED on it, in
 * the region tone at the region size, at `LABEL_PRIORITY.region`: above a sea's name (the
 * filter is on to see the regions), below every harbour's, so the ONE planner drops a region's
 * name rather than let it touch a mark or a place's name. Nothing here is set while the filter
 * is off, because nothing calls it then.
 */
export function regionNameRequests(regions: readonly RegionTint[], view: ViewBox): LabelRequest[] {
  const requests: LabelRequest[] = []
  for (const region of regions) {
    const at = region.at
    if (at.x < view.x || at.x > view.x + view.width || at.y < view.y || at.y > view.y + view.height) continue
    requests.push({
      id: `region:${region.id}`,
      text: region.name,
      at,
      priority: LABEL_PRIORITY.region,
      tone: 'region',
      placement: 'centred',
      sizePx: GLYPH.regionNameSize,
      spacingEm: GLYPH.seaNameSpacingEm,
    })
  }
  return requests
}
