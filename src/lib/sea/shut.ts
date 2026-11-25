// THE SEAS SHUT TO A FLEET, AS WATER SHE DOES NOT SAIL (0514): the grid with those cells closed, so the one search (./pathfind.ts)
// goes the long way round. Machinery: it knows cells and codes, not why a sea is shut (the server's `world.sea_conditions` says
// which). The grid is the world's own: no cell of it moves, so no strait (scripts/straits.mjs) and no stored course does either.

import type { SeaNav } from './grid.ts'

/** The zone raster the server serves (domain/seas zoneMap): cell values into `codes`. */
export interface ZoneGrid {
  readonly cols: number
  readonly rows: number
  readonly cells: Uint8Array
  readonly codes: ReadonlyArray<string | null>
}

/** `nav` with every cell of the `shut` zones closed, `open` pointing at the whole water; `nav` itself when nothing is shut. */
export function shutSeas(nav: SeaNav, zones: ZoneGrid | null, shut: readonly string[]): SeaNav {
  if (!zones || shut.length === 0 || zones.cols !== nav.cols || zones.rows !== nav.rows) return nav
  const closed = new Set(shut)
  const byValue = zones.codes.map((c) => c !== null && closed.has(c))
  if (!byValue.some(Boolean)) return nav
  const cells = new Uint8Array(nav.cells)
  for (let i = 0; i < cells.length; i++) if (byValue[zones.cells[i]]) cells[i] = 0
  return { ...nav, cells, open: nav, fine: 4 }
}
