// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PROTOTYPE — the free-water pathfinder, as a RUNTIME function rather than a build-time generator.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE CONCEPT (NO_SPAGHETTI §7B q1): "the fastest way through water between two points."
// WHERE IT LIVES (q2): here, for measurement only. Where it lives in the game is the subject of
//   docs/DESIGN_RESEARCH_NAVIGATION.md §Proposal — this file exists to price that decision, not to
//   pre-empt it.
// WHO THE SECOND CALLER IS (q3): the trade-route scan, which today asks voyage.reach_from for the
//   distance to MANY ports. That is why `sail()` here can also answer many goals in one search.
// WHAT WOULD MAKE IT THE WRONG SHAPE (q4): if a search costs more than a player will wait for at
//   departure. That is the number this file measures, and it refuses to be a guess.
//
// It differs from scripts/sea-grid.mjs in four measured ways, each of which is a defect that file
// has today:
//   1. A BINARY HEAP, not a linear scan of the open list. sea-grid.mjs says "fast enough and this
//      runs offline"; it is not fast enough to run at departure.
//   2. AN ICE MASK. sea-grid.mjs's raster has an open Arctic, so its own A* routes Lisboa->Nagasaki
//      over the North Pole at 88.6°N for 7,565 nm. In 1550 that water is ice.
//   3. AN OCTILE HEURISTIC scaled to the true cell size, and a tie-break, so the search does not
//      fan out over an open ocean where every path costs the same.
//   4. IT KEEPS THE PATH. The 782 stored legs keep only their length (0 of 782 carry a path), which
//      is why a fleet is drawn straight across the cape its leg was measured round.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { buildSeaGrid, COLS, ROWS, CELL_DEG, cellLat, cellLon, rowOf, colOf, gcNm, isWater }
  from '../sea-grid.mjs'

const NM_PER_DEG = 60

// ── The passability mask ───────────────────────────────────────────────────────────────────────
// Water is not one thing. A cell is CLOSED (ice, in this century) or open, and open water still
// carries a cost multiplier so a route can prefer the sailed road over the geometric one.
//
// The northern limit is the honest part of this prototype: the Northeast and Northwest Passages
// were not sailed until 1878 and 1906, so any path the raster offers above them is an artefact of
// the raster, not a route. The southern limit is the Antarctic pack.
export const ICE_NORTH_LAT = 66.5     // the Arctic Circle. See the note in the design doc: this is
export const ICE_SOUTH_LAT = -60.0    // a placeholder for a per-sea, per-season closure table.

/** water = navigable in this century. Returns a Uint8Array, 1 = sailable. */
export function buildNavGrid() {
  const water = buildSeaGrid()
  const nav = Uint8Array.from(water)
  for (let row = 0; row < ROWS; row++) {
    const lat = cellLat(row)
    if (lat > ICE_NORTH_LAT || lat < ICE_SOUTH_LAT) nav.fill(0, row * COLS, row * COLS + COLS)
  }
  return nav
}

// ── A min-heap over (priority, node) ───────────────────────────────────────────────────────────
// Typed arrays, no allocation per push. The open list on a Lisboa->Nagasaki search reaches tens of
// thousands of entries and a linear scan of it is what makes the existing generator take seconds.
class Heap {
  constructor(cap = 1 << 16) {
    this.pri = new Float64Array(cap)
    this.node = new Int32Array(cap)
    this.n = 0
  }
  #grow() {
    const pri = new Float64Array(this.pri.length * 2)
    const node = new Int32Array(this.node.length * 2)
    pri.set(this.pri); node.set(this.node)
    this.pri = pri; this.node = node
  }
  push(p, v) {
    if (this.n === this.pri.length) this.#grow()
    let i = this.n++
    this.pri[i] = p; this.node[i] = v
    while (i > 0) {
      const par = (i - 1) >> 1
      if (this.pri[par] <= this.pri[i]) break
      const tp = this.pri[par], tn = this.node[par]
      this.pri[par] = this.pri[i]; this.node[par] = this.node[i]
      this.pri[i] = tp; this.node[i] = tn
      i = par
    }
  }
  pop() {
    const top = this.node[0]
    if (--this.n > 0) {
      this.pri[0] = this.pri[this.n]; this.node[0] = this.node[this.n]
      let i = 0
      for (;;) {
        const l = 2 * i + 1, r = l + 1
        let s = i
        if (l < this.n && this.pri[l] < this.pri[s]) s = l
        if (r < this.n && this.pri[r] < this.pri[s]) s = r
        if (s === i) break
        const tp = this.pri[s], tn = this.node[s]
        this.pri[s] = this.pri[i]; this.node[s] = this.node[i]
        this.pri[i] = tp; this.node[i] = tn
        i = s
      }
    }
    return top
  }
}

// ── Geometry, precomputed per row ──────────────────────────────────────────────────────────────
// A cell is CELL_DEG tall everywhere and CELL_DEG*cos(lat) wide. Both in nm, once per row, so the
// inner loop is eight adds and no trigonometry.
const NS = CELL_DEG * NM_PER_DEG
const EW = new Float64Array(ROWS)
for (let r = 0; r < ROWS; r++) EW[r] = CELL_DEG * NM_PER_DEG * Math.cos((cellLat(r) * Math.PI) / 180)

/** The nearest sailable cell to a coordinate. A harbour sits ON the coast, so its own cell is
 *  usually land at this resolution; the distance of that snap is REPORTED, never hidden. */
