import { useCallback, useEffect, useMemo, useRef } from 'react'
import { fineClass } from '../components/ui'
import { project, WORLD_BOUNDS, type GeoBounds, type LatLon, type Point, type ViewBox } from '../lib/geo'
import { useT } from '../lib/i18n'
import type { FleetView, SnapshotPort } from '../lib/rpc'
import { ChartCanvas } from './ChartCanvas'
import { buildChartModel, dotPorts, visiblePorts } from './chartModel'
import { minTierForSpan, openingBounds } from './chartView'
import { GLYPH } from './glyphs'
import { hitTest } from './hitTest'
import { placedNames } from './placedNames'
import { mapFleetsOf } from './liveWorld'
import { loopD } from './route'
import type { MapSelection } from './mapTypes'
import { useRegionsFilter } from './regionsFilter'
import { useBackdrop } from './useBackdrop'
import { useChartSurface } from './useChartSurface'
import { ViewControls } from './ViewControls'
import type { PathStop } from './ShipPathLayer'

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
// This chart sits inside a desk face a phone scrolls. A chart that owned every gesture there —
// `touch-none`, a preventDefault wheel — would be a wall: the player's finger lands on it, drags
// down, and the page does not move. An action must never live where it cannot be reached
// (docs/CORE_REUSE.md §1.5), which is exactly why this chart once mounted no surface at all. The
// answer is not a second gesture implementation and not staying inert; it is the ONE surface hook,
// configured per use (the hook's header carries the contract):
//
//   · the CITIES chart (Buy / Sell) takes `wheel-zoom`: a one-finger drag DOWN the page scrolls
//     the page (`touch-pan-y`), so the desk below is always reachable with a thumb on the chart,
//     while the WHEEL zooms — the reader's first instinct on a map big enough to deserve it, and
//     the owner's row 2026-10-30 ("the map, i can't zoom in … in command"). A one-finger drag
//     ALONG the coast pans the chart; a pinch zooms it; a mouse drag pans both axes (a mouse never
//     scrolled a page by dragging).
//   · the PLAN's chart takes `still` (below), which cedes every gesture to the page — `page-vertical`,
//     no wheel listener, no +/− column — so it is a picture that never stands between a thumb and
//     the Issue button.
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
// ── 2026-10-25, OWNER ROW 183: THE PLAN'S CHART ─────────────────────────────────────────────────
// *"It should show map (without npcs or name of the cities that aren't associated with the route/plan"*.
// Two optional props, both off by default (every other caller is unchanged):
//   · `only` — the port CODES drawn at all. Every other harbour is left off the paper, so no other
//     city's mark or name can appear; the merchants never reach this chart (it is handed no traffic).
//   · `legs` — the plan's proposed courses (`planLines`, the course author's water, the same `path`
//     the queued SAIL lines carry and the server re-verifies). Point 2 above forbids a STRAIGHT line
//     between two places; these are not straight, they are the course the order would be queued with.
//
// ── 2026-10-26, OWNER ROW 218: A CITY PRESSED IS A CITY CHOSEN ─────────────────────────────────
// *"in mini map in command, show cities, when pressed upon, show trade goods with prices, and charts."*
// One more optional prop, off by default: `onPort`. With it, point 1 above is lifted for HARBOURS ONLY —
// a tap is answered by THE map tab's own hit test (`hitTest`, the same reach, the same drawn ports and
// dots, the same names-first rule), and a harbour it names is handed to the caller. The caller only
// SELECTS a city to read (the Buy / Sell desk); nothing is ordered by the tap. A hull or open water
// answers nothing here.
//
// ── 2026-10-29, OWNER ROW 191: THE PLAN'S MAP IS A PICTURE ─────────────────────────────────────
// *"in command, plan, i want to see a small map showing route concisely."* Two more optional props,
// both off by default: `still` (no pan, no zoom, no controls, no live fleets — the chart redraws only
// when the legs change) and `frame` (the one opening rule recomputed for the plan's legs, so the
// view holds them), plus `stops` — the numbered discs and the start's word, drawn by the chart's own
// `ShipPathLayer` (owner row 225), never a second marker layer.
//
// And it still invents no place: ports and coordinates are `world.snapshot()`; the fleet's
// position at sea is `voyage.position`, the server's closed form, copied (./liveWorld.ts).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** A city press keeps the reader's zoom (row 231). */
const keepZoom = (spanX: number) => spanX

