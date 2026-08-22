import { useMemo } from 'react'
import type { ViewBox } from '../lib/geo'
import { CoastlineLayer } from './CoastlineLayer'
import { FleetsLayer, TracksLayer } from './FleetsLayer'
import { LabelsLayer } from './LabelsLayer'
import { LegsLayer } from './LegsLayer'
import { PortsLayer } from './PortsLayer'
import { visiblePorts, type ChartModel } from './chartModel'
import { LABEL_SPAN_LIMIT, LEG_SPAN_LIMIT, minTierForSpan } from './chartView'
import { GLYPH } from './glyphs'
import { mapLabelRequests, planLabels } from './labels'
import type { MapPort, MapSelection } from './mapTypes'
import { legWebPath, type MapLeg } from './route'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT IS ON THE PAPER, AND IN WHAT ORDER — the whole chart, drawn once, wherever it is drawn.
//
// PAINT ORDER IS THE ONLY STACKING SVG HAS, so it is a RULE and not a preference: sea, coast,
// lanes, tracks, port marks, fleet dots, names. Every name therefore sits on top of every mark and
// no mark sits on a name; the lanes go under everything, because they are the paper's grain.
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
//   · WHICH LANES      only inside `LEG_SPAN_LIMIT`, and only between two DRAWN marks, so a lane
//                      never trails off to a harbour this zoom is too far out to draw.
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
  legs,
  box,
  unitsPerPx,
  coastlineD,
  selection,
  ariaLabel,
  className,
}: {
  model: ChartModel
  /** The WHOLE port table. What is drawn out of it is this component's decision, not the caller's. */
  ports: readonly MapPort[]
  /** The sea-lane graph. Pass none for a chart that should not draw the water routes. */
  legs: readonly MapLeg[]
  box: ViewBox
  /** Chart units per CSS pixel — every glyph and label size is in pixels and scaled by it. */
  unitsPerPx: number
  /** The world's land as one `d`, or '' while it is still being fetched (./useCoastline.ts). */
  coastlineD: string
  selection: MapSelection
  ariaLabel: string
  className?: string
}) {
  const drawnPorts = useMemo(
    () => visiblePorts(ports, model.portRoles, box, minTierForSpan(box.width)),
    [ports, model.portRoles, box],
  )

  const legsD = useMemo(() => {
    if (legs.length === 0 || box.width > LEG_SPAN_LIMIT) return ''
    return legWebPath(legs, new Map(drawnPorts.map((p) => [p.code, p])), box)
  }, [legs, box, drawnPorts])

  const labels = useMemo(
    () =>
      planLabels(mapLabelRequests(model, drawnPorts, selection, box.width <= LABEL_SPAN_LIMIT), {
        viewBox: box,
        unitsPerPx,
        fontSizePx: GLYPH.labelSize,
        gapPx: GLYPH.labelGapX,
        glyphRadiusPx: GLYPH.fleetHaloRadius,
      }),
    [model, drawnPorts, selection, box, unitsPerPx],
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
      <CoastlineLayer d={coastlineD} />
      <LegsLayer d={legsD} />
      <TracksLayer model={model} unitsPerPx={unitsPerPx} />
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
