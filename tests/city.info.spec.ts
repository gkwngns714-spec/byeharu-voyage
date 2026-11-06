import { test, expect } from '@playwright/test'
import { CITY_TABS } from '../src/features/map/cityTab'
import { reachable, ready } from './appReady.fixture'
import { openCityPanel } from './openCity.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MAP'S CITY PANEL (owner, 2026-11-06): "the map - city - info - money in out taxes they are too
// crowded … and right now market port info etc. info should be at first order, then town hall, then
// whatever."
//   · the tab order is Info, Town Hall, then Market, Port, Inn, History — one array, CITY_TABS;
//   · a city opens on Info;
//   · Info's four money lines (money, in, out, taxes) are one column of label-and-figure lines: no
//     line overlaps the next, none runs past the panel, and none does so with a nine-digit figure.
// Run it: npm run build && npx vite preview --port 4291, then
//   PLAYWRIGHT_BASE_URL=http://localhost:4291/byeharu-voyage/ npx playwright test city.info.spec.ts
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test('the order of the city tabs is one array: Info, Town Hall, then the rest', () => {
  expect(CITY_TABS.map((c) => c.id)).toEqual(['info', 'townhall', 'market', 'port', 'inn', 'history'])
})

for (const [w, h] of [[1440, 900], [1280, 800], [1024, 768], [390, 844]] as const) {
  test(`${w}: a city opens on Info, and its money lines neither overlap nor overflow`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize({ width: w, height: h })
    await page.goto('map')
    await ready(page)
    await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
    await openCityPanel(page, 'LIS', 'Lisbon')

    const tabs = page.getByTestId('map-city-tabs').getByRole('tab')
    const names = await tabs.allInnerTexts()
    expect(names.length).toBe(CITY_TABS.length)
    expect(names[0]).toBe('Info')
    expect(names[1]).toBe('Town Hall')
    await expect(tabs.first()).toHaveAttribute('aria-selected', 'true')
    await expect(page.getByTestId('city-info')).toBeVisible()

    const figures = page.getByTestId('city-info-figures')
    await expect(figures).toBeVisible({ timeout: 60_000 })
    // the world holds nine digits: write one into every figure, then measure
    await figures.locator('[data-stat-figure]').evaluateAll((els) => {
      for (const el of els) {
        const num = el.querySelector('span, div') ?? el
        el.setAttribute('data-stress', '1')
        ;(num as HTMLElement).textContent = '-988,000,000'
      }
    })
    const read = await figures.evaluate((root) => {
      const panel = root.closest('[data-testid="map-city-tabs"]')!.getBoundingClientRect()
      const rows = [...root.children].map((r) => r.getBoundingClientRect())
      const cells = [...root.querySelectorAll('[data-stat-label], [data-stat-figure]')].map((c) => ({
        r: c.getBoundingClientRect(),
        over: c.scrollWidth > c.clientWidth + 1,
      }))
      return {
        rows: rows.map((r) => ({ top: r.top, bottom: r.bottom })),
        outside: rows.some((r) => r.left < panel.left - 1 || r.right > panel.right + 1),
        overflow: cells.some((c) => c.over),
        sideways: document.documentElement.scrollWidth > document.documentElement.clientWidth,
      }
    })
    expect(read.rows.length).toBe(4)
    for (let i = 1; i < read.rows.length; i++) expect(read.rows[i].top, `line ${i} overlaps the one above`).toBeGreaterThanOrEqual(read.rows[i - 1].bottom - 1)
    expect(read.outside, 'a money line runs past the panel').toBe(false)
    expect(read.overflow, 'a label or figure overflows its cell').toBe(false)
    expect(read.sideways, 'the page scrolls sideways').toBe(false)
  })
}
