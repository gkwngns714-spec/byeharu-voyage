import type { SeaZoneMap } from '../../lib/rpc'

// THE SEAS ON THE CHART, UNPACKED — which zone a point of water is in, as the server's own zone raster says
// (`world.sea_zone_map`, 0396: public.sea_zone_cells, the raster the sail door samples a course on).
//
// The client never works out a zone from a sea and its boxes: it reads the cell. Row 0 is the north edge, column 0
// is 180° W. Pure: no React, no store, no canvas.

export interface ZoneCells {
  readonly cols: number
  readonly rows: number
  readonly cellDeg: number
  /** cols × rows bytes: the cell's value, an index into `codes`. */
  readonly cells: Uint8Array
  /** The zone code for each value; null where the value names no zone (land). */
  readonly codes: ReadonlyArray<string | null>
}

/** The served runs unpacked to one byte a cell; null when the payload is not whole (a row short, a value out of range). */
export function unpackZoneMap(map: SeaZoneMap | null | undefined): ZoneCells | null {
  if (!map || !Array.isArray(map.runs) || !Array.isArray(map.codes)) return null
  const { cols, rows } = map
  if (!(cols > 0) || !(rows > 0) || !(map.cell_deg > 0) || map.runs.length !== rows) return null
  const cells = new Uint8Array(cols * rows)
  for (let r = 0; r < rows; r++) {
    let c = 0
    const row = map.runs[r]
    if (typeof row !== 'string') return null
    for (const run of row.split(',')) {
      const cut = run.indexOf(':')
      const value = Number(run.slice(0, cut))
      const count = Number(run.slice(cut + 1))
      if (cut < 1 || !Number.isInteger(value) || value < 0 || value > 255 || !Number.isInteger(count) || count < 1 || c + count > cols) return null
      cells.fill(value, r * cols + c, r * cols + c + count)
      c += count
    }
    if (c !== cols) return null
  }
  return { cols, rows, cellDeg: map.cell_deg, cells, codes: map.codes }
}

/** The zone a point of water is in; null on land, off the chart, or where the raster names none. */
export function zoneAt(z: ZoneCells, lat: number, lon: number): string | null {
  const row = Math.floor((90 - lat) / z.cellDeg)
  const wrapped = ((((lon + 180) % 360) + 360) % 360)
  const col = Math.floor(wrapped / z.cellDeg)
  if (row < 0 || row >= z.rows || col < 0 || col >= z.cols) return null
  return z.codes[z.cells[row * z.cols + col]] ?? null
}
