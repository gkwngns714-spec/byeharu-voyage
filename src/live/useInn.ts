// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHO IS DRINKING HERE TODAY? — asked, and deliberately not refreshable.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The same shape as the other three port reads. What is different is WHY the answer is stable:
// `world.inn` derives the room from (officer, port, day, world secret), so asking again gives the
// same faces. That is the point — an officer who could be re-rolled by reloading would make the
// good ones free, and the owner asked for the good ones to be rare.
//
// The key still carries `readAt` so the room re-reads after an order (signing somebody changes
// whether she is offered), but nothing about the READ can change who is in it.

import { useEffect, useState } from 'react'
import { worldInn } from '../lib/rpc'
import type { InnView } from '../lib/rpc'
import { useWorld } from './worldStore'

export interface InnState {
  view: InnView | null
  loading: boolean
}

const IDLE: InnState = { view: null, loading: false }
const WAITING: InnState = { view: null, loading: true }

export function useInn(portId: string | null): InnState {
  const readAt = useWorld((s) => s.readAt)
  const key = portId ? `${portId}:${readAt ?? 0}` : null

  const [answer, setAnswer] = useState<{ key: string; state: InnState } | null>(null)

  useEffect(() => {
    if (!key || !portId) return
    let live = true
    void worldInn(portId).then((r) => {
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
