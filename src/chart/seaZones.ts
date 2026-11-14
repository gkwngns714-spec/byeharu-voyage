// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SEA ZONES ON THE CHART — the Seas filter's picture (owner, 2026-11-15: *"also in map, make
// filter, like regions, no in regions, have option to see seas, showing waves, requirement to pass
// etc."*). PURE: no React, no store.
//
// WHAT IS DRAWN, AND WHAT IS NOT. The zones are the server's raster (`world.sea_zone_map`, 0396:
// one byte a 0.25° cell). On 2026-11-14 a fill of that raster on the water read as *"square, not in
// sync"* (#668/#669/#672), so nothing here fills a cell. Two things are drawn instead:
//   · THE BORDERS between two zones — only where water of one zone meets water of another (a zone
//     against land is the coast, already drawn). Traced along the cells' edges, then set through
//     the edges' MIDPOINTS (a stair of cells becomes its diagonal), thinned, and rounded twice
//     (Chaikin), so a border reads as a line on the water, not as the cells it came from. A border
//     cut on a parallel or a meridian (most of them: a zone is a raster sea cut by boxes) stays
//     exactly straight. One path for the world, built once per raster: a pan moves it, it never
//     re-derives it, and it is the same line at every zoom.
//   · EACH ZONE'S NAME with what it asks, as a request to the ONE label planner (./labels.ts), at
//     the zone's deepest water: the cell furthest from any other zone or the shore (a chamfer
//     distance over the raster), so the name sits in the middle of its own sea and not on a cape.
// Every figure on a name is served (what the zone asks, open or closed for the fleet in hand): the
// screen hands the words in, this file only places them.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { project, type LatLon, type ViewBox } from '../lib/geo'
import type { ZoneCells } from '../domain/seas'
import { GLYPH } from './glyphs'
import { LABEL_PRIORITY, type LabelRequest } from './labels'

/** One zone's name on the chart, as the screen words it from the served read. */
export interface ZoneLabel {
  readonly code: string
  /** The zone's name (full, never cut). */
  readonly name: string
  /** What it asks, or what it lacks for the fleet in hand, in one or two words ("Title 3 · Waves 6"). */
  readonly note: string
  /** The server's verdict: closed to the fleet in hand (only while the conditions bite). */
  readonly closed: boolean
  /** Where the name may stand, deepest water first (`zoneAnchors`): it is set at the first one on the glass. */
  readonly at: readonly LatLon[]
  /** The zone the player pressed: always named. */
  readonly selected?: boolean
}

/** What the Seas filter hands the chart: the borders (one path) and the names. */
export interface ZonesOnChart {
  readonly outline: string
  readonly labels: readonly ZoneLabel[]
}

const isZone = (z: ZoneCells, v: number) => v !== 0 && (z.codes[v] ?? null) !== null

/** A zone's name has a place in each block this many degrees square that holds deep enough water of
 *  it, so a zone whose deepest water is off the glass is still named on the part that is on it. */
const ANCHOR_BLOCK_DEG = 1.5

/**
 * THE DEEPEST WATER OF EACH ZONE — per block of ANCHOR_BLOCK_DEG, the cell furthest (chamfer 3-4)
 * from a cell of another value (at least about 1° in, but the zone's deepest always counts), by zone
 * code, deepest first. The name is set at the deepest of them on the glass. A cell on the chart's east or west edge is not counted as a border (the sheet
 * wraps), the north and south edges are.
 */
