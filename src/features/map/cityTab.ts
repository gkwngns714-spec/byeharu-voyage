import { create } from 'zustand'

// WHICH TAB THE MAP'S CITY PANEL STANDS ON — Market | Port | Inn (CityTabs.tsx, owner 2026-10-15).
// Its own file because two components set it: the tab bar, and `Send fleet` (SendFleet.tsx),
// which turns to Port where her fleets are listed. Kept across cities, so a player reading prices
// along a coast taps city after city and stays on Market. Session chrome, never game state.

// The fourth, Town Hall (0123, owner 2026-10-15): the city's purse, its works, Invest, who invested.
export type CityTab = 'market' | 'port' | 'inn' | 'townhall'

export const CITY_TABS: readonly { id: CityTab; label: string }[] = [
  { id: 'market', label: 'Market' },
  { id: 'port', label: 'Port' },
  { id: 'inn', label: 'Inn' },
  { id: 'townhall', label: 'Town Hall' },
]

export const useCityTab = create<{ tab: CityTab; turnTo: (tab: CityTab) => void }>((set) => ({
  tab: 'market',
  turnTo: (tab) => set({ tab }),
}))
