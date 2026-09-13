// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT CAN THIS YARD LAY DOWN? — asked, not worked out.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Re-asked whenever the world is read again — landing a cargo in the shed changes what can be
// laid down, and so does building something. The mechanism (and why the last answer stays on
// screen while it re-asks) is useServedRead.ts.

import { worldBuildingYard } from '../lib/rpc'
import type { BuildingYardView } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

export type BuildingYardState = ServedRead<BuildingYardView>

export function useBuildingYard(portId: string | null): BuildingYardState {
  return useServedRead(portId, () => worldBuildingYard(portId as string))
}
