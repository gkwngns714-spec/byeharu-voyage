// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SEA IS ROUND — a course from Tokyo to Callao crosses the South Pacific, and the server sails it
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, docs/OWNER_REQUESTS.md row 91 (2026-09-14): *"the map should be continuous on left to
// right, and the ship going from tokyo to callao should cross south pacific ocean."*
//
// WHAT WAS WRONG, measured on main 2209a92 before the fix (docs/DEV_LOG.md 2026-09-14): the grid
// was always round and the A* always crossed the antimeridian — Tokyo → Acapulco came back as
// [[35.13,140.38],[39.13,179.88],[39.13,-179.88],[16.63,-99.88]] — but two readers refused to
// believe it. `segmentIsWater` returned false for any |Δlon| > 180 (so the straightener left the
// kink at the seam), and `voyage.path_refusal` answered the 0.25° hop between those two cell
// centres with `E_BAD_PATH: segment 1 jumps the antimeridian the long way round`. A Pacific
// crossing could be found and drawn and NEVER sailed.
//
// THE CONVENTION this file holds (migration 0088, src/lib/geo/projection.ts, NAVIGATION_PLAN §7):
//   · every vertex of a course lies in [−180, 180];
//   · a segment MAY straddle the seam, and it is ALWAYS read the short way round;
//   · one longitude rule each side — `lonLerp` here, `voyage.lon_lerp` there.
//
// PURE NODE SPEC — no `page`. The chain is applied in this process (PGlite, ~2-3 min), the course
// is proposed by THE pathfinder through the same fixture the rpc specs sail with, and the server's
// own verifier is asked directly with the figures cmd.do_sail passes for a roads-to-roads course.
//
// RED ON main's CODE, by construction: without 0088 the verifier refuses the course (E_BAD_PATH);
// without the client half the straightener leaves two vertices ON the seam. Both are asserted.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { haversineNm, lonLerp, shortLonDelta, unwrapLongitudes, wrapLon } from '../src/lib/geo'
import { pathLengthNm } from '../src/lib/geo'
import {
  clearBackend,
  createLocalBackend,
  expectOk,
  setBackend,
  worldSnapshot,
  type SnapshotPort,
} from '../src/lib/rpc'
import { courseBetweenPorts, seaNav } from './seaCourse.fixture'

let db: LocalDb
let portByCode: Record<string, SnapshotPort>

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  const snap = expectOk(await worldSnapshot())
  portByCode = Object.fromEntries(snap.ports.map((p) => [p.code, p]))
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

/** The straddling pairs of a course: adjacent vertices on opposite sides of ±180. */
const straddles = (course: readonly [number, number][]): number =>
  course.filter((p, i) => i > 0 && Math.abs(p[1] - course[i - 1][1]) > 180).length

/** The figures cmd.do_sail passes path_refusal for a course from one port's roads to another's:
 *  join = the course_join_nm knob, head and tail = 0076's flat 25 nm of sampling slack. */
async function serverRefusal(course: readonly [number, number][], from: SnapshotPort, to: SnapshotPort) {
  const r = await db.pg.query<{ ref: string | null; nm: string }>(
    `select voyage.path_refusal($1::jsonb, $2, $3, $4, $5, public.wc_num('course_join_nm'), 25, 25) as ref,
            voyage.path_nm($1::jsonb) as nm`,
    [JSON.stringify(course), from.roadstead.lat, from.roadstead.lon, to.roadstead.lat, to.roadstead.lon],
  )
  return { ref: r.rows[0].ref, nm: Number(r.rows[0].nm) }
}

// ── the rule, before the world ─────────────────────────────────────────────────────────────────

