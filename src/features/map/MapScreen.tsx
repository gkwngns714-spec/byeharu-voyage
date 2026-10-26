import { Fragment, useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
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
import { MerchantSheet } from '../../live/MerchantSheet'
import { merchantParts } from '../../live/merchantLine'
import { useMerchantCard } from '../../live/useMerchantCard'
import { useMerchantsHere } from '../../live/useMerchantsHere'
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
  hitTest,
  placedNames,
  mapFleetsOf,
  loopD,
  mapTrafficOf,
  Minimap,
  minTierForSpan,
  openingBounds,
  shipMarks,
  toggleSelection,
  useBackdrop,
  useChartSurface,
  useRegionsFilter,
  ViewControls,
  visiblePorts,
  type ChartModel,
  type MapPort,
  type MapSelection,
} from '../../chart'
// The one table that says where a side tray stands, and therefore where the chrome stops.
import { chromeAsideSideTrayClass, Icon } from '../../components/ui'
import { ChartMessage } from './ChartMessage'
import { FleetsCorner } from './FleetsCorner'
import { VoyageTray } from './VoyageTray'
import { SendFleet } from './SendFleet'
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

export function MapScreen() {
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

  // A FAILURE IS RENDERED, NEVER SPUN ON (DESIGN §F.5); an opening is one quiet line on the sea.
  if (phase === 'failed') return <ChartMessage refusal={fatal} />
  if (phase !== 'ready' || !snapshot || !seaNav) return <ChartMessage refusal={null} />

  // The chart mounts ONLY with the world in hand, so it can freeze its opening frame on real fleets.
  return (
    <Chart
      ports={snapshot.ports}
      seaNav={seaNav}
      fleets={fleets}
      traffic={traffic?.enabled ? traffic.fleets : NO_TRAFFIC}
      readAt={readAt}
      trafficReadAt={trafficReadAt}
    />
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
  const backdrop = useBackdrop(snapshotPorts)
  const ports = backdrop.ports
  const portsByCode = useMemo(() => new Map(ports.map((p) => [p.code, p])), [ports])
  const fleets = useMemo(() => mapFleetsOf(fleetViews), [fleetViews])
  const [selection, setSelection] = useState<MapSelection>(null)

  // HER WHOLE PATH WHEN ONE OF YOURS IS PRESSED (owner row 225): the leg she is on is her track; the queued stops
  // after it, or her standing route's lap, are drawn as the planned course with each stop numbered.
  const pressedView = selection?.kind === 'fleet' ? (fleetViews.find((f) => f.id === selection.id) ?? null) : null
  const shipPath = useShipPath(pressedView, nowMs)
  const pathD = useMemo(() => (shipPath.courses.length > 0 ? loopD(shipPath.courses) : null), [shipPath.courses])

  // THE OPEN MERCHANT'S CARD — read once here, for the sheet AND for her leg on the chart (the
  // card serves her full course; every other merchant is served the current segment only).
  const merchantId = selection?.kind === 'merchant' ? selection.id : null
  const { card } = useMerchantCard(merchantId)
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
  const model = useMemo(
    () => buildChartModel(fleets, ports, [], { nowMs, readAtMs: readAt }, traffic, trafficReadAt),
    [fleets, ports, nowMs, readAt, traffic, trafficReadAt],
  )

  // THE OPENING VIEW frames WHAT YOU HAVE, taken from the model AT MOUNT, once: it is the frame
  // ⌖ returns to, and a frame that moved with the fleets would re-frame the chart on every read.
  const [openingModel] = useState(() => model)
  const frameBounds = useCallback(
    (aspect: number) => openingBounds(openingModel.focusPoints, openingModel.motionPoints, ports, aspect),
    [openingModel, ports],
  )
  const chartRef = useRef<HTMLDivElement>(null)

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
      const drawn = shipMarks(model.fleets, model.traffic, view)
      const hit = hitTest(model, tappable, at, GLYPH.hitRadius * unitsPerPx, dots, GLYPH.dotHitRadius * unitsPerPx, drawn.traffic, placedNames())
      // A MERCHANT IS READ, NEVER COMMANDED: her tap selects her and leaves the command draft alone.
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
    [model, ports, selectFleet, seaNav],
  )

  const surface = useChartSurface(chartRef, frameBounds, onTap)
  const box = surface.viewBox

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

  // THE MINIMAP ONLY WHEN THE PLAYER HAS LEFT THE OPENING FRAME (./frame.ts says why).
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
  const panelOpen = selectedFleet !== null || selectedMerchant !== null || place !== null

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
          coast={backdrop.coast}
          seas={backdrop.seas}
          regions={regionsOn ? backdrop.regions : null}
          portFlags={portFlags}
          islets={backdrop.islets}
          selection={selection}
          plannedD={pathD}
          pathStops={shipPath.stops}
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
              selectFleet(id)
              setSelection((current) => toggleSelection(current, { kind: 'fleet', id }))
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

        {(zoomed || backdrop.error) && (
          <div className="pointer-events-auto absolute bottom-3 left-3 flex flex-col items-start gap-1">
            {backdrop.error && <p className="text-t-caption text-ink-faint">{t('map.noCoast')}</p>}
            {zoomed && (
              <Minimap
                model={model}
                ports={ports}
                coast={backdrop.coast}
                viewport={box}
                onJump={surface.centreOn}
                ariaLabel={t('map.overview')}
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
      {selectedFleet && (
        <VoyageTray
          key={selectedFleet.fleet.id}
          fleet={selectedFleet}
          portsByCode={portsByCode}
          nowMs={nowMs}
          onClose={() => setSelection(null)}
        />
      )}
      {selectedMerchant && (
        <MerchantSheet
          key={selectedMerchant.id}
          mode="side"
          card={card && card.fleet.id === selectedMerchant.id ? card : null}
          line={<PlaceLine parts={merchantParts(selectedMerchant, (c) => portsByCode.get(c)?.name ?? c, nowMs)} />}
          onClose={() => setSelection(null)}
        />
      )}
      {place && (
        <SendFleet
          key={place.dest.kind === 'port' ? place.dest.code : pointToken(place.dest.at)}
          dest={place.dest}
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
  )
}
