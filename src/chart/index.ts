// ═══════════════════════════════════════════════════════════════════════════════════════════════
// CHART — the one chart this game draws, and the single door into it
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A LAYER, not a screen and not a domain section. It sits between `domain` and `features`:
//
//     lib · components/ui        machinery and the design system — know nothing above them
//     domain/*                   the rules of the game, pure
//   → chart                      HOW THE WORLD IS DRAWN. May use lib, domain, components/ui.
//     features/*                 the screens. Any of them may COMPOSE the chart; none owns it.
//
// ── WHY IT EXISTS (2026-08-23) ─────────────────────────────────────────────────────────────────
// Every file in here was `src/features/map/`, which made the chart the Map tab's property. Then the
// owner asked for a small chart on SAIL — *"sail — a small map + current location on the left
// side"* — and `tests/sections.spec.ts` correctly refused the Command tab an import of the Map
// tab's internals. That refusal is the whole point of the boundary and it is also its trap, written
// out in `docs/SECTIONS.md`: **forbidding a sideways import does not remove the need to share, it
// converts sharing into a silent COPY, and a copy imports nothing, so no import-graph check can
// see it.** It has already happened twice in this repo (`PortPicker`, and `num`/`str`).
//
// So the thing MOVED, which is the answer `docs/NO_SPAGHETTI.md` §2 gives every time a boundary
// bites. The alternative that was considered and rejected — model into `domain/chart/`, layers into
// `components/chart/` — is forbidden by *"machinery knows nothing above it"*: every layer needs
// `ChartModel`, `MapPort` and `PortRole`, and `src/components/**` may not import `domain/**`. Making
// the layers take plain `{x, y, role}` props to get around that would have been a rewrite of every
// layer's prop type in order to survive a boundary, which is the shape §2 names as the tell that
// the boundary is in the wrong place.
//
// MapScreen's composition did not change. Only its import paths did.
//
// ── WHAT IS IN HERE, AND WHAT IS NOT ───────────────────────────────────────────────────────────
//   in    the read model (mapTypes, chartModel, liveWorld) · the geometry and the density rules
//         (chartView, route, labels, glyphs, svgPath, coastlineBuild) · the layers · the two
//         surfaces a screen composes (`ChartCanvas` for the picture, `SmallChart` for a whole
//         embedded one) · the hooks (`useChartSurface`, `useCoastline`, `useElementSize`)
//   out   the Map TAB — its screen, its two corner panels, its caption. Those are one screen's
//         chrome and they stay in `src/features/map/`, composing this section like anyone else.
//   out   anything that decides. The server owns every rule; nothing in here judges legality,
//         computes a position or invents a distance (./liveWorld.ts's header is the standing rule).
//
// ── THE ENTRANCE ───────────────────────────────────────────────────────────────────────────────
// Import `'../../chart'`, never `'../../chart/PortsLayer'`. `tests/sections.spec.ts` enforces both
// halves of that — nothing outside may reach past this file, and nothing in here may import a
// screen, the shell, the store or `live/`. What a chart needs from up there is a PARAMETER.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// ── the picture ────────────────────────────────────────────────────────────────────────────────
export { ChartCanvas } from './ChartCanvas'
export { SmallChart } from './SmallChart'
// The whole-world locator inset a full-tab chart wears in a corner (its header carries the §7B
// answers — including why it composes the chart's parts rather than `ChartCanvas` whole).
export { Minimap } from './Minimap'

// ── the read model: what a chart is told, and what it makes of it ──────────────────────────────
export type { MapFleet, MapPort, MapSelection, MapVoyage, MapWater } from './mapTypes'
export {
  buildChartModel,
  fleetsAtPort,
  fleetsBoundFor,
  portMarks,
  visiblePorts,
  dotPorts,
  type ChartModel,
  type FleetOnChart,
  type PortMark,
  type PortRole,
} from './chartModel'
export { mapFleetsOf, mapPortsOf } from './liveWorld'
// ROW 90 — the seas' names: how data/seas.json is read, and which waters ask to be named at a
// zoom. The DECISION, exported for the same reason `roadsteadMarks` is; the paint is LabelsLayer's.
export { mapSeasOf, seaNameRequests } from './seaNames'
export type { MapSea } from './mapTypes'

