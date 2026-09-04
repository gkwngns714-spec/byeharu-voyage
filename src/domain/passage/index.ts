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
// ── 0076: A HARBOUR IS REACHED FROM ITS ROADS ──────────────────────────────────────────────────
// THE ROADSTEAD — the one point of open water a port is reached from — is this section's business,
// because both ends of a passage are ports far more often than they are anything else. It owns
// three readings of it and they are the only ones on the client: where a SAIL DEPARTS
// (`sailOrigin`), where it ARRIVES (`sailTarget`), and the words a screen prints to explain why
// the track does not touch the quay (`roadsteadNote`, `roadsteadCourseNote`). The chart draws the
// same served pair off `MapPort` and computes nothing either.
//
// It is a SERVED fact, never derived. The one snap this side of the wire owns is `snapToNav`, for
// a point of open water the player TAPPED (`snapSeaPoint` below) — and `tests/duplication.spec.ts`
// holds that import to this file alone, because a second answer to "where is this port reached
// from" would make the line drawn, the course proposed and the endpoint the server verifies three
// different places.
//
// MEASURED COST (docs/NAVIGATION_PLAN.md §3): a search is 2–166 ms in Node; the in-browser figure
// is re-measured in the acceptance drive. It runs once per destination pick, on the pick.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { LatLon } from '../../lib/geo'
import { formatNm } from '../../lib/format'
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

/**
 * WHERE A PORT IS REACHED FROM — her ROADS, never her quay (0076).
 *
 * The one reading of the served pair, so the three answers below cannot drift apart. For a port
 * whose own cell is sailable water this IS her coordinate and `nm` is 0, which is why 77 of the
 * world's 238 places behave exactly as they did before 0076.
 */
function roadsteadOf(port: SnapshotPort): LatLon {
  return { lat: port.roadstead.lat, lon: port.roadstead.lon }
}

/** Where a SAIL from this fleet would depart: her port's ROADS, her open anchor, or — for an order
 *  that will queue — where the current voyage ends. ONE reading, beside `fleetPortCode`'s "where
 *  does her next order happen", which answers in port codes and cannot say "33°N 15°W". */
export function sailOrigin(
  fleet: FleetView,
  portByCode: Record<string, SnapshotPort>,
): LatLon | null {
  if (fleet.port) {
    const p = portByCode[fleet.port]
    return p ? roadsteadOf(p) : null
  }
  if (fleet.anchor) return { lat: fleet.anchor[0], lon: fleet.anchor[1] }
  if (fleet.voyage) {
    if (fleet.voyage.to) {
      // A queued order departs where the current voyage ENDS — and since 0076 a voyage to a port
      // ends in her roads, so this is the same point the server will have her lying at.
      const p = portByCode[fleet.voyage.to]
      return p ? roadsteadOf(p) : null
    }
    if (fleet.voyage.dest_point) {
      return { lat: fleet.voyage.dest_point[0], lon: fleet.voyage.dest_point[1] }
    }
  }
  return null
}

/**
 * WHERE A SAIL ARRIVES — the mirror of {@link sailOrigin}, and the one authority for it.
 *
 * It reads THE ORDER'S OWN TOKENS (`dest`, `dest_point`) rather than a screen's idea of a
 * destination: those are what the order line carries and what the server parses, so the course
 * proposed and the order issued can never be about two different places. Both screens that compose
 * a SAIL already hold exactly this record.
 *
 * IT WAS WRITTEN TWICE BEFORE 0076 — `features/map/SendFleet.tsx` and
 * `features/command/CommandScreen.tsx` each turned a destination into `{ lat: p.lat, lon: p.lon }`
 * — and 0076 is precisely the change that would have had to be made in both, on the same
 * afternoon, or one screen would have gone on proposing courses the server refuses. A harbour's
 * course endpoint is her ROADS (see {@link roadsteadOf}); a tapped point of open water is itself,
 * already snapped to sailable sea by the screen that pinpointed it.
 *
 * Null when the destination names a port this world does not hold, or names nothing at all — the
 * screen then proposes no course and the server is never asked.
 */
export function sailTarget(
  /** The SAIL's argument record, as the grammar spells it. */
  args: Readonly<Record<string, string>>,
  portByCode: Record<string, SnapshotPort>,
): LatLon | null {
  const code = args['dest']
  if (code) {
    const port = portByCode[code]
    return port ? roadsteadOf(port) : null
  }
  const token = args['dest_point']
  return token ? parsePointToken(token) : null
}

/**
 * THE ROADS, IN WORDS — one wording, so a harbour screen and the map's send panel cannot explain
 * the same fact two different ways (the discipline `domain/fleet`'s stat glosses already keep).
 *
 * WHY A SENTENCE HAS TO EXIST AT ALL: at departure the marker leaves the city triangle for a point
 * up to 67.7 nm out, and without a line of plain words that reads as a bug.
 *
 * Null when the port stands on its own water. There is nothing to explain there — "0 nm off the
 * quay" is a sentence about nothing — and drawing no line is the correct picture of a distance
 * that is zero, not a degraded one.
 *
 * It does NOT reuse `ports.approach`: that column is a SEA_PLACE-only remark the lookout speaks
 * (0036), and a second meaning for that word is the §7B defect this whole slice is named around.
 */
export function roadsteadNote(nm: number): string | null {
  if (!(nm > 0)) return null
  return `The roads lie ${formatNm(nm, 1)} off the quay. Ships anchor there; a pilot takes them in.`
}

/** The same fact where an ORDER is being composed: why the track she is about to buy will not
 *  touch the quay. Shorter, because it sits under a destination's name on the chart's own glass. */
export function roadsteadCourseNote(nm: number): string | null {
  if (!(nm > 0)) return null
  return `Her course ends in the roads, ${formatNm(nm, 1)} off the quay.`
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
