import { ShipTile, TileField } from '../../components/ui'
import type { FleetView } from '../../lib/rpc'
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

// THE TILE ITSELF is the design system's `ShipTile` since 2026-10-08 (a merchant's sheet prints the
// same hull); what is DERIVED — the hull fraction and the tuns in use — stays here, through
// domain/fleet, because the design system knows nothing above it.
export function FleetShips({ fleet }: { fleet: FleetView }) {
  return (
    <TileField>
      {fleet.ships.map((ship) => (
        <ShipTile
          key={ship.id}
          name={ship.name}
          className={ship.class}
          flagship={ship.is_flagship}
          hullPct={hullFraction(ship)}
          crew={ship.crew}
          crewMax={ship.crew_max}
          crewRequired={ship.crew_required}
          speedKn={ship.speed}
          holdUsed={shipHoldUsed(ship)}
          holdTotal={ship.hold}
          fittings={ship.fittings}
        />
      ))}
    </TileField>
  )
}
