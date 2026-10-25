import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A TRADE FROM THE GOOD PAGE, DRIVEN (docs/COMMAND_REDESIGN.md §2, R1) — on a local build, at the phone:
//   a good sold elsewhere → its Buy at row's Plan → the desk turns to Trade (row 183), the card there with the
//   board's figures for the chosen cities and the sell list beside it → a second sell row pressed changes the
//   card in place (nothing above it moves) → Go → the trip's lines stand in the queue, the SELL last.
// Nothing here asserts a price; the lines' order and the slot's turns are the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ viewport: { width: 390, height: 844 } })

test('a trade from the good page is queued whole and stands on Trade', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('command')
  await ready(page)
  await expect(page.getByTestId('watch-row').first()).toBeVisible({ timeout: 120_000 })
  // A good the docked city sells that others sell too: its page offers Plan on a row that is not here.
  await page.getByRole('button', { name: 'Here', exact: true }).click()
  await page.getByTestId('watch-row').first().click()
  await expect(page.getByTestId('good-page')).toBeVisible()
  const plan = page.getByTestId('desk-plan').first()
  await expect(plan).toBeVisible({ timeout: 60_000 })
  await plan.click()

  // owner row 183: the press turns the desk to Trade, and the trade is made there
  await expect(page.getByTestId('desk-plans')).toBeVisible({ timeout: 30_000 })
  const card = page.getByTestId('desk-plans').getByTestId('trade-card')
  await expect(card).toBeVisible()
  await expect(page.getByTestId('good-page')).toHaveCount(0)
  // the board's figures for the chosen cities land, and the Go button says Go
  const rows = page.getByTestId('trade-sell-row')
  await expect(rows.first()).toBeVisible({ timeout: 60_000 })
  await expect(card.getByTestId('plan-queue')).toHaveText('Go', { timeout: 60_000 })

  // a second sell row pressed: the card changes in place, nothing above it moves. Measured as the card's offset within
  // its face (the sheet scrolls to reach a row; a scroll is not a move).
  const offset = () =>
    card.evaluate((e) => {
      const face = e.closest('[data-testid="desk-plans"]') as HTMLElement
      return Math.round(e.getBoundingClientRect().top - face.getBoundingClientRect().top)
    })
  if ((await rows.count()) > 1) {
    const top = await offset()
    await rows.nth(1).click()
    await expect(rows.nth(1)).toHaveAttribute('aria-pressed', 'true')
    await page.waitForTimeout(800)
    expect(await offset(), 'a press moved the card').toBe(top)
  }

  await expect(card.getByTestId('plan-queue')).toHaveText('Go', { timeout: 60_000 })
  await card.getByTestId('plan-queue').click()
  await expect(page.getByTestId('trade-card')).toHaveCount(0, { timeout: 60_000 })
  await expect(page.getByTestId('desk-plans')).toBeVisible()
  const queued = page.getByTestId('queue-row')
  await expect(queued.first()).toBeVisible({ timeout: 30_000 })
  const texts = (await queued.allInnerTexts()).map((t) => t.replace(/\s+/g, ' '))
  console.log(`queued trade: ${JSON.stringify(texts)}`)
  expect(texts.length).toBeGreaterThanOrEqual(3)
  expect(texts.some((t) => /sell/i.test(t))).toBe(true)
  expect(texts.some((t) => /provision/i.test(t)), "the plan wrote a PROVISION line: supplies are the SAIL's own (0225)").toBe(false)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
})
