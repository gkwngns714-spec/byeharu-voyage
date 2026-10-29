// WHICH FACE OF THE DESK IS UP — COMMAND's own chrome (docs/COMMAND_DESK.md §3.1, §8; PORT's portView.ts
// pattern). Session storage, for portView's reason: a face you turned to is a thing you are doing.
//
// THE FACES, EACH DESCRIBED ONCE: Buy · Sell · City · Invest · Report. Buy and Sell (owner row 218, 2026-10-26:
// *"in command, there is market, and trade. i want to have buy and sell tab instead of those"*) replaced the
// Markets and Trade faces; both are the one page features/command/buysell/BuySell.tsx, on its two sides. Report
// (owner row 192, 2026-10-25: *"the profit tab on command, change it to report"*) replaced Profit (0278). A face is
// listed here only when it is BUILT — a tab that opens nothing is a door nobody opens. The ORDER is the strip's.

import { create } from 'zustand'
import type { PortFace } from '../../live/cityFaces'
import { createJSONStorage, persist } from 'zustand/middleware'
import { t } from '../../lib/i18n'

export const DESK_FACES = [
  { id: 'buy', get label() { return t('command.f_buy') } },
  { id: 'sell', get label() { return t('command.f_sell') } },
  { id: 'city', get label() { return t('command.f_city') } },
  { id: 'invest', get label() { return t('command.f_invest') } },
  { id: 'report', get label() { return t('command.f_report') } },
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
      face: 'buy',
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
          face: DESK_FACES.some((f) => f.id === p.face) ? (p.face as DeskFace) : 'buy',
          cityFace: typeof p.cityFace === 'string' ? p.cityFace : 'market',
        }
      },
    },
  ),
)
