import { create } from 'zustand'

/** A HULL ASKED FOR ON THE YARD from outside it (2026-11-23 play-test: the goal card's press opens the yard ON the Barca's sheet,
 *  where her Order is). Session-only and taken once: the yard opens that hull's sheet when it has it, and lets the ask go.
 *  Here since 2026-11-24 (H3): it stood in the Office's view store, which went with the Office. */
export const useYardAsk = create<{ hull: string | null; ask: (hull: string | null) => void; take: () => string | null }>((set, get) => ({
  hull: null,
  ask: (hull) => set({ hull }),
  take: () => {
    const h = get().hull
    if (h !== null) set({ hull: null })
    return h
  },
}))
