import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { openFleetSheet } from './desk.fixture'
import { pressFirstPricedCard, pressNearCity } from './deskMap.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// SAIL & BUY, DRIVEN (owner row 229; the trip's lines since docs/COMMAND_REDESIGN.md §2) — on a local build, at the phone:
//   HQ's Market plate (H3, 2026-11-24: it was the Trade desk) → a city she is not at (the chip strip) → a good's Buy button → THE panel's one button says "Sail & buy" →
//   pressed → the trip's lines are queued: SAIL there (it runs at once in port: she leaves), then BUY. No sell list
//   stands anywhere (row 229).
// Nothing here asserts a price; the lines and the button's word are the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ viewport: { width: 390, height: 844 }, locale: 'en-US' })

test('Sail & buy from a city she is not at is queued whole and stands in her orders', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('city')
  await ready(page)
  const city = await pressNearCity(page)
  const read = page.getByTestId('city-market-read')
  await expect(read).toHaveAttribute('data-here', 'false')
  await pressFirstPricedCard(page)

  const act = page.getByTestId('trade-act')
  await expect(act).toHaveAttribute('data-act', 'sail-buy')
  await expect(act).toHaveText('Sail & buy', { timeout: 60_000 })
  await expect(page.getByTestId('trade-sell-list')).toHaveCount(0)
  await expect(page.getByTestId('plan-days')).not.toContainText('—', { timeout: 60_000 })
  await act.click()
  await expect(page.getByTestId('trade-toast')).toContainText('Sailing to', { timeout: 60_000 })
  await expect(page.getByTestId('good-detail')).toHaveCount(0)
  await expect(page.getByTestId('city-screen')).toBeVisible()
  // the queue is in her sheet (her HQ row's press)
  await openFleetSheet(page)
  const queued = page.getByTestId('queue-row')
  await expect(queued.first()).toBeVisible({ timeout: 30_000 })
  const texts = (await queued.allInnerTexts()).map((t) => t.replace(/\s+/g, ' '))
  console.log(`queued trip to ${city}: ${JSON.stringify(texts)}`)
  // the SAIL runs at once in port (she leaves within the minute), so the queue may hold only the BUY that waits for her
  expect(texts.some((t) => /buy/i.test(t)), 'no BUY was queued').toBe(true)
  // …and a near city is reached in seconds (0242: arrivals every second): the SAIL is queued, under way, or done
  // (she lies at the city in hand)
  await expect
    .poll(
      async () =>
        (await page.getByTestId('queue-passage').count()) > 0 ||
        (await queued.filter({ hasText: /sail/i }).count()) > 0 ||
        (await page.locator(`[data-testid="city-market-read"][data-city="${city}"][data-here="true"]`).count()) > 0,
      { timeout: 90_000, message: 'no SAIL there' },
    )
    .toBe(true)
  expect(texts.some((t) => /sell/i.test(t)), 'a Sail & buy wrote a SELL').toBe(false)
  expect(texts.some((t) => /provision/i.test(t)), "the plan wrote a PROVISION line: supplies are the SAIL's own (0225)").toBe(false)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
})
