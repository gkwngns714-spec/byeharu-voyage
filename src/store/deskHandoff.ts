// A MOVE HANDED FROM HQ TO THE TRADE DESK (docs/design/hq-command-2026-11-23.md, the HQ command board v1).
//
// The board's trade card and its fleet row do not trade or plan on their own: each hands its ask to the desk, and the desk does it
// with ITS OWN press, so there is one code path. A best sale is pressed by the desk's `pressBest` (features/command/buysell/Trade.tsx)
// once that fleet is in hand at that city; a route ask opens the desk's route page (RouteFold) for that fleet. Session-only and taken
// once: the desk lets the ask go as it acts on it.

import { create } from 'zustand'
import type { BestSale } from '../lib/rpc'

export interface BestAsk {
  /** The fleet the sale was priced for. */
  fleet: string
  /** The city she buys at (port CODE): the city in hand when the board read it. */
  at: string
  sale: BestSale
}

export interface DeskHandoffState {
  best: BestAsk | null
  /** A fleet whose route page the desk opens. */
  route: string | null
  giveBest: (ask: BestAsk) => void
  giveRoute: (fleet: string) => void
  clearBest: () => void
  clearRoute: () => void
}

export const useDeskHandoff = create<DeskHandoffState>()((set) => ({
  best: null,
  route: null,
  giveBest: (best) => set({ best }),
  giveRoute: (route) => set({ route }),
  clearBest: () => set({ best: null }),
  clearRoute: () => set({ route: null }),
}))
