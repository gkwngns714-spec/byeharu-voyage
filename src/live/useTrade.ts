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
// WHAT IT READS: the verb grammar and the trade step off the snapshot, the one door (`issue`), and
// `world.buy_capacity()` through the one hook that asks it. WHAT IT RETURNS is exactly the shape
// the tray takes, so a screen composes `<TradeTray … capacity={capacity} act={act}>` and owns
// nothing but the pick and the quantity — COMMAND keeps the quantity on its order draft, PORT in
// local state, and neither spells the act.
//
// NO PRICE IS MULTIPLIED OUT HERE. Buying walks a stepped book (§G.2), so the only total ever
// named is the server's own `est_total`, and only where it is the total OF the quantity chosen —
// which is when the chosen quantity is the ceiling the server priced.

import { useState } from 'react'
import { findVerb, orderText } from '../domain/order'
import type { FleetView, MarketGood, Refusal } from '../lib/rpc'
import type { BuyCapacityState } from '../lib/trade'
import { useBuyCapacity } from './useBuyCapacity'
import { useWorld } from './worldStore'

/** What pressing the tray's one button does, whether it may fire yet, what the chosen quantity
 *  costs when the server has priced it, and what the server last answered. */
export interface TradeAct {
  send: () => void
  sending: boolean
  ready: boolean
  total: number | null
  refusal: Refusal | null
}

export function useTrade(
  fleet: FleetView,
  intent: 'buy' | 'sell',
  /** The good in the open tray, or null while no tray is open. */
  good: MarketGood | null,
  /** The caller's quantity — the draft's `qty`, or the screen's local state. */
  qty: number | null,
  /** Called once the order is issued: the tray closes, the pick is cleared. */
  onDone: () => void,
): { capacity: BuyCapacityState; step: number; act: TradeAct } {
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

  const total =
    intent === 'buy' && capacity.estTotal !== null && capacity.bound !== null && n === capacity.bound.max
      ? capacity.estTotal
      : null

  return { capacity, step, act: { send, sending, ready, total, refusal } }
}
