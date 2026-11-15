// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COURSE, HELD OFF THE DRAWN LAND (owner row 352, 2026-11-15)
//
// The owner: *"some ships go pass through land - such as hadibu ... fix this properly"*.
//
// WHY A COURSE COULD CROSS LAND. The sea is a 0.25-degree raster (public.sea_raster), scan-filled
// from Natural Earth 1:110m, which has no Socotra, no Bangka, no Gallipoli peninsula worth the name.
// The pathfinder (./pathfind.ts) searches that raster and then STRAIGHTENS the cell chain: two
// vertices are joined whenever every half-cell sample between them is raster water. So a course is
// legal by the server (voyage.path_refusal reads the same raster the same way) and is still drawn,
// on the chart's 1:10m coast, straight over an island, a cape or a peninsula 15 nm across.
//
// WHAT THIS DOES. Given a course and the land the chart draws (`blocked`, a point test; Node reads
// it from the chart's own tiles, scripts/lib/drawn-land.mjs), every segment that runs over drawn
// land is re-sailed: the stretch around the land is searched again on a FINE grid (FINE_PER_DEG
// cells a degree, 1.5 nm) whose cells are water by BOTH rules (raster water, and not drawn land),
// and the result is straightened by line of sight under both rules. What comes back:
//   * every vertex and every segment is still raster water by the server's own sampling
//     (`segmentIsWater`), so voyage.path_refusal accepts it exactly as before;
//   * no segment runs over more than `toleranceNm` of drawn land, unless the fine search found no
//     way at all (reported in `residual`, never hidden);
//   * the two ends are kept exactly (a course is joined to its roadsteads).
// A course that crosses no land comes back unchanged, vertex for vertex.
//
// PURE: no I/O, no DOM. The generator (scripts/build-land-channels.mjs) runs it over every stored
// course; the browser can run the same function once it holds the tiles along a course.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { lonLerp } from '../geo/index.ts'
import { gcNm, type SeaNav } from './grid.ts'
import { findPath, segmentIsWater, type SeaPath } from './pathfind.ts'

/** The fine grid's cells a degree: 0.025 degrees, 1.5 nm north-south. */
export const FINE_PER_DEG = 40

/** How finely a segment is walked over the drawn land, in nm. */
export const LAND_STEP_NM = 0.25

/** The default allowance: a clip of a cape shorter than this is inside the chart's own drawing
 *  error (the mid-level coast is simplified by 0.03 degrees, 1.8 nm). */
export const LAND_TOLERANCE_NM = 2

export interface DrawnLand {
  /** True when the point is on land the chart draws AND not water the game opened on purpose. */
  blocked(lat: number, lon: number): boolean
}

export interface LandRun {
  /** Index of the segment the run is on. */
  seg: number
  /** Length of the run, in nm. */
  nm: number
  /** Where along the segment it starts and ends, as fractions. */
  f0: number
  f1: number
}

/** Every run of consecutive samples on drawn land along one segment. */
export function segmentLandRuns(
  land: DrawnLand,
  [lat1, lon1]: readonly [number, number],
  [lat2, lon2]: readonly [number, number],
  seg = 0,
  stepNm = LAND_STEP_NM,
): LandRun[] {
  const nm = gcNm(lat1, lon1, lat2, lon2)
  const steps = Math.max(1, Math.ceil(nm / stepNm))
  const runs: LandRun[] = []
  let start = -1
  let count = 0
  for (let s = 0; s <= steps; s++) {
    const f = s / steps
    const on = land.blocked(lat1 + (lat2 - lat1) * f, lonLerp(lon1, lon2, f))
    if (on) {
      if (start < 0) start = s
      count++
    } else if (start >= 0) {
      runs.push({ seg, nm: (count * nm) / steps, f0: start / steps, f1: (s - 1) / steps })
      start = -1
      count = 0
    }
  }
  if (start >= 0) runs.push({ seg, nm: (count * nm) / steps, f0: start / steps, f1: 1 })
  return runs
}