export function SmallChart({
  ports,
  fleets,
  considering,
  highlight,
  only,
  legs,
  stops,
  still = false,
  frame,
  wholeWorld = false,
  onPort,
  goTo = null,
  ariaLabel,
  findAriaLabel,
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
  /** Row 183: draw ONLY these port codes (a plan's cities); absent, the whole table as the tab does. */
  only?: readonly string[]
  /** Row 183: the plan's proposed courses, drawn dashed (ChartCanvas `plannedD`). */
  legs?: readonly (readonly LatLon[])[]
  /** Row 191: the plan's stops — numbered discs, and the start's word (`ShipPathLayer`). */
  stops?: readonly PathStop[]
  /** Row 191: the plan's chart is STILL — no pan, no zoom, no controls, no fleet layer; it redraws
   *  only when the legs change. */
  still?: boolean
  /** Row 191: a still chart's frame, asked for the glass's aspect — the plan's legs, framed by the
   *  one opening rule (`openingBounds`). Absent: the whole world. */
  frame?: (aspect: number) => GeoBounds
  /** Row 207: open at 0 % zoom, the whole world on the glass, instead of framing the choice. */
  wholeWorld?: boolean
  /** Row 218: a harbour tapped (THE map tab's hit test) — the caller selects that city. Absent: no tap. */
  onPort?: (code: string) => void
  /** Row 231: a city PRESSED (on the map, the chip strip or the cargo list) — `n` counts the presses, so pressing
   *  the same city again glides back to it. The chart glides it to the middle at the reader's zoom. Absent: none. */
  goTo?: { code: string; n: number } | null
  ariaLabel: string
  findAriaLabel?: string
  className?: string
}) {
  const t = useT()
  const boxRef = useRef<HTMLDivElement>(null)
  // The ports as the chart draws them — set on the drawn shore (row 92), the same list the Map
  // tab draws — and the backdrop they stand on.
  const backdrop = useBackdrop(ports)
  const onlyKey = only ? only.join(' ') : null
  const chartPorts = useMemo(
    () => (onlyKey === null ? backdrop.ports : backdrop.ports.filter((p) => onlyKey.split(' ').includes(p.code))),
    [backdrop.ports, onlyKey],
  )
  const plannedD = useMemo(() => (legs && legs.length > 0 ? loopD(legs) : null), [legs])
  // The same switch the Map tab wears (row 93): one store, both surfaces.
  const regionsOn = useRegionsFilter()
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
    (aspect: number) =>
      still
        ? frame
          ? frame(aspect)
          : WORLD_BOUNDS
        : wholeWorld
          ? WORLD_BOUNDS
          : openingBounds(model.focusPoints, model.motionPoints, chartPorts, aspect),
    [model, chartPorts, wholeWorld, still, frame],
  )

  // No tap handler unless `onPort` asks for one (row 218, the header). The posture follows `still`: the
  // plan's chart (`still`) cedes everything to the page — `page-vertical` — and stays a picture, while the
  // cities chart wheel-zooms like the Map tab (`wheel-zoom`) and still lets a thumb scroll the form past it.
  const onTap = useCallback(
    (at: Point, unitsPerPx: number, view: ViewBox) => {
      if (still || !onPort) return
      const minTier = minTierForSpan(view.width)
      const tappable = visiblePorts(chartPorts, model.portRoles, view, minTier)
      const dots = dotPorts(chartPorts, model.portRoles, view, minTier)
      const hit = hitTest(model, tappable, at, GLYPH.hitRadius * unitsPerPx, dots, GLYPH.dotHitRadius * unitsPerPx, [], placedNames())
      if (hit?.kind === 'port') onPort(hit.code)
    },
    [still, onPort, chartPorts, model],
  )
  const surface = useChartSurface(boxRef, frameBounds, !still && onPort ? onTap : undefined, { scroll: still ? 'page-vertical' : 'wheel-zoom' })
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
    if (still || !box) return
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
  }, [considering, chartPorts, box, surface, still])

  // ── ROW 231: A CITY PRESSED IS A CITY GONE TO (the owner, 2026-10-26: "buying and selling when pressed a city,
  // move the map to that location"). Each press (a new `n`) GLIDES the city to the middle — the go-to loop the Map
  // tab's search uses (`surface.glideTo`) — at the reader's own zoom (the sheet wraps east-west, so even the whole
  // world turns to put it in the middle; north-south it comes as near the middle as the sheet's edge allows). Only
  // the viewBox moves: nothing on the page is collapsed, re-flowed or docked, and no city leaves the glass.
  const glideTo = surface.glideTo
  const pressedBefore = useRef(0)
  const goCode = goTo?.code ?? null
  const goN = goTo?.n ?? 0
  useEffect(() => {
    if (still || !box || !goCode || goN === pressedBefore.current) return
    pressedBefore.current = goN
    const port = ports.find((p) => p.code === goCode)
    if (port) glideTo(port, keepZoom)
  }, [goCode, goN, box, ports, glideTo, still])

  const selection: MapSelection = highlight ? { kind: 'port', code: highlight } : null

  return (
    <div
      ref={boxRef}
      {...(still ? {} : surface.handlers)}
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
          coast={backdrop.coast}
          seas={backdrop.seas}
          regions={regionsOn ? backdrop.regions : null}
          islets={backdrop.islets}
          selection={selection}
          // The zoom column is opaque and sits on the glass; these are its measured boxes, so the
          // label planner never prints a harbour's name underneath it (the Saint-Malo defect, found
          // 2026-08-21 — the same one mechanism the Map tab feeds, not a second spelling of it).
          keepOut={surface.chromeBoxes}
          plannedD={plannedD}
          pathStops={stops}
          ariaLabel={ariaLabel}
          className="pointer-events-none absolute inset-0 h-full w-full"
        />
      ) : (
        <p className={fineClass('absolute inset-0 flex items-center justify-center')}>
          {t('chart.opening')}
        </p>
      )}
      {!still && (
        <ViewControls
          surface={surface}
          findAriaLabel={findAriaLabel ?? t('chart.findOrder')}
          testId="small-chart-controls"
        />
      )}
    </div>
  )
}
