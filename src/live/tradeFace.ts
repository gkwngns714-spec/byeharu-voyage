// WHICH FACE OF THE TRADE BOARD IS TURNED TOWARDS YOU — Buy · Sell · Requests.
//
// docs/QUAY_LEDGER.md §3 A names the three segments of the board (the reference's buy tab, sell
// tab and 의뢰 board), and slice 4 (2026-09-14, owner row 76) lands the third. The first two are
// FACES OF ONE LEDGER, not two ledgers: every row keeps both its price cells (owner row 6 — *"i
// want to be able to click on buy and sell itself"*), and Sell merely narrows the same rows to
// what the ship carries. Requests is the board of what this port asks for (0087).
//
// ── ONE OWNER, TWO CALLERS ─────────────────────────────────────────────────────────────────────
// The quay she lies at (PortTrade.tsx) and a quay she is only reading (PortPrices.tsx) both turn
// the same three faces, and a face chosen on one must be the face shown on the other — two
// `useState`s would be two answers to "which face". Session storage for portView.ts's reason: a
// face you turned to is a thing you are DOING; it survives a reload and dies with the tab. The
// strip itself is `TradeFaces.tsx`, one component both faces compose.

import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'

/** The three faces, in the order the strip reads them. `label` is the player's word (docs/WORDS.md). */
export const TRADE_FACES = [
  { id: 'buy', label: 'Buy' },
  { id: 'sell', label: 'Sell' },
  { id: 'requests', label: 'Requests' },
] as const satisfies readonly { id: string; label: string }[]

export type TradeFace = (typeof TRADE_FACES)[number]['id']

export interface TradeFaceState {
  face: TradeFace
  turnTo: (face: TradeFace) => void
}

export const useTradeFace = create<TradeFaceState>()(
  persist(
    (set) => ({
      face: 'buy',
      turnTo: (face) => set({ face }),
    }),
    {
      name: 'byeharu-voyage.trade-face.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ face: s.face }),
      // A corrupt byte opens a face that EXISTS (portView.ts's own guard).
      merge: (persisted, current) => {
        const p = (persisted ?? {}) as Partial<TradeFaceState>
        return { ...current, face: TRADE_FACES.some((f) => f.id === p.face) ? (p.face as TradeFace) : 'buy' }
      },
    },
  ),
)
