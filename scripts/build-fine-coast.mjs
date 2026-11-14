#!/usr/bin/env node
// THE FINE COAST, BUILT (2026-11-14; docs/dev-log/2026-11-14-fine-coast.md).
//
// The chart's world file (data/world-110m.json) is Natural Earth 1:110m: right for the globe, and a
// handful of straight lines at a harbour. This script cuts Natural Earth 1:10m LAND (public domain)
// into square tiles at two levels of detail, so the chart can fetch only the few tiles on the glass
// once the view is close enough to need them (src/chart/fineCoast.ts). A PICTURE ONLY: nothing the
// server rules on (water, land, routes, harbour positions) reads these files.
//
//   node scripts/build-fine-coast.mjs <dir holding ne_10m_land.geojson>
//
// The source file is NOT vendored (10 MB); the script fetches it into that directory when
// it is missing, from github.com/nvkelso/natural-earth-vector (the Natural Earth repository).
//
// WRITES
//   public/coast/<level>/<ix>_<iy>.json   one tile: the land inside it, as a list of closed rings
//       (fill-rule evenodd). Each ring is a flat list of integers: x0, y0, then dx, dy pairs, in
//       units of the level's `quantum` degrees, x east and y SOUTH from the tile's north-west
//       corner (the chart's own axes). The SHORE is not stored: it is the rings' own edges minus
//       the ones lying on the tile's border, which are the cut and never a shore (the chart
//       derives it, src/chart/fineCoastBuild.ts). The file's own cuts, the antimeridian and the
//       foot of Antarctica, are tile borders too, so they drop out by the same rule.
//   src/chart/fineCoast.generated.ts      the index: which tiles have a file, which are all land,
//       and a version (a hash of every tile) the chart puts on each fetch so a rebuilt tile is
//       never read from an old cache
//
// A tile that is all sea has no file and is not listed; a tile that is all land has no file and is
// listed under `full` (the chart paints a square).

import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const SOURCE = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/'
const FILES = ['ne_10m_land.geojson']

/**
 * THE LEVELS. `tolerance` is the simplification in degrees, `minSpan` the smallest island kept,
 * `tileDeg` the tile's side, `quantum` the degrees one stored integer is (an eighth of the
 * tolerance: it is rounding, not detail), `maxUnitsPerPx` the loosest zoom (degrees per CSS pixel) the level is
 * drawn at: the tolerance is then about one pixel at the level's loosest zoom.
 */
const LEVELS = [
  { name: 'mid', tolerance: 0.03, minSpan: 0.06, tileDeg: 20, quantum: 0.004, maxUnitsPerPx: 0.03 },
  { name: 'fine', tolerance: 0.003, minSpan: 0.01, tileDeg: 5, quantum: 0.0005, maxUnitsPerPx: 0.006 },
]

async function source(dir, file) {
  const at = path.join(dir, file)
  if (!existsSync(at)) {
    const response = await fetch(SOURCE + file)
    if (!response.ok) throw new Error(`${file}: ${response.status}`)
    writeFileSync(at, Buffer.from(await response.arrayBuffer()))
  }
  return JSON.parse(readFileSync(at, 'utf8'))
}

/** Every linear ring of a FeatureCollection, as [lon, lat] lists without the closing repeat. */
function ringsOf(json) {
  const out = []
  for (const feature of json.features) {
    const g = feature.geometry
    if (!g) continue
    const polygons = g.type === 'Polygon' ? [g.coordinates] : g.type === 'MultiPolygon' ? g.coordinates : []
    for (const polygon of polygons) {
      for (const ring of polygon) {
        const pts = ring.map((p) => [p[0], p[1]])
        const a = pts[0]
        const z = pts[pts.length - 1]
        if (pts.length > 1 && a[0] === z[0] && a[1] === z[1]) pts.pop()
        if (pts.length >= 3) out.push(pts)
      }
    }
  }
  return out
}

