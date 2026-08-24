import { useCallback, useEffect, useMemo, useRef } from 'react'
import { fineClass } from '../components/ui'
import { project } from '../lib/geo'
import type { FleetView, SnapshotPort } from '../lib/rpc'
import { ChartCanvas } from './ChartCanvas'
import { buildChartModel } from './chartModel'
import { openingBounds } from './chartView'
import { mapFleetsOf, mapPortsOf } from './liveWorld'
import type { MapSelection } from './mapTypes'
import { useChartSurface } from './useChartSurface'
import { useCoastline } from './useCoastline'
import { ViewControls } from './ViewControls'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A SMALL CHART, EMBEDDED — the same chart, framed on the order being made, and steerable without
// ever standing between the player and the rest of the form.
//
// The owner, 2026-08-23: *"sail — a small map + current location on the left side"*, and then:
// *"the map in sail, i should be able to zoom, drag, move."* Choosing where to sail from a list of
// names asks the player to hold a map in their head; this is the map, and now it moves.
//
// ── IT IS THE SAME CHART, NOT A SECOND ONE ─────────────────────────────────────────────────────
// Every mark on it comes from the modules the Map tab draws with: `buildChartModel` decides which
// ports are loud, `ChartCanvas` decides what is on the paper and in what order, `openingBounds`
// decides the frame, `useCoastline` fetches the one backdrop (and the browser serves the second
// caller from cache) — and, since 2026-08-23, `useChartSurface` runs the gestures and
// `ViewControls` is the zoom column. Nothing is redrawn here and nothing is re-derived here. That
// is the whole reason `src/chart/` exists as a layer of its own (`docs/NO_SPAGHETTI.md` §2).
//
// ── A GESTURE SURFACE INSIDE A SCROLLING FORM, AND HOW THAT IS NOT A TRAP ──────────────────────
// This chart sits above the Issue button, inside a form a phone scrolls. A chart that owned every
// gesture there — `touch-none`, a preventDefault wheel — would be a wall: the player's finger
// lands on it, drags down, and the page does not move. An action must never live where it cannot
// be reached (docs/CORE_REUSE.md §1.5), which is exactly why this chart mounted no surface at all
// until today. The answer is not a second gesture implementation and not staying inert; it is the
// ONE surface hook in its embedded posture, `scroll: 'page-vertical'` (its header carries the
// contract):
//
//   · a one-finger drag DOWN the page scrolls the page — the browser itself runs the vertical
//     axis (`touch-pan-y`), so the Issue button is always reachable with a thumb on the chart;
//   · a one-finger drag ALONG the coast pans the chart; a pinch zooms it; a mouse drag pans both
//     axes (a mouse never scrolled a page by dragging);
//   · the WHEEL scrolls the page, untouched — no listener is attached — and zoom is the visible
//     +/−/find column, the same 44 px controls the Map tab wears, measured into `keepOut` so no
//     port name is ever printed underneath them.
//
// Rejected: a tap-to-activate mode (a modal state the player must discover, and one forgotten
// deactivation from being the very trap above); an expand-to-fullscreen chart (a second screen to
// build and leave, when the owner asked for THIS map to move); and any second implementation of
// pan/zoom (forbidden outright — one authority, configured, is the entire design).
//
// ── THE FRAME FOLLOWS THE CHOICE, UNTIL THE PLAYER TAKES THE WHEEL ─────────────────────────────
// Untouched, the chart re-frames as the order changes — the frame is the answer to "where are
// these two places", so picking a destination brings both ends onto the sheet (`openingBounds`,
// with the same 12° floor the tab uses). Once the player pans or zooms, their view stands (the
// hook keeps only deliberate moves), and `find` returns to the choice's frame by forgetting them —
// so there is exactly one definition of where this chart opens, and it is computed, not stored.
//
// ── TWO THINGS IT STILL DELIBERATELY DOES NOT DO ───────────────────────────────────────────────
//
// 1. IT TAKES NO TAP. No `onTap` is mounted: there is nothing here a tap could select that the
//    list beside it does not already say in words, and a tap that picked a destination would be a
//    second composer — the one thing docs/DESIGN.md §E.5 Law 3 still forbids. Pan and zoom change
//    what is SEEN, never what is ORDERED.
//
// 2. IT DRAWS NO LINE BETWEEN THE TWO PLACES. A straight segment from here to there would be read
//    as the passage and measured as the distance, and it is neither: Lisbon → Cádiz is 248 sailed
//    miles because Cape St Vincent is in the way, against 188 as the gull flies. That exact
//    substitution was a real defect on this very picker — it showed Seville at 169 nm against the
//    server's 286 and SORTED the list by the wrong number (`ArgPickers.tsx`, PortPicker's header) —
//    and drawing it instead of printing it would be the same lie in a shape nobody can check.
//    (0039: the sea-lane graph is gone with the leg model — the only lines a chart draws are
//    TRACKS, verified courses fleets are actually sailing.)
//
// And it still invents no place: ports and coordinates are `world.snapshot()`; the fleet's
// position at sea is `voyage.position`, the server's closed form, copied (./liveWorld.ts).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function SmallChart({
  ports,
  fleets,
  considering,
  highlight,
  ariaLabel,
  className = 'aspect-[3/2] w-full',
}: {
  /** `world.snapshot().ports` — the whole table. `ChartCanvas` decides which of it is drawn. */
  ports: readonly SnapshotPort[]
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
  const coastline = useCoastline()

  const chartPorts = useMemo(() => mapPortsOf(ports), [ports])
  const chartFleets = useMemo(() => mapFleetsOf(fleets), [fleets])
  const model = useMemo(
    () => buildChartModel(chartFleets, chartPorts, considering),
    [chartFleets, chartPorts, considering],
  )

  // The frame is a FUNCTION of the current choice, not a value frozen at mount as the tab's is:
  // the tab freezes because the player can sail away from its frame and "find" needs somewhere
  // stable to return to; here the choice IS the frame, so when the order changes, so does what
  // "find" (and an untouched chart) shows. `openingBounds` is the same arithmetic the tab uses,
  // including the 12° floor and the clamp against a wider-than-the-world fit.
  const frameBounds = useCallback(
    (aspect: number) => openingBounds(model.focusPoints, model.motionPoints, chartPorts, aspect),
    [model, chartPorts],
  )

  // No tap handler — see the header. `scroll: 'page-vertical'` is the embedded posture: the page
  // keeps its wheel and its vertical thumb-scroll, the chart gets everything else.
  const surface = useChartSurface(boxRef, frameBounds, undefined, { scroll: 'page-vertical' })
  const box = surface.viewBox

  // ── THE CHART MOVES TO THE HARBOUR YOU CHOSE (the owner, 2026-08-23: "when i press corfu or
  // dubrovnik for example on sail, map, the map does not move to that location. make it move -
  // pinpoint"). A ring drawn off the glass is the chart saying "I marked it" and showing nothing:
  // the untouched chart re-frames through `frameBounds` above, but once the player has panned or
  // zoomed, their view stands — and a chosen Adriatic harbour stayed outside a frame parked off
  // Iberia. So when the CHOICE gains a harbour (the same `considering` the ring is drawn from —
  // never the hover-only `highlight`, which a phone cannot raise), and the current frame cannot
  // show it, the view centres on it at the player's own zoom (`surface.centreOn`, the one existing
  // camera move — no second camera, no span change, nothing appears or disappears; only the
  // viewBox moves, which is the chart ANSWERING, not the layout restructuring).
  //
  // Only a NEW code moves the frame — the ref remembers what was already chosen, so panning away
  // from a standing choice is respected, and a frame that already holds the harbour is left alone.
  const chosenBefore = useRef<readonly string[]>([])
  useEffect(() => {
    if (!box) return
    const before = new Set(chosenBefore.current)
    chosenBefore.current = considering
    const fresh = considering.filter((code) => !before.has(code))
    const code = fresh[fresh.length - 1]
    if (!code) return
    const port = chartPorts.find((p) => p.code === code)
    if (!port) return
    const at = project(port)
    const inside =
      at.x >= box.x && at.x <= box.x + box.width && at.y >= box.y && at.y <= box.y + box.height
    if (!inside) surface.centreOn(port)
  }, [considering, chartPorts, box, surface])

  const selection: MapSelection = highlight ? { kind: 'port', code: highlight } : null

  return (
    <div
      ref={boxRef}
      {...surface.handlers}
      // `surface.touchClass` is `touch-pan-y` here — the posture and its touch-action are one fact,
      // stated by the hook. `select-none` stops a pan highlighting the labels, exactly as on the
      // tab. `overflow-hidden` clips only the picture; the one control (ViewControls) is in a
      // corner slot, which cannot be panned or clipped away, so the reach law has nothing to bite
      // on. `bv-sea` paints the water for the frames before the box is measured.
      className={`bv-sea relative overflow-hidden rounded-md border border-edge select-none ${surface.touchClass} ${className}`}
      data-testid="small-chart"
    >
      {box && surface.view ? (
        <ChartCanvas
          model={model}
          ports={chartPorts}
          box={box}
          unitsPerPx={surface.unitsPerPx}
          coastlineD={coastline.data?.d ?? ''}
          selection={selection}
          // The zoom column is opaque and sits on the glass; these are its measured boxes, so the
          // label planner never prints a harbour's name underneath it (the Saint-Malo defect, found
          // 2026-08-21 — the same one mechanism the Map tab feeds, not a second spelling of it).
          keepOut={surface.chromeBoxes}
          ariaLabel={ariaLabel}
          className="pointer-events-none absolute inset-0 h-full w-full"
        />
      ) : (
        <p className={fineClass('absolute inset-0 flex items-center justify-center')}>
          opening the chart…
        </p>
      )}
      <ViewControls
        surface={surface}
        findAriaLabel="Show where she lies and the harbours of this order"
        testId="small-chart-controls"
      />
    </div>
  )
}
