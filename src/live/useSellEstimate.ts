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
// ── A DOORWAY ONTO useServedRead, IN ITS 'subject' MODE (2026-09-14) ───────────────────────────
// Until 2026-09-14 this was a third private copy of "keep an answer keyed to its subject": its own
// `useState<{key, estimate}>`, its own "keep the last figure while the key moves". The SUBJECT is
// (fleet, good, the lot, the market's sell price) — what the answer depends on — and the rule that
// keeps the last answer while the next ask is on the wire is useServedRead's, not a second one
// here. NOT on the world's 3-second beat: this is a LIST, and each ask is `cmd.preview` — a real
// write, rolled back — so an open list of eight goods would be eight writes every 3 s per player
// on a live ~30-player database, for answers that cannot move unless the SUBJECT moves: the lot
// (units on board) or the served sell price, and the subject carries exactly those. So
// `reask: 'subject'` — asked once per subject, re-asked by a change of subject alone. That mode is
// the one authority's parameter (useServedRead.ts header), not a second hook.

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
  }, { reask: 'subject' })
  if (subject === null) return IDLE
  return { estimate: read.view, loading: read.loading }
}
