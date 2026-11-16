// THE TRADE DESK'S OWN CHROME (docs/COMMAND_DESK.md §3.1, §8).
//
// THE DESK HAS ONE FACE (owner, 2026-11-16: *"in trade, there are city invest report and levels, which aren't that related
// to trade. they should have separate tab like map you stats etc."*). Trade (features/command/buysell/Trade.tsx) is the
// desk; City, Invest and Report are the OFFICE tab's faces (features/command/officeView.ts), and Levels stand on the YOU
// page (features/you/YouScreen.tsx). So this store no longer holds a face: a strip of one is a door with nothing behind it.

import { create } from 'zustand'

export interface DeskViewState {
  /** Buy / Sell: whether the route's PAGE stands open. HERE, not in RouteFold's own state, because the desk
   *  has TWO SHAPES (DeskShell: the titled scroll box below 1024 px, the terminal above) and crossing that
   *  width mounts the face anew — a local `useState` closed the route on every turn of a
   *  tablet or resize of a window (tests/route.stopface.spec.ts, red on main from #225). Not persisted:
   *  an open page is a glance, not a thing you are doing. */
  routeOpen: boolean
  setRouteOpen: (open: boolean | ((open: boolean) => boolean)) => void
}

export const useDeskView = create<DeskViewState>()((set) => ({
  routeOpen: false,
  setRouteOpen: (open) => set((s) => ({ routeOpen: typeof open === 'function' ? open(s.routeOpen) : open })),
}))
