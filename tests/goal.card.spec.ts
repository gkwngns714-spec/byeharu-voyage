import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// THE GOAL CARD (remaster S6, src/features/command/levels/GoalCard.tsx): one line on the Trade screen with the next Title and the
// progress toward it, read from the same `world.levels()` the Levels face reads. Pinned on a local build at the phone and the desk:
//   · a fresh player sees the card, and its figures are the Levels face's own (the next title, Trading and Exploration levels);
//   · the card stands at the same height and place before and after the read lands (no re-flow), and nothing scrolls sideways;
//   · pressing it lands on the Levels face.

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

    test('shows the next title with the Levels face figures, holds its height, and opens Levels', async ({ page, request, baseURL }) => {
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
      const header = await box(page, '[data-testid="desk-header"]')
      const text = (await card.innerText()).replace(/\s+/g, ' ')
      // two lines since 2026-11-12: the title's name and Reputation, then the two tracks (no line of it may break at 320 px)
      const m = /^(.+?) (?:Reputation [\d,]+ )?Trading (\d+)\/(\d+) · Exploration (\d+)\/(\d+)/.exec(text)
      expect(m, `the card says: ${text}`).not.toBeNull()
      expect(m![3]).toBe(m![5])

      expect(
        await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth),
        'the card scrolls the page sideways',
      ).toBe(true)

      // press it: the Levels face, and its figures are the card's
      await card.click()
      await expect(page.getByTestId('desk-levels').first()).toBeVisible({ timeout: 60_000 })
      const level = async (id: string) => Number((await page.getByTestId(id).first().innerText()).match(/\d+/)![0])
      expect(await level('levels-trading')).toBe(Number(m![2]))
      expect(await level('levels-exploration')).toBe(Number(m![4]))
      await expect(page.getByTestId('levels-title')).toContainText(`${m![1]}`)
      // the press did not move the desk's header; wide, the card stands in it on every face and did not move; on a phone it is the
      // Goods face's own (the other faces keep every pixel for themselves)
      expect(await box(page, '[data-testid="desk-header"]'), 'the press moved the header').toEqual(header)
      const after = await box(page, '[data-testid="goal-card"]')
      if (size.width >= 1024) expect(after, 'the press moved the card').toEqual(loaded)
      else expect(after, 'the card stands on a face that is not Goods').toBeNull()
    })
  })
}
