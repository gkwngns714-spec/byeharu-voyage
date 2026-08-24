// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PATHFINDER — the fastest way through water between two points, PROPOSED here, never decided.
//
// §7B — the four questions:
//   CONCEPT      "the fastest sailable path between two coordinates over the navigable-sea grid."
//   LIVES HERE   src/lib/sea — machinery. It holds no opinion about fleets, stores or orders; the
//                same search would route a courier over a road grid. What it produces is a
//                PROPOSAL: the server (migration 0039's `voyage.path_refusal` / `voyage.path_nm`)
//                is the only authority on whether a path is legal water and on what it measures.
//                A client that lied here gains nothing — land is refused, and a longer path only
//                costs its own player days and stores (docs/NAVIGATION_PLAN.md §3).
//   SECOND CALLER  scripts/build-sea-migration.mjs (the all-pairs distance seed) and
//                scripts/build-proof-paths.mjs (the proofs' own proposals) run this exact file
//                under Node, so the numbers the economy quotes and the paths the proofs sail are
//                produced by the same search the player's browser runs.
//   WRONG SHAPE  if a search costs more than a player will wait at the moment of ordering.
//                Measured (scripts/proto, 2026-08-24, recorded in docs/NAVIGATION_PLAN.md §3):
//                worst single search 166 ms in Node; the browser figure is re-measured in the
//                acceptance drive. If that budget is ever blown, fix the search — do not cache
//                routes into a fixed graph; the owner refused that model three times.
//
// This file is the prototype `scripts/proto/pathfind.mjs` moved into the product (the plan's
// instruction: reuse, do not rewrite), with two changes: the grid arrives as a served `SeaNav`
// instead of being built from Natural Earth here, and the ice policy is IN the served raster
// (0038) rather than a latitude clamp of this file's own.
//
// Four properties carried from the prototype, each a measured defect of the generator it replaced:
//   1. A BINARY HEAP, not a linear scan of the open list.
//   2. AN OCTILE-SCALED heuristic (the plain great circle to the goal — admissible on this grid),
//      so the search does not fan out over an open ocean where every path costs the same.
//   3. IT KEEPS THE PATH — straightened by line-of-sight over water, so the line a chart draws and
//      the miles the server measures are the same polyline.
//   4. SNAP IS MEASURED, never assumed: a harbour's own cell is usually land at 0.25°, and the
//      distance of the snap to open water is reported so nothing hides it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { cellLat, cellLon, colOf, gcNm, rowOf, type SeaNav } from './grid.ts'

const NM_PER_DEG = 60

// ── A min-heap over (priority, node) ───────────────────────────────────────────────────────────
// Typed arrays, no allocation per push. The open list on a Lisboa→Nagasaki search reaches tens of
// thousands of entries and a linear scan of it is what made the old generator take seconds.
class Heap {
  pri: Float64Array
  node: Int32Array
  n = 0

  constructor(cap = 1 << 16) {
    this.pri = new Float64Array(cap)
    this.node = new Int32Array(cap)
  }

  private grow(): void {
    const pri = new Float64Array(this.pri.length * 2)
    const node = new Int32Array(this.node.length * 2)
    pri.set(this.pri)
    node.set(this.node)
    this.pri = pri
    this.node = node
  }

  push(p: number, v: number): void {
    if (this.n === this.pri.length) this.grow()
    let i = this.n++
    this.pri[i] = p
    this.node[i] = v
    while (i > 0) {
      const par = (i - 1) >> 1
      if (this.pri[par] <= this.pri[i]) break
      const tp = this.pri[par]
      const tn = this.node[par]
      this.pri[par] = this.pri[i]
      this.node[par] = this.node[i]
      this.pri[i] = tp
      this.node[i] = tn
      i = par
    }
  }

  pop(): number {
    const top = this.node[0]
    if (--this.n > 0) {
      this.pri[0] = this.pri[this.n]
      this.node[0] = this.node[this.n]
      let i = 0
      for (;;) {
        const l = 2 * i + 1
        const r = l + 1
        let s = i
        if (l < this.n && this.pri[l] < this.pri[s]) s = l
        if (r < this.n && this.pri[r] < this.pri[s]) s = r
        if (s === i) break
        const tp = this.pri[s]
        const tn = this.node[s]
        this.pri[s] = this.pri[i]
        this.node[s] = this.node[i]
        this.pri[i] = tp
        this.node[i] = tn
        i = s
      }
    }
    return top
  }
}

