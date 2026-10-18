import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADING TERMINAL, MEASURED (docs/COMMAND_DESK.md §3.9, 2026-10-18). The owner's own glass is
// 1440×731; the phone is 390×844.
//   · WIDE: the three panes (watchlist · chart · ticket) stand side by side and use the glass; the
//     page never scrolls sideways; the Best trade card is whole ABOVE THE FOLD (the nav's top);
//   · A PRESS SELECTS: pressing a good changes the chart and the ticket in place — no pane moves, no
//     row of the list moves;
//   · STOCK (owner: "i don't see stock of the trade goods"): watchlist rows and ladder rows carry the
//     stock gauge, and the chart its stock strip;
//   · PHONE: no sideways scroll; the good's page holds the chart, then the Best trade card.
// Prices are the local world's; nothing here asserts a figure — only geometry and presence.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

async function openDesk(page: Page, request: Parameters<typeof reachable>[0], baseURL: string | undefined) {
  test.setTimeout(420_000)
  test.skip(
    !(await reachable(request, baseURL ?? '')),
    `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
  )
  await page.goto('command')
  await ready(page)
  await expect(page.getByTestId('watch-row').first()).toBeVisible({ timeout: 120_000 })
}

const box = (page: Page, id: string) =>
  page.getByTestId(id).evaluate((e) => {
    const r = e.getBoundingClientRect()
    return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), bottom: Math.round(r.bottom) }
  })

test.describe('the terminal at 1440×731 (the owner\'s glass)', () => {
  test.use({ viewport: { width: 1440, height: 731 } })

  test('three panes across the glass; Best trade above the fold; stock on the rows and the chart', async ({ page, request, baseURL }) => {
    await openDesk(page, request, baseURL)
    await expect(page.getByTestId('desk-terminal')).toBeVisible()
    // nothing chosen yet: the list's first good fills the chart and the ticket
    await expect(page.getByTestId('best-trade')).toBeVisible({ timeout: 60_000 })
    await expect(page.getByTestId('sell-row').first()).toBeVisible({ timeout: 60_000 })

    const list = await box(page, 'desk-pane-list')
    const chart = await box(page, 'desk-pane-chart')
    const ticket = await box(page, 'desk-pane-ticket')
    expect(list.x + list.w, 'the list and the chart overlap').toBeLessThanOrEqual(chart.x + 1)
    expect(chart.x + chart.w, 'the chart and the ticket overlap').toBeLessThanOrEqual(ticket.x + 1)
    expect(ticket.x + ticket.w, 'the ticket does not reach the right edge').toBeGreaterThanOrEqual(1440 - 2)
    expect(list.x, 'the list does not start at the left edge').toBeLessThanOrEqual(2)
    expect(chart.w, 'the chart pane is not the widest').toBeGreaterThan(Math.max(list.w, ticket.w))

    const foldY = await page.evaluate(() => document.querySelector('nav')?.getBoundingClientRect().top ?? window.innerHeight)
    const best = await box(page, 'best-trade')
    expect(best.bottom, 'the Best trade card is not whole above the fold').toBeLessThanOrEqual(foldY)
    const plot = await box(page, 'price-chart')
    expect(plot.w, 'the chart is not big').toBeGreaterThan(560)
    expect(plot.bottom).toBeLessThanOrEqual(foldY)

    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)

    // STOCK: on the watchlist rows that carry a seller, on the ladder rows, and the chart's strip
    await expect(page.getByTestId('watch-row').locator('[data-testid="stock-gauge"]').first()).toBeVisible()
    await expect(page.getByTestId('sell-row').locator('[data-testid="stock-gauge"]').first()).toBeVisible()
    await expect(page.getByTestId('price-chart-stock')).toBeVisible({ timeout: 60_000 })
  })

  test('a press selects: the chart and the ticket change in place, nothing moves', async ({ page, request, baseURL }) => {
    await openDesk(page, request, baseURL)
    await expect(page.getByTestId('best-trade')).toBeVisible({ timeout: 60_000 })
    const rowsBefore = await page.evaluate(() =>
      [...document.querySelectorAll('[data-testid="watch-row"]')].slice(0, 10).map((e) => Math.round(e.getBoundingClientRect().top)),
    )
    const panes = async () => [await box(page, 'desk-pane-list'), await box(page, 'desk-pane-chart'), await box(page, 'desk-pane-ticket')]
    const before = await panes()
    const second = page.getByTestId('watch-row').nth(2)
    const code = await second.getAttribute('data-good')
    await second.click()
    await expect(second).toHaveAttribute('aria-pressed', 'true')
    await expect(page.getByTestId('sell-row').first()).toBeVisible({ timeout: 60_000 })
    await page.waitForTimeout(400)
    expect(await panes(), 'a press moved a pane').toEqual(before)
    const rowsAfter = await page.evaluate(() =>
      [...document.querySelectorAll('[data-testid="watch-row"]')].slice(0, 10).map((e) => Math.round(e.getBoundingClientRect().top)),
    )
    expect(rowsAfter, 'a press moved the list').toEqual(rowsBefore)
    expect(code).not.toBeNull()

    // A Plan stands in the ticket pane; closing it gives the ticket back, and no pane moved.
    const plan = page.getByTestId('desk-plan').first()
    if (await plan.count()) {
      await plan.click()
      await expect(page.getByTestId('plan-builder')).toBeVisible({ timeout: 30_000 })
      expect(await panes(), 'the plan builder moved a pane').toEqual(before)
      await page.getByTestId('plan-builder').getByTestId('tray-close').click()
      await expect(page.getByTestId('best-trade')).toBeVisible()
    }
  })
})

test.describe('the desk at 390×844', () => {
  test.use({ viewport: { width: 390, height: 844 } })

  test('no sideways scroll; the good page holds the chart, then the Best trade', async ({ page, request, baseURL }) => {
    await openDesk(page, request, baseURL)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    await page.getByTestId('watch-row').first().click()
    await expect(page.getByTestId('good-page')).toBeVisible()
    await expect(page.getByTestId('best-trade')).toBeVisible({ timeout: 60_000 })
    const chart = await box(page, 'good-chart')
    const best = await box(page, 'best-trade')
    expect(best.y, 'the Best trade card is not under the chart').toBeGreaterThan(chart.y)
    expect(best.x + best.w).toBeLessThanOrEqual(390)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
  })
})
