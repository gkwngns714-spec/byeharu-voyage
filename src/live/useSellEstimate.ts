import { useEffect, useState } from 'react'
import { findVerb, orderText, saleEstimate, type SaleEstimate } from '../domain/order'
import { cmdPreview } from '../lib/rpc'
import type { FleetView, MarketGood } from '../lib/rpc'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT SELLING THE WHOLE LOT WOULD REALISE — asked of the server, one answer per (good, lot, price).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-09-13 (row 82): the goods on board should show *"how much loss/profit the action
// will do"*. A profit is `cmd.do_sell`'s own arithmetic against the served cost basis, and the sale
// walks the book in steps (§G.2), so a client `(sell − paid) × units` would be wrong for every lot
// bigger than one step. So the figure is `cmd.preview` of `SELL <good> <all of it>` — run for real
// and rolled back — read through `saleEstimate`, exactly as the trade tray's button is priced.
//
// ── WHEN IT IS RE-ASKED, AND WHEN IT IS NOT ────────────────────────────────────────────────────
// Not on the world's 3-second beat: a list of N goods would be N dry runs every 3 s for nothing
// that can have changed. The answer moves only when what it depends on moves — the lot (units on
// board) or the market's served sell price — so the key is exactly those, and the last answer
// stands until they do. The trade tray keys its preview on `readAt` because ONE open tray may; a
// list may not.

const IDLE: { estimate: SaleEstimate | null; loading: boolean } = { estimate: null, loading: false }

export function useSellEstimate(
  fleet: FleetView,
  /** The market's row for a good on board, or null when this market does not list it. */
  good: MarketGood | null,
  /** Units on board — the lot the preview sells. */
  units: number,
): { estimate: SaleEstimate | null; loading: boolean } {
  const verbs = useWorld((s) => s.snapshot?.verbs)
  const spec = findVerb(verbs ?? [], 'SELL')
  const key = spec && good && units > 0 ? `${fleet.id}:${good.code}:${units}:${good.sell}` : null
  const [answer, setAnswer] = useState<{ key: string; estimate: SaleEstimate | null } | null>(null)

  useEffect(() => {
    if (!key || !spec || !good) return
    let live = true
    void cmdPreview(fleet.id, orderText(spec, { good: good.code, qty: String(units) }, fleet.name), null).then((r) => {
      if (!live) return
      setAnswer({ key, estimate: r.ok && r.value.estimate ? saleEstimate(r.value.estimate) : null })
    })
    return () => {
      live = false
    }
    // `spec`, `good` and `units` are folded into `key`; `fleet.name` only decorates the line.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, fleet.id])

  if (!key) return IDLE
  if (answer?.key === key) return { estimate: answer.estimate, loading: false }
  // A key that moved keeps the last figure on screen while the fresh one is on the wire.
  return { estimate: answer?.estimate ?? null, loading: true }
}
