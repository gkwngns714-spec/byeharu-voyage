// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT IS THIS CITY KEEPING FOR ME? — asked, not worked out.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The same shape as `useWorkstation` and `useBuyCapacity`, and for the same reason: how full a shed
// is, what it will still take, and what she is carrying are all facts the server decides, and a
// screen that recomputed any of them from a manifest would be a second implementation of a rule
// `cmd.do_store` enforces.
//
// One read carries BOTH sides — ashore and aboard — because this screen's whole job is moving
// goods between them, and two reads could disagree by a trade landed in between.

import { useEffect, useState } from 'react'
import { worldWarehouse } from '../lib/rpc'
import type { WarehouseView } from '../lib/rpc'
import { useWorld } from './worldStore'

export interface WarehouseState {
  view: WarehouseView | null
  loading: boolean
}

const IDLE: WarehouseState = { view: null, loading: false }
const WAITING: WarehouseState = { view: null, loading: true }

export function useWarehouse(portId: string | null, fleetId: string | null): WarehouseState {
  // Re-asked whenever the world is read again — a STORE moves cargo out of her hold, and the next
  // answer has to say so on both sides at once.
  const readAt = useWorld((s) => s.readAt)
  const key = portId ? `${portId}:${fleetId ?? '-'}:${readAt ?? 0}` : null

  const [answer, setAnswer] = useState<{ key: string; state: WarehouseState } | null>(null)

  useEffect(() => {
    if (!key || !portId) return
    let live = true
    void worldWarehouse(portId, fleetId).then((r) => {
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
