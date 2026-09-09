import { useCallback, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { unproject, type Point, type ViewBox } from '../../lib/geo'
import type { FleetView, SnapshotPort } from '../../lib/rpc'
import type { SeaNav } from '../../lib/sea'
import { pointToken, snapSeaPoint } from '../../domain/passage'
import { useShellState } from '../../app/shellState'
import { useWorld } from '../../live/worldStore'
// THE HAND-OFF SEAM — `domain/order`'s draft, the SAME one FLEETS, PORT and MARKET write into.
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
  hitTest,
  mapFleetsOf,
  mapPortsOf,
  Minimap,
  minTierForSpan,
  openingBounds,
  toggleSelection,
  useChartSurface,
  useCoastline,
  ViewControls,
  visiblePorts,
  type ChartModel,
  type MapPort,
  type MapSelection,
} from '../../chart'
import { ChartMessage } from './ChartMessage'
import { FleetsCorner } from './FleetsCorner'
import { FleetTray } from './FleetTray'
import { SendFleet } from './SendFleet'
import { viewLeftFrame } from './frame'

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
// send flow here (useSendFleet.ts) is a second CALLER of each, never a second authority; the only
// hand-off left is a refusal's fix that genuinely needs composing, through `domain/order`'s draft
// — the seam the other three screens use — never a store field, router state or a search param.
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

  // A FAILURE IS RENDERED, NEVER SPUN ON (DESIGN §F.5); an opening is one quiet line on the sea.
  if (phase === 'failed') return <ChartMessage refusal={fatal} />
  if (phase !== 'ready' || !snapshot || !seaNav) return <ChartMessage refusal={null} />

  // The chart mounts ONLY with the world in hand, so it can freeze its opening frame on real fleets.
  return <Chart ports={snapshot.ports} seaNav={seaNav} fleets={fleets} readAt={readAt} />
}

/** The one line beside a harbour's name at peek: its country, and which of yours are there. */
function portLine(model: ChartModel, port: MapPort): string {
  const here = fleetsAtPort(model, port.code).map((f) => f.fleet.name)
  const bound = fleetsBoundFor(model, port.code).map((f) => f.fleet.name)
  if (here.length > 0) return `${port.country} · ${here.join(', ')} here`
  if (bound.length > 0) return `${port.country} · ${bound.join(', ')} bound here`
  return port.country
}

function Chart({
  ports: snapshotPorts,
  seaNav,
  fleets: fleetViews,
  readAt,
}: {
  ports: readonly SnapshotPort[]
  /** The served navigable-water grid — the tap-on-open-water snap reads it (0039). */
  seaNav: SeaNav
  fleets: readonly FleetView[]
  readAt: number | null
}) {
  // THE ONE CLOCK (src/app/shellState.ts): it ticks a countdown's wording and 0075's drift.
  const { nowMs } = useShellState()
  const navigate = useNavigate()

  // WHICH HULL IS IN HAND is `domain/order`'s draft, app-wide; tapping a fleet here points it.
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  const handOff = useCommandDraft((s) => s.handOff)
  const compose = useCallback(
    (intent: Parameters<typeof handOff>[0]) => {
      handOff(intent)
      navigate('/command')
    },
    [handOff, navigate],
  )

  const ports = useMemo(() => mapPortsOf(snapshotPorts), [snapshotPorts])
  const portsByCode = useMemo(() => new Map(ports.map((p) => [p.code, p])), [ports])
  const fleets = useMemo(() => mapFleetsOf(fleetViews), [fleetViews])
  const model = useMemo(
    () => buildChartModel(fleets, ports, [], { nowMs, readAtMs: readAt }),
    [fleets, ports, nowMs, readAt],
  )

  const [selection, setSelection] = useState<MapSelection>(null)

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
  // SELECTS that water, snapped to the nearest sailable cell (0039) — water by construction.
  const onTap = useCallback(
    (at: Point, unitsPerPx: number, view: ViewBox) => {
      const tappable = visiblePorts(ports, model.portRoles, view, minTierForSpan(view.width))
      const hit = hitTest(model, tappable, at, GLYPH.hitRadius * unitsPerPx)
      if (hit?.kind === 'fleet') selectFleet(hit.id)
      if (hit) {
        setSelection((current) => toggleSelection(current, hit))
        return
      }
      const sea = snapSeaPoint(seaNav, unproject(at))
      setSelection(sea ? { kind: 'sea', at: sea } : null)
    },
    [model, ports, selectFleet, seaNav],
  )

  const surface = useChartSurface(chartRef, frameBounds, onTap)
  const box = surface.viewBox
  const coastline = useCoastline()

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

  return (
    <div
      ref={chartRef}
      {...surface.handlers}
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
          coastlineD={coastline.data?.d ?? ''}
          selection={selection}
          // Every `CHART_CHROME` box, so no harbour's name prints under the pill, the zoom column,
          // the minimap or the tray.
          keepOut={surface.chromeBoxes}
          ariaLabel="Chart of the world's harbours and the sea lanes between them, showing your fleets"
          className="absolute inset-0 h-full w-full"
        />
      )}

      {/* THE CHROME LAYER — corners only; pointer-transparent itself so it can never swallow a
          pan, and each child that is meant to be pressed turns pointer events back on. */}
      <div className="pointer-events-none absolute inset-0 z-10">
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
          findAriaLabel="Find your fleets"
          findTestId="map-find"
          testId="map-view-controls"
        />

        {(zoomed || coastline.error) && (
          <div className="pointer-events-auto absolute bottom-3 left-3 flex flex-col items-start gap-1">
            {coastline.error && <p className="text-t-caption text-ink-faint">coastline unavailable</p>}
            {zoomed && (
              <Minimap
                model={model}
                ports={ports}
                coastlineD={coastline.data?.d ?? ''}
                viewport={box}
                onJump={surface.centreOn}
                ariaLabel="The whole world, your fleets marked on it, and the part of it this chart is showing. Tap a place to look there."
              />
            )}
          </div>
        )}
      </div>

      {/* THE TRAY — one at a time, keyed by what was tapped so the next tap starts it at peek. */}
      {selectedFleet && (
        <FleetTray
          key={selectedFleet.fleet.id}
          fleet={selectedFleet}
          portsByCode={portsByCode}
          nowMs={nowMs}
          onClose={() => setSelection(null)}
        />
      )}
      {place && (
        <SendFleet
          key={place.dest.kind === 'port' ? place.dest.code : pointToken(place.dest.at)}
          dest={place.dest}
          line={place.port ? portLine(model, place.port) : 'Open sea'}
          onClose={() => setSelection(null)}
          onCompose={compose}
        />
      )}
    </div>
  )
}