/** The longest run of drawn land along a segment, in nm. */
export function longestLandRun(land: DrawnLand, a: readonly [number, number], b: readonly [number, number]): number {
  let worst = 0
  for (const r of segmentLandRuns(land, a, b)) if (r.nm > worst) worst = r.nm
  return worst
}

/** Every run over the tolerance along a whole course. */
export function courseLandRuns(land: DrawnLand, course: SeaPath, toleranceNm = LAND_TOLERANCE_NM): LandRun[] {
  const out: LandRun[] = []
  for (let i = 0; i + 1 < course.length; i++) {
    for (const r of segmentLandRuns(land, course[i], course[i + 1], i)) if (r.nm > toleranceNm) out.push(r)
  }
  return out
}

export interface RefineResult {
  path: SeaPath
  /** True when any segment was re-sailed. */
  changed: boolean
  /** Runs over the tolerance that remain (the fine search found no way round). */
  residual: LandRun[]
}

const pointAt = (a: readonly [number, number], b: readonly [number, number], f: number): [number, number] => [
  a[0] + (b[0] - a[0]) * f,
  lonLerp(a[1], b[1], f),
]

/** THE SERVER'S APPROACH SLACK: voyage.path_refusal lets a course's first and last stretch run
 *  over raster land for the harbour's snap plus this flat allowance (0076), so a course joined to
 *  its roadstead is judged here exactly as cmd.do_sail judges it. */
export const APPROACH_SLACK_NM = 25

/** Is the straight line A→B clear by both rules? `head`/`tail`: it starts/ends the course. */
function clear(
  nav: SeaNav,
  land: DrawnLand,
  a: readonly [number, number],
  b: readonly [number, number],
  tolNm: number,
  head = false,
  tail = false,
): boolean {
  return (
    segmentIsWater(nav, a, b, head ? APPROACH_SLACK_NM : 0, tail ? APPROACH_SLACK_NM : 0) &&
    longestLandRun(land, a, b) <= tolNm
  )
}

/** Does every segment of a course verify against the raster, as voyage.path_refusal reads it? */
export function courseIsWater(nav: SeaNav, path: SeaPath): boolean {
  for (let k = 1; k < path.length; k++) {
    const head = k === 1 ? APPROACH_SLACK_NM : 0
    const tail = k === path.length - 1 ? APPROACH_SLACK_NM : 0
    if (!segmentIsWater(nav, path[k - 1], path[k], head, tail)) return false
  }
  return true
}

/**
 * THE FINE SEARCH: A* from `from` to `to` over cells of 1/FINE_PER_DEG degrees inside a box, a
 * cell passable when its centre is raster water and not drawn land. Longitudes are unwrapped
 * relative to `from` so a box may straddle the antimeridian. Null when no way exists in the box.
 */
