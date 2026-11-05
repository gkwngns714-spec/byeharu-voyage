import { test, expect, type Page } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'

// CITIES AND MARKETS ARE MERCHANTS' PAGE (owner, 2026-11-05: *"in stats, make the cities tab like merchants"*, *"same for markets,
// a general graph would be nice"*). Merchants.tsx is the pattern: MAIN = two chart cards over ONE list card; SIDE = day figures
// (first on a phone). Pinned for Cities.tsx and Markets.tsx, on a phone and at 1,280: the two chart cards stand side by side above
// the list (one column on a phone, stacked), each holds a drawn chart or its "line soon" note, the list and every old test id are
// still there, nothing scrolls sideways, and on a phone the side comes first.

const WIDE = { width: 1280, height: 800 }
const FACES = [
  { tab: 'Cities', charts: ['stats-chart-city-purses', 'stats-chart-city-trade'], list: 'stats-cities', side: ['stats-cities-day', 'stats-cities-fold'], old: ['stats-cities-filters', 'stats-cities-sort'] },
  { tab: 'Markets', charts: ['stats-chart-market-sold', 'stats-chart-market-bought'], list: 'stats-goods', side: ['stats-markets-day', 'stats-risers'], old: ['stats-markets-filters', 'stats-markets-sort', 'stats-markets-window'] },
] as const

async function box(page: Page, id: string) {
  const b = await page.getByTestId(id).first().boundingBox()
  expect(b, `${id} is not on the page`).not.toBeNull()
  return b!
}

for (const glass of [PHONE, WIDE]) {
  for (const face of FACES) {
    test(`${face.tab} is Merchants' page at ${glass.width}: two chart cards over the list, the day at the side`, async ({ page, request, baseURL }) => {
      test.setTimeout(420_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await page.setViewportSize(glass)
      await page.goto('stats')
      await ready(page)
      await page.getByRole('tab', { name: face.tab, exact: true }).click()
      await expect(page.getByTestId(face.list)).toBeVisible({ timeout: 120_000 })
      for (const id of [...face.charts, ...face.side, ...face.old]) await expect(page.getByTestId(id).first()).toBeAttached()

      const [a, b, list, side] = await Promise.all([box(page, face.charts[0]), box(page, face.charts[1]), box(page, face.list), box(page, face.side[0])])
      // each chart card holds a chart or the note that the line starts at the next count — never an empty card
      for (const id of face.charts) {
        const card = page.getByTestId(id)
        expect((await card.getByRole('img').count()) + (await card.getByText(/./).count()), `${id} is empty`).toBeGreaterThan(1)
      }
      // the charts stand above the list in main
      expect(a.y + a.height, 'the charts are not above the list').toBeLessThanOrEqual(list.y + 1)
      expect(b.y + b.height).toBeLessThanOrEqual(list.y + 1)
      if (glass.width >= 768) {
        expect(Math.abs(a.y - b.y), 'the two chart cards are not side by side').toBeLessThan(2)
        expect(b.x).toBeGreaterThan(a.x + a.width - 2)
        expect(side.x, 'the side is not beside the main').toBeGreaterThan(list.x + list.width - 2)
      } else {
        expect(side.y, 'on a phone the side comes first').toBeLessThan(a.y)
      }
      const w = await page.evaluate(() => ({ scroll: document.documentElement.scrollWidth, client: document.documentElement.clientWidth }))
      expect(w.scroll, 'the page scrolls sideways').toBeLessThanOrEqual(w.client)
      await page.screenshot({ path: `test-results/shots/${face.tab.toLowerCase()}-${glass.width}.png`, fullPage: true })
    })
  }
}
