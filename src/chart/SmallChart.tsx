import { useMemo, useRef } from 'react'
import { fineClass } from '../components/ui'
import type { FleetView, SnapshotLeg, SnapshotPort } from '../lib/rpc'
import { ChartCanvas } from './ChartCanvas'
import { buildChartModel } from './chartModel'
import { clampView, fitView, openingBounds, unitsPerPixel, viewBoxOf } from './chartView'
import { mapFleetsOf, mapPortsOf } from './liveWorld'
import type { MapSelection } from './mapTypes'
import { useCoastline } from './useCoastline'
import { useElementSize } from './useElementSize'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SMALL CHART, EMBEDDED — the same chart, framed on two places and taking no gestures at all.
//
// The owner, 2026-08-23: *"sail — a small map + current location on the left side."* Choosing where
// to sail from a list of names asks the player to hold a map in their head; this is the map.
//
// ── IT IS THE SAME CHART, NOT A SECOND ONE ─────────────────────────────────────────────────────
// Every mark on it comes from the modules the Map tab draws with: `buildChartModel` decides which
// ports are loud, `ChartCanvas` decides what is on the paper and in what order, `openingBounds`
// decides the frame, `useCoastline` fetches the one backdrop (and the browser serves the second
// caller from cache). Nothing is redrawn here and nothing is re-derived here. That is the whole
// reason `src/chart/` exists as a layer of its own: `tests/sections.spec.ts` forbids the Command
// tab to reach into the Map tab, and the answer to a boundary that bites is to MOVE the thing down
// a layer, never to retype it (`docs/NO_SPAGHETTI.md` §2).
//
// ── THREE THINGS IT DELIBERATELY DOES NOT DO ───────────────────────────────────────────────────
//
// 1. IT TAKES NO INPUT. No pan, no zoom, no tap, no hover target — `pointer-events: none` on the
//    picture, and no handler prop exists to pass one. Two reasons, and either would be enough:
//    the standing law is that the map never accepts an order (`docs/DESIGN.md`, MapScreen's
//    header), and a gesture surface embedded in a form fights the page's own scroll on a phone
//    (`useChartSurface` sets `touch-none` and calls `preventDefault` on wheel, which is right for a
//    full tab and wrong inside a composer). It re-frames itself when the choice changes; that is
//    all the interaction it has.
//
// 2. IT DRAWS NO LINE BETWEEN THE TWO PLACES. A straight segment from here to there would be read
//    as the passage and measured as the distance, and it is neither: Lisbon → Cádiz is 248 sailed
//    miles because Cape St Vincent is in the way, against 188 as the gull flies. That exact
//    substitution was a real defect on this very picker — it showed Seville at 169 nm against the
//    server's 286 and SORTED the list by the wrong number (`ArgPickers.tsx`, PortPicker's header) —
//    and drawing it instead of printing it would be the same lie in a shape nobody can check. What
//    IS drawn between ports is the authored sea-lane graph, whose miles are the server's own.
//
// 3. IT INVENTS NO PLACE. Ports, coordinates and lanes are `world.snapshot()`; the fleet's position
//    at sea is `voyage.position`, the server's closed form, copied (./liveWorld.ts).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function SmallChart({
  ports,
  legs,
  fleets,
  considering,
  highlight,
  ariaLabel,
  className = 'aspect-[3/2] w-full',
}: {
  /** `world.snapshot().ports` — the whole table. `ChartCanvas` decides which of it is drawn. */
  ports: readonly SnapshotPort[]
  /** `world.snapshot().legs`. Pass an empty list for a chart that should not show the water routes. */
  legs: readonly SnapshotLeg[]
  /** The fleets to place. Usually the one the order is about. */
  fleets: readonly FleetView[]
  /**
   * Port CODES the player is choosing between — ringed exactly as a served destination is, and
   * included in the FRAME, so the picture always holds both ends of the decision.
   */
  considering: readonly string[]
  /**
   * One port to name unconditionally: the row the player is on. It is a `MapSelection`, the same
   * value a tap produces on the Map tab, so it draws the same ring and forces the same label
   * (./labels.ts, `LABEL_PRIORITY.selected`) instead of introducing a second idea of "picked out".
   * It does NOT move the frame — a picture that jumped as the pointer ran down a list would be
   * unreadable.
   */
  highlight: string | null
  ariaLabel: string
  className?: string
}) {
  const boxRef = useRef<HTMLDivElement>(null)
  const size = useElementSize(boxRef)
  const coastline = useCoastline()

  const chartPorts = useMemo(() => mapPortsOf(ports), [ports])
  const chartFleets = useMemo(() => mapFleetsOf(fleets), [fleets])
  const model = useMemo(
    () => buildChartModel(chartFleets, chartPorts, considering),
    [chartFleets, chartPorts, considering],
  )

  const measured = size.width > 0 && size.height > 0
  const aspect = measured ? size.width / size.height : 1

  // THE FRAME IS RE-COMPUTED, NOT REMEMBERED. The Map tab freezes its opening bounds at mount
  // because the player can move away from them and "fit" has to have somewhere to return to. Here
  // there is nowhere to move to and nothing to return to: the frame IS the answer to "where are
  // these two places", so it follows the choice. `openingBounds` is the same function the tab uses,
  // including the 12° floor that stops one docked fleet opening on a 1.5° harbour approach.
  //
  // `clampView` for the same reason the tab clamps: two ports on opposite sides of the world fit to
  // a span wider than the world, and the clamp parks the sheet in the middle instead of jamming it
  // against an edge.
  const view = useMemo(() => {
    if (!measured) return null
    const bounds = openingBounds(model.focusPoints, model.motionPoints, chartPorts, aspect)
    return clampView(fitView(bounds, aspect), aspect)
  }, [measured, model, chartPorts, aspect])

  const box = view ? viewBoxOf(view, aspect) : null

  const selection: MapSelection = highlight ? { kind: 'port', code: highlight } : null

  return (
    <div
      ref={boxRef}
      // `overflow-hidden` clips nothing that can be acted on: there is no control anywhere inside
      // this box, so the reach law (docs/CORE_REUSE.md §1.5) has nothing to bite on. `bv-sea` is
      // the design system's own water, the same surface the Map tab opens on.
      className={`bv-sea relative overflow-hidden rounded-md border border-edge ${className}`}
      data-testid="small-chart"
    >
      {box && view ? (
        <ChartCanvas
          model={model}
          ports={chartPorts}
          legs={legs}
          box={box}
          unitsPerPx={unitsPerPixel(view, size.width)}
          coastlineD={coastline.data?.d ?? ''}
          selection={selection}
          ariaLabel={ariaLabel}
          className="pointer-events-none absolute inset-0 h-full w-full"
        />
      ) : (
        <p className={fineClass('absolute inset-0 flex items-center justify-center')}>
          opening the chart…
        </p>
      )}
    </div>
  )
}