export function fineSearch(
  nav: SeaNav,
  land: DrawnLand,
  from: readonly [number, number],
  to: readonly [number, number],
  marginDeg: number,
): SeaPath | null {
  const G = FINE_PER_DEG
  let dLon = to[1] - from[1]
  if (dLon > 180) dLon -= 360
  else if (dLon < -180) dLon += 360
  const toLonU = from[1] + dLon
  // The box is laid on the world's own 1/G lattice, so a fine cell IS a cell of the coast mask
  // (./coastMask.ts): one cell, one answer, whichever search asks.
  const south = Math.max(-89, Math.floor((Math.min(from[0], to[0]) - marginDeg) * G) / G)
  const north = Math.min(89, Math.ceil((Math.max(from[0], to[0]) + marginDeg) * G) / G)
  const lonMargin = marginDeg / Math.max(0.2, Math.cos(((from[0] + to[0]) / 2) * (Math.PI / 180)))
  const west = Math.floor((Math.min(from[1], toLonU) - lonMargin) * G) / G
  const east = Math.ceil((Math.max(from[1], toLonU) + lonMargin) * G) / G
  const rows = Math.max(2, Math.ceil((north - south) * G))
  const cols = Math.max(2, Math.ceil((east - west) * G))
  // A bound on the work a click may cost: about 1,600 x 1,250 cells (40 by 30 degrees at the equator).
  if (rows * cols > 2_000_000) return null
  const latOf = (r: number) => north - (r + 0.5) / G
  const lonOf = (c: number) => {
    let l = west + (c + 0.5) / G
    if (l > 180) l -= 360
    else if (l < -180) l += 360
    return l
  }
  const N = rows * cols
  // bit 0: known · bit 1: raster water · bit 2: drawn land
  const pass = new Uint8Array(N)
  const state = (k: number): number => {
    let v = pass[k]
    if (v === 0) {
      const r = (k / cols) | 0
      const c = k - r * cols
      const lat = latOf(r)
      const lon = lonOf(c)
      const rr = Math.min(nav.rows - 1, Math.max(0, Math.floor((90 - lat) / nav.cellDeg)))
      const cc = ((Math.floor((lon + 180) / nav.cellDeg) % nav.cols) + nav.cols) % nav.cols
      // A fine cell is drawn water only when all four of its quarters are: its centre lies on the
      // corner of four of the land bitmap's pixels, and a step from it must not start on land.
      const q = 1 / (4 * G)
      const dry =
        land.blocked(lat + q, lon - q) || land.blocked(lat + q, lon + q) || land.blocked(lat - q, lon - q) || land.blocked(lat - q, lon + q)
      v = 1 | (nav.cells[rr * nav.cols + cc] ? 2 : 0) | (dry ? 4 : 0)
      pass[k] = v
    }
    return v
  }
  const passable = (k: number): boolean => state(k) === 3
  const cellOf = (lat: number, lonU: number) => {
    const r = Math.min(rows - 1, Math.max(0, Math.floor((north - lat) * G)))
    const c = Math.min(cols - 1, Math.max(0, Math.floor((lonU - west) * G)))
    return r * cols + c
  }
  /** The nearest passable cell to a point (rings out to a quarter degree), or -1. */
  const snap = (k0: number): number => {
    if (passable(k0)) return k0
    const r0 = (k0 / cols) | 0
    const c0 = k0 - r0 * cols
    for (let ring = 1; ring <= G / 4 + 2; ring++) {
      let best = -1
      let bestD = Infinity
      for (let dr = -ring; dr <= ring; dr++) {
        for (let dc = -ring; dc <= ring; dc++) {
          if (Math.max(Math.abs(dr), Math.abs(dc)) !== ring) continue
          const r = r0 + dr
          const c = c0 + dc
          if (r < 0 || r >= rows || c < 0 || c >= cols) continue
          const k = r * cols + c
          if (!passable(k)) continue
          const d = dr * dr + dc * dc
          if (d < bestD) {
            bestD = d
            best = k
          }
        }
      }
      if (best >= 0) return best
    }
    return -1
  }
  const start = snap(cellOf(from[0], from[1]))
  const goal = snap(cellOf(to[0], toLonU))
  if (start < 0 || goal < 0) return null

  const NS = 60 / G
  const ewRow = new Float64Array(rows)
  for (let r = 0; r < rows; r++) ewRow[r] = NS * Math.cos(latOf(r) * (Math.PI / 180))
  const gr = (goal / cols) | 0
  const gc = goal - gr * cols
  const h = (k: number) => {
    const r = (k / cols) | 0
    const c = k - r * cols
    const dy = (r - gr) * NS
    const dx = (c - gc) * ewRow[r]
    return Math.sqrt(dx * dx + dy * dy)
  }
  const g = new Float64Array(N).fill(Infinity)
  const prev = new Int32Array(N).fill(-1)
  const closed = new Uint8Array(N)
  // A small binary heap.
  let hp = new Float64Array(1024)
  let hn = new Int32Array(1024)
  let n = 0
  const push = (p: number, v: number) => {
    if (n === hp.length) {
      const p2 = new Float64Array(n * 2)
      p2.set(hp)
      hp = p2
      const n2 = new Int32Array(n * 2)
      n2.set(hn)
      hn = n2
    }
    let i = n++
    hp[i] = p
    hn[i] = v
    while (i > 0) {
      const par = (i - 1) >> 1
      if (hp[par] <= hp[i]) break
      ;[hp[par], hp[i]] = [hp[i], hp[par]]
      ;[hn[par], hn[i]] = [hn[i], hn[par]]
      i = par
    }
  }
  const pop = () => {
    const top = hn[0]
    if (--n > 0) {
      hp[0] = hp[n]
      hn[0] = hn[n]
      let i = 0
      for (;;) {
        const l = 2 * i + 1
        const r = l + 1
        let s = i
        if (l < n && hp[l] < hp[s]) s = l
        if (r < n && hp[r] < hp[s]) s = r
        if (s === i) break
        ;[hp[s], hp[i]] = [hp[i], hp[s]]
        ;[hn[s], hn[i]] = [hn[i], hn[s]]
        i = s
      }
    }
    return top
  }
  g[start] = 0
  push(h(start), start)
  let found = false
  while (n > 0) {
    const cur = pop()
    if (closed[cur]) continue
    if (cur === goal) {
      found = true
      break
    }
    closed[cur] = 1
    const r = (cur / cols) | 0
    const c = cur - r * cols
    for (let dr = -1; dr <= 1; dr++) {
      const nr = r + dr
      if (nr < 0 || nr >= rows) continue
      for (let dc = -1; dc <= 1; dc++) {
        if (dr === 0 && dc === 0) continue
        const nc = c + dc
        if (nc < 0 || nc >= cols) continue
        const k = nr * cols + nc
        if (closed[k] || !passable(k)) continue
        const dx = dc === 0 ? 0 : (ewRow[r] + ewRow[nr]) / 2
        const dy = dr === 0 ? 0 : NS
        const t = g[cur] + (dx === 0 ? dy : dy === 0 ? dx : Math.sqrt(dx * dx + dy * dy))
        if (t >= g[k]) continue
        g[k] = t
        prev[k] = cur
        push(t + h(k), k)
      }
    }
  }
  if (!found) return null
  const chain: number[] = []
  for (let k = goal; k !== -1; k = prev[k]) chain.push(k)
  chain.reverse()
  return chain.map((k): [number, number] => {
    const r = (k / cols) | 0
    return [latOf(r), lonOf(k - r * cols)]
  })
}