// ── Geometry, precomputed per row ──────────────────────────────────────────────────────────────
// A cell is cellDeg tall everywhere and cellDeg·cos(lat) wide. Both in nm, once per row per grid,
// so the inner loop is eight adds and no trigonometry. Keyed by the SeaNav object: the store
// holds exactly one, and a test building a second grid gets its own row table rather than a stale
// one.
const EW_CACHE = new WeakMap<SeaNav, Float64Array>()

function ewOf(nav: SeaNav): Float64Array {
  let ew = EW_CACHE.get(nav)
  if (!ew) {
    ew = new Float64Array(nav.rows)
    for (let r = 0; r < nav.rows; r++) {
      ew[r] = nav.cellDeg * NM_PER_DEG * Math.cos((cellLat(nav, r) * Math.PI) / 180)
    }
    EW_CACHE.set(nav, ew)
  }
  return ew
}

export interface LatLonPoint {
  readonly lat: number
  readonly lon: number
}

/** A polyline over the water: [lat, lon] pairs, ends included. */
export type SeaPath = [number, number][]

export interface FoundPath {
  /** The length OF THE POLYLINE, so the number quoted and the line drawn cannot disagree. */
  nm: number
  /** The raw grid-chain length, before straightening. Always ≥ nm. */
  gridNm: number
  path: SeaPath
  cells: number
  expanded: number
  /** How far the two ends had to snap to reach sailable water, summed. Reported, never hidden. */
  snapNm: number
  ms: number
}

/** The nearest sailable cell to a coordinate. A harbour sits ON the coast, so its own cell is
 *  usually land at this resolution; the distance of that snap is REPORTED, never hidden. */
export function snapToNav(
  nav: SeaNav,
  lat: number,
  lon: number,
  maxRings = 12,
): { row: number; col: number; snapNm: number } | null {
  const r0 = rowOf(nav, lat)
  const c0 = colOf(nav, lon)
  if (nav.cells[r0 * nav.cols + c0]) return { row: r0, col: c0, snapNm: 0 }
  for (let ring = 1; ring <= maxRings; ring++) {
    let best: { row: number; col: number; snapNm: number } | null = null
    let bestNm = Infinity
    for (let dr = -ring; dr <= ring; dr++) {
      for (let dc = -ring; dc <= ring; dc++) {
        if (Math.max(Math.abs(dr), Math.abs(dc)) !== ring) continue
        const row = r0 + dr
        if (row < 0 || row >= nav.rows) continue
        const col = (((c0 + dc) % nav.cols) + nav.cols) % nav.cols
        if (!nav.cells[row * nav.cols + col]) continue
        const nm = gcNm(lat, lon, cellLat(nav, row), cellLon(nav, col))
        if (nm < bestNm) {
          bestNm = nm
          best = { row, col, snapNm: nm }
        }
      }
    }
    if (best) return best
  }
  return null
}

const D = [
  [-1, 0],
  [1, 0],
  [0, -1],
  [0, 1],
  [-1, -1],
  [-1, 1],
  [1, -1],
  [1, 1],
] as const

/** Reusable per-search scratch, so consecutive searches (a picker, a bench, the distance seed)
 *  do not allocate three million-entry arrays each. Generation-stamped: no full clear per search. */
export interface SearchScratch {
  g?: Float64Array
  prev?: Int32Array
  seen?: Int32Array
  stamp?: number
}

/**
 * THE search. Returns the straightened polyline a ship actually sails — the grid's 45° staircase
 * is an artefact of the raster, not of the sea — and `nm` is the length OF THAT POLYLINE.
 * Null when no sailable way exists (or an end cannot reach water at all).
 */
