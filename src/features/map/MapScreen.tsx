import { armadaMarks } from './armadaMarks'
import { useArmadas } from '../../live/armadas'
import { Fragment, useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { PointerCoords } from './PointerCoords'
import { unproject, type LatLon, type Point, type ViewBox } from '../../lib/geo'
import type { FleetView, PortAllegiance, PortMerchant, SnapshotPort, TrafficFleet } from '../../lib/rpc'
import type { SeaNav } from '../../lib/sea'
import { pointToken, snapSeaPoint } from '../../domain/passage'
import { useShellState } from '../../app/shellState'
import { portNationOf, useWorld } from '../../live/worldStore'
import { useShipPath } from '../../live/useShipPath'
import { CityFlag } from '../../live/CityFlag'
import { usePortFlags } from '../../live/usePortFlags'
// THE MERCHANTS (0099): their sheet and its card are live-data React shared with PORT.
import { CargoSheet } from '../../live/CargoSheet'
import { NavySheet } from '../../live/NavySheet'
import { PirateSheet } from '../../live/PirateSheet'
import { MerchantSheet } from '../../live/MerchantSheet'
import { merchantParts } from '../../live/merchantLine'
import { useCargoShipCard } from '../../live/useCargoShipCard'
import { useNavyShipCard } from '../../live/useNavyShipCard'
import { usePirateShipCard } from '../../live/usePirateShipCard'
import { useMerchantCard } from '../../live/useMerchantCard'
import { useMerchantsHere } from '../../live/useMerchantsHere'
import { useFights } from '../../live/useFights'
import { FightSheet } from '../../live/FightSheet'
// WHICH HULL IS IN HAND — `domain/order`'s draft, the SAME one FLEETS points at.
import { useCommandDraft } from '../../domain/order'
// THE CHART IS A SECTION OF ITS OWN (src/chart) and this screen composes it; nothing here draws.
import {
  buildChartModel,
  ChartCanvas,
  clampView,
  fitView,
  fleetsAtPort,
  fleetsBoundFor,
  GLYPH,
  GoToLink,
  GoToMarker,
  goToPoint,
  GOTO_MIN_CLEAR_PX,
  GOTO_MARK_MS,
  goToSpan,
  PlaceLine,
  useGoTo,
  CHART_CHROME,
  type FleetOnChart,
  type GoToTarget,
  dotPorts,
  fightAt,
  fightRings,
  fightRimWins,
  fightTapWins,
  hitTest,
  placedNames,
  mapFightsOf,
  mapFleetsOf,
  loopD,
  mapTrafficOf,
  Minimap,
  minimapChosen,
  useMinimapPrefs,
  minTierForSpan,
  openingBounds,
  shipMarks,
  toggleSelection,
  useBackdrop,
  useChartShore,
  useChartSurface,
  useRegionsFilter,
  ViewControls,
  visiblePorts,
  type ChartModel,
  type MapPort,
  type MapSelection,
  type PathStop,
} from '../../chart'
// The one table that says where a side tray stands, and therefore where the chrome stops.
import { chromeAsideSideTrayClass, DetailPage, Icon, LoadMeter } from '../../components/ui'
import { worldLoadSteps } from '../../live/loadSteps'
import { ChartMessage } from './ChartMessage'
import { FleetsCorner } from './FleetsCorner'
import { VoyageTray } from './VoyageTray'
import { SendFleet } from './SendFleet'
import { useFleetSeas, useSeaZoneCells } from '../../live/useFleetSeas'
import { zoneAt } from '../../domain/seas'
import { RouteBar } from './RouteBar'
import { RouteEditor } from '../../live/RouteEditor'
import { useRouteBuilder } from './useRouteBuilder'
import { useRouteSeed } from './routeSeed'
import { CityHarbour } from './CityHarbour'
import { merchantsSummary } from '../../live/merchantGroups'
import { viewLeftFrame } from './frame'
import { useT, t as tNow } from '../../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MAP — the chart is the ground, and the chrome hides until it is summoned.
//
// docs/UI_DIRECTION.md §6: keep the chart, the corner controls, the minimap (only when zoomed);
// cut the caption bar, the hint sentence, the `KEEP & SEND` label; fold the Fleets panel to a
// pill that opens a `Corner`, and the detail panel into a `Tray`. The owner's own map rules are
// the constraint: clean map, corners not centre, minimal words, no jargon, foldable, dismissible.
//
//   NOTHING IN `features/map` MAY PICK AN ARGUMENT, BOUND A QUANTITY, OR JUDGE AN ORDER.
// One composer, one grammar, one judge (`cmd.preview`, run and rolled back), one issue path. The
// send flow here (useSendFleet.ts) is a second CALLER of each, never a second authority. Nothing
// is handed off any more (2026-09-09): SAIL's one doorway is this chart, and a refusal's fix that
// still needs a choice is words in the refusal — the choice is made where its verb lives.
//
// Drawn: one coastline, the lanes close in, three glyphs, a dotted track for the CURRENT leg, two
// corners, a tray when something is tapped. Absent: other players (§E.5), the route beyond the
// current leg (the chart never invents water), and the four sentences §2 item 20 counted. Nothing
// moves by itself — the position is the server's, copied — and every control is anchored to the
// glass, never to a coordinate (docs/CORE_REUSE.md §1.5). The chart is `role="img"` with no
// focusable element; everything it says, the corner and the tray also say as ordinary controls.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** The view before the glass is measured: nothing, which is no fine coast. */
const NO_VIEW: ViewBox = { x: 0, y: 0, width: 0, height: 0 }

export function MapScreen() {
  const t = useT()
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)
  const seaNav = useWorld((s) => s.seaNav)
  const fleets = useWorld((s) => s.fleets)
  const readAt = useWorld((s) => s.readAt)
  const trafficReadAt = useWorld((s) => s.trafficReadAt)
  // THE MERCHANTS (0099, docs/NPC_TRADERS.md §8.1): read on the shell's beat while this screen is
  // up — the one seam a screen has into the cadence, never a clock of its own.
  const traffic = useWorld((s) => s.traffic)
  const wantTraffic = useWorld((s) => s.wantTraffic)
  useEffect(() => wantTraffic(), [wantTraffic])

  // THE LOADING METER (owner row 255, 2026-10-31: *"when reloading, for example opening the city,
  // or loading the map, show percentage of its loading time"*) — the city's meter, composed here
  // the same way: the world's three real steps ride the store's `boot` (live/loadSteps.ts, the one
  // list), and the fourth is this screen's own read, the first roster of the ships at sea
  // (`traffic`, null until it lands — dark or lit). One component (LoadMeter), measured work, no
  // timer. It stands ON the sea as an overlay — before the chart, and over it for the beat the
  // roster still takes — so it moves nothing when it goes, and it is gone the instant every step is.
  // The roster is a step from the first frame while the world opens (the effect above asks for it at
  // once); once the world is up, only from the moment it is asked (`trafficWanted`, this screen's
  // alone): a roster the store keeps is placed in the very call that asks for it, so a return to the
  // map commits no frame of meter for a read that is not pending.
  const boot = useWorld((s) => s.boot)
  const asked = useWorld((s) => s.trafficWanted > 0)
  const world = worldLoadSteps(t, boot)
  const ships = { id: 'ships', label: t('map.loadShips'), done: traffic !== null }
  const steps = asked || world.some((s) => !s.done) ? [...world, ships] : world

  // A FAILURE IS RENDERED, NEVER SPUN ON (DESIGN §F.5); an opening is the sea with the meter on it.
  if (phase === 'failed') return <ChartMessage refusal={fatal} />

  // The chart mounts ONLY with the world in hand, so it can freeze its opening frame on real fleets.
  return (
    <div className="relative h-full w-full">
      {phase !== 'ready' || !snapshot || !seaNav ? (
        <ChartMessage refusal={null} />
      ) : (
        <Chart
          ports={snapshot.ports}
          seaNav={seaNav}
          fleets={fleets}
          traffic={traffic?.enabled ? traffic.fleets : NO_TRAFFIC}
          readAt={readAt}
          trafficReadAt={trafficReadAt}
        />
      )}
      <div className="pointer-events-none absolute inset-x-0 top-3 z-20 flex justify-center" data-testid="map-load-host">
        <LoadMeter steps={steps} className="w-56 max-w-[calc(100%-7rem)] rounded-chip bg-surface/90 px-3 shadow-sheet" data-testid="map-load" />
      </div>
    </div>
  )
}