export function zoneAnchors(z: ZoneCells): Map<string, LatLon[]> {
  const { cols, rows, cells } = z
  const n = cols * rows
  const INF = 65000
  const d = new Uint16Array(n)
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const i = r * cols + c
      const v = cells[i]
      const edge =
        !isZone(z, v) ||
        r === 0 ||
        r === rows - 1 ||
        cells[i - cols] !== v ||
        cells[i + cols] !== v ||
        (c > 0 && cells[i - 1] !== v) ||
        (c < cols - 1 && cells[i + 1] !== v)
      d[i] = edge ? 0 : INF
    }
  }
  const relax = (i: number, j: number, w: number) => {
    const via = d[j] + w
    if (via < d[i]) d[i] = via
  }
  for (let r = 1; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const i = r * cols + c
      if (d[i] === 0) continue
      if (c > 0) relax(i, i - 1, 3)
      relax(i, i - cols, 3)
      if (c > 0) relax(i, i - cols - 1, 4)
      if (c < cols - 1) relax(i, i - cols + 1, 4)
    }
  }
  for (let r = rows - 2; r >= 0; r--) {
    for (let c = cols - 1; c >= 0; c--) {
      const i = r * cols + c
      if (d[i] === 0) continue
      if (c < cols - 1) relax(i, i + 1, 3)
      relax(i, i + cols, 3)
      if (c < cols - 1) relax(i, i + cols + 1, 4)
      if (c > 0) relax(i, i + cols - 1, 4)
    }
  }
  // the deepest cell of each zone in each block of the chart: the zone's places for its name, deepest first
  const block = Math.max(1, Math.round(ANCHOR_BLOCK_DEG / z.cellDeg))
  const bcols = Math.ceil(cols / block)
  const best = new Map<number, Map<number, { i: number; d: number }>>()
  for (let i = 0; i < n; i++) {
    const v = cells[i]
    if (!isZone(z, v)) continue
    const key = Math.floor(Math.floor(i / cols) / block) * bcols + Math.floor((i % cols) / block)
    let byBlock = best.get(v)
    if (!byBlock) best.set(v, (byBlock = new Map()))
    const b = byBlock.get(key)
    if (!b || d[i] > b.d) byBlock.set(key, { i, d: d[i] })
  }
  const minDepth = 3 * Math.max(1, Math.round(1 / z.cellDeg))
  const out = new Map<string, LatLon[]>()
  for (const [v, byBlock] of best) {
    const all = [...byBlock.values()].sort((a, b) => b.d - a.d || a.i - b.i)
    const kept = all.filter((b, k) => k === 0 || b.d >= minDepth)
    out.set(
      z.codes[v]!,
      kept.map((b) => ({ lat: 90 - (Math.floor(b.i / cols) + 0.5) * z.cellDeg, lon: -180 + ((b.i % cols) + 0.5) * z.cellDeg })),
    )
  }
  return out
}

type Pt = readonly [number, number]

/** Douglas-Peucker, iterative: the points a polyline keeps within `eps` of itself. */
function thin(pts: Pt[], eps: number): Pt[] {
  if (pts.length < 3) return pts
  const keep = new Uint8Array(pts.length)
  keep[0] = 1
  keep[pts.length - 1] = 1
  const stack: Array<[number, number]> = [[0, pts.length - 1]]
  while (stack.length > 0) {
    const [a, b] = stack.pop()!
    const [ax, ay] = pts[a]
    const [bx, by] = pts[b]
    const dx = bx - ax
    const dy = by - ay
    const len = Math.hypot(dx, dy)
    let far = -1
    let farD = eps
    for (let i = a + 1; i < b; i++) {
      const [px, py] = pts[i]
      const dist = len === 0 ? Math.hypot(px - ax, py - ay) : Math.abs(dy * (px - ax) - dx * (py - ay)) / len
      if (dist > farD) {
        farD = dist
        far = i
      }
    }
    if (far > 0) {
      keep[far] = 1
      stack.push([a, far], [far, b])
    }
  }
  return pts.filter((_, i) => keep[i] === 1)
}

/** Chaikin's corner cutting, once; the ends of an open line stay where they are. */
function round(pts: Pt[], closed: boolean): Pt[] {
  if (pts.length < 3) return pts
  const out: Pt[] = closed ? [] : [pts[0]]
  const last = closed ? pts.length : pts.length - 1
  for (let i = 0; i < last; i++) {
    const [ax, ay] = pts[i]
    const [bx, by] = pts[(i + 1) % pts.length]
    out.push([0.75 * ax + 0.25 * bx, 0.75 * ay + 0.25 * by], [0.25 * ax + 0.75 * bx, 0.25 * ay + 0.75 * by])
  }
  if (!closed) out.push(pts[pts.length - 1])
  return out
}

/**
 * THE BORDERS BETWEEN ZONES, as one SVG path in chart units (x = lon, y = -lat; ../lib/geo
 * `project`), for the base copy of the sheet.
 */
