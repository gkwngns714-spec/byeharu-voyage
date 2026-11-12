import { useMemo } from 'react'
import { boundFor } from '../../../domain/order'
import { useWorld } from '../../../live/worldStore'
import type { FleetView } from '../../../lib/rpc'
import { useDeskGood } from '../../../store/deskGood'

// THE CITY IN HAND ON TRADE — one reading, for the board (Trade.tsx) and for the line that says where she is
// (TradeStatus.tsx), so the two cannot name different cities.
//
// Pressed on the map or the strip, else where she lies, else — under way — the city she is BOUND FOR. Never a stop on the
// way (2026-11-11, the trade-flow slice): a far trip sails leg by leg, and the leg's end (`voyage.to`) is a harbour she only
// takes supplies at; her queue names the destination (`boundFor`, domain/order).

export interface TradeCity {
  /** The port she lies at (CODE), or null. */
  docked: string | null
  /** Under way: the city she is bound for, past the stops on the way; null in port. */
  dest: string | null
  /** Her place for the board with no city pressed: her port, else her destination. */
  home: string | null
  /** The city in hand. */
  city: string | null
  /** She lies at the city in hand. */
  here: boolean
}

export function useTradeCity(fleet: FleetView): TradeCity {
  const portByCode = useWorld((s) => s.portByCode)
  const focus = useDeskGood((s) => s.focus)
  return useMemo(() => {
    const docked = fleet.status === 'DOCKED' ? fleet.port : null
    const dest = boundFor(fleet, (c) => portByCode[c] !== undefined) ?? fleet.voyage?.to ?? null
    const home = docked ?? dest
    const city = focus && portByCode[focus] ? focus : home
    return { docked, dest, home, city, here: docked !== null && docked === city }
  }, [fleet, portByCode, focus])
}