// ── the view: pan, zoom, and the three density rules that answer 214 ports on one sheet ────────
export {
  CHART_CAPTION,
  COMPACT_WIDTH_PX,
  FIT_PADDING,
  GREAT_PORT_TIER,
  SEA_NAME_SPAN_LIMIT,
  LABEL_SPAN_LIMIT,
  MAX_SPAN_X,
  MIN_SPAN_X,
  OPENING_MIN_SPAN_DEG,
  OVER_COVERAGE_LIMIT,
  PORT_TIER_BANDS,
  ZOOM_STEP,
  clampView,
  fitView,
  minTierForSpan,
  openingBounds,
  panBy,
  unitsPerPixel,
  viewBoxOf,
  viewOf,
  zoomAt,
  type ChartView,
} from './chartView'

// ── ink: the glyph metrics, the lines, the names, and what a tap lands on ──────────────────────
// Row 90 added the ship, the arrowhead, the heading and the zoom-scaled coast weight — all here,
// so a spec can hold "one hull for every fleet" and "the pen thickens as you zoom" as arithmetic.
export {
  arrowPath,
  coastStrokeWidth,
  GLYPH,
  headingDeg,
  portMarkScale,
  portStrokeWidth,
  shipPath,
  trianglePath,
} from './glyphs'
export { toClosedRingsD, toPolylineD } from './svgPath'
export { buildTrack, type TrackPaths } from './route'
// 0076 — WHICH PORTS SHOW THEIR ROADS, AND WHERE THE TWO ENDS ARE. The DECISION, exported; the
// layer that renders it is not, like every other layer in here (docs/SECTIONS.md:108). It is
// exported for the same reason `buildTrack` and `planLabels` are: what appears on the paper is
// data, and data is what a spec can hold to account without rendering a component.
export { roadsteadMarks, type RoadsteadMark } from './roadsteads'
// 0075 — where to draw her BETWEEN reads. Exported so the drive can assert the clamp directly.
export { driftedPoint, type Drift } from './drift'
export {
  LABEL_PRIORITY,
  LABEL_SIDES,
  mapLabelRequests,
  planLabels,
  type LabelRequest,
  type LabelSide,
  type LabelTone,
  type PlacedLabel,
  type Rect,
} from './labels'
export { hitTest, toggleSelection } from './hitTest'

// ── the backdrop ───────────────────────────────────────────────────────────────────────────────
export {
  COASTLINE_MIN_SPAN_DEG,
  COASTLINE_TOLERANCE_DEG,
  buildCoastline,
  type CoastCountry,
  type CoastlineData,
} from './coastlineBuild'
// `loadBackdrop` is DELIBERATELY NOT HERE. It is the one module in the section a bundler has to
// resolve (`…/world-110m.json?url`, `…/seas.json?raw`), and re-exporting it would put that edge in
// this file's static graph — which makes the whole entrance unloadable by a plain Node process,
// and the pure specs that measure this section's own figures are plain Node processes.
// `useBackdrop` reaches it dynamically, inside its effect; see ./useBackdrop.ts.
export { useBackdrop, type BackdropState } from './useBackdrop'

// ── the surfaces a screen mounts ───────────────────────────────────────────────────────────────
// `chromeBoxes` on the returned surface is the ONE thing a screen must now hand back to
// `ChartCanvas` (as `keepOut`), so that a port's name is never printed under one of the screen's own
// opaque buttons. See ./useChartSurface.ts's `useChromeBoxes` for why the chart measures the boxes
// but refuses to know what they are.
export {
  CHART_CHROME,
  useChartSurface,
  type ChartSurface,
  type ChartSurfaceOptions,
  type ChromeBox,
} from './useChartSurface'
// The one +/−/find column both surfaces wear — the Map tab mounts it and `SmallChart` mounts it
// itself, so an embedded chart arrives with its zoom already on board.
export { ViewControls } from './ViewControls'
export { useElementSize, type ElementSize } from './useElementSize'
// ROW 92 — where a harbour's mark is SET: on the drawn shore, never in drawn water. The decision,
// exported so tests/map.landfall.spec.ts can run it over the real file; applied once, in
// `useBackdrop`.
export {
  LANDFALL_CAP_NM,
  LANDFALL_INSET_DEG,
  landfallPoint,
  landfallPorts,
  onDrawnLand,
  type Landfall,
  type LandfallResult,
} from './landfall'
// ROW 93 — the regions as ink, and the one switch that shows them. The decisions are exported
// for the same reason `seaNameRequests` is; the paint is CoastlineLayer's and LabelsLayer's.
export { REGION_FILL, regionNameRequests, regionTintsOf, type RegionTint } from './regions'
export { readRegionsFilter, REGIONS_FILTER_KEY, setRegionsFilter, useRegionsFilter } from './regionsFilter'
