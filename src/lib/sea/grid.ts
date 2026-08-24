// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE NAVIGABLE SEA, AS THE CLIENT HOLDS IT — the raster the server serves, unpacked for search.
//
// §7B — the four questions, answered before this file existed:
//   CONCEPT      "which cells of the world are sailable water", as one grid in memory.
//   LIVES HERE   src/lib/sea, because it is MACHINERY with no opinion about the game — a grid,
//                a bit-unpacker and cell geometry would be equally at home in a different game.
//                The AUTHORITY for what the grid CONTAINS is the server's `public.sea_raster`
//                row (migration 0038); this module only unpacks and indexes what was served.
//   SECOND CALLER  scripts/build-sea-migration.mjs and scripts/build-proof-paths.mjs run this
//                same code under Node (type stripping), so the raster the generator packs and
//                the raster the browser unpacks cannot be two readings of one format.
//   WRONG SHAPE  if any constant here (cell size, row order, bit order) could disagree with the
//                server's copy. So there are no constants: every dimension arrives IN the served
//                payload, and the bit order is round-trip-asserted inside migration 0038 itself.
//
// THE FORMAT, stated once: each cell is a small PASSABILITY MASK of `bitsPerCell` bits, packed
// LSB-first — exactly PostgreSQL's `get_bit(bytea, n)` numbering, cell (row, col) starting at bit
// `(row * cols + col) * bitsPerCell` — so the server's verifier and this client index the same
// bit for the same cell by construction. Row 0 is the NORTH edge (lat +90), col 0 is −180.
//
// THE MASK (passability is a property of (water, ship) — coordinator's call, 2026-08-24):
//   bit 0  SEA    sailable water. The LAW gates on this bit alone today: no hull capability
//                 exists yet, so nothing else may refuse a passage (§7C — an optional guard
//                 nobody can satisfy would close the north to everyone).
//   bit 1  POLAR  the polar margin — open water poleward of the pack-ice closures (the Barents
//                 and White Sea road, Svalbard's whaling grounds, the sub-Antarctic fringe).
//                 DATA for the later systems (sea-region danger, NPC regions, ice-capable
//                 hulls), written now so the seam exists; it does not gate passage yet, and the
//                 migration that gives it a reader must say so.
//   bits 2+       reserved. A bit with no writer stays undocumented nowhere: it is added HERE,
//                 with its writer, when a system actually reads it.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { haversineNm } from '../geo/index.ts'

/** How many bits of mask each cell carries in the packed wire format. */
export const SEA_BIT = 1
export const POLAR_BIT = 2

/** The navigable-water grid, unpacked to one byte per cell. */
export interface SeaNav {
  readonly cols: number
  readonly rows: number
  readonly cellDeg: number
  /** cols × rows bytes: 1 = sailable water, 0 = not. The search reads ONLY this. */
  readonly cells: Uint8Array
  /** cols × rows bytes: the full per-cell passability mask (SEA_BIT | POLAR_BIT | …). */
  readonly marks?: Uint8Array
}

/** Cell centre latitude of a grid row (row 0 is the north edge). */
export const cellLat = (nav: Pick<SeaNav, 'cellDeg'>, row: number): number =>
  90 - (row + 0.5) * nav.cellDeg

/** Cell centre longitude of a grid column (col 0 is −180). */
export const cellLon = (nav: Pick<SeaNav, 'cellDeg'>, col: number): number =>
  -180 + (col + 0.5) * nav.cellDeg

export const rowOf = (nav: Pick<SeaNav, 'cellDeg' | 'rows'>, lat: number): number =>
  Math.min(nav.rows - 1, Math.max(0, Math.floor((90 - lat) / nav.cellDeg)))

export const colOf = (nav: Pick<SeaNav, 'cellDeg' | 'cols'>, lon: number): number =>
  ((Math.floor((lon + 180) / nav.cellDeg) % nav.cols) + nav.cols) % nav.cols

/** Is this cell sailable? Column wraps; row does not. */
export const isWater = (nav: SeaNav, row: number, col: number): boolean =>
  row >= 0 &&
  row < nav.rows &&
  nav.cells[row * nav.cols + (((col % nav.cols) + nav.cols) % nav.cols)] === 1

/** Is the cell under this coordinate sailable? */
export const isWaterAt = (nav: SeaNav, lat: number, lon: number): boolean =>
  nav.cells[rowOf(nav, lat) * nav.cols + colOf(nav, lon)] === 1

/** The one great-circle rule (src/lib/geo), adapted to the scalar shape the search loops want. */
export const gcNm = (lat1: number, lon1: number, lat2: number, lon2: number): number =>
  haversineNm({ lat: lat1, lon: lon1 }, { lat: lat2, lon: lon2 })

// ── The packed wire format ─────────────────────────────────────────────────────────────────────

/** Pack one mask byte per cell down to `bitsPerCell` bits per cell, LSB-first —
 *  `get_bit(bytea, n)` numbering, cell i's mask starting at bit i·bitsPerCell. */
export function packCells(masks: Uint8Array, bitsPerCell: number): Uint8Array {
  const totalBits = masks.length * bitsPerCell
  const packed = new Uint8Array(Math.ceil(totalBits / 8))
  for (let i = 0; i < masks.length; i++) {
    for (let b = 0; b < bitsPerCell; b++) {
      if ((masks[i] >> b) & 1) {
        const bit = i * bitsPerCell + b
        packed[bit >> 3] |= 1 << (bit & 7)
      }
    }
  }
  return packed
}

/** The inverse of {@link packCells}. `count` is cols × rows, which the packed form cannot know. */
export function unpackCells(packed: Uint8Array, count: number, bitsPerCell: number): Uint8Array {
  const masks = new Uint8Array(count)
  for (let i = 0; i < count; i++) {
    let m = 0
    for (let b = 0; b < bitsPerCell; b++) {
      const bit = i * bitsPerCell + b
      m |= ((packed[bit >> 3] >> (bit & 7)) & 1) << b
    }
    masks[i] = m
  }
  return masks
}

/** Decode base64 without assuming a DOM or Node — both provide `atob` since ES2022 runtimes. */
export function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

/** Build the searchable grid from the served `world.sea_raster()` payload. The search reads the
 *  SEA bit alone (`cells`); the full masks ride along for the systems that read the other bits. */
export function navFromServed(payload: {
  cols: number
  rows: number
  cell_deg: number
  bits_per_cell: number
  cells_base64: string
}): SeaNav {
  const packed = base64ToBytes(payload.cells_base64.replace(/\s+/g, ''))
  const count = payload.cols * payload.rows
  const marks = unpackCells(packed, count, payload.bits_per_cell)
  const cells = new Uint8Array(count)
  for (let i = 0; i < count; i++) cells[i] = marks[i] & SEA_BIT
  return {
    cols: payload.cols,
    rows: payload.rows,
    cellDeg: payload.cell_deg,
    cells,
    marks,
  }
}
