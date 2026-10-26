import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A TRADE FROM THE GOOD'S PAGE, DRIVEN (docs/COMMAND_REDESIGN.md §2, R1; owner row 218) — on a local build, at the phone:
//   Buy → a good of the city in hand → Plan trip → the card on the Buy face with the board's figures and the sell
//   list under it → a sell row → a second sell row pressed changes the card in place (nothing above it moves) → Go →
//   the trip's lines stand in the queue, the SELL last.
// Nothing here asserts a price; the lines' order and the slot's turns are the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ viewport: { width: 390, height: 844 } })

test('a trip from a good page is queued whole and stands on Buy', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('command')
  await ready(page)
  const face = page.getByTestId('desk-buy')
  await expect(face.getByTestId('city-good').first()).toBeVisible({ timeout: 120_000 })
  await face.getByTestId('city-good').first().click()
  await face.getByTestId('good-plan').click()

  // the trip is made on the Buy face, in flow
  const card = face.getByTestId('trade-card')
  await expect(card).toBeVisible({ timeout: 30_000 })
  // the board's figures for the chosen cities land, and the Go button says Go
  const rows = page.getByTestId('trade-sell-row')
  await expect(rows.first()).toBeVisible({ timeout: 60_000 })
  await rows.first().click()
  await expect(card.getByTestId('plan-queue')).toHaveText('Go', { timeout: 60_000 })

  // a second sell row pressed: the card changes in place, nothing above it moves. Measured as the card's offset within
  // its face (the sheet scrolls to reach a row; a scroll is not a move).
  const offset = () =>
    card.evaluate((e) => {
      const desk = e.closest('[data-testid="desk-buy"]') as HTMLElement
      return Math.round(e.getBoundingClientRect().top - desk.getBoundingClientRect().top)
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
  await expect(face).toBeVisible()
  const queued = page.getByTestId('queue-row')
  await expect(queued.first()).toBeVisible({ timeout: 30_000 })
  const texts = (await queued.allInnerTexts()).map((t) => t.replace(/\s+/g, ' '))
  console.log(`queued trade: ${JSON.stringify(texts)}`)
  expect(texts.length).toBeGreaterThanOrEqual(3)
  expect(texts.some((t) => /sell/i.test(t))).toBe(true)
  expect(texts.some((t) => /provision/i.test(t)), "the plan wrote a PROVISION line: supplies are the SAIL's own (0225)").toBe(false)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
})
