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
//
// ── THE DRY RUN IS A DOORWAY ONTO useServedRead (slice 3, 2026-09-13) ──────────────────────────
// Until slice 3 this hook kept its own copy of "ask again when the world is read, and throw the
// old answer away meanwhile": the preview's key carried `readAt`, so every 3 s (AppShell.tsx,
// READ_MIN_MS) the `You get` row and the button's figure went blank until the re-ask landed — row
// 77's defect, in the one tray that had not been folded. The haggle thread stakes this preview's
// `avg_price` on both sides and a thread cannot blink. So the dry run is one subject and one ask
// on `useServedRead`: the SUBJECT is (fleet, side, good, the SETTLED quantity), a re-read of the
// same subject keeps the last answer on screen and marks it `loading`, and a new quantity shows
// nothing of the old one. The settle timer survives as a settled COPY of the quantity — the
// stepper's slider reports every step of a drag, and each step is a new subject, so the subject
// only moves once the finger has rested PREVIEW_SETTLE_MS. The figure printed is still the figure
// for the quantity on the button: the answer is exposed only while the settled quantity IS the
// button's.

import { useEffect, useState } from 'react'
import type { TradeControls } from '../components/ui'
import { paidPerTun } from '../domain/fleet'
import { findVerb, orderText, saleEstimate, type SaleEstimate } from '../domain/order'
import { cmdPreview, ok } from '../lib/rpc'
import type { FleetView, MarketGood, Refusal } from '../lib/rpc'
import { useBuyCapacity } from './useBuyCapacity'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'

/** How long a chosen quantity must stand still before the server is asked to price it. Long
 *  enough that a slider drag is one ask; short enough that a tap on + reads as immediate. */
const PREVIEW_SETTLE_MS = 200

export function useTrade(
  fleet: FleetView,
  intent: 'buy' | 'sell',
  /** The good in the open tray, or null while no tray is open. */
  good: MarketGood | null,
  /** The caller's quantity — the draft's `qty`, or the screen's local state. */
  qty: number | null,
  /** Called once the order is issued: the tray closes, the pick is cleared. */
  onDone: () => void,
  /** THE BASKET'S DOOR (slice 2): stage this line for the chosen quantity instead of issuing it.
   *  Given by a quay with a basket; absent, the tray draws no `Add to basket`. */
  onStage?: (qty: number) => void,
): TradeControls {
  const issue = useWorld((s) => s.issue)
  // A SELECTOR RETURNS A SERVED REFERENCE, never a fresh literal: `?? []` builds a new array on
  // every read and zustand compares by identity, which is a render loop (React error #185).
  const verbs = useWorld((s) => s.snapshot?.verbs)
  const step = useWorld((s) => s.snapshot?.config.trade_step_tuns ?? 1)

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

  // THE ORDER, PREVIEWED — either side. A DRY RUN IS A REAL WRITE, ROLLED BACK, so the quantity
  // is SETTLED first: the stepper's slider reports every step of a drag, and an un-debounced ask
  // turned a 50-step drag into 50 `cmd.do_buy` round-trips. `settled` follows `n` after the finger
  // has rested PREVIEW_SETTLE_MS, and only the settled quantity is a subject.
  const [settled, setSettled] = useState(n)
  useEffect(() => {
    const timer = setTimeout(() => setSettled(n), PREVIEW_SETTLE_MS)
    return () => clearTimeout(timer)
  }, [n])
  // The SUBJECT is (fleet, side, good, settled quantity) — exactly as the buy ceiling is keyed — so
  // an answer for another quantity is never shown; a re-read of the world keeps the last answer
  // (useServedRead). The line previewed is the line the button issues, composed by the same
  // `orderText`, so the figure printed and the figure realised cannot be two figures.
  // `saleEstimate` reads the keys both verbs share (`qty`, `total`, `avg_price`, `haggle_saved`)
  // and the three a sale adds (`basis`, `cost`, `profit`), which a buy leaves null.
  const line =
    spec !== undefined && good !== null && settled > 0
      ? orderText(spec, { good: good.code, qty: String(settled) }, fleet.name)
      : null
  const subject = line !== null && good !== null ? `${fleet.id}:${intent}:${good.code}:${settled}` : null
  const dryRun = useServedRead<SaleEstimate | null>(subject, async () => {
    // A refusal here is not the tray's to render: the press states it in full. A fleet at sea
    // is QUEUEABLE and returns no estimate — there is nothing realised to print yet. Both are
    // folded into ONE served value (null) so the read keeps standing rather than clearing.
    const r = await cmdPreview(fleet.id, line as string, null)
    return ok<SaleEstimate | null>(r.ok && r.value.estimate ? saleEstimate(r.value.estimate) : null)
  })
  // Exposed only while the settled quantity IS the button's: the figure printed is always the
  // figure for the quantity chosen.
  const current = subject !== null && settled === n
  const preview = current ? dryRun.view : null
  const previewLoading = spec !== undefined && good !== null && n > 0 && (!current || (dryRun.loading && dryRun.view === null))

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

  // The same quantity `send` would issue, staged instead. The tray gates both on one condition.
  const stage = onStage ? () => onStage(n) : undefined

  return { capacity, step, act: { send, stage, sending, ready, total, refusal, paid, preview, previewLoading } }
}