/** The one line under a harbour's name at peek: its country, how many merchants the city concerns
 *  and how many of them lie here, and which of yours are here or heading here. The merchants
 *  resting here are not drawn on the chart (chartModel.ts), so the city counts them — the
 *  harbour's own read (`world.port_merchants`), never the capped sea window — and the list itself
 *  is the Port tab (CityHarbour.tsx). */
function portLine(
  model: ChartModel,
  port: MapPort,
  merchants: readonly PortMerchant[],
  allegiance: PortAllegiance | undefined,
): ReactNode {
  const here = fleetsAtPort(model, port.code)
  const bound = fleetsBoundFor(model, port.code)
  // 0143 (D14): THE FLAG IT FLIES TODAY, in place of the modern country's name — none until read.
  const parts: ReactNode[] = allegiance ? [<CityFlag allegiance={allegiance} />] : []
  const summary = merchantsSummary(merchants, port.code)
  if (summary) parts.push(summary)
  if (here.length > 0) parts.push(<>{fleetLinks(here)} {tNow('map.here')}</>)
  else if (bound.length > 0) parts.push(<>{fleetLinks(bound)} {tNow('map.headingHere')}</>)
  return parts.map((p, i) => (
    <Fragment key={i}>
      {i > 0 && ' · '}
      {p}
    </Fragment>
  ))
}

/** Your fleets by name, each a go-to link (src/chart/goTo.ts), comma-separated. */
function fleetLinks(fleets: readonly FleetOnChart[]): ReactNode {
  return fleets.map((f, i) => (
    <Fragment key={f.fleet.id}>
      {i > 0 && ', '}
      <GoToLink to={{ kind: 'fleet', id: f.fleet.id }}>{f.fleet.name}</GoToLink>
    </Fragment>
  ))
}

const NO_MERCHANTS: readonly PortMerchant[] = []

const NO_TRAFFIC: readonly TrafficFleet[] = []

