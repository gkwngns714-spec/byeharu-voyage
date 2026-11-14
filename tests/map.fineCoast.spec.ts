import { existsSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { test, expect } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { FINE_COAST_INDEX } from '../src/chart/fineCoast.generated'
import { fineLevelFor, indexLevel, plainTilePaths, shoreOfTiles, tilePaths, tilesCover, tilesOver, type FineLevel } from '../src/chart/fineCoastBuild'
import { LANDFALL_CAP_NM, landfallPoint, onDrawnLand } from '../src/chart/landfall'
import { haversineNm, unproject, type Point } from '../src/lib/geo'
import { MAX_SPAN_X, MIN_SPAN_X, paperOf } from '../src/chart/chartView'
import { buildCoastline, COASTLINE_TOLERANCE_DEG } from '../src/chart/coastlineBuild'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FINE COAST (2026-11-14; docs/dev-log/2026-11-14-fine-coast.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"fix the graphics overall, especially map. it is weird"*. At a harbour the coast was the
// 110m world file: straight lines many kilometres long. Close in, the chart now draws Natural Earth
// 1:10m land from tiles (public/coast/, built by scripts/build-fine-coast.mjs). The laws:
//
//   (1) WHICH LEVEL: none over the wide chart, the middle one from 0.03 degrees a pixel, the fine one
//       from 0.006; the closest zoom is the fine one on a phone and on a desktop.
//   (2) WHICH TILES: exactly the ones under a box, across the antimeridian too.
//   (3) THE SHIPPED TILES ARE WHAT THE INDEX SAYS: every listed tile has a file, every file is listed,
//       an all-land tile has none; every ring stays inside its tile; no tile is heavier than its bound,
//       and the closest view never needs more than a handful.
//   (4) A TILE'S OWN EDGE IS NEVER DRAWN AS A SHORE.
//   (5) IN THE BROWSER: the wide chart fetches no tile; zoomed right in, tiles are fetched and the coast
//       on the glass is no longer the world file's.
//
// (1) to (4) are plain Node. (5) needs a served build: npm run build && npm run preview.

const LEVELS = FINE_COAST_INDEX.levels
const level = (name: string): FineLevel => {
  const found = LEVELS.find((l) => l.name === name)
  if (!found) throw new Error(`no level ${name}`)
  return found
}
const TILE_DIR = path.join(process.cwd(), 'public', 'coast')

/** No tile may be heavier than this, uncompressed (the heaviest built is under 30 KB). */
const TILE_BYTES_MAX = 40_000

test.describe('the fine coast: levels and tiles', () => {
  test('(1) the wide chart has no level; the closest zoom is the fine one on every glass', () => {
    expect(fineLevelFor(LEVELS, 360 / 1280)).toBeNull()
    expect(fineLevelFor(LEVELS, 40 / 390)).toBeNull()
    // the mid level's loosest zoom: 0.03 until 2026-11-15, now 0.045 (the owner: "when i zoom out, the details of the map
    // disappears, make it so that it stays as long as possible"; its 0.03 degree tolerance is still 0.67 px there)
    expect(fineLevelFor(LEVELS, 0.046)).toBeNull()
    expect(fineLevelFor(LEVELS, 0.045)?.name).toBe('mid')
    expect(fineLevelFor(LEVELS, 0.031)?.name).toBe('mid')
    expect(fineLevelFor(LEVELS, 0.0061)?.name).toBe('mid')
    expect(fineLevelFor(LEVELS, 0.006)?.name).toBe('fine')
    expect(fineLevelFor(LEVELS, MIN_SPAN_X / 390)?.name).toBe('fine')
    expect(fineLevelFor(LEVELS, MIN_SPAN_X / 1280)?.name).toBe('fine')
    expect(fineLevelFor(LEVELS, 0)).toBeNull()
  })

  test('(2) the tiles under a box, and across the antimeridian', () => {
    const fine = level('fine')
    // Lisbon, a phone's closest view: one 5 degree tile (longitude -10 to -5, latitude 35 to 40).
    expect(tilesOver(fine, { x: -9.9, y: -39.5, width: 1.5, height: 3.2 })).toEqual(['34_25'])
    // a box over two columns and two rows
    expect(tilesOver(fine, { x: -11, y: -41, width: 2, height: 2 }).sort()).toEqual(['33_25', '33_26', '34_25', '34_26'])
    // across the seam: the last column and the first, named on the base world
    expect(tilesOver(fine, { x: 178, y: -2, width: 4, height: 1 }).sort()).toEqual(['0_18', '71_18'])
    expect(tilesOver(fine, { x: -182, y: -2, width: 4, height: 1 }).sort()).toEqual(['0_18', '71_18'])
    // a box as wide as the world names every column once
    expect(tilesOver(level('mid'), { x: -200, y: -10, width: 400, height: 5 })).toHaveLength(18)
    // cover: a set covers a box inside it and not one beyond it
    const ids = new Set(tilesOver(fine, { x: -11, y: -41, width: 2, height: 2 }))
    expect(tilesCover(fine, ids, { x: -10.5, y: -40.5, width: 1, height: 1 })).toBe(true)
    expect(tilesCover(fine, ids, { x: -5.5, y: -40.5, width: 1, height: 1 })).toBe(false)
  })

  test('(2b) the closest view needs only a handful of fine tiles', () => {
    const fine = level('fine')
    // the loosest zoom the fine level is drawn at, on a 1,280 by 800 glass: the wide sheet is 1.5 views
    const width = fine.maxUnitsPerPx * 1280
    const sheet = paperOf({ x: 3.1, y: -47.3, width, height: (width * 800) / 1280 })
    expect(tilesOver(fine, sheet).length).toBeLessThanOrEqual(12)
    const close = paperOf({ x: 3.1, y: -47.3, width: MIN_SPAN_X, height: (MIN_SPAN_X * 800) / 1280 })
    expect(tilesOver(fine, close).length).toBeLessThanOrEqual(4)
  })

  for (const l of LEVELS) {
    test(`(3) ${l.name}: the shipped tiles are the index, each inside its tile and its bound`, () => {
      const listed = l.tiles.split(' ').filter(Boolean)
      const full = new Set(l.full.split(' ').filter(Boolean))
      const onDisk = readdirSync(path.join(TILE_DIR, l.name)).map((f) => f.replace(/\.json$/, '')).sort()
      expect(onDisk).toEqual([...listed].sort())
      for (const id of full) expect(existsSync(path.join(TILE_DIR, l.name, `${id}.json`)), `${id} is all land and has no file`).toBe(false)
      const kindOf = indexLevel(l).kindOf
      const side = Math.round(l.tileDeg / l.quantum)
      let heaviest = 0
      let total = 0
      for (const id of listed) {
        expect(kindOf(id)).toBe('file')
        const text = readFileSync(path.join(TILE_DIR, l.name, `${id}.json`), 'utf8')
        heaviest = Math.max(heaviest, text.length)
        total += text.length
        const rings = JSON.parse(text) as number[][]
        expect(rings.length, `${l.name}/${id} holds land`).toBeGreaterThan(0)
        for (const ring of rings) {
          let x = 0
          let y = 0
          for (let i = 0; i < ring.length; i += 2) {
            x += ring[i]
            y += ring[i + 1]
            if (x < 0 || x > side || y < 0 || y > side) throw new Error(`${l.name}/${id}: a point outside the tile (${x}, ${y})`)
          }
        }
        const paths = tilePaths(l, id, rings)
        expect(paths.d.length, `${l.name}/${id} has a body`).toBeGreaterThan(0)
      }
      expect(heaviest, `the heaviest ${l.name} tile, in bytes`).toBeLessThan(TILE_BYTES_MAX)
      console.log(`${l.name}: ${listed.length} tiles, ${full.size} all land, ${total} bytes, heaviest ${heaviest}`)
    })
  }

  test('(4) a tile\'s own edge is never a shore; an island inside is one closed run', () => {
    const l: FineLevel = { name: 't', tolerance: 0.01, tileDeg: 10, quantum: 0.01, maxUnitsPerPx: 1, tiles: '18_9', full: '' }
    // tile 18_9: longitude 0 to 10, latitude 0 to 10, so chart x 0 to 10 and y -10 to 0.
    // Land in the west half, cut along the tile's west, north and south edges; its east side is the shore.
    const west = [0, 0, 500, 0, 0, 1000, -500, 0]
    const paths = tilePaths(l, '18_9', [west])
    expect(paths.d).toBe('M0 -10L5 -10L5 0L0 0Z')
    expect(paths.coastD).toBe('M5 -10L5 0')
    // an island that touches no edge is the same ring, closed
    const island = tilePaths(l, '18_9', [[200, 200, 100, 0, 0, 100]])
    expect(island.d).toBe('M2 -8L3 -8L3 -7Z')
    expect(island.coastD).toBe('M2 -8L3 -8L3 -7Z')
    // all land: the square and no line; sea: nothing; rubbish: nothing, never a throw
    expect(plainTilePaths(l, '18_9', 'land')).toMatchObject({ d: 'M0 -10L10 -10L10 0L0 0Z', coastD: '' })
    expect(plainTilePaths(l, '18_9', 'sea')).toEqual({ d: '', coastD: '', rings: [] })
    expect(tilePaths(l, '18_9', { nope: true })).toEqual({ d: '', coastD: '', rings: [] })
    expect(tilePaths(l, '18_9', [[1, 2, 'x', 4, 5, 6], [1, 2, 3]])).toEqual({ d: '', coastD: '', rings: [] })
    // the rings the landfall reads are the body's own points
    expect(paths.rings).toEqual([[{ x: 0, y: -10 }, { x: 5, y: -10 }, { x: 5, y: 0 }, { x: 0, y: 0 }]])
  })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE GUARD: THE ZOOM MAY NEVER OUTRUN THE COAST AGAIN
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"find the root cause, make it so that this problem does not occur again"*. The cause
// (the dev-log has it whole): commit 600d0fb3 set the coast's tolerance (0.2 degrees, tuned at the
// opening view) and the closest zoom (1.5 degrees, tuned for names) as two unrelated numbers. At
// that zoom 0.2 degrees is 52 pixels on a phone and 171 on a desktop, and nothing related the two.
// These two laws relate them, on the real data, in plain Node:
//
//   (6) AT EVERY ZOOM THE MAP ALLOWS, ON EVERY GLASS, the data that is drawn there was simplified by
//       no more than COAST_ERROR_PX_MAX pixels. Move MIN_SPAN_X closer, coarsen a level, or move a
//       level's limit, and this fails.
//   (7) AT THE CLOSEST ZOOM, NEAR A HARBOUR, no drawn stretch of shore is one straight line longer
//       than COAST_SEGMENT_PX_MAX pixels, measured at Lisbon, Nagasaki and Venice on a 1,280 pixel
//       glass. The 110m world file is measured by the same ruler and must FAIL it, so the ruler is
//       known to see the fault it is there for.

/** The most the drawn coast may have been simplified by, in CSS pixels, at any zoom on any glass. */
const COAST_ERROR_PX_MAX = 8
/** The longest single straight stretch of shore near a harbour at the closest zoom, in CSS pixels. */
const COAST_SEGMENT_PX_MAX = 200
/** How near "near a harbour" is, in CSS pixels at the closest zoom. */
const NEAR_HARBOUR_PX = 250
/** The glasses the chart is drawn on, by width in CSS pixels: a small phone to a 4K desktop. */
const GLASS_WIDTHS = [320, 390, 768, 1280, 1920, 2560, 3840]
const GUARD_HARBOURS = [
  { name: 'Lisbon', lon: -9.139016, lat: 38.708042 },
  { name: 'Nagasaki', lon: 129.879639, lat: 32.749528 },
  { name: 'Venice', lon: 12.331944, lat: 45.439722 },
]

/** Every straight stretch of an SVG `d` made of M, L and Z, as [x1, y1, x2, y2]. */
function segmentsOf(d: string): [number, number, number, number][] {
  const out: [number, number, number, number][] = []
  for (const sub of d.split('M')) {
    if (sub === '') continue
    const closed = sub.endsWith('Z')
    const pts = sub.replace('Z', '').split('L').map((p) => p.trim().split(' ').map(Number))
    for (let i = 1; i < pts.length; i++) out.push([pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1]])
    if (closed && pts.length > 2) out.push([pts[pts.length - 1][0], pts[pts.length - 1][1], pts[0][0], pts[0][1]])
  }
  return out
}

/** The longest stretch of `d` that passes within `nearDeg` of a point, in degrees (0 when none does). */
function longestNear(d: string, at: { x: number; y: number }, nearDeg: number): number {
  let longest = 0
  for (const [x1, y1, x2, y2] of segmentsOf(d)) {
    const dx = x2 - x1
    const dy = y2 - y1
    const len2 = dx * dx + dy * dy
    const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((at.x - x1) * dx + (at.y - y1) * dy) / len2))
    if (Math.hypot(x1 + t * dx - at.x, y1 + t * dy - at.y) > nearDeg) continue
    longest = Math.max(longest, Math.sqrt(len2))
  }
  return longest
}

/** The fine level's shore over a box, from the shipped tiles. */
function shippedLine(l: FineLevel, box: { x: number; y: number; width: number; height: number }): string {
  const kindOf = indexLevel(l).kindOf
  let line = ''
  for (const id of tilesOver(l, box)) {
    if (kindOf(id) !== 'file') continue
    line += tilePaths(l, id, JSON.parse(readFileSync(path.join(TILE_DIR, l.name, `${id}.json`), 'utf8'))).coastD
  }
  return line
}

test.describe('the guard: the zoom never outruns the coast', () => {
  test('(6) at every zoom on every glass, the drawn coast was simplified by a few pixels at most', () => {
    let worst = { px: 0, where: '' }
    for (const width of GLASS_WIDTHS) {
      // every zoom from the closest to the whole world, in steps of 2 %
      for (let span = MIN_SPAN_X; span <= MAX_SPAN_X; span *= 1.02) {
        const unitsPerPx = span / width
        const drawn = fineLevelFor(LEVELS, unitsPerPx)
        const tolerance = drawn ? drawn.tolerance : COASTLINE_TOLERANCE_DEG
        const px = tolerance / unitsPerPx
        if (px > worst.px) worst = { px, where: `${drawn ? drawn.name : '110m'} at ${span.toFixed(2)} degrees across ${width} px` }
      }
    }
    console.log(`the coast's worst simplification on the glass: ${worst.px.toFixed(1)} px (${worst.where})`)
    expect(worst.px, `the coast is simplified by ${worst.px.toFixed(1)} px: ${worst.where}`).toBeLessThanOrEqual(COAST_ERROR_PX_MAX)
    // and the ruler sees the old fault: the 110m file alone, at the closest zoom, is far over the bound
    expect(COASTLINE_TOLERANCE_DEG / (MIN_SPAN_X / 390)).toBeGreaterThan(COAST_ERROR_PX_MAX * 5)
  })

  test('(7) at the closest zoom no shore near a harbour is one long straight line', () => {
    const glass = 1280
    const unitsPerPx = MIN_SPAN_X / glass
    const drawn = fineLevelFor(LEVELS, unitsPerPx)
    expect(drawn, 'the closest zoom is drawn from a fine level').not.toBeNull()
    const world = buildCoastline(JSON.parse(readFileSync(path.join(process.cwd(), 'data', 'world-110m.json'), 'utf8')))
    const near = NEAR_HARBOUR_PX * unitsPerPx
    for (const harbour of GUARD_HARBOURS) {
      const at = { x: harbour.lon, y: -harbour.lat }
      const box = { x: at.x - near, y: at.y - near, width: 2 * near, height: 2 * near }
      const fine = longestNear(shippedLine(drawn as FineLevel, box), at, near) / unitsPerPx
      const old = longestNear(world.coastD, at, near) / unitsPerPx
      console.log(`${harbour.name}: longest straight shore within ${NEAR_HARBOUR_PX} px: ${fine.toFixed(0)} px drawn, ${old.toFixed(0)} px in the 110m file`)
      expect(fine, `${harbour.name} has a shore near it`).toBeGreaterThan(0)
      expect(fine, `${harbour.name}: a straight shore ${fine.toFixed(0)} px long at the closest zoom`).toBeLessThanOrEqual(COAST_SEGMENT_PX_MAX)
      // the same ruler on the 110m file: where it has a shore this near at all, it is over the bound
      if (old > 0) expect(old).toBeGreaterThan(COAST_SEGMENT_PX_MAX)
    }
  })
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE HARBOURS STAND ON THE SHORE THAT IS DRAWN (2026-11-14; docs/dev-log/2026-11-14-harbours-onshore.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A harbour's mark is set on the drawn shore by the landfall (src/chart/landfall.ts). While the only
// coast was the 110m world that was one answer; with the fine coast on the glass a mark left on the
// 110m shore stood miles off it (Tainan 8 nm inland, Ceuta 2.5 nm out at sea). The landfall is now
// run against the coast in hand. The law, on the real ports and the shipped tiles, in plain Node:
//
//   (8) AT THE CLOSEST ZOOM every harbour whose fine shore is within the landfall's cap is drawn
//       within HARBOUR_OFFSHORE_PX_MAX pixels of it, on land; and the harbours beyond the cap are
//       exactly the named list below (river cities), so a new one is a decision and not a surprise.

/** How far from the drawn shore a harbour's mark may stand at the closest zoom, in CSS pixels on a
 *  1,280 px glass. The landfall sets a mark 0.005 degrees inside the shore, which is 4.3 px there. */
const HARBOUR_OFFSHORE_PX_MAX = 8
/** THE RIVER CITIES: harbours whose true place is further than the cap from the fine shore. They
 *  are drawn where the data puts them, inland. Add a name here only by deciding it belongs here. */
const BEYOND_THE_CAP = [
  'Amsterdam',
  'Ayutthaya',
  'Basra',
  'Hanoi',
  'Hooghly',
  'Hoorn',
  'Kaliningrad',
  'London',
  'Ningbo',
  'Pustozersk',
  'Rotterdam',
  'Seville',
]

test.describe('the harbours stand on the drawn shore', () => {
  test('(8) at the closest zoom every harbour within the cap is on the fine shore; the rest are named', () => {
    const fine = level('fine')
    const kindOf = indexLevel(fine).kindOf
    const cache = new Map<string, readonly (readonly Point[])[]>()
    const ringsOf = (id: string) => {
      let rings = cache.get(id)
      if (!rings) {
        const kind = kindOf(id)
        rings = kind === 'file' ? tilePaths(fine, id, JSON.parse(readFileSync(path.join(TILE_DIR, fine.name, `${id}.json`), 'utf8'))).rings : plainTilePaths(fine, id, kind).rings
        cache.set(id, rings)
      }
      return rings
    }
    // every tile is "held": the whole world's fine shore
    const everywhere = { has: () => true } as unknown as ReadonlySet<string>
    const shore = shoreOfTiles(fine, everywhere, ringsOf)
    const world = buildCoastline(JSON.parse(readFileSync(path.join(process.cwd(), 'data', 'world-110m.json'), 'utf8')))
    const ports = (JSON.parse(readFileSync(path.join(process.cwd(), 'data', 'ports.json'), 'utf8')) as { ports: { name: string; lat: number; lon: number }[] }).ports
    const unitsPerPx = MIN_SPAN_X / 1280

    /** How far a point is from the fine shore: on the glass in pixels, and over the ground in miles. */
    const offShore = (p: Point): { px: number; nm: number } => {
      let best = Infinity
      let at = p
      for (const ring of shore.ringsNear(p) ?? []) {
        for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
          const a = ring[j]
          const b = ring[i]
          if (shore.isCut?.(a, b)) continue
          const dx = b.x - a.x
          const dy = b.y - a.y
          const len2 = dx * dx + dy * dy
          const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
          const d = Math.hypot(a.x + t * dx - p.x, a.y + t * dy - p.y)
          if (d < best) {
            best = d
            at = { x: a.x + t * dx, y: a.y + t * dy }
          }
        }
      }
      return { px: best / unitsPerPx, nm: best === Infinity ? Infinity : haversineNm(unproject(p), unproject(at)) }
    }

    const beyond: string[] = []
    const table: string[] = []
    let moved = 0
    let worst = { px: 0, name: '' }
    let worstBefore = { px: 0, name: '' }
    let farBefore = 0
    for (const port of ports) {
      const served = { x: port.lon, y: -port.lat }
      const rings = shore.ringsNear(served) ?? []
      const truth = offShore(served)
      // where the mark stood: on the 110m shore
      const before = offShore(landfallPoint(world.rings, served).at)
      // where it stands now: on the coast in hand
      const landed = landfallPoint(rings, served, shore)
      const after = offShore(landed.at)
      if (landed.moved) moved++
      if (truth.nm > LANDFALL_CAP_NM) {
        beyond.push(port.name)
        expect(landed.moved, `${port.name} is beyond the cap and stays where the data puts it`).toBe(false)
        continue
      }
      if (before.px > HARBOUR_OFFSHORE_PX_MAX) farBefore++
      if (before.px > worstBefore.px) worstBefore = { px: before.px, name: port.name }
      if (after.px > worst.px) worst = { px: after.px, name: port.name }
      if (/^(Tainan|Tripoli|Algiers|Ternate|Ceuta|Lisbon|Nagasaki|Venice)$/.test(port.name)) {
        table.push(`${port.name}: ${before.px.toFixed(0)} px before (${before.nm.toFixed(1)} nm), ${after.px.toFixed(1)} px now`)
      }
      expect(after.px, `${port.name} stands ${after.px.toFixed(0)} px from the drawn shore at the closest zoom`).toBeLessThanOrEqual(HARBOUR_OFFSHORE_PX_MAX)
      expect(onDrawnLand(rings, landed.at), `${port.name} stands on drawn land`).toBe(true)
    }
    console.log(table.join('\n'))
    console.log(
      `${ports.length} harbours: ${moved} set on the fine shore by the landfall, ${beyond.length} beyond the cap; ` +
        `further than ${HARBOUR_OFFSHORE_PX_MAX} px before: ${farBefore} (worst ${worstBefore.name}, ${worstBefore.px.toFixed(0)} px); worst now ${worst.name}, ${worst.px.toFixed(1)} px`,
    )
    expect(beyond.sort()).toEqual([...BEYOND_THE_CAP].sort())
  })
})

test.describe('the fine coast: on the glass', () => {
  for (const glass of [
    { name: 'phone', size: { width: 390, height: 844 } },
    { name: 'desktop', size: { width: 1280, height: 800 } },
  ]) {
    test(`(5) ${glass.name}: no tile over the wide chart; tiles and a finer coast at the closest zoom`, async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      await page.setViewportSize(glass.size)
      const tiles: { url: string; status: number }[] = []
      page.on('response', (r) => {
        if (/\/coast\/(mid|fine)\//.test(r.url())) tiles.push({ url: r.url(), status: r.status() })
      })
      await page.goto('map')
      await ready(page)
      const coast = page.getByTestId('map-coastline').first()
      await expect(coast).toBeAttached()
      const press = async (label: string, n: number) => {
        for (let i = 0; i < n; i++) {
          await page.evaluate((l) => (document.querySelector(`[aria-label="${l}"]`) as HTMLElement).click(), label)
          await page.waitForTimeout(80)
        }
        await page.waitForTimeout(800)
      }
      const zoom = async () => Number(((await page.getByTestId('map-zoom-percent').textContent()) ?? '').replace(/[^0-9]/g, ''))

      // furthest out: the 110m world, and nothing fetched for it
      await press('Zoom out', 14)
      const worldD = (await coast.getAttribute('d')) ?? ''
      expect(worldD.length).toBeGreaterThan(10_000)
      const atWide = tiles.length
      await page.waitForTimeout(500)
      expect(tiles.length, 'the wide chart fetches no tile').toBe(atWide)
      expect(tiles.filter((t) => /\/fine\//.test(t.url)), 'no fine tile before the chart is close').toHaveLength(0)

      // right in
      await press('Zoom in', 16)
      expect(await zoom()).toBe(100)
      await expect.poll(async () => (await coast.getAttribute('d')) !== worldD, { timeout: 15_000 }).toBe(true)
      const fine = tiles.filter((t) => /\/fine\//.test(t.url))
      expect(fine.length, 'fine tiles were fetched').toBeGreaterThan(0)
      expect(tiles.filter((t) => t.status !== 200), 'every tile asked for exists').toHaveLength(0)
      // the line is drawn from the same tiles as the body
      const line = (await page.getByTestId('map-coast').first().getAttribute('d')) ?? ''
      expect(line.length).toBeGreaterThan(0)

      // and back out: the world file again
      await press('Zoom out', 16)
      await expect.poll(async () => (await coast.getAttribute('d')) === worldD, { timeout: 15_000 }).toBe(true)
    })
  }
})
