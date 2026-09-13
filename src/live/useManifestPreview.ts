// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BASKET, PRICED — every staged line through the real verbs, rolled back, as one answer that
// KEEPS STANDING while the next one is on the wire.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/QUAY_LEDGER.md §3 C: the basket prints served totals — the tax, the port's fee, what the
// haggle saved, profit against what was paid, the net. None of those can be summed on this side of
// the wire (a buy walks a stepped book; the tax and the fee are per step inside `world.quote`), so
// the ONE reading is `cmd.preview_basket` (0083), and this hook is the one place it is asked.
//
// ── A DOORWAY ONTO useServedRead, NOT A SECOND HOOK ────────────────────────────────────────────
// PR #59's first cut of this file keyed its ask on the world's `readAt` and answered
// `{estimate: null, loading: true}` every time the key moved — and the shell reads the world every
// 3 s (AppShell.tsx, READ_MIN_MS), so every 3 s the basket's total rows unmounted, its title lost
// its net and its one button went dead (the adversarial review's MUST-FIX 1). That is exactly the
// defect `useServedRead` was written to end, in four other port hooks, the same day. So this hook
// is one line of subject and one line of ask on that rule: the SUBJECT is (fleet, port, the lines
// in input order), a re-read of the same subject keeps the last answer on screen and marks it
// `loading`, and a new subject — a line added, removed or re-quantified — shows nothing of the old
// one. The button is never disabled on `loading`.
//
// ── A REFUSAL IS THE ANSWER HERE, NOT THE ABSENCE OF ONE ───────────────────────────────────────
// `useServedRead` clears the view on a refusal, because for the shed or the inn a refusal means
// there is nothing to draw. For a basket the refusal IS what to draw: `refusal.line` (result.ts) is
// the server's word for which input line it will not take, and the panel prints the sentence
// under that line. So the ask folds both outcomes into ONE served value — an estimate, or a refusal
// — and hands it to useServedRead as `ok`. Nothing is swallowed; the refusal crosses the boundary
// as data, which is worldStore's rule 2.
//
// No settle timer: a line is staged by ONE press (the quantity was chosen, and debounced, in the
// trade tray by `useTrade`), so the subject moves once per press and there is nothing to debounce.
// No `reask()`: `E_BUSY` — the market's clock held the rows — is re-asked by the world's next beat.

import { cmdPreviewBasket, ok } from '../lib/rpc'
import type { ManifestLine, ManifestReceipt, Refusal } from '../lib/rpc'
import { useServedRead } from './useServedRead'

export interface ManifestPreviewState {
  /** The receipt the commit would produce, for THESE lines as of the last read. Null until the
   *  first answer lands, or when the market refused. */
  estimate: ManifestReceipt | null
  /** Why the market would refuse this basket, with `line` naming the input line where one did. */
  refusal: Refusal | null
  /** True while an ask is on the wire — the first one, or a re-ask on the world's beat. */
  loading: boolean
}

/** What the market said about these lines: an estimate, or a refusal naming a line. */
interface Priced {
  estimate: ManifestReceipt | null
  refusal: Refusal | null
}

/** The one spelling of "these lines" as a subject: side, good and units, in input order. */
function linesKey(lines: readonly ManifestLine[]): string {
  return lines.map((l) => `${l.side}:${l.good}:${l.qty}`).join(',')
}

export function useManifestPreview(fleetId: string, portCode: string, lines: readonly ManifestLine[]): ManifestPreviewState {
  const subject = lines.length > 0 ? `${fleetId}:${portCode}:${linesKey(lines)}` : null
  const read = useServedRead<Priced>(subject, async () => {
    const r = await cmdPreviewBasket(fleetId, lines)
    return ok<Priced>(r.ok ? { estimate: r.value.estimate, refusal: null } : { estimate: null, refusal: r.refusal })
  })
  return { estimate: read.view?.estimate ?? null, refusal: read.view?.refusal ?? null, loading: read.loading }
}
