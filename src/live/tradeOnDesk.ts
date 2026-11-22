import { useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { useCommandDraft } from '../domain/order'
import { useDeskGood } from '../store/deskGood'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// X1 (docs/design/roadmap-2026-11-23.md §4; the visual overhaul's slice 3): ONE PLACE TO TRADE. HQ > Market had its own basket and its
// own trade tray, and Office > City > Market its own trade face (the tray, the basket): three copies of trading, each with its own
// words. The Trade desk is the one; the other two keep the market's READING (the goods, their prices, the chart, Requests, Supplies)
// and their Buy / Sell presses open the desk on that city, that good and that side, for the fleet that pressed.
//
// THE FACE LIST ENTRY THAT REVERSES IT: `TRADE_ON_DESK` (./tradeOnDeskKnob.ts). False, and the HQ Market's basket and tray and the Office market's trade
// face are back exactly as they were (their code is kept, behind this one flag, until a month has passed with no complaint).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export { TRADE_ON_DESK } from './tradeOnDeskKnob'

/** Open the Trade desk on `good` at `port`, on `side`, with `fleetId` in hand. */
export function useOpenOnDesk(): (good: string, port: string, side: 'buy' | 'sell', fleetId?: string) => void {
  const open = useDeskGood((s) => s.open)
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  const navigate = useNavigate()
  return useCallback(
    (good, port, side, fleetId) => {
      if (fleetId) selectFleet(fleetId)
      open(good, port, side)
      navigate('/command')
    },
    [open, selectFleet, navigate],
  )
}