test.describe('the one longitude rule', () => {
  test('shortLonDelta takes the short way and wrapLon leaves a vertex alone', () => {
    expect(shortLonDelta(179, -179)).toBe(2)
    expect(shortLonDelta(-179, 179)).toBe(-2)
    expect(shortLonDelta(10, 20)).toBe(10)
    expect(shortLonDelta(-9.625, 4.375)).toBe(14)
    expect(wrapLon(180)).toBe(180)
    expect(wrapLon(-180)).toBe(-180)
    expect(wrapLon(190)).toBe(-170)
    expect(wrapLon(-190)).toBe(170)
  })

  test('lonLerp walks the 0.25° across the seam, not the 359.75° round the world', () => {
    expect(Math.abs(lonLerp(179.875, -179.875, 0.5))).toBe(180)
    expect(lonLerp(179.875, -179.875, 0.25)).toBeCloseTo(179.9375, 9)
    expect(lonLerp(179.875, -179.875, 0.75)).toBeCloseTo(-179.9375, 9)
    expect(lonLerp(179.875, -179.875, 0)).toBe(179.875)
    expect(lonLerp(179.875, -179.875, 1)).toBe(-179.875)
    // Inside the sheet it is exactly the linear step it always was.
    expect(lonLerp(-9.625, 4.375, 0.5)).toBe(-9.625 + (4.375 - -9.625) * 0.5)
  })

  test('unwrapLongitudes is shortLonDelta accumulated', () => {
    const u = unwrapLongitudes([
      { lat: 35, lon: 140 },
      { lat: 39, lon: 179.875 },
      { lat: 39, lon: -179.875 },
      { lat: -12, lon: -77 },
    ])
    expect(u.map((p) => p.lon)).toEqual([140, 179.875, 180.125, 283])
  })

  test('the haversine is already periodic: 0.2° across the seam is 12 nm', () => {
    expect(haversineNm({ lat: 0, lon: 179.9 }, { lat: 0, lon: -179.9 })).toBeCloseTo(12.0, 1)
  })
})

// ── the world ──────────────────────────────────────────────────────────────────────────────────