/** Ramer-Douglas-Peucker on an open list; the first and last points are kept. */
function simplify(points, tolerance) {
  const n = points.length
  if (n < 3) return points.slice()
  const tol2 = tolerance * tolerance
  const keep = new Uint8Array(n)
  keep[0] = keep[n - 1] = 1
  const stack = [0, n - 1]
  while (stack.length) {
    const end = stack.pop()
    const start = stack.pop()
    const [ax, ay] = points[start]
    const [bx, by] = points[end]
    const dx = bx - ax
    const dy = by - ay
    const len2 = dx * dx + dy * dy
    let worst = 0
    let at = -1
    for (let i = start + 1; i < end; i++) {
      const [px, py] = points[i]
      const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2))
      const d2 = (px - ax - t * dx) ** 2 + (py - ay - t * dy) ** 2
      if (d2 > worst) {
        worst = d2
        at = i
      }
    }
    if (worst > tol2 && at > 0) {
      keep[at] = 1
      stack.push(start, at, at, end)
    }
  }
  return points.filter((_, i) => keep[i] === 1)
}

/** A closed ring simplified: cut at its two far ends so no vertex is pinned by where the file began. */
function simplifyRing(ring, tolerance) {
  let west = 0
  let east = 0
  for (let i = 1; i < ring.length; i++) {
    if (ring[i][0] < ring[west][0]) west = i
    if (ring[i][0] > ring[east][0]) east = i
  }
  if (west === east) return []
  const turned = [...ring.slice(west), ...ring.slice(0, west)]
  const cut = (east - west + ring.length) % ring.length
  const first = simplify(turned.slice(0, cut + 1), tolerance)
  const second = simplify([...turned.slice(cut), turned[0]], tolerance)
  return [...first, ...second.slice(1, -1)]
}

/** Sutherland-Hodgman against one half-plane: keep the side where `coord(axis) * sign <= limit * sign`. */
function clipHalf(ring, axis, limit, sign) {
  const out = []
  const n = ring.length
  for (let i = 0; i < n; i++) {
    const a = ring[i]
    const b = ring[(i + 1) % n]
    const ain = a[axis] * sign <= limit * sign
    const bin = b[axis] * sign <= limit * sign
    if (ain) out.push(a)
    if (ain !== bin) {
      const t = (limit - a[axis]) / (b[axis] - a[axis])
      const p = [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])]
      p[axis] = limit
      out.push(p)
    }
  }
  return out
}

/** Twice the signed area of a ring. */
function area2(ring) {
  let s = 0
  for (let i = 0, n = ring.length; i < n; i++) {
    const a = ring[i]
    const b = ring[(i + 1) % n]
    s += a[0] * b[1] - b[0] * a[1]
  }
  return s
}

const hash = createHash('sha256')

