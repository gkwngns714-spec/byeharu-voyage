import { project, type LatLon } from '../lib/geo'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WORLD EVENTS ON THE MAP (0469): a ring round every harbour with a famine, a festival or a blockade running or announced. 0484: and,
// with the map's Race layer on, round every contested city someone leads this week (RACE_MINE, RACE_RIVAL: always `live`, solid).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHICH AND WHERE are the server's (world.world_events, through src/live/useWorldEvents.ts); the screen hands the harbours' places in.
// PAINT ORDER (ChartCanvas): with the battles' rings, UNDER the port marks, the hulls and every name, so it never covers a city's
// name and asks the label planner for nothing. A running event's ring is solid, an announced one's dashed. The kind is its colour
// (a famine amber, a festival the accent, a blockade red) AND its line (a blockade's is doubled), so colour is not the only signal.
// NOT A HIT TARGET: the harbour under it is pressed as always. Dark, or with none, it draws nothing.

export interface MapEventMark extends LatLon {
  readonly id: string
  /** FAMINE, FESTIVAL or BLOCKADE. */
  readonly code: string
  readonly portCode: string
  readonly live: boolean
}

const STROKE: Record<string, string> = {
  FAMINE: 'stroke-warning',
  FESTIVAL: 'stroke-accent',
  BLOCKADE: 'stroke-danger',
  // 0484: the map's Race layer rings each contested city by who leads it this week: her country green, a rival amber (a race to win). The
  // leader's flag stands by the city's name (the chart's flags), so colour is not the only signal.
  RACE_MINE: 'stroke-success',
  RACE_RIVAL: 'stroke-warning',
}

/** The ring's radius, in CSS pixels: wide enough to stand clear of the largest harbour mark. */
const RING_PX = 13

export function EventMarksLayer({ marks, unitsPerPx }: { marks: readonly MapEventMark[]; unitsPerPx: number }) {
  if (marks.length === 0) return null
  const r = RING_PX * unitsPerPx
  return (
    <g pointerEvents="none" data-testid="map-event-marks">
      {marks.map((m) => {
        const at = project(m)
        const stroke = STROKE[m.code] ?? 'stroke-ink'
        return (
          <g key={m.id} data-testid="map-event-mark" data-code={m.code} data-port={m.portCode} data-live={m.live || undefined}>
            <circle
              cx={at.x}
              cy={at.y}
              r={r}
              className={`fill-none ${stroke}`}
              strokeWidth={2}
              strokeDasharray={m.live ? undefined : '3 3'}
              vectorEffect="non-scaling-stroke"
            />
            {m.code === 'BLOCKADE' && (
              <circle cx={at.x} cy={at.y} r={r + 3 * unitsPerPx} className={`fill-none ${stroke}`} strokeWidth={1} vectorEffect="non-scaling-stroke" />
            )}
          </g>
        )
      })}
    </g>
  )
}
