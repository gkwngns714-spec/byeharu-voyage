import { useMemo } from 'react'
import { useWorld } from '../../../live/worldStore'
import type { BoardBuyRow, BoardSellRow, FleetView } from '../../../lib/rpc'
import type { PlanDraft } from './planDraft'
import type { PlanLeg } from '../../../domain/passage'
import { useHeldFleet } from '../../../live/useSailLegs'
import { planLines } from './planLines'

// THE COURSES THE TRADE PAGE DRAWS (owner rows 183 and 217) — proposed ONCE, by the one course author
// (`planLines` for a plan being made, `sailLegs` for a trip already queued), and handed to THE map on top of the
// page (TradeMap.tsx) and to the leg list under the card (PlanVoyage.tsx). Nothing here draws or prices.
//
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
  const held = useHeldFleet(fleet) ?? fleet
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
