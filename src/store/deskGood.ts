// WHICH CITY AND WHICH GOOD THE COMMAND DESK IS READING (docs/COMMAND_DESK.md §6; owner row 218, 2026-10-26).
//
// The Buy and Sell faces (features/command/buysell) read ONE city — pressed on the mini map, else where she lies,
// else her next port — and, on it, ONE good pressed (its prices, its chart, who bought what). Both faces read the
// same pair, so turning from Buy to Sell keeps the city in hand.
//
// A store, not a prop chain, because it has two writers: the desk (a city or a good pressed) and the map's city
// panel (a good's price tray hands the city and the good over: "Open in Command", live/PriceTray.tsx). `handed`
// is that hand-over waiting for the desk: the desk turns to Buy on it once and spends it (CommandScreen.tsx).
// Session storage: what you were looking at survives a reload and dies with the tab.

import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'

export interface DeskGoodState {
  /** The good's CODE pressed on the city's list, or null. */
  code: string | null
  /** The port CODE the desk reads, or null for "where she lies, else her next port". */
  focus: string | null
  /** A hand-over from outside the desk is waiting (the desk turns to Buy once). */
  handed: boolean
  /** From outside the desk: read this good at this city. */
  open: (code: string, focus?: string | null) => void
  /** A good pressed (null: none). */
  pick: (code: string | null) => void
  /** A city pressed: the good pressed belongs to the city it was pressed at, so it is let go. */
  setFocus: (port: string | null) => void
  spendHand: () => void
  close: () => void
}

export const useDeskGood = create<DeskGoodState>()(
  persist(
    (set) => ({
      code: null,
      focus: null,
      handed: false,
      open: (code, focus = null) => set({ code, focus, handed: true }),
      pick: (code) => set({ code }),
      setFocus: (focus) => set((s) => (s.focus === focus ? s : { focus, code: null })),
      spendHand: () => set({ handed: false }),
      close: () => set({ code: null, focus: null }),
    }),
    {
      name: 'byeharu-voyage.desk-good.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ code: s.code, focus: s.focus }),
    },
  ),
)
