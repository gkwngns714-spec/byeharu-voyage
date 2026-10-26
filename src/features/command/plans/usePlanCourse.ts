import { useMemo, useState } from 'react'
import { useWorld } from '../../../live/worldStore'
import type { BoardBuyRow, BoardSellRow, FleetView } from '../../../lib/rpc'
import type { PlanDraft } from './planDraft'
import { planLines, sailLegs, type PlanLeg } from './planLines'

// THE COURSES THE TRADE PAGE DRAWS (owner rows 183 and 217) — proposed ONCE, by the one course author
// (`planLines` for a plan being made, `sailLegs` for a trip already queued), and handed to THE map on top of the
// page (TradeMap.tsx) and to the leg list under the card (PlanVoyage.tsx). Nothing here draws or prices.
//
// THE FLEET THE COURSES ARE PROPOSED FROM is held while nothing about where she starts has changed: the world is
// re-read every 3 s and every read is a new object, and proposing a course is the pathfinder's work. A new version
// (a trade, an arrival, an order) or status hands the new one over (derive-from-the-last-render).

function useHeldFleet(fleet: FleetView): FleetView {
  const key = `${fleet.id}:${fleet.version}:${fleet.status}:${fleet.port ?? ''}`
  const [held, setHeld] = useState({ key, fleet })
  if (held.key !== key) setHeld({ key, fleet })
  return held.key === key ? held.fleet : fleet
}

const NONE: readonly PlanLeg[] = []

/** The plan's legs: to the buy city through the board's stops, then on to the sell city (`planLines`). */
export function usePlanCourse(
  fleet: FleetView,
  plan: PlanDraft | null,
  buyRow: BoardBuyRow | null,
  sellRow: BoardSellRow | null,
): readonly PlanLeg[] {
  const seaNav = useWorld((s) => s.seaNav)
  const portByCode = useWorld((s) => s.portByCode)
  const held = useHeldFleet(fleet)
  const toBuyKey = (buyRow?.stops ?? []).join(' ')
  const toSellKey = (sellRow?.stops ?? []).join(' ')
  return useMemo(() => {
    if (!seaNav || !plan?.sellAt) return NONE
    const text = planLines(plan, held, seaNav, portByCode, {
      toBuy: toBuyKey ? toBuyKey.split(' ') : [],
      toSell: toSellKey ? toSellKey.split(' ') : [],
    })
    return text.ok ? text.legs : NONE
  }, [seaNav, plan, held, portByCode, toBuyKey, toSellKey])
}

/** A queued trip's legs: through its SAILs' harbours, in order, from where she is now (`sailLegs`). */
export function useSailLegs(fleet: FleetView, codes: readonly string[]): readonly PlanLeg[] {
  const seaNav = useWorld((s) => s.seaNav)
  const portByCode = useWorld((s) => s.portByCode)
  const held = useHeldFleet(fleet)
  const key = codes.join(' ')
  return useMemo(
    () => (seaNav && key ? sailLegs(held, seaNav, portByCode, key.split(' ')) : NONE),
    [seaNav, held, portByCode, key],
  )
}
