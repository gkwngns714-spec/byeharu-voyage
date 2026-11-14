import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// FLEETS SAYS ONLY WHAT SHE HAS (owner row 203, 2026-10-25: *"what is this 'keep supply at'? this is useless"*).
// Since 0225 supplies are bought by every SAIL, so the fold's Supplies column is one figure — `Supplies N days` —
// and carries no keep control: no stepper, no keep button, no hint about topping up at every port.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ viewport: { width: 390, height: 844 } })

test('the fleet page shows Supplies N days and no keep control', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('fleets')
  await ready(page)
  await page.getByTestId('fleet-row').first().click()
  // HER CONTENT IS ON A PAGE (owner, 2026-10-31: *"enough with folding things … once clicked show
  // new page popping up"*): the row opens `fleet-page`, the one DetailPage, and the sections stand there.
  const fleetPage = page.getByTestId('fleet-page')
  await expect(fleetPage).toBeVisible()
  const fold = fleetPage.getByTestId('fleet-fold')
  await expect(fold).toBeVisible()
  // TWO STEPS (owner, 2026-11-14: "when pressed a fleet, show only ships, then when i press the ship, show cargo and supplies"): the days stand on a ship's page,
  // under the word that says whose they are (the server serves them per fleet).
  await expect(fold).not.toContainText(/keep/i)
  await fold.getByTestId('fleet-ship-row').first().click()
  const shipPage = page.getByTestId('fleet-ship-page')
  const days = shipPage.getByTestId('fleet-stores-days')
  await expect(days).toBeVisible()
  await expect(days).toContainText('Whole fleet')
  await expect(days).toContainText(/\d+(\.\d)?\s*days/)
  await expect(shipPage.getByTestId('fleet-keep-stepper')).toHaveCount(0)
  await expect(shipPage.getByTestId('fleet-keep')).toHaveCount(0)
  await expect(shipPage).not.toContainText(/keep/i)
  await shipPage.locator('[data-detail-back]').click()
  await expect(shipPage).toHaveCount(0)
  // Command is the fleet's, one row further
  await fold.getByTestId('fleet-more').click()
  await expect(page.getByTestId('fleet-more-page').getByTestId('fleet-command')).toBeVisible()
  await page.locator('[data-detail-back]').last().click()
  await expect(page.getByTestId('fleet-more-page')).toHaveCount(0)
  // THE BACK PRESS REVEALS THE LIST, UNTOUCHED.
  await page.locator('[data-detail-back]').last().click()
  await expect(fleetPage).toHaveCount(0)
})
