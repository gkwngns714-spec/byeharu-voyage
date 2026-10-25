import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// FLEETS SAYS ONLY WHAT SHE HAS (owner row 203, 2026-10-25: *"what is this 'keep supply at'? this is useless"*).
// Since 0225 supplies are bought by every SAIL, so the fold's Supplies column is one figure — `Supplies N days` —
// and carries no keep control: no stepper, no keep button, no hint about topping up at every port.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test.use({ viewport: { width: 390, height: 844 } })

test('the fleet fold shows Supplies N days and no keep control', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('fleets')
  await ready(page)
  await page.getByTestId('fleet-row').first().click()
  const fold = page.getByTestId('fleet-fold')
  await expect(fold).toBeVisible()
  const days = fold.getByTestId('fleet-stores-days')
  await expect(days).toBeVisible()
  await expect(days).toContainText('Supplies')
  await expect(days).toContainText(/\d+(\.\d)?\s*days/)
  await expect(fold.getByTestId('fleet-keep-stepper')).toHaveCount(0)
  await expect(fold.getByTestId('fleet-keep')).toHaveCount(0)
  await expect(fold).not.toContainText(/keep/i)
  await expect(fold.getByTestId('fleet-command')).toBeVisible()
})
