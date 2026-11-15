// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE REAL STRAITS ARE PASSABLE — the guard (owner row 352, migration 0446)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-15: the fix over-corrected. Messina to Zakynthos is 630 nm where it was 291: the
// course goes round Sicily, not through the Strait of Messina, "a real, wide strait that ships must be
// able to pass".
//
// WHAT WAS WRONG: 0440 took every course off the land the chart draws and 0441 ended the approach
// allowance. Both were right, and both had been standing in for real straits the 0.25-degree raster
// closes (Messina, the Great Belt, the Bangka strait, the western fairway of Surabaya). Nothing held
// a strait OPEN: the land guard (tests/sea.noLandCrossing.spec.ts) only fails when a course is on
// the land, and a course that goes 340 nm round an island is not.
//
// WHAT THIS HOLDS, on the build's own world (tests/builtWorld.fixture.ts): for every strait on the
// list (scripts/straits.mjs STRAIT_PASSES), the course the browser's course author plots between the
// named harbour on each side (the search, then the re-sailing off the coast mask):
//   1. runs through the strait's own water (its box);
//   2. is no longer than the stated multiple of the straight line between the two roadsteads;
//   3. is over no drawn land and is accepted by the server's law, every sample read.
// And the ruler sees the fault: with a charted strait's cells closed again, the same two harbours are
// far apart (Messina to Zakynthos over 600 nm).
//
// A strait leaves the list only in a slice whose dev-log says why it may close. A NEW harbour, raster,
// coast or pathfinder change that fails here has closed a strait: open it (a `charted` channel in
// scripts/sea-grid.mjs, docs/NAVIGATION_PLAN.md section 8) or put the roadstead back on its water.
//
// WHEN IT RUNS (scripts/ci/select-specs.mjs): a PR that changes a file this spec imports (the
// pathfinder, the refiner, the mask builder, the audit, the sea grid, the list), a file named here
// ('ports.json', 'world-110m.json', 'mask.json', 'fineCoast.generated.ts', 'drawn-land.mjs'), or a
// migration that writes public.sea_raster, public.sea_reaches, voyage.channels or voyage.drawn_roadsteads.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test'
import { existsSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { crossingsOf, readWorldCourses, truthLand, type WorldCourses } from '../scripts/db/audit-land-crossings.mjs'
import { buildCoastMask } from '../scripts/build-coast-mask.mjs'
import { CHANNELS, carveInventory, gcNm } from '../scripts/sea-grid.mjs'
import { STRAIT_PASSES, courseInBox } from '../scripts/straits.mjs'
import { coastLand, coastMaskFrom, courseRefusedAt, findPath, navFromServed, refineCourse, type CoastMaskPayload, type SeaNav } from '../src/lib/sea'

const MASK = path.resolve('public', 'coast', 'mask.json')
/** What this guard stands on, by name (so a change to any of them selects it). */
const WATCHED = [
  ['data', 'ports.json'],
  ['data', 'world-110m.json'],
  ['scripts', 'lib', 'drawn-land.mjs'],
  ['public', 'coast', 'mask.json'],
  ['src', 'chart', 'fineCoast.generated.ts'],
]

let db: LocalDb
let world: WorldCourses

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  world = await readWorldCourses(db.pg)
})

test.afterAll(async () => {
  await db?.close()
})

const road = (code: string): [number, number] => {
  const p = world.ports.find((x) => x.code === code)
  if (!p || p.rlat == null || p.rlon == null) throw new Error(`no harbour ${code} with a roadstead in this world`)
  return [p.rlat, p.rlon]
}
const len = (c: readonly (readonly [number, number])[]) => c.reduce((t, p, i) => (i ? t + gcNm(c[i - 1][0], c[i - 1][1], p[0], p[1]) : t), 0)
/** The course the browser's course author proposes (src/domain/passage proposeCourse): the search, then the re-sailing. */
const plot = (nav: SeaNav, payload: CoastMaskPayload, a: [number, number], b: [number, number]) => {
  const raw = findPath(nav, { lat: a[0], lon: a[1] }, { lat: b[0], lon: b[1] })
  return raw ? refineCourse(nav, coastLand(coastMaskFrom(payload), nav), raw.path).path : null
}

test('the files the guard stands on are where it reads them', () => {
  for (const parts of WATCHED) expect(existsSync(path.resolve(...parts)), parts.join('/')).toBe(true)
  // the list is not empty, names each strait 0446 opened, and every charted channel 0446 opened is on it
  expect(STRAIT_PASSES.length).toBeGreaterThanOrEqual(30)
  for (const id of ['messina', 'great-belt', 'bangka', 'surabaya']) {
    expect(CHANNELS.find((c) => c.id === id)?.charted, `${id} is a charted channel`).toBe(true)
    expect(STRAIT_PASSES.some((p) => p.id === id), `${id} is on the list`).toBe(true)
  }
})

