import { project } from '../lib/geo'
import type { ChartModel } from './chartModel'
import { GLYPH } from './glyphs'

// GLYPHS 2 AND 3 — THE FLEET AND ITS DESTINATION — plus the track between them.
//
// Split into two components because SVG has no z-index and paint order is the only stacking there
// is. Tracks and destination rings belong UNDER the port marks (a dotted line crossing a port
// should pass behind it); the fleet dot belongs OVER them (it is the thing that is moving, and it
// often sits on a port it has just left). MapScreen paints tracks → ports → fleets → labels.
//
// THE TRACK, per DESIGN §E.5: "dotted behind the fleet and fainter ahead of it". Two paths that
// meet exactly at the dot, so the bright half is the passage made and the faint half is what is
// left. The split point is the SERVER's closed-form position (§D.2, `voyage.position`): copied,
// never recomputed here. It is the CURRENT LEG and only that — the planned route beyond it is not
// served (README §4.8), so the voyage's destination gets a ring and no line runs to it.
//
// A fleet AT ANCHOR gets no dot: §E.5 draws it as the port's filled triangle plus a label, and the
// label is placed with all the others by ./labels.ts.
//
// NO OTHER PLAYERS ARE DRAWN, EVER. §E.5 is explicit about why: a chart showing rivals is a
// targeting surface, and this game has no PvP (§J.2). There is no prop on this layer that could
// carry one — the omission is structural, not a setting.
//
// Everything here is a pure function of `model`, and `model` is a pure function of the last read
// (./chartModel.ts). There is no animation state and no clock on this layer, so there is nothing to
// drift — and no handler either: taps are resolved once, on the surface, by ./hitTest.ts.

/** Tracks and destination rings — painted UNDER the port marks. */
export function TracksLayer({ model, unitsPerPx }: { model: ChartModel; unitsPerPx: number }) {
  return (
    <g pointerEvents="none" data-testid="map-tracks">
      {model.fleets.map((f) =>
        f.track ? (
          <g key={f.fleet.id}>
            <path
              d={f.track.aheadD}
              className="fill-none stroke-accent/25"
              strokeWidth={GLYPH.trackStroke}
              strokeDasharray="1 5"
              strokeLinecap="round"
              vectorEffect="non-scaling-stroke"
            />
            <path
              d={f.track.sailedD}
              className="fill-none stroke-accent/75"
              strokeWidth={GLYPH.trackStroke}
              strokeDasharray="1 3"
              strokeLinecap="round"
              vectorEffect="non-scaling-stroke"
            />
          </g>
        ) : null,
      )}

      {/* GLYPH 3b — a destination that is BARE WATER (0039): the same dashed ring, at the
          pinpointed spot, because it is the same fact — where she is bound. */}
      {model.destinationSeaPoints.map((at, i) => {
        const { x, y } = project(at)
        return (
          <circle
            key={`sea-${i}`}
            cx={x}
            cy={y}
            r={GLYPH.destinationRingRadius * unitsPerPx}
            className="fill-none stroke-accent/60"
            strokeWidth={GLYPH.glyphStroke}
            strokeDasharray="3 3"
            vectorEffect="non-scaling-stroke"
          />
        )
      })}

      {/* GLYPH 3 — the destination: a dashed ring round the port a fleet is bound for. */}
      {[...model.destinationPoints].map(([code, at]) => {
        const { x, y } = project(at)
        return (
          <circle
            key={code}
            cx={x}
            cy={y}
            r={GLYPH.destinationRingRadius * unitsPerPx}
            className="fill-none stroke-accent/60"
            strokeWidth={GLYPH.glyphStroke}
            strokeDasharray="3 3"
            vectorEffect="non-scaling-stroke"
          />
        )
      })}
    </g>
  )
}

/** GLYPH 2 — the fleet at sea. A fleet at anchor draws nothing here; it IS its port's loud mark. */
export function FleetsLayer({
  model,
  selectedId,
  unitsPerPx,
}: {
  model: ChartModel
  selectedId: string | null
  unitsPerPx: number
}) {
  const px = (n: number) => n * unitsPerPx

  return (
    <g pointerEvents="none" data-testid="map-fleets">
      {model.fleets.map((f) => {
        if (f.dockedAtCode !== null) return null
        const { x, y } = project(f.at)
        const selected = selectedId === f.fleet.id

        return (
          <g key={f.fleet.id}>
            <circle
              cx={x}
              cy={y}
              r={px(GLYPH.fleetHaloRadius)}
              className={`fill-chart-sea/70 ${selected ? 'stroke-ink/70' : 'stroke-accent/40'}`}
              strokeWidth={GLYPH.glyphStroke}
              vectorEffect="non-scaling-stroke"
            />
            <circle cx={x} cy={y} r={px(GLYPH.fleetDotRadius)} className="fill-accent" />
          </g>
        )
      })}
    </g>
  )
}
