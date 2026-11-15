#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-coast-mask.mjs — THE COAST MASK, BUILT (owner row 352; src/lib/sea/coastMask.ts says what
// it is). Run it whenever the sea raster or the chart's coast tiles change:
//
//   node scripts/build-coast-mask.mjs [world-image.tar.gz]
//
// Reads the raster the chain serves out of a world image (`npm run build` writes one under dist/;
// with none named, the newest under node_modules/.cache/byeharu-world-image is used) and the land
// the chart draws (public/coast/fine, scripts/lib/drawn-land.mjs). Writes public/coast/mask.json.
// tests/sea.noLandCrossing.spec.ts fails when the mask was cut for another raster than the one the
// applied chain serves, or when it differs from what this script would write.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHash } from 'node:crypto'
import { drawnLand, PX_PER_DEG } from './lib/drawn-land.mjs'
import { riverCarvedCells } from './sea-grid.mjs'
import { navFromServed } from '../src/lib/sea/index.ts'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
export const MASK_FILE = path.join(ROOT, 'public', 'coast', 'mask.json')
export const SUB = 20

/** THE SUB-CELL RULE: land when the chart draws land at ANY of the land bitmap's pixels inside it
 *  (2 x 2 of them: the bitmap is PX_PER_DEG = 80 a degree, a sub-cell 1/40). So the mask is never
 *  thinner than the drawn land: a course held clear of the mask is clear of the coast the chart
 *  draws, to the bitmap's own pixel. */
function subCellHasLand(land, north, west, size) {
  const n = Math.max(1, Math.round(size * PX_PER_DEG))
  for (let a = 0; a < n; a++) {
    for (let b = 0; b < n; b++) {
      if (land.isLand(north - ((a + 0.5) * size) / n, west + ((b + 0.5) * size) / n)) return true
    }
  }
  return false
}

/**
 * The mask for one served raster (`{ cols, rows, cell_deg, bits_per_cell, cells_base64 }`).
 * A raster WATER cell is listed when the chart draws land in any of its SUB x SUB sub-cells. A
 * river-carved cell (a channel the chart does not draw: land in 1:110m, water on purpose) is never
 * listed; a charted channel's cell is listed like any other (0440), and raster
 * LAND is the raster's own answer (the refiner treats it as land throughout).
 */
export function buildCoastMask(raster, land = drawnLand('fine')) {
  const nav = navFromServed(raster)
  if (nav.cols !== 1440 || nav.rows !== 720) throw new Error('coast mask: the raster is not the 0.25-degree world grid')
  const river = riverCarvedCells()
  const bytesPerCell = Math.ceil((SUB * SUB) / 8)
  const idx = []
  const bits = []
  for (let row = 0; row < nav.rows; row++) {
    for (let col = 0; col < nav.cols; col++) {
      const k = row * nav.cols + col
      const water = nav.cells[k] !== 0
      if (!water || river.has(k)) continue // raster land is the raster's; a river carve is water on purpose (0440: a charted channel's drawn land is listed)
      const lat0 = 90 - row * nav.cellDeg
      const lon0 = -180 + col * nav.cellDeg
      const cell = new Uint8Array(bytesPerCell)
      let landSubs = 0
      for (let i = 0; i < SUB; i++) {
        for (let j = 0; j < SUB; j++) {
          if (subCellHasLand(land, lat0 - (i * nav.cellDeg) / SUB, lon0 + (j * nav.cellDeg) / SUB, nav.cellDeg / SUB)) {
            const b = i * SUB + j
            cell[b >> 3] |= 1 << (b & 7)
            landSubs++
          }
        }
      }
      if (landSubs === 0) continue
      idx.push(k)
      bits.push(cell)
    }
  }
  const cells = Buffer.alloc(idx.length * 4)
  idx.forEach((k, i) => cells.writeUInt32LE(k, i * 4))
  return {
    sub: SUB,
    raster: {
      cols: nav.cols,
      rows: nav.rows,
      cellDeg: nav.cellDeg,
      md5: createHash('md5').update(raster.cells_base64.replace(/\s+/g, '')).digest('hex'),
    },
    cells: cells.toString('base64'),
    bits: Buffer.concat(bits.map((b) => Buffer.from(b))).toString('base64'),
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { openImage, readWorldCourses, newestImage } = await import('./db/audit-land-crossings.mjs')
  const file = process.argv[2] ?? (await newestImage())
  const db = await openImage(file)
  const { raster } = await readWorldCourses(db)
  await db.close()
  const mask = buildCoastMask(raster)
  writeFileSync(MASK_FILE, JSON.stringify(mask) + '\n')
  console.log(`coast mask: ${mask.cells.length ? Buffer.from(mask.cells, 'base64').length / 4 : 0} cell(s) hold drawn land; raster ${mask.raster.md5}; wrote ${path.relative(ROOT, MASK_FILE)}`)
}
