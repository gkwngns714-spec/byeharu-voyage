// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT CAN THIS CITY MAKE? — asked, not worked out.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The same discipline as `useBuyCapacity`, and for the same reason. "Can she make a suit of sails
// here" is three rules at once — does this city keep a workstation, is it good enough for this
// fitting, and is every input in her hold — and all three are enforced by `cmd.do_make`. A screen
// that worked them out from a recipe and a manifest would be a SECOND implementation of them, and
// the two would disagree the first day either changed.
//
// So `world.workstation(port, fleet)` answers all of it, and this file is only the asking. The
// answer is keyed by (port, fleet, last read): a hold emptied by a trade changes what is makeable,
// and a stale yes is exactly the bug useBuyCapacity was written to remove.

import { useEffect, useState } from 'react'
import { worldWorkstation } from '../lib/rpc'
import type { WorkstationView } from '../lib/rpc'
import { useWorld } from './worldStore'

export interface WorkstationState {
  view: WorkstationView | null
  loading: boolean
}

const IDLE: WorkstationState = { view: null, loading: false }
const WAITING: WorkstationState = { view: null, loading: true }

export function useWorkstation(portId: string | null, fleetId: string | null): WorkstationState {
  // Re-asked whenever the world is read again — a MAKE spends her cargo, and the next answer must
  // say so.
  const readAt = useWorld((s) => s.readAt)
  const key = portId ? `${portId}:${fleetId ?? '-'}:${readAt ?? 0}` : null

  const [answer, setAnswer] = useState<{ key: string; state: WorkstationState } | null>(null)

  useEffect(() => {
    if (!key || !portId) return
    let live = true
    void worldWorkstation(portId, fleetId).then((r) => {
      if (!live) return
      setAnswer({ key, state: { view: r.ok ? r.value : null, loading: false } })
    })
    return () => {
      live = false
    }
  }, [key, portId, fleetId])

  if (!key) return IDLE
  // An answer that belongs to a different (port, fleet, read) is not this question's answer.
  return answer?.key === key ? answer.state : WAITING
}
