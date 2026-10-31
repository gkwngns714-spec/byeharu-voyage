import { test, expect, type Page } from '@playwright/test'
import { PHONE, closeDetail, openDetail, reachable, ready } from './appReady.fixture'

// THE STATS TAB (0214; the owner: "a statistic tab along with command, map etc. … updated regularly"). The
// five faces render on a phone with no sideways scroll, the "Updated HH:MM:SS" line says when the live figures are from,
// and the Cities face draws every harbour OPEN for a company that has invested nowhere (0223, owner row 197: "all
// the info without investment"). The local world's backend plays the stats job before the first read (localBackend.ts), so
// the faces have a row to show. It names StatsScreen.tsx so CI's rule N selects it.
//
// THE FACE (2026-10-20, owner requests 187 and 188 — "no visuals, no charts, no number moving around" and
// "I want stats to be in real time, by seconds updated"): the RIGHT NOW band stands on every face with the
// figures the world's own beat carries, and the rollup's figures are drawn as charts — a stacked bar for the
// composition, bars from a zero line for each count, ranked bars for which of these is big. Pinned below:
// the band is there with its purse, the band survives a change of face, and the Overview draws a chart.
//
// LIVE TO THE SECOND (0224, owner row 200): the band's world money and its trades since the count come from
// world.stats_now(), asked every second while the tab is open (statsLive.ts). Pinned: they are figures, not dashes.

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
    // THE FACE'S DETAIL IS FOLDED (2026-10-31, the sheet law): one press opens it, as a player does.
    await openDetail(page, 'stats-money')
    await expect(page.getByTestId('stats-holder')).toHaveCount(4)
    await expect(page.getByTestId('stats-updated')).toContainText(/Updated \d\d:\d\d:\d\d/)
    // RIGHT NOW: the live band, with a purse that is a figure and not a dash — and the world's live figures (0224)
    await expect(page.getByTestId('stats-live')).toBeVisible()
    await expect(page.getByTestId('stats-live-purse')).toContainText(/\d/)
    await expect(page.getByTestId('stats-live-world')).toContainText(/\d/, { timeout: 30_000 })
    await expect(page.getByTestId('stats-live-trades')).toContainText(/\d/)
    // the economy watch (0229, docs/CLOSED_ECONOMY.md §7), from the live read
    await expect(page.getByTestId('stats-watch')).toBeVisible({ timeout: 30_000 })
    // and the rollup is DRAWN: the holders' stacked bar and at least one chart on the face
    expect(await page.getByTestId('stats-overview').locator('[role="img"]').count()).toBeGreaterThan(0)
    await noSidewaysScroll(page)
    await closeDetail(page)

    await page.getByRole('tab', { name: 'Markets', exact: true }).click()
    await expect(page.getByTestId('stats-markets')).toBeVisible({ timeout: 60_000 })
    await openDetail(page, 'stats-goods')
    expect(await page.getByTestId('stats-good').count()).toBeGreaterThan(10)
    await noSidewaysScroll(page)
    await closeDetail(page)

    await page.getByRole('tab', { name: 'Cities', exact: true }).click()
    await expect(page.getByTestId('stats-cities')).toBeVisible({ timeout: 60_000 })
    await openDetail(page, 'stats-cities-list')
    // nothing invested anywhere, and every harbour is open (0223, owner row 197): no lock, no "Invest",
    // and the first row opens with its overview AND its detail
    expect(await page.getByTestId('stats-city-open').count()).toBeGreaterThan(10)
    await expect(page.getByTestId('stats-city-locked')).toHaveCount(0)
    await expect(page.getByTestId('stats-cities')).not.toContainText(/Invest|Locked/)
    await page.getByTestId('stats-city-open').first().click()
    await expect(page.getByTestId('stats-city-overview')).toBeVisible({ timeout: 60_000 })
    await expect(page.getByTestId('stats-city-detail')).toBeVisible()
    await expect(page.getByTestId('stats-city-lock')).toHaveCount(0)
    await noSidewaysScroll(page)
    await page.getByTestId('stats-city-close').click()
    await closeDetail(page)

    await page.getByRole('tab', { name: 'Merchants', exact: true }).click()
    await expect(page.getByTestId('stats-merchants')).toBeVisible({ timeout: 60_000 })
    await noSidewaysScroll(page)

    await page.getByRole('tab', { name: 'Me', exact: true }).click()
    await expect(page.getByTestId('stats-me')).toBeVisible({ timeout: 60_000 })
    await openDetail(page, 'stats-leaderboard')
    await expect(page.getByTestId('stats-leaderboard-you')).toBeVisible()
    await closeDetail(page)
    await expect(page.getByTestId('stats-me-bars')).toBeVisible()
    // the live band belongs to the TAB, not to a face: it is still there on the fifth one
    await expect(page.getByTestId('stats-live-purse')).toContainText(/\d/)
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
