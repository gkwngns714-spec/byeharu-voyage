import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADE LOOP FROM ONE PAGE (owner row 194's acceptance, docs/COMMAND_REDESIGN.md R1): a new company at
// Lisbon makes a whole buy → sail → sell trip from the Trade page ALONE, at the owner's desktop (1440×900) and
// the phone (390×844):
//   Trade → Start = Here → a good this port sells → a Sell row → Go
// and the queue holds the trip: a BUY here, a SAIL to the sell city (through its stops when there are any) and
// a SELL last — no PROVISION line, because supplies are the SAIL's own (0221, row 203). The first lines run at
// once in port, so within the minute the fleet has left: the BUY is done and she is SAILING (the strip says so).
// Nothing here asserts a price; the words on the page are 1–2 words (row 202), and that is asserted.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

for (const size of SIZES) {
  test.describe(`the trade loop at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('buy → sail → sell is queued from Trade alone, and the fleet leaves', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      await page.getByRole('tab', { name: 'Trade', exact: true }).click()
      const face = page.getByTestId('desk-plans')
      await expect(face).toBeVisible()

      // START = Here: what this port sells, each row one press
      await face.getByTestId('trade-start-here').click()
      const goods = face.getByTestId('trade-good')
      await expect(goods.first()).toBeVisible({ timeout: 120_000 })
      await goods.first().click()
      await expect(goods.first()).toHaveAttribute('aria-pressed', 'true')

      // the card stands, with the sell list: open rows are presses, shut rows say why in 1–2 words
      const card = face.getByTestId('trade-card')
      await expect(card).toBeVisible()
      await expect(card.getByTestId('plan-queue')).toHaveText('Pick sell')
      const rows = face.getByTestId('trade-sell-row')
      await expect(rows.first()).toBeVisible({ timeout: 120_000 })
      for (const reason of await face.getByTestId('trade-sell-shut').locator('span').last().allInnerTexts()) {
        expect(reason.trim().split(/\s+/).length, `a shut row's reason is not 1–2 words: "${reason}"`).toBeLessThanOrEqual(2)
      }
      // the card's labels are 1–2 words
      for (const label of await card.locator('[data-testid="plan-estimate"] .text-t-label').allInnerTexts()) {
        if (label.trim()) expect(label.trim().split(/\s+/).length, `a card label is not 1–2 words: "${label}"`).toBeLessThanOrEqual(2)
      }

      // pick the first open sell row: the card fills in place, Go says Go
      await rows.first().click()
      await expect(rows.first()).toHaveAttribute('aria-pressed', 'true')
      await expect(card.getByTestId('trade-sell')).not.toContainText('—')
      await expect(card.getByTestId('plan-supplies')).not.toContainText('—', { timeout: 60_000 })
      const go = card.getByTestId('plan-queue')
      await expect(go).toHaveText('Go', { timeout: 60_000 })
      await go.click()

      // the trip is in the queue. The BUY ran the moment it was queued (she is in port, and the queue runs itself), so
      // what stands is the rest of it: SAIL … , SELL last — and no PROVISION line anywhere (0221).
      await expect(page.getByTestId('trade-card')).toHaveCount(0, { timeout: 60_000 })
      const queued = page.getByTestId('queue-row')
      await expect(queued.first()).toBeVisible({ timeout: 30_000 })
      const texts = (await queued.allInnerTexts()).map((t) => t.replace(/\s+/g, ' '))
      console.log(`trade loop queued: ${JSON.stringify(texts)}`)
      expect(texts.length).toBeGreaterThanOrEqual(2)
      expect(texts.some((t) => /\bBUY\b/i.test(t)), 'the BUY is still pending: it did not run in port').toBe(false)
      expect(texts.some((t) => /\bSAIL\b/i.test(t)), 'no SAIL in the queue').toBe(true)
      expect(/\bSELL\b/i.test(texts[texts.length - 1]), 'the SELL is not last').toBe(true)
      expect(texts.some((t) => /provision/i.test(t)), 'a PROVISION line was written').toBe(false)

      // and she leaves: the BUY ran in port and the SAIL departed — the orders pane shows her passage under way
      await expect(page.getByTestId('queue-passage'), 'the fleet did not leave port within the minute').toBeVisible({ timeout: 90_000 })
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
