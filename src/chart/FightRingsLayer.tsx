import type { FightRing } from './fightRings'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE RED RINGS — one circle round the fleets of every battle being fought (0364, owner row 321).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHERE AND HOW BIG is ./fightRings.ts (pure, and measured by tests/map.fightRings.spec.ts). This file only inks it.
// PAINT ORDER (ChartCanvas): UNDER the port marks, the hulls and every name, so a ring never covers a fleet or a city's
// name; its fill is a faint wash (the danger colour at 10 %), so the sea and coast under it still read. It is no
// label, asks the label planner for nothing and moves no name (tests/map.labels.spec.ts's law is untouched).
// THE PULSE is the line's own opacity, slow (`bv-fight-ring`, src/index.css); the reduced-motion sweep at the bottom
// of that file leaves it steady at full strength. A battle that is over keeps its ring a short while, still and
// fainter, then the server stops serving it.
// NOT A HIT TARGET: the chart hit-tests in one place (MapScreen's `onTap`, with `fightAt`), never by elements.

export function FightRingsLayer({ rings, selectedId, unitsPerPx }: { rings: readonly FightRing[]; selectedId: string | null; unitsPerPx: number }) {
  if (rings.length === 0) return null
  return (
    <g pointerEvents="none" data-testid="map-fight-rings">
      {rings.map((ring) => (
        <g key={ring.id} data-testid="map-fight-ring" data-fight={ring.id} data-kind={ring.kind} data-over={ring.over || undefined} data-mine={ring.mine || undefined} data-r-px={Math.round(ring.rPx)}>
          <circle cx={ring.centre.x} cy={ring.centre.y} r={ring.r} className="fill-danger/10" />
          <circle
            cx={ring.centre.x}
            cy={ring.centre.y}
            r={ring.r}
            className={`fill-none stroke-danger ${ring.over ? 'opacity-50' : 'bv-fight-ring'}`}
            strokeWidth={selectedId === ring.id ? 3 : 2}
            vectorEffect="non-scaling-stroke"
          />
          {/* a second, thin line just inside: red is not the only signal that this is a ring and not a coast */}
          <circle
            cx={ring.centre.x}
            cy={ring.centre.y}
            r={Math.max(0, ring.r - 4 * unitsPerPx)}
            className="fill-none stroke-danger/50"
            strokeWidth={1}
            strokeDasharray="2 4"
            vectorEffect="non-scaling-stroke"
          />
        </g>
      ))}
    </g>
  )
}
