import { useCallback, useMemo, useRef, useState } from 'react'
import { Button, Notice } from '../../components/ui'
import { formatRealShort } from '../../lib/format'
import type { Point, ViewBox } from '../../lib/geo'
import type { FleetView, Refusal, SnapshotConfig, SnapshotLeg, SnapshotPort } from '../../lib/rpc'
import { useShellState } from '../../app/shellState'
import { useWorld } from '../../live/worldStore'
import { CoastlineLayer } from './CoastlineLayer'
import { DetailPanel } from './DetailPanel'
import { FleetsLayer, TracksLayer } from './FleetsLayer'
import { FleetsPanel } from './FleetsPanel'
import { LabelsLayer } from './LabelsLayer'
import { LegsLayer } from './LegsLayer'
import { PortsLayer } from './PortsLayer'
import {
  COMPACT_WIDTH_PX,
  LABEL_SPAN_LIMIT,
  LEG_SPAN_LIMIT,
  minTierForSpan,
  openingBounds,
} from './chartView'
import { buildChartModel, visiblePorts } from './chartModel'
import { GLYPH } from './glyphs'
import { hitTest, toggleSelection } from './hitTest'
import { mapLabelRequests, planLabels } from './labels'
import { mapFleetsOf, mapPortsOf } from './liveWorld'
import type { MapSelection } from './mapTypes'
import { legWebPath } from './route'
import { CHART_CHROME, useChartSurface } from './useChartSurface'
import { useCoastline } from './useCoastline'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// MAP — READ-ONLY, BY DESIGN AND FOREVER.
//
// The chart shows where fleets are and where they are sailing. It accepts no input that changes
// the world: no click-to-move, no drag-a-route, no context menu, no order composed on a marker.
// Orders are written on the Command tab, in words.
//
// This is not a temporary limitation of the skeleton — it is the game's shape. byeharu's map grew
// commands and the movement rules then had to be re-derived on the map's terms; the map became the
// hardest surface in the app because it was doing two jobs. Here it does one: it tells you where
// things are. Any future pull to "just let them tap the port to sail there" adds a second place
// orders come from, and there is exactly one.
//
// ── WHERE THE PICTURE COMES FROM ───────────────────────────────────────────────────────────────
// The live world, and nowhere else (src/live/worldStore.ts):
//   snapshot.ports  214 real harbours with Wikidata coordinates and a `size_tier`
//   snapshot.legs   782 sea lanes whose distances are SAILED distances
//   world.fleets    your fleets — and for one at sea, `voyage.position`, the closed form of §D.2
//   snapshot.config the time compression printed in the caption, rather than a number typed here
// ./liveWorld.ts is the only module that has seen the wire format. The stub it replaced
// (sampleVoyages.ts: twelve invented ports, four invented fleets) is deleted.
//
// ── NOTHING ON THIS SCREEN MOVES BY ITSELF ─────────────────────────────────────────────────────
// The position is the SERVER's, copied. There is no client clock driving a glyph, no per-frame
// re-derivation, no animation state — the old ./voyage.ts and its rAF clock are deleted, because a
// second implementation of the movement rule on this side of the wire is exactly what the live
// store's third rule forbids. A read is the catch-up, so the picture changes when the world is read
// again, and the caption says how long ago that was rather than pretending to be live.
// The ONE clock-dependent thing left is the wording of a countdown, against the server's own `eta`.
//
// ── WHAT IS ON THIS SCREEN, AND WHAT IS NOT ────────────────────────────────────────────────────
//   drawn   one pale coastline · the sea lanes, close in only · three glyphs (port, fleet,
//           destination) · a dotted track for the CURRENT leg · two corner panels · a caption
//   absent  OTHER PLAYERS. §E.5: drawing rivals would make the chart a targeting surface, and
//           there is no PvP (§J.2). No prop on any layer here can carry one.
//   absent  the planned route beyond the current leg — the server does not serve it (README §4.8),
//           so the destination is RINGED and no line is drawn to it. The chart never invents water.
//   absent  every control that is not pan, zoom, fold or dismiss.
//
// ── 214 PORTS ON ONE SHEET ─────────────────────────────────────────────────────────────────────
// Three rules, all keyed on one column and one number:
//   1. the zoom sets a `size_tier` floor (PORT_TIER_BANDS) — the world shows the 35 great ports,
//      a sea adds the 79 middling, a coast adds all 100 small ones. YOUR ports are always drawn.
//   2. the mark is scaled by the tier (portMarkScale), so the hierarchy is visible, not implied.
//   3. names are planned as a SET over the visible ports only, dropped rather than overprinted,
//      and ranked by role first and tier second (./labels.ts).
//
// ── KEYBOARD AND SCREEN READERS ────────────────────────────────────────────────────────────────
// The chart itself is `role="img"` with a description, and it holds NO focusable elements. That is
// a decision, not an omission: dozens of invisible tab stops on a picture is worse than none, and
// everything the chart says is also said in the panels — the fleet list names every fleet, where
// it is and when it arrives, as ordinary keyboard-reachable buttons, and selecting one there fills
// the same detail panel a tap does. Nothing on this screen is reachable ONLY by pointer.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function MapScreen() {
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)
  const snapshot = useWorld((s) => s.snapshot)
  const fleets = useWorld((s) => s.fleets)
  const readAt = useWorld((s) => s.readAt)

  // A FAILURE IS RENDERED, NEVER SPUN ON. The refusal arrives with a code and a sentence a player
  // can read (DESIGN §F.5); printing it here is the whole handling.
  if (phase === 'failed') return <ChartMessage refusal={fatal} />
  // Opening: one quiet line on the chart's own sea, so the tab does not flash a different surface
  // before settling. Never an endless spinner — the store's phase always resolves.
  if (phase !== 'ready' || !snapshot) return <ChartMessage refusal={null} />

  // The chart mounts ONLY with the world in hand. That is what lets it freeze its opening frame at
  // its own mount (see below) on real fleets rather than on an empty model.
  return (
    <Chart
      ports={snapshot.ports}
      legs={snapshot.legs}
      config={snapshot.config}
      fleets={fleets}
      readAt={readAt}
    />
  )
}

