// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WIDE GLASS — the column is a column, and the tray stands beside it (owner row 80)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-09-13, on PORT › Trade in a 1,545-px window: *"look. too much blank space."*
// Every geometry test in this suite is pinned to the phone (390×844), which is why a Sheet that
// stretched to any width passed for a month. This file is the desktop's own pin: 1440×900.
//
// Two proofs. The PURE one parses the literal Tailwind classes `screenLayout.ts` must type out
// (Tailwind cannot see a class built from a number) and asserts the arithmetic against the named
// constants, so the tray's edge and the column's edge cannot drift apart. The BROWSER one opens the
// Trade face wide, presses a price, and requires: the rows are no wider than the column; the tray
// is a side panel to the RIGHT of the rows with no overlap; and — row 15, still — nothing moved.

import { test, expect } from '@playwright/test'
import {
  GAP_REM,
  PAIR_REM,
  SHEET_REM,
  TRAY_REM,
  sheetBodyClass,
  trayDockWideClass,
} from '../src/components/ui/screenLayout'
import { reachable, ready } from './appReady.fixture'

const WIDE = { width: 1440, height: 900 }

test('the literal wide classes encode the named constants — one rule, two readers', () => {
  const rem = (cls: string, prefix: string) => {
    const m = new RegExp(`${prefix}\\[([0-9.]+)rem\\]`).exec(cls)
    expect(m, `${prefix}[…rem] missing from "${cls}"`).not.toBeNull()
    return Number(m![1])
  }
  const sheet = sheetBodyClass()
  const tray = trayDockWideClass()
  expect(PAIR_REM).toBe(SHEET_REM + GAP_REM + TRAY_REM)
  expect(rem(sheet, 'lg:max-w-')).toBe(PAIR_REM)
  expect(rem(sheet, 'lg:pr-')).toBe(TRAY_REM + GAP_REM)
  expect(rem(tray, 'lg:w-')).toBe(TRAY_REM)
  // right offset = max(0, 50% − PAIR/2): the number inside the calc is half the pair.
  const half = /calc\(50%-([0-9.]+)rem\)/.exec(tray)
  expect(half, `the tray's right offset is not 50% − PAIR/2 in "${tray}"`).not.toBeNull()
  expect(Number(half![1])).toBe(PAIR_REM / 2)
})

