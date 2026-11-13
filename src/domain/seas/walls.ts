import { readSeaWall, type SeaConditions, type SeaWall, type SeaZone } from '../../lib/rpc'

// A FLEET'S SEAS — every sea with what it asks and, for one fleet, the wall the server says stands in it.
//
// Read off `world.sea_conditions` (0215, 0391): `fleets[].seas` holds `public.sea_refusal`'s own figures for each sea
// that refuses her, so open or closed is the server's verdict and nothing is compared here. A world before 0391 serves
// no verdict: `judged` is false and no sea is called closed.

export interface SeaRow {
  zone: SeaZone
  /** The wall in this sea for the fleet in hand; null when it is open to her (or nothing was judged). */
  wall: SeaWall | null
}

export interface FleetSeas {
  /** Whether the sea conditions bind yet (`sea_conditions_bite`). Dark, a wall is what the rule WILL say. */
  bite: boolean
  /** Whether the server judged this fleet's seas at all. */
  judged: boolean
  fleet: SeaConditions['fleets'][number] | null
  rows: SeaRow[]
  /** The codes of the seas that refuse her. */
  closed: ReadonlySet<string>
}

const NONE: ReadonlySet<string> = new Set()

export function fleetSeas(conditions: SeaConditions | null | undefined, fleetId: string | null): FleetSeas {
  if (!conditions) return { bite: false, judged: false, fleet: null, rows: [], closed: NONE }
  const fleet = conditions.fleets.find((f) => f.id === fleetId) ?? conditions.fleets[0] ?? null
  const served = fleet?.seas
  const judged = served !== undefined && served !== null
  const closed = new Set<string>()
  const rows = [...conditions.zones]
    .sort((a, b) => a.ord - b.ord)
    .map((zone) => {
      const wall = judged ? readSeaWall(served[zone.code]) : null
      if (wall) closed.add(zone.code)
      return { zone, wall }
    })
  return { bite: conditions.bite, judged, fleet, rows, closed }
}

/** The wall in one sea for that fleet, or null when it is open to her. */
export function wallIn(seas: FleetSeas, zone: string | null): SeaWall | null {
  if (zone === null) return null
  return seas.rows.find((r) => r.zone.code === zone)?.wall ?? null
}
