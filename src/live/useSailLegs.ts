import { useMemo, useState } from 'react'
import { sailLegs, type PlanLeg } from '../domain/passage'
import type { FleetView } from '../lib/rpc'
import { useWorld } from './worldStore'

// THE FLEET THE COURSES ARE PROPOSED FROM is held while nothing about where she starts has changed: the world is
// re-read every 3 s and every read is a new object, and proposing a course is the pathfinder's work. A new version
// (a trade, an arrival, an order) or status hands the new one over (derive-from-the-last-render).

export function useHeldFleet(fleet: FleetView | null): FleetView | null {
  const key = fleet ? `${fleet.id}:${fleet.version}:${fleet.status}:${fleet.port ?? ''}` : ''
  const [held, setHeld] = useState({ key, fleet })
  if (held.key !== key) setHeld({ key, fleet })
  return held.key === key ? held.fleet : fleet
}

const NONE: readonly PlanLeg[] = []

/** A queued trip's legs: through its SAILs' harbours, in order, from where she is now (`sailLegs`). */
export function useSailLegs(fleet: FleetView | null, codes: readonly string[]): readonly PlanLeg[] {
  const seaNav = useWorld((s) => s.seaNav)
  const portByCode = useWorld((s) => s.portByCode)
  const held = useHeldFleet(fleet)
  const key = codes.join(' ')
  return useMemo(
    () => (seaNav && held && key ? sailLegs(held, seaNav, portByCode, key.split(' ')) : NONE),
    [seaNav, held, portByCode, key],
  )
}
