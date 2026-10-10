import { project } from '../lib/geo'
import type { ChartModel } from './chartModel'
import { arrowPath, GLYPH, shipPath } from './glyphs'
import type { MerchantInk } from './mapTypes'

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
// MERCHANT COMPANIES are the owner's 2026-10-08 exception (DESIGN Q7, docs/NPC_TRADERS.md §8.2):
// companies the world keeps, not players. They arrive only through `model.traffic` — the SAME hull
// at the SAME size as yours, filled in the company's nation ink, with no halo (the halo and the gold
// are how "yours" stays loud), at sea and, when she lies in port, at the port's served roadstead,
// bow north. The one merchant whose card is open draws her leg, faint.
//
// Everything here is a pure function of `model`, and `model` is a pure function of the last read
// (./chartModel.ts). There is no animation state and no clock on this layer, so there is nothing to
// drift — and no handler either: taps are resolved once, on the surface, by ./hitTest.ts.

/** The nation inks as WHOLE class names, so Tailwind sees every one (no assembled strings). */
const NATION_FILL: Record<MerchantInk, string> = {
  prt: 'fill-nation-prt',
  esp: 'fill-nation-esp',
  nld: 'fill-nation-nld',
  eng: 'fill-nation-eng',
  han: 'fill-nation-han',
  ita: 'fill-nation-ita',
  ott: 'fill-nation-ott',
  east: 'fill-nation-east',
}

/** Tracks and destination rings — painted UNDER the port marks. */
export function TracksLayer({ model, unitsPerPx }: { model: ChartModel; unitsPerPx: number }) {
  return (
    <g pointerEvents="none" data-testid="map-tracks">
      {/* THE COURSE (row 90): the passage made is SOLID, the water ahead is DASHED, and the
          water ahead ends in an arrowhead at the course's last vertex, turned along its last
          segment. Both halves are the served polyline (./route.ts); the arrow's tip and turn are
          two of its own points. The roadstead's `1 5` dot is no longer borrowed from here. */}
      {model.fleets.map((f) =>
        f.track ? (
          <g key={f.fleet.id}>
            <path
              d={f.track.aheadD}
              className="fill-none stroke-accent/45"
              strokeWidth={GLYPH.trackStroke}
              strokeDasharray="5 4"
              strokeLinecap="round"
              vectorEffect="non-scaling-stroke"
            />
            <path
              d={f.track.sailedD}
              className="fill-none stroke-accent/85"
              strokeWidth={GLYPH.trackStroke + 0.4}
              strokeLinecap="round"
              vectorEffect="non-scaling-stroke"
            />
            {f.track.endHeading !== null && (
              <path
                d={arrowPath(GLYPH.arrowHalfWidth)}
                transform={`translate(${f.track.end.x} ${f.track.end.y}) rotate(${f.track.endHeading}) scale(${unitsPerPx})`}
                className="fill-none stroke-accent/85"
                strokeWidth={GLYPH.trackStroke + 0.4}
                strokeLinecap="round"
                strokeLinejoin="round"
                vectorEffect="non-scaling-stroke"
                data-testid="map-track-arrow"
              />
            )}
          </g>
        ) : null,
      )}

      {/* OWNER ROW 112 — THE OPEN MERCHANT'S WHOLE ROUTE: every leg of the loop she runs, drawn
          as the baked water it is (0099 serves the courses on her card). Quieter than the leg she
          is on, and under it, so "where she goes" and "where she is going now" read as two things.
          Drawn for a merchant in port as well — a route is what she runs, not what she is doing. */}
      {model.traffic.map((t) =>
        t.loopD ? (
          <path
            key={`merchant-loop-${t.fleet.id}`}
            data-testid="map-merchant-loop"
            d={t.loopD}
            className="fill-none stroke-ink-faint/30"
            strokeWidth={GLYPH.trackStroke}
            strokeDasharray="2 6"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
          />
        ) : null,
      )}

      {/* 0099 — THE OPEN MERCHANT'S LEG: the one traffic row that carries her full served course
          (her card is open), drawn faint through the same track paths, no arrow, no ring. */}
      {model.traffic.map((t) =>
        t.track ? (
          <g key={`merchant-${t.fleet.id}`} data-testid="map-merchant-track">
            <path
              d={t.track.aheadD}
              className="fill-none stroke-ink-faint/50"
              strokeWidth={GLYPH.trackStroke}
              strokeDasharray="5 4"
              strokeLinecap="round"
              vectorEffect="non-scaling-stroke"
            />
            <path
              d={t.track.sailedD}
              className="fill-none stroke-ink-faint/70"
              strokeWidth={GLYPH.trackStroke}
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

/**
 * GLYPH 2 — the fleet at sea, AS A SHIP (row 90): `shipPath`, the one hull, turned to her course
 * heading (`FleetOnChart.heading`, the served segment's) inside the same sea-coloured halo the dot
 * wore. A fleet at an open anchor is the same hull pointing north. A fleet in port draws nothing
 * here; it IS its port's loud mark.
 */
export function FleetsLayer({
  model,
  selectedId,
  selectedMerchantId = null,
  unitsPerPx,
}: {
  model: ChartModel
  selectedId: string | null
  /** 0099 — the merchant whose card is open, outlined in ink. */
  selectedMerchantId?: string | null
  unitsPerPx: number
}) {
  const px = (n: number) => n * unitsPerPx

  return (
    <g pointerEvents="none" data-testid="map-fleets">
      {/* 0099 — THE MERCHANTS, UNDER yours: the same `shipPath` at the same size, nation ink, no
          halo. A docked merchant lies at the roadstead, bow north. */}
      {model.traffic.map((t) => {
        const { x, y } = project(t.at)
        const selected = selectedMerchantId === t.fleet.id
        return (
          <path
            key={`merchant-${t.fleet.id}`}
            d={shipPath(GLYPH.shipHalfLength)}
            transform={`translate(${x} ${y}) rotate(${t.heading ?? 0}) scale(${unitsPerPx})`}
            className={`${NATION_FILL[t.merchant.ink]} ${selected ? 'stroke-ink' : 'stroke-chart-sea'}`}
            strokeWidth={GLYPH.glyphStroke * (selected ? 1.2 : 0.6)}
            strokeLinejoin="round"
            vectorEffect="non-scaling-stroke"
            data-testid="map-merchant"
            data-merchant-id={t.fleet.id}
            data-merchant-docked={t.merchant.docked ? 'true' : 'false'}
          />
        )
      })}
      {model.fleets.map((f) => {
        if (f.dockedAtCode !== null) return null
        const { x, y } = project(f.at)
        const selected = selectedId === f.fleet.id

        return (
          <g key={f.fleet.id} data-fleet-heading={f.heading ?? 0}>
            <circle
              cx={x}
              cy={y}
              r={px(GLYPH.fleetHaloRadius)}
              className={`fill-chart-sea/70 ${selected ? 'stroke-ink/70' : 'stroke-accent/40'}`}
              strokeWidth={GLYPH.glyphStroke}
              vectorEffect="non-scaling-stroke"
            />
            <path
              d={shipPath(GLYPH.shipHalfLength)}
              transform={`translate(${x} ${y}) rotate(${f.heading ?? 0}) scale(${unitsPerPx})`}
              className="fill-accent stroke-chart-sea"
              strokeWidth={GLYPH.glyphStroke * 0.6}
              strokeLinejoin="round"
              vectorEffect="non-scaling-stroke"
              data-testid="map-ship"
            />
          </g>
        )
      })}
    </g>
  )
}
