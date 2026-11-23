import { useMemo } from 'react'
import { seaRows, unpackZoneMap, type SeaRow, type ZoneCells } from '../domain/seas'
import { worldSeaZoneMap } from '../lib/rpc'
import { SESSION_MS } from '../store/resourceCache'
import { useSeaConditions } from './useSeaConditions'
import { useServedRead } from './useServedRead'

// THE SEAS, BY NAME — the one hook the Map's Seas filter and the Codex's Seas face read the zones through (world.sea_conditions).
// No sea is called closed: the sea limits are off (docs/design/hq-command-2026-11-23.md).

export function useSeaRows(): { rows: SeaRow[]; loading: boolean } {
  const read = useSeaConditions()
  return useMemo(() => ({ rows: seaRows(read.view), loading: read.loading }), [read.view, read.loading])
}

/** WHICH SEA EVERY CELL OF THE CHART IS IN (world.sea_zone_map, 0396). World data: asked once a session, and only when `wanted`
 *  (the Map's Seas filter is on). */
export function useSeaZoneCells(wanted: boolean): ZoneCells | null {
  const read = useServedRead(wanted ? 'sea-zone-map' : null, () => worldSeaZoneMap(), {
    trigger: 0,
    name: 'worldSeaZoneMap',
    freshMs: SESSION_MS,
  })
  return useMemo(() => unpackZoneMap(read.view), [read.view])
}
