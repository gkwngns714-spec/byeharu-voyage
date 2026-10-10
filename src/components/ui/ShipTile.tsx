import { formatInt, formatKnots, formatOfTotal, formatPct } from '../../lib/format'
import { Bar } from './Bar'
import { Figure } from './Figure'
import { Icon } from './Icon'
import { Tile } from './Tile'

// ONE HULL, AS A TILE — moved here from features/fleets/FleetShips.tsx (2026-10-08) because two
// faces print it: your own fleet (FLEETS) and a merchant's (the merchant sheet, MAP and PORT,
// docs/NPC_TRADERS.md §8.3). PURE PROPS: the design system knows nothing above it
// (tests/sections.spec.ts), so whatever is derived — the hull fraction, the tuns in use — is the
// CALLER's, through its own authority, and this prints the numbers it is handed.
//
// Who she is, what she is, how sound (the bar), how many hands and how much room. What IS mounted
// is one caption line, only on a hull that carries something.
export function ShipTile({
  name,
  className,
  flagship,
  hullPct,
  crew,
  crewMax,
  crewRequired,
  speedKn,
  holdUsed,
  holdTotal,
  fittings = [],
  testId = 'fleet-ship-tile',
}: {
  name: string
  /** The class NAME, as served (`Carlat`). */
  className: string
  flagship: boolean
  /** 0–1. */
  hullPct: number
  crew: number
  crewMax: number
  crewRequired: number
  speedKn: number
  holdUsed: number
  holdTotal: number
  fittings?: readonly { name: string; qty: number }[]
  testId?: string
}) {
  const short = crew < crewRequired
  return (
    <Tile
      mark={flagship ? <Icon name="ship" size={20} className="text-accent" aria-label="flagship" /> : undefined}
      name={name}
      // 0074: HER OWN SPEED, because a fitting moves one hull and not the rest.
      meta={`${className} · ${formatKnots(speedKn)}`}
      figure={<Figure value={`${formatInt(crew)}/${formatInt(crewMax)}`} unit="crew" tone={short ? 'danger' : 'ink'} />}
      second={<Figure value={formatOfTotal(holdUsed, holdTotal)} unit="tons" />}
      bar={
        <Bar
          pct={hullPct * 100}
          tone={hullPct < 0.4 ? 'danger' : hullPct < 0.75 ? 'warning' : 'neutral'}
          label={`${name} hull`}
          figure={<span className="text-t-caption tabular-nums text-ink-muted">{formatPct(hullPct)}</span>}
        />
      }
      data-testid={testId}
    >
      {fittings.length > 0 && (
        <span className="text-t-caption text-ink-faint">
          {fittings.map((f) => (f.qty > 1 ? `${f.name} ×${formatInt(f.qty)}` : f.name)).join(' · ')}
        </span>
      )}
    </Tile>
  )
}
