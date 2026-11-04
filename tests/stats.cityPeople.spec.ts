import { test, expect } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'

// STATS · CITY · PEOPLE (0305) — owner, 2026-11-04: "add population info on stats - city."
// A city's Stats page shows its people: the population at 24 px, how it stands against the real-world figure, the last step's arrow and why
// (the City hall's words), the tax a day, its rank — and a chart of the kept day of steps. English and Korean; the phone glass has no sideways scroll.

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`a city's people on Stats — ${locale}`, () => {
    test.use({ locale })
    for (const glass of [{ width: 1280, height: 800 }, { width: 320, height: 640 }]) {
      test(`the city page shows population, real-world standing, step, tax and rank at ${glass.width}`, async ({ page, request, baseURL }) => {
        test.setTimeout(480_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
        await page.setViewportSize(glass)
        await page.goto('stats')
        await ready(page)
        await page.getByRole('tablist').first().getByRole('tab').nth(2).click()
        const rows = page.getByTestId('stats-city-open')
        await expect.poll(() => rows.count(), { timeout: 60_000 }).toBeGreaterThan(10)
        await rows.first().click()
        const people = page.getByTestId('stats-city-people')
        await expect(people).toBeVisible({ timeout: 90_000 })
        const pop = page.getByTestId('stats-city-population')
        await expect(pop).toHaveAttribute('data-population', /^\d+$/)
        await expect(pop).toHaveAttribute('data-kind', /^(GROW|HOLD|SHRINK)$/)
        // the figure is 24 px
        const font = await pop.locator('.tabular-nums').first().evaluate((el) => parseFloat(getComputedStyle(el).fontSize))
        expect(font).toBeGreaterThanOrEqual(24)
        // the step's words are the hall's: an arrow, then the reason or the kind
        await expect(pop).toContainText(/[↑→↓]/)
        await expect(page.getByTestId('stats-city-people-base')).toContainText('%')
        await expect(page.getByTestId('stats-city-people-tax')).toHaveAttribute('data-per-day', /^\d+$/)
        await expect(page.getByTestId('stats-city-people-rank')).toHaveAttribute('data-rank', /^[1-9]\d*$/)
        // the words in the glass's language
        await expect(people).toContainText(locale === 'ko-KR' ? '주민' : 'People')
        // no sideways scroll
        const flat = await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1)
        expect(flat).toBe(true)
      })
    }
  })
}
