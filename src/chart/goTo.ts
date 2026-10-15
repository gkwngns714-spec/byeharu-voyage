import { create } from 'zustand'
import type { LatLon } from '../lib/geo'
import type { Whereabouts } from '../domain/fleet'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// GO TO — the ONE way anything outside the chart asks the chart to show a place.
//
// The owner, 2026-10-15: *"the tab shown from the left, i want to be able to click all, for
// example if i press a city, it will point me to that location with a marker"*.
//
// A panel never touches the view. It names a TARGET and calls `goTo`; the map screen (the one
// holder of the surface, MapScreen.tsx) takes the request, resolves it to a coordinate through the
// chart's own model — a harbour by its code, a fleet by her drawn mark, else by `whereabouts`
// (src/domain/fleet/where.ts), the one "where is she" rule — glides there with the zoom glide's
// loop (`useChartSurface.glideTo`) and rings it with a marker. Every link in every panel is
// `GoToLink` (./GoToLink.tsx), which calls this and nothing else.
//
// A request made while the Map tab is not up (a merchant's sheet on PORT) is held here and taken
// when the chart mounts; `openMap`, registered by the shell (the one place inside the router),
// brings the tab up.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export type GoToTarget =
  | { readonly kind: 'port'; readonly code: string }
  /** A fleet of yours or a merchant, by id. `where` is her row's own whereabouts, for a hull the
   *  chart does not draw (a merchant resting in a harbour is served by that harbour alone). */
  | { readonly kind: 'fleet'; readonly id: string; readonly where?: Whereabouts }
  | { readonly kind: 'point'; readonly at: LatLon }

/** How long the marker rings a place, unless the next go-to moves it sooner. */
export const GOTO_MARK_MS = 4000

/** Narrower than this much clear glass beside the side panels (a phone), the panels FOLD for a
 *  go-to rather than leave the place under them. */
export const GOTO_MIN_CLEAR_PX = 220

interface GoToState {
  /** The request not yet taken, numbered so the same place asked twice is two requests. */
  readonly request: { readonly target: GoToTarget; readonly seq: number } | null
  readonly seq: number
  /** How many charts are mounted to take a request (0 or 1). */
  readonly charts: number
  /** Brings the Map tab up — the shell's, null outside the router (the map preview). */
  readonly openMap: (() => void) | null
  goTo: (target: GoToTarget) => void
  take: () => { readonly target: GoToTarget; readonly seq: number } | null
}

export const useGoTo = create<GoToState>((set, get) => ({
  request: null,
  seq: 0,
  charts: 0,
  openMap: null,
  goTo: (target) => {
    const seq = get().seq + 1
    set({ request: { target, seq }, seq })
    const { charts, openMap } = get()
    if (charts === 0 && openMap) openMap()
  },
  take: () => {
    const r = get().request
    if (r) set({ request: null })
    return r
  },
}))

/** Ask the chart to show a place. */
export function goTo(target: GoToTarget): void {
  useGoTo.getState().goTo(target)
}
