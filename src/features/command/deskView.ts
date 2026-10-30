// WHICH FACE OF THE DESK IS UP — COMMAND's own chrome (docs/COMMAND_DESK.md §3.1, §8; PORT's portView.ts
// pattern). Session storage, for portView's reason: a face you turned to is a thing you are doing.
//
// THE FACES, EACH DESCRIBED ONCE: Trade · City · Invest · Profit. Trade (owner 2026-10-30, *"removing the map, just
// have combined buy and sell tab with trade goods when docked"*) merged the earlier Buy and Sell faces (row 218)
// into ONE page, features/command/buysell/Trade.tsx — the docked city's goods, both sides in one list. A face is
// listed here only when it is BUILT — a tab that opens nothing is a door nobody opens. The ORDER is the strip's.

import { create } from 'zustand'
import type { PortFace } from '../../live/cityFaces'
import { createJSONStorage, persist } from 'zustand/middleware'
import { t } from '../../lib/i18n'

export const DESK_FACES = [
  { id: 'trade', get label() { return t('command.f_trade') } },
  { id: 'city', get label() { return t('command.f_city') } },
  { id: 'invest', get label() { return t('command.f_invest') } },
  { id: 'profit', get label() { return t('command.f_profit') } },
] as const

export type DeskFace = (typeof DESK_FACES)[number]['id']

export interface DeskViewState {
  face: DeskFace
  /** The City face's building (live/cityFaces.ts); one that the city lacks falls back to its first. */
  cityFace: PortFace
  /** Buy / Sell: whether the route fold stands open. HERE, not in RouteFold's own state, because the desk
   *  has TWO SHAPES (CommandScreen: the Sheet below 1024 px, the terminal above) and crossing that
   *  width mounts the face anew — a fold's own `useState` folded the route shut on every turn of a
   *  tablet or resize of a window (tests/route.stopface.spec.ts, red on main from #225). Not persisted:
   *  an open fold is a glance, not a thing you are doing. */
  routeOpen: boolean
  turnTo: (face: DeskFace) => void
  setCityFace: (face: PortFace) => void
  setRouteOpen: (open: boolean | ((open: boolean) => boolean)) => void
}

export const useDeskView = create<DeskViewState>()(
  persist(
    (set) => ({
      face: 'trade',
      cityFace: 'market',
      routeOpen: false,
      turnTo: (face) => set({ face }),
      setCityFace: (cityFace) => set({ cityFace }),
      setRouteOpen: (open) => set((s) => ({ routeOpen: typeof open === 'function' ? open(s.routeOpen) : open })),
    }),
    {
      name: 'byeharu-voyage.desk.v1',
      storage: createJSONStorage(() => sessionStorage),
      partialize: (s) => ({ face: s.face, cityFace: s.cityFace }),
      // A stale or corrupt byte opens a face that EXISTS.
      merge: (persisted, current) => {
        const p = (persisted ?? {}) as Partial<DeskViewState>
        return {
          ...current,
          face: DESK_FACES.some((f) => f.id === p.face) ? (p.face as DeskFace) : 'trade',
          cityFace: typeof p.cityFace === 'string' ? p.cityFace : 'market',
        }
      },
    },
  ),
)
