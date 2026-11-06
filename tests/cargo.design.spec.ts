// ═════════════════════════════════════════════════════════════════════════════════════════════════
// CARGO SHIPS YOU CAN SEE — V4 of docs/CITY_CONVOYS.md (owner row 276, 2026-11-05)
// ═════════════════════════════════════════════════════════════════════════════════════════════════
//
//   *"cargo ship? with different graphics. npc like merchants but different."*
//
// Written first, red, then green. It holds: ONE new hull through the one renderer (`hullPath`), heavier
// than any merchant and carrying a crown; a row the server marks `kind: CARGO_SHIP` draws that hull in
// her nation's ink whatever class she sails; cargo ships are never thinned; and A MERCHANT'S ROW, WHICH
// CARRIES NO `kind`, READS EXACTLY AS IT DID: while no cargo ship exists nothing here changes anything.
// The server half (the rows, the card, funds on the way) is proof 20 (scripts/db/proofs/20_cargo_seen.sql).
//
// BROWSER: pictures of the hull at the sizes the map draws it, beside the merchants' hulls, on the chart's
// own sea, in docs/dev-log/2026-11-05-cargo-visible/. A hull is the same CSS size at every zoom (glyphs.ts),
// so "map zoom sizes" are 1× and 2× device pixels; the 2× is the owner's laptop.

