// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PASSAGE PROPOSAL — the course a client offers the server for a SAIL or a DIVERT.
//
// §7B — the four questions:
//   CONCEPT      "the course this order proposes, from where she is to where she is sent."
//   LIVES HERE   src/domain/passage — a rule-of-the-game READING (it composes served facts: the
//                fleet's served position, the port table, the served raster) with no React and no
//                store. The SEARCH itself is machinery and lives in src/lib/sea; the AUTHORITY on
//                legality and distance is the server (migration 0039): a proposal makes nothing
//                legal, only findable, and the server re-verifies every segment and measures the
//                miles itself.
//   SECOND CALLER  born with two: the Command composer (previews and issues the order) and the
//                map's SailHere (the same intent, one tab earlier). A third is the divert flow.
//                That is exactly why this is not a private helper of either screen.
//   WRONG SHAPE  if a screen ever computed a course of its own, or trusted the proposal's `nm` as
//                a fact — the number a screen prints is the SERVER's estimate from cmd.preview,
//                and the proposal's nm is used for nothing but existing.
//
// MEASURED COST (docs/NAVIGATION_PLAN.md §3): a search is 2–166 ms in Node; the in-browser figure
// is re-measured in the acceptance drive. It runs once per destination pick, on the pick.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { LatLon } from '../../lib/geo'
import {
  cellLat,
  cellLon,
  findPath,
  snapToNav,
  type SeaNav,
  type SeaPath,
  type SearchScratch,
} from '../../lib/sea'
import type { FleetView, SnapshotPort } from '../../lib/rpc'

/** One scratch for every search the app runs — three million-entry arrays, allocated once. */
const SCRATCH: SearchScratch = {}

/** Where a SAIL from this fleet would depart: her quay, her open anchor, or — for an order that
 *  will queue — where the current voyage ends. ONE reading, beside `fleetPortCode`'s "where does
 *  her next order happen", which answers in port codes and cannot say "33°N 15°W". */
export function sailOrigin(
  fleet: FleetView,
  portByCode: Record<string, SnapshotPort>,
): LatLon | null {
  if (fleet.port) {
    const p = portByCode[fleet.port]
    return p ? { lat: p.lat, lon: p.lon } : null
  }
  if (fleet.anchor) return { lat: fleet.anchor[0], lon: fleet.anchor[1] }
  if (fleet.voyage) {
    if (fleet.voyage.to) {
      const p = portByCode[fleet.voyage.to]
      return p ? { lat: p.lat, lon: p.lon } : null
    }
    if (fleet.voyage.dest_point) {
      return { lat: fleet.voyage.dest_point[0], lon: fleet.voyage.dest_point[1] }
    }
  }
  return null
}

/** Where the fleet IS right now — for a DIVERT, which turns where she stands. The served
 *  closed-form position; never a client derivation. */
export function fleetNow(fleet: FleetView, portByCode: Record<string, SnapshotPort>): LatLon | null {
  const pos = fleet.voyage?.position
  if (pos) return { lat: pos.lat, lon: pos.lon }
  return sailOrigin(fleet, portByCode)
}

/**
 * The proposal. Null when the two points share no sailable water — which the server would refuse
 * anyway; a null here just lets the screen say so without a round trip.
 */
export function proposeCourse(nav: SeaNav, from: LatLon, to: LatLon): SeaPath | null {
  const r = findPath(nav, from, to, SCRATCH)
  // A `performance` measure, so the cost the player pays is a NUMBER anyone can read off the
  // Performance panel (or a driver) rather than a claim: the plan budgeted <=166 ms for the worst
  // search and the acceptance run re-measures it in the real browser. Marks are free when nobody
  // is looking; nothing is logged.
  if (r && typeof performance !== 'undefined' && typeof performance.measure === 'function') {
    performance.measure('passage-search', { start: performance.now() - r.ms, end: performance.now() })
  }
  return r ? r.path : null
}

/**
 * A tapped point of open water, SNAPPED to the centre of its nearest sailable cell — so the
 * destination the order carries is water by construction and the server's join tolerance is
 * never spent on the tap's own imprecision. Null when the tap is deep inland.
 */
export function snapSeaPoint(nav: SeaNav, at: LatLon): LatLon | null {
  const s = snapToNav(nav, at.lat, at.lon, 4)
  if (!s) return null
  return { lat: Number(cellLat(nav, s.row).toFixed(4)), lon: Number(cellLon(nav, s.col).toFixed(4)) }
}

/** The token the SAIL grammar reads for a water point ("33,-15") — one spelling, shared by the
 *  draft, the order line and the divert. 4 decimals ≈ 6 m; the parser takes exactly this shape. */
export function pointToken(at: LatLon): string {
  return `${Number(at.lat.toFixed(4))},${Number(at.lon.toFixed(4))}`
}

/** The inverse of {@link pointToken}: the draft carries the token; the pathfinder wants numbers. */
export function parsePointToken(token: string): LatLon | null {
  const m = /^(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$/.exec(token.trim())
  if (!m) return null
  const lat = Number(m[1])
  const lon = Number(m[2])
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
    return null
  }
  return { lat, lon }
}

/** How a water point reads on a screen: "33.0°N 15.0°W". The one wording, so the panel, the
 *  fleet chip and the report agree. */
export function pointLabel(at: LatLon): string {
  const ns = at.lat >= 0 ? 'N' : 'S'
  const ew = at.lon >= 0 ? 'E' : 'W'
  return `${Math.abs(at.lat).toFixed(1)}°${ns} ${Math.abs(at.lon).toFixed(1)}°${ew}`
}