export function findPath(
  nav: SeaNav,
  from: LatLonPoint,
  to: LatLonPoint,
  scratch: SearchScratch = {},
): FoundPath | null {
  const t0 = performance.now()
  const a = snapToNav(nav, from.lat, from.lon)
  const b = snapToNav(nav, to.lat, to.lon)
  if (!a || !b) return null
  const COLS = nav.cols
  const ROWS = nav.rows
  const start = a.row * COLS + a.col
  const goal = b.row * COLS + b.col
  const goalLat = cellLat(nav, b.row)
  const goalLon = cellLon(nav, b.col)
  const EW = ewOf(nav)
  const NS = nav.cellDeg * NM_PER_DEG

  const N = COLS * ROWS
  const g = (scratch.g ??= new Float64Array(N))
  const prev = (scratch.prev ??= new Int32Array(N))
  const seen = (scratch.seen ??= new Int32Array(N))
  const stamp = (scratch.stamp = (scratch.stamp ?? 0) + 1)

  const heap = new Heap()
  g[start] = 0
  prev[start] = -1
  seen[start] = stamp
  heap.push(gcNm(cellLat(nav, a.row), cellLon(nav, a.col), goalLat, goalLon), start)
  let expanded = 0
  let found = false

  while (heap.n > 0) {
    const cur = heap.pop()
    if (cur === goal) {
      found = true
      break
    }
    // A stale heap entry: this node already came out with a better g.
    if (seen[cur] !== stamp) continue
    seen[cur] = -stamp // closed
    expanded++
    const row = (cur / COLS) | 0
    const col = cur - row * COLS
    const ew = EW[row]
    const cost = g[cur]
    for (let k = 0; k < 8; k++) {
      const nrow = row + D[k][0]
      if (nrow < 0 || nrow >= ROWS) continue
      const ncol = (((col + D[k][1]) % COLS) + COLS) % COLS
      const next = nrow * COLS + ncol
      if (!nav.cells[next]) continue
      if (seen[next] === -stamp) continue
      const dy = D[k][0] === 0 ? 0 : NS
      const dx = D[k][1] === 0 ? 0 : (ew + EW[nrow]) / 2
      const step = dx === 0 ? dy : dy === 0 ? dx : Math.sqrt(dx * dx + dy * dy)
      const tentative = cost + step
      if (seen[next] === stamp && tentative >= g[next]) continue
      g[next] = tentative
      prev[next] = cur
      seen[next] = stamp
      heap.push(tentative + gcNm(cellLat(nav, nrow), cellLon(nav, ncol), goalLat, goalLon), next)
    }
  }
  if (!found) return null

  const cellChain: number[] = []
  for (let n = goal; n !== -1; n = prev[n]) {
    cellChain.push(n)
    if (n === start) break
  }
  cellChain.reverse()
  const pts: SeaPath = [
    [from.lat, from.lon],
    ...cellChain.map((n): [number, number] => [cellLat(nav, (n / COLS) | 0), cellLon(nav, n % COLS)]),
    [to.lat, to.lon],
  ]
  const path = straighten(nav, pts, a.snapNm + cellDiagNm(nav), b.snapNm + cellDiagNm(nav))
  let nm = 0
  for (let i = 0; i + 1 < path.length; i++) {
    nm += gcNm(path[i][0], path[i][1], path[i + 1][0], path[i + 1][1])
  }
  return {
    nm,
    gridNm: g[goal],
    path,
    cells: cellChain.length,
    expanded,
    snapNm: a.snapNm + b.snapNm,
    ms: performance.now() - t0,
  }
}

/**
 * Every sample along this segment is sailable water. The ENDS are exempt only by the head/tail
 * allowance actually measured (a harbour approach), never by a fixed figure. A segment whose two
 * ends straddle the antimeridian the long way round is refused — the search never emits one, and
 * the server's verifier applies the same reading.
 */
export function segmentIsWater(
  nav: SeaNav,
  [lat1, lon1]: readonly [number, number],
  [lat2, lon2]: readonly [number, number],
  headNm = 0,
  tailNm = 0,
): boolean {
  if (Math.abs(lon2 - lon1) > 180) return false
  const nm = gcNm(lat1, lon1, lat2, lon2)
  const steps = Math.max(2, Math.ceil(nm / (nav.cellDeg * NM_PER_DEG * 0.5)))
  for (let s = 1; s < steps; s++) {
    const f = s / steps
    if (f * nm < headNm || (1 - f) * nm < tailNm) continue
    const lat = lat1 + (lat2 - lat1) * f
    const lon = lon1 + (lon2 - lon1) * f
    if (!nav.cells[rowOf(nav, lat) * nav.cols + colOf(nav, lon)]) return false
  }
  return true
}

/** One cell diagonal in nm — the sampling slack past a measured snap. THE APPROACH RULE, shared
 *  with the server: an end of a path may run over the coast for its MEASURED snap distance plus
 *  one cell diagonal, never for a fixed guess. The server's `voyage.path_refusal` allows the
 *  same snap (from `sea_reaches.snap_nm`) plus a slightly LARGER slack (25 nm), so a course this
 *  straightener passes can never be refused for its own approach. */
