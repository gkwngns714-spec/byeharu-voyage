// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DRAWN LAND, AS A QUESTION — "is this point on the land the chart draws?" (owner row 352)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-15: *"some ships go pass through land - such as hadibu ... fix this properly,
// and make procedures that this won't happen again"*.
//
// The chart, zoomed in, draws Natural Earth 1:10m land (scripts/build-fine-coast.mjs cuts it into
// the tiles under public/coast/; src/chart/fineCoastBuild.ts decodes them). The sea the game sails
// is a 0.25-degree raster (public.sea_raster) that was scan-filled from Natural Earth 1:110m, which
// has no Socotra at all. So a course could be legal water by the server's raster and still run
// straight over an island the player sees. This module reads THE SAME TILES the chart draws, so a
// course can be held to the land the player is shown, not to a coarser copy of it.
//
// The tiles are read at the finest level the chart has ('fine': 5-degree tiles, simplified to
// 0.003 degrees, islands down to 0.01 degrees), and each tile is filled once into a bitmap of
// `PX_PER_DEG` pixels a degree (0.0125 degrees, 0.75 nm), with the chart's own fill rule
// (even-odd, so a lake is water). A tile that is all land is all land; a tile with no file is sea.
//
// PURE NODE, NO DATABASE. Used by:
//   scripts/db/audit-land-crossings.mjs   the audit (every stored course, every roadstead)
//   scripts/build-coast-mask.mjs          the coast mask the course author steers by
//   tests/sea.noLandCrossing.spec.ts      the guard on every PR touching lanes, ports or coast
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
export const COAST_INDEX_FILE = path.join(ROOT, 'src', 'chart', 'fineCoast.generated.ts')
export const COAST_DIR = path.join(ROOT, 'public', 'coast')

/** Pixels a degree in the land bitmap: 0.0125 degrees, 0.75 nm north-south. */
export const PX_PER_DEG = 80

/** The tile index the chart is built with (src/chart/fineCoast.generated.ts), read as data. */
export function readCoastIndex() {
  const text = readFileSync(COAST_INDEX_FILE, 'utf8')
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  return JSON.parse(text.slice(start, end + 1))
}

/**
 * The land the chart draws at one level, as `isLand(lat, lon)`. Tiles are filled lazily, on the
 * first question that lands in them, and kept.
 */
export function drawnLand(levelName = 'fine') {
  const index = readCoastIndex()
  const level = index.levels.find((l) => l.name === levelName)
  if (!level) throw new Error(`drawn-land: no level "${levelName}" in ${COAST_INDEX_FILE}`)
  const files = new Set(level.tiles.split(' ').filter(Boolean))
  const full = new Set(level.full.split(' ').filter(Boolean))
  const size = level.tileDeg
  const cols = Math.round(360 / size)
  const rows = Math.round(180 / size)
  const side = Math.round(size * PX_PER_DEG)
  const units = Math.round(size / level.quantum)
  const scale = side / units
  /** @type {Map<string, Uint8Array | 'land' | 'sea'>} */
  const tiles = new Map()

  function fill(id) {
    const file = path.join(COAST_DIR, level.name, `${id}.json`)
    if (!existsSync(file)) throw new Error(`drawn-land: the index lists ${level.name}/${id} but ${file} is missing`)
    const json = JSON.parse(readFileSync(file, 'utf8'))
    const bitmap = new Uint8Array(side * side)
    // Every ring as pixel coordinates (x east, y south, from the tile's north-west corner).
    const rings = []
    for (const ring of json) {
      if (!Array.isArray(ring) || ring.length < 6 || ring.length % 2 !== 0) continue
      const n = ring.length / 2
      const xs = new Float64Array(n)
      const ys = new Float64Array(n)
      let x = 0
      let y = 0
      for (let i = 0; i < n; i++) {
        x += ring[2 * i]
        y += ring[2 * i + 1]
        xs[i] = x * scale
        ys[i] = y * scale
      }
      rings.push({ xs, ys, n })
    }
    const crossings = []
    for (let py = 0; py < side; py++) {
      const yc = py + 0.5
      crossings.length = 0
      for (const { xs, ys, n } of rings) {
        for (let i = 0, j = n - 1; i < n; j = i++) {
          const y1 = ys[j]
          const y2 = ys[i]
          if (y1 > yc !== y2 > yc) crossings.push(xs[j] + ((yc - y1) / (y2 - y1)) * (xs[i] - xs[j]))
        }
      }
      if (crossings.length < 2) continue
      crossings.sort((a, b) => a - b)
      for (let k = 0; k + 1 < crossings.length; k += 2) {
        const from = Math.max(0, Math.ceil(crossings[k] - 0.5))
        const to = Math.min(side - 1, Math.ceil(crossings[k + 1] - 0.5) - 1)
        for (let px = from; px <= to; px++) bitmap[py * side + px] = 1
      }
    }
    return bitmap
  }

  function tileOf(ix, iy) {
    const id = `${ix}_${iy}`
    let t = tiles.get(id)
    if (t === undefined) {
      t = files.has(id) ? fill(id) : full.has(id) ? 'land' : 'sea'
      tiles.set(id, t)
    }
    return t
  }

  /** Is this point on the land the chart draws? Longitude may be any real; it is wrapped. */
  function isLand(lat, lon) {
    if (!(lat > -90 && lat < 90)) return false
    let x = (lon + 180) % 360
    if (x < 0) x += 360
    const ix = Math.min(cols - 1, Math.floor(x / size))
    const iy = Math.min(rows - 1, Math.floor((lat + 90) / size))
    const t = tileOf(ix, iy)
    if (t === 'sea') return false
    if (t === 'land') return true
    const top = (iy + 1) * size - 90
    const px = Math.min(side - 1, Math.floor((x - ix * size) * PX_PER_DEG))
    const py = Math.min(side - 1, Math.floor((top - lat) * PX_PER_DEG))
    return t[py * side + px] === 1
  }

  return { level: level.name, tolerance: level.tolerance, isLand }
}

// ── ONE MEASURE ─────────────────────────────────────────────────────────────────────────────────

const toRad = (d) => (d * Math.PI) / 180

/** Great-circle nm, the same figure src/lib/sea's gcNm gives (for reports). */
export function gcNm(lat1, lon1, lat2, lon2) {
  const dLat = toRad(lat2 - lat1)
  const dLon = toRad(lon2 - lon1)
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2
  return 2 * 3440.065 * Math.asin(Math.min(1, Math.sqrt(a)))
}