export function zoneOutline(z: ZoneCells): string {
  const { cols, rows, cells, cellDeg } = z
  const W = cols + 1
  const NV = W * (rows + 1)
  const adj = new Map<number, number[]>()
  const link = (a: number, b: number) => {
    const la = adj.get(a)
    if (la) la.push(b)
    else adj.set(a, [b])
    const lb = adj.get(b)
    if (lb) lb.push(a)
    else adj.set(b, [a])
  }
  const border = (a: number, b: number) => a !== b && isZone(z, a) && isZone(z, b)
  for (let r = 0; r < rows; r++) {
    for (let c = 1; c < cols; c++) {
      if (border(cells[r * cols + c - 1], cells[r * cols + c])) link(r * W + c, (r + 1) * W + c)
    }
  }
  for (let r = 1; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      if (border(cells[(r - 1) * cols + c], cells[r * cols + c])) link(r * W + c, r * W + c + 1)
    }
  }
  const used = new Set<number>()
  const key = (a: number, b: number) => (a < b ? a * NV + b : b * NV + a)
  const lines: number[][] = []
  const walk = (start: number, next: number) => {
    const line = [start, next]
    used.add(key(start, next))
    let cur = next
    while ((adj.get(cur)?.length ?? 0) === 2 && cur !== start) {
      const step = adj.get(cur)!.find((m) => !used.has(key(cur, m)))
      if (step === undefined) break
      used.add(key(cur, step))
      line.push(step)
      cur = step
    }
    lines.push(line)
  }
  // open lines first (from every end and junction), then whatever is left is a ring
  for (const [v, ns] of adj) if (ns.length !== 2) for (const m of ns) if (!used.has(key(v, m))) walk(v, m)
  for (const [v, ns] of adj) for (const m of ns) if (!used.has(key(v, m))) walk(v, m)

  const at = (v: number): Pt => [-180 + (v % W) * cellDeg, Math.floor(v / W) * cellDeg - 90]
  let d = ''
  for (const line of lines) {
    const closed = line.length > 3 && line[0] === line[line.length - 1]
    const corners = line.map(at)
    // through the edges' midpoints: a stair of cells becomes its diagonal; a straight cut stays straight
    const mids: Pt[] = []
    for (let i = 0; i + 1 < corners.length; i++) mids.push([(corners[i][0] + corners[i + 1][0]) / 2, (corners[i][1] + corners[i + 1][1]) / 2])
    let pts: Pt[] = closed ? mids : [corners[0], ...mids, corners[corners.length - 1]]
    pts = thin(pts, cellDeg * 0.35)
    pts = round(round(pts, closed), closed)
    if (pts.length < 2) continue
    d += `M${pts[0][0].toFixed(3)} ${pts[0][1].toFixed(3)}`
    for (let i = 1; i < pts.length; i++) d += `L${pts[i][0].toFixed(3)} ${pts[i][1].toFixed(3)}`
    if (closed) d += 'Z'
  }
  return d
}

/**
 * The zones' names this window asks for: each centred on its deepest water with three lines of
 * give, its ask on a second, smaller line. ABOVE every quiet harbour's name (the filter was turned
 * on to read the seas) and below every port of yours, as a region's name is; the pressed zone is
 * forced.
 */
export function zoneNameRequests(labels: readonly ZoneLabel[], view: ViewBox): LabelRequest[] {
  const out: LabelRequest[] = []
  // a name's box reaches half its width each side of its place: a place this far inside the glass is one it can stand on
  const padX = view.width * 0.08
  const padY = view.height * 0.04
  for (const zone of labels) {
    const inside = (p: { x: number; y: number }) =>
      p.x >= view.x + padX && p.x <= view.x + view.width - padX && p.y >= view.y + padY && p.y <= view.y + view.height - padY
    const at = zone.at.map(project).find(inside)
    if (!at) continue
    out.push({
      id: `zone:${zone.code}`,
      text: zone.name,
      note: zone.note,
      noteSizePx: GLYPH.zoneNoteSize,
      at,
      priority: zone.selected ? LABEL_PRIORITY.selected : LABEL_PRIORITY.region,
      force: zone.selected,
      tone: zone.closed ? 'zone-closed' : 'zone',
      placement: 'centred',
      slackLines: 3,
      sizePx: GLYPH.zoneNameSize,
    })
  }
  return out
}

const SHAPES = new WeakMap<ZoneCells, { outline: string; anchors: Map<string, LatLon[]> }>()

/** The borders and the anchors of one raster, worked out once per raster (the read is kept for the session). */
export function zoneShapes(z: ZoneCells): { outline: string; anchors: Map<string, LatLon[]> } {
  let shape = SHAPES.get(z)
  if (!shape) {
    shape = { outline: zoneOutline(z), anchors: zoneAnchors(z) }
    SHAPES.set(z, shape)
  }
  return shape
}
