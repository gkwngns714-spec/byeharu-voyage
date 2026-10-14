import type { CSSProperties, ReactNode } from 'react'
import { project, type LatLon } from '../lib/geo'
import type { ChartModel, FleetOnChart, TrafficOnChart } from './chartModel'
import {
  arrowPath,
  GLYPH,
  hullGroup,
  hullGroupHalo,
  hullPath,
} from './glyphs'
import type { MerchantInk } from './mapTypes'
import { useRegionsFilter } from './regionsFilter'
import { nightStyle } from './sun'

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
// companies the world keeps, not players. They arrive only through `model.traffic` — through the
// SAME `HullGroup` as yours, filled in the company's nation ink, with no halo (the halo and the gold
// are how "yours" stays loud), at sea and, when she lies in port, at the port's served roadstead,
// bow north. The one merchant whose card is open draws her leg, faint.
//
// ROW 120 (2026-10-11) — A FLEET IS DRAWN AS THE SHIPS SHE IS. One hull at one size became the hull
// CLASS's own silhouette at the size her burthen earns, and a fleet of several is drawn as several:
// the arithmetic is ./glyphs.ts's (`hullPath`, `hullGroup`, `hullGroupHalo`) and the ONE renderer is
// `HullGroup` below, which both lists go through.
//
// 2026-10-14 — A SHIP AT EVERY ZOOM, AND THE SUN ON HER (owner: *"show ships when zoomed out"*;
// *"sunlight based on real science"*). Row 125's EMBER — past a density a fleet became a dot with a
// light and no hull, and at the globe only the major fleets were drawn at all — is retired: this
// layer draws a HULL for every ship it is handed, at every span. WHAT it is handed is
// ./shipMarks.ts's decision (culled to the view, the merchants thinned to one per cell), made by
// `ChartCanvas` once per copy of the sheet, so this file decides nothing about who is on the paper
// and never did. Her riding light is lit by the Sun: the group carries `--night` (./PortsLayer.tsx
// `nightStyle`, the one spelling), the two lamp circles fade by day (`.bv-sun-light`), and a
// merchant's hull mixes from her night ink toward the pale deck a ship shows the sky
// (`.bv-sun-merchant`, src/index.css).
//
// Everything here is a pure function of what it is handed, and that is a pure function of the last
// read (./chartModel.ts). There is no animation state and no clock on this layer, so there is nothing
// to drift — and no handler either: taps are resolved once, on the surface, by ./hitTest.ts.

/** The same eight inks as a STROKE, for row 125's lanes. Whole class names for the same reason the
 *  fills below are: Tailwind scans source text, and an assembled string is a class it never sees. */
const NATION_STROKE: Record<MerchantInk, string> = {
  prt: 'stroke-nation-prt',
  esp: 'stroke-nation-esp',
  nld: 'stroke-nation-nld',
  eng: 'stroke-nation-eng',
  han: 'stroke-nation-han',
  ita: 'stroke-nation-ita',
  ott: 'stroke-nation-ott',
  east: 'stroke-nation-east',
}

/**
 * WHERE IN HER BLINK THIS FLEET IS (owner, 2026-10-12). A stable offset into the 2.6 s cycle,
 * derived from her OWN id — the `berthSlotOf` lesson from ./liveWorld.ts, which this chart learned
 * when docked merchants were fanned by their position in the served list and every hull shifted
 * along the ring whenever a neighbour arrived. A phase taken from an index would do the same thing
 * in time: the whole sea would re-stagger itself on every read. Taken from her id, a merchant keeps
 * her own rhythm for as long as she exists, whoever else is at sea.
 */
function blinkPhase(id: string): number {
  let h = 0
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) % 2600
  return h
}

/** The nation inks as WHOLE class names, so Tailwind sees every one (no assembled strings). The
 *  matching custom property is what `.bv-sun-merchant-nation` mixes from by day. */
const NATION_FILL: Record<MerchantInk, { readonly cls: string; readonly token: string }> = {
  prt: { cls: 'fill-nation-prt', token: 'var(--color-nation-prt)' },
  esp: { cls: 'fill-nation-esp', token: 'var(--color-nation-esp)' },
  nld: { cls: 'fill-nation-nld', token: 'var(--color-nation-nld)' },
  eng: { cls: 'fill-nation-eng', token: 'var(--color-nation-eng)' },
  han: { cls: 'fill-nation-han', token: 'var(--color-nation-han)' },
  ita: { cls: 'fill-nation-ita', token: 'var(--color-nation-ita)' },
  ott: { cls: 'fill-nation-ott', token: 'var(--color-nation-ott)' },
  east: { cls: 'fill-nation-east', token: 'var(--color-nation-east)' },
}

