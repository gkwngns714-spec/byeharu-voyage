import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import {
  ALL_NAMES_FULL_SPAN,
  buildChartModel,
  DOT_SPAN_DEG,
  GLYPH,
  LABEL_PRIORITY,
  LABEL_SPAN_LIMIT,
  mapLabelRequests,
  mapPortsOf,
  minTierForSpan,
  planLabels,
  SEA_NAME_SPAN_LIMIT,
  visiblePorts,
  type PlacedLabel,
} from '../src/chart'
import { REAL_PORTS } from './mapWorld.fixture'
import type { ViewBox } from '../src/lib/geo'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DETAIL STAYS AS THE GLASS PULLS BACK, AND THE NAMES ARE BIGGER (2026-11-15;
// docs/dev-log/2026-11-15-map-detail.md).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"in map, when i zoom out, the details of the map disappears, make it so that it stays as long as possible.
// the names of the cities as well as regions, countries, flags, should be bigger, city icon slightly bigger."*
//
//   (1) NO ZOOM CUT-OFF ON A NAME. Every harbour that wears its full mark asks for its name at every span, and the seas'
//       names are asked for at every span; the planner (src/chart/labels.ts) hides a name only when it would touch
//       another name or a mark, in the priority order (yours, then the capitals, then by size).
//   (2) THE SIZES: a city's name 13 px (was 10.5), a great harbour's 15 (12), a region's 16 (13); the flag is in ems of the
//       name, so it grew with it; the city's mark is drawn 1.12× the ramp and its dot is 1.8 px (1.6).
//   (3) A CAPITAL'S NAME, OR AT LEAST ITS FLAG: where a capital's name cannot be set, its flag alone is tried.
//   (4) ON THE RUNNING GAME, furthest out on a phone and on a desktop: at least MIN_NAMES harbour names and a floor of
//       flags, every capital on the glass set (its name and flag, or its flag alone), and no two names overlap.

const CAPITALS = new Map([
  ['LIS', 'PRT'], ['SVQ', 'ESP'], ['MRS', 'FRA'], ['LON', 'ENG'], ['AMS', 'NLD'], ['COP', 'DNK'], ['STO', 'SWE'],
  ['GDA', 'POL'], ['ARK', 'RUS'], ['HAM', 'HAN'], ['VEN', 'VEN'], ['GOA', 'GEN'], ['IST', 'OTT'],
])
const PORTS = mapPortsOf(REAL_PORTS, CAPITALS)
const overlaps = (a: PlacedLabel, b: PlacedLabel) =>
  a.box.x < b.box.x + b.box.width && b.box.x < a.box.x + a.box.width && a.box.y < b.box.y + b.box.height && b.box.y < a.box.y + a.box.height

test('(1) no span limit on a name: every full harbour and every sea asks, and the middling harbours are full at every span', () => {
  expect(LABEL_SPAN_LIMIT).toBe(Number.POSITIVE_INFINITY)
  expect(SEA_NAME_SPAN_LIMIT).toBe(Number.POSITIVE_INFINITY)
  expect(minTierForSpan(360)).toBe(3)
  expect(minTierForSpan(ALL_NAMES_FULL_SPAN)).toBe(1)
  expect(minTierForSpan(ALL_NAMES_FULL_SPAN * 1.01)).toBe(3)
  expect(DOT_SPAN_DEG).toBe(180)
})

test('(2) the names and the marks are bigger', () => {
  expect(GLYPH.labelSize).toBe(13)
  expect(GLYPH.greatLabelSize).toBe(15)
  expect(GLYPH.regionNameSize).toBe(16)
  expect(GLYPH.markGrowth).toBeCloseTo(1.12, 9)
  expect(GLYPH.portDotRadius).toBeCloseTo(1.8, 9)
  // a harbour's light did not grow with its dot
  expect(GLYPH.portDotRadius * GLYPH.harbourLightHaloScale).toBeCloseTo(1.6 * 9, 6)
})

test('(3) a capital asks above every other quiet harbour, and keeps at least its flag where its name will not go', () => {
  expect(LABEL_PRIORITY.capital).toBeGreaterThan(LABEL_PRIORITY.quiet + 5)
  expect(LABEL_PRIORITY.capital).toBeLessThan(LABEL_PRIORITY.route)
  // the whole world on a 1920 px glass: Europe's corner holds more capitals than its names can be set for
  const view: ViewBox = { x: -180, y: -90, width: 360, height: 187.5 }
  const upp = 360 / 1920
  const model = buildChartModel([], PORTS)
  const drawn = visiblePorts(PORTS, model.portRoles, view, minTierForSpan(view.width))
  // every other harbour held by one nation; the capitals by none, so each must fall back to its own nation's flag
  const flags = new Map(PORTS.filter((p) => !p.capital).map((p) => [p.code, 'POR']))
  const placed = planLabels(mapLabelRequests(model, drawn, null, true, flags), {
    viewBox: view,
    unitsPerPx: upp,
    fontSizePx: GLYPH.labelSize,
    gapPx: GLYPH.labelGapX,
    glyphRadiusPx: GLYPH.fleetHaloRadius,
    centredOnMark: true,
  })
  for (let i = 0; i < placed.length; i++) for (let j = i + 1; j < placed.length; j++) expect(overlaps(placed[i], placed[j]), `${placed[i].text} / ${placed[j].text}`).toBe(false)
  const byId = new Map(placed.map((l) => [l.id, l]))
  for (const port of PORTS.filter((p) => p.capital)) expect(byId.get(`port:${port.code}`)?.flag, `${port.name}'s flag`).toBe(port.capital)
  // non-vacuous: at least one capital is down to its flag alone here, and many more harbours are named than the 35 great ones
  expect(placed.filter((l) => l.text === '' && l.flag).length).toBeGreaterThan(0)
  expect(placed.filter((l) => l.id.startsWith('port:') && l.text !== '').length).toBeGreaterThan(35)
})

// ── (4) the running game, furthest out ──────────────────────────────────────────────────────────
/** MEASURED 2026-11-15 on the after pictures (docs/dev-log/2026-11-15-map-detail.md): furthest out the phone set 9 harbour
 *  names and 10 flags (4 / 4 before), the 1920 desktop 56 names and 35 flags (23 / 19 before). The floors leave room for the
 *  world's own drift (ships, and their names, move). */
const MIN_NAMES = { phone: 7, desktop: 40 } as const

async function widest(page: Page) {
  const button = page.getByTestId('map-view-controls').locator('button').nth(1)
  for (let i = 0; i < 16; i++) {
    await button.click()
    await page.waitForTimeout(100)
  }
  let last = ''
  await expect
    .poll(async () => {
      await page.waitForTimeout(200)
      const now = (await page.getByTestId('map-view').getAttribute('viewBox')) ?? ''
      const still = now === last
      last = now
      return still
    })
    .toBe(true)
  await page.waitForTimeout(500)
}

const seen = (page: Page) =>
  page.evaluate(() => {
    type Box = { x: number; y: number; w: number; h: number; name: string }
    const box = (e: Element, name: string): Box => {
      const r = e.getBoundingClientRect()
      return { x: r.x, y: r.y, w: r.width, h: r.height, name }
    }
    // a name is its letters and its flag; a capital's flag alone is its flag
    const names: Box[] = []
    for (const g of document.querySelectorAll('[data-testid="map-labels"] > *')) {
      const text = g.tagName === 'text' ? g : g.querySelector('text')
      const flag = g.querySelector('[data-testid="map-label-flag"]')
      const parts = [text, flag].filter((e): e is Element => e !== null).map((e) => box(e, text?.textContent ?? '(flag)'))
      if (parts.length === 0) continue
      const x = Math.min(...parts.map((p) => p.x))
      const y = Math.min(...parts.map((p) => p.y))
      names.push({ x, y, w: Math.max(...parts.map((p) => p.x + p.w)) - x, h: Math.max(...parts.map((p) => p.y + p.h)) - y, name: parts[0].name })
    }
    const ports = document.querySelectorAll('[data-testid="map-labels"] text[data-label-id^="port:"]').length
    // every harbour the plan set, by its name or (a capital) by its flag alone
    const labelled = new Set(
      [...document.querySelectorAll('[data-testid="map-labels"] [data-label-id^="port:"]')].map((e) => (e.getAttribute('data-label-id') ?? '').slice(5)),
    )
    const flagged = [...document.querySelectorAll('[data-testid="map-labels"] [data-label-flag]')].length
    const glass = document.querySelector('[data-testid="map-chart"]')!.getBoundingClientRect()
    const chrome = [...document.querySelectorAll('[data-chart-chrome]')].map((c) => c.getBoundingClientRect())
    // the capitals whose mark is well inside the glass and clear of the chrome (a name may not be set under a button)
    const capitals = [...document.querySelectorAll('[data-testid="map-ports"] [data-port-capital="yes"]')].flatMap((g) => {
      const r = g.querySelector('circle, path')!.getBoundingClientRect()
      const cx = r.x + r.width / 2
      const cy = r.y + r.height / 2
      const inside = cx > glass.x + 40 && cx < glass.right - 40 && cy > glass.y + 40 && cy < glass.bottom - 40
      const clear = chrome.every((c) => cx < c.x - 40 || cx > c.right + 40 || cy < c.y - 40 || cy > c.bottom + 40)
      return inside && clear ? [g.getAttribute('data-port-code') ?? ''] : []
    })
    return { names, ports, labelled: [...labelled], flagged, capitals }
  })

for (const glass of [
  { tag: 'phone', width: 390, height: 844, dsf: 2, touch: true, min: MIN_NAMES.phone, minFlags: 6 },
  { tag: 'desktop', width: 1920, height: 1000, dsf: 1, touch: false, min: MIN_NAMES.desktop, minFlags: 25 },
]) {
  test.describe(`(4) furthest out on the ${glass.tag} (${glass.width}x${glass.height})`, () => {
    test.use({ viewport: { width: glass.width, height: glass.height }, deviceScaleFactor: glass.dsf, hasTouch: glass.touch, locale: 'en-US' })
    test('enough names, every capital on the glass flagged, and no two names overlap', async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(420_000)
      await page.goto('map')
      await ready(page)
      await page.waitForSelector('[data-testid="map-ports"] > g')
      await page.evaluate(() => document.fonts.ready)
      await widest(page)
      const s = await seen(page)
      const clash: string[] = []
      const hits = (a: (typeof s.names)[number], b: (typeof s.names)[number]) => a.x + 2 < b.x + b.w && b.x + 2 < a.x + a.w && a.y + 2 < b.y + b.h && b.y + 2 < a.y + a.h
      for (let i = 0; i < s.names.length; i++) for (let j = i + 1; j < s.names.length; j++) if (hits(s.names[i], s.names[j])) clash.push(`${s.names[i].name} / ${s.names[j].name}`)
      console.log(`${glass.tag} furthest out: ${s.ports} harbour names, ${s.flagged} flags, capitals on the glass ${s.capitals.join(' ')}`)
      expect(clash, 'names overlap furthest out').toEqual([])
      expect(s.ports, 'harbour names furthest out').toBeGreaterThanOrEqual(glass.min)
      expect(s.capitals.length, 'non-vacuous: capitals on the glass').toBeGreaterThan(0)
      // every capital on the glass is set: by its name and flag, or by its flag alone where its name does not fit (a capital
      // the world's allegiance gives no holder has no flag to draw, and is set by its name; the plan's own law (3) above
      // proves a held capital keeps its flag at the widest desktop view)
      const labelled = new Set(s.labelled)
      expect(s.capitals.filter((c) => !labelled.has(c)), 'capitals not set furthest out').toEqual([])
      expect(s.flagged, 'flags furthest out').toBeGreaterThanOrEqual(glass.minFlags)
    })
  })
}
