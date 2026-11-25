import { test, expect } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { corpWorld } from './corpWorld.fixture'
import { serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════
// A FRESH REFUSAL CARRIES ITS FIXING PRESS; MENDED, IT IS NO LONGER ANNOUNCED (branch `stale-refusal`, driven here)
// ═══════════════════════════════════════════════════════════════════════════════
//
// tests/refusal.stale.spec.ts holds the rule in plain Node. THIS DRIVES IT ONCE IN THE BROWSER, at 390 and 1440:
//   * her job's first sail is refused because her flagship is a wreck (tests/corpWorld.fixture.ts `wreck`): the job stops on it, and
//     her row on HQ wears Repair at the server's price;
//   * on the Trade desk the note at the head of her queue names HER (never an order's number), says why in the server's words,
//     prints no code, and carries Repair at the same price;
//   * Repair is pressed there: the note is gone (the cause is mended), the refused order is still a row of her queue, and her row
//     on HQ no longer wears Repair.

const OUT = process.env.HQ_SHOTS ?? 'test-results/refusal-drive'

for (const size of [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
])
  test(`@${size.width}: a wrecked flagship's refusal carries Repair; repaired, it is not announced again`, async ({ page, request, baseURL }) => {
    test.setTimeout(900_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    await serveWorldImage(page, await corpWorld({ courses: true, wreck: true }))
    await page.setViewportSize(size)
    await page.goto('city')
    await ready(page)
    await expect(page.getByTestId('corp-worker-list')).toBeVisible({ timeout: 300_000 })
    const row = page.locator('[data-testid="corp-worker"][data-kind="fleet"]').first()
    const name = (await row.getByTestId('corp-worker-name').innerText()).trim()

    // she is given a run; its sail is refused: her job stops, and her row wears Repair at the server's price
    await row.click()
    const sheet = page.getByTestId('hq-sheet-assign')
    await sheet.getByTestId('corp-assign-run').first().click({ timeout: 180_000 })
    await sheet.getByTestId('corp-assign-go').click()
    await expect(sheet).toHaveCount(0, { timeout: 120_000 })
    await expect(row, 'her job did not stop on the wreck with a repair to press').toHaveAttribute('data-fix', 'repair', { timeout: 180_000 })
    await expect(row).toHaveAttribute('data-state', 'stopped')
    // the price is the Shipyard's own dry run: it stands on her row once that has answered
    await expect.poll(async () => Number(await row.getAttribute('data-fix-cost')), { timeout: 120_000, message: 'her row names no price for the repair' }).toBeGreaterThan(0)
    const cost = Number(await row.getAttribute('data-fix-cost'))
    await expect(row).toContainText('Repair')
    await page.getByTestId('corp-workers').scrollIntoViewIfNeeded()
    await page.screenshot({ path: `${OUT}/refusal-hq-${size.width}.png` })

    // THE FRESH NOTE, on the Trade desk: her name, the server's words, no code, no order number, and Repair at the same price
    await page.goto('command')
    await ready(page)
    // her queue stands behind the desk's Orders row
    await page.getByTestId('command-queue').click({ timeout: 180_000 })
    const note = page.getByTestId('queue-halt')
    await expect(note).toBeVisible({ timeout: 180_000 })
    await expect(note).toContainText(name)
    await expect(note).toContainText('not fit to sail')
    expect(await note.innerText(), 'the note names an order number').not.toMatch(/Order \d+/)
    expect((await note.innerText()).match(/E_[A-Z_]+/g) ?? [], 'a code is printed').toEqual([])
    const fix = page.getByTestId('queue-halt-fix').getByTestId('corp-fix')
    await expect(fix).toHaveAttribute('data-fix', 'repair')
    await expect(fix).toHaveAttribute('data-cost', String(cost), { timeout: 60_000 })
    const box = (await fix.boundingBox())!
    expect(box.height, 'Repair is under 44 px').toBeGreaterThanOrEqual(43.5)
    expect(await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth), 'the desk scrolls sideways').toBe(false)
    await note.scrollIntoViewIfNeeded()
    await page.screenshot({ path: `${OUT}/refusal-fresh-${size.width}.png` })

    // REPAIRED: the note is gone; the refused order is still a row of her queue
    await fix.click()
    await expect(note, 'the refusal is still announced after the repair').toHaveCount(0, { timeout: 180_000 })
    await expect(page.getByTestId('queue-halt-fix')).toHaveCount(0)
    await expect(page.getByTestId('queue-row').first(), 'the refused order left her queue with the note').toBeVisible()
    await page.getByTestId('queue-row').first().scrollIntoViewIfNeeded()
    await page.screenshot({ path: `${OUT}/refusal-mended-${size.width}.png` })

    // and on HQ her row no longer wears Repair
    await page.goto('city')
    await ready(page)
    await expect(page.locator('[data-testid="corp-worker"][data-kind="fleet"]').first()).not.toHaveAttribute('data-fix', 'repair', { timeout: 180_000 })
  })
