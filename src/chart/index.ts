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

// ── the read model: what a chart is told, and what it makes of it ──────────────────────────────
export type { MapFleet, MapPort, MapSelection, MapVoyageLeg } from './mapTypes'
export {
  buildChartModel,
  fleetsAtPort,
  fleetsBoundFor,
  visiblePorts,
  type ChartModel,
  type FleetOnChart,
  type PortRole,
} from './chartModel'
export { mapFleetsOf, mapPortsOf } from './liveWorld'

// ── the view: pan, zoom, and the three density rules that answer 214 ports on one sheet ────────
export {
  CHART_CAPTION,
  COMPACT_WIDTH_PX,
  FIT_PADDING,
  LABEL_SPAN_LIMIT,
  LEG_SPAN_LIMIT,
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
export { GLYPH, portMarkScale, trianglePath } from './glyphs'
export { toClosedRingsD, toPolylineD } from './svgPath'
export { buildTrack, legWebPath, type MapLeg, type TrackPaths } from './route'
export {
  LABEL_PRIORITY,
  LABEL_SIDES,
  mapLabelRequests,
  planLabels,
  type LabelRequest,
  type LabelSide,
  type LabelTone,
  type PlacedLabel,
} from './labels'
export { hitTest, toggleSelection } from './hitTest'

// ── the backdrop ───────────────────────────────────────────────────────────────────────────────
export {
  COASTLINE_MIN_SPAN_DEG,
  COASTLINE_TOLERANCE_DEG,
  buildCoastline,
  type CoastlineData,
} from './coastlineBuild'
// `loadCoastline` is DELIBERATELY NOT HERE. It is the one module in the section a bundler has to
// resolve (`…/world-110m.json?url`), and re-exporting it would put that edge in this file's static
// graph — which makes the whole entrance unloadable by a plain Node process, and the pure specs
// that measure this section's own figures are plain Node processes. `useCoastline` reaches it
// dynamically, inside its effect; see ./useCoastline.ts.
export { useCoastline, type CoastlineState } from './useCoastline'

// ── the surfaces a screen mounts ───────────────────────────────────────────────────────────────
export { CHART_CHROME, useChartSurface, type ChartSurface } from './useChartSurface'
export { useElementSize, type ElementSize } from './useElementSize'
