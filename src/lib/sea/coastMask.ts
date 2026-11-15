// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COAST MASK — the land the chart draws, where the raster cannot see it (owner row 352)
//
// The sea raster (public.sea_raster) is 0.25 degrees a cell, scan-filled from Natural Earth 1:110m.
// The chart draws Natural Earth 1:10m. Where the two disagree, a raster WATER cell holds land the
// player sees: all of Socotra, Bangka, the Gallipoli peninsula, every cape a straight course clips.
// This mask lists exactly those cells, each cut into SUB x SUB sub-cells (SUB = 20: 0.0125 degrees,
// 0.75 nm, the land bitmap's own pixel, scripts/lib/drawn-land.mjs PX_PER_DEG), one bit a sub-cell: 1 = the
// chart draws land there. A water cell that is not listed holds no drawn land. A cell the game
// opened ON PURPOSE (a carved channel: land in 1:110m, water in the raster, the Thames or the
// Bosphorus) is never listed, so a river the game sails is never "land" here.
//
// WHO MAKES IT: scripts/build-coast-mask.mjs, from the chart's own tiles (public/coast/fine) and
// the raster the chain serves. It is written to public/coast/mask.json and stamped with the
// raster it was cut for; tests/sea.noLandCrossing.spec.ts fails when the two drift apart.
// WHO READS IT: the course author (src/domain/passage proposeCourse, through ./refine.ts) in the
// browser, and the generator that re-sails every stored lane (scripts/build-clear-courses.mjs).
// One mask, so a player's course and a merchant's lane are held off the same land.
//
// A PICTURE'S ANSWER, NOT THE LAW. The server's law is still the raster (voyage.path_refusal);
// everything ./refine.ts returns is raster water by that law. The mask only steers the course off
// land the raster is too coarse to know about.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { base64ToBytes, type SeaNav } from './grid.ts'
import type { DrawnLand } from './refine.ts'

/** Sub-cells a side of one raster cell. */
export const COAST_MASK_SUB = 20

/** The file as served (public/coast/mask.json). */
export interface CoastMaskPayload {
  /** Sub-cells a side; must equal COAST_MASK_SUB. */
  readonly sub: number
  /** The raster it was cut for: cols, rows, cell_deg, and an md5 of the served cells. */
  readonly raster: { readonly cols: number; readonly rows: number; readonly cellDeg: number; readonly md5: string }
  /** The listed cells, ascending, as little-endian uint32 raster indices, base64. */
  readonly cells: string
  /** SUB*SUB bits a listed cell, row-major from the north-west sub-cell, LSB first, base64. */
  readonly bits: string
}

export interface CoastMask {
  readonly cols: number
  readonly rows: number
  readonly cellDeg: number
  readonly sub: number
  /** Raster index → offset of its bits in `bits`, in bytes. */
  readonly at: Map<number, number>
  readonly bits: Uint8Array
  readonly bytesPerCell: number
}

/** Decode the served payload. Throws on a shape it does not know (a stale or foreign file). */
export function coastMaskFrom(payload: CoastMaskPayload): CoastMask {
  if (payload.sub !== COAST_MASK_SUB) throw new Error(`coast mask: sub ${payload.sub}, expected ${COAST_MASK_SUB}`)
  const idxBytes = base64ToBytes(payload.cells)
  const bits = base64ToBytes(payload.bits)
  const bytesPerCell = Math.ceil((payload.sub * payload.sub) / 8)
  const n = idxBytes.length / 4
  if (!Number.isInteger(n) || bits.length !== n * bytesPerCell) throw new Error('coast mask: cells and bits disagree')
  const view = new DataView(idxBytes.buffer, idxBytes.byteOffset, idxBytes.byteLength)
  const at = new Map<number, number>()
  for (let i = 0; i < n; i++) at.set(view.getUint32(i * 4, true), i * bytesPerCell)
  return { cols: payload.raster.cols, rows: payload.raster.rows, cellDeg: payload.raster.cellDeg, sub: payload.sub, at, bits, bytesPerCell }
}

/** Is this point on land the chart draws, as the mask holds it? */
export function maskBlocked(mask: CoastMask, lat: number, lon: number): boolean {
  const fr = (90 - lat) / mask.cellDeg
  const row = Math.floor(fr)
  if (row < 0 || row >= mask.rows) return false
  let fc = (lon + 180) / mask.cellDeg
  fc = ((fc % mask.cols) + mask.cols) % mask.cols
  const col = Math.floor(fc)
  const off = mask.at.get(row * mask.cols + col)
  if (off === undefined) return false
  const sr = Math.min(mask.sub - 1, Math.floor((fr - row) * mask.sub))
  const sc = Math.min(mask.sub - 1, Math.floor((fc - col) * mask.sub))
  const bit = sr * mask.sub + sc
  return (mask.bits[off + (bit >> 3)] & (1 << (bit & 7))) !== 0
}

/**
 * The mask as the refiner asks it: raster LAND is land (the server refuses it but on a harbour's
 * own approach, and the chart draws a coast there too); in a listed water cell, the sub-cell's bit;
 * any other water cell is open sea.
 */
export function coastLand(mask: CoastMask, nav: SeaNav): DrawnLand {
  return {
    blocked: (lat, lon) => {
      const row = Math.floor((90 - lat) / nav.cellDeg)
      if (row < 0 || row >= nav.rows) return true
      const col = ((Math.floor((lon + 180) / nav.cellDeg) % nav.cols) + nav.cols) % nav.cols
      const k = row * nav.cols + col
      if (!nav.cells[k]) return true
      return mask.at.has(k) && maskBlocked(mask, lat, lon)
    },
  }
}

/** Does this mask belong to this raster's shape? (The md5 is checked where the cells are hashed.) */
export function maskFits(mask: CoastMask, nav: SeaNav): boolean {
  return mask.cols === nav.cols && mask.rows === nav.rows && mask.cellDeg === nav.cellDeg
}
