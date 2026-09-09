import { Bar, Figure, Icon, Tile, TileField } from '../../components/ui'
import { formatInt, formatKnots, formatOfTotal, formatPct } from '../../lib/format'
import type { FleetShip, FleetView } from '../../lib/rpc'
import { hullFraction, shipHoldUsed } from '../../domain/fleet'

// HER HULLS, AS TILES — what an eight-column table was.
//
// The table (Ship · Class · Hull · Crew · Speed · Hold · Load · Free) was 8 facts wide in a 358px
// box, sheared at CREW, and printed "Swipe the table for the rest." under itself. A tile carries
// the same reading in the order a captain asks it: who she is, what she is, how sound (the bar),
// how many hands and how much room. Load and Free were Hold twice, so there is one hold figure.
//
// ── WHAT IS NOT DRAWN ──────────────────────────────────────────────────────────────────────────
// `GAIVOTA — FITTED / Nothing mounted. She sails as the shipwright rated her. / rig 0/1 · weapon
// 0/1 · ground-tackle 0/1 · 3 cabin(s)` — an empty state printed as a paragraph, per hull, and a
// slot count for cabins that hold nothing yet (docs/OWNER_REQUESTS.md row 68). What IS mounted is
// a fact and is printed, one caption line, only on a hull that carries something. Mounting one is
// the FIT verb on COMMAND; this face reads.

export function FleetShips({ fleet }: { fleet: FleetView }) {
  return (
    <TileField>
      {fleet.ships.map((ship) => (
        <ShipTile key={ship.id} ship={ship} />
      ))}
    </TileField>
  )
}

function ShipTile({ ship }: { ship: FleetShip }) {
  const hull = hullFraction(ship)
  const used = shipHoldUsed(ship)
  const short = ship.crew < ship.crew_required
  return (
    <Tile
      mark={ship.is_flagship ? <Icon name="ship" size={20} className="text-accent" aria-label="flagship" /> : undefined}
      name={ship.name}
      // 0074: HER OWN SPEED, because a fitting moves one hull and not the rest.
      meta={`${ship.class} · ${formatKnots(ship.speed)}`}
      figure={
        <Figure
          value={`${formatInt(ship.crew)}/${formatInt(ship.crew_max)}`}
          unit="crew"
          tone={short ? 'danger' : 'ink'}
        />
      }
      second={<Figure value={formatOfTotal(used, ship.hold)} unit="t" />}
      bar={
        <Bar
          pct={hull * 100}
          tone={hull < 0.4 ? 'danger' : hull < 0.75 ? 'warning' : 'neutral'}
          label={`${ship.name} hull`}
          figure={<span className="text-t-caption tabular-nums text-ink-muted">{formatPct(hull)}</span>}
        />
      }
      data-testid="fleet-ship-tile"
    >
      {ship.fittings.length > 0 && (
        <span className="text-t-caption text-ink-faint">
          {ship.fittings.map((f) => (f.qty > 1 ? `${f.name} ×${formatInt(f.qty)}` : f.name)).join(' · ')}
        </span>
      )}
    </Tile>
  )
}
