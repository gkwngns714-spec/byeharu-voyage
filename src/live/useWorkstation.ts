// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT CAN SHE MAKE HERE? — asked, not worked out.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// "Can she make a suit of sails here, and what would it take?" is a rule `cmd.do_make` enforces,
// and a client that worked it out from the manifest would be a second copy of that rule with its
// own way of drifting. The server answers; this hook carries the answer.
//
// Re-asked whenever the world is read again — a MAKE spends her cargo, and the next answer must
// say so. The mechanism (and why the last answer stays on screen while it re-asks) is
// useServedRead.ts.

import { worldWorkstation } from '../lib/rpc'
import type { WorkstationView } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

export type WorkstationState = ServedRead<WorkstationView>

export function useWorkstation(portId: string | null, fleetId: string | null): WorkstationState {
  return useServedRead(portId ? `${portId}:${fleetId ?? '-'}` : null, () =>
    worldWorkstation(portId as string, fleetId),
  )
}