/** Tracks and destination rings — painted UNDER the port marks. */
export function TracksLayer({
  model,
  unitsPerPx,
  lanes,
}: {
  model: ChartModel
  unitsPerPx: number
  /** Past `LANE_SPAN_DEG` — the span at which a thinned loop is safe to draw. Handed down rather
   *  than re-derived here, so there is one place that decides where the sheet changes. */
  lanes: boolean
}) {
  const litLanes = lanes
  // Regions on: each merchant in her nation's ink. Off: every merchant in the one dark blue.
  const regions = useRegionsFilter()
  return (
    <g pointerEvents="none" data-testid="map-tracks">
      {/* OWNER ROW 125 — THE MAJOR FLEETS' LANES, at a wide span only. *"major fleet shoud also
          show the routes as well"*. FIRST in this layer, so they lie under every track, every port
          mark and every hull: a lane is the faintest thing on the sheet, the grain of the world's
          trade rather than a line anybody is meant to follow.

          IN HER NATION'S INK, at /25, hairline. The ink is the SAME channel the hulls use, so a
          lane and the fleet keeping it read as one thing without a legend — MAP_ATMOSPHERE §4's
          two-channel rule, which row 120 and row 125 both answer to.

          ONLY ON THE WIDE SHEET. Zoomed in, the sheet is a working chart and 240 thinned loops
          across it would be a thicket over the water somebody is reading; and a lane is thinned,
          so close in it would also be visibly WRONG — straight where the course bends.

          WHO GETS ONE IS THE SERVER'S ANSWER (`fleet_lane_min_ships`, 0111). Nothing here counts
          hulls: a client that decided what "major" means would be a second authority on it, and
          the one that is not the server would be the one that goes stale. */}
      {litLanes &&
        model.traffic.map((t) =>
          t.laneD ? (
            <path
              key={`merchant-lane-${t.fleet.id}`}
              data-testid="map-merchant-lane"
              data-lane-ink={t.merchant.ink}
              d={t.laneD}
              className={`fill-none ${regions ? NATION_STROKE[t.merchant.ink] : 'stroke-merchant'} opacity-15`}
              strokeWidth={GLYPH.trackStroke}
              strokeLinecap="round"
              strokeLinejoin="round"
              vectorEffect="non-scaling-stroke"
            />
          ) : null,
        )}

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
 * ONE FLEET'S HULLS, PLACED AND TURNED — the ONE renderer behind every hull on this chart, yours
 * and the merchants' alike (owner row 120).
 *
 * It emits a single `<g>` whose transform does all three jobs at once — put her where the server
 * put her, turn her onto her heading, and take the glyph out of pixels into chart units — so every
 * hull in the group is placed by `translate(dx dy)` inside that frame and the whole formation turns
 * as one. `children` is the chrome that belongs INSIDE the frame (your halo); the hulls follow it,
 * so a halo never paints over a hull.
 *
 * WHY IT TAKES A `FleetOnChart` AND NOT A MERCHANT TYPE. `TrafficOnChart extends FleetOnChart`, so
 * this signature is the whole of what both lists have in common and neither list can grow a second
 * arrangement without the other seeing it (docs/NO_SPAGHETTI.md §1). The things that genuinely
 * DIFFER between them — the ink, the halo, the test hooks — are props, which is what a difference
 * that is real looks like.
 */
function HullGroup({
  fleet,
  unitsPerPx,
  className,
  style,
  strokeWidth,
  hooks,
  children,
  sun,
}: {
  fleet: FleetOnChart
  unitsPerPx: number
  className: string
  /** Inline style for the hulls — the nation ink token, when the Regions filter is on. */
  style?: CSSProperties
  strokeWidth: number
  /** The `data-*` hooks this list wants — on the GROUP, so there is one of them per fleet. */
  hooks: Readonly<Record<string, string>>
  children?: ReactNode
  /** Where the Sun is overhead, for her `--night`. */
  sun: LatLon
}) {
  const { x, y } = project(fleet.at)
  const marks = hullGroup(fleet.fleet.hulls ?? [], unitsPerPx)

  return (
    <g
      transform={`translate(${x} ${y}) rotate(${fleet.heading ?? 0}) scale(${unitsPerPx})`}
      data-fleet-heading={fleet.heading ?? 0}
      data-hulls={marks.length}
      style={nightStyle(fleet.at, sun)}
      {...hooks}
    >
      {children}
      {/* HER RIDING LIGHT AT EVERY ZOOM (owner, 2026-10-13: *"i see no blue markers for ship"*),
          LIT BY THE SUN (2026-10-14): the same blue lamp and blink at every span, drawn UNDER the
          hull so the shape stays on top, sized to HER (the group's halo) so the glow reaches past
          the hull and reads as a light round her rather than a dot hidden beneath her — and out by
          day, through the group's `--night`. */}
      {marks.length > 0 && (() => {
        const lit = hullGroupHalo(marks)
        return (
          <g className="bv-ship-blink bv-sun-light" style={{ animationDelay: `${blinkPhase(fleet.fleet.id)}ms` }} pointerEvents="none" data-ship-light="">
            <circle cx={lit.cx} cy={lit.cy} r={lit.r * GLYPH.shipLightBloomScale} className="fill-ship-light/20" />
            <circle cx={lit.cx} cy={lit.cy} r={lit.r * GLYPH.shipLightGlowScale} className="fill-ship-light/45" />
          </g>
        )
      })()}
      {marks.map((m, i) => (
        <path
          key={i}
          d={hullPath(m.cls, m.halfLength)}
          transform={`translate(${m.dx} ${m.dy})`}
          className={className}
          style={style}
          strokeWidth={strokeWidth}
          strokeLinejoin="round"
          vectorEffect="non-scaling-stroke"
          data-hull-class={m.cls ?? 'unknown'}
        />
      ))}
    </g>
  )
}

/**
 * GLYPH 2 — the fleet at sea, AS HER HULLS (row 90 made her a ship, row 120 made her HERSELF):
 * `hullPath` per hull, each at the size her class earns, arranged by `hullGroup` and turned as one
 * formation onto her course heading (`FleetOnChart.heading`, the served segment's) inside the
 * sea-coloured halo the dot wore. A fleet at an open anchor is the same group pointing north. A
 * fleet in port draws nothing here; it IS its port's loud mark.
 *
 * HANDED ITS LISTS, NOT THE MODEL (2026-10-14): `fleets` and `traffic` are ./shipMarks.ts's
 * decision for one copy of the sheet — your fleets on the view, the merchants on the view thinned
 * to one per cell. Every one of them is drawn, as a ship.
 */
export function FleetsLayer({
  fleets,
  traffic,
  selectedId,
  selectedMerchantId = null,
  unitsPerPx,
  sun,
}: {
  /** Your fleets at sea on this view (`shipMarks`). */
  fleets: readonly FleetOnChart[]
  /** The merchants on this view, thinned (`shipMarks`). */
  traffic: readonly TrafficOnChart[]
  selectedId: string | null
  /** 0099 — the merchant whose card is open, outlined in ink. */
  selectedMerchantId?: string | null
  unitsPerPx: number
  /** Where the Sun is overhead (./sun.ts). */
  sun: LatLon
}) {
  // Regions on: each merchant in her nation's ink. Off: every merchant in the one dark blue.
  const regions = useRegionsFilter()
  return (
    <g pointerEvents="none" data-testid="map-fleets">
      {/* 0099 — THE MERCHANTS, UNDER yours: the same `HullGroup` at the same sizes, nation ink, no
          halo. Row 120: she draws AS MANY HULLS AS SHE HAS, because `world.sea_traffic` serves her
          count and 0102 her classes.

          THE TEST HOOKS SIT ON THE GROUP AND NOT ON A HULL, deliberately: there is exactly one
          `map-merchant` per merchant whatever she sails, so a spec that asks for her box gets her
          whole mark and a spec that counts hulls on the sea counts fleets. */}
      {traffic.map((t) => {
        const selected = selectedMerchantId === t.fleet.id
        const nation = NATION_FILL[t.merchant.ink]
        return (
          <HullGroup
            key={`merchant-${t.fleet.id}`}
            fleet={t}
            unitsPerPx={unitsPerPx}
            sun={sun}
            className={`${regions ? `bv-sun-merchant-nation ${nation.cls}` : 'bv-sun-merchant fill-merchant'} ${selected ? 'stroke-ink' : 'bv-sun-keyline stroke-chart-sea'}`}
            style={regions ? ({ '--nation-ink': nation.token } as CSSProperties) : undefined}
            strokeWidth={GLYPH.glyphStroke * (selected ? 1.2 : 0.6)}
            hooks={{
              'data-testid': 'map-merchant',
              'data-merchant-id': t.fleet.id,
              'data-merchant-docked': t.merchant.docked ? 'true' : 'false',
            }}
          />
        )
      })}
      {fleets.map((f) => {
        const selected = selectedId === f.fleet.id
        // ONE HALO FOR THE WHOLE GROUP, sized to the hulls actually drawn and inside the group's own
        // frame — so it follows the formation astern as she turns. For a single hull it is the
        // circle that was here before row 120, to the pixel (./glyphs.ts `hullGroupHalo`).
        const halo = hullGroupHalo(hullGroup(f.fleet.hulls ?? [], unitsPerPx))
        return (
          <HullGroup
            key={f.fleet.id}
            fleet={f}
            unitsPerPx={unitsPerPx}
            sun={sun}
            className="fill-accent bv-sun-keyline stroke-chart-sea"
            strokeWidth={GLYPH.glyphStroke * 0.6}
            hooks={{ 'data-testid': 'map-ship' }}
          >
            <circle
              cx={halo.cx}
              cy={halo.cy}
              r={halo.r}
              className={`bv-sun-fleet-halo fill-chart-sea/70 ${selected ? 'stroke-ink/70' : 'stroke-accent/40'}`}
              strokeWidth={GLYPH.glyphStroke}
              vectorEffect="non-scaling-stroke"
            />
          </HullGroup>
        )
      })}
    </g>
  )
}