test('every real strait on the list is passable: a short, clean course runs through it', () => {
  test.setTimeout(300_000)
  const nav = navFromServed(world.raster)
  const payload = JSON.parse(readFileSync(MASK, 'utf8')) as CoastMaskPayload
  const truth = truthLand(nav)
  const closed: string[] = []
  for (const p of STRAIT_PASSES) {
    const [a, b] = [road(p.a), road(p.b)]
    const course = plot(nav, payload, a, b)
    const gc = gcNm(a[0], a[1], b[0], b[1])
    const say = `${p.name}: ${p.a} to ${p.b}`
    if (!course) {
      closed.push(`${say}: no course by sea`)
      continue
    }
    const nm = len(course)
    if (!courseInBox(course, p.box, gcNm)) closed.push(`${say}: the course (${nm.toFixed(0)} nm) does not run through the strait`)
    else if (nm > gc * p.within) closed.push(`${say}: ${nm.toFixed(0)} nm sailed, over ${p.within} times the ${gc.toFixed(0)} nm straight line`)
    const land = crossingsOf(truth, course)
    if (land.length) closed.push(`${say}: ${land[0].nm} nm of drawn land at ${land[0].at.join(',')}`)
    if (courseRefusedAt(nav, course, 0, 0)) closed.push(`${say}: refused by the server's law`)
  }
  expect(closed, 'A REAL STRAIT IS CLOSED (docs/NAVIGATION_PLAN.md section 8: chart it in scripts/sea-grid.mjs, or put the roadstead on its water)').toEqual([])
})

test("the owner's example: Messina to Zakynthos goes through the strait, and the ruler sees the fault", () => {
  test.setTimeout(120_000)
  const nav = navFromServed(world.raster)
  const payload = JSON.parse(readFileSync(MASK, 'utf8')) as CoastMaskPayload
  const [mes, zak] = [road('MES'), road('ZAK')]
  const course = plot(nav, payload, mes, zak)
  expect(course, 'the search finds a course').not.toBeNull()
  // 291 nm before 0440, 630 after it (round Sicily), about 260 through the strait
  expect(len(course!)).toBeLessThan(320)
  // Messina's roadstead lies in the strait, in the cell the channel opened, not 14 nm off in the Tyrrhenian
  const { carved } = carveInventory()
  const strait = new Set(carved.get('messina'))
  expect(strait.size).toBe(2)
  const cellOf = (lat: number, lon: number) => Math.floor((90 - lat) / nav.cellDeg) * nav.cols + Math.floor((lon + 180) / nav.cellDeg)
  expect(strait.has(cellOf(mes[0], mes[1])), `Messina's roadstead ${mes.join(',')} lies in the strait`).toBe(true)
  // THE RULER: the same world with the strait's two cells closed again, and the mask cut for it. No course
  // through, and from the nearest water left to the roadstead (the Tyrrhenian side) Zakynthos is round Sicily.
  const bytes = Buffer.from(world.raster.cells_base64, 'base64')
  for (const k of strait) {
    const bit = k * world.raster.bits_per_cell
    bytes[bit >> 3] &= ~(1 << (bit & 7))
  }
  const shut = { ...world.raster, cells_base64: bytes.toString('base64') }
  const shutNav = navFromServed(shut)
  for (const k of strait) expect(shutNav.cells[k], 'the ruler closed the cell').toBe(0)
  const round = plot(shutNav, buildCoastMask(shut), [38.375, 15.375], zak)
  expect(round, 'round Sicily there is still a way').not.toBeNull()
  expect(len(round!)).toBeGreaterThan(600)
})

test('a fairway is water one fine cell wide down its own line, and nowhere else (0446)', () => {
  // Messina and Surabaya's western fairway are drawn narrower than the course author's 1.5-nm grid can follow
  // (two pixels of the land bitmap, not lined up with the grid). The mask leaves the fine cells their own
  // lines run through as water; the land the chart draws in the rest of their cells stays in the mask.
  const nav = navFromServed(world.raster)
  const mask = coastMaskFrom(JSON.parse(readFileSync(MASK, 'utf8')) as CoastMaskPayload)
  const land = coastLand(mask, nav)
  const { carved } = carveInventory()
  const fairways = CHANNELS.filter((c) => c.fairway)
  expect(fairways.map((c) => c.id).sort()).toEqual(['messina', 'surabaya'])
  for (const ch of fairways) {
    expect(ch.charted, `${ch.id} is charted`).toBe(true)
    for (let i = 0; i + 1 < ch.points.length; i++) {
      const [a, b] = [ch.points[i], ch.points[i + 1]]
      const n = Math.max(1, Math.ceil(gcNm(a[0], a[1], b[0], b[1]) / 0.25))
      for (let s = 0; s <= n; s++) {
        const lat = a[0] + ((b[0] - a[0]) * s) / n
        const lon = a[1] + ((b[1] - a[1]) * s) / n
        expect(land.blocked(lat, lon), `${ch.id}: its line is water at ${lat.toFixed(4)},${lon.toFixed(4)}`).toBe(false)
      }
    }
    // the cells it opened still hold the land the chart draws beside the fairway
    for (const k of carved.get(ch.id) ?? []) expect(mask.at.has(k), `${ch.id} cell ${k} keeps its drawn land in the mask`).toBe(true)
  }
})
