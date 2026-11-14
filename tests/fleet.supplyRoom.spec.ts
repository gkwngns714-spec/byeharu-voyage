import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// SUPPLIES HAVE THEIR OWN SPACE, ON THE PAGE (0345 built it; 0369 lit `ship_stores_separate`, owner rows 221 and 324).
// The shipped world is lit, so the fleet's page carries one more row above "Supplies N days": `Supply room 8/26 tons`
// (what is aboard, of how much her supply room holds). Read at 390 px in English and in Korean; nothing shears sideways.

const WORDS = {
  en: { room: 'Supply room', figure: /\d+\/\d+\s*tons?/ },
  ko: { room: '보급 창고', figure: /\d+\/\d+\s*톤/ },
} as const

for (const lang of ['en', 'ko'] as const) {
  test.describe(`the supply room row, ${lang}`, () => {
    test.use({ viewport: { width: 390, height: 844 }, locale: lang === 'ko' ? 'ko-KR' : 'en-US' })

    test('the fleet page names her supply room: aboard of room, in tons', async ({ page, request, baseURL }) => {
      test.setTimeout(420_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      await page.goto('fleets')
      await ready(page)
      expect(await page.evaluate(() => document.documentElement.lang)).toBe(lang)
      await page.getByTestId('fleet-row').first().click()
      await expect(page.getByTestId('fleet-page').getByTestId('fleet-fold')).toBeVisible()
      // 2026-11-14 (owner: "when i press the ship, show cargo and supplies"): the supply room is a ship's own, on her page
      await page.getByTestId('fleet-page').getByTestId('fleet-ship-row').first().click()
      const fold = page.getByTestId('fleet-ship-page')
      await expect(fold).toBeVisible()
      const room = fold.getByTestId('fleet-stores-space')
      await expect(room).toBeVisible()
      await expect(room).toContainText(WORDS[lang].room)
      await expect(room).toContainText(WORDS[lang].figure)
      // her room is a real figure: aboard never above it on a new company, and the room above zero
      const [aboard, cap] = ((await room.textContent()) ?? '').match(/(\d+)\/(\d+)/)!.slice(1).map(Number)
      expect(cap).toBeGreaterThan(0)
      expect(aboard).toBeLessThanOrEqual(cap)
      await expect(fold.getByTestId('fleet-stores-days')).toBeVisible()
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
      if (process.env.SUPPLY_ROOM_SHOTS) await page.screenshot({ path: `${process.env.SUPPLY_ROOM_SHOTS}/supply-room-390-${lang}.png` })
    })
  })
}
