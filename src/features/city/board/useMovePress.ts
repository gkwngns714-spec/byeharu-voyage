import { useCallback } from 'react'
import { useCommandDraft } from '../../../domain/order'
import { openHq } from '../../../app/hqPlace'
import { pressServed } from './servedPress'
import type { MoveData } from './useBoard'

// ONE PRESS, THE CARD'S OWN ACT, IN PLACE (docs/design/hq-command-2026-11-23.md; 0480). A card of the served board commits its own
// act through the building's own door (servedPress.ts): a trade card buys and sails, a yard card orders, a crew card hires. HQ stays
// where it was, and nothing jumps to another tab.
//
// The v1 cards (ranked on the client, each opening a sheet: trade, request, yard, crew, invest) went with H2's v1 ranking; their
// cases here and their `MoveData` variants were deleted by H3 (2026-11-24). Once H1's Assign sheet exists, a card's press opens it
// filled in (`openHq({ sheet: 'assign', move })`) instead of committing: docs/design/hq-corp-2026-11-24.md C3.

export function useMovePress(): (m: MoveData) => void {
  return useCallback((m: MoveData) => void pressServed(m.move, m.fleet), [])
}

/** A fleet row's press: her sheet over HQ (cargo, route, orders), her route first on `route`. */
export function useFleetPress(): (fleet: string, route: boolean) => void {
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  return useCallback(
    (fleet: string, route: boolean) => {
      selectFleet(fleet)
      openHq({ sheet: 'fleet', fleet, route })
    },
    [selectFleet],
  )
}
