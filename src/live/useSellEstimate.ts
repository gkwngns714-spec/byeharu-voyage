import { findVerb, orderText, saleEstimate, type SaleEstimate } from '../domain/order'
import { cmdPreview, ok } from '../lib/rpc'
import type { FleetView, MarketGood } from '../lib/rpc'
import { useServedRead } from './useServedRead'
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
// ── A DOORWAY ONTO useServedRead (2026-09-14) ──────────────────────────────────────────────────
// Until 2026-09-14 this was a third private copy of "keep an answer keyed to its subject": its own
// `useState<{key, estimate}>`, its own "keep the last figure while the key moves". The SUBJECT is
// (fleet, good, the lot, the market's sell price) — what the answer depends on — and the rule that
// keeps the last answer while the next ask is on the wire is useServedRead's, not a second one
// here. That rule also re-asks on the world's beat, which this file used to refuse ("N goods would
// be N dry runs every 3 s"): the cost is real and named here, and it is paid because the answer
// DOES move with the world — a won bargain changes what a sale realises without the lot or the
// price moving — and a second mechanism to save the asks is the spaghetti the law forbids.

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
  // The line the button would issue, composed by the same `orderText`; `fleet.name` only decorates it.
  const line = spec && good && units > 0 ? orderText(spec, { good: good.code, qty: String(units) }, fleet.name) : null
  const subject = line !== null && good ? `${fleet.id}:${good.code}:${units}:${good.sell}` : null
  const read = useServedRead<SaleEstimate | null>(subject, async () => {
    // A refusal or a queueable line (nothing run) is ONE served value — null — so the read keeps
    // standing rather than clearing.
    const r = await cmdPreview(fleet.id, line as string, null)
    return ok<SaleEstimate | null>(r.ok && r.value.estimate ? saleEstimate(r.value.estimate) : null)
  })
  if (subject === null) return IDLE
  return { estimate: read.view, loading: read.loading }
}
