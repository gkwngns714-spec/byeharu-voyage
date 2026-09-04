import { useMemo } from 'react'
import type { ViewBox } from '../lib/geo'
import { CoastlineLayer } from './CoastlineLayer'
import { project } from '../lib/geo'
import { FleetsLayer, TracksLayer } from './FleetsLayer'
import { LabelsLayer } from './LabelsLayer'
import { PortsLayer } from './PortsLayer'
import { RoadsteadsLayer } from './RoadsteadsLayer'
import { visiblePorts, type ChartModel } from './chartModel'
import { LABEL_SPAN_LIMIT, minTierForSpan } from './chartView'
import { GLYPH } from './glyphs'
import { mapLabelRequests, planLabels, type Rect } from './labels'
import type { MapPort, MapSelection } from './mapTypes'
import type { ChromeBox } from './useChartSurface'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT IS ON THE PAPER, AND IN WHAT ORDER — the whole chart, drawn once, wherever it is drawn.
//
// PAINT ORDER IS THE ONLY STACKING SVG HAS, so it is a RULE and not a preference: sea, coast,
// tracks, ROADSTEADS, port marks, fleet dots, names. Every name therefore sits on top of every mark
// and no mark sits on a name; the roads go under the ports, because a dotted line crossing a
// harbour should pass behind it.
//
// ── THE SEA IS PAINTED HERE, AND THAT IS NEW (2026-08-23) ──────────────────────────────────────
// "Sea" used to be the first word of that list and no line of code. The chart drew straight onto
// whatever its container happened to be — the `.bv-sea` gradient on both callers — so the sheet had
// no ground of its own, and three things followed. The coast's contrast varied with WHERE on the
// glass it fell (1.03 : 1 against the gradient's top stop, ~1.6 : 1 against its bottom). The label
// halo, `stroke-chart-sea`, punched a hole in a colour that was nowhere behind it. And a token
// named "the chart's sea" described nothing the eye ever met. One `<rect>` makes all three true at
// once, and it is why the contrast figures in src/index.css are one number rather than a range.
// It also means the chart's legibility no longer depends on what any screen puts behind it.
//
// ── WHY THIS IS A COMPONENT AND NOT SEVEN LINES INSIDE MapScreen ───────────────────────────────
// It was seven lines inside MapScreen while the map tab was the only place a chart appeared. The
// Command tab now shows one too (./SmallChart.tsx, on SAIL), and the second `<svg>` would have had
// to restate the same stack — a copy that no import check can see, because a copy imports nothing
// (`docs/NO_SPAGHETTI.md` §2, and `docs/SECTIONS.md`'s note on the trap a boundary sets). Two
// stacks can DISAGREE, which is question 3 of §1's checklist, so there is one.
//
// The three derivations that decide what is drawn ride with it for the same reason. Each one is a
// rule about density, not about a screen:
//   · WHICH PORTS      `visiblePorts` — on the glass, and either big enough for this zoom
//                      (`minTierForSpan`) or one of yours. ONE list, consumed by the marks and by
//                      the label planner, so a name can never float over a mark that was not drawn.
//   · (the lane layer is GONE — 0039: there are no fixed sea lanes on a free sea; the only lines
//      are TRACKS, the verified courses fleets are actually sailing)
//   · WHICH NAMES      planned as a SET over the drawn ports (./labels.ts), which is the only way
//                      two labels can know about each other.
// MapScreen's hit test asks `visiblePorts` the same question with the same box at the moment of a
// tap, which is what keeps "what you can touch" and "what you can see" the same list.
//
// ── IT IS A PICTURE ────────────────────────────────────────────────────────────────────────────
// There is no handler on this component and no prop that could carry one. Selection is resolved by
// the surface that owns the gestures (./hitTest.ts, ./useChartSurface.ts) and arrives here as a
// `MapSelection`, which is a name and not a verb. A chart that accepted an order would be a second
// place orders come from, and there is exactly one (`docs/DESIGN.md`, MapScreen's own header).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function ChartCanvas({
  model,
  ports,
  box,
  unitsPerPx,
  coastlineD,
  selection,
  keepOut,
  ariaLabel,
  className,
}: {
  model: ChartModel
  /** The WHOLE port table. What is drawn out of it is this component's decision, not the caller's. */
  ports: readonly MapPort[]
  box: ViewBox
  /** Chart units per CSS pixel — every glyph and label size is in pixels and scaled by it. */
  unitsPerPx: number
  /** The world's land as one `d`, or '' while it is still being fetched (./useCoastline.ts). */
  coastlineD: string
  selection: MapSelection
  /**
   * OPAQUE CHROME THE SCREEN HAS PUT OVER THIS CHART, in CSS pixels from the chart's top-left
   * corner — hand `useChartSurface`'s `chromeBoxes` straight through. No name will be placed inside
   * one of these, which is how `Saint-Malo` stops rendering as `Sain` behind the zoom column.
   *
   * A PARAMETER, because a chart may not know what a screen is (src/chart/index.ts). Both figures
   * in it are the screen's: the chart converts them to chart units and asks nothing else about
   * them, and it never learns what the box CONTAINS. Omit it and the chart assumes nothing is over
   * it, which is exactly true of `SmallChart`.
   */
  keepOut?: readonly ChromeBox[]
  ariaLabel: string
  className?: string
}) {
  const drawnPorts = useMemo(
    () => visiblePorts(ports, model.portRoles, box, minTierForSpan(box.width)),
    [ports, model.portRoles, box],
  )

  // THE SCREEN'S PIXELS, TURNED INTO CHART UNITS — the one line of arithmetic the keep-out contract
  // needs, done here so no screen ever has to hold a scale or a viewBox origin. `unitsPerPx` is the
  // same on both axes (viewBoxOf derives the height from the surface's aspect), so one factor does
  // both.
  const keepOutUnits = useMemo<readonly Rect[] | undefined>(() => {
    if (!keepOut || keepOut.length === 0) return undefined
    return keepOut.map((r) => ({
      x: box.x + r.x * unitsPerPx,
      y: box.y + r.y * unitsPerPx,
      width: r.width * unitsPerPx,
      height: r.height * unitsPerPx,
    }))
  }, [keepOut, box, unitsPerPx])

  const labels = useMemo(
    () =>
      planLabels(mapLabelRequests(model, drawnPorts, selection, box.width <= LABEL_SPAN_LIMIT), {
        viewBox: box,
        unitsPerPx,
        fontSizePx: GLYPH.labelSize,
        gapPx: GLYPH.labelGapX,
        glyphRadiusPx: GLYPH.fleetHaloRadius,
        keepOut: keepOutUnits,
      }),
    [model, drawnPorts, selection, box, unitsPerPx, keepOutUnits],
  )

  const selectedFleetId = selection?.kind === 'fleet' ? selection.id : null
  const selectedPortCode = selection?.kind === 'port' ? selection.code : null

  return (
    <svg
      className={className}
      viewBox={`${box.x} ${box.y} ${box.width} ${box.height}`}
      role="img"
      aria-label={ariaLabel}
    >
      {/* THE SEA — the ground everything else is measured against. It is the whole viewBox, so it
          moves with the paper and there is never an unpainted edge mid-pan. */}
      <rect
        x={box.x}
        y={box.y}
        width={box.width}
        height={box.height}
        className="fill-chart-sea"
        pointerEvents="none"
        data-testid="map-sea"
      />
      <CoastlineLayer d={coastlineD} />
      <TracksLayer model={model} unitsPerPx={unitsPerPx} />
      {/* THE ROADS (0076) — the dotted helper line out to the one point of open water each port is
          reached from, and the hollow circle on it. UNDER the port marks, because a dotted line
          crossing a harbour should pass behind it (FleetsLayer.tsx:6-9) and a city standing on its
          own roads is the right picture. It is handed `drawnPorts`, the same list PortsLayer gets,
          so a line can never run out of a mark that was not drawn. */}
      <RoadsteadsLayer ports={drawnPorts} unitsPerPx={unitsPerPx} />
      {/* THE PINPOINT (0039) — the tapped spot of open water, marked exactly like a selected
          port is ringed, because it is the same act one step earlier: naming a destination. */}
      {selection?.kind === 'sea' &&
        (() => {
          const at = project(selection.at)
          return (
            <g pointerEvents="none" data-testid="map-sea-point">
              <circle
                cx={at.x}
                cy={at.y}
                r={GLYPH.destinationRingRadius * unitsPerPx}
                className="fill-none stroke-ink/70"
                strokeWidth={GLYPH.glyphStroke}
                vectorEffect="non-scaling-stroke"
              />
              <circle cx={at.x} cy={at.y} r={2 * unitsPerPx} className="fill-ink/70" />
            </g>
          )
        })()}
      <PortsLayer
        ports={drawnPorts}
        portRoles={model.portRoles}
        selectedCode={selectedPortCode}
        unitsPerPx={unitsPerPx}
      />
      <FleetsLayer model={model} selectedId={selectedFleetId} unitsPerPx={unitsPerPx} />
      <LabelsLayer labels={labels} unitsPerPx={unitsPerPx} />
    </svg>
  )
}
