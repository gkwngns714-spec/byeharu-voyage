import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TWO RAILS AGREE (owner, 2026-10-31: *"right now when i press map, i see hq fleets map stats,
// where as if i press hq there is no fleet. WTF are you doing?"*)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// There is ONE tab table (`app/navTabs.ts`, NAV_CELLS) and ONE renderer (`app/NavBar.tsx`): the
// City page renders the shell's own NavBar as its rail, so the two can never drift again — no
// hand-written list, no second nav model. This spec is the guard: it reads both rails' cell labels
// as arrays and compares them cell by cell, on the City page and on Map, then reaches Fleets from
// HQ and HQ again.

test.use({ viewport: { width: 390, height: 844 } })

const EXPECTED = ['HQ', 'Fleets', 'Map', 'Stats', 'Menu']

async function labels(page: Page, rail: string): Promise<string[]> {
  return page.getByTestId(rail).locator('[data-testid^="nav-label-"]').allInnerTexts()
}

async function cellHeights(page: Page, rail: string): Promise<number[]> {
  return page
    .getByTestId(rail)
    .locator('[data-testid^="nav-cell-"]')
    .evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().height)))
}

async function noSideScroll(page: Page, where: string) {
  const s = await page.evaluate(() => ({ w: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }))
  expect(s.w, `${where} scrolls sideways`).toBeLessThanOrEqual(s.cw)
}

test('HQ and Map draw the same five cells, from the one tab table', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)

  // ── THE CITY (HQ): its rail is the shell's own NavBar inside the page's frame ──────────────────
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('city-screen')).toBeVisible()
  const city = await labels(page, 'city-rail')
  console.log(`HQ rail: ${city.join(' · ')}`)
  expect(city, 'the City rail is not the tab table').toEqual(EXPECTED)
  const cityHeights = await cellHeights(page, 'city-rail')
  expect(Math.min(...cityHeights), `a City rail cell is under 44 px: ${cityHeights.join(', ')}`).toBeGreaterThanOrEqual(44)
  await noSideScroll(page, 'the City page')

  // ── MAP: the shell's own bar, read the same way and compared as arrays — never by eye ──────────
  await page.getByTestId('city-rail').getByTestId('nav-cell-/map').click()
  await expect(page).toHaveURL(/\/map$/)
  await ready(page)
  await expect(page.getByTestId('map-chart')).toBeVisible()
  const map = await labels(page, 'app-nav')
  console.log(`Map rail: ${map.join(' · ')}`)
  expect(map, 'the shell rail and the City rail disagree').toEqual(city)
  const mapHeights = await cellHeights(page, 'app-nav')
  expect(Math.min(...mapHeights), `a shell rail cell is under 44 px: ${mapHeights.join(', ')}`).toBeGreaterThanOrEqual(44)
  await noSideScroll(page, 'the Map page')

  // ── FLEETS from HQ, and HQ back (owner: "if i press hq there is no fleet") ─────────────────────
  await page.getByTestId('app-nav').getByTestId('nav-cell-/city').click()
  await expect(page).toHaveURL(/\/city(\?|$)/)
  await ready(page)
  await expect(page.getByTestId('city-screen')).toBeVisible()
  await page.getByTestId('city-rail').getByTestId('nav-cell-/fleets').click()
  await expect(page).toHaveURL(/\/fleets$/)
  await ready(page)
  await expect(page.getByTestId('fleets')).toBeVisible()
  await page.getByTestId('app-nav').getByTestId('nav-cell-/city').click()
  await expect(page).toHaveURL(/\/city(\?|$)/)
  await ready(page)
  await expect(page.getByTestId('city-screen')).toBeVisible()
  expect(await labels(page, 'city-rail'), 'the City rail lost a cell after the Fleets round trip').toEqual(EXPECTED)
})
