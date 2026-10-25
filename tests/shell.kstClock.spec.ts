import { test, expect } from '@playwright/test'
import { formatKoreaTime } from '../src/lib/format'
import { PHONE, reachable, ready } from './appReady.fixture'

// ROW 195 — the owner, 2026-10-25: *"the clock on the game, i need a real time clock, set in korea
// since i am in korea. and a date for game"*. The strip carries BOTH: the game's own date (row 176's
// one authority, `formatGameToday`) under its word, and the real time in Korea, ticking each second.

test('Korea time is UTC+9 whatever the device zone, to the second', () => {
  // 2026-10-25 15:04:05 UTC is 00:04:05 the next day in Seoul (no daylight saving there).
  expect(formatKoreaTime(Date.UTC(2026, 9, 25, 15, 4, 5))).toBe('00:04:05')
  expect(formatKoreaTime(Date.UTC(2026, 0, 1, 0, 0, 0))).toBe('09:00:00')
  expect(formatKoreaTime(Number.NaN)).toBe('—')
})

for (const size of [PHONE, { width: 1280, height: 800 }]) {
  test(`${size.width}px: the strip shows KST ticking beside the game date`, async ({ page, request, baseURL }) => {
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(size)
    await page.goto('map')
    await ready(page)
    const kst = page.getByTestId('kst-clock')
    await expect(kst).toBeVisible()
    await expect(kst).toHaveText(/^\d{2}:\d{2}:\d{2}$/)
    await expect(page.locator('header')).toContainText('KST')
    if (size.width >= 640) await expect(page.locator('header')).toContainText('Game date')
    // The game's hour is still whole on the strip: the new clock did not push it out.
    const hour = await page.getByTestId('game-clock').boundingBox()
    const left = await page.getByTestId('game-clock').evaluate((el) => (el.parentElement as HTMLElement).getBoundingClientRect().right)
    expect(hour!.x + hour!.width, 'the game hour is cut off').toBeLessThanOrEqual(left + 0.5)
    await expect(page.getByTestId('game-date')).toHaveText(/\d{4}/)

    // It is Korea's time: within two seconds of the instant this test reads, in Asia/Seoul.
    const first = (await kst.textContent()) ?? ''
    const [h, m, s] = first.split(':').map(Number)
    const seoul = new Date(Date.now() + 9 * 3_600_000)
    const diff = Math.abs(h * 3600 + m * 60 + s - (seoul.getUTCHours() * 3600 + seoul.getUTCMinutes() * 60 + seoul.getUTCSeconds()))
    expect(Math.min(diff, 86_400 - diff), `${first} is not Seoul time`).toBeLessThanOrEqual(5)

    // It ticks: a later reading differs, each second.
    await expect(kst).not.toHaveText(first, { timeout: 3_000 })

    // The clock sits inside the bar, never under the purse or off the glass.
    const bar = await page.locator('header').boundingBox()
    const clock = await kst.boundingBox()
    const purse = await page.getByTestId('purse').boundingBox()
    expect(bar && clock && purse).toBeTruthy()
    expect(clock!.x + clock!.width).toBeLessThanOrEqual(purse!.x)
    expect(clock!.x).toBeGreaterThanOrEqual(bar!.x)
  })
}
