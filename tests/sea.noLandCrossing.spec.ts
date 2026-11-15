// ═══════════════════════════════════════════════════════════════════════════════════════════════
// NO COURSE CROSSES THE DRAWN LAND — the guard (owner row 352, migration 0440)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-15: *"some ships go pass through land - such as hadibu. i found one by myself,
// and i am guessing there are millions like this. fix this properly, and make procedures that this
// won't happen again"*.
//
// WHAT WAS WRONG: the sea is a 0.25-degree raster scan-filled from Natural Earth 1:110m (no
// Socotra at all), the pathfinder straightens its courses against that raster alone, and the chart
// draws 1:10m. On the main world before 0440, 774 of the 1,141 lanes and 2,422 of the 3,350 route
// legs ran over more than 2 nm of drawn land, and 62,024 of the 71,556 courses the browser would
// propose between two harbours did.
//
// WHAT THIS HOLDS, on the build's own world (tests/builtWorld.fixture.ts), with the audit's own
// functions (scripts/db/audit-land-crossings.mjs) and the chart's own tiles:
//   1. the coast mask the course author steers by (public/coast/mask.json) is exactly what
//      scripts/build-coast-mask.mjs cuts for the raster this chain serves;
//   2. every lane (npc_courses: merchants, cargo, pirates, navy), every route leg
//      (standing_route_stops) and every coast course (npc_coast_courses) is off the drawn land, but for the KNOWN list
//      (scripts/db/land-crossings.known.json), and that list may only shrink: a new crossing fails,
//      and so does a known one that no longer crosses (take it off the list);
//   3. the harbours whose roadstead (sea_reaches) lies on drawn land are the known list, no more;
//   4. the owner's own example: the course from Hadibu to Kilwa crossed the whole of Socotra; the
//      course author's course does not, and the search alone still would (the ruler sees the fault);
//   5. a fixed sample of the course author's courses (every harbour to an origin in every 22nd)
//      crosses no more often than the known count;
//   6. (0440) the charted channels (scripts/sea-grid.mjs, `charted: true`: Corfu, Tsugaru and the
//      Wielingen, opened by 0440; and eight straits carved before, from Kerch to Malacca) are open water,
//      and the cells 0440 opened keep their drawn land in the mask; Corfu to Ancona sails the channel
//      over no land.
//   7. (0441) AN APPROACH IS NOT A CANAL. The server skipped every sample within 25 nm of each end of a
//      course unread, so the straight line from Panama City's roads to Portobelo's (46 nm, across the
//      isthmus) was water, and the search offered it. Now an end has an approach only when it stands
//      on land, and a roadstead never does: no straight line between two roadsteads is accepted with
//      raster land under it, the Panama line is refused (and the old rule still shows the fault), the
//      course author goes by sea, and no stored course is one the server's own law refuses (the
//      audit lists such a course beside the crossings).
// After 0440 the known list is EMPTY, and after 0441 the sample's count is 0: every lane, route leg and
// coast course is off the drawn land, no roadstead lies on it, and no proposed course crosses.
// Keep it so: a new crossing is fixed, never listed.
//
// WHEN IT RUNS (scripts/ci/select-specs.mjs): a PR that changes a file this spec imports (the
// pathfinder, the refiner, the mask, the audit, the sea grid), names here ('ports.json',
// 'world-110m.json', 'sea-grid.mjs', 'mask.json', 'fineCoast.generated.ts', 'drawn-land.mjs'), or a
// migration that writes npc_courses, standing_route_stops, sea_reaches, sea_raster or
// cargo_circuit_legs. The procedure is docs/NAVIGATION_PLAN.md §8.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test'
import { existsSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import {
  auditAllowance,
  auditWorld,
  crossingsOf,
  flatAllowanceIsWater,
  readWorldCourses,
  truthLand,
  type WorldCourses,
} from '../scripts/db/audit-land-crossings.mjs'
import { buildCoastMask } from '../scripts/build-coast-mask.mjs'
import { CHANNELS, carveInventory } from '../scripts/sea-grid.mjs'
import { coastLand, coastMaskFrom, courseRefusedAt, findPath, navFromServed, refineCourse, segmentIsWater, type CoastMaskPayload } from '../src/lib/sea'

const KNOWN = path.resolve('scripts', 'db', 'land-crossings.known.json')
const MASK = path.resolve('public', 'coast', 'mask.json')
/** What this guard stands on, by name (so a change to any of them selects it). */
const WATCHED = [
  ['data', 'ports.json'],
  ['data', 'world-110m.json'],
  ['scripts', 'sea-grid.mjs'],
  ['scripts', 'lib', 'drawn-land.mjs'],
  ['public', 'coast', 'mask.json'],
  ['src', 'chart', 'fineCoast.generated.ts'],
]
/** Solid Socotra: drawn land through and through (the generator checks it on the tiles). */
const SOCOTRA = { south: 12.45, north: 12.55, west: 53.7, east: 54.2 }

interface Known {
  crossings: string[]
  roadsteads: string[]
  pairSample: { every: number; pairs: number; crossing: number }
}

let db: LocalDb
let world: WorldCourses
let known: Known

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  world = await readWorldCourses(db.pg)
  known = JSON.parse(readFileSync(KNOWN, 'utf8')) as Known
})