/** The longest stretch of course one search window may cover (0440): clusters of land closer than
 *  60 nm are searched as one, up to this length, so a long coast is still searched in boxes the
 *  fine search can afford. */
const MAX_WINDOW_NM = 300

const PULL_AHEAD = 80
const PULL_SPAN_NM = 400

/** Greedy line of sight under both rules; adjacent points are always joined. `head`/`tail`: the
 *  stretch starts/ends the whole course, so the server's approach slack applies there. */
function pull(nav: SeaNav, land: DrawnLand, pts: SeaPath, tolNm: number, head: boolean, tail: boolean): SeaPath {
  const out: SeaPath = [pts[0]]
  let i = 0
  while (i < pts.length - 1) {
    // A bounded look ahead (PULL_AHEAD points, PULL_SPAN_NM of line): every check samples its whole
    // line, and an ocean-long one is never the shortcut that matters near a coast.
    let j = Math.min(pts.length - 1, i + PULL_AHEAD)
    while (j > i + 1 && gcNm(pts[i][0], pts[i][1], pts[j][0], pts[j][1]) > PULL_SPAN_NM) j--
    for (; j > i + 1; j--) if (clear(nav, land, pts[i], pts[j], tolNm, head && i === 0, tail && j === pts.length - 1)) break
    out.push(pts[j])
    i = j
  }
  return out
}

const round = (p: readonly [number, number]): [number, number] => [Math.round(p[0] * 10000) / 10000, Math.round(p[1] * 10000) / 10000]

