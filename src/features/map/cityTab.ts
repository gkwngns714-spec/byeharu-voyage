import { create } from 'zustand'

// WHICH TAB THE MAP'S CITY PANEL STANDS ON — Market | Port | Inn (CityTabs.tsx, owner 2026-10-15).
// Its own file because two components set it: the tab bar, and `Send fleet` (SendFleet.tsx),
// which turns to Port where her fleets are listed. Kept across cities, so a player reading prices
// along a coast taps city after city and stays on Market. Session chrome, never game state.

export type CityTab = 'market' | 'port' | 'inn'

export const CITY_TABS: readonly { id: CityTab; label: string }[] = [
  { id: 'market', label: 'Market' },
  { id: 'port', label: 'Port' },
  { id: 'inn', label: 'Inn' },
]

export const useCityTab = create<{ tab: CityTab; turnTo: (tab: CityTab) => void }>((set) => ({
  tab: 'market',
  turnTo: (tab) => set({ tab }),
}))