test.afterAll(async () => {
  await db?.close()
})

const inSocotra = (course: readonly (readonly [number, number])[]): number => {
  let n = 0
  for (let i = 0; i + 1 < course.length; i++) {
    const [a, b] = [course[i], course[i + 1]]
    for (let s = 0; s <= 400; s++) {
      const lat = a[0] + ((b[0] - a[0]) * s) / 400
      const lon = a[1] + ((b[1] - a[1]) * s) / 400
      if (lat >= SOCOTRA.south && lat <= SOCOTRA.north && lon >= SOCOTRA.west && lon <= SOCOTRA.east) n++
    }
  }
  return n
}

test('the files the guard stands on are where it reads them', () => {
  for (const parts of WATCHED) expect(existsSync(path.resolve(...parts)), parts.join('/')).toBe(true)
})

test('the coast mask is the one cut for the raster this chain serves', () => {
  test.setTimeout(120_000)
  const shipped = JSON.parse(readFileSync(MASK, 'utf8')) as CoastMaskPayload
  const fresh = buildCoastMask(world.raster)
  expect(shipped.raster, 'run `node scripts/build-coast-mask.mjs` after the raster or the coast tiles change').toEqual(fresh.raster)
  expect(shipped.cells === fresh.cells && shipped.bits === fresh.bits, 'the mask differs from what the builder cuts: rebuild it').toBe(true)
})