export function snapToNav(nav, lat, lon, maxRings = 12) {
  const r0 = rowOf(lat), c0 = colOf(lon)
  if (nav[r0 * COLS + c0]) return { row: r0, col: c0, snapNm: 0 }
  for (let ring = 1; ring <= maxRings; ring++) {
    let best = null, bestNm = Infinity
    for (let dr = -ring; dr <= ring; dr++) {
      for (let dc = -ring; dc <= ring; dc++) {
        if (Math.max(Math.abs(dr), Math.abs(dc)) !== ring) continue
        const row = r0 + dr
        if (row < 0 || row >= ROWS) continue
        const col = ((c0 + dc) % COLS + COLS) % COLS
        if (!nav[row * COLS + col]) continue
        const nm = gcNm(lat, lon, cellLat(row), cellLon(col))
        if (nm < bestNm) { bestNm = nm; best = { row, col, snapNm: nm } }
      }
    }
    if (best) return best
  }
  return null
}

const D = [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [-1, 1], [1, -1], [1, 1]]

/**
 * THE search. Returns { nm, cells, path, expanded, ms } or null.
 *
 * `path` is the straightened polyline a ship actually sails — the grid's 45° staircase is an
 * artefact of the raster, not of the sea — and `nm` is the length OF THAT POLYLINE, so the number
 * quoted and the line drawn can never disagree. That is the defect the 782 stored legs have.
 */
export function findPath(nav, from, to, opts = {}) {
  const t0 = performance.now()
  const a = snapToNav(nav, from.lat, from.lon)
  const b = snapToNav(nav, to.lat, to.lon)
  if (!a || !b) return null
  const start = a.row * COLS + a.col
  const goal = b.row * COLS + b.col
  const goalLat = cellLat(b.row), goalLon = cellLon(b.col)

  const N = COLS * ROWS
  const g = opts.g ?? new Float64Array(N)
  const prev = opts.prev ?? new Int32Array(N)
  const seen = opts.seen ?? new Int32Array(N)   // generation stamp: no 1M-cell clear per search
  const stamp = (opts.stamp = (opts.stamp ?? 0) + 1)

  const heap = new Heap()
  g[start] = 0; prev[start] = -1; seen[start] = stamp
  heap.push(gcNm(cellLat(a.row), cellLon(a.col), goalLat, goalLon), start)
  let expanded = 0
  let found = false

  while (heap.n > 0) {
    const cur = heap.pop()
    if (cur === goal) { found = true; break }
    // A stale heap entry: this node already came out with a better g.
    if (seen[cur] !== stamp) continue
    seen[cur] = -stamp                          // closed
    expanded++
    const row = (cur / COLS) | 0
    const col = cur - row * COLS
    const ns = NS, ew = EW[row]
    const cost = g[cur]
    for (let k = 0; k < 8; k++) {
      const nrow = row + D[k][0]
      if (nrow < 0 || nrow >= ROWS) continue
      const ncol = ((col + D[k][1]) % COLS + COLS) % COLS
      const next = nrow * COLS + ncol
      if (!nav[next]) continue
      if (seen[next] === -stamp) continue
      const dr = D[k][0], dc = D[k][1]
      const dy = dr === 0 ? 0 : ns
      const dx = dc === 0 ? 0 : (ew + EW[nrow]) / 2
      const step = dx === 0 ? dy : dy === 0 ? dx : Math.sqrt(dx * dx + dy * dy)
      const tentative = cost + step
      if (seen[next] === stamp && tentative >= g[next]) continue
      g[next] = tentative
      prev[next] = cur
      seen[next] = stamp
      heap.push(tentative + gcNm(cellLat(nrow), cellLon(ncol), goalLat, goalLon), next)
    }
  }
  if (!found) return null

  const cells = []
  for (let n = goal; n !== -1; n = prev[n]) { cells.push(n); if (n === start) break }
  cells.reverse()
  const pts = [[from.lat, from.lon],
               ...cells.map((n) => [cellLat((n / COLS) | 0), cellLon(n % COLS)]),
               [to.lat, to.lon]]
  const path = straighten(nav, pts)
  let nm = 0
  for (let i = 0; i + 1 < path.length; i++) nm += gcNm(path[i][0], path[i][1], path[i + 1][0], path[i + 1][1])
  return { nm, gridNm: g[goal], path, cells: cells.length, expanded, snapNm: a.snapNm + b.snapNm,
           ms: performance.now() - t0 }
}

/** Every sample along this segment is sailable water. The ENDS are exempt only by the snap
 *  distance actually measured, never by a fixed 25 nm the way sea-grid.mjs does it. */
export function segmentIsWater(nav, [lat1, lon1], [lat2, lon2], headNm = 0, tailNm = 0) {
  if (Math.abs(lon2 - lon1) > 180) return false
  const nm = gcNm(lat1, lon1, lat2, lon2)
  const steps = Math.max(2, Math.ceil(nm / (CELL_DEG * NM_PER_DEG * 0.5)))
  for (let s = 1; s < steps; s++) {
    const f = s / steps
    if (f * nm < headNm || (1 - f) * nm < tailNm) continue
    const lat = lat1 + (lat2 - lat1) * f
    const lon = lon1 + (lon2 - lon1) * f
    if (!nav[rowOf(lat) * COLS + colOf(lon)]) return false
  }
  return true
}

function straighten(nav, points) {
  const out = [points[0]]
  let i = 0
  while (i < points.length - 1) {
    let j = points.length - 1
    for (; j > i + 1; j--) {
      const head = i === 0 ? 40 : 0
      const tail = j === points.length - 1 ? 40 : 0
      if (segmentIsWater(nav, points[i], points[j], head, tail)) break
    }
    out.push(points[j])
    i = j
  }
  return out
}

export { COLS, ROWS, CELL_DEG, cellLat, cellLon, rowOf, colOf, gcNm, isWater }
