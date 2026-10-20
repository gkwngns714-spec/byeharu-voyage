import { create } from 'zustand'
import type { LatLon } from '../lib/geo'
import { whereabouts, type WhereFacts, type Whereabouts } from '../domain/fleet'

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

/** What `goToPoint` may ask the live chart about. Three questions, each answered by the screen that
 *  holds the model and the served rows — nothing here reads a store. */
export interface GoToWorld {
  /** A harbour by CODE, from the chart's own port table. */
  readonly portAt: (code: string) => LatLon | null
  /** A hull the chart DREW, by fleet id — yours or a merchant's. Her mark is the truest answer
   *  there is: it is the thing the player can see. */
  readonly drawnAt: (id: string) => LatLon | null
  /** Her SERVED ROW, for a hull the chart is not drawing. Null when no read holds her. */
  readonly rowOf: (id: string) => WhereFacts | null
}

/**
 * WHERE A TARGET IS — the ONE resolution from "show me her" to a coordinate.
 *
 * A point is itself. A harbour is its place in the table. A fleet or a merchant is the mark the
 * chart drew for her; failing that (a resting merchant is not drawn, and the sea window is capped
 * at `sea_traffic_max`, so most merchants on a city's list are not drawn either) it is where her
 * own row says she is — `whereabouts`, the one classification (src/domain/fleet/where.ts).
 *
 * 2026-10-20, THE OWNER (request 184): *"I want to be able to click on npc name like location, and
 * then point me to that location like for cities."* Her name was already a link and already asked
 * for this; the resolution it asked had an answer for a merchant in port and a merchant at anchor
 * and NONE for a merchant at sea, so pressing the name of the merchant in a city's "Incoming" list
 * did nothing at all. A sailing row carries the position the server placed her at — the same point
 * the chart draws when she is on the paper — and that is the answer. If a read placed her nowhere,
 * where she is BOUND is the only other place she is, and the chart shows that rather than nothing.
 *
 * PURE, and the screen holds no second copy of it (tests/map.goto.spec.ts).
 */
export function goToPoint(target: GoToTarget, world: GoToWorld): LatLon | null {
  if (target.kind === 'point') return target.at
  if (target.kind === 'port') return world.portAt(target.code)
  const drawn = world.drawnAt(target.id)
  if (drawn) return drawn
  const row = world.rowOf(target.id)
  const w = target.where ?? (row ? whereabouts(row) : null)
  switch (w?.kind) {
    case 'docked':
      return world.portAt(w.port)
    case 'anchored':
      return w.at
    case 'sailing':
      return w.at ?? (w.to ? world.portAt(w.to) : w.point)
    default:
      return null
  }
}