function buildLevel(level, sourceRings) {
  const { tolerance, minSpan, tileDeg, quantum: QUANTUM } = level
  const tiles = new Map()
  const tile = (ix, iy) => {
    const id = `${ix}_${iy}`
    let t = tiles.get(id)
    if (!t) tiles.set(id, (t = { ix, iy, body: [] }))
    return t
  }
  const cols = 360 / tileDeg
  const rows = 180 / tileDeg
  let points = 0
  let rings = 0

  for (const raw of sourceRings) {
    let minX = Infinity
    let maxX = -Infinity
    let minY = Infinity
    let maxY = -Infinity
    for (const [x, y] of raw) {
      if (x < minX) minX = x
      if (x > maxX) maxX = x
      if (y < minY) minY = y
      if (y > maxY) maxY = y
    }
    if (maxX - minX < minSpan && maxY - minY < minSpan) continue
    const ring = simplifyRing(raw, tolerance)
    if (ring.length < 3) continue
    rings++
    points += ring.length

    const cx0 = Math.max(0, Math.floor((minX + 180) / tileDeg))
    const cx1 = Math.min(cols - 1, Math.floor((maxX + 180) / tileDeg))
    const cy0 = Math.max(0, Math.floor((minY + 90) / tileDeg))
    const cy1 = Math.min(rows - 1, Math.floor((maxY + 90) / tileDeg))

    // THE BODY: the ring cut to each column, then to each tile of the column.
    for (let ix = cx0; ix <= cx1; ix++) {
      const x0 = -180 + ix * tileDeg
      const strip = clipHalf(clipHalf(ring, 0, x0, -1), 0, x0 + tileDeg, 1)
      if (strip.length < 3) continue
      for (let iy = cy0; iy <= cy1; iy++) {
        const y0 = -90 + iy * tileDeg
        const piece = clipHalf(clipHalf(strip, 1, y0, -1), 1, y0 + tileDeg, 1)
        if (piece.length >= 3 && Math.abs(area2(piece)) > 1e-12) tile(ix, iy).body.push(piece)
      }
    }

  }

  // WRITE. A tile whose body is the whole square, with no shore inside it, is `full`.
  const dir = path.join(ROOT, 'public', 'coast', level.name)
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
  const have = []
  const full = []
  let bytes = 0
  let largest = 0
  for (const t of tiles.values()) {
    const west = -180 + t.ix * tileDeg
    const north = -90 + (t.iy + 1) * tileDeg
    const q = (p) => [Math.round((p[0] - west) / QUANTUM), Math.round((north - p[1]) / QUANTUM)]
    const flat = (pts) => {
      const out = []
      let px = 0
      let py = 0
      for (const p of pts) {
        const [x, y] = q(p)
        if (out.length > 0 && x === px && y === py) continue
        out.push(x - px, y - py)
        px = x
        py = y
      }
      return out
    }
    const body = t.body.map(flat).filter((r) => r.length >= 6)
    if (body.length === 0) continue
    const onBorder = (p) => p[0] === west || p[0] === west + tileDeg || p[1] === north || p[1] === north - tileDeg
    if (t.body.length === 1 && t.body[0].every(onBorder) && Math.abs(Math.abs(area2(t.body[0])) / 2 - tileDeg * tileDeg) < 1e-9) {
      full.push(`${t.ix}_${t.iy}`)
      continue
    }
    const text = JSON.stringify(body)
    writeFileSync(path.join(dir, `${t.ix}_${t.iy}.json`), text)
    have.push(`${t.ix}_${t.iy}`)
    hash.update(`${level.name}/${t.ix}_${t.iy}:${text}`)
    bytes += text.length
    if (text.length > largest) largest = text.length
  }
  console.log(
    `${level.name}: ${rings} rings, ${points} points, ${have.length} tile files (${full.length} all land), ${bytes} bytes, largest ${largest}`,
  )
  return {
    name: level.name,
    tolerance,
    tileDeg,
    quantum: QUANTUM,
    maxUnitsPerPx: level.maxUnitsPerPx,
    tiles: have.sort().join(' '),
    full: full.sort().join(' '),
  }
}

const dir = process.argv[2]
if (!dir) throw new Error('usage: node scripts/build-fine-coast.mjs <source dir>')
mkdirSync(dir, { recursive: true })
const sourceRings = []
for (const file of FILES) sourceRings.push(...ringsOf(await source(dir, file)))
const levels = LEVELS.map((level) => buildLevel(level, sourceRings))
const body = JSON.stringify({ version: hash.digest('hex').slice(0, 10), levels }, null, 2)
writeFileSync(
  path.join(ROOT, 'src', 'chart', 'fineCoast.generated.ts'),
  `// GENERATED by scripts/build-fine-coast.mjs from Natural Earth 1:10m land (public domain).
// Do not edit: run the script. The tiles themselves are public/coast/<level>/<ix>_<iy>.json.
export const FINE_COAST_INDEX = ${body} as const
`,
)