function Chart({
  ports: snapshotPorts,
  seaNav,
  fleets: fleetViews,
  traffic: trafficRows,
  readAt,
  trafficReadAt,
}: {
  /** Merchant fleets (0099) — never in `fleets`, so nothing about YOUR fleets sees one. */
  traffic: readonly TrafficFleet[]
  ports: readonly SnapshotPort[]
  /** The served navigable-water grid — the tap-on-open-water snap reads it (0039). */
  seaNav: SeaNav
  fleets: readonly FleetView[]
  readAt: number | null
  /** When the merchants landed — their own drift instant (see `buildChartModel`). */
  trafficReadAt: number | null
}) {
  const t = useT()
  // THE ONE CLOCK (src/app/shellState.ts): it ticks a countdown's wording and 0075's drift.
  const { nowMs } = useShellState()

  // WHICH HULL IS IN HAND is `domain/order`'s draft, app-wide; tapping a fleet here points it.
  const selectFleet = useCommandDraft((s) => s.selectFleet)

  // THE PORTS AS THE CHART DRAWS THEM (row 92): served, then set on the drawn shore the moment
  // the coast arrives — one list, read by the model, the hit test, the frame and the picture.
  // THE COUNTRIES' CAPITALS (2026-11-15): their marks and names stay furthest out (src/chart/mapTypes.ts `capital`).
  const nationByCode = useWorld((s) => s.nationByCode)
  const capitals = useMemo(
    () => new Map(Object.values(nationByCode).flatMap((n) => (n.capital ? [[n.capital, n.code] as const] : []))),
    [nationByCode],
  )
  const backdrop = useBackdrop(snapshotPorts, capitals)
  // 0367: an armada at sea is ONE mark, under her name, carrying every hull of her fleets (armadaMarks.ts).
  const armadaList = useArmadas().armadas
  const fleets = useMemo(() => armadaMarks(mapFleetsOf(fleetViews), armadaList), [fleetViews, armadaList])
  const [selection, setSelection] = useState<MapSelection>(null)

  // THE SEAS, AS THE FLEET IN HAND MEETS THEM (useFleetSeas): which sea a pressed place lies in, and whether it is
  // closed to her. The chart itself does NOT shade the closed seas (owner, 2026-11-14: "north pacific ocean, south
  // pacific ocean color, square, not in sync"): the shade was the server's zone raster, squares of a second colour
  // on the water. The sea is one colour; a closed sea is said in words where it is pressed and on the Seas face.
  const seas = useFleetSeas()
  const seaCells = useSeaZoneCells(seas.bite && seas.judged)

  // HER WHOLE PATH WHEN ONE OF YOURS IS PRESSED (owner row 225): the leg she is on is her track; the queued stops
  // after it, or her standing route's lap, are drawn as the planned course with each stop numbered.
  const pressedView = selection?.kind === 'fleet' ? (fleetViews.find((f) => f.id === selection.id) ?? null) : null
  const shipPath = useShipPath(pressedView, nowMs)
  const pathD = useMemo(() => (shipPath.courses.length > 0 ? loopD(shipPath.courses) : null), [shipPath.courses])

  // ROUTE MODE (owner row 209, docs/ROUTE_BUILDER.md): the ONE exception to "the map never takes an order" beside the
  // Send fleet tray. Started from a fleet's tray (Set route); while it lasts a city tap adds a stop (nothing else answers
  // a tap), no tray opens, and the chart draws the route being built — numbered stops, the start said "Now", the stop
  // not yet kept "?". Cancel or Final ends it, and a tap selects exactly as before. useRouteBuilder.ts decides.
  const [routeFor, setRouteFor] = useState<string | null>(null)
  const routeView = routeFor !== null ? (fleetViews.find((f) => f.id === routeFor) ?? null) : null
  const route = useRouteBuilder(routeView)
  const routeTap = useRef<((code: string) => void) | null>(null)
  useEffect(() => {
    routeTap.current = routeView ? route.tap : null
  })
  // the stop cap is the routes book's served stop_max (the standing-route knob), which the store reads on every beat
  const startRoute = (id: string) => {
    setSelection(null)
    setRouteFor(id)
  }
  const endRoute = () => {
    route.reset()
    setRouteFor(null)
  }
  // A TRIP HANDED IN (routeSeed.ts; the build yard's "Plan trip"): route mode opens for that fleet with the stops kept.
  // Taken on the first frame the map is up, and whenever one is handed while it is up, as a go-to is.
  const takeSeed = useRef<() => void>(() => {})
  useEffect(() => {
    takeSeed.current = () => {
      const waiting = useRouteSeed.getState().request
      if (!waiting || !fleetViews.some((f) => f.id === waiting.fleetId)) return
      useRouteSeed.getState().take()
      setSelection(null)
      setRouteFor(waiting.fleetId)
      route.seed(waiting.fleetId, waiting.stops)
    }
  })
  const fleetsRead = fleetViews.length > 0
  useEffect(() => {
    if (!fleetsRead) return
    const frame = requestAnimationFrame(() => takeSeed.current())
    const unsubscribe = useRouteSeed.subscribe((s) => {
      if (s.request) takeSeed.current()
    })
    return () => {
      cancelAnimationFrame(frame)
      unsubscribe()
    }
  }, [fleetsRead])
  const finalRoute = async () => {
    const id = routeFor
    if (!(await route.final()) || id === null) return
    endRoute()
    // her track now shows the queue: the fleet is selected, as a tap on her hull does
    selectFleet(id)
    setSelection({ kind: 'fleet', id })
  }
  // REPEAT (B4): the kept stops, as a loop, in THE route editor (live/RouteEditor.tsx) on the one pop-up page, over the
  // chart. Back (or the editor's Cancel) returns to the builder with every stop still kept; a route that started ends
  // route mode and selects her, so her lap is what the chart draws.
  const [repeatStops, setRepeatStops] = useState<readonly string[] | null>(null)
  const closeRepeat = useCallback(() => setRepeatStops(null), [])
  const repeatDone = (started?: boolean) => {
    const id = routeFor
    setRepeatStops(null)
    if (!started || id === null) return
    endRoute()
    selectFleet(id)
    setSelection({ kind: 'fleet', id })
  }
  const routeCourses = useMemo(() => route.legs.map((l) => l.path.map(([lat, lon]) => ({ lat, lon }))), [route.legs])
  const routeD = useMemo(() => (routeCourses.length > 0 ? loopD(routeCourses) : null), [routeCourses])
  const keptCount = route.kept.length
  const routeStops = useMemo<readonly PathStop[]>(() => {
    const out: PathStop[] = []
    const first = route.legs[0]?.path[0]
    if (first) out.push({ at: { lat: first[0], lon: first[1] }, n: 0, days: null, label: tNow('desk.now') })
    route.legs.forEach((leg, i) => {
      const end = leg.path[leg.path.length - 1]
      if (end) out.push({ at: { lat: end[0], lon: end[1] }, n: i + 1, days: null, ...(i >= keptCount ? { label: '?' } : {}) })
    })
    return out
  }, [route.legs, keptCount])

  // THE OPEN MERCHANT'S CARD — read once here, for the sheet AND for her leg on the chart (the
  // card serves her full course; every other merchant is served the current segment only).
  const merchantId = selection?.kind === 'merchant' ? selection.id : null
  // 0310: a cargo ship is tapped like a merchant, and has a card of her own.
  const cargoId = merchantId !== null && trafficRows.find((t) => t.id === merchantId)?.kind === 'CARGO_SHIP' ? merchantId : null
  // 0331: a navy ship too.
  const navyId = merchantId !== null && trafficRows.find((t) => t.id === merchantId)?.kind === 'NAVY' ? merchantId : null
  // 0339: a pirate ship too.
  const pirateId = merchantId !== null && trafficRows.find((t) => t.id === merchantId)?.kind === 'PIRATE' ? merchantId : null
  const { card } = useMerchantCard(cargoId === null && navyId === null && pirateId === null ? merchantId : null)
  const cargoCard = useCargoShipCard(cargoId)
  const navyCard = useNavyShipCard(navyId)
  const pirateCard = usePirateShipCard(pirateId)
  const traffic = useMemo(
    () =>
      mapTrafficOf(
        trafficRows,
        card && card.fleet.id === merchantId
          ? { id: card.fleet.id, voyage: card.fleet.voyage, legs: card.route?.legs ?? null }
          : null,
      ),
    [trafficRows, card, merchantId],
  )
  // THE OPENING VIEW frames WHAT YOU HAVE, taken from a model AT MOUNT, once: it is the frame
  // ⌖ returns to, and a frame that moved with the fleets would re-frame the chart on every read.
  // It reads the ports on the WORLD coast (the backdrop's), never the shore on the glass: the frame
  // decides the view, and the shore on the glass is decided by the view.
  const [openingModel] = useState(() => buildChartModel(fleets, backdrop.ports, [], { nowMs, readAtMs: readAt }, traffic, trafficReadAt))
  const frameBounds = useCallback(
    (aspect: number) => openingBounds(openingModel.focusPoints, openingModel.motionPoints, backdrop.ports, aspect),
    [openingModel, backdrop.ports],
  )
  const chartRef = useRef<HTMLDivElement>(null)
  // THE SURFACE COMES BEFORE THE MODEL (2026-11-14), because the ports the model is built from are
  // set on the shore that is on the glass (useChartShore), and that shore is the view's. The tap is
  // therefore handed over as one stable function that calls the real one (`onTap`, below, which
  // needs the model): the surface never sees it change.
  const tapRef = useRef<((at: Point, unitsPerPx: number, view: ViewBox, presses: number) => void) | null>(null)
  const tap = useCallback((at: Point, unitsPerPx: number, view: ViewBox, presses: number) => tapRef.current?.(at, unitsPerPx, view, presses), [])
  const surface = useChartSurface(chartRef, frameBounds, tap)
  const box = surface.viewBox
  // THE PORTS AS THIS VIEW DRAWS THEM: on the fine shore close in, on the world coast when wide
  // (src/chart/useChartShore.ts). One list, read by the model, the hit test and the picture.
  const shore = useChartShore(backdrop, box ?? NO_VIEW, surface.unitsPerPx)
  const ports = shore.ports
  const portsByCode = useMemo(() => new Map(ports.map((p) => [p.code, p])), [ports])
  const model = useMemo(
    () => buildChartModel(fleets, ports, [], { nowMs, readAtMs: readAt }, traffic, trafficReadAt),
    [fleets, ports, nowMs, readAt, traffic, trafficReadAt],
  )

  // THE BATTLES BEING FOUGHT (0364, owner row 321): each is a red ring round its fleets (src/chart/fightRings.ts),
  // and a press on a ring opens the fight (src/live/FightSheet.tsx). Asked only while this screen is mounted.
  const fightCards = useFights()
  const fights = useMemo(() => mapFightsOf(fightCards), [fightCards])

  // THE ONLY THING A TAP ON THE CHART DOES: a selection. Nearest glyph within reach wins (the
  // reach is src/chart/glyphs.ts's); the same thing again, or deep inland, clears it; open water
  // SELECTS that water, snapped to the nearest sailable cell (0039) — water by construction, and
  // only on the SECOND press (row 172, below).
  const onTap = useCallback(
    (at: Point, unitsPerPx: number, view: ViewBox, presses: number) => {
      // The FULL marks answer at the full reach; the DOTS at half a touch, behind a mark as
      // near (row 104: a dot is the city it stands for — but never at a named harbour's
      // expense, the theft row 94 measured; chartModel.ts `portMarks`, hitTest.ts).
      const minTier = minTierForSpan(view.width)
      const tappable = visiblePorts(ports, model.portRoles, view, minTier)
      const dots = dotPorts(ports, model.portRoles, view, minTier)
      // THE MERCHANTS THE SHEET DREW — the same thinning the picture applied (shipMarks), so a tap
      // can only land on a hull that is actually on the paper.
      const drawn = shipMarks(model.fleets, model.traffic, view, unitsPerPx)
      const hit = hitTest(model, tappable, at, GLYPH.hitRadius * unitsPerPx, dots, GLYPH.dotHitRadius * unitsPerPx, drawn.traffic, placedNames())
      // ROUTE MODE: only a harbour answers (no hull, no merchant can steal the tap), and it is the next stop.
      if (routeTap.current) {
        const city = hitTest({ ...model, fleets: [] }, tappable, at, GLYPH.hitRadius * unitsPerPx, dots, GLYPH.dotHitRadius * unitsPerPx, [], placedNames())
        if (city?.kind === 'port') routeTap.current(city.code)
        return
      }
      // A MERCHANT IS READ, NEVER COMMANDED: her tap selects her and leaves the command draft alone.
      // A BATTLE'S RING (0364): the whole circle is its press target. A city's NAME under it is still the city (the
      // name is what the thumb was on); a small ring takes every other press inside it, and a wide one leaves a
      // harbour, a merchant or a fleet that is not in the battle its own press (`fightTapWins`).
      const onName = placedNames().some((n) => at.x >= n.box.x && at.x <= n.box.x + n.box.width && at.y >= n.box.y && at.y <= n.box.y + n.box.height)
      const ring = onName ? null : fightAt(fightRings(fights, unitsPerPx), at, unitsPerPx)
      // THE RIM of a wide ring is the fight's too, off the mark's own centre (fightRimWins): where the mark under the press stands
      const under: LatLon | null =
        hit?.kind === 'port'
          ? ([...tappable, ...dots].find((p) => p.code === hit.code) ?? null)
          : hit?.kind === 'fleet'
            ? (model.fleets.find((f) => f.fleet.id === hit.id)?.at ?? null)
            : hit?.kind === 'merchant'
              ? (drawn.traffic.find((f) => f.fleet.id === hit.id)?.at ?? null)
              : null
      const tapWins = ring !== null && fightTapWins(ring, hit === null ? null : hit.kind === 'port' ? { kind: 'port' } : hit.kind === 'fleet' || hit.kind === 'merchant' ? { kind: hit.kind, id: hit.id } : null)
      if (ring && (tapWins || fightRimWins(ring, at, under, unitsPerPx))) {
        setSelection((current) => toggleSelection(current, { kind: 'fight', id: ring.id }))
        return
      }
      if (hit?.kind === 'fleet') selectFleet(hit.id)
      if (hit) {
        setSelection((current) => toggleSelection(current, hit))
        return
      }
      // A POINT OF OPEN WATER ANSWERS TO A DOUBLE PRESS (owner row 172, 2026-10-20: *"When I press
      // a map, it shows the coordinate. But this is uncomfortable feature since I want to just move
      // around. Show coordinate when pressed twice."*). A single press on the water therefore does
      // what the owner asked the map to do when he touches it — nothing but what the hand did, a
      // pan — except that it still CLEARS whatever was open, which is the dismiss gesture every
      // map has and the one thing a player cannot do any other way on a phone. The count is the
      // surface's (useChartSurface's `presses`), so the rule is written once and the chart's other
      // targets are untouched: a harbour, a hull and a merchant all still answer the first press.
      if (presses < 2) {
        setSelection(null)
        return
      }
      const sea = snapSeaPoint(seaNav, unproject(at))
      setSelection(sea ? { kind: 'sea', at: sea } : null)
    },
    [model, ports, selectFleet, seaNav, fights],
  )

  useEffect(() => {
    tapRef.current = onTap
  }, [onTap])

  // THE REGIONS FILTER (row 93): off is the map as it was; on hands the tints to the picture.
  const regionsOn = useRegionsFilter()
  // 0143 (D14) asked for the flags with Regions on only. The owner, 2026-10-18: "beside the name show
  // flag that are influenced by" — every harbour's name carries the bundled flag of the nation that
  // holds it, at every zoom; measured legible and clean at 1440×900 and 390×844 (PR screenshots).
  const portFlags = usePortFlags(true)
  const allegiance = useWorld((s) => s.allegiance)
  const loadAllegiance = useWorld((s) => s.loadAllegiance)
  const openPort = selection?.kind === 'port' ? selection.code : null
  // A city panel that opens reads the flags again (they change once a day; the beat asks hourly).
  useEffect(() => {
    if (openPort !== null) void loadAllegiance()
  }, [openPort, loadAllegiance])

  // THE MINIMAP ONLY WHEN THE PLAYER HAS LEFT THE OPENING FRAME (./frame.ts says why), UNLESS THE PLAYER HAS
  // RESIZED, FOLDED OR UNFOLDED IT ON PURPOSE (owner, 2026-11-14): then it obeys them at every zoom.
  const minimapPrefs = useMinimapPrefs()
  const aspect = surface.width > 0 && surface.height > 0 ? surface.width / surface.height : null
  const zoomed =
    aspect !== null &&
    surface.view !== null &&
    viewLeftFrame(surface.view, clampView(fitView(frameBounds(aspect), aspect), aspect))

  // WHAT THE TRAY IS ABOUT. A stable object per selection, so the send flow's effects key on it.
  const selectedFleet =
    selection?.kind === 'fleet' ? (model.fleets.find((f) => f.fleet.id === selection.id) ?? null) : null
  const place = useMemo(() => {
    if (selection?.kind === 'port') {
      const port = portsByCode.get(selection.code)
      return port ? { dest: { kind: 'port' as const, code: port.code, name: port.name }, port } : null
    }
    if (selection?.kind === 'sea') return { dest: { kind: 'sea' as const, at: selection.at }, port: null }
    return null
  }, [selection, portsByCode])
  // THE SEA THE PLACE IS IN, and the wall in it for the fleet in hand: named on the tray, so a press on shaded water
  // says why it is shaded. A harbour is judged at its roads, as the sail door judges it.
  const placeSea = useMemo(() => {
    if (!place || !seaCells) return null
    const at = place.port ? place.port.roadstead : place.dest.kind === 'sea' ? place.dest.at : null
    const code = at ? zoneAt(seaCells, at.lat, at.lon) : null
    const row = code === null ? null : (seas.rows.find((r) => r.zone.code === code) ?? null)
    return row ? { name: row.zone.name, wall: row.wall } : null
  }, [place, seaCells, seas.rows])
  const placePortCode = place?.port?.code ?? null
  const placePortId = placePortCode ? (snapshotPorts.find((p) => p.code === placePortCode)?.id ?? null) : null
  // A MERCHANT OPENED FROM THE CITY'S LIST (2026-10-13) is remembered WITH the harbour she was
  // opened from: once she is the selection the city is not, and her row — the sheet's peek line,
  // and the only place a RESTING merchant is served at all (the sea window drops her) — would be
  // gone with it. So the harbour's read stays asked for while her sheet is open.
  const [viaHarbour, setViaHarbour] = useState<{ id: string; code: string; fleet: string } | null>(null)
  const harbourId = placePortId ?? (merchantId !== null && viaHarbour?.fleet === merchantId ? viaHarbour.id : null)
  const harbourCode = placePortCode ?? (merchantId !== null && viaHarbour?.fleet === merchantId ? viaHarbour.code : null)
  const merchantsHere = useMerchantsHere(harbourId)
  // EVERY merchant the harbour concerns goes to the tray, unfiltered (owner, 2026-10-14: *"i press
  // a city and i see no ship info"* — a filter to the ones lying here left almost every city blank
  // once 0116 cut a rest to two minutes). The tray groups them (src/live/merchantGroups.ts).
  const harbourRows = merchantsHere.view?.enabled && merchantsHere.view.port === harbourCode ? merchantsHere.view.merchants : NO_MERCHANTS
  // Her row: the sea window's when she is on the water, else the harbour's own (a resting
  // merchant is served by the harbour and by nothing else — chartModel.ts, 2026-10-13).
  const selectedMerchant = merchantId
    ? (trafficRows.find((t) => t.id === merchantId) ?? harbourRows.find((t) => t.id === merchantId) ?? null)
    : null
  // the battle whose ring was pressed: its served card, kept as last served once the ring has left the map, so a
  // reader of the result is not shut out when the server stops serving it
  const fightId = selection?.kind === 'fight' ? selection.id : null
  const servedFight = fightId !== null ? (fightCards.find((c) => c.id === fightId) ?? null) : null
  const [keptFight, setKeptFight] = useState(servedFight)
  if (servedFight !== null && servedFight !== keptFight) setKeptFight(servedFight)
  const openFight = fightId !== null ? (servedFight ?? (keptFight?.id === fightId ? keptFight : null)) : null
  const panelOpen = selectedFleet !== null || selectedMerchant !== null || place !== null || openFight !== null

  // ── GO TO (src/chart/goTo.ts) — this screen is the one taker ──────────────────────────────────
  // A request is resolved to a coordinate through THIS chart's model — `goToPoint`'s rule, handed
  // the model and the served rows: a harbour by its code; a fleet or a merchant by the mark the
  // chart drew for her, else by her own row (a merchant resting in a harbour is not drawn, and
  // neither is one outside the capped sea window). Then the zoom glide carries the view there and
  // the marker rings it. Nothing is selected or closed: the panel the link was in stays as it was —
  // unless the side panels leave too little clear glass (a phone), when they FOLD, still mounted,
  // until the tab at the edge or the next tap on the chart brings them back.
  const [mark, setMark] = useState<{ at: LatLon; seq: number } | null>(null)
  const [foldedFor, setFoldedFor] = useState<{ selection: MapSelection } | null>(null)
  const folded = panelOpen && foldedFor !== null && foldedFor.selection === selection
  const take = useRef<(request: { target: GoToTarget; seq: number }) => void>(() => {})
  useEffect(() => {
    const portAt = (code: string): LatLon | null => {
      const p = portsByCode.get(code)
      return p ? { lat: p.lat, lon: p.lon } : null
    }
    // THE RESOLUTION IS `goToPoint`'s (src/chart/goTo.ts), not this screen's: this hands it the
    // three questions it may ask of the live chart and nothing else.
    const resolve = (t: GoToTarget): LatLon | null =>
      goToPoint(t, {
        portAt,
        drawnAt: (id) =>
          (model.fleets.find((f) => f.fleet.id === id) ?? model.traffic.find((f) => f.fleet.id === id))?.at ?? null,
        rowOf: (id) => harbourRows.find((r) => r.id === id) ?? trafficRows.find((r) => r.id === id) ?? null,
      })
    take.current = (request) => {
      const at = resolve(request.target)
      const element = chartRef.current
      if (!at || !element) return
      // How much glass the side panels leave clear, measured off the page (they fold and slide).
      const rect = element.getBoundingClientRect()
      let clear = rect.width
      for (const node of element.querySelectorAll('[data-tray-mode="side"], [data-tray-mode="side-next"]')) {
        clear = Math.min(clear, node.getBoundingClientRect().left - rect.left)
      }
      let u = 0.5
      let clearShare = 1
      if (clear < rect.width - 1) {
        if (clear >= GOTO_MIN_CLEAR_PX) {
          u = clear / 2 / rect.width
          clearShare = clear / rect.width
        } else setFoldedFor({ selection })
      }
      // How close it lands is chartView.ts `goToSpan`'s, the one rule (a readable band).
      surface.glideTo(at, (current) => goToSpan(current, clearShare), u)
      setMark({ at, seq: request.seq })
    }
  })
  const measured = surface.view !== null
  useEffect(() => {
    if (!measured) return
    useGoTo.setState((s) => ({ charts: s.charts + 1 }))
    const run = () => {
      const request = useGoTo.getState().take()
      if (request) take.current(request)
    }
    // A request held while the tab was down is taken on the first frame the view is committed.
    const frame = requestAnimationFrame(run)
    const unsubscribe = useGoTo.subscribe((s) => {
      if (s.request) run()
    })
    return () => {
      cancelAnimationFrame(frame)
      unsubscribe()
      useGoTo.setState((s) => ({ charts: s.charts - 1 }))
    }
  }, [measured])
  useEffect(() => {
    if (!mark) return
    const id = window.setTimeout(() => setMark(null), GOTO_MARK_MS)
    return () => window.clearTimeout(id)
  }, [mark])

  return (
    <>
    <div
      ref={chartRef}
      {...surface.handlers}
      data-panels-folded={folded || undefined}
      // `touchClass` is the hook's (posture and `touch-action` are ONE fact); `bv-sea` paints the
      // frames before `box` is measured, so nothing flashes where the sea will be.
      className={`bv-sea relative h-full w-full ${surface.touchClass} select-none overflow-hidden`}
      data-testid="map-chart"
    >
      {box && (
        <ChartCanvas
          model={model}
          ports={ports}
          box={box}
          unitsPerPx={surface.unitsPerPx}
          coast={shore.coast}
          seas={backdrop.seas}
          regions={regionsOn ? backdrop.regions : null}
          portFlags={portFlags}
          islets={shore.islets}
          fights={fights}
          selection={selection}
          plannedD={routeView ? routeD : pathD}
          pathStops={routeView ? routeStops : shipPath.stops}
          // Every `CHART_CHROME` box, so no harbour's name prints under the pill, the zoom column,
          // the minimap or the tray.
          keepOut={surface.chromeBoxes}
          ariaLabel={t('map.chartLabel')}
          className="absolute inset-0 h-full w-full"
        />
      )}

      {mark && box && <GoToMarker key={mark.seq} at={mark.at} box={box} width={surface.width} height={surface.height} />}

      {/* THE CHROME LAYER — corners only; pointer-transparent itself so it can never swallow a
          pan, and each child that is meant to be pressed turns pointer events back on.
          ITS RIGHT EDGE GIVES WAY TO AN OPEN SIDE TRAY from `lg` (screenLayout.ts
          `chromeAsideSideTrayClass`), so the zoom column and Regions are never left underneath the
          panel; below `lg` the panel covers the glass and the chrome keeps its full width under it. */}
      <div
        className={`pointer-events-none absolute inset-0 z-10 ${
          panelOpen && !folded ? chromeAsideSideTrayClass() : ''
        }`}
      >
        {surface.width > 0 && (
          <FleetsCorner
            model={model}
            portsByCode={portsByCode}
            selectedId={selection?.kind === 'fleet' ? selection.id : null}
            nowMs={nowMs}
            // Selecting from the LIST also brings the chart to her — a view change and nothing else.
            onSelect={(id) => {
              // in route mode the list only brings the chart to her: no tray opens until the route is ended
              if (routeFor === null) {
                selectFleet(id)
                setSelection((current) => toggleSelection(current, { kind: 'fleet', id }))
              }
              const target = model.fleets.find((f) => f.fleet.id === id)
              if (target) surface.centreOn(target.at)
            }}
          />
        )}

        <ViewControls
          surface={surface}
          findAriaLabel={t('map.findFleets')}
          findTestId="map-find"
          testId="map-view-controls"
        />

        {/* THE CORNER: where the mouse is (./PointerCoords.tsx), a missing coast, and the minimap. */}
        {(
          <div className="pointer-events-auto absolute bottom-3 left-3 flex flex-col items-start gap-1">
            <PointerCoords chart={chartRef} box={box} />
            {backdrop.error && <p className="text-t-caption text-ink-faint">{t('map.noCoast')}</p>}
            {(zoomed || minimapChosen(minimapPrefs)) && surface.width > 0 && (
              <Minimap
                model={model}
                ports={ports}
                coast={backdrop.coast}
                viewport={box}
                onJump={surface.centreOn}
                ariaLabel={t('map.overview')}
                glass={{ width: surface.width, height: surface.height }}
                words={{ fold: t('map.miniFold'), open: t('map.miniOpen'), size: t('map.miniSize') }}
              />
            )}
          </div>
        )}
      </div>

      {/* THE FOLDED PANELS' TAB (a go-to on a narrow glass): one press brings them back. */}
      {folded && (
        <button
          type="button"
          {...CHART_CHROME}
          onClick={() => setFoldedFor(null)}
          aria-label={t('map.showPanel')}
          data-testid="map-unfold"
          className="absolute right-0 top-1/2 z-20 flex h-14 w-8 -translate-y-1/2 items-center justify-center rounded-l-control bg-surface text-ink-muted shadow-sheet"
        >
          <Icon name="chevron" size={18} className="rotate-180" />
        </button>
      )}

      {/* THE TRAY — one at a time, keyed by what was tapped so the next tap starts it at peek. */}
      {routeView && (
        <RouteBar
          fleetName={routeView.name}
          route={route}
          name={(code) => portsByCode.get(code)?.name ?? code}
          onCancel={endRoute}
          onFinal={() => void finalRoute()}
          onRepeat={setRepeatStops}
        />
      )}
      {selectedFleet && !routeView && (
        <VoyageTray
          key={selectedFleet.fleet.id}
          fleet={selectedFleet}
          portsByCode={portsByCode}
          nowMs={nowMs}
          onClose={() => setSelection(null)}
          onSetRoute={() => startRoute(selectedFleet.fleet.id)}
        />
      )}
      {selectedMerchant && cargoId !== null && (
        <CargoSheet
          key={selectedMerchant.id}
          mode="side"
          card={cargoCard && cargoCard.fleet.id === selectedMerchant.id ? cargoCard : null}
          line={<PlaceLine parts={merchantParts(selectedMerchant, (c) => portsByCode.get(c)?.name ?? c, nowMs)} />}
          onClose={() => setSelection(null)}
        />
      )}
      {selectedMerchant && navyId !== null && (
        <NavySheet
          key={selectedMerchant.id}
          mode="side"
          card={navyCard && navyCard.fleet.id === selectedMerchant.id ? navyCard : null}
          line={<PlaceLine parts={merchantParts(selectedMerchant, (c) => portsByCode.get(c)?.name ?? c, nowMs)} />}
          onClose={() => setSelection(null)}
        />
      )}
      {selectedMerchant && pirateId !== null && (
        <PirateSheet
          key={selectedMerchant.id}
          mode="side"
          card={pirateCard && pirateCard.fleet.id === selectedMerchant.id ? pirateCard : null}
          line={<PlaceLine parts={merchantParts(selectedMerchant, (c) => portsByCode.get(c)?.name ?? c, nowMs)} />}
          onClose={() => setSelection(null)}
        />
      )}
      {selectedMerchant && cargoId === null && navyId === null && pirateId === null && (
        <MerchantSheet
          key={selectedMerchant.id}
          mode="side"
          card={card && card.fleet.id === selectedMerchant.id ? card : null}
          line={<PlaceLine parts={merchantParts(selectedMerchant, (c) => portsByCode.get(c)?.name ?? c, nowMs)} />}
          onClose={() => setSelection(null)}
        />
      )}
      {openFight && !routeView && <FightSheet key={openFight.id} mode="side" card={openFight} onClose={() => setSelection(null)} />}
      {place && (
        <SendFleet
          key={place.dest.kind === 'port' ? place.dest.code : pointToken(place.dest.at)}
          dest={place.dest}
          sea={placeSea}
          line={place.port ? portLine(model, place.port, harbourRows, portNationOf(allegiance, place.port.code)) : t('map.openSea')}
          harbour={
            place.port && (
              <CityHarbour
                portCode={place.port.code}
                merchants={harbourRows}
                landed={merchantsHere.view !== null && (!merchantsHere.view.enabled || merchantsHere.view.port === harbourCode)}
                here={fleetsAtPort(model, place.port.code)}
                bound={fleetsBoundFor(model, place.port.code)}
                portsByCode={portsByCode}
                nowMs={nowMs}
                // A MERCHANT IS READ, NEVER COMMANDED — from the list exactly as from her hull.
                onOpenMerchant={(id) => {
                  if (placePortId && placePortCode) setViaHarbour({ id: placePortId, code: placePortCode, fleet: id })
                  setSelection({ kind: 'merchant', id })
                }}
                // YOURS opens her own panel, as a tap on her hull does.
                onOpenFleet={(id) => {
                  selectFleet(id)
                  setSelection({ kind: 'fleet', id })
                }}
              />
            )
          }
          onClose={() => setSelection(null)}
        />
      )}
    </div>
    {/* REPEAT'S PAGE stands BESIDE the chart's surface, not in it: a press or a wheel on the page is the page's, never
        a pan, a zoom or a tap on the sea under it. */}
    {routeView && repeatStops && (
      <DetailPage title={t('map.routeTitle')} onClose={closeRepeat} data-testid="route-repeat-page">
        <RouteEditor fleet={routeView} route={null} seed={repeatStops} onDone={repeatDone} />
      </DetailPage>
    )}
    </>
  )
}
