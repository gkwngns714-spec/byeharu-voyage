import type { RouteBoard, RouteBoardRow } from '../../lib/rpc'

// THE BOARD'S FIGURES — what the Routes page's side column prints and the order its list is read in, read off the SERVED
// board and nothing else (2026-11-03, the page slice; owner row 267: *"too packed"* — the side column is the tray's and is used).
//
// WHAT THIS IS. Pure readings of `world.route_board` (0106): the order the lanes are read in (the ONE sort this screen has
// always done — the server serves every figure and no order, RoutesScreen.tsx says why the seam is here), hers apart from the
// merchants', the board's shape as counts (how many are hers, how many you could sail today, how many have no fleet), the
// first lanes of the order as a slice, and the lanes by company as a count. Every figure is a served field, a count over
// served rows or a slice of the ordered rows — never a distance measured here, never earnings summed here: `public.route_nm`
// says what a lap sails and `public.route_earnings` what it earns, and a client that re-derived either would be a second
// authority (docs/NO_SPAGHETTI.md §1, §2: a reading of a served payload with no React, no store and no screen in it).
//
// WHERE IT LIVES, AND WHY. It is the Routes screen's own vocabulary over its own read; no other screen reads the board
// (useRouteBoard.ts: asked when ROUTES mounts, never on the beat). THE SECOND CALLER is implausible by construction — a second
// screen printing the world's lanes would be the duplicate "one fact, one home" refuses (tests/consistency.spec.ts) — so it
// stays in the screen rather than in src/domain; the day it is wanted twice, it moves there whole. In its own file rather than
// RoutesScreen.tsx so the screen file holds components and the readings can be read without a browser.

/** The three orders, which are the owner's own three (row 115): how far a lap sails, what a lap earns, how many harbours it
 *  calls at. */
export type Order = 'nm' | 'earned' | 'calls'

/** THE FIGURE A LANE IS RANKED BY under an order — NULL where the server has none (an unmeasured lap, earnings before a
 *  second lap closes). The row says the absence in a word; the order sorts it last. */
export function rankedOf(route: RouteBoardRow, order: Order): number | null {
  if (order === 'nm') return route.nm
  if (order === 'calls') return route.stop_count
  return route.earnings.lap
}

/** THE ORDER THE BOARD IS READ IN. Within each order the tie-break is the NAME, so the list does not shuffle under the player
 *  between two reads of the same figures. A figure the server has not got sorts LAST rather than as a zero: the route has not
 *  earned nothing and is not nought miles long, the server has declined to say. */
export function sortRoutes(rows: readonly RouteBoardRow[], order: Order): RouteBoardRow[] {
  const by = (r: RouteBoardRow): number => rankedOf(r, order) ?? Number.NEGATIVE_INFINITY
  return [...rows].sort((a, b) => by(b) - by(a) || a.name.localeCompare(b.name))
}

/** HERS APART FROM THE MERCHANTS' — each group keeps the order it was given. The server serves no other player's lanes
 *  (DESIGN §E.5), so every lane that is not hers is a merchant company's. */
export function groupsOf(rows: readonly RouteBoardRow[]): { mine: RouteBoardRow[]; others: RouteBoardRow[] } {
  return { mine: rows.filter((r) => r.mine), others: rows.filter((r) => !r.mine) }
}

/** THE BOARD'S SHAPE, as counts over the served rows. */
export interface BoardFigures {
  /** Lanes on the board (served; `omitted` says how many more the world holds). */
  lanes: number
  /** Hers. */
  mine: number
  /** The merchants'. */
  merchants: number
  /** Lanes you could sail today (`closed` false: the gate would not refuse you). */
  inReach: number
  /** Lanes shut to you today (`closed`: the navigation its longest leg asks is above yours). */
  outOfReach: number
  /** Lanes with no fleet on them — plans, not lanes. */
  noFleet: number
}

export function figuresOf(board: RouteBoard): BoardFigures {
  const rows = board.routes
  const mine = rows.filter((r) => r.mine).length
  const outOfReach = rows.filter((r) => r.closed).length
  return {
    lanes: rows.length,
    mine,
    merchants: rows.length - mine,
    inReach: rows.length - outOfReach,
    outOfReach,
    noFleet: rows.filter((r) => !r.assigned).length,
  }
}

/** A lane on a ranked board: the lane and the figure it stands for. */
export interface TopLane {
  route: RouteBoardRow
  value: number
}

/** THE FIRST `n` LANES OF THE ORDER that carry the ranked figure — a slice of the ordered rows (the lanes the server has no
 *  figure for stand at the order's end and are not a bar of nothing). Hers and the merchants' together: the board ranks
 *  lanes, and a bar board answers "which of these is big" over all of them. */
export function topOf(rows: readonly RouteBoardRow[], order: Order, n: number): TopLane[] {
  const out: TopLane[] = []
  for (const route of sortRoutes(rows, order)) {
    const value = rankedOf(route, order)
    if (value === null) continue
    out.push({ route, value })
    if (out.length === n) break
  }
  return out
}

/** A company on the board and how many of its lanes are served. */
export interface CompanyLanes {
  /** The company's served name; null for hers (the board serves no name on her own lanes — she knows whose they are). */
  company: string | null
  nation: string | null
  lanes: number
}

/** THE LANES BY COMPANY — a count over the served rows, most lanes first (ties by name, as the list), the first `n`. Hers are
 *  one company with no name (`company` null). */
export function companiesOf(rows: readonly RouteBoardRow[], n: number): CompanyLanes[] {
  const byName = new Map<string, CompanyLanes>()
  for (const r of rows) {
    const key = r.mine ? '' : (r.company ?? '')
    const seen = byName.get(key)
    if (seen !== undefined) seen.lanes += 1
    else byName.set(key, { company: r.mine ? null : r.company, nation: r.mine ? null : r.nation_code, lanes: 1 })
  }
  return [...byName.values()].sort((a, b) => b.lanes - a.lanes || (a.company ?? '').localeCompare(b.company ?? '')).slice(0, n)
}
