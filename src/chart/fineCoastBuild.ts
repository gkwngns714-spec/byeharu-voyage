// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FINE COAST, AS GEOMETRY (2026-11-14; docs/dev-log/2026-11-14-fine-coast.md)
//
// The owner: *"fix the graphics overall, especially map. it is weird"*. Zoomed into a harbour the
// coast was a handful of straight lines many kilometres long, because the world file is Natural
// Earth 1:110m simplified to 0.2 degrees (./coastlineBuild.ts): right for the globe, 52 pixels of
// error on a phone at the closest zoom and 170 on a desktop.
//
// So close in, the chart draws Natural Earth 1:10m land instead, cut into square TILES at two
// levels (scripts/build-fine-coast.mjs writes them to public/coast/). Only the tiles under the
// coast's sheet are fetched, and only once the view is close enough to need them, so the first
// load and every wide view cost exactly what they did.
//
// A PICTURE ONLY. Nothing here is asked where water is: the routes, the server's land rule and
// every harbour's position are untouched, and the wide chart, the minimap and the landfall
// (./landfall.ts) still read the 110m file.
//
// This module is PURE (numbers in, strings out), so a spec can run it over the shipped tiles in
// plain Node; ./useFineCoast.ts owns the network.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { CHART_WIDTH, type Point, type ViewBox } from '../lib/geo'
import { LANDFALL_CAP_NM, type ShoreInHand } from './landfall'

/** One level of detail, as the generated index states it (./fineCoast.generated.ts). */
export interface FineLevel {
  readonly name: string
  /** How far the level's simplification may move the shore, in degrees. */
  readonly tolerance: number
  /** A tile's side, in degrees. */
  readonly tileDeg: number
  /** Degrees per stored integer. */
  readonly quantum: number
  /** The loosest zoom this level is drawn at, in chart units (degrees) per CSS pixel. */
  readonly maxUnitsPerPx: number
  /** Tiles that have a file, as "ix_iy" separated by spaces. */
  readonly tiles: string
  /** Tiles that are all land (no file: a square). */
  readonly full: string
}

/** What a tile is, without fetching it. */
export type TileKind = 'file' | 'land' | 'sea'

/** A level with its two lists as sets. */
export interface FineLevelIndex extends FineLevel {
  readonly kindOf: (id: string) => TileKind
}

export function indexLevel(level: FineLevel): FineLevelIndex {
  const files = new Set(level.tiles.split(' ').filter(Boolean))
  const full = new Set(level.full.split(' ').filter(Boolean))
  return { ...level, kindOf: (id) => (files.has(id) ? 'file' : full.has(id) ? 'land' : 'sea') }
}

/**
 * WHICH LEVEL A ZOOM IS DRAWN AT: the finest one whose own limit the zoom is inside, or null, which
 * is the 110m world file. Keyed on degrees per PIXEL and not on the span: what makes a coast blocky
 * is how many pixels its error covers, and a desktop shows that error three times the size a phone
 * does at the same span.
 */
export function fineLevelFor<L extends FineLevel>(levels: readonly L[], unitsPerPx: number): L | null {
  let best: L | null = null
  for (const level of levels) {
    if (unitsPerPx > 0 && unitsPerPx <= level.maxUnitsPerPx && (!best || level.maxUnitsPerPx < best.maxUnitsPerPx)) best = level
  }
  return best
}

/**
 * THE TILES UNDER A BOX, every one (sea and all-land tiles too, so "is this box covered" is a
 * question about ids alone). The box is in chart units and may run past the antimeridian: a tile
 * is named on the base world, whichever copy of the sheet the box met it on.
 */
export function tilesOver(level: FineLevel, box: ViewBox): string[] {
  const size = level.tileDeg
  const cols = Math.round(CHART_WIDTH / size)
  const rows = Math.round(180 / size)
  // rows are counted from the SOUTH (latitude -90 is row 0); chart y is minus the latitude.
  const y0 = Math.max(0, Math.min(rows - 1, Math.floor((90 - (box.y + box.height)) / size)))
  const y1 = Math.max(0, Math.min(rows - 1, Math.ceil((90 - box.y) / size) - 1))
  const x0 = Math.floor((box.x + 180) / size)
  const x1 = Math.max(x0, Math.ceil((box.x + box.width + 180) / size) - 1)
  const out: string[] = []
  const seen = new Set<number>()
  for (let x = x0; x <= x1 && seen.size < cols; x++) {
    const ix = ((x % cols) + cols) % cols
    if (seen.has(ix)) continue
    seen.add(ix)
    for (let iy = y0; iy <= y1; iy++) out.push(`${ix}_${iy}`)
  }
  return out
}

/** The two strings a coast is drawn from: THE BODY and THE LINE (./CoastlineLayer.tsx). */
export interface CoastPaths {
  readonly d: string
  readonly coastD: string
}

/** One tile, decoded: the two strings, and THE SAME RINGS as points, which is what the landfall
 *  reads (./landfall.ts): a harbour is set on exactly the shore the strings draw. */
export interface TilePaths extends CoastPaths {
  readonly rings: readonly (readonly Point[])[]
}

const EMPTY: TilePaths = { d: '', coastD: '', rings: [] }

function origin(level: FineLevel, id: string): { west: number; top: number } {
  const [ix, iy] = id.split('_').map(Number)
  return { west: -180 + ix * level.tileDeg, top: 90 - (iy + 1) * level.tileDeg }
}

