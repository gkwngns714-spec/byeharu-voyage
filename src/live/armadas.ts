import { cmdArmadaDisband, cmdArmadaForm } from '../lib/rpc'
import type { ArmadaView, Armadas, FleetView } from '../lib/rpc'
import { useWorld } from './worldStore'

// AN ARMADA, READ IN ONE PLACE (0367, docs/ARMADA.md; owner row 323: "with more than one fleet, max 6 fleet - an armada"). The Fleets page, the map's send list, the chart's
// marks and Trade's sail all read this one hook (the world store's one read). The armadas are the server's (`world.armadas`); the figures of an armada are sums of her fleets' own served totals
// (`world.fleets().totals`, public.fleet_totals), added up here once so no two faces add them differently.

/** `world.armadas`, as the world's own read keeps it (worldStore.refresh: on the world's beat, after the fleets and the routes, and only for a company of two fleets or
 *  more). A company of one fleet, and everyone before the first read: no armadas, switched off. */
export function useArmadas(): Armadas {
  return useWorld((s) => s.armadas)
}

/** The armada a fleet is in, or null. */
export function armadaOf(armadas: Armadas, fleetId: string): ArmadaView | null {
  return armadas.armadas.find((a) => a.fleets.includes(fleetId)) ?? null
}

/** Her fleets as the world read serves them, in the armada's order (the flagship fleet first). A fleet the read no longer holds is left out. */
export function fleetsOf(armada: ArmadaView, fleets: readonly FleetView[]): FleetView[] {
  return armada.fleets.flatMap((id) => fleets.find((f) => f.id === id) ?? [])
}

export interface ArmadaTotals {
  fleets: number
  ships: number
  attack: number
  hull: number
  hullMax: number
  crew: number
  crewMax: number
  wagesDay: number
}

/** What an armada adds up to: the sums of her fleets' served totals. Nothing here is a second reading of a ship. */
export function armadaTotals(members: readonly FleetView[]): ArmadaTotals {
  const sum = (pick: (f: FleetView) => number) => members.reduce((n, f) => n + pick(f), 0)
  return {
    fleets: members.length,
    ships: sum((f) => f.totals?.ships ?? f.ships.length),
    attack: sum((f) => f.totals?.attack ?? 0),
    hull: sum((f) => f.totals?.hull ?? 0),
    hullMax: sum((f) => f.totals?.hull_max ?? 0),
    crew: sum((f) => f.totals?.crew ?? 0),
    crewMax: sum((f) => f.totals?.crew_max ?? 0),
    wagesDay: sum((f) => f.totals?.wages_day ?? 0),
  }
}

export { cmdArmadaDisband, cmdArmadaForm }
