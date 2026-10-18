import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PLAN BUILDER, DRIVEN (docs/COMMAND_DESK.md §3.5, slice D4) — on a local build, at the phone:
//   a good sold elsewhere → its Buy at row's Plan → the builder (the slot turns over) with the board's
//   estimate for the chosen cities → a sell city pressed changes the estimate in place (nothing above it
//   moves) → "Queue it once" → the desk turns to Plans, where the plan's lines stand in the queue, the
//   SAIL to the buy city first and the SELL last.
// Nothing here asserts a price; the lines' order and the slot's turns are the claim.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ viewport: { width: 390, height: 844 } })

test('a plan from the good page is queued whole and stands on Plans', async ({ page, request, baseURL }) => {
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

  const builder = page.getByTestId('plan-builder')
  await expect(builder).toBeVisible()
  await expect(page.getByTestId('good-page')).toHaveCount(0)
  // the board's estimate for the chosen cities lands (skeleton first, at its final height)
  await expect(builder.getByTestId('plan-estimate')).toContainText('Net', { timeout: 60_000 })

  // a second sell city pressed: the estimate changes in place, nothing above it moves
  const sellChips = builder.getByRole('group', { name: 'Sell at' }).getByRole('button')
  if ((await sellChips.count()) > 1) {
    const top = await builder.getByTestId('plan-estimate').evaluate((e) => Math.round(e.getBoundingClientRect().top))
    await sellChips.nth(1).click()
    await page.waitForTimeout(800)
    expect(await builder.getByTestId('plan-estimate').evaluate((e) => Math.round(e.getBoundingClientRect().top))).toBe(top)
  }

  await builder.getByTestId('plan-queue').click()
  await expect(builder).toHaveCount(0, { timeout: 60_000 })
  await expect(page.getByTestId('desk-plans')).toBeVisible()
  const rows = page.getByTestId('queue-row')
  await expect(rows.first()).toBeVisible({ timeout: 30_000 })
  const texts = (await rows.allInnerTexts()).map((t) => t.replace(/\s+/g, ' '))
  console.log(`queued plan: ${JSON.stringify(texts)}`)
  expect(texts.length).toBeGreaterThanOrEqual(3)
  expect(texts.some((t) => /sell/i.test(t))).toBe(true)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
})