const cellDiagNm = (nav: SeaNav): number => nav.cellDeg * NM_PER_DEG * Math.SQRT2

function straighten(nav: SeaNav, points: SeaPath, headNm: number, tailNm: number): SeaPath {
  const out: SeaPath = [points[0]]
  let i = 0
  while (i < points.length - 1) {
    let j = points.length - 1
    for (; j > i + 1; j--) {
      const head = i === 0 ? headNm : 0
      const tail = j === points.length - 1 ? tailNm : 0
      if (segmentIsWater(nav, points[i], points[j], head, tail)) break
    }
    out.push(points[j])
    i = j
  }
  return out
}

// ── The flood: one source, every distance ──────────────────────────────────────────────────────

export interface Flood {
  readonly nav: SeaNav
  readonly g: Float64Array
  readonly prev: Int32Array
  readonly seen: Uint8Array
  readonly source: { row: number; col: number; snapNm: number }
}

/**
 * Dijkstra from one coordinate over the whole grid (bounded by `limitNm` when given): the
 * distance to EVERY cell in one pass, where A* answers one goal. This is what prices the
 * all-pairs seed (0038) and the proofs' path table — 228 floods instead of 25,878 searches.
 */
export function floodFrom(nav: SeaNav, from: LatLonPoint, limitNm = Infinity): Flood | null {
  const source = snapToNav(nav, from.lat, from.lon)
  if (!source) return null
  const COLS = nav.cols
  const ROWS = nav.rows
  const N = COLS * ROWS
  const EW = ewOf(nav)
  const NS = nav.cellDeg * NM_PER_DEG
  const g = new Float64Array(N)
  const prev = new Int32Array(N).fill(-1)
  const seen = new Uint8Array(N) // 0 unseen · 1 open · 2 closed
  const heap = new Heap()
  const start = source.row * COLS + source.col
  g[start] = 0
  seen[start] = 1
  heap.push(0, start)
  while (heap.n > 0) {
    const cur = heap.pop()
    if (seen[cur] === 2) continue
    seen[cur] = 2
    const row = (cur / COLS) | 0
    const col = cur - row * COLS
    const ew = EW[row]
    const cost = g[cur]
    if (cost > limitNm) continue
    for (let k = 0; k < 8; k++) {
      const nrow = row + D[k][0]
      if (nrow < 0 || nrow >= ROWS) continue
      const ncol = (((col + D[k][1]) % COLS) + COLS) % COLS
      const next = nrow * COLS + ncol
      if (!nav.cells[next]) continue
      if (seen[next] === 2) continue
      const dy = D[k][0] === 0 ? 0 : NS
      const dx = D[k][1] === 0 ? 0 : (ew + EW[nrow]) / 2
      const step = dx === 0 ? dy : dy === 0 ? dx : Math.sqrt(dx * dx + dy * dy)
      const tentative = cost + step
      if (seen[next] === 1 && tentative >= g[next]) continue
      g[next] = tentative
      prev[next] = cur
      seen[next] = 1
      heap.push(tentative, next)
    }
  }
  return { nav, g, prev, seen, source }
}

/** The straightened path from a flood's source to a coordinate, or null if the flood never
 *  reached it. Same straightening, same measure, as {@link findPath}. */
export function floodPathTo(
  flood: Flood,
  from: LatLonPoint,
  to: LatLonPoint,
): { nm: number; gridNm: number; path: SeaPath } | null {
  const nav = flood.nav
  const b = snapToNav(nav, to.lat, to.lon)
  if (!b) return null
  const goal = b.row * nav.cols + b.col
  if (flood.seen[goal] !== 2) return null
  const chain: number[] = []
  for (let n = goal; n !== -1; n = flood.prev[n]) chain.push(n)
  chain.reverse()
  const pts: SeaPath = [
    [from.lat, from.lon],
    ...chain.map((n): [number, number] => [
      cellLat(nav, (n / nav.cols) | 0),
      cellLon(nav, n % nav.cols),
    ]),
    [to.lat, to.lon],
  ]
  const path = straighten(nav, pts, flood.source.snapNm + cellDiagNm(nav), b.snapNm + cellDiagNm(nav))
  let nm = 0
  for (let i = 0; i + 1 < path.length; i++) {
    nm += gcNm(path[i][0], path[i][1], path[i + 1][0], path[i + 1][1])
  }
  return { nm, gridNm: flood.g[goal], path }
}
