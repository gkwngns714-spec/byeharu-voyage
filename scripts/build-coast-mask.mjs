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
import { riverCarvedCells, CHANNELS, gcNm } from './sea-grid.mjs'
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

/** THE FAIRWAYS (0446): a charted channel marked `fairway` in scripts/sea-grid.mjs is drawn narrower than
 *  the course author's grid can pass (the western fairway of Surabaya: two pixels of the land bitmap,
 *  1.5 nm, not lined up with the 1.5-nm cells). The fine cells its line runs through (2 x 2 sub-cells
 *  each) are water in the mask, so the fairway is one fine cell wide at its narrowest. The line itself
 *  is drawn water at every 0.25 nm (scripts/build-straits.mjs refuses otherwise), so a course in the
 *  fairway is never further over the drawn coast than one sub-cell (0.75 nm), under the audit's
 *  tolerance. Returns the sub-cells as `I * 28800 + J` (I, J: 1/80-degree rows from 90 N, columns from 180 W). */
export function fairwaySubCells() {
  const FINE = (SUB / 0.25) / 2 // fine cells a degree (src/lib/sea/refine.ts FINE_PER_DEG = 40)
  const out = new Set()
  for (const ch of CHANNELS) {
    if (!ch.fairway) continue
    if (!ch.charted) throw new Error(`coast mask: ${ch.id} is a fairway but not charted`)
    for (let i = 0; i + 1 < ch.points.length; i++) {
      const [a, b] = [ch.points[i], ch.points[i + 1]]
      const n = Math.max(1, Math.ceil(gcNm(a[0], a[1], b[0], b[1]) / 0.1))
      for (let s = 0; s <= n; s++) {
        const A = Math.floor((90 - (a[0] + ((b[0] - a[0]) * s) / n)) * FINE) // the fine cell (1/40 degree): 2 x 2 sub-cells
        const B = Math.floor((a[1] + ((b[1] - a[1]) * s) / n + 180) * FINE)
        for (const I of [2 * A, 2 * A + 1]) for (const J of [2 * B, 2 * B + 1]) out.add(I * 28800 + J)
      }
    }
  }
  return out
}

/**
 * The mask for one served raster (`{ cols, rows, cell_deg, bits_per_cell, cells_base64 }`).
 * A raster WATER cell is listed when the chart draws land in any of its SUB x SUB sub-cells. A
 * river-carved cell (a channel the chart does not draw: land in 1:110m, water on purpose) is never
 * listed; a charted channel's cell is listed like any other (0440), but for a fairway's own line (0446); and raster
 * LAND is the raster's own answer (the refiner treats it as land throughout).
 */
export function buildCoastMask(raster, land = drawnLand('fine')) {
  const nav = navFromServed(raster)
  if (nav.cols !== 1440 || nav.rows !== 720) throw new Error('coast mask: the raster is not the 0.25-degree world grid')
  const river = riverCarvedCells()
  const fairway = fairwaySubCells()
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
          if (fairway.has((row * SUB + i) * 28800 + col * SUB + j)) continue // 0446: a fairway's own line is water
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
