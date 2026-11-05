import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { buildCoastline, onDrawnLand } from '../src/chart'
import { CELL_DEG, COLS, buildSeaGrid, harbourIslands, islandCells, rowOf, colOf } from '../scripts/sea-grid.mjs'
import { deriveWorld } from '../scripts/lib/world-derive.mjs'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE HARBOURS' ISLANDS — owner row 92, and row 41's law that the fleet never touches land.
//
// The drawn coast and the sea raster read the same polygon points. These laws hold them together:
// an island that is drawn is an island no keel can sail through, and it is drawn point for point.
// PURE: no page, no database.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const WORLD = JSON.parse(readFileSync(path.join(process.cwd(), 'data', 'world-110m.json'), 'utf8'))
const COAST = buildCoastline(WORLD)
const ISLANDS = harbourIslands()
const WATER = buildSeaGrid()
const cellOf = (lat: number, lon: number) => rowOf(lat) * COLS + colOf(lon)

test('28 islands, each a harbour of the world, each with its own marker', () => {
  expect(ISLANDS).toHaveLength(28)
  const codes = new Set(deriveWorld().ports.map((p) => p.code))
  for (const island of ISLANDS) expect(codes.has(island.code), island.code).toBe(true)
  expect(new Set(ISLANDS.map((i) => i.code)).size).toBe(28)
})

test('every island is drawn exactly as the file has it, whatever its size', () => {
  for (const { code, ring } of ISLANDS) {
    const drawn = COAST.rings.find(
      (r) => r.length === ring.length && r.every((p, i) => p.x === ring[i][0] && p.y === -ring[i][1]),
    )
    expect(drawn, `${code} is not in the body point for point`).toBeDefined()
  }
})

test('no raster cell an island touches is sailable: every vertex, every edge, the whole interior', () => {
  for (const { code, ring } of ISLANDS) {
    for (let i = 0; i + 1 < ring.length; i++) {
      const [x1, y1] = ring[i]
      const [x2, y2] = ring[i + 1]
      const steps = Math.max(2, Math.ceil(Math.hypot(x2 - x1, y2 - y1) / (CELL_DEG / 20)))
      for (let s = 0; s <= steps; s++) {
        const lon = x1 + ((x2 - x1) * s) / steps
        const lat = y1 + ((y2 - y1) * s) / steps
        expect(WATER[cellOf(lat, lon)], `${code}: a keel can reach its shore at ${lat}, ${lon}`).toBe(0)
      }
    }
  }
  // Every harbour on an island: its own quay is land to the raster, so its roadstead lies off it.
  const ports = deriveWorld().ports
  for (const { code } of ISLANDS) {
    const port = ports.find((p) => p.code === code)!
    if (onDrawnLand(COAST.rings, { x: port.lon, y: -port.lat })) {
      expect(WATER[cellOf(port.lat, port.lon)], `${code}: its quay is sailable water`).toBe(0)
    }
  }
})

test('the islands close only what they touch: a count a person has looked at', () => {
  // MEASURED 2026-11-05: 182 cells of 1,036,800. A move here moves the raster, and needs a migration.
  expect(islandCells().size).toBe(182)
})
