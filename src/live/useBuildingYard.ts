// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT CAN THIS YARD LAY DOWN? — asked, not worked out.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The same shape as `useWorkstation` and `useWarehouse`. "Can she be built here" is three rules —
// does this city keep a yard, is it good enough for this hull, and is every material ashore — and
// all three are `cmd.do_build`'s. A screen that worked them out from a recipe and a warehouse
// would be a second implementation of them.
//
// No fleet in the key, deliberately: a hull comes out of the CITY, not out of a hold, so what she
// is carrying does not change the answer. That is the whole reason storage was built first.

import { useEffect, useState } from 'react'
import { worldBuildingYard } from '../lib/rpc'
import type { BuildingYardView } from '../lib/rpc'
import { useWorld } from './worldStore'

export interface BuildingYardState {
  view: BuildingYardView | null
  loading: boolean
}

const IDLE: BuildingYardState = { view: null, loading: false }
const WAITING: BuildingYardState = { view: null, loading: true }

export function useBuildingYard(portId: string | null): BuildingYardState {
  // Re-asked whenever the world is read again — landing a cargo in the shed changes what can be
  // laid down, and so does building something.
  const readAt = useWorld((s) => s.readAt)
  const key = portId ? `${portId}:${readAt ?? 0}` : null

  const [answer, setAnswer] = useState<{ key: string; state: BuildingYardState } | null>(null)

  useEffect(() => {
    if (!key || !portId) return
    let live = true
    void worldBuildingYard(portId).then((r) => {
      if (!live) return
      setAnswer({ key, state: { view: r.ok ? r.value : null, loading: false } })
    })
    return () => {
      live = false
    }
  }, [key, portId])

  if (!key) return IDLE
  return answer?.key === key ? answer.state : WAITING
}