import { test, expect } from '@playwright/test'
import { mkdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { CARGO_HULL, GLYPH, HULL_GROUP_MAX, hullGroup, hullHalfLengthOf, hullPath, hullShapeFor, hullShapeOf, registerHullClasses } from '../src/chart/glyphs'
import { mapTrafficOf } from '../src/chart/liveWorld'
import { shipMarks, stableSlot, THIN_MOD, THIN_TIERS } from '../src/chart/shipMarks'
import type { TrafficOnChart } from '../src/chart/chartModel'
import type { TrafficFleet } from '../src/lib/rpc'
import { translateMaybe } from '../src/lib/i18n'

/** The twelve merchant silhouettes, each at its own size: one served class of each shape. */
const MERCHANT_CLASSES = (['fore', 'square'] as const).flatMap((rig) =>
  ([1, 2, 3, 4, 5, 6] as const).map((size) => ({ code: `${rig}${size}`, rig, tier: size, size })),
)

/** The points of an SVG path of M, L and Z only, one list per subpath. */
function subpaths(d: string): [number, number][][] {
  return d
    .split('M')
    .filter(Boolean)
    .map((part) =>
      part
        .replace(/Z/g, '')
        .split('L')
        .map((pair) => pair.trim().split(/\s+/).map(Number) as [number, number]),
    )
}

/** Shoelace, signed: positive runs clockwise on a y-down sheet. */
const signedArea = (pts: readonly [number, number][]) =>
  pts.reduce((sum, [x, y], i) => {
    const [nx, ny] = pts[(i + 1) % pts.length]
    return sum + (x * ny - nx * y) / 2
  }, 0)

const widthOf = (pts: readonly [number, number][]) => Math.max(...pts.map((p) => p[0])) - Math.min(...pts.map((p) => p[0]))
const lengthOf = (pts: readonly [number, number][]) => Math.max(...pts.map((p) => p[1])) - Math.min(...pts.map((p) => p[1]))

/** How much ink a closed hull lays down: her outline less any hole cut by a subpath wound the other way. */
const inkOf = (d: string) => subpaths(d).reduce((sum, pts) => sum + signedArea(pts), 0)

function rowOf(over: Partial<TrafficFleet> & { id: string }): TrafficFleet {
  return {
    company: 'A company',
    nation_code: 'PRT',
    ink: 'prt',
    name: 'A fleet',
    status: 'DOCKED',
    ships: 1,
    hulls: ['nau'],
    port: 'LIS',
    roadstead: [38.7, -9.2],
    anchor: null,
    voyage: null,
    next_lap_at: null,
    lane: null,
    ...over,
  }
}

test.describe('the hull', () => {
  test.beforeAll(() => registerHullClasses(MERCHANT_CLASSES))

  test('she is one more silhouette of the one renderer, and no merchant draws it', () => {
    expect(hullShapeOf(CARGO_HULL)).toBe('cargo')
    const d = hullPath(CARGO_HULL)
    expect(d).not.toBe('')
    for (const c of MERCHANT_CLASSES) {
      expect(hullShapeOf(c.code)).toBe(hullShapeFor(c.rig, c.size))
      expect(hullShapeOf(c.code)).not.toBe('cargo')
      expect(hullPath(c.code)).not.toBe(d)
    }
  })

  test('she is wider, longer and heavier in ink than any ordinary merchant (sizes 1-4; the rare capitals and flagships may outsize her, 2026-11-06)', () => {
    const hull = subpaths(hullPath(CARGO_HULL))[0]
    const ink = inkOf(hullPath(CARGO_HULL))
    for (const c of MERCHANT_CLASSES.filter((m) => m.size <= 4)) {
      const theirs = subpaths(hullPath(c.code))[0]
      expect(widthOf(hull), `wider than ${c.code}`).toBeGreaterThan(widthOf(theirs))
      expect(lengthOf(hull), `longer than ${c.code}`).toBeGreaterThan(lengthOf(theirs))
      expect(ink, `more ink than ${c.code}`).toBeGreaterThan(inkOf(hullPath(c.code)))
    }
    // Wide for her length as no merchant is: the carrack's beam is under 0.6 of her length.
    expect(widthOf(hull) / lengthOf(hull)).toBeGreaterThan(0.65)
  })

  test('the stern is high: she is widest aft, and ends square', () => {
    const hull = subpaths(hullPath(CARGO_HULL))[0]
    const aft = hull.filter(([, y]) => y > 0)
    const fore = hull.filter(([, y]) => y < 0)
    expect(Math.max(...aft.map(([x]) => x))).toBeGreaterThan(Math.max(...fore.map(([x]) => x)))
    const last = Math.max(...hull.map(([, y]) => y))
    expect(hull.filter(([, y]) => y === last).length).toBeGreaterThanOrEqual(2)
  })

  test('no hole in her (W0a): the crown was 5.9 x 5 px at 1x and read as mush; two solid bars name her instead', () => {
    // One subpath: the deck is whole. The mark is a second <path> the renderer draws from the kind table (tests/map.kinds.spec.ts).
    expect(subpaths(hullPath(CARGO_HULL))).toHaveLength(1)
  })

  test('she scales like every hull, and one hull is one mark', () => {
    expect(hullPath(CARGO_HULL, 13)).not.toBe(hullPath(CARGO_HULL))
    const marks = hullGroup([CARGO_HULL], 0.01)
    expect(marks).toHaveLength(1)
    expect(marks[0]).toMatchObject({ cls: CARGO_HULL, dx: 0, dy: 0, halfLength: hullHalfLengthOf(CARGO_HULL) })
    expect(hullHalfLengthOf(CARGO_HULL)).toBeGreaterThan(GLYPH.hullHalfLength[4])
    expect(HULL_GROUP_MAX).toBe(3)
  })

  test('the renderer is not forked: FleetsLayer has one hullPath and never names her hull', () => {
    const src = readFileSync(path.join('src', 'chart', 'FleetsLayer.tsx'), 'utf8')
    expect(src.match(/hullPath\(/g)).toHaveLength(1)
    expect(src).not.toContain('CARGO_HULL')
    expect(src.match(/function HullGroup/g)).toHaveLength(1)
    expect(src.match(/<HullGroup/g)).toHaveLength(2)
  })
})

test.describe('the wire', () => {
  test('a row of kind CARGO_SHIP draws her hull, whatever class she sails', () => {
    const [m] = mapTrafficOf([rowOf({ id: 'cargo-1', kind: 'CARGO_SHIP', hulls: ['qpinnace'], ships: 1 })])
    expect(m.hulls).toEqual([CARGO_HULL])
    expect(m.cargo).toBe(true)
    expect(m.ink).toBe('prt')
  })

  test('a merchant row is read exactly as it was: no key added, no hull moved', () => {
    const [m] = mapTrafficOf([rowOf({ id: 'merchant-1', hulls: ['nau', 'carlat'], ships: 2 })])
    expect(m.hulls).toEqual(['nau', 'carlat'])
    expect('cargo' in m).toBe(false)
  })
})

test.describe('the view', () => {
  const view = { x: 0, y: 0, width: 360, height: 180 }
  const at = { lat: 0, lon: 0 }
  const row = (id: string, cargo: boolean) =>
    ({ at, fleet: { id }, merchant: { ink: 'prt', ...(cargo ? { cargo: true as const } : {}) } }) as unknown as TrafficOnChart
  const dropped = Array.from({ length: 400 }, (_, i) => `ship-${i}`).find((id) => stableSlot(id) >= THIN_TIERS[0].keep)!

  test('the widest view thins a merchant and never a cargo ship', () => {
    expect(THIN_TIERS[0].keep).toBeLessThan(THIN_MOD)
    expect(view.width).toBeGreaterThanOrEqual(THIN_TIERS[0].fromSpanDeg)
    expect(shipMarks([], [row(dropped, false)], view).traffic).toHaveLength(0)
    expect(shipMarks([], [row(dropped, true)], view).traffic).toHaveLength(1)
  })

  test('off the glass she is culled like any ship', () => {
    const away = { ...view, x: 170, width: 20, y: 170, height: 5 }
    expect(shipMarks([], [row(dropped, true)], away).traffic).toHaveLength(0)
  })
})

test.describe('the words', () => {
  const said = (locale: 'en' | 'ko', dict: string, key: string) => translateMaybe(locale, dict as never, key)

  test('the owner\'s three words, EN and KO', () => {
    expect(said('en', 'map', 'cargoShip')).toBe('Cargo ship')
    expect(said('ko', 'map', 'cargoShip')).toBe('화물선')
    expect(said('en', 'map', 'funds')).toBe('Funds')
    expect(said('ko', 'map', 'funds')).toBe('자금')
    expect(said('en', 'map', 'shipment')).toBe('Shipment')
    expect(said('ko', 'map', 'shipment')).toBe('수송')
  })

  test('every new label exists in both tongues, and the hall and Stats have theirs', () => {
    for (const [dict, key] of [['map', 'nextCities'], ['town', 'fundsOnWay'], ['town', 'arrivesIn'], ['town', 'stopsAway'], ['stats', 'fundsAtSea'], ['codex', 'cargoNote']]) {
      expect(said('en', dict, key), `${dict}.${key}`).toBeTruthy()
      expect(said('ko', dict, key), `${dict}.${key}`).toBeTruthy()
    }
  })
})

test.describe('the pictures', () => {
  const OUT = path.join('docs', 'dev-log', '2026-11-05-cargo-visible')
  const css = readFileSync(path.join('src', 'index.css'), 'utf8')
  const token = (name: string): string => {
    const m = css.match(new RegExp(`--color-${name}:\\s*([^;]+);`))
    if (!m) throw new Error(`no token ${name}`)
    const alias = m[1].trim().match(/^var\(--color-([\w-]+)\)$/)
    return alias ? token(alias[1]) : m[1].trim()
  }

  test('the hull at chart size beside the merchants, 1× and 2×', async ({ browser }) => {
    registerHullClasses(MERCHANT_CLASSES)
    mkdirSync(OUT, { recursive: true })
    const sea = token('chart-sea')
    const lines: readonly { label: string; cls: string; ink: string }[] = [
      { label: 'barca', cls: 'fore1', ink: token('merchant') },
      { label: 'carrack (nau)', cls: 'square3', ink: token('merchant') },
      { label: 'galleon', cls: 'square4', ink: token('merchant') },
      { label: 'flagship', cls: 'square6', ink: token('merchant') },
      { label: 'flagship, nation ink', cls: 'square6', ink: token('nation-prt') },
      { label: 'CARGO SHIP', cls: CARGO_HULL, ink: token('nation-prt') },
      { label: 'CARGO SHIP', cls: CARGO_HULL, ink: token('nation-eng') },
      { label: 'CARGO SHIP', cls: CARGO_HULL, ink: token('nation-ott') },
    ]
    const hull = (cls: string, ink: string, turn: number, scale = 1) =>
      `<svg width="${40 * scale}" height="${40 * scale}" viewBox="-20 -20 40 40"><path transform="rotate(${turn})" d="${hullPath(cls)}" fill="${ink}" stroke="${sea}" stroke-width="${GLYPH.glyphStroke * 0.6}" stroke-linejoin="round"/></svg>`
    const html = `<!doctype html><body style="margin:0;background:${sea};color:#d8d2c0;font:12px sans-serif;padding:12px;width:520px">
      <table style="border-collapse:collapse">
      <tr><th align="left">hull</th><th>bow up</th><th>on a course</th><th>4× to read the shape</th></tr>
      ${lines.map((l) => `<tr><td style="padding-right:16px">${l.label}</td><td>${hull(l.cls, l.ink, 0)}</td><td>${hull(l.cls, l.ink, 62)}</td><td>${hull(l.cls, l.ink, 0, 4)}</td></tr>`).join('')}
      </table></body>`
    for (const dpr of [1, 2]) {
      const context = await browser.newContext({ viewport: { width: 560, height: 800 }, deviceScaleFactor: dpr })
      const page = await context.newPage()
      await page.setContent(html)
      await page.screenshot({ path: path.join(OUT, `hulls-${dpr}x.png`), fullPage: true })
      await context.close()
    }
  })
})
