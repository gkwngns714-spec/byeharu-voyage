import { test, expect } from '@playwright/test'
import { openFold, ready, reachable } from './appReady.fixture'
import { buyHere, findCarry, sailAndSell } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADE LOOP FROM THE DESK (owner row 194's acceptance, docs/COMMAND_REDESIGN.md R1; the face is ONE screen
// since owner 2026-10-30): a new company at Lisbon makes a whole buy → sail → sell trip, at the owner's desktop
// (1440×900) and the phone (390×844):
//   Trade → a good of Lisbon → Buy (the panel's one button) → a city she is not at (the chip strip; owner
//   row 229: no list of where to sell) → the good → Sail & sell
// and the queue holds the trip: a SAIL to the sell city (through its stops when there are any) and a SELL last —
// no PROVISION line, because supplies are the SAIL's own (0225, row 203). The SAIL runs at once in port, so
// within the minute the fleet has left (the orders pane says so).
// Nothing here asserts a price; the words on the page are 1–2 words (row 202), and that is asserted.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const SIZES = [
  { width: 1440, height: 900 },
  { width: 390, height: 844 },
] as const

for (const size of SIZES) {
  test.describe(`the trade loop at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size })

    test('buy → sail → sell is queued from Trade, and the fleet leaves', async ({ page, request, baseURL }) => {
      test.setTimeout(480_000)
      test.skip(
        !(await reachable(request, baseURL ?? '')),
        `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
      )
      await page.goto('command')
      await ready(page)
      const face = page.getByTestId('desk-trade')
      await expect(face).toBeVisible()

      // a good Lisbon sells that a harbour near her deals in — found by pressing cities (owner row 229)
      const { code, city } = await findCarry(page)
      // BUY: at once, through THE trade panel's one button
      await buyHere(page, code)
      // SELL: that city, the same panel, its button "Sail & sell", its labels 1–2 words
      await sailAndSell(page, code, city)

      // the trip is in the queue: SAIL … , SELL last — no BUY (the cargo is already aboard) and no PROVISION (0225).
      // The queue stands in the folded Orders on a phone (the one-page law).
      await openFold(page, 'command-queue')
      const queued = page.getByTestId('queue-row')
      await expect(queued.first()).toBeVisible({ timeout: 30_000 })
      const texts = (await queued.allInnerTexts()).map((t) => t.replace(/\s+/g, ' '))
      console.log(`trade loop queued: ${JSON.stringify(texts)}`)
      // a near city is one leg, and the SAIL runs at once in port: it may have left the queue already (queue-passage below)
      expect(texts.length).toBeGreaterThanOrEqual(1)
      expect(texts.some((t) => /\bBUY\b/i.test(t)), 'a BUY was queued for cargo already aboard').toBe(false)
      expect(/\bSELL\b/i.test(texts[texts.length - 1]), 'the SELL is not last').toBe(true)
      expect(texts.some((t) => /provision/i.test(t)), 'a PROVISION line was written').toBe(false)

      // and she leaves: the SAIL departed — the orders pane shows her passage under way
      await expect(page.getByTestId('queue-passage'), 'the fleet did not leave port within the minute').toBeVisible({ timeout: 90_000 })
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
