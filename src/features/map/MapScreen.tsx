import { useCallback, useMemo, useRef, useState } from 'react'
import { Button } from '../../components/ui'
import type { Point } from '../../lib/geo'
import { CoastlineLayer } from './CoastlineLayer'
import { DetailPanel } from './DetailPanel'
import { FleetsLayer, TracksLayer } from './FleetsLayer'
import { FleetsPanel } from './FleetsPanel'
import { LabelsLayer } from './LabelsLayer'
import { PortsLayer } from './PortsLayer'
import { COMPACT_WIDTH_PX, LABEL_SPAN_LIMIT, openingBounds } from './chartView'
import { buildChartModel } from './chartModel'
import { GLYPH } from './glyphs'
import { hitTest, toggleSelection } from './hitTest'
import { mapLabelRequests, planLabels } from './labels'
import type { MapSelection } from './mapTypes'
import { V0_PORTS, V0_PORTS_BY_CODE, sampleFleets } from './sampleVoyages'
import { CHART_CHROME, useChartSurface } from './useChartSurface'
import { useCoastline } from './useCoastline'
import { useWallClock } from './useWallClock'

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
// ── WHAT IS ON THIS SCREEN, AND WHAT IS NOT ────────────────────────────────────────────────────
//   drawn   one pale coastline · three glyphs (port, fleet, destination) · a dotted track per
//           fleet at sea · two corner panels · a permanent caption
//   absent  OTHER PLAYERS. §E.5: drawing rivals would make the chart a targeting surface, and
//           there is no PvP (§J.2). No prop on any layer here can carry one.
//   absent  every control that is not pan, zoom, fold or dismiss.
//
// ── THE ONE THING THAT MOVES ───────────────────────────────────────────────────────────────────
// `nowMs` is a wall-clock reading sampled per animation frame (./useWallClock.ts). `buildChartModel`
// turns it into the whole picture through the closed form of §D.2 (./voyage.ts). NOTHING between
// them remembers anything: leave the tab for an hour and the first frame back draws the fleet
// exactly where the arithmetic says it is, because no timer was counting in the meantime.
//
// ── KEYBOARD AND SCREEN READERS ────────────────────────────────────────────────────────────────
// The chart itself is `role="img"` with a description, and it holds NO focusable elements. That is
// a decision, not an omission: sixteen invisible tab stops on a picture is worse than none, and
// everything the chart says is also said in the panels — the fleet list names every fleet, where
// it is and when it arrives, as ordinary keyboard-reachable buttons, and selecting one there fills
// the same detail panel a tap does. Nothing on this screen is reachable ONLY by pointer.
//
// ── STUBBED, AND SAID SO ───────────────────────────────────────────────────────────────────────
// The fleets come from ./sampleVoyages.ts, not from the server — there is no `voyages` table yet.
// When there is, that import becomes the read RPC's result and nothing else on this screen changes.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function MapScreen() {
  // The sample is anchored ONCE, at mount, so the two demonstration voyages carry on from where
  // they were instead of restarting on every render. (When this is live data it will be a prop.)
  const [sampleOrigin] = useState(() => Date.now())
  const fleets = useMemo(() => sampleFleets(sampleOrigin), [sampleOrigin])

  const nowMs = useWallClock()
  const model = useMemo(() => buildChartModel(fleets, V0_PORTS, nowMs), [fleets, nowMs])

  const [selection, setSelection] = useState<MapSelection>(null)

  // THE OPENING VIEW frames WHAT YOU HAVE, not the whole port table — and how much of it depends
  // on the shape of the glass (openingBounds carries the measured arithmetic).
  //
  // Taken from the model AT MOUNT, once. It has to be stable: it is the frame the "fit" control
  // returns to, and a bounds that moved with the fleets would re-frame the chart on every
  // animation frame, which is a map that will not sit still.
  const [openingModel] = useState(() => buildChartModel(sampleFleets(sampleOrigin), V0_PORTS, sampleOrigin))
  const frameBounds = useCallback(
    (aspect: number) =>
      openingBounds(openingModel.focusPoints, openingModel.motionPoints, V0_PORTS, aspect),
    [openingModel],
  )
  const chartRef = useRef<HTMLDivElement>(null)

  // THE ONLY THING A TAP ON THE CHART DOES. The nearest glyph within a 44 px reach wins
  // (./hitTest.ts explains why that is one function and not a touch circle per glyph); tapping the
  // same thing again, or tapping open water, clears the selection. The surface hands over the
  // scale at the moment of the tap, so the reach is 44 px at every zoom.
  const onTap = useCallback(
    (at: Point, unitsPerPx: number) =>
      setSelection((current) =>
        toggleSelection(current, hitTest(model, V0_PORTS, at, GLYPH.hitRadius * unitsPerPx)),
      ),
    [model],
  )

  const surface = useChartSurface(chartRef, frameBounds, onTap)
  const coastline = useCoastline()

  const box = surface.viewBox
  const selectedFleetId = selection?.kind === 'fleet' ? selection.id : null
  const selectedPortCode = selection?.kind === 'port' ? selection.code : null

  // A phone is not a small desktop. Below `sm` the chart is ~390 px wide and a panel that opens by
  // default eats most of it, so the fleet list starts folded to its header chip there and open at
  // desktop widths (defect 3). `surface.width` is 0 until the box is measured, which is why the
  // panels wait for it — Collapsible reads `defaultOpen` once, at mount, so it must be right then.
  const compact = surface.width > 0 && surface.width < COMPACT_WIDTH_PX

  // EVERY NAME ON THE CHART, PLACED AS A SET. Re-planned each frame because the fleets move; it is
  // ~16 labels × 4 candidate sides, which is nothing, and it is the only way two labels can know
  // about each other (see ./labels.ts for the overprinting this replaced).
  const labels = useMemo(
    () =>
      box
        ? planLabels(
            mapLabelRequests(model, V0_PORTS, selection, box.width <= LABEL_SPAN_LIMIT),
            {
              viewBox: box,
              unitsPerPx: surface.unitsPerPx,
              fontSizePx: GLYPH.labelSize,
              gapPx: GLYPH.labelGapX,
              glyphRadiusPx: GLYPH.fleetHaloRadius,
            },
          )
        : [],
    [box, model, selection, surface.unitsPerPx],
  )

  return (
    <div
      ref={chartRef}
      {...surface.handlers}
      // `touch-none` hands every touch to the pan/zoom handler instead of the page scroller;
      // `select-none` stops a drag across the chart highlighting the labels.
      className="relative h-full w-full touch-none select-none overflow-hidden bg-chart-sea"
      data-testid="map-chart"
    >
      {box && (
        <svg
          className="absolute inset-0 h-full w-full"
          viewBox={`${box.x} ${box.y} ${box.width} ${box.height}`}
          role="img"
          aria-label="Chart of the Atlantic approaches and the western Mediterranean, showing ports and your fleets"
        >
          {/* PAINT ORDER IS THE ONLY STACKING SVG HAS: sea, coast, tracks, port marks, fleet
              dots, names. Every name therefore sits on top of every mark, and no mark sits on a
              name. */}
          <CoastlineLayer d={coastline.data?.d ?? ''} />
          <TracksLayer model={model} unitsPerPx={surface.unitsPerPx} />
          <PortsLayer
            ports={V0_PORTS}
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
          portsByCode={V0_PORTS_BY_CODE}
          selection={selection}
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
        portsByCode={V0_PORTS_BY_CODE}
        selection={selection}
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

      {/* THE PERMANENT CAPTION. Two facts the player should never have to work out or be told
          twice: the time scale (§D.3 asks for it here, always) and — the owner asked for this
          explicitly — that this screen is a view, and orders are given somewhere else.
          Pointer-transparent, so it can never swallow a pan gesture near the bottom edge. */}
      <div
        className="pointer-events-none absolute inset-x-0 bottom-0 z-10 flex items-center gap-2 bg-app/70 px-3 py-1.5 backdrop-blur"
        data-testid="map-is-a-view"
      >
        <span className="shrink-0 font-mono text-[10px] text-ink-faint">1 min = 8 h sail</span>
        <span className="min-w-0 truncate font-mono text-[10px] text-ink-muted">
          view only · orders on Command
        </span>
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
