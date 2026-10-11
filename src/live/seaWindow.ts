// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SEA WINDOW — what the merchant read is asked to look at (0102).
//
// `world.sea_traffic` served every merchant fleet in the world on every beat until 0102. At the
// roster the owner asked for (row 118, ×10) that is a read nobody should pay for in order to look
// at one sea, so the read takes a window: `{south, north, west, east}` in degrees, the server's own
// spelling, and null for the whole world.
//
// THIS IS THE ONE PLACE THAT SHAPE IS BUILT. The server refuses a malformed window `E_BAD_VIEW`
// rather than quietly widening it (0102), which is the right posture for a server and the wrong
// thing to discover from a screen: a chart zoomed out past the globe has a viewBox that runs off
// the ±180 the window may name, and `clampView` centres such a view rather than clamping it, so
// that case is NORMAL and not an error. Every window therefore comes through here, where it is
// clamped into what the server accepts and reduced to null when it covers the world — null IS the
// world, and is both cheaper to send and clearer to read than ±90/±180.
//
// Nothing here reads or writes the store, and nothing here triggers a read. A changed window is
// picked up by the NEXT beat (`worldStore.setTrafficWindow`), for the reason the first-want rule
// gives: a merchant read that lands outside the beat is drifted from an instant that is not the
// one that produced it, and every hull on the chart jumps. The server's 10° pad covers the lag.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { GeoBounds } from '../lib/geo'
import type { SeaWindow } from '../lib/rpc/types'

/** Within this much of the whole globe, a window is the globe. Below the pad the server already
 *  adds (10°), narrowing the request buys nothing and only risks an edge case at ±180. */
const WORLD_SLACK_DEG = 10

/** Four decimals is about eleven metres — far finer than any merchant's berth and far coarser than
 *  the arithmetic noise a pan leaves behind (38.7 − 6 is 32.699999999999996 in binary). Rounding
 *  here is what makes `sameSeaWindow` mean what it says: a drag of a millionth of a degree must not
 *  count as a new window and send every subscriber of the store a re-render. */
const round4 = (v: number): number => Math.round(v * 1e4) / 1e4
const clampLat = (v: number): number => round4(Math.min(90, Math.max(-90, v)))
const clampLon = (v: number): number => round4(Math.min(180, Math.max(-180, v)))

/**
 * The window a lat/lon rectangle asks for, or null when it may as well be the world.
 *
 * Returns null for a degenerate or non-finite box too: a window the server would refuse is never
 * worth sending, and the world is the answer that is never wrong.
 */
export function seaWindowOf(bounds: GeoBounds): SeaWindow | null {
  const { minLat, maxLat, minLon, maxLon } = bounds
  if (![minLat, maxLat, minLon, maxLon].every((v) => Number.isFinite(v))) return null
  const south = clampLat(Math.min(minLat, maxLat))
  const north = clampLat(Math.max(minLat, maxLat))
  const west = clampLon(Math.min(minLon, maxLon))
  const east = clampLon(Math.max(minLon, maxLon))
  if (north - south <= 0 || east - west <= 0) return null
  if (north - south >= 180 - WORLD_SLACK_DEG && east - west >= 360 - WORLD_SLACK_DEG) return null
  return { south, north, west, east }
}

// `seaWindowAround(point, deg)` — a window of so many degrees round a point — was DELETED on
// 2026-10-11, the day it was written, with its only caller. PORT asked for one while it drew the
// merchants out of `traffic`; 0104 gave a harbour its own read (`world.port_merchants`, asked at a
// tap and bounded by the harbour itself), PORT stopped reading the traffic at all, and the window
// went with the list that needed it. A helper kept alive by its own spec is the spaghetti
// docs/NO_SPAGHETTI.md names: it would be the SECOND answer to "what water is this screen about"
// the day something else wanted one, and `seaWindowOf` over a box is the first.

/**
 * The window that covers all of them — what the store sends when two screens that both draw
 * merchants are mounted at once (MAP during a transition into PORT, and the other way).
 *
 * A single union box is a SUPERSET of every window in it, which is the safe direction: a merchant
 * in one wanter's window is never missing because another wanter was looking elsewhere. One null —
 * one wanter that wants the world — makes the union the world, and no windows at all is the world
 * too, because a wanter with nothing to say about where it is looking has not narrowed anything.
 *
 * It does not wrap the antimeridian: a pair of windows either side of ±180 unions to a band taking
 * in nearly every longitude, the long way round rather than through the seam. That is still a
 * superset of both, which is all this promises — it just asks for more sea than it needs. The
 * clever version is two windows on the wire, and a second window is a second thing to be wrong
 * about for a case the chart cannot reach: there is no harbour within 10° of ±180 in this world,
 * so no screen ever asks for a pair that straddles it.
 */
export function seaWindowUnion(windows: readonly (SeaWindow | null)[]): SeaWindow | null {
  if (windows.length === 0 || windows.some((w) => w === null)) return null
  const live = windows as readonly SeaWindow[]
  return seaWindowOf({
    minLat: Math.min(...live.map((w) => w.south)),
    maxLat: Math.max(...live.map((w) => w.north)),
    minLon: Math.min(...live.map((w) => w.west)),
    maxLon: Math.max(...live.map((w) => w.east)),
  })
}

/** Are these the same window? The store compares before it writes, so a pan that does not change
 *  the window the server would be asked for does not re-render every subscriber. */
export function sameSeaWindow(a: SeaWindow | null, b: SeaWindow | null): boolean {
  if (a === null || b === null) return a === b
  return a.south === b.south && a.north === b.north && a.west === b.west && a.east === b.east
}
