// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADE, READ AND DONE — the one act behind the one tray, for the two quays that open it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/UI_DIRECTION.md §6, PORT: *"TRAY: identical to Command's buy tray (same component, same
// `issue`)"*. The COMPONENT is `TradeTray` in the design system, and the design system may read
// nothing above it (tests/sections.spec.ts, "machinery knows nothing above it") — so what a press
// of its one button DOES has to arrive as a prop. On 2026-09-09 that prop was written twice: once
// inside PORT's own copy of the tray, once inline in COMMAND's TradeQuestion, each with its own
// `sending`, its own `refusal`, its own "the total is the server's only when the quantity is the
// ceiling" rule. Same verb grammar, same door, same three lines of state — two authorities. This
// is the one.
//
// WHAT IT READS: the verb grammar and the trade step off the snapshot, the one door (`issue`),
// `world.buy_capacity()` through the one hook that asks it, what the fleet PAID for the good
// (served on the fleet, 0081 — never remembered here), and `cmd.preview()` of the exact line the
// button will issue — on BOTH sides since 2026-09-11 — so every figure the tray prints is the
// server's own arithmetic for the quantity chosen. WHAT IT RETURNS is exactly the shape the tray
// takes (`TradeControls`, declared beside the tray), so a screen composes
// `<TradeTray … trade={useTrade(…)}>` and owns nothing but the pick and the quantity.
//
// NO PRICE IS MULTIPLIED OUT HERE, AND NOTHING IS SUBTRACTED. Buying walks a stepped book (§G.2),
// so a total is only ever a SERVED total for the quantity it is printed against. Until 2026-09-11
// the buy side had one such figure — `est_total`, priced by `world.buy_capacity` at the ceiling —
// so the button read `Buy 20 t` with no figure at every other quantity. The dry run that already
// priced a sale prices a buy the same way (`cmd.do_buy`'s own `{qty, total}`, run and rolled back;
// 0008:692 reads exactly that key off a previewed BUY), and `est_total` remains the fallback at
// the ceiling while the dry run is in flight. A sale's proceeds, cost and profit are
// `cmd.do_sell`'s own result (the owner's row 74). A client that subtracted the served basis from
// the served bid would be a second ledger wearing a smaller hat, and wrong by the book's steps.

import { useEffect, useState } from 'react'
import type { TradeControls } from '../components/ui'
import { paidPerTun } from '../domain/fleet'
import { findVerb, orderText, saleEstimate, type SaleEstimate } from '../domain/order'
import { cmdPreview } from '../lib/rpc'
import type { FleetView, MarketGood, Refusal } from '../lib/rpc'
import { PREVIEW_SETTLE_MS } from '../lib/trade'
import { useBuyCapacity } from './useBuyCapacity'
import { useWorld } from './worldStore'