/** The chart's sea with one line on it: opening, or the reason it could not open. */
function ChartMessage({ refusal }: { refusal: Refusal | null }) {
  return (
    <div
      className="bv-sea flex h-full w-full items-center justify-center p-6"
      data-testid="map-chart"
    >
      {refusal ? (
        <Notice tone="danger" className="max-w-sm" data-testid="map-fatal">
          <span className="block font-mono text-[10px] uppercase tracking-wider">{refusal.code}</span>
          {refusal.sentence}
        </Notice>
      ) : (
        <p className="font-mono text-[11px] text-ink-faint" data-testid="map-loading">
          opening the chart…
        </p>
      )}
    </div>
  )
}

function Chart({
  ports: snapshotPorts,
  legs,
  config,
  fleets: fleetViews,
  readAt,
}: {
  ports: readonly SnapshotPort[]
  legs: readonly SnapshotLeg[]
  config: SnapshotConfig
  fleets: readonly FleetView[]
  readAt: number | null
}) {
  // THE ONE CLOCK (src/app/shellState.ts). It ticks a countdown's wording and nothing else on this
  // screen: no glyph, no track and no frame is a function of it.
  const { nowMs } = useShellState()

  const ports = useMemo(() => mapPortsOf(snapshotPorts), [snapshotPorts])
  const portsByCode = useMemo(() => new Map(ports.map((p) => [p.code, p])), [ports])
  const fleets = useMemo(() => mapFleetsOf(fleetViews), [fleetViews])
  const model = useMemo(() => buildChartModel(fleets, ports), [fleets, ports])

  const [selection, setSelection] = useState<MapSelection>(null)

  // THE OPENING VIEW frames WHAT YOU HAVE — your fleets and the ports they are using — not the 214
  // harbours of the world; and how much of it depends on the shape of the glass (openingBounds
  // carries the measured arithmetic, and the floor that stops a lone docked fleet opening on a
  // 1.5° harbour approach).
  //
  // Taken from the model AT MOUNT, once. It has to be stable: it is the frame the "fit" control
  // returns to, and a bounds that moved with the fleets would re-frame the chart under the player
  // every time the world was read.
  const [openingModel] = useState(() => model)
  const frameBounds = useCallback(
    (aspect: number) => openingBounds(openingModel.focusPoints, openingModel.motionPoints, ports, aspect),
    [openingModel, ports],
  )
  const chartRef = useRef<HTMLDivElement>(null)

  // THE ONLY THING A TAP ON THE CHART DOES. The nearest glyph within a 44 px reach wins
  // (./hitTest.ts explains why that is one function and not a touch circle per glyph); tapping the
  // same thing again, or tapping open water, clears the selection. The surface hands over the
  // scale AND the viewBox at the moment of the tap, so the reach is 44 px at every zoom and the
  // ports it tests are exactly the ports that were drawn — the same `visiblePorts` rule, applied
  // to the same box, with no second idea of what is on the sheet.
  //
  // A SELECTION IS A VIEW CHANGE AND NOTHING ELSE. There is no other callback on this surface.
  const onTap = useCallback(
    (at: Point, unitsPerPx: number, view: ViewBox) => {
      const tappable = visiblePorts(ports, model.portRoles, view, minTierForSpan(view.width))
      setSelection((current) =>
        toggleSelection(current, hitTest(model, tappable, at, GLYPH.hitRadius * unitsPerPx)),
      )
    },
    [model, ports],
  )

  const surface = useChartSurface(chartRef, frameBounds, onTap)
  const box = surface.viewBox

  // WHICH PORTS ARE ON THE PAPER — computed once, consumed by the marks and the names (and by the
  // tap above, from the same function). chartModel.visiblePorts: on the glass, and either big
  // enough for this zoom or one of yours.
  const drawnPorts = useMemo(
    () => (box ? visiblePorts(ports, model.portRoles, box, minTierForSpan(box.width)) : []),
    [box, ports, model.portRoles],
  )

  const selectedFleetId = selection?.kind === 'fleet' ? selection.id : null
  const selectedPortCode = selection?.kind === 'port' ? selection.code : null

  const coastline = useCoastline()

  // THE SEA LANES, close in only. Above LEG_SPAN_LIMIT the layer is not built and not rendered:
  // 782 crossings drawn from orbit is a spiderweb, not a chart. It is built over the DRAWN ports,
  // so a lane always joins two marks the player can see — never a line trailing off to a harbour
  // this zoom is too far out to draw.
  const legsD = useMemo(() => {
    if (!box || box.width > LEG_SPAN_LIMIT) return ''
    return legWebPath(legs, new Map(drawnPorts.map((p) => [p.code, p])), box)
  }, [box, legs, drawnPorts])

  // A phone is not a small desktop. Below `sm` the chart is ~390 px wide and a panel that opens by
  // default eats most of it, so the fleet list starts folded to its header chip there and open at
  // desktop widths (defect 3). `surface.width` is 0 until the box is measured, which is why the
  // panels wait for it — Collapsible reads `defaultOpen` once, at mount, so it must be right then.
  const compact = surface.width > 0 && surface.width < COMPACT_WIDTH_PX

  // EVERY NAME ON THE CHART, PLACED AS A SET. It is the visible ports plus the fleets × 8 candidate
  // sides, which is small because the visible set is small — and it is the only way two labels can
  // know about each other (see ./labels.ts for the overprinting this replaced).
  const labels = useMemo(
    () =>
      box
        ? planLabels(
            mapLabelRequests(model, drawnPorts, selection, box.width <= LABEL_SPAN_LIMIT),
            {
              viewBox: box,
              unitsPerPx: surface.unitsPerPx,
              fontSizePx: GLYPH.labelSize,
              gapPx: GLYPH.labelGapX,
              glyphRadiusPx: GLYPH.fleetHaloRadius,
            },
          )
        : [],
    [box, model, drawnPorts, selection, surface.unitsPerPx],
  )

  return (
    <div
      ref={chartRef}
      {...surface.handlers}
      // `touch-none` hands every touch to the pan/zoom handler instead of the page scroller;
      // `select-none` stops a drag across the chart highlighting the labels.
      className="bv-sea relative h-full w-full touch-none select-none overflow-hidden"
      data-testid="map-chart"
    >
      {box && (
        <svg
          className="absolute inset-0 h-full w-full"
          viewBox={`${box.x} ${box.y} ${box.width} ${box.height}`}
          role="img"
          aria-label="Chart of the world's harbours and the sea lanes between them, showing your fleets"
        >
          {/* PAINT ORDER IS THE ONLY STACKING SVG HAS: sea, coast, lanes, tracks, port marks, fleet
              dots, names. Every name therefore sits on top of every mark, and no mark sits on a
              name. The lanes go under everything — they are the paper's grain. */}
          <CoastlineLayer d={coastline.data?.d ?? ''} />
          <LegsLayer d={legsD} />
          <TracksLayer model={model} unitsPerPx={surface.unitsPerPx} />
          <PortsLayer
            ports={drawnPorts}
            portRoles={model.portRoles}
            selectedCode={selectedPortCode}
            unitsPerPx={surface.unitsPerPx}
          />
          <FleetsLayer model={model} selectedId={selectedFleetId} unitsPerPx={surface.unitsPerPx} />
          <LabelsLayer labels={labels} unitsPerPx={surface.unitsPerPx} />
        </svg>
      )}

      {/* PANEL ONE — top-left. Held back until the surface has been measured, so it mounts
          knowing whether it is on a phone (see `compact`). */}
      {surface.width > 0 && (
        <FleetsPanel
          model={model}
          portsByCode={portsByCode}
          selection={selection}
          nowMs={nowMs}
          compact={compact}
          // Selecting from the LIST also brings the chart to the fleet. The opening frame holds
          // what is moving, which on a phone can leave a fleet lying in a far-off port off the
          // glass; this is how you get to it, and it is still only a view change.
          onSelect={(id) => {
            setSelection((current) => toggleSelection(current, { kind: 'fleet', id }))
            const target = model.fleets.find((f) => f.fleet.id === id)
            if (target) surface.centreOn(target.at)
          }}
        />
      )}

      {/* PANEL TWO — bottom-right, and only when something is selected. */}
      <DetailPanel
        model={model}
        portsByCode={portsByCode}
        selection={selection}
        nowMs={nowMs}
        compact={compact}
        onDismiss={() => setSelection(null)}
      />

      {/* THE VIEW CONTROLS — the complete set. Top-right, in their own uncapped, unscrollable
          column, so nothing can ever put them out of reach (docs/CORE_REUSE.md §1.5). */}
      <div
        {...CHART_CHROME}
        className="absolute right-3 top-3 z-10 flex flex-col gap-1"
        data-testid="map-view-controls"
      >
        <Button
          variant="secondary"
          size="icon"
          aria-label="Zoom in"
          onClick={surface.zoomIn}
          className="bg-surface/90 backdrop-blur"
        >
          +
        </Button>
        <Button
          variant="secondary"
          size="icon"
          aria-label="Zoom out"
          onClick={surface.zoomOut}
          className="bg-surface/90 backdrop-blur"
        >
          −
        </Button>
        <Button
          variant="secondary"
          size="icon"
          aria-label="Frame your fleets"
          onClick={surface.fit}
          className="bg-surface/90 font-mono text-[10px] backdrop-blur"
        >
          fit
        </Button>
      </div>

      {/* THE PERMANENT CAPTION. Three facts the player should never have to work out or be told
          twice: the time scale (§D.3 asks for it here, always — and it is the SERVER's
          `time_compression`, not a number typed into this file), that this screen is a view and
          orders are given somewhere else (the owner asked for this explicitly), and WHEN the
          picture was read. That last one is the honest half of "the position is the server's": the
          chart is a reading, and a reading has an age.
          Pointer-transparent, so it can never swallow a pan gesture near the bottom edge. */}
      <div
        className="pointer-events-none absolute inset-x-0 bottom-0 z-10 flex items-center gap-2 bg-app/70 px-3 py-1.5 backdrop-blur"
        data-testid="map-is-a-view"
      >
        <span className="shrink-0 font-mono text-[10px] text-ink-faint">
          1 min = {config.time_compression / 60} h sail
        </span>
        <span className="min-w-0 truncate font-mono text-[10px] text-ink-muted">
          view only · orders on Command
        </span>
        {readAt !== null && (
          <span className="ml-auto shrink-0 font-mono text-[10px] text-ink-faint" data-testid="map-read-age">
            read {formatRealShort(nowMs - readAt)} ago
          </span>
        )}
      </div>

      {/* A missing backdrop is worth one quiet line, never a crash: the chart still works without
          it. Ports, fleets and tracks are all drawn from coordinates, not from this file. */}
      {coastline.error && (
        <p className="pointer-events-none absolute bottom-9 left-3 z-10 font-mono text-[10px] text-ink-faint">
          coastline unavailable
        </p>
      )}
    </div>
  )
}
