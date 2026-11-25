// PURE UNIT SPEC (0514): the course author goes round the seas shut to a fleet, and the grid of the world never moves.
import { test, expect } from '@playwright/test'
import { findPath, shutSeas, type SeaNav } from '../src/lib/sea'
import { proposeCourse } from '../src/domain/passage'
import { seaRows } from '../src/domain/seas'
import type { SeaConditions } from '../src/lib/rpc'

// 1 degree cells, 60 x 20, all water; zone B is columns 20 to 29 of rows 0 to 15 (a way round south of it), zone A the rest.
const cols = 360
const rows = 180
function world(): { nav: SeaNav; zones: { cols: number; rows: number; cells: Uint8Array; codes: (string | null)[] } } {
  const cells = new Uint8Array(cols * rows).fill(1)
  // a wall of land at column 0 so the long way round the globe is not taken
  for (let r = 0; r < rows; r++) cells[r * cols] = 0
  const z = new Uint8Array(cols * rows).fill(1)
  for (let r = 60; r < 110; r++) for (let c = 180; c < 190; c++) z[r * cols + c] = 2
  return { nav: { cols, rows, cellDeg: 1, cells }, zones: { cols, rows, cells: z, codes: [null, 'A', 'B'] } }
}
const at = (row: number, col: number) => ({ lat: 90 - (row + 0.5), lon: -180 + col + 0.5 })
const crosses = (path: readonly (readonly [number, number])[], z: { cells: Uint8Array }) => {
  for (let i = 0; i + 1 < path.length; i++)
    for (let k = 0; k <= 100; k++) {
      const lat = path[i][0] + ((path[i + 1][0] - path[i][0]) * k) / 100
      const lon = path[i][1] + ((path[i + 1][1] - path[i][1]) * k) / 100
      if (z.cells[Math.floor(90 - lat) * cols + Math.floor(lon + 180)] === 2) return true
    }
  return false
}

test('nothing shut: the very same grid; another raster: the very same grid', () => {
  const { nav, zones } = world()
  expect(shutSeas(nav, zones, [])).toBe(nav)
  expect(shutSeas(nav, zones, ['NOWHERE'])).toBe(nav)
  expect(shutSeas(nav, null, ['B'])).toBe(nav)
  expect(shutSeas(nav, { ...zones, cols: 10 }, ['B'])).toBe(nav)
})

test('a shut sea is gone round, and the world grid is untouched', () => {
  const { nav, zones } = world()
  const before = nav.cells.slice()
  const from = at(85, 170)
  const to = at(85, 200)
  const open = proposeCourse(nav, from, to)!
  expect(crosses(open, zones)).toBe(true)
  const her = shutSeas(nav, zones, ['B'])
  const round = proposeCourse(her, from, to)!
  expect(crosses(round, zones)).toBe(false)
  expect(findPath(nav, from, to)!.nm).toBeLessThan(findPath(her, from, to)!.nm)
  expect(nav.cells).toEqual(before)
})

test('bound into a shut sea, or with no way round, she proposes the whole water (the server says which sea is closed)', () => {
  const { nav, zones } = world()
  const her = shutSeas(nav, zones, ['B'])
  expect(proposeCourse(her, at(85, 170), at(85, 185))).toEqual(proposeCourse(nav, at(85, 170), at(85, 185)))
  for (let r = 0; r < rows; r++) for (let c = 180; c < 190; c++) zones.cells[r * cols + c] = 2
  const wall = shutSeas(nav, zones, ['B'])
  expect(proposeCourse(wall, at(85, 170), at(85, 200))).toEqual(proposeCourse(nav, at(85, 170), at(85, 200)))
})

test('the seas are listed by continent: the level they ask, then the served order', () => {
  const zone = (code: string, title_min: number, ord: number) => ({ code, name: code, title_min, wave_min: 0, ord, boxes: [] })
  const c = { zones: [zone('ASIA', 6, 1), zone('EUR2', 1, 9), zone('EUR1', 1, 2)] } as unknown as SeaConditions
  expect(seaRows(c).map((r) => r.zone.code)).toEqual(['EUR1', 'EUR2', 'ASIA'])
})
