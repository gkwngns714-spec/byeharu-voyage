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
// ── A DOORWAY ONTO useServedRead (2026-09-14) ──────────────────────────────────────────────────
// Until 2026-09-14 this hook keyed its answer on (fleet, good, readAt) and returned `{bound: null,
// loading: true}` whenever the key moved — and the shell reads the world every 3 s (AppShell.tsx,
// READ_MIN_MS), so every 3 s the ceiling was thrown away: the tray's `Max` row unmounted, the
// stepper clamped to a ceiling of nought, and the row repainted when the re-ask landed. The owner:
// *"when i press buy, the max keeps refreshing."* That is row 77's defect once more, in the one
// hook `useServedRead`'s header had exempted. The SUBJECT is (fleet, good); a re-read of the same
// subject keeps the last ceiling on screen and marks it `loading`; a new good shows nothing of the
// old one. The ceiling is still re-asked on every beat — a purse spent elsewhere, or stock another
// house took, changes the answer — and `cmd.issue` re-checks it on the press regardless.

import { ok, worldBuyCapacity } from '../lib/rpc'
import { useServedRead } from './useServedRead'
import { useWorld } from './worldStore'
import type { BuyCapacityState, QtyBound } from '../lib/trade'

export type { BuyCapacityState }

// `BuyCapacityState` moved to src/lib/trade 2026-09-01: the design system's picker takes it as a
// prop and may not import the store, so the SHAPE lives below both of them. Re-exported above so
// this file is still the one place a caller has to know about.

/** The server's phrase for what stops her, as the slider's caption reads it. */
function captionFor(boundBy: string): string {
  switch (boundBy) {
    case 'hold': return 'cargo space'
    case 'stock': return 'stock here'
    case 'daily cap': return "today's trading limit"
    case 'purse': return 'your money'
    case 'at sea': return 'being at sea'
    default: return boundBy
  }
}

/** What `world.buy_capacity` said, as the picker reads it — the served value of one ask. */
interface Ceiling {
  bound: QtyBound
  estTotal: number
}

export function useBuyCapacity(fleetId: string | null, goodCode: string | null): BuyCapacityState {
  const goodId = useWorld((s) => (goodCode ? (s.goodByCode[goodCode]?.id ?? null) : null))
  const subject = fleetId && goodId ? `${fleetId}:${goodId}` : null
  const read = useServedRead<Ceiling>(subject, async () => {
    // A refusal here is not the player's problem to solve: useServedRead clears the view, the
    // picker simply offers nothing, and the composer's own preview states the reason in full when
    // they try to issue.
    const r = await worldBuyCapacity(fleetId as string, goodId as string)
    if (!r.ok) return r
    return ok<Ceiling>({
      bound: { max: Number(r.value.max_qty), binding: captionFor(r.value.bound_by) },
      estTotal: Number(r.value.est_total),
    })
  })
  return { bound: read.view?.bound ?? null, estTotal: read.view?.estTotal ?? null, loading: read.loading }
}
