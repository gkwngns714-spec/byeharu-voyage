// A TRIP HANDED TO THE MAP'S ROUTE BUILDER FROM OUTSIDE THE MAP (S3 of docs/SECOND_SHIP.md, 2026-11-13).
//
// The build yard's sheet knows which harbours sell what a hull still lacks (world.yard_sources); the Map's route
// builder is the one place a trip of several stops is drawn, judged leg by leg by the server and queued
// (useRouteBuilder.ts). "Plan trip" hands the first to the second: a fleet and a list of harbour codes wait here, and
// the map screen (the one holder of the route mode) takes them when it is up, as it takes a go-to (chart/goTo.ts).
// Nothing is sent: the stops arrive as a draft she can undo, and Final is still her press.

import { create } from 'zustand'

interface RouteSeedState {
  /** The trip not yet taken by the map. */
  readonly request: { readonly fleetId: string; readonly stops: readonly string[] } | null
  plan: (fleetId: string, stops: readonly string[]) => void
  take: () => { readonly fleetId: string; readonly stops: readonly string[] } | null
}

export const useRouteSeed = create<RouteSeedState>((set, get) => ({
  request: null,
  plan: (fleetId, stops) => set({ request: stops.length > 0 ? { fleetId, stops: [...stops] } : null }),
  take: () => {
    const r = get().request
    if (r) set({ request: null })
    return r
  },
}))
