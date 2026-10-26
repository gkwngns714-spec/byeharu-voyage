import { project, type LatLon } from '../lib/geo'
import { GLYPH } from './glyphs'

// THE STOPS OF A PRESSED SHIP'S WHOLE PATH (owner row 225: *"i want to see the full paths when i press my ship"*).
// The dashed line is `plannedD` (ChartCanvas) — the same course drawing a plan and a queued trip use; this only
// marks where the path calls, in order: a numbered disc at each stop and the days of the leg that ends there.
// Served nothing, computed nothing: the screen hands it the stops (live/useShipPath.ts).

export interface PathStop {
  /** Where the leg ends (its last course vertex). */
  at: LatLon
  /** 1, 2, 3 … in the order she calls. */
  n: number
  /** The days of the leg that ends here, already spelt; null when unknown. */
  days: string | null
}

const DISC_PX = 8

export function ShipPathLayer({ stops, unitsPerPx }: { stops: readonly PathStop[]; unitsPerPx: number }) {
  return (
    <g pointerEvents="none" data-testid="map-ship-path">
      {stops.map((s) => {
        const { x, y } = project(s.at)
        return (
          <g key={s.n} data-testid="map-path-stop" data-stop={s.n}>
            <circle cx={x} cy={y} r={DISC_PX * unitsPerPx} className="fill-accent stroke-chart-sea" strokeWidth={1.2 * unitsPerPx} />
            <text
              x={x}
              y={y}
              fontSize={GLYPH.labelSize * unitsPerPx}
              textAnchor="middle"
              dominantBaseline="central"
              className="fill-chart-sea font-mono font-semibold"
            >
              {s.n}
            </text>
            {s.days && (
              <text
                x={x + (DISC_PX + 3) * unitsPerPx}
                y={y}
                fontSize={GLYPH.labelSize * unitsPerPx}
                dominantBaseline="central"
                className="bv-sun-name-halo stroke-chart-sea fill-ink font-mono"
                strokeWidth={GLYPH.labelHaloWidth * unitsPerPx}
                style={{ paintOrder: 'stroke' }}
                data-testid="map-path-days"
              >
                {s.days}
              </text>
            )}
          </g>
        )
      })}
    </g>
  )
}
