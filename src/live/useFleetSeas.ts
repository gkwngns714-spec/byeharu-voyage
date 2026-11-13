import { useMemo } from 'react'
import { fleetSeas, unpackZoneMap, type FleetSeas, type ZoneCells } from '../domain/seas'
import { useCommandDraft } from '../domain/order'
import { worldSeaZoneMap } from '../lib/rpc'
import { SESSION_MS } from '../store/resourceCache'
import { useSeaConditions } from './useSeaConditions'
import { useServedRead } from './useServedRead'

// THE SEAS OF THE FLEET IN HAND — the one hook every screen reads a fleet's open and closed seas through.
//
// `fleetId` names the fleet; absent, it is the fleet the app-wide draft points at (the last fleet the player touched
// on any tab), else her first. The verdicts are the server's (domain/seas reads them off world.sea_conditions).

export function useFleetSeas(fleetId?: string | null): FleetSeas & { loading: boolean } {
  const drafted = useCommandDraft((s) => s.fleetId)
  const read = useSeaConditions()
  const id = fleetId === undefined ? drafted : fleetId
  return useMemo(() => ({ ...fleetSeas(read.view, id), loading: read.loading }), [read.view, read.loading, id])
}

/** WHICH SEA EVERY CELL OF THE CHART IS IN (world.sea_zone_map, 0396). World data: asked once a session, and only
 *  when `wanted` (a world whose sea conditions bite and that serves the read: before that nothing is shaded). */
export function useSeaZoneCells(wanted: boolean): ZoneCells | null {
  const read = useServedRead(wanted ? 'sea-zone-map' : null, () => worldSeaZoneMap(), {
    trigger: 0,
    name: 'worldSeaZoneMap',
    freshMs: SESSION_MS,
  })
  return useMemo(() => unpackZoneMap(read.view), [read.view])
}
