// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT IS THIS CITY KEEPING FOR ME? — asked, not worked out.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// How full a shed is, what it will still take, and what she is carrying are all facts the server
// decides, and a screen that recomputed any of them from a manifest would be a second
// implementation of a rule `cmd.do_store` enforces.
//
// One read carries BOTH sides — ashore and aboard — because this screen's whole job is moving
// goods between them, and two reads could disagree by a trade landed in between.
//
// Re-asked whenever the world is read again — a STORE moves cargo out of her hold, and the next
// answer has to say so on both sides at once. The mechanism (and why the last answer stays on
// screen while it re-asks) is useServedRead.ts.

import { worldWarehouse } from '../lib/rpc'
import type { WarehouseView } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

export type WarehouseState = ServedRead<WarehouseView>

export function useWarehouse(portId: string | null, fleetId: string | null): WarehouseState {
  return useServedRead(portId ? `${portId}:${fleetId ?? '-'}` : null, () =>
    worldWarehouse(portId as string, fleetId),
  )
}
