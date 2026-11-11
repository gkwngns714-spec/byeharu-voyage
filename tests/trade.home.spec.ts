import { test, expect } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'

// S1 of the remaster (owner, 2026-11-11: "make it playable"): a new captain lands where the buy buttons are.
// The root opens TRADE (the desk, route /command, `navTabs.HOME_TAB`), the bar's second cell is worded Trade,
// and Stats lives in the Menu — still one tray away. It names navTabs.ts so CI's rule N selects it.
for (const size of [PHONE, { width: 1280, height: 800 }]) {
  test(`a fresh world lands on Trade with buy buttons, and Stats is in the Menu @${size.width}`, async ({ page, request, baseURL }) => {
    test.setTimeout(420_000)
    expect(await reachable(request, baseURL ?? ''), `nothing served at ${baseURL}`).toBe(true)
    await page.setViewportSize(size)
    await page.goto('/')
    await expect(page).toHaveURL(/\/command$/)
    await ready(page)

    const bar = page.getByTestId('nav-bar')
    await expect(bar.getByTestId('nav-label-/command')).toHaveText('Trade')
    await expect(bar.getByTestId('nav-cell-/stats'), 'Stats is back on the bar').toHaveCount(0)
    await expect(page.getByTestId('trade-buy').first(), 'no buy button on the landing screen').toBeVisible({ timeout: 120_000 })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), 'sideways scroll').toBe(true)

    await bar.getByTestId('nav-cell-cabin').click()
    await page.getByTestId('nav-group-panel').getByRole('link', { name: 'Stats', exact: true }).click()
    await expect(page).toHaveURL(/\/stats$/)
    await expect(page.getByTestId('stats')).toBeVisible({ timeout: 120_000 })
  })
}
