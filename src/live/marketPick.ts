// WHICH GOOD THE MARKET'S CHART IS ON — one store, two regions.
//
// The owner, 2026-10-31: *"when pressing a market, instead of city, i would like to have a graph
// shown, that is changed when pressed a trade good."* The chart stands in the CITY'S LEFT REGION
// (CityScreen) and the list of goods stands in the panel; a press anywhere must move both. Two
// `useState`s would be two answers to "which good" — the defect tradeFace.ts names — so the good in
// hand is ONE session store, keyed by the port it was picked at (a pick at Lisbon says nothing about
// Amsterdam's board).
//
// A pick is NOT required for the chart to draw: with nothing picked, the chart shows the first good
// of the port's list, sorted the way the ledger sorts (by name). A pick that no longer exists on
// this port's board falls back the same way. Nothing here decides what a good IS — that is the
// market read's.

import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import type { MarketGood } from '../lib/rpc'

export interface MarketPickState {
  portId: string | null
  goodId: string | null
  goodCode: string | null
  pick: (portId: string, good: MarketGood) => void
}

export const useMarketPick = create<MarketPickState>()(
  persist(
    (set) => ({
      portId: null,
      goodId: null,
      goodCode: null,
      pick: (portId, good) => set({ portId, goodId: good.good_id, goodCode: good.code }),
    }),
    {
      name: 'byeharu-voyage.market-pick.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ portId: s.portId, goodId: s.goodId, goodCode: s.goodCode }),
    },
  ),
)

/** The good in hand at THIS port: the one picked here when it is still listed, else the port's
 *  first good by name (the ledger's own order). Null while the board has not landed. */
export function usePickedGood(portId: string, goods: readonly MarketGood[]): MarketGood | null {
  const picked = useMarketPick((s) => (s.portId === portId ? s.goodId : null))
  const hit = picked !== null ? goods.find((g) => g.good_id === picked) : undefined
  if (hit) return hit
  if (goods.length === 0) return null
  return [...goods].sort((a, b) => a.name.localeCompare(b.name))[0]
}
