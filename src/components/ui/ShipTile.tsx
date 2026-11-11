import type { ReactNode } from 'react'
import { formatInt, formatKnots, formatOfTotal, formatPct } from '../../lib/format'
import { Bar } from './Bar'
import { FactsLine } from './FactsLine'
import { Figure } from './Figure'
import { Icon } from './Icon'
import { Tile } from './Tile'
import { useT } from '../../lib/i18n'

// ONE HULL, AS A TILE — moved here from features/fleets/FleetShips.tsx (2026-10-08) because two
// faces print it: your own fleet (FLEETS) and a merchant's (the merchant sheet, MAP and PORT,
// docs/NPC_TRADERS.md §8.3). PURE PROPS: the design system knows nothing above it
// (tests/sections.spec.ts), so whatever is derived — the hull fraction, the tuns in use — is the
// CALLER's, through its own authority, and this prints the numbers it is handed.
//
// Who she is, what she is, how sound (the bar), how many hands and how much room. What IS mounted
// is one caption line, only on a hull that carries something.
//
// HER POWER (0337, docs/WORLD_POWERS.md 2.3): the five figures a fight reads, one caption line under the bar, when the caller hands them over. They are
// `world.ship_view`'s own, served on every hull (`FleetShip`), so a caller passes the ship itself: nothing is added up and no total is invented here. Her hull
// and her crew are the bar and the figure above it, not said twice.
export interface ShipPower {
  attack: number
  accuracy: number
  reach: number
  armour: number
  sighting: number
}

const POWER = ['attack', 'accuracy', 'reach', 'armour', 'sighting'] as const

export function ShipTile({
  name,
  className,
  flagship,
  hull,
  hullPct,
  crew,
  crewMax,
  crewRequired,
  speedKn,
  holdUsed,
  holdTotal,
  fittings = [],
  power,
  wrapName,
  children,
  testId = 'fleet-ship-tile',
}: {
  /** Her name whole, wrapped at its spaces (Tile's `wrapName`). */
  wrapName?: boolean
  /** The caller's own presses for this hull (Fleets: Stats and Move), at the tile's foot. */
  children?: ReactNode
  name: string
  /** The class NAME, as served (`Carlat`). */
  className: string
  flagship: boolean
  /** 0310: a picture of her hull, the caller's, in the place of the flagship's mark. */
  hull?: ReactNode
  /** 0–1. */
  hullPct: number
  crew: number
  crewMax: number
  crewRequired: number
  speedKn: number
  holdUsed: number
  holdTotal: number
  fittings?: readonly { name: string; qty: number }[]
  /** Her five fighting figures (0337). Absent: no Power line is drawn. */
  power?: ShipPower
  testId?: string
}) {
  const t = useT()
  const short = crew < crewRequired
  return (
    <Tile
      mark={hull ?? (flagship ? <Icon name="ship" size={20} className="text-accent" aria-label={t('ui.flagship')} /> : undefined)}
      name={name}
      wrapName={wrapName}
      // 0074: HER OWN SPEED, because a fitting moves one hull and not the rest.
      meta={`${className} · ${formatKnots(speedKn)}`}
      figure={<Figure value={`${formatInt(crew)}/${formatInt(crewMax)}`} unit={t('ui.unitCrew')} tone={short ? 'danger' : 'ink'} />}
      second={<Figure value={formatOfTotal(holdUsed, holdTotal)} unit={t('ui.unitTons')} />}
      bar={
        <Bar
          pct={hullPct * 100}
          tone={hullPct < 0.4 ? 'danger' : hullPct < 0.75 ? 'warning' : 'neutral'}
          label={t('ui.hullOf', { name })}
          figure={<span className="text-t-caption tabular-nums text-ink-muted">{formatPct(hullPct)}</span>}
        />
      }
      data-testid={testId}
    >
      {power && (
        <FactsLine className="mt-0" data-testid="ship-power">
          <span className="text-ink-muted">{t('ship.power')}</span>
          {POWER.map((k) => (
            <span key={k} className="whitespace-nowrap">
              {t(`ship.${k}`)} <span className="tabular-nums text-ink-muted">{formatInt(power[k])}</span>
            </span>
          ))}
        </FactsLine>
      )}
      {fittings.length > 0 && (
        <span className="text-t-caption text-ink-faint">
          {fittings.map((f) => (f.qty > 1 ? `${f.name} ×${formatInt(f.qty)}` : f.name)).join(' · ')}
        </span>
      )}
      {children}
    </Tile>
  )
}