/** A tile with no file: the whole square for land, nothing for sea. Neither has a shore inside. */
export function plainTilePaths(level: FineLevel, id: string, kind: 'land' | 'sea'): TilePaths {
  if (kind === 'sea') return EMPTY
  const { west, top } = origin(level, id)
  const s = level.tileDeg
  return {
    d: `M${west} ${top}L${west + s} ${top}L${west + s} ${top + s}L${west} ${top + s}Z`,
    coastD: '',
    rings: [[{ x: west, y: top }, { x: west + s, y: top }, { x: west + s, y: top + s }, { x: west, y: top + s }]],
  }
}

/**
 * ONE TILE'S FILE, AS THE TWO STRINGS. The file is the land inside the tile as closed rings, each a
 * flat list of integers (x0, y0, then dx, dy pairs) from the tile's north-west corner. THE BODY is
 * every ring closed. THE LINE is the same rings with every edge that lies on the tile's border left
 * out: such an edge is where the tile was cut (or the file's own cut at the antimeridian), never a
 * shore, and stroked it would rule a square round every tile. Anything malformed is skipped, never
 * thrown: a bad tile may not take the chart down.
 */
export function tilePaths(level: FineLevel, id: string, json: unknown): TilePaths {
  if (!Array.isArray(json)) return EMPTY
  const { west, top } = origin(level, id)
  const q = level.quantum
  const side = Math.round(level.tileDeg / q)
  const digits = Math.max(0, Math.ceil(-Math.log10(q)))
  const nx = (v: number) => +(west + v * q).toFixed(digits)
  const ny = (v: number) => +(top + v * q).toFixed(digits)
  const sx = (v: number) => String(nx(v))
  const sy = (v: number) => String(ny(v))
  const rings: Point[][] = []
  let d = ''
  let coastD = ''
  for (const ring of json as unknown[]) {
    if (!Array.isArray(ring) || ring.length < 6 || ring.length % 2 !== 0) continue
    const n = ring.length / 2
    const xs = new Array<number>(n)
    const ys = new Array<number>(n)
    let x = 0
    let y = 0
    let ok = true
    for (let i = 0; i < n; i++) {
      const dx: unknown = ring[2 * i]
      const dy: unknown = ring[2 * i + 1]
      if (typeof dx !== 'number' || typeof dy !== 'number') {
        ok = false
        break
      }
      x += dx
      y += dy
      xs[i] = x
      ys[i] = y
    }
    if (!ok) continue
    rings.push(xs.map((v, i) => ({ x: nx(v), y: ny(ys[i]) })))
    const at = (i: number) => `${sx(xs[i])} ${sy(ys[i])}`

    d += `M${at(0)}`
    for (let i = 1; i < n; i++) d += `L${at(i)}`
    d += 'Z'

    // An edge i → i+1 is the tile's cut when both its ends are on the same side of the square.
    const cut = (i: number) => {
      const j = (i + 1) % n
      return (
        (xs[i] === 0 && xs[j] === 0) ||
        (xs[i] === side && xs[j] === side) ||
        (ys[i] === 0 && ys[j] === 0) ||
        (ys[i] === side && ys[j] === side)
      )
    }
    let start = -1
    for (let i = 0; i < n; i++) {
      if (cut(i)) {
        start = (i + 1) % n
        break
      }
    }
    if (start === -1) {
      // no cut at all: an island (or a lake) whole inside the tile, one closed run
      coastD += `M${at(0)}`
      for (let i = 1; i < n; i++) coastD += `L${at(i)}`
      coastD += 'Z'
      continue
    }
    let open = false
    for (let k = 0; k < n; k++) {
      const i = (start + k) % n
      if (cut(i)) {
        open = false
        continue
      }
      if (!open) {
        coastD += `M${at(i)}`
        open = true
      }
      coastD += `L${at((i + 1) % n)}`
    }
  }
  return { d, coastD, rings }
}

/**
 * THE COAST IN HAND, FOR THE LANDFALL (./landfall.ts `ShoreInHand`): the held tiles of one level as
 * the shore a harbour's mark is set on. A harbour is held when its own tile is; its landfall reads
 * the rings of every held tile within the cap of it, so a shore just across a tile's border is
 * found. A tile's own border is a cut, never landed on, and a harbour inland within the cap is
 * brought to the shore (`fromLand`): this coast is real enough to have the quay.
 */
export function shoreOfTiles(
  level: FineLevel,
  ids: ReadonlySet<string>,
  ringsOf: (id: string) => readonly (readonly Point[])[] | undefined,
): ShoreInHand {
  const size = level.tileDeg
  const onGrid = (v: number) => Math.abs(v / size - Math.round(v / size)) < 1e-9
  const capLat = LANDFALL_CAP_NM / 60
  return {
    fromLand: true,
    isCut: (a, b) => (a.x === b.x && onGrid(a.x)) || (a.y === b.y && onGrid(a.y)),
    ringsNear: (p) => {
      const own = tilesOver(level, { x: p.x, y: p.y, width: 0, height: 0 })[0]
      if (own === undefined || !ids.has(own)) return null
      const capLon = capLat / Math.max(0.2, Math.cos((p.y * Math.PI) / 180))
      const out: (readonly Point[])[] = []
      for (const id of tilesOver(level, { x: p.x - capLon, y: p.y - capLat, width: 2 * capLon, height: 2 * capLat })) {
        if (!ids.has(id)) continue
        const rings = ringsOf(id)
        if (rings) for (const ring of rings) out.push(ring)
      }
      return out
    },
  }
}

/** Is every tile a box needs among these ids? */
export function tilesCover(level: FineLevel, ids: ReadonlySet<string>, box: ViewBox): boolean {
  return tilesOver(level, box).every((id) => ids.has(id))
}
