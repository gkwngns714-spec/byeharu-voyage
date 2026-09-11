// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MANIFEST, PRICED — every staged line through the real verbs, rolled back, as one answer.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/QUAY_LEDGER.md §3 C: the manifest face prints served totals — goods at mid, the tax, the
// spread after haggle, profit vs paid, net to purse, purse after, hold after. None of those can be
// summed on this side of the wire (a buy walks a stepped book; the tax and the cut are per step
// inside `world.quote`), so the ONE reading is `cmd.preview_basket` (0083), and this hook is the
// one place it is asked. PortTrade asks once and hands the answer down: the tray prints it and the
// hold gauge draws `hold.tuns_delta` from it. A second ask would be a second estimate that could
// disagree with the first for the same lines.
//
// SHAPED AFTER ./useTrade.ts's dry run, DELIBERATELY. Keyed by (fleet, the lines, the last read),
// so an answer for other lines — or from before the world was read again — is never shown; settled
// for PREVIEW_SETTLE_MS (lib/trade, the same constant the line preview waits) because a dry run is
// a real write and a stepper drag reports every step; the `live` guard discards an answer whose key
// has moved on. UNLIKE useTrade, THE REFUSAL IS KEPT: a line's tray has a button whose press states
// the refusal in full, but a manifest has no other place to say which line the quay refused, and
// `refusal.line` (the input index, result.ts) is what lets the tray say it under that line.
//
// `reask()` is for E_BUSY only — the quay was locked by the market's own clock and nothing was
// decided; asking again is the fix the server itself names. It is not a retry loop.

import { useCallback, useEffect, useState } from 'react'
import { cmdPreviewBasket } from '../lib/rpc'
import type { FleetView, ManifestLine, ManifestReceipt, Refusal } from '../lib/rpc'
import { PREVIEW_SETTLE_MS } from '../lib/trade'
import { useWorld } from './worldStore'

export interface ManifestPreviewState {
  /** The receipt the commit would produce, for THESE lines as of the last read. Null until it lands
   *  or when the quay refused. */
  estimate: ManifestReceipt | null
  /** Why the quay would refuse this manifest, with `line` naming the input line where one did. */
  refusal: Refusal | null
  /** True while a dry run for these lines has been asked and not yet answered. */
  loading: boolean
  /** Ask again with the same lines — the answer to E_BUSY. */
  reask: () => void
}

interface Answer {
  key: string
  estimate: ManifestReceipt | null
  refusal: Refusal | null
}

/** The one spelling of "these lines" as a key: side, good and tuns, in input order. */
function linesKey(lines: readonly ManifestLine[]): string {
  return lines.map((l) => `${l.side}:${l.good}:${l.qty}`).join(',')
}

export function useManifestPreview(fleet: FleetView, lines: readonly ManifestLine[]): ManifestPreviewState {
  const readAt = useWorld((s) => s.readAt)
  const [asked, setAsked] = useState(0)
  const key = lines.length > 0 ? `${fleet.id}:${linesKey(lines)}:${readAt ?? 0}:${asked}` : null
  const [answer, setAnswer] = useState<Answer | null>(null)

  useEffect(() => {
    if (!key) return
    let live = true
    const timer = setTimeout(() => {
      void cmdPreviewBasket(fleet.id, lines).then((r) => {
        if (!live) return
        setAnswer(r.ok ? { key, estimate: r.value.estimate, refusal: null } : { key, estimate: null, refusal: r.refusal })
      })
    }, PREVIEW_SETTLE_MS)
    return () => {
      live = false
      clearTimeout(timer)
    }
    // `lines` and `fleet.id` are folded into `key`, which is the one thing that decides a re-ask.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key])

  const reask = useCallback(() => setAsked((n) => n + 1), [])

  if (key === null) return { estimate: null, refusal: null, loading: false, reask }
  if (answer?.key !== key) return { estimate: null, refusal: null, loading: true, reask }
  return { estimate: answer.estimate, refusal: answer.refusal, loading: false, reask }
}
