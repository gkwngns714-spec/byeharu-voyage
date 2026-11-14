import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import { reachable, ready, WORLD_BOOT_MS } from './appReady.fixture'
import { serveLitSeas } from './seasLit.fixture'
import { MAP_LAYER_KEY, readMapLayer, REGIONS_FILTER_KEY, zoneAnchors, zoneOutline } from '../src/chart'
import type { ZoneCells } from '../src/domain/seas'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP'S FILTER: OFF, REGIONS, SEAS (owner, 2026-11-15: "also in map, make filter, like regions, no in regions,
// have option to see seas, showing waves, requirement to pass etc.").
//
// Pure: the borders are traced only between two zones (never along a shore), a cut on a meridian stays one straight
// line, and a zone's name stands in its deepest water. The kept choice reads the old Regions switch.
//
// Browser (the lit world, seasLit.fixture.ts: a title-1 barca at Lisbon, Europe open, the rest closed): the filter
// offers three choices, one at a time; Seas draws the borders and N zone names each with its ask, a closed zone is
// marked, the water names give way; a press on the water opens that sea's tray; the choice survives a reload. Phone
// 390 and 320, desktop, EN and KO; the chrome covers none of itself; screenshots to SEAS_SHOTS.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** A 8 x 4 raster at 1 degree: zone A west of column 4, zone B east, land in the top-left corner. */
function raster(): ZoneCells {
  const cols = 8
  const rows = 4
  const cells = new Uint8Array(cols * rows)
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) cells[r * cols + c] = c < 4 ? 1 : 2
  cells[0] = 0
  return { cols, rows, cellDeg: 1, cells, codes: [null, 'A', 'B'] }
}

test.describe('the sea zones, drawn from the raster', () => {
  test('one straight border between two zones, none along the shore', () => {
    const d = zoneOutline(raster())
    // one line, on the meridian between columns 3 and 4 (lon -176), top to bottom
    expect(d.match(/M/g)?.length).toBe(1)
    const xs = [...d.matchAll(/[ML](-?[\d.]+) (-?[\d.]+)/g)].map((m) => Number(m[1]))
    expect(new Set(xs)).toEqual(new Set([-176]))
  })
  test('a name stands inside its own zone', () => {
    const at = zoneAnchors(raster())
    expect(at.get('A')![0].lon).toBeLessThan(-176)
    expect(at.get('B')![0].lon).toBeGreaterThan(-176)
  })
  test('the kept choice: the new key, else the old Regions switch, else off', () => {
    const store = (o: Record<string, string>) => (k: string) => o[k] ?? null
    expect(readMapLayer(store({}))).toBe('off')
    expect(readMapLayer(store({ [REGIONS_FILTER_KEY]: '1' }))).toBe('regions')
    expect(readMapLayer(store({ [MAP_LAYER_KEY]: 'seas', [REGIONS_FILTER_KEY]: '1' }))).toBe('seas')
    expect(readMapLayer(store({ [MAP_LAYER_KEY]: 'nonsense' }))).toBe('off')
    expect(
      readMapLayer(() => {
        throw new Error('refused')
      }),
    ).toBe('off')
  })
})

const SHOTS = process.env.SEAS_SHOTS ?? 'test-results/seas-filter'

async function openMap(page: Page, lang: 'en' | 'ko') {
  await page.addInitScript((l) => {
    try {
      localStorage.setItem('bv.locale', l)
    } catch {
      /* a private window */
    }
  }, lang)
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: WORLD_BOOT_MS })
  await page.evaluate(() => document.fonts.ready)
}

async function choose(page: Page, layer: 'off' | 'regions' | 'seas') {
  await page.getByTestId('map-layer-filter').click()
  await expect(page.getByTestId('map-layer-menu')).toBeVisible()
  await page.getByTestId(`map-layer-${layer}`).click()
  await expect(page.getByTestId('map-layer-menu')).toHaveCount(0)
  await expect(page.getByTestId('map-layer-filter')).toHaveAttribute('data-layer', layer)
}

async function press(page: Page, which: 'in' | 'out', times: number) {
  const button = page.getByTestId('map-view-controls').locator('button').nth(which === 'in' ? 0 : 1)
  for (let i = 0; i < times; i++) {
    await button.click()
    await page.waitForTimeout(150)
  }
  await page.waitForTimeout(700)
}

const zonesOnGlass = (page: Page) =>
  page.evaluate(() => ({
    names: [...document.querySelectorAll('[data-label-id^="zone:"]')].map((t) => t.textContent ?? ''),
    notes: [...document.querySelectorAll('[data-label-note^="zone:"]')].map((t) => t.textContent ?? ''),
    closed: document.querySelectorAll('[data-zone-closed="yes"]').length,
    borders: (document.querySelector('[data-testid="map-zone-borders"] path')?.getAttribute('d') ?? '').length,
    seaNames: document.querySelectorAll('[data-label-id^="sea:"]').length,
    regionNames: document.querySelectorAll('[data-label-id^="region:"]').length,
    sideScroll: document.documentElement.scrollWidth > window.innerWidth,
  }))

type Box = { x: number; y: number; width: number; height: number }
const hits = (a: Box, b: Box) => a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height