export function useTrade(
  fleet: FleetView,
  intent: 'buy' | 'sell',
  /** The good in the open tray, or null while no tray is open. */
  good: MarketGood | null,
  /** The caller's quantity — the draft's `qty`, or the screen's local state. */
  qty: number | null,
  /** Called once the order is issued: the tray closes, the pick is cleared. */
  onDone: () => void,
): TradeControls {
  const issue = useWorld((s) => s.issue)
  // A SELECTOR RETURNS A SERVED REFERENCE, never a fresh literal: `?? []` builds a new array on
  // every read and zustand compares by identity, which is a render loop (React error #185).
  const verbs = useWorld((s) => s.snapshot?.verbs)
  const step = useWorld((s) => s.snapshot?.config.trade_step_tuns ?? 1)
  // Re-asked whenever the world is read again — the same key useBuyCapacity turns on.
  const readAt = useWorld((s) => s.readAt)

  // ONE reading of world.buy_capacity(), and only while BUYING — a sell has no purse ceiling.
  const capacity = useBuyCapacity(intent === 'buy' && good ? fleet.id : null, good?.code ?? null)

  const [sending, setSending] = useState(false)
  // A refusal belongs to the pick that earned it, so it is stored WITH that pick's key and read
  // back only while the same good and the same price are open — another good, or the other price,
  // starts clean without anything having to be cleared (the shape useBuyCapacity keeps its answer in).
  const key = good ? `${good.code}:${intent}` : null
  const [refused, setRefused] = useState<{ key: string; refusal: Refusal | null } | null>(null)
  const refusal = refused !== null && refused.key === key ? refused.refusal : null

  const spec = findVerb(verbs ?? [], intent === 'buy' ? 'BUY' : 'SELL')
  const n = qty ?? 0
  const ready = spec !== undefined && good !== null && n > 0

  // THE ORDER, PREVIEWED — either side. Keyed by (fleet, side, good, quantity, last read), exactly
  // as the buy ceiling is, so an answer for another quantity — or from before the world was read
  // again — is never shown: the tray waits instead. The line previewed is the line the button
  // issues, composed by the same `orderText`, so the figure printed and the figure realised cannot
  // be two figures. `saleEstimate` reads the keys both verbs share (`qty`, `total`) and the three a
  // sale adds (`basis`, `cost`, `profit`), which a buy leaves null.
  const previewKey =
    spec !== undefined && good !== null && n > 0 ? `${fleet.id}:${intent}:${good.code}:${n}:${readAt ?? 0}` : null
  const [answer, setAnswer] = useState<{ key: string; estimate: SaleEstimate | null } | null>(null)
  useEffect(() => {
    if (!previewKey || !spec || !good) return
    // A DRY RUN IS A REAL WRITE, ROLLED BACK. The stepper's slider reports every step of a drag,
    // and each report is a new quantity, so an un-debounced effect turned a 50-step drag into 50
    // `cmd.do_buy` round-trips. The ask waits until the finger has rested for PREVIEW_SETTLE_MS;
    // the `live` guard still discards an answer that arrives after the key has moved on.
    let live = true
    const timer = setTimeout(() => {
      void cmdPreview(fleet.id, orderText(spec, { good: good.code, qty: String(n) }, fleet.name), null).then((r) => {
        if (!live) return
        // A refusal here is not the tray's to render: the press states it in full. A fleet at sea
        // is QUEUEABLE and returns no estimate — there is nothing realised to print yet.
        const estimate = r.ok && r.value.estimate ? saleEstimate(r.value.estimate) : null
        setAnswer({ key: previewKey, estimate })
      })
    }, PREVIEW_SETTLE_MS)
    return () => {
      live = false
      clearTimeout(timer)
    }
    // `spec`, `good`, `intent` and `n` are folded into `previewKey`; `fleet.name` only decorates the line.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [previewKey, fleet.id])
  const preview = previewKey !== null && answer?.key === previewKey ? answer.estimate : null
  const previewLoading = previewKey !== null && answer?.key !== previewKey

  const send = () => {
    if (!spec || !good || !key || n <= 0 || sending) return
    setSending(true)
    setRefused(null)
    void (async () => {
      // THE LINE IS COMPOSED AT ISSUE TIME AND NEVER PRINTED (§5). `orderText` walks the server's
      // own verb grammar, so there is one composer on this side of the wire — no screen writes an
      // order string, and the player never reads one.
      const okay = await issue(fleet.id, orderText(spec, { good: good.code, qty: String(n) }, fleet.name), null)
      setSending(false)
      if (okay) onDone()
      else setRefused({ key, refusal: useWorld.getState().refusal })
    })()
  }

  // The served total for THIS quantity: the dry run's, else — while it is in flight, and only at
  // the ceiling `world.buy_capacity` priced — the capacity read's own `est_total`.
  const total =
    preview?.total ??
    (intent === 'buy' && capacity.estTotal !== null && capacity.bound !== null && n === capacity.bound.max
      ? capacity.estTotal
      : null)

  const paid = good ? paidPerTun(fleet, good.code) : null

  return { capacity, step, act: { send, sending, ready, total, refusal, paid, preview, previewLoading } }
}