test('no lane and no route leg crosses the drawn land, but the known list, which only shrinks', () => {
  test.setTimeout(120_000)
  const out = auditWorld(world)
  const found = [...new Set(out.crossings.map((c) => c.key))].sort()
  const added = found.filter((k) => !known.crossings.includes(k))
  const gone = known.crossings.filter((k) => !found.includes(k))
  const worst = (k: string) => out.crossings.find((c) => c.key === k)
  expect(
    added.map((k) => `${k}: ${worst(k)?.worst.nm} nm of land at ${worst(k)?.worst.at.join(',')}${worst(k)?.refused ? `; refused by the server's law at ${worst(k)?.refused?.join(',')}` : ''}`),
    'NEW courses over the drawn land, or refused by voyage.path_refusal: re-sail them (scripts/build-land-channels.mjs, scripts/build-isthmus.mjs)',
  ).toEqual([])
  expect(gone, 'these no longer cross: take them off scripts/db/land-crossings.known.json').toEqual([])
})

test('the roadsteads on the drawn land are the known ones, no more', () => {
  const out = auditWorld(world)
  expect([...out.roadsteads].sort()).toEqual([...known.roadsteads].sort())
})

test("the owner's example: Hadibu to Kilwa no longer sails across Socotra", () => {
  const nav = navFromServed(world.raster)
  const mask = coastMaskFrom(JSON.parse(readFileSync(MASK, 'utf8')) as CoastMaskPayload)
  const had = world.ports.find((p) => p.code === 'HAD')
  const kil = world.ports.find((p) => p.code === 'KIL')
  expect(had?.rlat != null && kil?.rlat != null).toBe(true)
  const from = { lat: had!.rlat!, lon: had!.rlon! }
  const to = { lat: kil!.rlat!, lon: kil!.rlon! }
  const raw = findPath(nav, from, to)
  expect(raw, 'the search finds a course').not.toBeNull()
  // The ruler sees the fault: the search alone runs straight over the island.
  expect(inSocotra(raw!.path)).toBeGreaterThan(0)
  const course = refineCourse(nav, coastLand(mask, nav), raw!.path).path
  expect(inSocotra(course), JSON.stringify(course)).toBe(0)
  expect(crossingsOf(truthLand(nav), course)).toEqual([])
  // And the stored lane the merchants sail is the same kind of course.
  const lane = world.npc.find((c) => c.a === 'HAD' && c.b === 'KIL')
  if (lane) expect(inSocotra(lane.course)).toBe(0)
})

test('the charted channels are open water, and the land the chart draws in them stays land (0440)', () => {
  // Corfu's two channels, the Tsugaru strait and the Wielingen: water the chart draws and 1:110m closed.
  // The raster opens their cells; the coast mask still lists the drawn land inside each, so a course is
  // steered down the strait, never across the island beside it.
  const nav = navFromServed(world.raster)
  const mask = coastMaskFrom(JSON.parse(readFileSync(MASK, 'utf8')) as CoastMaskPayload)
  const { carved } = carveInventory()
  const charted = CHANNELS.filter((c) => c.charted)
  // Three opened by 0440, and eight straits carved long before and held to their drawn land since.
  expect(charted.map((c) => c.id).sort()).toEqual(
    ['bab-el-mandeb', 'baltic-gulfs', 'corfu', 'hormuz', 'kerch', 'malacca', 'seto', 'sunda', 'tsugaru', 'western-scheldt', 'white-sea'],
  )
  for (const ch of charted) {
    for (const k of carved.get(ch.id) ?? []) expect(nav.cells[k], `${ch.id} cell ${k} is water`).not.toBe(0)
  }
  // Every cell 0440 opened holds drawn land (an island, a cape, the far shore), and the mask keeps it.
  for (const id of ['corfu', 'tsugaru', 'western-scheldt']) {
    for (const k of carved.get(id) ?? []) expect(mask.at.has(k), `${id} cell ${k} keeps its drawn land in the mask`).toBe(true)
  }
  // Corfu to Ancona, as the course author proposes it: up the North Corfu channel, over no land.
  const cor = world.ports.find((p) => p.code === 'COR')
  const anc = world.ports.find((p) => p.code === 'ANC')
  const raw = findPath(nav, { lat: cor!.rlat!, lon: cor!.rlon! }, { lat: anc!.rlat!, lon: anc!.rlon! })
  expect(raw, 'the search finds a course').not.toBeNull()
  const course = refineCourse(nav, coastLand(mask, nav), raw!.path).path
  expect(crossingsOf(truthLand(nav), course)).toEqual([])
})

test('an approach is not a canal: Panama City to Portobelo goes by sea, and no allowance hides land (0441)', () => {
  test.setTimeout(120_000)
  const nav = navFromServed(world.raster)
  const mask = coastMaskFrom(JSON.parse(readFileSync(MASK, 'utf8')) as CoastMaskPayload)
  const pan = world.ports.find((p) => p.code === 'PAN')
  const prt = world.ports.find((p) => p.code === 'PRT')
  expect(pan?.rlat != null && prt?.rlat != null).toBe(true)
  const a: [number, number] = [pan!.rlat!, pan!.rlon!]
  const b: [number, number] = [prt!.rlat!, prt!.rlon!]
  // The ruler sees the fault: by the rule as it stood (25 nm unread at each end) the straight line is water,
  // and it runs over the isthmus the chart draws.
  expect(flatAllowanceIsWater(nav, [a, b]), 'the old rule let the line through').toBe(true)
  expect(crossingsOf(truthLand(nav), [a, b]).length).toBeGreaterThan(0)
  // The rule as it stands refuses it, whole-course and as the straightener reads one segment.
  expect(courseRefusedAt(nav, [a, b])).not.toBeNull()
  expect(segmentIsWater(nav, a, b, 25, 25)).toBe(false)
  // The course author goes by sea: round the Horn, over no land, and the server's law accepts it.
  const raw = findPath(nav, { lat: a[0], lon: a[1] }, { lat: b[0], lon: b[1] })
  expect(raw, 'the search finds a course by sea').not.toBeNull()
  const course = refineCourse(nav, coastLand(mask, nav), raw!.path).path
  expect(raw!.nm).toBeGreaterThan(5000)
  expect(crossingsOf(truthLand(nav), course)).toEqual([])
  expect(courseRefusedAt(nav, course)).toBeNull()
  // An end that stands on land still has its approach, and only that: from a land cell straight to the
  // next water is passed inside the allowance, and refused when a second run of land follows the water.
  const lis = world.ports.find((p) => p.code === 'LIS')!
  expect(courseRefusedAt(nav, [[lis.lat, lis.lon], [lis.rlat!, lis.rlon!]], 60, 25), 'Lisbon quay to its roads, as an approach').toBeNull()
  expect(courseRefusedAt(nav, [[lis.lat, lis.lon], [lis.rlat!, lis.rlon!]], 0, 0), 'the same line with no approach').not.toBeNull()
  // Every pair of harbours: no straight line is accepted with raster land under it, whatever the allowance.
  const al = auditAllowance(world)
  expect(al.still, 'straight lines the rule accepts over raster land').toEqual([])
  expect(al.byAllowance, 'the old rule let lines through by the allowance alone: the audit still measures it').toBeGreaterThan(0)
  expect(al.canals.some((c) => c.key === 'PAN-PRT')).toBe(true)
})

test("a fixed sample of the course author's courses crosses no more often than the known count", () => {
  test.setTimeout(300_000)
  const codes = world.ports.filter((p) => p.rlat != null).map((p) => p.code).sort()
  const origins = new Set(codes.filter((_, i) => i % known.pairSample.every === 0))
  const out = auditWorld(world, { pairs: true, pairFilter: (a) => origins.has(a.code) })
  const crossing = out.crossings.filter((c) => c.kind === 'pair').length
  expect(out.counted.pair).toBe(known.pairSample.pairs)
  expect(crossing, `the sample crosses ${crossing} times, the known count is ${known.pairSample.crossing}: lower it if it fell`).toBeLessThanOrEqual(known.pairSample.crossing)
})
