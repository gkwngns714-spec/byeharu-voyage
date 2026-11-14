import { test, expect } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'

// S1 of the remaster (owner, 2026-11-11: "make it playable"): a new captain lands where the buy buttons are.
// The root opens TRADE (the desk, route /command, `navTabs.HOME_TAB`), the bar's second cell is worded Trade,
// and Stats lives in the Menu on a phone — still one tray away — and is its own cell on the wide rail, with You
// (owner, 2026-11-14: "make you, stats on the left side like hq, trade etc."). It names navTabs.ts so CI's rule N selects it.
for (const size of [PHONE, { width: 1280, height: 800 }]) {
  test(`a fresh world lands on Trade with buy buttons, and Stats is one place away @${size.width}`, async ({ page, request, baseURL }) => {
    test.setTimeout(420_000)
    expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL}`).toBe(true)
    await page.setViewportSize(size)
    await page.goto('/')
    await expect(page).toHaveURL(/\/command$/)
    await ready(page)

    const bar = page.getByTestId('nav-bar')
    await expect(bar.getByTestId('nav-label-/command')).toHaveText('Trade')
    const onRail = size.width >= 1024
    const labels = (await bar.locator('[data-testid^="nav-label-"]').allInnerTexts()).map((s) => s.trim())
    expect(labels).toEqual(onRail ? ['HQ', 'Trade', 'Fleets', 'Map', 'You', 'Stats', 'Menu'] : ['HQ', 'Trade', 'Fleets', 'Map', 'Menu'])
    await expect(page.getByTestId('trade-buy').first(), 'no buy button on the landing screen').toBeVisible({ timeout: 120_000 })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), 'sideways scroll').toBe(true)

    // ONE PLACE PER DESTINATION: the rail's own cells are not in its Menu; the phone's Menu holds all seven.
    await bar.getByTestId('nav-cell-cabin').click()
    const panel = page.getByTestId('nav-group-panel')
    await expect(panel.getByRole('link')).toHaveCount(onRail ? 5 : 7)
    await expect(panel.locator('a[href$="/you"], a[href$="/stats"]')).toHaveCount(onRail ? 0 : 2)
    if (onRail) {
      await bar.getByTestId('nav-cell-cabin').click()
      await expect(panel).toHaveCount(0)
      // the rail fits its seven cells: the Menu's foot is inside the window
      const foot = await bar.getByTestId('nav-cell-cabin').evaluate((e) => Math.round(e.getBoundingClientRect().bottom))
      expect(foot, 'the Menu cell is cut off the rail').toBeLessThanOrEqual(size.height)
      await bar.getByTestId('nav-cell-/you').click()
      await expect(page).toHaveURL(/\/you$/)
      await expect(bar.getByTestId('nav-cell-/you')).toHaveClass(/text-accent/)
      await bar.getByTestId('nav-cell-/stats').click()
    } else {
      await panel.getByRole('link', { name: 'Stats', exact: true }).click()
    }
    await expect(page).toHaveURL(/\/stats$/)
    await expect(page.getByTestId('stats')).toBeVisible({ timeout: 120_000 })
  })
}