for (const glass of [
  { tag: '390-en', width: 390, height: 844, lang: 'en' },
  { tag: '320-ko', width: 320, height: 640, lang: 'ko' },
  { tag: '320-en', width: 320, height: 640, lang: 'en' },
  { tag: '1440-en', width: 1440, height: 900, lang: 'en' },
] as const) {
  test.describe(`the map's filter at ${glass.tag}`, () => {
    test.use({ viewport: { width: glass.width, height: glass.height }, locale: glass.lang === 'ko' ? 'ko-KR' : 'en-US' })
    test.beforeAll(() => mkdirSync(SHOTS, { recursive: true }))

    test('off, regions, seas: one at a time; seas names each zone with its ask, marks the closed, and is kept', async ({ page, request, baseURL }) => {
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      test.setTimeout(600_000)
      await serveLitSeas(page)
      await openMap(page, glass.lang)

      // off by default: no zone, the water named as before
      await expect(page.getByTestId('map-layer-filter')).toHaveAttribute('data-layer', 'off')
      await page.getByTestId('map-layer-filter').click()
      await expect(page.getByRole('menuitemradio')).toHaveCount(3)
      await page.keyboard.press('Escape')
      const off = await zonesOnGlass(page)
      expect(off.names).toEqual([])
      expect(off.borders).toBe(0)

      // seas
      await choose(page, 'seas')
      await expect(page.locator('[data-testid="map-zone-borders"] path').first()).toBeAttached({ timeout: 120_000 })
      await page.waitForTimeout(500)
      await page.screenshot({ path: `${SHOTS}/${glass.tag}-seas-open.png` })
      await press(page, 'out', 3)
      const wide = await zonesOnGlass(page)
      await page.screenshot({ path: `${SHOTS}/${glass.tag}-seas-wide.png` })
      expect(wide.borders, 'the borders are drawn').toBeGreaterThan(1000)
      expect(wide.names.length, 'zones are named').toBeGreaterThan(2)
      expect(wide.notes.length, 'every zone name carries its ask').toBe(wide.names.length)
      expect(wide.notes.every((n) => n.length > 0)).toBe(true)
      expect(wide.closed, 'a zone closed to the fleet in hand is marked').toBeGreaterThan(0)
      expect(wide.seaNames, 'the water names give way to the zones').toBe(0)
      expect(wide.sideScroll).toBe(false)
      console.log(`${glass.tag}: ${wide.names.length} zones named (${wide.closed} closed): ${wide.names.map((n, i) => `${n} [${wide.notes[i]}]`).join(' · ')}`)

      // the chrome covers none of itself, and the column keeps one right edge
      const column = await page.getByTestId('map-view-controls').evaluate((col) => [...col.children].map((c) => Math.round(c.getBoundingClientRect().right)))
      expect(new Set(column).size).toBe(1)
      const fleets = await page.getByTestId('map-fleets-corner').boundingBox()
      const controls = await page.getByTestId('map-view-controls').boundingBox()
      if (fleets && controls) {
        expect(hits(fleets, controls), 'chrome covers chrome').toBe(false)
      }

      // the whole world (day and night on one glass), then close in: a sea and its name
      await press(page, 'out', 4)
      await page.screenshot({ path: `${SHOTS}/${glass.tag}-seas-world.png` })
      await press(page, 'in', 7)
      await page.screenshot({ path: `${SHOTS}/${glass.tag}-seas-close.png` })

      // a press on the water opens that sea's tray (tried at each zone name's middle until one is water, not a place)
      const targets = await page.evaluate(() =>
        [...document.querySelectorAll('[data-label-id^="zone:"]')].map((t) => {
          const r = t.getBoundingClientRect()
          return { x: r.x + r.width / 2, y: r.y + r.height / 2, code: (t.getAttribute('data-label-id') ?? '').slice(5) }
        }),
      )
      // and, last, the middle of the glass (a close view of open water may hold no zone's name)
      targets.push({ x: glass.width / 2, y: glass.height / 2, code: '' })
      let opened = false
      for (const at of targets) {
        await page.mouse.click(at.x, at.y)
        await page.waitForTimeout(400)
        if (await page.getByTestId('map-zone-tray').isVisible().catch(() => false)) {
          opened = true
          break
        }
      }
      expect(opened, 'a press on a sea opens its tray').toBe(true)
      await expect(page.getByTestId('map-zone-name')).not.toHaveText('')
      await expect(page.getByTestId('map-zone-codex')).toBeVisible()
      await page.screenshot({ path: `${SHOTS}/${glass.tag}-seas-tray.png` })
      await page.getByTestId('map-zone-tray').getByTestId('tray-close').click()
      await expect(page.getByTestId('map-zone-tray')).toHaveCount(0)

      // regions: the zones go, the regions come
      await choose(page, 'regions')
      await page.waitForTimeout(400)
      const regions = await zonesOnGlass(page)
      expect(regions.names).toEqual([])
      expect(regions.borders).toBe(0)

      // kept across a reload
      await choose(page, 'seas')
      expect(await page.evaluate((k) => localStorage.getItem(k), MAP_LAYER_KEY)).toBe('seas')
      await page.reload()
      await ready(page)
      await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: WORLD_BOOT_MS })
      await expect(page.getByTestId('map-layer-filter')).toHaveAttribute('data-layer', 'seas')
      await expect(page.locator('[data-testid="map-zone-borders"] path').first()).toBeAttached({ timeout: 120_000 })
      await choose(page, 'off')
      expect(await page.evaluate((k) => localStorage.getItem(k), MAP_LAYER_KEY)).toBeNull()
    })
  })
}
