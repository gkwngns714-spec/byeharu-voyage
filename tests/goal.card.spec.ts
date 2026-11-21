import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// THE GOAL CARD (remaster S6, src/features/command/GoalCard.tsx): one line on the Trade screen with the next Title and the
// progress toward it, read from the same `world.levels()` the You page's levels read. Pinned on a local build at the phone and the desk:
//   · a fresh player sees the card, and its figures are the You page's own (the next title, Trading and Exploration levels);
//   · the card stands at the same height and place before and after the read lands (no re-flow), and nothing scrolls sideways;
//   · pressing it opens the step that is next (2026-11-22): with the second ship's count on it, the build yard (Office > City);
//     the You page, where the levels stand, is read for the card's figures.
// 0363 (S3 of docs/SECOND_SHIP.md): while the company has ONE ship the second line is "Second ship n / of" in place of the two
// tracks (one line for the other, no height added); a fresh player at Lisbon reads "Second ship · materials 0 / 4". The tracks are then the
// You page's alone, and come back to the card with the second ship (tests/second.ship.spec.ts plays that).

const SIZES = [
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
] as const

const box = (page: Page, sel: string) =>
  page.evaluate((s) => {
    const e = document.querySelector(s)
    if (!e) return null
    const r = e.getBoundingClientRect()
    return { y: Math.round(r.y), h: Math.round(r.height) }
  }, sel)

for (const size of SIZES) {
  test.describe(`the goal card at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size, deviceScaleFactor: 2 })

    test('shows the next title with the You page level figures, holds its height, and opens the yard', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      await page.goto('command')
      // the card's place exists from the first paint: the hold, then the card, at one height and one top edge
      const hold = page.locator('[data-testid="goal-card-hold"], [data-testid="goal-card"]').first()
      await ready(page)
      await expect(hold).toBeVisible({ timeout: 120_000 })
      // whichever stood first (the hold while the read is out, or the card if it had landed) is the box to keep
      const first = await box(page, '[data-testid="goal-card-hold"], [data-testid="goal-card"]')
      const card = page.getByTestId('goal-card')
      await expect(card).toBeVisible({ timeout: 120_000 })
      await expect(page.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
      const loaded = await box(page, '[data-testid="goal-card"]')
      expect(loaded!.h, 'the card is not a fixed two-line height').toBe(44)
      expect(loaded, 'the card moved when the read landed').toEqual(first)

      // the card's text, read before the press
      const text = (await card.innerText()).replace(/\s+/g, ' ')
      // two lines since 2026-11-12: the title's name and Reputation, then (0363, a company of one ship) the second ship
      const m = /^Next: (.+?) (?:Reputation [\d,]+ )?Second ship · materials (\d+) \/ (\d+)$/.exec(text)
      expect(m, `the card says: ${text}`).not.toBeNull()
      expect([m![2], m![3]], 'a fresh company at Lisbon has none of the Barca\'s four lines stored').toEqual(['0', '4'])
      await expect(page.getByTestId('goal-tracks')).toHaveCount(0)

      expect(
        await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth),
        'the card scrolls the page sideways',
      ).toBe(true)

      // press it: the next step, the build yard where the four materials are stored (2026-11-22)
      await expect(card).toHaveAttribute('data-next', 'yard')
      await card.click()
      await expect(page).toHaveURL(/\/office$/)
      await expect(page.getByTestId('port-yard')).toBeVisible({ timeout: 60_000 })
      // the You page, where the levels stand (the desk's Levels face moved there, 2026-11-16): its figures are the card's
      await page.goto('you')
      await ready(page)
      await expect(page.getByTestId('you-levels').first()).toBeVisible({ timeout: 60_000 })
      await expect(page.getByTestId('levels-trading').first()).toBeVisible()
      await expect(page.getByTestId('levels-exploration').first()).toBeVisible()
      await expect(page.getByTestId('levels-title')).toContainText(`${m![1]}`)
    })
  })
}