test.describe('Tokyo → Callao crosses the South Pacific', () => {
  test('the proposed course straddles the seam once, stays on the sphere, and is the Pacific’s length', async () => {
    const tokyo = portByCode['TOK']
    const callao = portByCode['CLL']
    expect(tokyo, 'Tokyo (TOK) is in the world').toBeDefined()
    expect(callao, 'Callao (CLL) is in the world').toBeDefined()
    const nav = await seaNav()
    const course = courseBetweenPorts(nav, tokyo, callao)

    // Every vertex is a coordinate on the sphere — the convention's first clause.
    for (const [lat, lon] of course) {
      expect(Math.abs(lat)).toBeLessThanOrEqual(90)
      expect(Math.abs(lon)).toBeLessThanOrEqual(180)
    }
    // Exactly one segment straddles the antimeridian: she crosses it once, going east — a
    // POSITIVE short-way step (140.375 → −77.375 is +142.25°, not −217.75°).
    expect(straddles(course)).toBe(1)
    const at = course.findIndex((p, k) => k > 0 && Math.abs(p[1] - course[k - 1][1]) > 180)
    expect(shortLonDelta(course[at - 1][1], course[at][1])).toBeGreaterThan(0)
    // And the straightener MERGED across it: no vertex is left standing on the seam's own two
    // columns (179.875 / −179.875), which is where main's `segmentIsWater` left a kink.
    expect(course.filter(([, lon]) => Math.abs(lon) >= 179.75)).toEqual([])

    // THE BAND. The great circle between the two roads is a hard floor (a polyline measured
    // segment by segment on the sphere cannot be shorter than the arc between its ends); 1.15×
    // that arc is the ceiling — a line-of-sight-straightened 8-connected grid path measures
    // 2–8 % over the straight line (NAVIGATION_PLAN §3), while the way she was refused into
    // before, round the Cape, is ≥ 1.5× (Tokyo → Calabar measured 10,876 nm on a 7,143 nm arc).
    const gc = haversineNm(
      { lat: tokyo.roadstead.lat, lon: tokyo.roadstead.lon },
      { lat: callao.roadstead.lat, lon: callao.roadstead.lon },
    )
    const nm = pathLengthNm(course.map(([lat, lon]) => ({ lat, lon })))
    expect(gc).toBeGreaterThan(8_000)
    expect(gc).toBeLessThan(9_000)
    expect(nm).toBeGreaterThanOrEqual(gc)
    expect(nm).toBeLessThanOrEqual(gc * 1.15)
  })

  test('the server accepts it, measures the same miles, and cuts it into pieces that stay on the sphere', async () => {
    const tokyo = portByCode['TOK']
    const callao = portByCode['CLL']
    const nav = await seaNav()
    const course = courseBetweenPorts(nav, tokyo, callao)
    const { ref, nm } = await serverRefusal(course, tokyo, callao)
    expect(ref, 'voyage.path_refusal on the seam-crossing course').toBeNull()
    expect(nm).toBeCloseTo(pathLengthNm(course.map(([lat, lon]) => ({ lat, lon }))), 0)

    const segs = await db.pg.query<{ s: { a: [number, number]; b: [number, number]; nm: string; sea_id: string | null }[] }>(
      'select voyage.segments_from_course($1::jsonb) as s',
      [JSON.stringify(course)],
    )
    const pieces = segs.rows[0].s
    expect(pieces.length).toBe(Math.ceil(nm / 500))
    for (const p of pieces) {
      expect(Math.abs(p.a[1])).toBeLessThanOrEqual(180)
      expect(Math.abs(p.b[1])).toBeLessThanOrEqual(180)
      // A piece is ~500 nm of water (0047 divides the parameter, so 450–530 nm here), so its two
      // ends are at most ~10° apart the short way — the straddling piece included.
      const d = Math.abs(shortLonDelta(p.a[1], p.b[1]))
      expect(d).toBeLessThan(15)
      expect(p.sea_id, `piece ${JSON.stringify(p.a)} → ${JSON.stringify(p.b)} has a sea`).not.toBeNull()
    }
    expect(pieces.filter((p) => Math.abs(p.a[1] - p.b[1]) > 180).length).toBe(1)
    // TWO figures, both 0047's: `path_nm` sums each vertex pair's great-circle chord (this course
    // is one segment, so that is the arc itself), and the pieces sum to the lat/lon-STRAIGHT line
    // she actually sails — the figure cmd.do_sail gates, prices and stores as total_nm. On the
    // short segments of every pre-0088 course they agree within 0.1 %; on one 8,000-nm segment
    // the line is ~3 % longer than the arc. Both sit in the band; neither is this slice's to move.
    const sailed = pieces.reduce((t, p) => t + Number(p.nm), 0)
    const gc = haversineNm(
      { lat: tokyo.roadstead.lat, lon: tokyo.roadstead.lon },
      { lat: callao.roadstead.lat, lon: callao.roadstead.lon },
    )
    expect(sailed).toBeGreaterThanOrEqual(nm - 0.01)
    expect(sailed).toBeLessThanOrEqual(gc * 1.15)
  })

  test('the same course sailed back, Callao → Tokyo, crosses once going west', async () => {
    const nav = await seaNav()
    const course = courseBetweenPorts(nav, portByCode['CLL'], portByCode['TOK'])
    expect(straddles(course)).toBe(1)
    // West is a NEGATIVE short-way step: −77.375 → 140.375 is −142.25°, not +217.75°.
    const i = course.findIndex((p, k) => k > 0 && Math.abs(p[1] - course[k - 1][1]) > 180)
    expect(shortLonDelta(course[i - 1][1], course[i][1])).toBeLessThan(0)
    expect((await serverRefusal(course, portByCode['CLL'], portByCode['TOK'])).ref).toBeNull()
  })

  test('a straddling segment over land is still refused as land, not as “the long way round”', async () => {
    // 0088's own E_LAND control: across Fiji's Vanua Levu, whose cell on the seam is land while
    // 1.5° either side is water. Read the old way this would have sampled 21,000 nm of water.
    const r = await db.pg.query<{ ref: string | null }>(
      `select voyage.path_refusal($1::jsonb, $2, $3, $4, $5, 0.5, 0, 0) as ref`,
      ['[[-16.375,178.5],[-16.375,-178.5]]', -16.375, 178.5, -16.375, -178.5],
    )
    expect(r.rows[0].ref).toMatch(/^E_LAND:/)
  })
})

// ── and nothing else moved ─────────────────────────────────────────────────────────────────────

test('Lisbon → Amsterdam is the course it was before the sea was round', async () => {
  // Recorded on main 2209a92, 2026-09-14, by the same search over the same raster (4 dp): a
  // course nowhere near the seam, for which the short-way step is bit-for-bit the linear one.
  const BEFORE: [number, number][] = [
    [38.625, -9.625],
    [40.375, -9.875],
    [44.125, -9.375],
    [50.375, -3.125],
    [50.625, 0.625],
    [52.875, 4.375],
  ]
  const nav = await seaNav()
  const course = courseBetweenPorts(nav, portByCode['LIS'], portByCode['AMS'])
  expect(course.length).toBe(BEFORE.length)
  course.forEach(([lat, lon], i) => {
    expect(lat).toBeCloseTo(BEFORE[i][0], 4)
    expect(lon).toBeCloseTo(BEFORE[i][1], 4)
  })
  expect(pathLengthNm(course.map(([lat, lon]) => ({ lat, lon })))).toBeCloseTo(1123.2, 1)
  expect((await serverRefusal(course, portByCode['LIS'], portByCode['AMS'])).ref).toBeNull()
})
