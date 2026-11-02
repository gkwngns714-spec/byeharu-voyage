import { test, expect } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'

// A GOOD ON STATS → MARKETS IS A PRESS TARGET (owner, 2026-11-02: "on stats, market - trade goods. nothing opened… when i
// click i want to see the charts and info"; GoodTray.tsx). Pressing it opens the tray with the good's name and the price
// chart of a city that lists it, over the page: the list under it does not move. Names Markets.tsx and GoodTray.tsx so CI's
// rule N selects it.

const WIDE = { width: 1280, height: 707 }

for (const vp of [PHONE, WIDE]) {
  test(`a good on Stats → Markets opens its tray with a chart at ${vp.width}px`, async ({ page, request, baseURL }) => {
    test.setTimeout(420_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(vp)
    await page.goto('stats')
    await ready(page)
    await page.getByRole('tab', { name: /markets/i }).first().click()
    const rows = page.getByTestId('stats-good')
    await expect(rows.first()).toBeVisible({ timeout: 120_000 })
    // a row that can be pressed is a button
    expect(await rows.first().evaluate((el) => el.tagName)).toBe('BUTTON')
    await expect(page.getByTestId('stats-good-tray')).toHaveCount(0)

    const top = () => rows.first().evaluate((el) => el.getBoundingClientRect().top)
    const before = await top()
    await rows.first().click()
    const tray = page.getByTestId('stats-good-tray')
    await expect(tray).toBeVisible()
    // the tray names the good
    const code = await tray.getAttribute('data-good')
    expect(code).toBeTruthy()
    await expect(tray.getByRole('heading').first()).not.toBeEmpty()
    // the WORLD chart stands at once (the 24 recorded mids the server serves with the good); a city's own chart, with the
    // span picker over it, is a choice only for a city whose book is already loaded
    await expect(tray.getByTestId('stats-good-chart')).toBeVisible()
    await expect(tray.locator('[role="img"]')).toHaveCount(1, { timeout: 30_000 })
    expect(await top()).toBe(before)
  })
}
