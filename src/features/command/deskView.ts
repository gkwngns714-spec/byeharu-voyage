// WHICH FACE OF THE DESK IS UP, and how the Markets list is filtered and sorted — COMMAND's own chrome
// (docs/COMMAND_DESK.md §3.1, §8; PORT's portView.ts pattern). Session storage, for portView's reason:
// a face you turned to is a thing you are doing.
//
// THE FACES, EACH DESCRIBED ONCE (COMMAND_DESK D1: Markets · Plans · City · Invest · Profit). A face
// is listed here only when it is BUILT — a tab that opens nothing is a door nobody opens — so City,
// Invest and Profit join this table with their slices (D5, D6, D7). The ORDER is the strip's.

import { create } from 'zustand'
import type { PortFace } from '../../live/cityFaces'
import { createJSONStorage, persist } from 'zustand/middleware'

export const DESK_FACES = [
  { id: 'markets', label: 'Markets' },
  { id: 'plans', label: 'Plans' },
  { id: 'city', label: 'City' },
  { id: 'invest', label: 'Invest' },
] as const

export type DeskFace = (typeof DESK_FACES)[number]['id']

/** The list's filters: every good, what the docked city sells, what is on board, or one category. */
export type DeskFilter = 'all' | 'here' | 'on_board' | `cat:${string}`

/** The list's sorts (§3.2): by name, by the move across the record, by the price. */
export const DESK_SORTS = [
  { id: 'name', label: 'Name' },
  { id: 'change', label: 'Change' },
  { id: 'price', label: 'Price' },
] as const

export type DeskSort = (typeof DESK_SORTS)[number]['id']

export interface DeskViewState {
  face: DeskFace
  filter: DeskFilter
  sort: DeskSort
  search: string
  /** The City face's building (live/cityFaces.ts); one that the city lacks falls back to its first. */
  cityFace: PortFace
  turnTo: (face: DeskFace) => void
  setCityFace: (face: PortFace) => void
  setFilter: (filter: DeskFilter) => void
  setSort: (sort: DeskSort) => void
  setSearch: (search: string) => void
}

export const useDeskView = create<DeskViewState>()(
  persist(
    (set) => ({
      face: 'markets',
      filter: 'all',
      sort: 'name',
      search: '',
      cityFace: 'market',
      turnTo: (face) => set({ face }),
      setCityFace: (cityFace) => set({ cityFace }),
      setFilter: (filter) => set({ filter }),
      setSort: (sort) => set({ sort }),
      setSearch: (search) => set({ search }),
    }),
    {
      name: 'byeharu-voyage.desk.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ face: s.face, filter: s.filter, sort: s.sort, cityFace: s.cityFace }),
      // A stale or corrupt byte opens a face that EXISTS.
      merge: (persisted, current) => {
        const p = (persisted ?? {}) as Partial<DeskViewState>
        return {
          ...current,
          face: DESK_FACES.some((f) => f.id === p.face) ? (p.face as DeskFace) : 'markets',
          filter: typeof p.filter === 'string' ? (p.filter as DeskFilter) : 'all',
          sort: DESK_SORTS.some((s) => s.id === p.sort) ? (p.sort as DeskSort) : 'name',
          cityFace: typeof p.cityFace === 'string' ? p.cityFace : 'market',
        }
      },
    },
  ),
)
