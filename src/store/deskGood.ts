// WHICH GOOD IS OPEN ON THE COMMAND DESK (docs/COMMAND_DESK.md §6) — and which city its chart follows.
//
// A store, not a prop chain, because it has two writers on day one: the desk's watchlist (a row
// pressed) and the map's city panel (a good's price tray hands the good over: "Open in Command"). The
// FOCUS is the city the good page's chart and hero follow — a Buy at row's city, or a Sell at row the
// player tapped; null means "the page's own default" (the docked city when it trades the good, else the
// cheapest seller). Session storage: what you were looking at survives a reload and dies with the tab,
// as the order draft and the port face do.

import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'

export interface DeskGoodState {
  /** The good's CODE, or null when no good page is open. */
  code: string | null
  /** The port CODE the chart follows, or null for the page's default. */
  focus: string | null
  open: (code: string, focus?: string | null) => void
  setFocus: (port: string | null) => void
  close: () => void
}

export const useDeskGood = create<DeskGoodState>()(
  persist(
    (set) => ({
      code: null,
      focus: null,
      open: (code, focus = null) => set({ code, focus }),
      setFocus: (focus) => set({ focus }),
      close: () => set({ code: null, focus: null }),
    }),
    {
      name: 'byeharu-voyage.desk-good.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ code: s.code, focus: s.focus }),
    },
  ),
)