/** Every segment voyage.path_refusal would refuse, searched again under both rules; null when one
 *  has no way (0440). */
function mend(nav: SeaNav, land: DrawnLand, path: SeaPath, los: number): SeaPath | null {
  const out: SeaPath = [path[0]]
  const n = path.length - 1
  for (let k = 1; k <= n; k++) {
    const a = path[k - 1]
    const b = path[k]
    if (segmentIsWater(nav, a, b, k === 1 ? APPROACH_SLACK_NM : 0, k === n ? APPROACH_SLACK_NM : 0)) {
      out.push(b)
      continue
    }
    let fine: SeaPath | null = null
    for (const margin of [0.4, 1.2, 3]) {
      fine = fineSearch(nav, land, a, b, margin)
      if (fine) break
    }
    if (!fine) {
      // An ocean-long stretch is too big a box for the fine search: the raster's own search answers it,
      // and is taken only when every one of its legs is raster water with no slack at all.
      const coarse = findPath(nav, { lat: a[0], lon: a[1] }, { lat: b[0], lon: b[1] })
      if (!coarse) return null
      const legs: SeaPath = [a, ...coarse.path.slice(1, -1), b]
      for (let j = 1; j < legs.length; j++) if (!segmentIsWater(nav, legs[j - 1], legs[j], 0, 0)) return null
      for (let j = 1; j < legs.length - 1; j++) out.push(round(legs[j]))
      out.push(b)
      continue
    }
    const stretch = pull(nav, land, [a, ...fine, b], los, k === 1, k === n)
    for (let j = 1; j < stretch.length - 1; j++) out.push(round(stretch[j]))
    out.push(b)
  }
  return out
}

/** THE PIXEL EDGE (0440): a course that runs exactly along an edge of the land bitmap's pixels is
 *  read on one side of it by one rounding and on the other by another (Chios: a meridian on the
 *  west coast, 3 nm of land to the audit and none to the mask). The refiner asks both sides. */
function edgeSafe(land: DrawnLand): DrawnLand {
  const e = 1e-6
  return { blocked: (lat, lon) => land.blocked(lat, lon) || land.blocked(lat + e, lon + e) || land.blocked(lat - e, lon - e) }
}

/**
 * THE REFINER. `toleranceNm` is what the result is held to; the line of sight inside it is held to
 * half of that, so a straightened stretch never sits right at the limit.
 */
