// THE DRY RUN OF ONE TRADE LINE (0490, moved out of useTrade.ts whole): `cmd.preview` of exactly the line a trade button issues, run
// and rolled back by the server — the ONE reading of what a trade will do before the press. Two readers: the trade sheet (useTrade),
// and Your cargo's "Here" (CargoBest), which READS what selling all of a good where she lies would leave and composes no order of its
// own (tests/verbHomes.spec.ts: a COMMAND file imports no composing apparatus). A sale's estimate carries the served `trip_net`.

import { findVerb, orderText, saleEstimate, type SaleEstimate } from '../domain/order'
import { cmdPreview, ok } from '../lib/rpc'
import type { FleetView } from '../lib/rpc'
import { useServedRead } from './useServedRead'
import { useSettled } from './useSettled'
import { useWorld } from './worldStore'

/** THE DRY RUN OF ONE TRADE LINE — `cmd.preview` of exactly the line the button issues, the ONE reading of what a trade will do
 *  before the press (the trade sheet through useTrade; since 0490 also Your cargo's "Here", which previews selling all of a good
 *  where she lies). A sale's estimate carries the served `trip_net` (0490): the profit shown is the SOLD event's, not worked out here. */
export function useSaleEstimate(
  fleet: FleetView,
  intent: 'buy' | 'sell',
  /** The good's code, or null: nothing is asked. */
  code: string | null,
  /** The units on the button (0: nothing is asked). */
  n: number,
  /** 0497: SELL EVERYTHING SHE CARRIES OF IT is asked as the grammar's own ALL, not as its number: the server then sells what the
   *  quay takes today (cmd.do_sell cuts ALL to the day's allowance) where the bare number is refused whole for being over it. The
   *  owner's wreck carried 899 coral at a quay that takes 210 a day: the sell face quoted nothing and its press was refused. */
  all = false,
): { preview: SaleEstimate | null; previewLoading: boolean } {
  const verbs = useWorld((s) => s.snapshot?.verbs)
  const spec = findVerb(verbs ?? [], intent === 'buy' ? 'BUY' : 'SELL')
  // THE ORDER, PREVIEWED — either side. A DRY RUN IS A REAL WRITE, ROLLED BACK, so the quantity
  // is SETTLED first: the stepper's slider reports every step of a drag, and an un-debounced ask
  // turned a 50-step drag into 50 `cmd.do_buy` round-trips. `settled` follows `n` after the finger
  // has rested (useSettled — the one timer), and only the settled quantity is a subject.
  const settled = useSettled(n)
  // The SUBJECT is (fleet, side, good) — what the figures are FOR — and the QUESTION is the settled
  // quantity (useServedRead's `question` option, 2026-09-14). A new quantity re-asks and the last
  // served figures STAND, marked `previewLoading`, until the new ones land; a re-read of the world
  // keeps them the same way; another good shows nothing of this one's. Until 2026-09-14 the
  // quantity was part of the subject, so every press of + blanked the `You get` row and drew a
  // `Checking the price…` line for the settle plus the wire — the owner: *"when selling, a refresh
  // sign of checking the price... keeps showing up."* The line previewed is the line the button
  // issues, composed by the same `orderText`, so the figure printed and the figure realised cannot
  // be two figures. `saleEstimate` reads the keys both verbs share (`qty`, `total`, `avg_price`,
  // `haggle_saved`), the three a sale adds (`basis`, `cost`, `profit`), and since 0490 the sale's costs and its one profit
  // (`tax`, `wages`, `dock_fee`, `trip_net`), which a buy leaves null.
  const line = spec !== undefined && code !== null && settled > 0 ? orderText(spec, { good: code, qty: all ? 'ALL' : String(settled) }, fleet.name) : null
  const subject = spec !== undefined && code !== null ? `${fleet.id}:${intent}:${code}` : null
  const question = line !== null ? `${all ? 'ALL' : settled}` : null
  const dryRun = useServedRead<SaleEstimate | null>(
    subject,
    async () => {
      // A refusal here is not the tray's to render: the press states it in full. A fleet at sea
      // is QUEUEABLE and returns no estimate — there is nothing realised to print yet. Both are
      // folded into ONE served value (null) so the read keeps standing rather than clearing.
      const r = await cmdPreview(fleet.id, line as string, null)
      return ok<SaleEstimate | null>(r.ok && r.value.estimate ? saleEstimate(r.value.estimate) : null)
    },
    { question, name: 'cmdPreview', cache: false },
  )
  // The figures on screen are the last served for this good; `previewLoading` says they are not
  // yet the figures for the quantity on the button — the finger has not rested, or the answer for
  // the settled quantity is still on the wire (`stale`). A re-ask of the SAME quantity on the
  // world's beat is neither: the figures stand undimmed. The tray dims stale figures; the button
  // prints its total only once they are current, so a total is never printed against the wrong
  // quantity.
  const preview = n > 0 ? dryRun.view : null
  const previewLoading = n > 0 && subject !== null && (settled !== n || dryRun.stale || (dryRun.view === null && dryRun.loading))
  return { preview, previewLoading }
}
