import { Segmented } from '../../components/ui'
import { TRADE_FACES, useTradeFace } from './tradeFace'

// THE STRIP — Buy · Sell · Requests, one `Segmented` over the one store (tradeFace.ts). Composed
// by the quay she lies at (PortTrade.tsx) and by a quay she is only reading (PortPrices.tsx), so
// the two draw one control rather than each its own. A press SELECTS a face; it inserts nothing
// above itself and moves nothing above the board (owner row 15).
export function TradeFaces() {
  const face = useTradeFace((s) => s.face)
  const turnTo = useTradeFace((s) => s.turnTo)
  return <Segmented label="Trade faces" segments={TRADE_FACES} value={face} onChange={turnTo} className="mt-3" />
}
