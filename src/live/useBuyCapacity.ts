// ═══════════════════════════════════════════════════════════════════════════════════════════════
// HOW MUCH CAN SHE BUY? — asked, not worked out.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// This replaces a client-side `buyBound()` whose own comment admitted the flaw: it divided the
// purse by the market's opening ask, and a real BUY REPRICES AS IT WALKS THE BOOK (§G.2), so the
// true ceiling is always lower. The player met that as a MAX chip offering 91 tuns of pepper and a
// refusal reading "91 tuns cost 8130 d. and you hold 8000" — the game contradicting its own picker.
//
// `world.buy_capacity(fleet, good)` answers it on the server, stepping down through the SAME quote
// a committed trade walks, so the number offered and the number charged cannot disagree. It also
// returns WHICH limit binds — hold, stock, daily cap or purse — so the caption under the slider is
// the server's word rather than the client's guess at it.
//
// The answer is keyed by (fleet, good, last read). A stale ceiling is the bug this file exists to
// remove, so an answer for a different good — or from before the world was read again — is never
// shown: the picker waits instead.

import { useEffect, useState } from 'react'
import { worldBuyCapacity } from '../lib/rpc'
import { useWorld } from './worldStore'
import type { BuyCapacityState } from '../lib/trade'

export type { BuyCapacityState }

// `BuyCapacityState` moved to src/lib/trade 2026-09-01: the design system's picker takes it as a
// prop and may not import the store, so the SHAPE lives below both of them. Re-exported above so
// this file is still the one place a caller has to know about.

const WAITING: BuyCapacityState = { bound: null, estTotal: null, loading: true }
const IDLE: BuyCapacityState = { bound: null, estTotal: null, loading: false }

/** The server's phrase for what stops her, as the slider's caption reads it. */
function captionFor(boundBy: string): string {
  switch (boundBy) {
    case 'hold': return 'the hold'
    case 'stock': return 'the stock here'
    case 'daily cap': return "today's trading limit"
    case 'purse': return 'your purse'
    case 'at sea': return 'being at sea'
    default: return boundBy
  }
}

export function useBuyCapacity(fleetId: string | null, goodCode: string | null): BuyCapacityState {
  const goodId = useWorld((s) => (goodCode ? (s.goodByCode[goodCode]?.id ?? null) : null))
  // Re-asked whenever the world is read again: a purse spent elsewhere, or stock another house
  // took, changes the answer.
  const readAt = useWorld((s) => s.readAt)
  const key = fleetId && goodId ? `${fleetId}:${goodId}:${readAt ?? 0}` : null

  const [answer, setAnswer] = useState<{ key: string; state: BuyCapacityState } | null>(null)

  useEffect(() => {
    if (!key || !fleetId || !goodId) return
    let live = true
    void worldBuyCapacity(fleetId, goodId).then((r) => {
      if (!live) return
      if (!r.ok) {
        // A refusal here is not the player's problem to solve: the picker simply offers nothing,
        // and the composer's own preview states the reason in full when they try to issue.
        setAnswer({ key, state: IDLE })
        return
      }
      setAnswer({
        key,
        state: {
          bound: { max: Number(r.value.max_qty), binding: captionFor(r.value.bound_by) },
          estTotal: Number(r.value.est_total),
          loading: false,
        },
      })
    })
    return () => {
      live = false
    }
  }, [key, fleetId, goodId])

  if (!key) return IDLE
  // An answer that belongs to a different (fleet, good, read) is not this question's answer.
  return answer?.key === key ? answer.state : WAITING
}