export function refineCourse(
  nav: SeaNav,
  drawn: DrawnLand,
  course: SeaPath,
  toleranceNm = LAND_TOLERANCE_NM,
): RefineResult {
  if (course.length < 2) return { path: course, changed: false, residual: [] }
  const land = edgeSafe(drawn)
  const los = toleranceNm / 2
  const last = course.length - 1
  // Distances along the course: cum[i] is the nm from the first point to vertex i.
  const cum: number[] = [0]
  for (let i = 1; i <= last; i++) cum.push(cum[i - 1] + gcNm(course[i - 1][0], course[i - 1][1], course[i][0], course[i][1]))
  const total = cum[last]
  // THE RUNS, along the whole course (0440): a run that ends on a vertex and goes on past it is ONE
  // run. A course's turning point is a raster cell centre, and the raster cannot see an island, so a
  // turn may lie on drawn land (Strangford, Oland): searched segment by segment, each half began or
  // ended in a pocket of the coast that the fine grid cannot leave, and the course was kept as it was.
  const runs: { from: number; to: number; nm: number }[] = []
  for (let i = 0; i < last; i++) {
    const segNm = cum[i + 1] - cum[i]
    for (const r of segmentLandRuns(land, course[i], course[i + 1], i)) {
      const from = cum[i] + r.f0 * segNm
      const to = cum[i] + r.f1 * segNm
      const prev = runs[runs.length - 1]
      if (prev && r.f0 === 0 && prev.to >= cum[i] - 1e-9) {
        prev.to = to
        prev.nm += r.nm
      } else runs.push({ from, to, nm: r.nm })
    }
  }
  const landRuns = runs.filter((r) => r.nm > los)
  if (!landRuns.length) return { path: course, changed: false, residual: courseLandRuns(land, course, toleranceNm) }
  // THE WINDOWS: each cluster of land (runs closer than 60 nm are one), with 20 nm of open water
  // either side, measured along the course. Only the windows are searched again and straightened;
  // the rest of the course is kept as it was, so the work follows the land, not the ocean.
  const windows: [number, number][] = []
  for (const r of landRuns) {
    const w0 = Math.max(0, r.from - 20)
    const w1 = Math.min(total, r.to + 20)
    const prev = windows[windows.length - 1]
    if (prev && w0 <= prev[1] + 20 && w1 - prev[0] <= MAX_WINDOW_NM) prev[1] = Math.max(prev[1], w1)
    else windows.push([w0, w1])
  }
  /** The point at `pos` nm along the course: a vertex itself when it falls on one. */
  const at = (pos: number): [number, number] => {
    if (pos <= 0) return course[0] as [number, number]
    if (pos >= total) return course[last] as [number, number]
    let i = 0
    while (i < last - 1 && cum[i + 1] < pos) i++
    const segNm = cum[i + 1] - cum[i]
    if (segNm <= 1e-9) return course[i] as [number, number]
    return round(pointAt(course[i], course[i + 1], (pos - cum[i]) / segNm))
  }
  const path: SeaPath = [course[0]]
  let changed = false

  let next = 1 // the first vertex not yet passed
  for (const [w0, w1] of windows) {
    const p = at(w0)
    const q = at(w1)
    let fine: SeaPath | null = null
    for (const margin of [0.4, 1.2, 3]) {
      fine = fineSearch(nav, land, p, q, margin)
      if (fine) break
    }
    if (!fine) continue
    // The course as it was, up to the window.
    while (next < last && cum[next] < w0) path.push(course[next++])
    const tail = path[path.length - 1]
    if (tail[0] !== p[0] || tail[1] !== p[1]) path.push(p)
    const stretch = pull(nav, land, [p, ...fine, q], los, w0 <= 0, w1 >= total)
    for (let k = 1; k < stretch.length - 1; k++) path.push(round(stretch[k]))
    // Every vertex inside the window is replaced by the search.
    while (next < last && cum[next] <= w1) next++
    if (w1 < total) path.push(q)
    changed = true
  }
  while (next < last) path.push(course[next++])
  path.push(course[last])
  if (!changed) return { path: course, changed: false, residual: courseLandRuns(land, course, toleranceNm) }
  // Two stretches may meet a kept vertex from either side: drop a point repeated in place. Then one
  // bounded pass of line of sight over the whole course, which also drops a kept vertex that sits on
  // the drawn land itself (a raster cell centre on an island the raster cannot see).
  const deduped = path.filter((p, k) => k === 0 || p[0] !== path[k - 1][0] || p[1] !== path[k - 1][1])
  let pulled: SeaPath | null = pull(nav, land, deduped, los, true, true)
  pulled[0] = course[0]
  pulled[pulled.length - 1] = course[course.length - 1]
  // A stretch kept from the old course and cut at a window's edge is sampled at other points than
  // the whole segment was, so it may touch a raster land cell the whole segment's samples missed
  // (0440, measured: Riga to Copenhagen by Gotland's south cape). Such a segment is searched again.
  if (!courseIsWater(nav, pulled)) pulled = mend(nav, land, pulled, los)
  // THE SERVER'S RULE IS NEVER BROKEN: a re-sailed course that voyage.path_refusal would refuse is
  // not offered. The course comes back as it came, and its land stays listed in `residual`.
  if (!pulled || !courseIsWater(nav, pulled)) {
    return { path: course, changed: false, residual: courseLandRuns(land, course, toleranceNm) }
  }
  return { path: pulled, changed: true, residual: courseLandRuns(land, pulled, toleranceNm) }
}
