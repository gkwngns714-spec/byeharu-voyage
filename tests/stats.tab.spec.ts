import { test, expect, type Page } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'

// THE STATS TAB (0214; the owner: "a statistic tab along with command, map etc. … updated regularly"). The
// five faces render on a phone with no sideways scroll, the "Updated … ago" line says how old the figures are,
// and the Cities face draws every harbour LOCKED for a company that has invested nowhere — the server sent no
// figures to hide. The local world's backend plays the stats job before the first read (localBackend.ts), so
// the faces have a row to show. It names StatsScreen.tsx so CI's rule N selects it.

const WIDE = { width: 1280, height: 707 }

async function noSidewaysScroll(page: Page) {
  const w = await page.evaluate(() => ({ scroll: document.documentElement.scrollWidth, client: document.documentElement.clientWidth }))
  expect(w.scroll, 'the page scrolls sideways').toBeLessThanOrEqual(w.client)
}

for (const vp of [PHONE, WIDE]) {
  test(`every face renders at ${vp.width}px with no sideways scroll`, async ({ page, request, baseURL }) => {
    test.setTimeout(420_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(vp)
    await page.goto('stats')
    await ready(page)
    await expect(page.getByTestId('stats')).toBeVisible()

    // Overview: the world's money, with its age
    await expect(page.getByTestId('stats-overview')).toBeVisible({ timeout: 120_000 })
    await expect(page.getByTestId('stats-holder')).toHaveCount(4)
    await expect(page.getByTestId('stats-updated')).toContainText('Updated')
    await noSidewaysScroll(page)

    await page.getByRole('tab', { name: 'Markets', exact: true }).click()
    await expect(page.getByTestId('stats-markets')).toBeVisible({ timeout: 60_000 })
    expect(await page.getByTestId('stats-good').count()).toBeGreaterThan(10)
    await noSidewaysScroll(page)

    await page.getByRole('tab', { name: 'Cities', exact: true }).click()
    await expect(page.getByTestId('stats-cities')).toBeVisible({ timeout: 60_000 })
    // nothing invested anywhere: every harbour is locked, and the first one says what to invest
    await expect(page.getByTestId('stats-city-open')).toHaveCount(0)
    expect(await page.getByTestId('stats-city-locked').count()).toBeGreaterThan(10)
    await expect(page.getByTestId('stats-city-locked').first()).toContainText('Invest')
    await page.getByTestId('stats-city-locked').first().click()
    await expect(page.getByTestId('stats-city-lock')).toBeVisible({ timeout: 60_000 })
    await expect(page.getByTestId('stats-city-overview')).toHaveCount(0)
    await expect(page.getByTestId('stats-city-detail')).toHaveCount(0)
    await noSidewaysScroll(page)

    await page.getByRole('tab', { name: 'Merchants', exact: true }).click()
    await expect(page.getByTestId('stats-merchants')).toBeVisible({ timeout: 60_000 })
    await noSidewaysScroll(page)

    await page.getByRole('tab', { name: 'Me', exact: true }).click()
    await expect(page.getByTestId('stats-me')).toBeVisible({ timeout: 60_000 })
    await expect(page.getByTestId('stats-leaderboard-you')).toBeVisible()
    await noSidewaysScroll(page)
  })
}

test('the bar reaches Stats in one tap, beside Map', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.setViewportSize(PHONE)
  await page.goto('command')
  await ready(page)
  const labels = await page.getByTestId('nav-bar').locator('a, button').allInnerTexts()
  expect(labels.map((l) => l.trim())).toEqual(['Command', 'Fleets', 'Map', 'Stats', 'Menu'])
  await page.getByTestId('nav-bar').getByText('Stats').click()
  await expect(page.getByTestId('stats')).toBeVisible()
  await expect(page).toHaveURL(/\/stats$/)
})