test.describe('wide glass', () => {
  test.use({ viewport: WIDE })

  test(`PORT › Trade at ${WIDE.width}px: a readable column, and the tray beside it`, async ({
    page,
    request,
    baseURL,
  }) => {
    test.setTimeout(420_000)
    test.skip(
      !(await reachable(request, baseURL ?? '')),
      `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
    )
    await page.goto('port')
    await ready(page)
    await page.getByRole('tab', { name: /^Trade/i }).first().click()
    await page.waitForTimeout(400)

    const rows = page.locator('[data-testid="trade-row"]')
    expect(await rows.count(), 'no trade rows — is a fleet docked with a market here?').toBeGreaterThan(1)

    const remPx = await page.evaluate(() => parseFloat(getComputedStyle(document.documentElement).fontSize))
    const rowBox = (await rows.first().boundingBox())!
    // 1. THE COLUMN. A row is no wider than SHEET_REM: the gulf between name and price is gone.
    expect(rowBox.width, `a trade row is ${rowBox.width}px wide — the column cap is not applied`).toBeLessThanOrEqual(
      SHEET_REM * remPx + 1,
    )

    // 2. PRESS A PRICE. Nothing at or above the pressed row moves (row 15), and the tray opens.
    const before = await page.evaluate(() =>
      [...document.querySelectorAll('[data-testid="trade-row"]')].map((t) => {
        const r = t.getBoundingClientRect()
        return { left: r.left, top: r.top }
      }),
    )
    await page.evaluate(() => {
      const cell = [...document.querySelectorAll('button')].find((b) => /^buy\b/i.test((b.innerText || '').trim()))
      ;(cell as HTMLButtonElement | undefined)?.click()
    })
    await page.waitForTimeout(900)
    const after = await page.evaluate(() =>
      [...document.querySelectorAll('[data-testid="trade-row"]')].map((t) => {
        const r = t.getBoundingClientRect()
        return { left: r.left, top: r.top }
      }),
    )
    expect(after).toEqual(before)

    // 3. THE TRAY IS A SIDE PANEL: to the right of the rows, no overlap, TRAY_REM wide, and it
    //    reaches from under the status strip to the nav rather than rising from the bottom edge.
    const tray = page.locator('[data-testid="trade-tray"]')
    await expect(tray).toBeVisible()
    const trayBox = (await tray.boundingBox())!
    expect(trayBox.x, 'the tray overlaps the rows — it is not beside the column').toBeGreaterThanOrEqual(
      rowBox.x + rowBox.width,
    )
    expect(Math.abs(trayBox.width - TRAY_REM * remPx)).toBeLessThanOrEqual(1)
    expect(trayBox.height, 'the tray is a bottom sheet, not a side panel').toBeGreaterThan(WIDE.height * 0.7)
    // The gap between column and tray is GAP_REM, not a gulf.
    expect(Math.abs(trayBox.x - (rowBox.x + rowBox.width) - GAP_REM * remPx)).toBeLessThanOrEqual(2)
  })

  // ═════════════════════════════════════════════════════════════════════════════════════════════
  // THE BASKET IS THE SLOT'S FIXTURE (owner rows 76 and 80, slice 2). The reference has the goods
  // on the left and the basket on the right; here the right-hand slot shows the basket BEFORE any
  // press, a price press puts the trade tray in the SAME slot (same x, same width), `Add to basket`
  // hands the slot back to the basket with the line on it and the served total on its button, and
  // through all of it the goods column does not move.
  // ═════════════════════════════════════════════════════════════════════════════════════════════
  test(`PORT › Trade at ${WIDE.width}px: the basket stands in the slot, a pick replaces it, a stage returns it`, async ({
    page,
    request,
    baseURL,
  }) => {
    test.setTimeout(420_000)
    test.skip(
      !(await reachable(request, baseURL ?? '')),
      `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
    )
    await page.goto('port')
    await ready(page)
    await page.getByRole('tab', { name: /^Trade/i }).first().click()
    await page.waitForTimeout(400)

    const rows = page.locator('[data-testid="trade-row"]')
    expect(await rows.count(), 'no trade rows — is a fleet docked with a market here?').toBeGreaterThan(1)
    const remPx = await page.evaluate(() => parseFloat(getComputedStyle(document.documentElement).fontSize))
    const offsets = () =>
      page.evaluate(() =>
        [...document.querySelectorAll('[data-testid="trade-row"]')].map((t) => {
          const r = t.getBoundingClientRect()
          return { left: r.left, top: r.top }
        }),
      )
    const before = await offsets()

    // 1. NO PICK, AND THE BASKET IS THERE — empty, with the cargo bar, in the side slot.
    const basket = page.locator('[data-testid="basket-panel"]')
    await expect(basket, 'the basket panel is absent with no pick — the slot must never be empty at lg').toBeVisible()
    await expect(basket.locator('[data-testid="basket-empty"]')).toBeVisible()
    await expect(basket.locator('[data-testid="cargo-bar"]')).toContainText(/\d+ \/ \d+ tons?/)
    const basketBox = (await basket.boundingBox())!
    expect(Math.abs(basketBox.width - TRAY_REM * remPx)).toBeLessThanOrEqual(1)
    expect(basketBox.height, 'the basket is a bottom sheet, not a side panel').toBeGreaterThan(WIDE.height * 0.7)
    // No ✕ on a fixture: there is nothing to close it to.
    await expect(basket.locator('[data-testid="tray-close"]')).toHaveCount(0)

    // 2. PRESS A PRICE. The trade tray takes the SAME slot — same x, same width — and the basket
    //    is not standing beside or under it (one tray at a time, PR #59 MUST-FIX 3).
    await page.evaluate(() => {
      const cell = [...document.querySelectorAll('[data-testid="trade-row"] button:enabled')].find((b) =>
        /^buy\b/i.test(((b as HTMLElement).innerText || '').trim()),
      )
      ;(cell as HTMLButtonElement | undefined)?.click()
    })
    const tray = page.locator('[data-testid="trade-tray"]')
    await expect(tray).toBeVisible()
    await expect(basket).toHaveCount(0)
    const trayBox = (await tray.boundingBox())!
    expect(Math.abs(trayBox.x - basketBox.x), 'the trade tray does not stand where the basket stood').toBeLessThanOrEqual(1)
    expect(Math.abs(trayBox.width - basketBox.width)).toBeLessThanOrEqual(1)
    expect(await offsets()).toEqual(before)

    // 3. ADD TO BASKET. The slot hands back to the basket with the line on it, priced: the one
    //    button carries the served total, and the wash is on the cargo bar.
    const stage = tray.locator('[data-testid="trade-tray-stage"]')
    await expect(stage).toBeEnabled({ timeout: 20_000 })
    await stage.click()
    await expect(tray).toHaveCount(0)
    await expect(basket).toBeVisible()
    const stagedBox = (await basket.boundingBox())!
    expect(Math.abs(stagedBox.x - basketBox.x)).toBeLessThanOrEqual(1)
    await expect(basket.locator('[data-testid="basket-line"]')).toHaveCount(1)
    const send = basket.locator('[data-testid="basket-send"]')
    await expect(send, 'the basket was never priced — cmd.preview_basket did not answer').toBeEnabled({ timeout: 20_000 })
    await expect(send).toHaveText(/^Buy 1 line · [\d,]+ d\.$/)
    expect(await basket.locator('[data-testid="basket-total"]').count()).toBeGreaterThanOrEqual(3)
    await expect(basket.locator('[data-testid="cargo-bar"] [data-bar-pending]')).toHaveCount(1)
    // The goods column has not moved through any of it.
    expect(await offsets()).toEqual(before)
  })
})
