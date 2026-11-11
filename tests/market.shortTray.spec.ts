import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// S5 (2026-11-11) — ONE GOODS CARD, AND A SHORT TRADE TRAY
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner's remaster: "make it playable, make it fun", "much more simpler, easy to handle". A playtest
// counted two goods cards for one good (the HQ Market's TradeRow, the Trade screen's card) and a tray of
// 18 controls where a new player needs the quantity, the total and the button. THE LAWS proven here:
//   1. the HQ Market draws THE goods card the Trade screen draws (`trade-good`), and no `trade-row`;
//   2. a buy completes through the short tray: the count, the button carrying the served total;
//   3. the detail (Cargo space, Kind, Trend, Range, In stock, the bargain, the city's trades) stands under
//      ONE More row, and opening it moves neither the button nor the page behind it (the owner's law: a
//      press never re-flows the page); Less brings the short body back;
//   4. nothing scrolls sideways — at 390 and 1280, at DPR 2.

test.use({ deviceScaleFactor: 2 })

async function openMarket(page: Page, size: { width: number; height: number }) {
  await page.setViewportSize(size)
  await page.goto('city')
  await ready(page)
  await page.getByTestId('city-building-market').click()
  await expect(page.getByTestId('city-market-buy')).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
}

/** Where a thing stands on the glass, and the page's own scroll. */
async function box(page: Page, testid: string) {
  return page.evaluate((id) => {
    const r = document.querySelector(`[data-testid="${id}"]`)!.getBoundingClientRect()
    const panel = document.querySelector('[data-testid="city-face-panel"]')!.getBoundingClientRect()
    return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), panelH: Math.round(panel.height), panelY: Math.round(panel.y) }
  }, testid)
}

async function noSideways(page: Page, where: string) {
  const spill = await page.evaluate(() => {
    const out: string[] = []
    const doc = document.documentElement
    if (doc.scrollWidth > doc.clientWidth + 1) out.push(`the page: ${doc.scrollWidth} > ${doc.clientWidth}`)
    for (const el of document.querySelectorAll<HTMLElement>('[data-testid="trade-tray"], [data-testid="trade-tray"] *, [data-testid="city-market-buy"] *')) {
      const s = getComputedStyle(el)
      if ((s.overflowX === 'auto' || s.overflowX === 'scroll') && el.scrollWidth > el.clientWidth + 1) out.push(`${el.dataset.testid ?? el.tagName}: ${el.scrollWidth} > ${el.clientWidth}`)
    }
    return out
  })
  expect(spill, `${where}: something scrolls sideways`).toEqual([])
}

for (const size of [{ width: 390, height: 844 }, { width: 1280, height: 800 }]) {
  test(`HQ Market @${size.width}: the one goods card, a buy through the short tray, and More moves nothing`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await openMarket(page, size)

    // 1. THE ONE CARD
    const cards = page.locator('[data-testid="city-market-buy"] [data-testid="trade-good"]')
    await expect(cards.first()).toBeVisible({ timeout: 60_000 })
    await expect(page.locator('[data-testid="city-face-panel"] [data-testid="trade-row"]'), 'the HQ Market still draws the old TradeRow').toHaveCount(0)
    await noSideways(page, 'the Market')

    // 2. THE SHORT TRAY
    const purse = (await page.getByTestId('purse').innerText()).replace(/\s+/g, ' ')
    await cards.nth(1).getByTestId('trade-buy').click()
    const tray = page.getByTestId('trade-tray')
    await expect(tray).toBeVisible({ timeout: 30_000 })
    const send = page.getByTestId('trade-tray-send')
    await expect(send).toBeEnabled({ timeout: 60_000 })
    await expect(send, 'the button never carried the served total').toContainText('🪙', { timeout: 60_000 })
    await expect(tray.getByTestId('trade-tray-qty')).toBeVisible()
    await expect(tray.getByTestId('trade-tray-more')).toBeVisible()
    for (const detail of ['trade-tray-space', 'trend-row', 'quay-stock', 'good-kind-row', 'haggle-row']) {
      await expect(tray.getByTestId(detail), `${detail} stands in the short body — it belongs under More`).toHaveCount(0)
    }

    // 3. MORE: every detail reachable, and nothing moves
    await page.waitForTimeout(500)
    const before = { send: await box(page, 'trade-tray-send'), tray: await box(page, 'trade-tray'), scroll: await page.evaluate(() => [scrollY, document.querySelector('main')?.scrollTop ?? 0]) }
    await tray.getByTestId('trade-tray-more').click()
    const layer = tray.getByTestId('trade-tray-detail')
    await expect(layer).toBeVisible()
    await expect(tray.getByTestId('trade-tray-less')).toBeFocused()
    for (const detail of ['trade-tray-space', 'trend-row', 'quay-stock', 'good-kind-row']) {
      await expect(layer.getByTestId(detail), `${detail} is not under More`).toHaveCount(1)
    }
    await expect(layer.getByTestId('haggle-row').or(layer.getByTestId('haggle-thread')).first(), 'the bargain is not under More').toBeAttached()
    await page.waitForTimeout(300)
    const after = { send: await box(page, 'trade-tray-send'), tray: await box(page, 'trade-tray'), scroll: await page.evaluate(() => [scrollY, document.querySelector('main')?.scrollTop ?? 0]) }
    console.log(`@${size.width}: send ${JSON.stringify(before.send)} → ${JSON.stringify(after.send)}; tray h ${before.tray.h} → ${after.tray.h}`)
    expect(after.send, 'opening More moved the button').toEqual(before.send)
    expect(after.tray.h, 'opening More re-flowed the tray').toBe(before.tray.h)
    expect(after.tray.panelH, 'opening More re-flowed the page behind').toBe(before.tray.panelH)
    expect(after.scroll, 'opening More scrolled the page').toEqual(before.scroll)
    await noSideways(page, 'More')
    await page.screenshot({ path: `test-results/short-tray-more-${size.width}.png` })
    await tray.getByTestId('trade-tray-less').click()
    await expect(layer).toHaveCount(0)
    await expect(tray.getByTestId('trade-tray-more')).toBeFocused()
    expect(await box(page, 'trade-tray-send'), 'closing More moved the button').toEqual(before.send)

    // 2b. …and the buy completes through the short tray
    await send.click()
    await expect(tray).toHaveCount(0, { timeout: 60_000 })
    await expect.poll(async () => (await page.getByTestId('purse').innerText()).replace(/\s+/g, ' '), { timeout: 30_000 }).not.toBe(purse)
    await expect(cards.first()).toBeVisible()
  })
}
